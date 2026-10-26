;=======================================================================================
; *args, **kwargs, keyword-only parameters, and f(*a, **k) calls (overlay R).
;
; A function's parameters are its first locals, in this order: the positional ones
; (nargs, the last nd with defaults), *args, the keyword-only ones (+19 of them, their
; defaults in the tuple at +16, NULL = required), **kwargs (+18 FF_VARARGS/FF_VARKW).
; call_py hands a call of such a function to bind_ex, which lays the parameters out.
;
; A call with * or ** collects its arguments in a list and a dict: PACK_ARGS takes the
; ones compiled so far, EX_ARG adds each further one, and CALL_EX makes the call. CALL_EX
; leaves the tuple of keyword names under the callable, where it stays referenced for
; the whole call; the compiler drops it afterwards (ROT2, POP).
;
; This is tail X: the opcodes' handlers and bind_ex are reached through stubs in vm.asm
; (xx_* return; the stub goes on to vm_loop, or makes the call).
;=======================================================================================
FF_VARARGS      = 1
FF_VARKW        = 2
FF_GEN          = 4                     ; it has a yield: calling it makes a generator

ba_slots:       .fill 2 * 48            ; the parameters being bound
ba_npos:        .byte 0                 ; positional parameters
ba_flags:       .byte 0
ba_nkwo:        .byte 0
ba_npar:        .byte 0                 ; all parameters
ba_np:          .byte 0                 ; positional arguments given
ba_kw0:         .byte 0                 ; the first keyword-only parameter
ba_ap:          .word 0                 ; argument 0's address (argument i at - 2i)
ba_i:           .byte 0
ba_cnt:         .byte 0
ba_obj:         .word 0                 ; *args tuple / **kwargs dict

; ba_arg - A = argument index -> A/X (the value stack, bank 0)
ba_arg:
        asl a
        sta t7
        sec
        lda ba_ap
        sbc t7
        sta t7
        lda ba_ap+1
        sbc #0
        sta t7+1
        ldy #1
        lda (t7),y
        tax
        dey
        lda (t7),y
        rts

; ba_setap - A = number of arguments on the stack -> ba_ap = argument 0's address
; (vsp + 2 * A - 2; with none, the slot above vsp)
ba_setap:
        asl a
        clc
        adc vsp
        sta ba_ap
        lda vsp+1
        adc #0
        sta ba_ap+1
        sec
        lda ba_ap
        sbc #2
        sta ba_ap
        lda ba_ap+1
        sbc #0
        sta ba_ap+1
        rts

; ba_slot - A = parameter index -> Y = its offset in ba_slots
ba_slot:
        asl a
        tay
        rts

; ba_tuple_item - A = index, p1 = tuple -> A/X = item
ba_tuple_item:
        asl a
        clc
        adc #6
        taz
        inz
        lda [p1],z
        tax
        dez
        lda [p1],z
        rts

;---------------------------------------------------------------------------------------
; bind_ex - (call_py) c_func's argc arguments on the stack (the last nkw keyword ones,
; named by kwnames) -> its parameters in order, argc = their number, no keywords
;---------------------------------------------------------------------------------------
xx_bind_ex:
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #6
        lda [p0],z
        sta ba_npos
        ldz #18
        lda [p0],z
        sta ba_flags
        inz
        lda [p0],z
        sta ba_nkwo
        ldz #12                         ; all parameters: the params tuple's length
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldz #4
        lda [p1],z
        sta ba_npar
        lda ba_npos                     ; the first keyword-only one
        sta ba_kw0
        lda ba_flags
        and #FF_VARARGS
        beq +
        inc ba_kw0
+       sec
        lda argc
        sbc nkw
        sta ba_np
        lda argc
        jsr ba_setap
        ldx #0                          ; no parameter bound yet
        lda #0
-       sta ba_slots,x
        inx
        cpx #2 * 48
        bne -
        ; positional arguments
        lda #0
        sta ba_i
_pos:   lda ba_i
        cmp ba_np
        bcs _star
        cmp ba_npos
        bcc +
        lda ba_flags                    ; more than the positional parameters
        and #FF_VARARGS
        bne _star
        jmp raise_arg_count
+       jsr ba_arg
        pha
        lda ba_i
        jsr ba_slot
        pla
        sta ba_slots,y
        txa
        sta ba_slots+1,y
        inc ba_i
        bra _pos
_star:  lda ba_flags                    ; *args: the extra positional arguments
        and #FF_VARARGS
        beq _dstar
        sec
        lda ba_np
        sbc ba_npos
        bcs +
        lda #0
+       sta ba_cnt
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        #PUSH                           ; (kept alive)
        sta ba_obj
        stx ba_obj+1
        sta p1
        stx p1+1
        lda #0
        sta ba_i
-       lda ba_i
        cmp ba_cnt
        bcs +
        clc
        adc ba_npos
        jsr ba_arg
        pha
        lda ba_i
        asl a
        clc
        adc #6
        taz
        pla
        sta [p1],z
        inz
        txa
        sta [p1],z
        inc ba_i
        bra -
+       lda ba_npos
        jsr ba_slot
        lda ba_obj
        sta ba_slots,y
        lda ba_obj+1
        sta ba_slots+1,y
_dstar: lda ba_flags                    ; **kwargs: an empty dict, the last parameter
        and #FF_VARKW
        beq _kw
        jsr dict_new
        #PUSH
        sta ba_obj
        stx ba_obj+1
        lda ba_npar
        dec a
        jsr ba_slot
        lda ba_obj
        sta ba_slots,y
        lda ba_obj+1
        sta ba_slots+1,y
        ; keyword arguments: by name to their parameter, or into **kwargs
_kw:    lda #0
        sta ba_i
_kwnext:
        lda ba_i
        cmp nkw
        bcc +
        jmp _defaults
+       lda kwnames                     ; the name
        sta p1
        lda kwnames+1
        sta p1+1
        lda ba_i
        jsr ba_tuple_item
        sta t4
        stx t4+1
        lda c_func                      ; the parameters that can be named
        sta p0
        lda c_func+1
        sta p0+1
        ldz #12
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldx #0
_find:  cpx ba_npos
        bcc _try
        cpx ba_kw0
        bcc _skip
        txa
        sec
        sbc ba_kw0
        cmp ba_nkwo
        bcs _none
_try:   phx
        txa
        jsr ba_tuple_item
        cmp t4
        bne _not
        cpx t4+1
        bne _not
        plx                             ; parameter X
        txa
        jsr ba_slot
        lda ba_slots,y
        ora ba_slots+1,y
        beq +
        jmp raise_multiple
+       phy
        clc
        lda ba_i
        adc ba_np
        jsr ba_arg
        ply
        sta ba_slots,y
        txa
        sta ba_slots+1,y
        bra _kwdone
_not:   plx
_skip:  inx
        bra _find
_none:  lda ba_flags                    ; no such parameter: **kwargs takes it
        and #FF_VARKW
        bne +
        jmp raise_unexpected_kw
+       lda ba_npar
        dec a
        jsr ba_slot
        lda ba_slots,y
        sta r0
        lda ba_slots+1,y
        sta r0+1
        lda t4
        sta r1
        lda t4+1
        sta r1+1
        clc
        lda ba_i
        adc ba_np
        jsr ba_arg
        sta r2
        stx r2+1
        jsr dict_set
_kwdone:
        inc ba_i
        jmp _kwnext
        ; defaults of the positional parameters, then of the keyword-only ones
_defaults:
        lda c_func
        sta p0
        lda c_func+1
        sta p0+1
        ldz #10
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        lda #0                          ; t5 = the first parameter with a default
        sta t5+1
        lda p1+1
        beq +
        ldz #4
        lda [p1],z
        sta t5+1
+       sec
        lda ba_npos
        sbc t5+1
        sta t5
        ldx #0
-       cpx ba_npos
        bcs _kwdef
        txa
        jsr ba_slot
        lda ba_slots,y
        ora ba_slots+1,y
        bne +
        cpx t5                          ; missing: its default, if it has one
        bcs _hasdef
        jmp raise_arg_count
_hasdef:
        phy
        phx
        txa
        sec
        sbc t5
        jsr ba_tuple_item
        stx t4
        plx
        ply
        sta ba_slots,y
        lda t4
        sta ba_slots+1,y
+       inx
        bra -
_kwdef: lda c_func
        sta p0
        lda c_func+1
        sta p0+1
        ldz #16
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldx #0
-       cpx ba_nkwo
        bcs _place
        txa
        clc
        adc ba_kw0
        jsr ba_slot
        lda ba_slots,y
        ora ba_slots+1,y
        bne +
        phy
        phx
        txa
        jsr ba_tuple_item
        stx t4
        plx
        ply
        sta ba_slots,y
        ora t4
        bne ++
        #RAISE EXC_TYPE, "missing a required keyword-only argument"
+       inx
        bra -
+       lda t4
        sta ba_slots+1,y
        inx
        bra -
        ; the stack: the arguments (and the tuple / dict) go, the parameters come
_place: clc
        lda ba_ap
        adc #2
        sta vsp
        lda ba_ap+1
        adc #0
        sta vsp+1
        lda #0
        sta ba_i
-       lda ba_i
        cmp ba_npar
        bcs +
        asl a
        tay
        lda ba_slots+1,y
        tax
        lda ba_slots,y
        #PUSH
        inc ba_i
        bra -
+       lda ba_npar
        sta argc
        lda #0
        sta nkw
        sta kwnames
        sta kwnames+1
        jmp clear_rregs

;---------------------------------------------------------------------------------------
; PACK_ARGS n, names - the first * or ** of a call: its n positional arguments become a
; list, its keyword ones (named by the tuple, or none) a dict
;---------------------------------------------------------------------------------------
xx_pack_args:
        #FETCHB
        sta ba_np
        #FETCHW
        sta kwnames                     ; (borrowed: kwnames is free until the call)
        stx kwnames+1
        lda #0
        sta nkw
        lda kwnames+1
        beq +
        sta p1+1
        lda kwnames
        sta p1
        ldz #4
        lda [p1],z
        sta nkw
+       clc                             ; argument 0's address
        lda ba_np
        adc nkw
        jsr ba_setap
        lda ba_np
        sta nitems
        lda #0
        sta nitems+1
        jsr list_new
        #PUSH
        lda #0
        sta ba_i
-       lda ba_i
        cmp ba_np
        bcs +
        jsr ba_arg
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        inc ba_i
        bra -
+       jsr dict_new
        #PUSH
        lda #0
        sta ba_i
-       lda ba_i
        cmp nkw
        bcs +
        lda kwnames
        sta p1
        lda kwnames+1
        sta p1+1
        lda ba_i
        jsr ba_tuple_item
        sta r1
        stx r1+1
        clc
        lda ba_i
        adc ba_np
        jsr ba_arg
        sta r2
        stx r2+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_set
        inc ba_i
        bra -
+       #POP                            ; [arguments][list][dict] -> [list][dict]
        sta r3
        stx r3+1
        #POP
        sta r2
        stx r2+1
        clc
        lda ba_ap
        adc #2
        sta vsp
        lda ba_ap+1
        adc #0
        sta vsp+1
        lda r2
        ldx r2+1
        #PUSH
        lda r3
        ldx r3+1
        #PUSH
        lda #0
        sta kwnames
        sta kwnames+1
        sta nkw
        jmp clear_rregs

;---------------------------------------------------------------------------------------
; EX_ARG kind - one more argument of a * / ** call ([list][dict] below):
;   0 value: append        1 iterable: extend (*x)
;   2 name, value: a keyword (once only)       3 mapping: its items as keywords (**x)
;---------------------------------------------------------------------------------------
xx_ex_arg:
        #FETCHB
        cmp #4                          ; displays: [*a, *b], {**d, k: v}
        bcc +
        cmp #5
        beq _merge
        jmp ex_display
+       cmp #1
        beq _extend
        bcs _keyword
        #PEEK 0                         ; append
        sta r1
        stx r1+1
        #PEEK 2
        sta r0
        stx r0+1
        jsr list_append
        #DROP 1
        jmp _done
_extend:
        #PEEK 0
        jsr list_from_iterable          ; (may run Python: a user iterator)
        #POKE 0
        sta t0
        stx t0+1
        #PEEK 2
        sta r0
        stx r0+1
        lda t0
        ldx t0+1
        jsr list_extend_r0
        #DROP 1
        jmp _done
_keyword:
        cmp #2
        bne _merge
        #PEEK 1                         ; [list][dict][name][value]
        sta r1
        stx r1+1
        #PEEK 0
        sta r2
        stx r2+1
        #PEEK 2
        jsr ex_kwarg
        #DROP 2
        bra _done
_merge: sta ex_kind                     ; (3: a call's **, 5: a display's)
        #PEEK 0                         ; a dict's items
        jsr type_of
        cmp #T_DICT
        beq +
        lda ex_kind
        cmp #5
        beq _notmap
        #RAISE EXC_TYPE, "argument after ** must be a dict"
_notmap:
        #PEEK 0
        ldy #RT_MAP
        jmp raise_typed
+       lda #0
        sta ba_i
-       #PEEK 0
        jsr seq_len
        lda ba_i
        cmp t0
        bcs +
        #PEEK 0
        sta p0
        stx p0+1
        lda ba_i
        asl a
        sta t0
        lda #0
        rol a
        sta t0+1
        jsr list_item_ptr
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
        lda ba_i                        ; (Python code may run in there)
        pha
        lda ex_kind
        pha
        #PEEK 1
        sta r0
        stx r0+1
        lda ex_kind
        cmp #5
        beq _upd
        lda r0
        ldx r0+1
        jsr ex_kwarg
        bra _nxt
_upd:   jsr dict_set                    ; a display: later keys win
_nxt:   pla
        sta ex_kind
        pla
        sta ba_i
        inc ba_i
        bra -
+       #DROP 1
_done:  jmp clear_rregs
ex_kind:        .byte 0

; ex_display - EX_ARG kinds 4-9 for displays, on [list][dict]: 4 [key][value] into the
; dict, 5 a mapping's items into it; 6-9 the result instead of the pair: the list, a
; tuple, a set of its items, or the dict
ex_display:
        cmp #6
        bcs _finish
        #PEEK 1                         ; 4: dict[key] = value
        sta r1
        stx r1+1
        #PEEK 0
        sta r2
        stx r2+1
        #PEEK 2
        sta r0
        stx r0+1
        jsr dict_set
        #DROP 2
        jmp clear_rregs
_finish:
        sec
        sbc #6
        pha
        #POP                            ; the dict
        ply
        cpy #3
        bne +
        #POKE 0                         ; {**d}: the dict
        rts
+       cpy #0
        beq _rts                        ; [*a]: the list
        phy
        #PEEK 0
        ply
        cpy #1
        bne +
        jsr tuple_from_list             ; (*a,)
        bra _put
+       ldy #F_SET                      ; {*a}
        jsr sets_from_iter
_put:   #POKE 0
_rts:   rts

; ex_kwarg - A/X = the call's keyword dict, r1 = name, r2 = value: add it (TypeError
; for a name that is no string, or one given twice)
ex_kwarg:
        sta r0
        stx r0+1
        lda r1
        ldx r1+1
        jsr type_of
        cmp #T_STR
        beq +
        #RAISE EXC_TYPE, "keywords must be strings"
+       lda r2                          ; (dict_find's comparisons use r2)
        pha
        lda r2+1
        pha
        jsr dict_find
        pla
        sta r2+1
        pla
        sta r2
        bcs +
        jmp raise_multiple
+       jmp dict_set

;---------------------------------------------------------------------------------------
; CALL_EX method - [f][list][dict] (method 1: [meth][self or NULL][list][dict]) -> the
; call, with [names or None] left under it. The names are the dict's keys, interned so
; they match parameter names.
;---------------------------------------------------------------------------------------
xx_call_ex:
        #FETCHB
        sta ba_flags                    ; 1: a method call
        #POP
        sta r3                          ; dict
        stx r3+1
        #POP
        sta r2                          ; list
        stx r2+1
        lda ba_flags
        beq +
        #POP
        sta r1                          ; self (or NULL)
        stx r1+1
+       #POP
        sta r0                          ; the callable
        stx r0+1
        lda r3
        ldx r3+1
        jsr seq_len
        lda t0
        sta nkw
        bne +
        lda #R_NONE                     ; no keywords
        ldx #0
        #PUSH
        lda #0
        sta kwnames
        sta kwnames+1
        bra _f
+       sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new                   ; (r0-r3 keep the rest alive)
        #PUSH
        sta kwnames
        stx kwnames+1
        lda #0
        sta ba_i
-       lda ba_i
        cmp nkw
        bcs _f
        lda r3                          ; key i, interned if a name of that spelling exists
        sta p0
        lda r3+1
        sta p0+1
        lda ba_i
        asl a
        sta t0
        lda #0
        sta t0+1
        jsr list_item_ptr
        ldz #1
        lda [p1],z
        tax
        dez
        lda [p1],z
        pha
        phx
        jsr str_info
        ldx #3
-       lda fp0,x
        sta fp2,x
        dex
        bpl -
        jsr intern_find
        plx
        pla
        bcs +
        lda int_ref
        ldx int_ref+1
+       pha
        lda kwnames
        sta p1
        lda kwnames+1
        sta p1+1
        lda ba_i
        asl a
        clc
        adc #6
        taz
        pla
        sta [p1],z
        inz
        txa
        sta [p1],z
        inc ba_i
        bra --
_f:     lda r0                          ; the callable (and self)
        ldx r0+1
        #PUSH
        lda ba_flags
        beq +
        lda r1
        ldx r1+1
        #PUSH
+       lda #0                          ; the positional arguments
        sta ba_i
-       lda r2
        ldx r2+1
        jsr seq_len
        lda ba_i
        cmp t0
        bcs +
        sta t2
        lda #0
        sta t2+1
        lda r2
        ldx r2+1
        jsr seq_get_t2
        #PUSH
        inc ba_i
        bra -
+       sta argc                        ; (A = their number)
        lda #0                          ; the keyword values
        sta ba_i
-       lda ba_i
        cmp nkw
        bcs +
        lda r3
        sta p0
        lda r3+1
        sta p0+1
        lda ba_i
        asl a
        sta t0
        lda #0
        sta t0+1
        jsr list_item_ptr
        ldz #3
        lda [p1],z
        tax
        dez
        lda [p1],z
        #PUSH
        inc ba_i
        bra -
+       clc
        lda argc
        adc nkw
        sta argc
        jsr clear_rregs
        lda ba_flags                    ; C set: a method call
        lsr a
        rts

;---------------------------------------------------------------------------------------
; generators (gen.asm): saving and restoring the exception handlers of a generator
; that yields inside a try
;---------------------------------------------------------------------------------------
; xg_handlers_in - (gen_resume) p0 = generator: push its saved handlers (for the frame
; just pushed)
xg_handlers_in:
        ldz #13
        lda [p0],z
        beq _done
        sta gen_c
        asl                             ; room: 8 bytes each
        asl
        asl
        clc
        adc hsp
        lda hsp+1
        adc #0
        cmp #>(HSTACK_END - 8)
        bcc +
        jmp raise_recursion
+       ldz #8
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldy #4                          ; Y = offset in the array
_next:  tya
        taz
        lda [p1],z                      ; ip
        ldz #0
        sta [hsp],z
        tya
        inc a
        taz
        lda [p1],z
        ldz #1
        sta [hsp],z
        iny
        iny
        jsr _off                        ; vsp = result slot - offset
        ldz #2
        sta [hsp],z
        inz
        txa
        sta [hsp],z
        inz
        lda frp                         ; frp: this frame's
        sta [hsp],z
        inz
        lda frp+1
        sta [hsp],z
        iny
        iny
        jsr _off                        ; vfp
        ldz #6
        sta [hsp],z
        inz
        txa
        sta [hsp],z
        iny
        iny
        clc
        lda hsp
        adc #8
        sta hsp
        bcc +
        inc hsp+1
+       dec gen_c
        bne _next
_done:  rts
; A/X = result slot - the word at p1 + Y
_off:   tya
        taz
        sec
        lda c_slot
        sbc [p1],z
        pha
        inz
        lda c_slot+1
        sbc [p1],z
        tax
        pla
        rts

; xg_handlers_out - (gen_handlers_out) A = gen_c handlers of the frame: into an array
; of the generator gen_ref, and off the handler stack
xg_handlers_out:
       sta nitems                      ; 3 words each
        asl
        clc
        adc nitems
        sta nitems
        lda #0
        sta nitems+1
        jsr arr_new
        sta t1
        stx t1+1
        jsr gen_p0
        ldz #8
        lda t1
        sta [p0],z
        inz
        lda t1+1
        sta [p0],z
        lda t1
        sta p1
        lda t1+1
        sta p1+1
        lda gen_c                       ; the oldest first: from hsp - 8 * count
        asl
        asl
        asl
        sta t0
        sec
        lda hsp
        sbc t0
        sta hsp
        sta fp1
        lda hsp+1
        sbc #0
        sta hsp+1
        sta fp1+1
        ldy #4
_copy:  ldz #0                          ; ip
        lda [fp1],z
        jsr _put
        ldz #1
        lda [fp1],z
        jsr _put
        sec                             ; result slot - vsp
        ldz #2
        lda c_slot
        sbc [fp1],z
        pha
        inz
        lda c_slot+1
        sbc [fp1],z
        tax
        pla
        jsr _put
        txa
        jsr _put
        sec                             ; result slot - vfp
        ldz #6
        lda c_slot
        sbc [fp1],z
        pha
        inz
        lda c_slot+1
        sbc [fp1],z
        tax
        pla
        jsr _put
        txa
        jsr _put
        clc
        lda fp1
        adc #8
        sta fp1
        bcc +
        inc fp1+1
+       dec gen_c
        bne _copy
        rts
_put:   phz
        pha
        tya
        taz
        pla
        sta [p1],z
        plz
        iny
        rts

; g.send(value): resume it with value as its yield's result -> the next value it yields
; (StopIteration when it ends); a new generator takes only None
xg_send:
        #NARGS 2, 2
        #ARG 0
        sta gen_ref
        stx gen_ref+1
        jsr gen_p0
        ldz #12
        lda [p0],z
        cmp #GS_NEW
        bne +
        lda argv+3
        bne _new
        lda argv+2
        cmp #R_NONE
        beq +
_new:   #RAISE EXC_TYPE, "can't send non-None value to a just-started generator"
+       lda argv+2
        sta gen_sent
        lda argv+3
        sta gen_sent+1
        #ARG 0
        jsr gen_send_native
        bcs +
        rts
+       jmp xg_stop                     ; (A/X = what it returned)

; xg_state - ARG 0 = a generator -> A = its state (GS_DONE for one an exception
; left); a running one raises ValueError
xg_state:
        #ARG 0
        sta gen_ref
        stx gen_ref+1
        jsr gen_p0
        ldz #12
        lda [p0],z
        cmp #GS_RUN
        bne +
        jsr gen_alive
        lda #GS_DONE
        bcc +
        #RAISE EXC_VALUE, "generator already executing"
+       rts
; xg_end - ARG 0 is finished
xg_end:
        #ARG 0
        sta p0
        stx p0+1
        jmp gen_end

; g.close(): GeneratorExit at its yield, so its finally blocks run; it must end (or
; raise GeneratorExit / StopIteration). One that yields again: RuntimeError.
xg_close:
        #NARGS 1, 1
        jsr xg_state
        cmp #GS_SUSP
        beq _exit
_end:   jsr xg_end                      ; (not started, or finished)
_none:  lda #R_NONE
        ldx #0
        rts
_exit:  lda #<_run
        ldx #>_run
        jsr try_call
        bcs _exc
        lda tc_c
        bne _none                       ; it ended
        #RAISE EXC_RUNTIME, "generator ignored GeneratorExit"
_exc:   lda #EXC_GENEXIT
        jsr _is
        bcs _ok
        lda #EXC_STOPITER
        jsr _is
        bcs _ok
        jmp throw                       ; anything else goes on
_ok:    jsr clear_exc
        bra _end
_is:    ldx cur_exc                     ; is cur_exc an instance of class id A?
        stx r2
        ldx cur_exc+1
        stx r2+1
        jmp exc_is
_run:   lda #EXC_GENEXIT
        jsr exc_new_empty
        sta gen_exc
        stx gen_exc+1
        #ARG 0
        jmp gen_resume_native

; g.throw(exc) / g.throw(cls, value): exc raised at its yield -> the next value it
; yields (StopIteration when it ends). A generator not started or finished raises it
; here (and is finished).
xg_throw:
        #NARGS 2, 3
        #ARG 1
        ldy npos
        cpy #3
        bne +
        ldy argv+4                      ; cls(value)
        sty r1
        ldy argv+5
        sty r1+1
        jsr call1
+       jsr make_exception
        #PUSH                           ; (kept while the state is checked)
        jsr xg_state
        cmp #GS_SUSP
        beq _go
        jsr xg_end
        #POP
        sta cur_exc
        stx cur_exc+1
        lda #0
        sta exc_ip_set
        jmp throw
_go:    #POP
        sta gen_exc
        stx gen_exc+1
        #ARG 0
        jsr gen_resume_native
        bcs +
        rts
+       jmp xg_stop                     ; (A/X = what it returned)

;---------------------------------------------------------------------------------------
; generators: the parts of gen.asm that only run with overlay R in
; xg_create - (call_py through gen_make, with the locals pushed) the generator instead
; of the call: its locals go in the tuple -> A/X = it, the call's result (vsp = the
; result slot)
;---------------------------------------------------------------------------------------
xg_create:
        lda c_func
        sta p0
        lda c_func+1
        sta p0+1
        ldz #7
        lda [p0],z                      ; nlocals
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new                   ; (may collect: the locals are on the stack)
        ldz #4
        lda [p0],z
        beq +
        asl
        sta t0
        lda #0
        sta t0+1
        lda vsp
        ldx vsp+1
        clc
        jsr gen_xfer
+       lda p0
        ldx p0+1
        #PUSH                           ; (kept while the generator is made)
        lda #GEN_SIZE
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_GEN
        jsr alloc                       ; (the body is zeroed: GS_NEW)
        ldz #4
        lda c_func
        sta [p0],z
        inz
        lda c_func+1
        sta [p0],z
        #POP
        ldz #6
        sta [p0],z
        inz
        txa
        sta [p0],z
        lda c_func                      ; it starts at the function's code
        sta p1
        lda c_func+1
        sta p1+1
        ldz #4
        lda [p1],z
        ldz #10
        sta [p0],z
        ldz #5
        lda [p1],z
        ldz #11
        sta [p0],z
        lda c_slot                      ; the locals go; the generator is the result
        sta vsp
        lda c_slot+1
        sta vsp+1
        lda p0
        ldx p0+1
        rts

; xg_stop - A/X = what a generator returned: raise StopIteration with it as .value (and
; in .args, unless it is None)
xg_stop:
        #PUSH                           ; (kept while the exception is made)
        sta r1
        stx r1+1
        cpx #0
        bne _arg
        cmp #R_NONE
        bne _arg
        lda #0                          ; None: no args
        sta r1
        sta r1+1
_arg:   lda #EXC_STOPITER
        jsr exc_new
        sta r0
        stx r0+1
        lda #<S_VALUE
        ldx #>S_VALUE
        jsr sym_name
        sta r1
        stx r1+1
        #POP
        sta r2
        stx r2+1
        lda r0
        pha
        lda r0+1
        pha
        jsr setattr
        pla
        sta cur_exc+1
        pla
        sta cur_exc
        lda #0
        sta exc_ip_set
        jmp throw

; map() / filter(): the iterator (builtins.asm has the rest)
xb_map:
        ldy #16
        lda #IT_MAP
        bra mapfilter
xb_filter:
        ldy #2
        lda #IT_FILTER
mapfilter:
        pha
        ldx #2
        jsr check_nargs
        #ARG 0
        #PUSH                           ; [f]
        lda npos
        cmp #2
        beq _one
        ldx #0                          ; zip(*iterables): the arguments after f
-       lda argv+2,x
        sta argv,x
        inx
        cpx #30
        bne -
        dec nargc
        jsr bi_zip
        bra _it
_one:   #ARG 1
        jsr get_iter
_it:    sta r3                          ; (f, it)
        stx r3+1
        #POP
        sta r2
        stx r2+1
        jsr tuple2
        sta r0
        stx r0+1
        pla
        jsr iter_alloc
        ldy #1                          ; f(x), or f(*x) for several iterables
        lda npos
        cmp #2
        beq +
        iny
+       tya
        ldz #8
        sta [p0],z
        lda #0
        sta r0
        sta r0+1
        lda p0
        ldx p0+1
        rts

;---------------------------------------------------------------------------------------
; keyword arguments for a plain Python function (call_py): see vm.asm
;---------------------------------------------------------------------------------------
kwv:            .fill 32
xx_kw_to_positional:
        ; take the kw values off the stack
        ldx #0
-       cpx nkw                         ; kwv[j] = value j = vsp + 2*(nkw-1-j)
        bcs +
        stx t0
        lda nkw
        sec
        sbc #1
        sbc t0
        asl
        tay
        txa
        asl
        tax
        lda (vsp),y
        sta kwv,x
        iny
        lda (vsp),y
        sta kwv+1,x
        ldx t0
        inx
        bra -
+       ; this could be done in place but keep it simple: pop them
        lda nkw
        asl
        clc
        adc vsp
        sta vsp
        bcc +
        inc vsp+1
+       sec
        lda argc
        sbc nkw
        sta argc
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #6
        lda [p0],z
        sta t1                          ; nargs
        lda argc
        cmp t1
        bcc +
        beq +
        jmp raise_arg_count
+       ; push NULL params argc .. nargs-1
-       lda argc
        cmp t1
        bcs +
        lda #0
        tax
        #PUSH
        inc argc
        bra -
+       ; place each kw value: param index from the params tuple (+12)
        ldz #12
        lda [p0],z
        sta p2
        inz
        lda [p0],z
        sta p2+1
        lda #0
        sta t3                          ; j
_kw:    lda t3
        cmp nkw
        bcs _done
        ; name j
        lda kwnames
        ldx kwnames+1
        sta p1
        stx p1+1
        lda t3
        asl
        clc
        adc #6
        taz
        lda [p1],z
        sta t4
        inz
        lda [p1],z
        sta t4+1
        ; search the params
        ldx #0
-       cpx t1
        bcs _unexp
        txa
        asl
        clc
        adc #6
        taz
        lda [p2],z
        cmp t4
        bne +
        inz
        lda [p2],z
        cmp t4+1
        beq _found
+       inx
        bra -
_found: ; slot of param x = vsp + 2*(nargs-1-x); must be NULL
        stx t0
        lda t1
        sec
        sbc #1
        sbc t0
        asl
        tay
        lda (vsp),y
        iny
        ora (vsp),y
        beq +
        jmp raise_multiple
+       lda t3
        asl
        tax
        lda kwv+1,x
        sta (vsp),y
        dey
        lda kwv,x
        sta (vsp),y
        inc t3
        bra _kw
_unexp: jmp raise_unexpected_kw
_done:  ; fill trailing NULL params from defaults, missing ones are errors
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #10
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldx #0
_fill:  cpx t1
        bcs _ok
        stx t0
        lda t1
        sec
        sbc #1
        sbc t0
        asl
        tay
        lda (vsp),y
        iny
        ora (vsp),y
        bne _next
        ; default for param x: defaults[x - (nargs - nd)]
        lda p1+1
        beq _miss
        ldz #4
        lda [p1],z
        sta t2
        lda t1
        sec
        sbc t2
        sta t2
        cpx t2
        bcc _miss
        txa
        sec
        sbc t2
        asl
        clc
        adc #6
        taz
        inz
        lda [p1],z
        sta (vsp),y
        dey
        dez
        lda [p1],z
        sta (vsp),y
_next:  inx
        bra _fill
_miss:  jmp raise_arg_count
_ok:    lda #0
        sta nkw
        rts

;---------------------------------------------------------------------------------------
; MAKE_CLASS (vm.asm runs it)
;---------------------------------------------------------------------------------------
xx_make_class:
        ; base -> cls  (+4 name, +6 base, +8 dict, +10 MRO, +12 bases: classm.asm)
        lda #14
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_CLASS
        jsr alloc
        lda p0
        sta r0
        lda p0+1
        sta r0+1
        #FETCHW
        ldz #4
        sta [p0],z
        inz
        txa
        sta [p0],z
        jsr class_bases                 ; the bases (tail M) -> A/X = the class
        sta r0
        stx r0+1
        #POKE 0
        jsr dict_new
        sta t0
        stx t0+1
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #8
        lda t0
        sta [p0],z
        inz
        lda t0+1
        sta [p0],z
        clc                             ; its body runs now (LOAD_CLASSNAME); an entry
        lda vsp                         ; at this slot or above is left from a failed one
        adc #1
        sta cb_lim
        lda vsp+1
        adc #0
        sta cb_lim+1
        jsr cb_prune_lim
        ldx cb_sp
        cpx #CB_MAX * 4
        bcc +
        #RAISE EXC_RUNTIME, "classes nested too deeply"
+       lda r0
        sta cb_stack,x
        lda r0+1
        sta cb_stack+1,x
        lda vsp                         ; (where it is on the value stack)
        sta cb_stack+2,x
        lda vsp+1
        sta cb_stack+3,x
        inx
        inx
        inx
        inx
        stx cb_sp
        lda #0
        sta r0
        sta r0+1
        rts
