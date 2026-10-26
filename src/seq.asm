;=======================================================================================
; Subscripts, slices and iteration.
;=======================================================================================
; T_ITER kinds
IT_SEQ          = 0                     ; list / tuple: +6 seq, +8 index
IT_STR          = 1                     ; +6 str, +8 index
IT_DICT         = 2                     ; keys: +6 dict, +8 index, +12 size, +14 keys
                                        ; left, +16 last key (methods.asm it_dpair)
IT_RANGE        = 3                     ; +8 cur, +12 stop, +16 step
IT_ITEMS        = 4                     ; dict items
IT_VALUES       = 5                     ; dict values
IT_ENUM         = 6                     ; +6 inner iterator, +8 count
IT_ZIP          = 7                     ; +6 tuple of iterators
IT_REV          = 8                     ; +6 seq, +8 index (counts down)
IT_INST         = 9                     ; +6 instance with __next__
IT_FILE         = 10                    ; +6 file (its lines)
IT_MAP          = 11                    ; +6 (f, iterator), +8 call style (builtins.asm)
IT_FILTER       = 12                    ; (the same)

;---------------------------------------------------------------------------------------
; index helpers
;---------------------------------------------------------------------------------------
; norm_index - A/X = index (int ref), t5 = length -> t0 = index in 0..len-1, C set if out
norm_index:
        jsr int_val
        bcc +
        jmp raise_need_int
+       bit acc+3
        bpl _pos
        ; negative: add the length
        clc
        lda acc
        adc t5
        sta acc
        lda acc+1
        adc t5+1
        sta acc+1
        lda acc+2
        adc #0
        sta acc+2
        lda acc+3
        adc #0
        sta acc+3
        bmi _out
_pos:   lda acc+2
        ora acc+3
        bne _out
        lda acc+1
        cmp t5+1
        bcc _in
        bne _out
        lda acc
        cmp t5
        bcs _out
_in:    lda acc
        sta t0
        lda acc+1
        sta t0+1
        clc
        rts
_out:   sec
        rts

;---------------------------------------------------------------------------------------
op_load_subscr:
        #PEEK 1
        sta r2
        stx r2+1
        #PEEK 0
        sta r3
        stx r3+1
        jsr getitem
        sta t0
        stx t0+1
        #DROP 1
        lda t0
        ldx t0+1
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

; getitem - r2[r3] -> A/X
getitem:
        lda r3
        ldx r3+1
        jsr type_of
        cmp #T_SLICE
        bne +
        lda r2                          ; (an instance's __getitem__ gets the slice)
        ldx r2+1
        jsr type_of
        cmp #T_INST
        beq _inst
        jmp getslice
+       lda r2
        ldx r2+1
        jsr type_of
        cmp #T_LIST
        beq _seq
        cmp #T_TUPLE
        beq _seq
        cmp #T_STR
        beq _str
        cmp #T_DICT
        beq _dict
        cmp #T_RANGE
        beq _range
        cmp #T_INST
        bne _bad
_inst:  lda #S_GETITEM
        jsr inst_binop
        bcs _bad
        rts
_bad:   #RAISE EXC_TYPE, "object is not subscriptable"
_seq:   ldz #4
        lda [p0],z
        sta t5
        inz
        lda [p0],z
        sta t5+1
        lda r3
        ldx r3+1
        jsr norm_index
        bcc +
        lda r2
        ldx r2+1
        jmp raise_index_of
+       lda r2
        ldx r2+1
        sta p0
        stx p0+1
        jmp seq_get
_str:   lda r2
        ldx r2+1
        jsr str_info
        lda str_len
        sta t5
        lda str_len+1
        sta t5+1
        lda r3
        ldx r3+1
        jsr norm_index
        bcc +
        #RAISE EXC_INDEX, "string index out of range"
+       lda r2
        ldx r2+1
        jsr str_info
        clc
        lda fp0
        adc t0
        sta fp0
        lda fp0+1
        adc t0+1
        sta fp0+1
        ldz #0
        lda [fp0],z
        jmp char_str
_dict:  lda r2
        sta r0
        lda r2+1
        sta r0+1
        lda r3
        sta r1
        lda r3+1
        sta r1+1
        jsr dict_get
        bcs +
        rts
+       jmp raise_key
_range: ; start + i * step
        jsr range_len                   ; t5 = length
        lda r3
        ldx r3+1
        jsr norm_index
        bcc +
        jmp raise_index
+       lda t0
        sta acc
        lda t0+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        lda r2
        ldx r2+1
        jmp range_at

; char_str - A = char -> A/X = one-character string (cached for ASCII)
char_cache:     .fill 256, 0            ; 128 refs
char_str:
        and #$7f
        asl
        tay
        lda char_cache+1,y
        beq _new
        tax
        lda char_cache,y
        rts
_new:   phy
        tya
        lsr
        pha
        lda #1
        sta str_len
        lda #0
        sta str_len+1
        lda al_perm
        pha
        lda #F_PERM
        sta al_perm
        jsr str_alloc
        pla
        sta al_perm
        pla
        ldz #6
        sta [p0],z
        ply
        lda p0
        sta char_cache,y
        lda p0+1
        sta char_cache+1,y
        lda p0
        ldx p0+1
        rts

op_store_subscr:
        ; obj key val ->
        #PEEK 2
        sta r0
        stx r0+1
        #PEEK 1
        sta r1
        stx r1+1
        #PEEK 0
        sta r2
        stx r2+1
        jsr setitem
        #DROP 3
        jsr clear_rregs
        jmp vm_loop

; setitem - r0[r1] = r2
setitem:
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_LIST
        beq _list
        cmp #T_DICT
        bne +
        jmp dict_set
+       cmp #T_INST
        bne _bad
        ; __setitem__(key, value): push and call
        lda r0
        pha
        lda r0+1
        pha
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        lda #S_SETITEM
        jsr inst_method2
        pla
        pla
        rts
_bad:   #RAISE EXC_TYPE, "object does not support item assignment"
_list:  ldz #4
        lda [p0],z
        sta t5
        inz
        lda [p0],z
        sta t5+1
        lda r1
        ldx r1+1
        jsr norm_index
        bcc +
        #RAISE EXC_INDEX, "list assignment index out of range"
+       lda r0
        ldx r0+1
        sta p0
        stx p0+1
        jsr list_item_ptr
        ldz #0
        lda r2
        sta [p1],z
        inz
        lda r2+1
        sta [p1],z
        rts

; inst_method2 - call r0's method A with two arguments r1, r2 (no result needed)
inst_method2:
        sta dun_sym
        lda r0
        ldx r0+1
        sta _self                       ; (class_lookup uses r0)
        stx _self+1
        jsr type_of
        ldz #4
        lda [p0],z
        sta r3
        inz
        lda [p0],z
        sta r3+1
        lda r2
        pha
        lda r2+1
        pha
        lda r3
        sta r2
        lda r3+1
        sta r2+1
        lda r1
        pha
        lda r1+1
        pha
        lda dun_sym
        ldx #0
        jsr sym_name
        sta r1
        stx r1+1
        jsr class_lookup
        bcc +
        jmp setitem_bad
+       #PUSH
        lda _self
        ldx _self+1
        #PUSH
        pla
        tax
        pla
        #PUSH
        pla
        tax
        pla
        #PUSH
        lda #3
        sta argc
        jmp vm_call_nested
_self:  .word 0
setitem_bad:
        #RAISE EXC_TYPE, "object does not support item assignment"

op_delete_subscr:
        #PEEK 1
        sta r0
        stx r0+1
        #PEEK 0
        sta r1
        stx r1+1
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_DICT
        beq _dict
        cmp #T_LIST
        bne _bad
        ldz #4
        lda [p0],z
        sta t5
        inz
        lda [p0],z
        sta t5+1
        lda r1
        ldx r1+1
        jsr norm_index
        bcc +
        jmp raise_index
+       lda t0
        ldx t0+1
        jsr list_del_at
        bra _done
_dict:  jsr dict_del
        bcc _done
        jmp raise_key
_bad:   #RAISE EXC_TYPE, "object does not support item deletion"
_done:  #DROP 2
        jsr clear_rregs
        jmp vm_loop

; list_del_at - remove item A/X from list r0 -> A/X = the removed item
list_del_at:
        sta t0
        stx t0+1
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        jsr list_item_ptr
        ldz #0
        lda [p1],z
        pha
        inz
        lda [p1],z
        pha
        ldz #4
        sec
        lda [p0],z
        sbc #1
        sta [p0],z
        sta t4
        inz
        lda [p0],z
        sbc #0
        sta [p0],z
        sta t4+1
        ; move (newlen - index) items down one slot
        sec
        lda t4
        sbc t0
        sta t1
        lda t4+1
        sbc t0+1
        sta t1+1
        asw t1
        lda t1
        ora t1+1
        beq +
        lda t1
        sta t0
        lda t1+1
        sta t0+1
        lda p1
        sta fp1
        lda p1+1
        sta fp1+1
        clc
        lda p1
        adc #2
        sta fp0
        lda p1+1
        adc #0
        sta fp0+1
        lda #HEAP_BANK
        sta fp0+2
        sta fp1+2
        lda #0
        sta fp0+3
        sta fp1+3
        jsr dma_copy
+       plx
        pla
        rts

;---------------------------------------------------------------------------------------
; slices: list/tuple/str[start:stop:step]
;---------------------------------------------------------------------------------------
sl_start:       .dword 0
sl_stop:        .dword 0
sl_step:        .dword 0
sl_len:         .word 0
it_val:         .dword 0

; slice_bounds - r3 = slice, t5 = length -> sl_start/sl_stop/sl_step (clamped)
slice_bounds:
        lda r3
        sta p3
        lda r3+1
        sta p3+1
        ; step
        ldz #9
        lda [p3],z
        tax
        dez
        lda [p3],z
        cmp #R_NONE
        bne +
        cpx #0
        bne +
        lda #1
        sta acc
        lda #0
        sta acc+1
        sta acc+2
        sta acc+3
        bra _st
+       jsr int_val
        bcc +
        jmp raise_need_int
+       lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        bne _st
        #RAISE EXC_VALUE, "slice step cannot be zero"
_st:    ldq acc
        stq sl_step
        ; start: default 0 (or len-1 for a negative step)
        ldz #4
        jsr _bound
        bcc +
        jsr _deflo
+       ldq acc
        stq sl_start
        ldz #6
        jsr _bound
        bcc +
        jsr _defhi
+       ldq acc
        stq sl_stop
        rts
; default start / stop
_deflo: bit sl_step+3
        bmi _lenm1
_zero:  lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
        rts
_defhi: bit sl_step+3
        bmi _minus1
        lda t5
        sta acc
        lda t5+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        rts
_lenm1: jsr _defhi2
        bra _dec
_defhi2:
        lda t5
        sta acc
        lda t5+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        rts
_minus1:
        lda #$ff
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
        rts
_dec:   sec
        lda acc
        sbc #1
        sta acc
        lda acc+1
        sbc #0
        sta acc+1
        lda acc+2
        sbc #0
        sta acc+2
        lda acc+3
        sbc #0
        sta acc+3
        rts
; field Z of the slice -> acc clamped; C set if None
_bound: phz
        inz
        lda [p3],z
        tax
        dez
        lda [p3],z
        plz
        cmp #R_NONE
        bne +
        cpx #0
        bne +
        sec
        rts
+       jsr int_val
        bcc +
        jmp raise_need_int
+       ; negative: += len; then clamp to [0, len] (step > 0) or [-1, len-1] (step < 0)
        bit acc+3
        bpl _clamp
        clc
        lda acc
        adc t5
        sta acc
        lda acc+1
        adc t5+1
        sta acc+1
        lda acc+2
        adc #0
        sta acc+2
        lda acc+3
        adc #0
        sta acc+3
        bpl _clamp
        bit sl_step+3
        bmi +
        jsr _zero
        clc
        rts
+       jsr _minus1
        clc
        rts
_clamp: ; above len?
        lda acc+3
        ora acc+2
        bne _hi
        lda acc+1
        cmp t5+1
        bcc _ok
        bne _hi
        lda acc
        cmp t5
        bcc _ok
_hi:    bit sl_step+3
        bmi +
        jsr _defhi2
        clc
        rts
+       jsr _defhi2
        jsr _dec
_ok:    clc
        rts

; getslice - r2[r3 slice] -> A/X (a new list, tuple or string)
getslice:
        lda r2
        ldx r2+1
        jsr type_of
        sta t6
        cmp #T_STR
        beq +
        cmp #T_LIST
        beq +
        cmp #T_TUPLE
        beq +
        #RAISE EXC_TYPE, "object is not sliceable"
+       ldz #4
        lda [p0],z
        sta t5
        inz
        lda [p0],z
        sta t5+1
        jsr slice_bounds
        lda t6
        cmp #T_STR
        bne _list
        ; string: collect the chars in the builder
        lda sbp
        pha
        lda sbp+1
        pha
        lda r2
        ldx r2+1
        jsr str_info
_sl:    jsr slice_more
        bcs _sdone
        clc
        lda fp0
        adc sl_start
        sta fp1
        lda fp0+1
        adc sl_start+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        ldz #0
        lda [fp1],z
        jsr sb_putc
        jsr slice_step
        bra _sl
_sdone: plx
        pla
        jmp sb_take
_list:  lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        sta r0
        stx r0+1
_ll:    jsr slice_more
        bcs _ldone
        lda r2
        ldx r2+1
        sta p0
        stx p0+1
        lda sl_start
        sta t0
        lda sl_start+1
        sta t0+1
        jsr seq_get
        sta r1
        stx r1+1
        jsr list_append
        jsr slice_step
        bra _ll
_ldone: lda t6
        cmp #T_TUPLE
        bne +
        lda r0
        ldx r0+1
        jmp tuple_from_list
+       lda r0
        ldx r0+1
        rts

; slice_more - C clear while sl_start has not reached sl_stop (in the step's direction)
slice_more:
        ldq sl_start
        stq acc
        ldq sl_stop
        stq acc2
        jsr acc_sub                     ; start - stop
        lda acc+3
        bvc +
        eor #$80
+       bit sl_step+3
        bmi _neg
        ; step > 0: more while start < stop  (start - stop < 0)
        and #$80
        beq _no
        clc
        rts
_neg:   ; step < 0: more while start > stop
        and #$80
        bne _no
        lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        beq _no
        clc
        rts
_no:    sec
        rts

slice_step:
        ldq sl_start
        stq acc
        ldq sl_step
        stq acc2
        jsr acc_add
        ldq acc
        stq sl_start
        rts

;---------------------------------------------------------------------------------------
; ranges
;---------------------------------------------------------------------------------------
; range_new - acc = start, acc2 = stop, acc3 = step -> A/X
range_new:
        lda #16
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_RANGE
        jsr alloc
        ldz #4
        ldx #0
-       lda acc,x
        sta [p0],z
        inz
        inx
        cpx #12                         ; acc, acc2, acc3 are consecutive
        bne -
        lda p0
        ldx p0+1
        rts

; range_len - range r2 -> t5 = length (clamped to 16 bits)
range_len:
        lda r2
        ldx r2+1
        sta p3
        stx p3+1
        ldz #4
        ldx #0
-       lda [p3],z
        sta sl_start,x
        inz
        inx
        cpx #12
        bne -
        lda #0
        sta t5
        sta t5+1
-       jsr slice_more
        bcs +
        jsr slice_step
        inw t5
        lda t5+1
        cmp #$ff
        bne -
+       rts

; range_at - acc = index, range A/X -> A/X = start + index * step
range_at:
        sta p3
        stx p3+1
        ldz #16
        ldx #3
-       dez
        lda [p3],z
        sta acc2,x
        dex
        bpl -
        jsr acc_mul
        ldz #4
        ldx #0
-       lda [p3],z
        sta acc2,x
        inz
        inx
        cpx #4
        bne -
        jsr acc_add
        jmp int_new

; range_index - is acc3 in range A/X? -> A = 1 / 0
range_index:
        sta p3
        stx p3+1
        ldz #4
        ldx #0
-       lda [p3],z
        sta sl_start,x
        inz
        inx
        cpx #12
        bne -
        ; linear walk (ranges in "in" tests are short in practice)
-       jsr slice_more
        bcs _no
        ldq sl_start
        cpq acc3
        beq _yes
        jsr slice_step
        bra -
_yes:   lda #1
        rts
_no:    lda #0
        rts

;---------------------------------------------------------------------------------------
; iteration
;---------------------------------------------------------------------------------------
op_get_iter:
        #PEEK 0
        jsr get_iter
        #POKE 0
        jmp vm_loop

; iter_alloc - A = kind, r0 = seq -> A/X / p0 = a new iterator
iter_alloc:
        pha
        lda #20
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_ITER
        jsr alloc
        pla
        ldz #4
        sta [p0],z
        ldz #6
        lda r0
        sta [p0],z
        inz
        lda r0+1
        sta [p0],z
        ; a dict or set: note its size, to notice changes (methods.asm it_dpair)
        ldz #4
        lda [p0],z
        cmp #IT_DICT
        beq _view
        cmp #IT_ITEMS
        bcc _done
        cmp #IT_VALUES+1
        bcs _done
_view:  jsr iter_view_init
_done:  lda p0
        ldx p0+1
        rts

; get_iter - A/X iterable -> A/X iterator
get_iter:
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_ITER
        beq _self
        cmp #T_GEN                      ; a generator is its own iterator
        beq _self
        ldy #IT_SEQ
        cmp #T_LIST
        beq _new
        cmp #T_TUPLE
        beq _new
        ldy #IT_STR
        cmp #T_STR
        beq _new
        ldy #IT_DICT
        cmp #T_DICT
        beq _new
        cmp #T_SET                      ; (and T_FSET: the keys)
        bcs _new
        cmp #T_RANGE
        beq _range
        cmp #T_INST
        beq _inst
        ldy #IT_FILE
        cmp #T_FILE
        beq _new
        #RAISE EXC_TYPE, "object is not iterable"
_self:  lda r0
        ldx r0+1
        rts
_new:   tya
        jsr iter_alloc
        lda #0
        sta r0
        sta r0+1
        lda p0
        ldx p0+1
        rts
_range: lda #IT_RANGE
        jsr iter_alloc
        lda r0                          ; (after allocating: a collection clobbers p1-p3)
        sta p3
        lda r0+1
        sta p3+1
        ldz #4                          ; copy start, stop, step to +8..+19
-       lda [p3],z
        phz
        pha
        tza
        clc
        adc #4
        taz
        pla
        sta [p0],z
        plz
        inz
        cpz #16
        bne -
        lda p0
        ldx p0+1
        rts
_inst:  ; __iter__ returns the iterator; we drive it with __next__
        lda r0
        sta r2
        lda r0+1
        sta r2+1
        lda #S_ITER
        jsr inst_unary
        bcc +
        #RAISE EXC_TYPE, "object is not iterable"
+       sta r0
        stx r0+1
        lda #IT_INST
        jmp iter_alloc

op_for_iter:
        #PEEK 0
        jsr type_of
        cmp #T_GEN
        bne +
        jmp gen_for_iter                ; (runs it in the loop, as a call: gen.asm)
+       #PEEK 0
        jsr iter_next
        bcs _end
        #PUSH
        inw ip
        inw ip
        jmp vm_loop
_end:   #DROP 1
        #FETCHW
        sta ip
        stx ip+1
        jmp vm_loop

; iter_next - A/X iterator -> C clear and A/X = next value, or C set when exhausted
iter_next:
        sta p2
        stx p2+1
        ldz #0
        lda [p2],z
        cmp #T_GEN
        bne +
        lda p2
        ldx p2+1
        jmp gen_next_native
+       ldz #4
        lda [p2],z
        asl
        tax
        jmp (iter_tab,x)
iter_tab:
        .word it_seq, it_str, it_dict, it_range, it_items, it_values, it_enum
        .word it_zip, it_rev, it_inst, it_file, it_mapfilter, it_mapfilter
it_file:
        ldz #7
        lda [p2],z
        tax
        dez
        lda [p2],z
        jmp file_iter_next

; p2 = iterator: t0 = index (+8), p0 = seq (+6); C set when index >= len
it_index:
        ldz #6
        lda [p2],z
        sta p0
        inz
        lda [p2],z
        sta p0+1
        ldz #8
        lda [p2],z
        sta t0
        inz
        lda [p2],z
        sta t0+1
        ldz #4
        lda t0
        cmp [p0],z
        inz
        lda t0+1
        sbc [p0],z
        rts
; advance index
it_inc: ldz #8
        lda [p2],z
        clc
        adc #1
        sta [p2],z
        inz
        lda [p2],z
        adc #0
        sta [p2],z
        rts

it_seq: jsr it_index
        bcs _end
        jsr it_inc
        jsr seq_get
        clc
_end:   rts

it_rev: ; index counts down from len; stored as "items left"
        ldz #6
        lda [p2],z
        sta p0
        inz
        lda [p2],z
        sta p0+1
        ldz #8
        lda [p2],z
        inz
        ora [p2],z
        bne +
        sec
        rts
+       ldz #8
        sec
        lda [p2],z
        sbc #1
        sta [p2],z
        sta t0
        inz
        lda [p2],z
        sbc #0
        sta [p2],z
        sta t0+1
        jsr seq_get
        clc
        rts

it_str: jsr it_index
        bcs _end
        jsr it_inc
        clc
        lda p0
        adc #6
        sta fp0
        lda p0+1
        adc #0
        sta fp0+1
        clc
        lda fp0
        adc t0
        sta fp0
        lda fp0+1
        adc t0+1
        sta fp0+1
        lda #HEAP_BANK
        sta fp0+2
        lda #0
        sta fp0+3
        ldz #0
        lda [fp0],z
        jsr char_str
        clc
_end:   rts

; the dict iterators: it_dpair (overlay R, methods.asm) finds the pair
it_dict:
        jsr it_dpair
        bcs _end
        ldz #1
        lda [p1],z
        tax
        dez
        lda [p1],z
        clc
_end:   rts

it_values:
        jsr it_dpair
        bcs _end
        ldz #3
        lda [p1],z
        tax
        dez
        lda [p1],z
        clc
_end:   rts

it_items:
        jsr it_dpair
        bcs _end
        ; (key, value) tuple
        ldz #0
        lda [p1],z
        sta r2
        inz
        lda [p1],z
        sta r2+1
        inz
        lda [p1],z
        sta r3
        inz
        lda [p1],z
        sta r3+1
        jsr tuple2
        clc
_end:   rts

; tuple2 - (r2, r3) -> A/X
tuple2:
        lda #2
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        ldz #6
        lda r2
        sta [p0],z
        inz
        lda r2+1
        sta [p0],z
        inz
        lda r3
        sta [p0],z
        inz
        lda r3+1
        sta [p0],z
        lda #0
        sta r2
        sta r2+1
        sta r3
        sta r3+1
        lda p0
        ldx p0+1
        rts

it_range:
        ; cur +8, stop +12, step +16 -> sl_* for slice_more
        ldz #8
        ldx #0
-       lda [p2],z
        sta sl_start,x
        inz
        inx
        cpx #12
        bne -
        jsr slice_more
        bcs _end
        ldq sl_start                    ; the value (slice_step uses acc)
        stq it_val
        jsr slice_step
        ldz #8
        ldx #0
-       lda sl_start,x
        sta [p2],z
        inz
        inx
        cpx #4
        bne -
        ldq it_val
        stq acc
        jsr int_new
        clc
_end:   rts

it_enum:
        ; (count, next(inner))
        lda p2
        pha
        lda p2+1
        pha
        ldz #6
        lda [p2],z
        tay
        inz
        lda [p2],z
        tax
        tya
        jsr iter_next
        sta r3
        stx r3+1
        pla
        sta p2+1
        pla
        sta p2
        bcs _out
        ldz #8
        lda [p2],z
        sta acc
        inz
        lda [p2],z
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr it_inc
        lda r3
        pha
        lda r3+1
        pha
        jsr int_new
        sta r2
        stx r2+1
        pla
        sta r3+1
        pla
        sta r3
        jsr tuple2
        clc
_end:   rts
_out:   lda #0                          ; (r3 held no value: it must not stay a root)
        sta r3
        sta r3+1
        sec
        rts

it_zip:
        ; a tuple of next() of every inner iterator; stop at the first exhausted. The
        ; tuple being filled is on the value stack: an inner __next__ may run Python code
        ; (and collect garbage) between its items. (The tuple of iterators is the zip
        ; iterator's, which its caller keeps.)
        ldz #6
        lda [p2],z
        sta r0
        inz
        lda [p2],z
        sta r0+1
        lda r0
        ldx r0+1
        jsr seq_len
        lda t0
        sta nitems
        lda #0
        sta nitems+1
        lda r0
        pha
        lda r0+1
        pha
        jsr tuple_new
        #PUSH                           ; [result]
        pla
        sta r0+1
        pla
        sta r0
        lda #0
        sta t6
_each:  lda r0
        ldx r0+1
        jsr seq_len
        lda t6
        cmp t0
        bcs _done
        lda t6
        sta t2
        lda #0
        sta t2+1
        lda r0
        ldx r0+1
        jsr seq_get_t2
        ldy t6
        phy
        ldy r0
        phy
        ldy r0+1
        phy
        jsr iter_next
        ply
        sty r0+1
        ply
        sty r0
        ply
        sty t6
        bcs _end
        pha
        lda t6
        asl
        clc
        adc #6
        taz
        phx
        #PEEK 0                         ; the result tuple
        sta p1
        stx p1+1
        plx
        pla
        sta [p1],z
        inz
        txa
        sta [p1],z
        inc t6
        bra _each
_done:  #POP
        clc
        rts
_end:   #DROP 1
        sec
        rts

it_inst:
        ldz #6
        lda [p2],z
        sta r2
        inz
        lda [p2],z
        sta r2+1
        lda #<_next                     ; __next__, catching what it raises:
        ldx #>_next                     ; StopIteration ends the loop
        jsr try_call
        bcs _exc
        lda tc_c
        bne _bad
        lda tc_res
        ldx tc_res+1
        rts                             ; (C clear)
_exc:   lda cur_exc
        sta r2
        lda cur_exc+1
        sta r2+1
        lda #EXC_STOPITER
        jsr exc_is
        bcs +
        jmp throw                       ; (anything else: out to the enclosing handler)
+       jsr clear_exc                   ; exhausted (A/X = 0: no value)
        ldx #0
        sec
        rts
_next:  lda #S_NEXT
        jmp inst_unary
_bad:   #RAISE EXC_TYPE, "iterator has no __next__"

; clear_exc - forget the current exception (a native catcher handled it)
clear_exc:
        lda #0
        sta cur_exc
        sta cur_exc+1
        sta exc_ip_set
        jmp clear_rregs

;---------------------------------------------------------------------------------------
; try_call - A/X = a routine: call it under an error context of our own. C clear: it
; returned (tc_res = its A/X, tc_c = its carry); C set: it raised cur_exc, which the
; caller now handles (jmp throw passes it on). The caller's native state (its builtin's
; arguments, its tail: NATIVE_SAVE) and ip, vsp, vfp are as they were either way.
;---------------------------------------------------------------------------------------
tc_res:         .word 0
tc_c:           .byte 0
tc_vec:         .word 0
try_call:
        sta tc_vec
        stx tc_vec+1
        #NATIVE_SAVE
        lda ip+2
        pha
        lda ip+1
        pha
        lda ip
        pha
        lda vfp+1
        pha
        lda vfp
        pha
        lda vsp+1
        pha
        lda vsp
        pha
        lda err_vec+1
        pha
        lda err_vec
        pha
        lda err_sp+1
        pha
        lda err_sp
        pha
        tsx
        stx err_sp
        tsy
        sty err_sp+1
        lda #<_catch
        sta err_vec
        lda #>_catch
        sta err_vec+1
        jsr _go
        sta tc_res
        stx tc_res+1
        lda #0
        rol a
        sta tc_c
        lda #0                          ; it returned
        bra _restore
_go:    jmp (tc_vec)
_catch: lda #1                          ; (the CPU stack is back at our context)
_restore:
        sta tc_how
        pla
        sta err_sp
        pla
        sta err_sp+1
        pla
        sta err_vec
        pla
        sta err_vec+1
        pla
        sta vsp
        pla
        sta vsp+1
        pla
        sta vfp
        pla
        sta vfp+1
        pla
        sta ip
        pla
        sta ip+1
        pla
        sta ip+2
        #NATIVE_RESTORE
        lda tc_how
        lsr a
        rts
tc_how:         .byte 0

;---------------------------------------------------------------------------------------
; helpers for builtins
;---------------------------------------------------------------------------------------
; list_from_iterable - A/X -> A/X = a new list with all its items
list_from_iterable:
        jsr get_iter
        #PUSH                           ; keep the iterator alive
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH
_loop:  #PEEK 1
        jsr iter_next
        bcs _done
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        bra _loop
_done:  #POP
        pha
        phx
        #DROP 1
        lda #0
        sta r0
        sta r0+1
        sta r1
        sta r1+1
        plx
        pla
        rts

; tuple_from_list - A/X list -> A/X tuple with the same items
tuple_from_list:
        sta r2
        stx r2+1
        jsr seq_len
        lda t0
        sta nitems
        lda t0+1
        sta nitems+1
        jsr tuple_new
        sta r1
        stx r1+1
        lda #0
        sta t5
        sta t5+1
        lda r2
        ldx r2+1
        jsr tuple_fill
        lda #0
        sta r2
        sta r2+1
        lda r1
        ldx r1+1
        rts
