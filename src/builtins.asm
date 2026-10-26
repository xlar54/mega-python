;=======================================================================================
; Builtin functions. A native routine gets its arguments in argv (nargc of them, the
; last nkw being keyword values named by kwnames) and returns its result in A/X. They
; stay valid across Python code it runs (vm_call_nested saves and restores them, with
; npos); argc is for the calls it makes itself. The arguments are also on the value
; stack: argument i is at vsp + 2*(nargc-1-i) while vsp is the call's.
;=======================================================================================
ARG     .macro i
        lda argv+2*\i
        ldx argv+2*\i+1
        .endm
NARGS   .macro lo, hi
        ldx #\lo
        ldy #\hi
        jsr check_nargs
        .endm

; check_nargs - X..Y positional arguments, and no keywords unless the routine reads them
check_nargs:
        sec
        lda nargc
        sbc nkw
        sta npos
        cpx npos
        beq +
        bcs _bad
+       cpy npos
        bcc _bad
        rts
_bad:   jmp raise_args

; builtins_init - make the builtin objects (perm) and bind the global ones
builtins_init:
        lda #F_PERM
        sta al_perm
        lda #0
        sta t6
_loop:  lda #8
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_BUILTIN
        jsr alloc
        lda t6
        ldz #4
        sta [p0],z
        tax
        lda builtin_flags,x
        inz
        sta [p0],z
        lda p0
        sta builtin_refs_lo,x
        lda p0+1
        sta builtin_refs_hi,x
        lda builtin_name_lo,x
        sta t4
        lda builtin_name_hi,x
        sta t4+1
        lda t4
        ldx t4+1
        jsr sym_name
        ldz #6
        sta [p0],z
        inz
        txa
        sta [p0],z
        ldx t6
        lda builtin_flags,x
        and #BF_GLOBAL
        beq _next
        lda t4
        ldx t4+1
        jsr sym_val_addr
        ldz #0
        lda p0
        sta [fp1],z
        inz
        lda p0+1
        sta [fp1],z
_next:  inc t6
        lda t6
        cmp #NBUILTINS
        bcc _loop
        ; BaseException.__init__ is a builtin that stores the args (the classes are
        ; made before the builtins: xh_reset)
        ldx #EXC_BASE
        lda exc_cls_lo,x
        sta p0
        lda exc_cls_hi,x
        sta p0+1
        ldz #8
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        lda #<S_INIT
        ldx #>S_INIT
        jsr sym_name
        sta r1
        stx r1+1
        lda #B_INIT
        jsr builtin_obj
        sta r2
        stx r2+1
        jsr dict_set
        jsr clear_rregs
        lda #0
        sta al_perm
        jmp math_init

; builtin_obj - A = builtin id -> A/X
builtin_obj:
        tax
        lda builtin_refs_lo,x
        pha
        lda builtin_refs_hi,x
        tax
        pla
        rts

; builtin_method - r0 = object, r1 = name ref -> C clear, A/X = method if found
builtin_method:
        lda r0
        ldx r0+1
        jsr type_of
        ldx #<meth_list
        ldy #>meth_list
        cmp #T_LIST
        beq _search
        ldx #<meth_tuple
        ldy #>meth_tuple
        cmp #T_TUPLE
        beq _search
        ldx #<meth_str
        ldy #>meth_str
        cmp #T_STR
        beq _search
        ldx #<meth_dict
        ldy #>meth_dict
        cmp #T_DICT
        beq _search
        ldx #<meth_file
        ldy #>meth_file
        cmp #T_FILE
        beq _search
        ldx #<meth_set
        ldy #>meth_set
        cmp #T_SET
        beq _search
        ldx #<meth_frozenset
        ldy #>meth_frozenset
        cmp #T_FSET
        beq _search
        ldx #<meth_property
        ldy #>meth_property
        cmp #T_DESC
        beq _search
        ldx #<meth_generator
        ldy #>meth_generator
        cmp #T_GEN
        beq _search
        sec
        rts
_search:
        stx t6
        sty t6+1
_next:  ldy #1
        lda (t6),y
        cmp #$ff
        beq _miss
        tax
        dey
        lda (t6),y
        jsr sym_name
        cmp r1
        bne _skip
        cpx r1+1
        bne _skip
        ldy #2
        lda (t6),y
        jsr builtin_obj
        clc
        rts
_skip:  clc
        lda t6
        adc #4
        sta t6
        bcc _next
        inc t6+1
        bra _next
_miss:  sec
        rts

; kw_get - A/X = symbol: is it among the keyword arguments? -> C clear, A/X = value
kw_get:
        jsr sym_name
        sta t4
        stx t4+1
        lda kwnames+1
        beq _no
        sta p1+1
        lda kwnames
        sta p1
        ldx #0
-       cpx nkw
        bcs _no
        txa
        asl
        clc
        adc #6
        taz
        lda [p1],z
        cmp t4
        bne +
        inz
        lda [p1],z
        cmp t4+1
        beq _yes
+       inx
        bra -
_yes:   ; value: argv[npos + x]
        sec
        lda nargc
        sbc nkw
        stx t0
        clc
        adc t0
        asl
        tax
        lda argv,x
        pha
        lda argv+1,x
        tax
        pla
        clc
        rts
_no:    sec
        rts

; builtin_type_of_r2 - the builtin type object of r2 -> A/X (instances: their class)
builtin_type_of_r2:
        lda r2
        ldx r2+1
        jsr type_of
        tax
        lda type_builtin,x
        cmp #$ff
        bne +
        ldz #4                          ; instance: its class
        lda [p0],z
        tay
        inz
        lda [p0],z
        tax
        tya
        rts
+       jmp builtin_obj
type_builtin:
        .byte B_NONETYPE, B_INT, B_STR, B_LIST, B_TUPLE, B_DICT, B_NONETYPE, B_FUNCTION
        .byte B_FUNCTION, B_FUNCTION, B_TYPE, $ff, B_RANGE, B_OBJECT, B_FLOAT, B_NONETYPE
        .byte B_BOOL, B_OBJECT, B_OBJECT, B_TEXTIOWRAPPER, B_MODULE, B_PROPERTY
        .byte B_GENERATOR, B_SET, B_FROZENSET

; put_str - print string A/X
put_str:
        jsr str_info
        lda fp0
        sta fp2
        lda fp0+1
        sta fp2+1
        lda fp0+2
        sta fp2+2
        lda #0
        sta fp2+3
        lda str_len
        sta t6
        lda str_len+1
        sta t6+1
        jmp put_far

;---------------------------------------------------------------------------------------
; print(*args, sep=' ', end='\n')
;---------------------------------------------------------------------------------------
bi_print:
        sec
        lda nargc
        sbc nkw
        sta npos
        ; sep and end (None means the default)
        lda #<S_SEP
        ldx #>S_SEP
        jsr kw_get
        bcc +
        lda #0
        tax
+       jsr none_to_null
        pha
        phx
        lda #<S_END
        ldx #>S_END
        jsr kw_get
        bcc +
        lda #0
        tax
+       jsr none_to_null
        sta t3
        stx t3+1
        plx
        pla
        sta t2
        stx t2+1
        ; &arg0 = vsp + 2*(argc-1)
        lda nargc
        asl
        sec
        sbc #2
        clc
        adc vsp
        sta t1
        lda vsp+1
        adc #0
        sta t1+1
        ; keep sep, end, &arg, count on the CPU stack across str() calls
        lda #0
        sta t0                          ; index
_loop:  lda t0
        cmp npos
        bcs _end
        lda t0
        beq _nosep
        lda t2+1
        bne +
        lda #' '
        jsr putc
        bra _nosep
+       lda t2
        ldx t2+1
        jsr put_str
_nosep: ldx #0                          ; t0-t3 and npos survive str() calls
-       lda t0,x
        pha
        inx
        cpx #8
        bne -
        lda npos
        pha
        lda sbp
        pha
        lda sbp+1
        pha
        ; argument t0 is at t1 - 2*t0
        lda t0
        asl
        sta t4
        sec
        lda t1
        sbc t4
        sta t4
        lda t1+1
        sbc #0
        sta t4+1
        ldy #1
        lda (t4),y
        tax
        dey
        lda (t4),y
        jsr obj_str
        plx
        pla
        jsr sb_flush
        pla
        sta npos
        ldx #7
-       pla
        sta t0,x
        dex
        bpl -
        inc t0
        bra _loop
_end:   lda t3+1
        bne +
        lda #10
        jsr putc
        bra _ret
+       lda t3
        ldx t3+1
        jsr put_str
_ret:   lda #R_NONE
        ldx #0
        rts

; None -> 0 (NULL); anything else unchanged
none_to_null:
        cpx #0
        bne +
        cmp #R_NONE
        bne +
        lda #0
+       rts

;---------------------------------------------------------------------------------------
bi_len:
        #NARGS 1, 1
        #ARG 0
        jsr obj_len
        jmp int_new

; obj_len - A/X -> acc = len
obj_len:
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq _four
        cmp #T_LIST
        beq _four
        cmp #T_TUPLE
        beq _four
        cmp #T_DICT
        beq _four
        cmp #T_SET                      ; (and T_FSET)
        bcs _four
        cmp #T_RANGE
        beq _range
        cmp #T_INST
        bne _bad
        lda #S_LEN
        jsr inst_unary
        bcs _bad
        jsr int_val
        rts
_bad:   #RAISE EXC_TYPE, "object has no len()"
_four:  ldz #4
        lda [p0],z
        sta acc
        inz
        lda [p0],z
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        rts
_range: jsr range_len
        lda t5
        sta acc
        lda t5+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        rts

bi_range:
        #NARGS 1, 3
        ; start, stop, step
        lda #1
        sta acc3
        lda #0
        sta acc3+1
        sta acc3+2
        sta acc3+3
        lda npos
        cmp #1
        bne +
        #ARG 0
        jsr need_int
        ldq acc
        stq acc2
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
        jmp range_new
+       cmp #3
        bne +
        #ARG 2
        jsr need_int
        lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        bne _st
        #RAISE EXC_VALUE, "range() arg 3 must not be zero"
_st:    ldq acc
        stq acc3
+       #ARG 1
        jsr need_int
        ldq acc
        stq acc2
        #ARG 0
        jsr need_int
        jmp range_new

; need_int - A/X -> acc, TypeError if not an int
need_int:
        jsr int_val
        bcc +
        jmp raise_need_int
+       rts

bi_input:
        #NARGS 0, 1
        lda npos
        beq +
        lda sbp
        pha
        lda sbp+1
        pha
        #ARG 0
        jsr obj_str
        plx
        pla
        jsr sb_flush
+       lda #0
        sta rl_len
        jsr rl_read
        bcc +
        #RAISE EXC_KEYBOARD, ""
+       lda #<LINEBUF
        sta fp2
        lda #>LINEBUF
        sta fp2+1
        lda #0
        sta fp2+2
        sta fp2+3
        sta str_len+1
        lda rl_len
        sta str_len
        jmp str_from_far

bi_int:
        #NARGS 0, 2
        lda npos
        bne +
        lda #1                          ; int() = 0
        ldx #0
        rts
+       #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq _str
        lda npos
        cmp #2
        bne +
        #RAISE EXC_TYPE, "int() can't convert non-string with explicit base"
+       lda r2
        ldx r2+1
        jsr is_float
        bcc +
        lda r2
        ldx r2+1
        jsr float_load
        jsr f_unpack
        jsr f_trunc
        jmp f_int_result
+       lda r2
        ldx r2+1
        jsr int_val
        bcs _bad
        jmp int_new
_bad:   #RAISE EXC_TYPE, "int() argument must be a string or a number"
_str:   lda #10
        sta t6
        lda npos
        cmp #2
        bne +
        #ARG 1
        jsr need_int
        lda acc
        sta t6
+       lda r2
        ldx r2+1
        jsr parse_int
        bcs +
        jmp int_new
+       jsr sb_mark_t5
        #SBPRINT "invalid literal for int(): "
        lda r2
        ldx r2+1
        jsr obj_repr
        lda #EXC_VALUE
        jmp raise_sb

; parse_int - string A/X, base t6 (0 = from the prefix) -> acc, C set if invalid
parse_int:
        jsr str_info
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
        sta t5                          ; negative
        sta t5+1                        ; digits seen
        jsr _skipws
        jsr _peek
        cmp #'-'
        bne +
        inc t5
        jsr _adv
        bra ++
+       cmp #'+'
        bne +
        jsr _adv
+       ; prefix
        lda t6
        beq _pfx
        cmp #16
        beq _pfx
        cmp #8
        beq _pfx
        cmp #2
        bne _digits
_pfx:   jsr _peek
        cmp #'0'
        bne _nopfx
        ldz #1
        lda str_len+1
        bne +
        lda str_len
        cmp #2
        bcc _nopfx
+       lda [fp0],z
        ora #$20
        ldx #16
        cmp #'x'
        beq _setb
        ldx #8
        cmp #'o'
        beq _setb
        ldx #2
        cmp #'b'
        bne _nopfx
_setb:  lda t6
        beq +
        cpx t6
        bne _nopfx
+       stx t6
        jsr _adv
        jsr _adv
_nopfx: lda t6
        bne _digits
        lda #10
        sta t6
_digits:
        jsr _peek
        bcs _end
        cmp #'_'
        beq _skip
        jsr digit_value
        bcs _end
        cmp t6
        bcs _end
        sta t2
        ldq acc
        stq MULTINA
        lda t6
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda MULTOUT+4
        ora MULTOUT+5
        ora MULTOUT+6
        ora MULTOUT+7
        bne _bad
        clc
        lda MULTOUT
        adc t2
        sta acc
        lda MULTOUT+1
        adc #0
        sta acc+1
        lda MULTOUT+2
        adc #0
        sta acc+2
        lda MULTOUT+3
        adc #0
        sta acc+3
        bmi _bad
        inc t5+1
_skip:  jsr _adv
        bra _digits
_end:   jsr _skipws
        lda str_len
        ora str_len+1
        bne _bad
        lda t5+1
        beq _bad
        lda t5
        beq +
        jsr acc_neg
+       clc
        rts
_bad:   sec
        rts
_peek:  lda str_len
        ora str_len+1
        bne +
        sec
        rts
+       ldz #0
        lda [fp0],z
        clc
        rts
_adv:   inw fp0
        dew str_len
        rts
_skipws:
        jsr _peek
        bcs +
        cmp #33
        bcs +
        jsr _adv
        bra _skipws
+       rts

bi_str:
        #NARGS 0, 1
        lda npos
        bne +
        lda #0
        sta str_len
        sta str_len+1
        jmp str_alloc
+       lda sbp
        pha
        lda sbp+1
        pha
        #ARG 0
        jsr obj_str
        plx
        pla
        jmp sb_take

bi_format:
        #NARGS 1, 2
        lda npos
        cmp #2
        beq +
        jmp bi_str
+       lda sbp
        pha
        lda sbp+1
        pha
        #ARG 1
        sta r3
        stx r3+1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       #ARG 0
        sta r2
        stx r2+1
        jsr format_spec
        plx
        pla
        jmp sb_take

bi_repr:
        #NARGS 1, 1
        lda sbp
        pha
        lda sbp+1
        pha
        #ARG 0
        jsr obj_repr
        plx
        pla
        jmp sb_take

bi_abs:
        #NARGS 1, 1
        #ARG 0
        jsr is_float
        bcc +
        #ARG 0
        jmp float_abs
+       #ARG 0
        jsr need_int
        bit acc+3
        bpl +
        jsr acc_neg
        bit acc+3
        bpl +
        jmp int_overflow
+       jmp int_new

; min/max(iterable) or min/max(a, b, ...)
bi_min:
        lda #$ff
        bra minmax
bi_max:
        lda #1
minmax:
        sta mm_dir                      ; the obj_cmp result that replaces the best (not in
        sec                             ; a t register: tuple_new may collect garbage)
        lda nargc
        sbc nkw
        sta npos
        bne +
        jmp raise_args
+       ; key= : compare key(item) (the keys are computed first)
        lda #<S_KEY
        ldx #>S_KEY
        jsr kw_get
        bcc +
        lda #0
        tax
+       sta mm_key
        stx mm_key+1
        lda npos
        cmp #1
        beq _iter
        ; several arguments: make a tuple of them
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        ldx #0
        ldz #6
-       lda argv,x
        sta [p0],z
        inz
        inx
        txa
        lsr
        cmp npos
        bcc -
        lda p0
        ldx p0+1
        bra _go
_iter:  #ARG 0
_go:    ldy mm_key                      ; (the key function stays on the CPU stack)
        phy
        ldy mm_key+1
        phy
        ldy mm_dir
        phy
        jsr list_from_iterable
        #PUSH                           ; [list]
        jsr seq_len
        lda t0
        ora t0+1
        bne +
        #RAISE EXC_VALUE, "min()/max() arg is an empty sequence"
+       pla
        sta t6+1
        pla
        sta mm_key+1
        pla
        sta mm_key
        lda t6+1
        pha
        lda mm_key+1
        bne _keys
        #PEEK 0                         ; no key: the items are the keys
        #PUSH                           ; [list][keys]
        bra _find
_keys:  lda mm_key                      ; [list][keyfunc][keys]
        ldx mm_key+1
        #PUSH
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH
        lda #0
        sta t2
        sta t2+1
-       #PEEK 2
        jsr seq_len
        lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq ++
+       lda t2
        pha
        lda t2+1
        pha
        #PEEK 1                         ; key(item)
        #PUSH
        #PEEK 3
        jsr seq_get_t2
        #PUSH
        lda #1
        sta argc
        jsr vm_call_nested
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        jsr clear_rregs
        pla
        sta t2+1
        pla
        sta t2
        inw t2
        bra -
+       #POP                            ; [list][keys]
        #POKE 0
_find:  ; t2 = index, t4 = the best index, t5 = length
        pla
        sta t6+1
        #PEEK 0
        jsr seq_len
        lda t0
        sta t5
        lda t0+1
        sta t5+1
        lda #0
        sta t4
        sta t4+1
        lda #1
        sta t2
        lda #0
        sta t2+1
_loop:  lda t2
        cmp t5
        bne +
        lda t2+1
        cmp t5+1
        beq _done
+       ldx #0                          ; keep t2, t4, t5, want across the compare
-       lda t2,x
        pha
        inx
        cpx #2
        bne -
        lda t4
        pha
        lda t4+1
        pha
        lda t5
        pha
        lda t5+1
        pha
        lda t6+1
        pha
        #PEEK 0
        jsr seq_get_t2                  ; keys[i]
        sta r2
        stx r2+1
        lda t4
        sta t2
        lda t4+1
        sta t2+1
        #PEEK 0
        jsr seq_get_t2                  ; keys[best]
        sta r3
        stx r3+1
        jsr obj_cmp
        sta t7
        pla
        sta t6+1
        pla
        sta t5+1
        pla
        sta t5
        pla
        sta t4+1
        pla
        sta t4
        pla
        sta t2+1
        pla
        sta t2
        lda t7
        cmp t6+1
        bne +
        lda t2
        sta t4
        lda t2+1
        sta t4+1
+       jsr clear_rregs
        inw t2
        bra _loop
_done:  #DROP 1                         ; [list]
        lda t4
        sta t2
        lda t4+1
        sta t2+1
        #POP
        jmp seq_get_t2
mm_key:         .word 0
mm_dir:         .byte 0

bi_sum:
        #NARGS 1, 2
        lda #1                          ; start = 0
        ldx #0
        ldy npos
        cpy #2
        bne +
        #ARG 1
+       #PUSH                           ; [total]
        #ARG 0
        jsr get_iter                    ; (lazily, as CPython: sum(range(10**6)) fits)
        #PUSH                           ; [total, iterator]
_loop:  #PEEK 0
        jsr iter_next
        bcs _done
        sta r3
        stx r3+1
        #PEEK 1
        sta r2
        stx r2+1
        lda #BOP_ADD
        sta bop
        jsr binop
        #POKE 1
        jsr clear_rregs
        bra _loop
_done:  #DROP 1
        #POP
        rts

bi_chr:
        #NARGS 1, 1
        #ARG 0
        jsr need_int
        lda acc+1
        ora acc+2
        ora acc+3
        bne _bad
        lda acc
        bmi _bad
        jmp char_str
_bad:   #RAISE EXC_VALUE, "chr() arg not in range(128)"

bi_ord:
        #NARGS 1, 1
        #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        bne _bad
        lda r2
        ldx r2+1
        jsr str_info
        lda str_len
        cmp #1
        bne _bad
        lda str_len+1
        bne _bad
        ldz #0
        lda [fp0],z
        and #$7f
        jmp int_small
_bad:   #RAISE EXC_TYPE, "ord() expected a character"

bi_list:
        #NARGS 0, 1
        lda npos
        bne +
        lda #0
        sta nitems
        sta nitems+1
        jmp list_new
+       #ARG 0
        jmp list_from_iterable

bi_tuple:
        #NARGS 0, 1
        lda npos
        bne +
        lda #0
        sta nitems
        sta nitems+1
        jmp tuple_new
+       #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_TUPLE
        bne +
        lda r2
        ldx r2+1
        rts
+       lda r2
        ldx r2+1
        jsr list_from_iterable
        jmp tuple_from_list

bi_dict:
        #NARGS 0, 1
        jsr dict_new
        #PUSH
        lda npos
        beq _kw
        #ARG 0
        sta r2
        stx r2+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_update_from
_kw:    ; keyword arguments become string keys
        ldx #0
-       cpx nkw
        bcs _done
        phx
        lda kwnames
        sta p1
        lda kwnames+1
        sta p1+1
        txa
        asl
        clc
        adc #6
        taz
        lda [p1],z
        sta r1
        inz
        lda [p1],z
        sta r1+1
        txa
        clc
        adc npos
        asl
        tay
        lda argv,y
        sta r2
        lda argv+1,y
        sta r2+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_set
        plx
        inx
        bra -
_done:  #POP
        rts

; dict_update_from - r0 = dict, r2 = dict or iterable of pairs
dict_update_from:
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_DICT
        bne _pairs
        lda r2
        ldx r2+1
        jsr seq_len
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _done
+       lda r2
        ldx r2+1
        sta p0
        stx p0+1
        lda t2
        asl
        sta t0
        lda t2+1
        rol
        sta t0+1
        jsr list_item_ptr
        lda r2
        pha
        lda r2+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        ldz #0
        lda [p1],z
        sta r1
        inz
        lda [p1],z
        sta r1+1
        inz
        lda [p1],z
        sta r2
        inz
        lda [p1],z
        sta r2+1
        jsr dict_set
        pla
        sta t2+1
        pla
        sta t2
        pla
        sta r2+1
        pla
        sta r2
        lda r2
        ldx r2+1
        jsr seq_len
        inw t2
        bra -
_done:  rts
_pairs: lda r0
        ldx r0+1
        #PUSH
        lda r2
        ldx r2+1
        jsr list_from_iterable
        #PUSH
        lda #0
        sta t2
        sta t2+1
_loop:  #PEEK 0
        jsr seq_len
        lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _end
+       #PEEK 0
        jsr seq_get_t2
        sta r2
        stx r2+1
        jsr seq_len                     ; each pair must have two items
        lda t0
        cmp #2
        bne _bad
        lda r2
        ldx r2+1
        sta p0
        stx p0+1
        lda #0
        sta t0
        sta t0+1
        jsr seq_get
        sta r1
        stx r1+1
        lda #1
        sta t0
        jsr seq_get
        sta r2
        stx r2+1
        #PEEK 1
        sta r0
        stx r0+1
        lda t2
        pha
        lda t2+1
        pha
        jsr dict_set
        pla
        sta t2+1
        pla
        sta t2
        inw t2
        bra _loop
_end:   #DROP 2
        rts
_bad:   #RAISE EXC_VALUE, "dictionary update sequence element has wrong length"

bi_bool:
        #NARGS 0, 1
        lda npos
        bne +
        lda #R_FALSE
        ldx #0
        rts
+       #ARG 0
        jsr obj_truth
        jmp bool_from_a

bi_type:
        #NARGS 1, 1
        #ARG 0
        sta r2
        stx r2+1
        jmp builtin_type_of_r2

bi_isinstance:
        #NARGS 2, 2
        #ARG 0
        sta r2
        stx r2+1
        #ARG 1
        sta r3
        stx r3+1
        jsr isinstance_r2_r3
        lda #0
        rol
        jmp bool_from_a

bi_hex:
        lda #16
        bra radix
bi_oct:
        lda #8
        bra radix
bi_bin:
        lda #2
radix:  sta t6
        #NARGS 1, 1
        #ARG 0
        jsr need_int
        lda sbp
        pha
        lda sbp+1
        pha
        bit acc+3
        bpl +
        lda #'-'
        jsr sb_putc
        jsr acc_neg
+       lda #'0'
        jsr sb_putc
        ldx t6
        lda #'x'
        cpx #16
        beq +
        lda #'o'
        cpx #8
        beq +
        lda #'b'
+       jsr sb_putc
        jsr sb_radix
        plx
        pla
        jmp sb_take

; sb_radix - append unsigned acc in base t6 (2, 8, 16; lower-case digits)
sb_radix:
        lda #0
        sta t5
_dig:   lda acc
        ldx t6
        cpx #16
        bne +
        and #15
        bra _put
+       cpx #8
        bne +
        and #7
        bra _put
+       and #1
_put:   tay
        lda hex_digits,y
        pha
        inc t5
        ; shift right by log2(base)
        ldx t6
-       lsr acc+3
        ror acc+2
        ror acc+1
        ror acc
        txa
        lsr
        tax
        cpx #1
        bne -
        lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        bne _dig
-       pla
        jsr sb_putc
        dec t5
        bne -
        rts
hex_digits:     .text "0123456789abcdef"

bi_divmod:
        #NARGS 2, 2
        #ARG 0
        jsr is_float
        bcs +
        #ARG 1
        jsr is_float
        bcc ++
+       jmp float_divmod
+       #ARG 1
        jsr need_int
        ldq acc
        stq acc2
        #ARG 0
        jsr need_int
        jsr acc_divmod
        jsr int_new
        sta r2
        stx r2+1
        ldq acc3
        stq acc
        jsr int_new
        sta r3
        stx r3+1
        jmp tuple2

bi_pow:
        #NARGS 2, 3
        lda npos
        cmp #3
        beq _mod
        #ARG 0
        sta r2
        stx r2+1
        #ARG 1
        sta r3
        stx r3+1
        lda #BOP_POW
        sta bop
        jmp binop
_mod:   ; (base ** exp) % mod by square-and-multiply, reducing each step
        #ARG 2
        jsr need_int
        ldq acc
        stq pm_mod
        #ARG 1
        jsr need_int
        ldq acc
        stq pm_exp
        bit acc+3
        bpl +
        #RAISE EXC_VALUE, "pow() negative exponent with a modulus"
+       #ARG 0
        jsr need_int
        ldq pm_mod
        stq acc2
        jsr acc_divmod
        ldq acc3
        stq pm_base
        lda #1
        sta pm_res
        lda #0
        sta pm_res+1
        sta pm_res+2
        sta pm_res+3
_loop:  lda pm_exp
        ora pm_exp+1
        ora pm_exp+2
        ora pm_exp+3
        beq _done
        lda pm_exp
        and #1
        beq +
        ldq pm_res
        stq acc
        ldq pm_base
        stq acc2
        jsr _mulmod
        ldq acc
        stq pm_res
+       lsr pm_exp+3
        ror pm_exp+2
        ror pm_exp+1
        ror pm_exp
        ldq pm_base
        stq acc
        stq acc2
        jsr _mulmod
        ldq acc
        stq pm_base
        bra _loop
_done:  ldq pm_res
        stq acc
        ldq pm_mod
        stq acc2
        jsr acc_divmod
        ldq acc3
        stq acc
        jmp int_new
_mulmod:
        jsr acc_mul
        bcc +
        jmp int_overflow
+       ldq pm_mod
        stq acc2
        jsr acc_divmod
        ldq acc3
        stq acc
        rts
pm_mod:         .dword 0
pm_exp:         .dword 0
pm_base:        .dword 0
pm_res:         .dword 0

bi_iter:
        #NARGS 1, 1
        #ARG 0
        jmp get_iter

bi_next:
        #NARGS 1, 2
        lda npos
        pha
        #ARG 1
        pha
        phx
        #ARG 0
        jsr type_of
        cmp #T_INST
        bne +
        #ARG 0                          ; an instance: its __next__
        sta r0
        stx r0+1
        lda #IT_INST
        jsr iter_alloc
        bra _next
+       cmp #T_ITER
        beq +
        cmp #T_GEN
        beq +
        #RAISE EXC_TYPE, "object is not an iterator"
+       #ARG 0
_next:  jsr iter_next
        bcs _end
        ply
        ply
        ply
        rts
_end:   sta nx_val                      ; (a generator: what it returned)
        stx nx_val+1
        plx
        pla
        ply
        cpy #2
        bne +
        rts                             ; the default
+       #ARG 0
        jsr type_of
        cmp #T_GEN
        bne +
        lda nx_val                      ; StopIteration(value)
        ldx nx_val+1
        jmp gen_stop
+       #RAISE EXC_STOPITER, ""
nx_val:         .word 0

bi_reversed:
        #NARGS 1, 1
        #ARG 0
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_LIST
        beq _ok
        cmp #T_TUPLE
        beq _ok
        lda r0
        ldx r0+1
        jsr list_from_iterable
        sta r0
        stx r0+1
_ok:    lda r0
        ldx r0+1
        jsr seq_len
        lda t0
        pha
        lda t0+1
        pha
        lda #IT_REV
        jsr iter_alloc
        pla
        ldz #9
        sta [p0],z
        pla
        dez
        sta [p0],z
        lda #0
        sta r0
        sta r0+1
        lda p0
        ldx p0+1
        rts

bi_any:
        lda #1
        bra anyall
bi_all:
        lda #0
anyall: sta t6                          ; the truth value that decides
        #NARGS 1, 1
        lda t6
        pha
        #ARG 0
        jsr get_iter
        #PUSH
_loop:  #PEEK 0
        jsr iter_next
        bcs _end
        jsr obj_truth
        sta t0
        pla
        pha
        cmp t0
        beq _hit
        bra _loop
_hit:   #DROP 1
        pla
        jmp bool_from_a
_end:   #DROP 1
        pla
        eor #1
        jmp bool_from_a

; hash(): ints, floats and strings as CPython would (-1 -> -2); an instance's
; __hash__(); tuples, frozensets and the rest by obj_hash (dicthash.asm). Unhashable
; values (lists, dicts, sets, instances with __eq__ but no __hash__) raise TypeError.
bi_hash:
        #NARGS 1, 1
        #ARG 0
        sta r2
        stx r2+1
        jsr int_val
        bcs +
        lda acc                         ; -1 hashes as -2
        and acc+1
        and acc+2
        and acc+3
        cmp #$ff
        bne _int
        dec acc
        bra _int
+
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_FLOAT
        bne +
        lda r2
        ldx r2+1
        jmp float_hash
+       cmp #T_STR
        bne _id
        lda r2
        ldx r2+1
        jsr str_info
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
_loop:  lda str_len                     ; acc = acc * 31 + c
        ora str_len+1
        beq _end
        ldq acc
        stq MULTINA
        lda #31
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        ldq MULTOUT
        stq acc
        ldz #0
        lda [fp0],z
        clc
        adc acc
        sta acc
        bcc _nc
        inw acc+1
_nc:    inw fp0
        dew str_len
        bra _loop
_end:   lda acc+3
        and #$3f
        sta acc+3
_int:   jmp int_new
_id:    lda r2
        ldx r2+1
        jsr need_hashable
        jsr type_of
        cmp #T_INST
        bne _obj
        lda #S_HASH
        jsr inst_unary                  ; (r2 = the instance)
        bcs _obj
        rts
_obj:   lda r2
        ldx r2+1
        jsr obj_hash
        sta acc                         ; (16 bits, sign-extended)
        stx acc+1
        txa
        asl a
        lda #0
        sbc #0
        eor #$ff
        sta acc+2
        sta acc+3
        jmp int_new

bi_id:
        #NARGS 1, 1
        #ARG 0
bi_id_ax:
        sta acc
        stx acc+1
        lda #0
        sta acc+2
        sta acc+3
        jmp int_new

bi_callable:
        #NARGS 1, 1
        #ARG 0
        jsr type_of
        cmp #T_FUNC
        beq _y
        cmp #T_BUILTIN
        beq _y
        cmp #T_CLASS
        beq _y
        cmp #T_BOUND
        beq _y
        lda #0
        jmp bool_from_a
_y:     lda #1
        jmp bool_from_a

; name string argument 1 -> r1 = interned name (C set if no such name exists at all)
attr_name_arg:
        #ARG 1
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       lda r2
        ldx r2+1
        jsr str_info
        lda fp0
        sta fp2
        lda fp0+1
        sta fp2+1
        lda fp0+2
        sta fp2+2
        lda #0
        sta fp2+3
        jsr intern
        lda int_ref
        sta r1
        lda int_ref+1
        sta r1+1
        rts

bi_getattr:
        #NARGS 2, 3
        jsr attr_name_arg
        #ARG 0
        sta r0
        stx r0+1
        lda npos
        cmp #3
        beq _def
        jmp getattr
_def:   ; with a default: catch AttributeError by checking first
        jsr has_attr
        bcc +
        #ARG 2
        rts
+       #ARG 0
        sta r0
        stx r0+1
        jmp getattr

bi_hasattr:
        #NARGS 2, 2
        jsr attr_name_arg
        #ARG 0
        sta r0
        stx r0+1
        jsr has_attr
        lda #0
        rol
        eor #1
        jmp bool_from_a

; has_attr - r0 = object, r1 = name -> C clear if it has it
has_attr:
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_INST
        bne _other
        ldz #6
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        ldz #4
        lda [p0],z
        sta r2
        inz
        lda [p0],z
        sta r2+1
        lda t0+1
        beq _cls
        lda r0
        pha
        lda r0+1
        pha
        lda t0
        sta r0
        lda t0+1
        sta r0+1
        jsr dict_find
        pla
        sta r0+1
        pla
        sta r0
        bcc _yes
_cls:   jsr class_lookup
        rts
_other: cmp #T_CLASS
        bne _bm
        lda r0
        sta r2
        lda r0+1
        sta r2+1
        jmp class_lookup
_bm:    jmp builtin_method
_yes:   clc
        rts

bi_setattr:
        #NARGS 3, 3
        jsr attr_name_arg
        #ARG 0
        sta r0
        stx r0+1
        #ARG 2
        sta r2
        stx r2+1
        jsr setattr
        lda #R_NONE
        ldx #0
        rts

; map(f, *iterables) and filter(f, iterable): lazy iterators, as in Python 3. IT_MAP /
; IT_FILTER (seq.asm): +6 a tuple (f, the items' iterator: zip's for several
; iterables), +8 1 = call f(x), 2 = f(*x)
bi_map:         #TAILCALL TAIL_X, xb_map         ; (args.asm)
bi_filter:      #TAILCALL TAIL_X, xb_filter

; it_mapfilter - (iter_next, seq.asm) p2 = a map / filter iterator -> C clear and A/X =
; its next item, or C set
it_mapfilter:
        ldz #4                          ; CPU: [kind][style]
        lda [p2],z
        pha
        ldz #8
        lda [p2],z
        pha
        ldz #7
        lda [p2],z
        tax
        dez
        lda [p2],z
        #PUSH                           ; [(f, it)]
_next:  #PEEK 0                         ; x = next(it)
        sta p3
        stx p3+1
        ldz #9
        lda [p3],z
        tax
        dez
        lda [p3],z
        jsr iter_next
        bcs _end
        #PUSH                           ; [(f, it)][x]
        #PEEK 1
        sta p3
        stx p3+1
        ldz #7                          ; f
        lda [p3],z
        tax
        dez
        lda [p3],z
        cpx #0
        bne _call
        cmp #R_NONE
        bne _call
        #PEEK 0                         ; filter(None, ...): x is the test
        bra _test
_call:  #PUSH                           ; [(f, it)][x][f]
        pla                             ; the call style
        pha
        cmp #1
        beq _x
        #PEEK 1                         ; f(*x): x's items
        sta p3
        stx p3+1
        ldz #4
        lda [p3],z
        sta argc
        sta t0
        ldz #6
_items: lda t0
        beq _go
        lda [p3],z
        pha
        inz
        lda [p3],z
        tax
        pla
        inz
        phz
        #PUSH
        plz
        dec t0
        bra _items
_x:     sta argc                        ; f(x)
        #PEEK 1
        #PUSH
_go:    jsr vm_call_nested              ; -> A/X; the stack is back at [(f, it)][x]
_test:  sta t0
        stx t0+1
        pla
        tay
        pla                             ; the kind
        pha
        phy
        cmp #IT_MAP
        beq _ret                        ; map: f's result
        lda t0
        ldx t0+1
        jsr obj_truth
        beq _skip
        #PEEK 0                         ; filter: x
        sta t0
        stx t0+1
_ret:   #DROP 2
        pla
        pla
        lda t0
        ldx t0+1
        clc
        rts
_skip:  #DROP 1
        bra _next
_end:   #DROP 1
        pla
        pla
        lda #0
        tax
        sec
        rts

bi_round:
        #NARGS 1, 2
        #ARG 0
        jsr is_float
        bcc +
        jmp float_round
+       #ARG 0
        jsr need_int
        jmp int_new

bi_object:
bi_gentype:
bi_moduletype:
bi_filetype:
bi_nonetype:
bi_functype:
        #RAISE EXC_TYPE, "cannot create instances of this type"

bi_super:
        #NARGS 2, 2
        #ARG 0
        sta r2
        stx r2+1
        #ARG 1
        sta r3
        stx r3+1
        jmp make_super

bi_exit:
        lda #EXC_SYSEXIT
        jsr exc_new_empty
        jmp raise_obj

; BaseException.__init__(self, *args): self.args = args
bi_exc_init:
        lda nargc
        beq _bad
        sec
        sbc #1
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        ldx #2
        ldz #6
-       txa
        lsr
        cmp nargc
        bcs +
        lda argv,x
        sta [p0],z
        inz
        lda argv+1,x
        sta [p0],z
        inz
        inx
        inx
        bra -
+       lda p0
        sta r2
        lda p0+1
        sta r2+1
        #ARG 0
        sta r0
        stx r0+1
        lda #<S_ARGS
        ldx #>S_ARGS
        jsr sym_name
        sta r1
        stx r1+1
        jsr setattr
        lda #R_NONE
        ldx #0
        rts
_bad:   jmp raise_args

;---------------------------------------------------------------------------------------
; machine access
;---------------------------------------------------------------------------------------
; peek(addr) - addr is a 28-bit address
bi_peek:
        #NARGS 1, 1
        #ARG 0
        jsr need_int
        jsr peek_addr
        bne +
        lda (fp0),y                     ; bank 0 as the CPU sees it: I/O at $D000
        bra ++
+       lda [fp0],z
+       sta acc
        lda #0
        sta acc+1
        sta acc+2
        sta acc+3
        jmp int_new

; peek_addr - fp0 = the address in acc; Z set if it is in bank 0 (Y = Z = 0)
peek_addr:
        ldq acc
        stq fp0
        ldy #0
        ldz #0
        lda acc+2
        ora acc+3
        rts

bi_poke:
        #NARGS 2, 2
        #ARG 1
        jsr need_int
        lda acc
        pha
        #ARG 0
        jsr need_int
        jsr peek_addr
        bne +
        pla
        sta (fp0),y
        bra ++
+       pla
        sta [fp0],z
+       lda #R_NONE
        ldx #0
        rts

; mem() - print free heap memory
bi_mem: #TAILCALL TAIL_H, xh_mem

; heap_free -> acc = bytes in the free list plus the untouched top
heap_free:
        sec
        lda #<HEAP_LIMIT
        sbc heap_top
        sta acc
        lda #>HEAP_LIMIT
        sbc heap_top+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        lda free_list
        sta t0
        lda free_list+1
        sta t0+1
-       lda t0+1
        beq +
        sta p1+1
        lda t0
        sta p1
        ldz #2
        clc
        lda [p1],z
        adc acc
        sta acc
        inz
        lda [p1],z
        adc acc+1
        sta acc+1
        lda acc+2
        adc #0
        sta acc+2
        ldz #4
        lda [p1],z
        sta t0
        inz
        lda [p1],z
        sta t0+1
        bra -
+       rts

bi_gc:
        jsr gc_collect
        lda #R_NONE
        ldx #0
        rts

bi_cls:
        jsr scr_text
        jsr scr_clear
        lda #R_NONE
        ldx #0
        rts

bi_help: #TAILCALL TAIL_H, xh_help

;---------------------------------------------------------------------------------------
; environment requests: handled by the REPL loop outside the VM
;---------------------------------------------------------------------------------------
bi_run:
        lda #REQ_RUN
        jmp repl_request
bi_edit:
        lda #REQ_EDIT
        jmp repl_request
bi_new:
        lda #REQ_NEW
        jmp repl_request
bi_files:
        lda #REQ_FILES
        jmp repl_request
bi_load:
        lda #REQ_LOAD
        bra file_request
bi_save:
        lda #REQ_SAVE
file_request:
        pha
        #NARGS 1, 1
        #ARG 0
        jsr set_filename
        pla
        jmp repl_request

; set_filename - string A/X -> FNAMEBUF = name + ".py" (PETSCII-ish: upper/lower swap)
set_filename:
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       lda r2
        ldx r2+1
        jsr str_info
        lda str_len+1
        bne _long
        lda str_len
        beq _long
        cmp #13
        bcs _long
        ldz #0
        ldy #0
-       cpz str_len
        bcs +
        lda [fp0],z
        sta FNAMEBUF,y
        iny
        inz
        bra -
+       ; append .py unless it is already there
        cpy #3
        bcc _add
        lda FNAMEBUF-3,y
        cmp #'.'
        bne _add
        lda FNAMEBUF-2,y
        ora #$20
        cmp #'p'
        bne _add
        lda FNAMEBUF-1,y
        ora #$20
        cmp #'y'
        beq _end
_add:   lda #'.'
        sta FNAMEBUF,y
        iny
        lda #'p'
        sta FNAMEBUF,y
        iny
        lda #'y'
        sta FNAMEBUF,y
        iny
_end:   sty fname_len
        rts
_long:  #RAISE EXC_VALUE, "file name must be 1-12 characters"

;---------------------------------------------------------------------------------------
; enumerate(iterable, start=0) and zip(*iterables): lazy iterators
;---------------------------------------------------------------------------------------
bi_enumerate:
        #NARGS 1, 2
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
        lda npos
        cmp #2
        bne +
        #ARG 1
        jsr need_int
+       lda acc                         ; the counter is 16-bit
        pha
        lda acc+1
        pha
        #ARG 0
        jsr get_iter
        sta r0
        stx r0+1
        lda #IT_ENUM
        jsr iter_alloc
        ldz #9
        pla
        sta [p0],z
        dez
        pla
        sta [p0],z
        lda #0
        sta r0
        sta r0+1
        lda p0
        ldx p0+1
        rts

bi_zip:
        lda nargc
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        #PUSH                           ; the tuple of iterators (kept alive)
        lda #0
        sta t6
-       lda t6
        cmp nitems
        bcs +
        asl
        tax
        lda argv,x
        pha
        lda argv+1,x
        tax
        pla
        ldy t6
        phy
        jsr get_iter
        ply
        sty t6
        sta t4
        stx t4+1
        #PEEK 0
        sta p0
        stx p0+1
        lda t6
        asl
        clc
        adc #6
        taz
        lda t4
        sta [p0],z
        inz
        lda t4+1
        sta [p0],z
        inc t6

        bra -
+       #POP
        sta r0
        stx r0+1
        lda #IT_ZIP
        jsr iter_alloc
        lda #0
        sta r0
        sta r0+1
        lda p0
        ldx p0+1
        rts

;---------------------------------------------------------------------------------------
; tracebacks (in overlay R: the REPL brings R in before it reports an error)
;---------------------------------------------------------------------------------------
print_exception:
        jsr scr_fresh_line
        lda #COL_ERROR
        sta scr_color
        lda cur_exc
        ldx cur_exc+1
        sta r2
        stx r2+1
        ; syntax errors carry their own line; others: the levels of calls
        lda #EXC_SYNTAX
        jsr exc_is
        bcs _msg
        jsr print_tb
_msg:   ; "Name: message", or just "Name" when str(exc) is empty
        lda sbp
        pha
        lda sbp+1
        pha
        lda cur_exc
        ldx cur_exc+1
        jsr sb_type_name
        lda sbp
        pha
        lda sbp+1
        pha
        #SBPRINT ": "
        lda sbp
        pha
        lda sbp+1
        pha
        lda cur_exc
        ldx cur_exc+1
        jsr obj_str
        pla
        sta t1+1
        pla
        sta t1
        pla
        sta t2+1
        pla
        sta t2
        lda sbp
        cmp t1
        bne +
        lda sbp+1
        cmp t1+1
        bne +
        lda t2                          ; empty message: drop the ": "
        sta sbp
        lda t2+1
        sta sbp+1
+       plx
        pla
        jsr sb_flush
        lda #10
        jsr putc
        lda #COL_NORMAL
        sta scr_color
        rts

;---------------------------------------------------------------------------------------
; The levels of calls an exception left. throw records them when it is first raised
; (tb_capture, while overlay R is in): each frame's return ip (a line of its caller) and
; the name of the function it called, innermost first. print_tb prints them outermost
; first, as CPython does ("  line 3, in f"), the last one at exc_ip.
;---------------------------------------------------------------------------------------
TB_N            = 12
tb_exc:         .word 0                 ; the exception they belong to
tb_n:           .byte 0
tb_more:        .byte 0                 ; there were more frames (the outer ones)
tb_ip:          .fill 2 * TB_N
tb_name:        .fill 2 * TB_N          ; a perm name string, or 0

tb_capture:
        lda cur_exc
        sta tb_exc
        lda cur_exc+1
        sta tb_exc+1
        lda #0
        sta tb_more
        lda frp
        sta fp1
        lda frp+1
        sta fp1+1
        lda #<(FSTACK >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        ldy #0                          ; Y = 2 * entries
_loop:  lda fp1
        cmp #<FSTACK
        bne +
        lda fp1+1
        cmp #>FSTACK
        beq _done
+       cpy #2 * TB_N
        bcc +
        inc tb_more
        bra _done
+       sec
        lda fp1
        sbc #8
        sta fp1
        bcs +
        dec fp1+1
+       ldz #0                          ; the return ip
        lda [fp1],z
        sta tb_ip,y
        inz
        lda [fp1],z
        sta tb_ip+1,y
        ldz #4                          ; the callee: in the result slot, or a
        lda [fp1],z                     ; generator's function
        sta t0
        inz
        lda [fp1],z
        sta t0+1
        phy
        ldz #6
        lda [fp1],z
        and #FR_GEN
        beq _slot
        ldy #2
        lda (t0),y
        sta p0
        iny
        lda (t0),y
        sta p0+1
        ldz #4
        lda [p0],z
        pha
        inz
        lda [p0],z
        tax
        pla
        bra _f
_slot:  ldy #1
        lda (t0),y
        tax
        dey
        lda (t0),y
_f:     sta p0
        stx p0+1
        jsr type_of
        cmp #T_FUNC
        beq +
        lda #0
        tax
        bra _put
+       ldz #9                          ; its name
        lda [p0],z
        tax
        dez
        lda [p0],z
_put:   ply
        sta tb_name,y
        txa
        sta tb_name+1,y
        iny
        iny
        bra _loop
_done:  tya
        lsr a
        sta tb_n
        rts

print_tb:
        lda tb_exc                      ; (recorded for this exception?)
        cmp cur_exc
        bne _rts
        lda tb_exc+1
        cmp cur_exc+1
        bne _rts
        #PRINT "Traceback (most recent call last):"
        lda #10
        jsr putc
        lda tb_more
        beq +
        #PRINT "  ..."
        lda #10
        jsr putc
+       ldx tb_n
_lvl:   dex                             ; frame X: its return ip, and the function
        bmi _last                       ; of the frame outside it (X + 1)
        phx
        txa
        asl a
        tay
        lda tb_ip,y
        ldx tb_ip+1,y
        jsr _line
        plx
        phx
        inx
        cpx tb_n
        bcc _named
        lda tb_more
        bne _eol
        jsr _module
        bra _eol
_named: txa
        asl a
        tay
        lda tb_name,y
        ldx tb_name+1,y
        jsr _in
_eol:   lda #10
        jsr putc
        plx
        bra _lvl
_last:  lda exc_ip                      ; where it was raised
        ldx exc_ip+1
        jsr _line
        lda tb_n
        beq _mod
        lda tb_name
        ldx tb_name+1
        jsr _in
        bra +
_mod:   jsr _module
+       lda #10
        jmp putc
_rts:   rts
_line:  jsr line_of_ip                  ; "  line N"
        bcc +
        #PRINT "  ?"
        rts
+       pha
        phx
        #PRINT "  line "
        plx
        pla
        sta acc
        stx acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_mark_t5
        jsr sb_int
        lda t5
        ldx t5+1
        jmp sb_flush
_in:    cpx #0                          ; ", in name"
        beq _rts
        pha
        phx
        #PRINT ", in "
        plx
        pla
        jmp put_str
_module:
        #PRINT ", in <module>"
        rts

; line_of_ip - code offset A/X -> A/X = line (C clear), C set if unknown.
; The line table holds (offset, line) pairs in code order; take the last offset < ip.
line_of_ip:
        sta t0
        stx t0+1
        lda #<LINETAB
        sta fp0
        lda #>LINETAB
        sta fp0+1
        lda #<(LINETAB >> 16)
        sta fp0+2
        lda #>(LINETAB >> 16)
        sta fp0+3
        lda #0
        sta t1                          ; best line
        sta t1+1
        lda #1
        sta t2                          ; none found yet
_loop:  lda fp0
        cmp linetab_end
        bne +
        lda fp0+1
        cmp linetab_end+1
        beq _done
+       ldz #1
        lda [fp0],z
        cmp t0+1
        bcc _take
        bne _skip
        dez
        lda [fp0],z
        cmp t0
        bcs _skip
_take:  ldz #2
        lda [fp0],z
        sta t1
        inz
        lda [fp0],z
        sta t1+1
        lda #0
        sta t2
_skip:  clc
        lda fp0
        adc #4
        sta fp0
        bcc _loop
        inc fp0+1
        bra _loop
_done:  lda t2
        lsr
        lda t1
        ldx t1+1
        rts
