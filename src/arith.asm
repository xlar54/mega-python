;=======================================================================================
; Operators. Ints are 32-bit signed; results that do not fit raise OverflowError.
;=======================================================================================
BOP_ADD = 0
BOP_SUB = 1
BOP_MUL = 2
BOP_TRUEDIV = 3
BOP_FLOORDIV = 4
BOP_MOD = 5
BOP_POW = 6
BOP_LSHIFT = 7
BOP_RSHIFT = 8
BOP_AND = 9
BOP_OR = 10
BOP_XOR = 11
BOP_IADD = 12

bop:            .byte 0
bop_types:      .word 0                 ; type of r2, r3

;---------------------------------------------------------------------------------------
; fast paths for small ints, else the generic binop
;---------------------------------------------------------------------------------------
op_add:
        ldy #0
        lda (vsp),y
        lsr
        bcc _slow
        ldy #2
        lda (vsp),y
        lsr
        bcc _slow
        ; (2a+1) + (2b+1) - 1
        ldy #0
        lda (vsp),y
        and #$fe
        sta t0
        iny
        lda (vsp),y
        sta t0+1
        iny
        clc
        lda (vsp),y
        adc t0
        sta t1
        iny
        lda (vsp),y
        adc t0+1
        bvs _slow
        tax
        #DROP 1
        lda t1
        #POKE 0
        jmp vm_loop
_slow:  ldx #2*OP_ADD
        jmp op_binop

op_sub:
        ldy #0
        lda (vsp),y
        lsr
        bcc _slow
        ldy #2
        lda (vsp),y
        lsr
        bcc _slow
        ; (2a+1) - (2b+1) + 1 = (2a+1) - 2b
        ldy #0
        lda (vsp),y
        and #$fe
        sta t0
        iny
        lda (vsp),y
        sta t0+1
        iny
        sec
        lda (vsp),y
        sbc t0
        sta t1
        iny
        lda (vsp),y
        sbc t0+1
        bvs _slow
        tax
        #DROP 1
        lda t1
        #POKE 0
        jmp vm_loop
_slow:  ldx #2*OP_SUB
        jmp op_binop

; X = 2 * opcode
op_binop:
        txa
        lsr
        sec
        sbc #OP_ADD
        sta bop
        #PEEK 1
        sta r2
        stx r2+1
        #PEEK 0
        sta r3
        stx r3+1
        jsr binop
        sta t0
        stx t0+1
        #DROP 1
        lda t0
        ldx t0+1
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

;---------------------------------------------------------------------------------------
; binop - r2 <bop> r3 -> A/X
;---------------------------------------------------------------------------------------
binop:
        lda r2
        ldx r2+1
        jsr type_of
        sta bop_types
        lda r3
        ldx r3+1
        jsr type_of
        sta bop_types+1
        lda bop_types
        jsr is_inttype
        bcc _notint
        lda bop_types+1
        jsr is_inttype
        bcc _intother
        jmp int_binop
_intother:
        lda bop_types+1
        cmp #T_FLOAT
        bne +
        jmp float_binop
+       ; int * seq
        lda bop
        cmp #BOP_MUL
        bne binop_inst
        lda bop_types+1
        cmp #T_STR
        beq _swapmul
        cmp #T_LIST
        beq _swapmul
        cmp #T_TUPLE
        bne binop_inst
_swapmul:
        lda r2
        ldx r2+1
        ldy r3
        sty r2
        ldy r3+1
        sty r2+1
        sta r3
        stx r3+1
        lda bop_types
        ldx bop_types+1
        sta bop_types+1
        stx bop_types
        jmp seq_repeat
_notint:
        lda bop_types
        cmp #T_FLOAT
        bne +
        jmp float_binop
+       cmp #T_STR
        beq _str
        cmp #T_LIST
        beq _list
        cmp #T_TUPLE
        beq _tuple
        bra binop_inst
_str:   lda bop
        cmp #BOP_IADD
        beq +
        cmp #BOP_ADD
        bne _strmul
+       lda bop_types+1
        cmp #T_STR
        bne binop_inst
        jmp str_concat
_strmul:
        cmp #BOP_MUL
        bne _strmod
        lda bop_types+1
        jsr is_inttype
        bcc binop_inst
        jmp seq_repeat
_strmod:
        cmp #BOP_MOD
        bne binop_inst
        jmp str_percent
_list:  lda bop
        cmp #BOP_IADD
        bne +
        lda bop_types+1
        cmp #T_LIST
        beq _extend
        cmp #T_TUPLE
        beq _extend
        bra binop_inst
_extend:
        jmp list_iadd
+       cmp #BOP_ADD
        bne _seqmul
        lda bop_types+1
        cmp #T_LIST
        bne binop_inst
        jmp seq_concat
_tuple: lda bop
        cmp #BOP_ADD
        beq +
        cmp #BOP_IADD
        bne _seqmul
+       lda bop_types+1
        cmp #T_TUPLE
        bne binop_inst
        jmp seq_concat
_seqmul:
        cmp #BOP_MUL
        bne binop_inst
        lda bop_types+1
        jsr is_inttype
        bcc binop_inst
        jmp seq_repeat
binop_inst:
        ; user classes: __add__ etc. (then the reflected __radd__)
        lda bop_types
        cmp #T_INST
        bne _refl
        ldx bop
        lda bop_dunder,x
        ldx #0
        jsr inst_binop                  ; r2 op r3 via r2's method -> C clear if done
        bcs _refl
        rts
_refl:  lda bop_types+1
        cmp #T_INST
        bne _bad
        ldx bop
        lda bop_rdunder,x
        beq _bad
        ldx #0
        jsr inst_rbinop
        bcs _bad
        rts
_bad:   jmp raise_binop_types

bop_dunder:
        .byte S_ADD, S_SUB, S_MUL, S_TRUEDIV, S_FLOORDIV, S_MOD, S_POW, S_LSHIFT
        .byte S_RSHIFT, S_AND, S_OR, S_XOR, S_IADD
bop_rdunder:
        .byte S_RADD, S_RSUB, S_RMUL, 0, 0, 0, 0, 0, 0, 0, 0, 0, S_RADD
bop_names:
        .text "+", 0, "-", 0, "*", 0, "/", 0, "//", 0, "%", 0, "**", 0, "<<", 0
        .text ">>", 0, "&", 0, "|", 0, "^", 0, "+=", 0
bop_name_ofs:
        .byte 0, 2, 4, 6, 8, 11, 13, 16, 19, 22, 24, 26, 28

;---------------------------------------------------------------------------------------
; integer operators: acc = r2, acc2 = r3
;---------------------------------------------------------------------------------------
int_binop:
        lda r3
        ldx r3+1
        jsr int_val
        ldq acc
        stq acc2
        lda r2
        ldx r2+1
        jsr int_val
        lda bop
        asl
        tax
        jmp (int_op_tab,x)
int_op_tab:
        .word iop_add, iop_sub, iop_mul, iop_truediv, iop_floordiv, iop_mod
        .word iop_pow, iop_lshift, iop_rshift, iop_and, iop_or, iop_xor, iop_add

; result in acc -> A/X ref
iop_done:
        jmp int_new

iop_add:
        jsr acc_add
        bvs int_overflow
        bra iop_done
iop_sub:
        jsr acc_sub
        bvs int_overflow
        bra iop_done
iop_mul:
        jsr acc_mul
        bcs int_overflow
        bra iop_done
iop_truediv:
        lda acc2                        ; int / 0 (CPython's message differs from 1.0 / 0)
        ora acc2+1
        ora acc2+2
        ora acc2+3
        bne +
        #RAISE EXC_ZERODIV, "division by zero"
+       jmp float_binop
iop_floordiv:
        jsr acc_divmod
        bra iop_done
iop_mod:
        jsr acc_divmod
        ldq acc3
        stq acc
        bra iop_done
iop_pow:
        bit acc2+3
        bpl +
        jmp float_binop                 ; a negative power: a float
+       ; acc3 = base, acc = 1; square-and-multiply on acc2
        ldq acc
        stq acc3
        lda #1
        sta acc
        lda #0
        sta acc+1
        sta acc+2
        sta acc+3
_loop:  lda acc2
        ora acc2+1
        ora acc2+2
        ora acc2+3
        beq iop_done
        lda acc2
        and #1
        beq _sq
        ; acc *= acc3
        ldq acc2
        pha
        phx
        phy
        phz
        ldq acc3
        stq acc2
        jsr acc_mul
        plz
        ply
        plx
        pla
        stq acc2
        bcs int_overflow
_sq:    lsr acc2+3
        ror acc2+2
        ror acc2+1
        ror acc2
        lda acc2
        ora acc2+1
        ora acc2+2
        ora acc2+3
        beq iop_done
        ; acc3 *= acc3
        ldq acc
        pha
        phx
        phy
        phz
        ldq acc2
        pha
        phx
        phy
        phz
        ldq acc3
        stq acc
        stq acc2
        jsr acc_mul
        php
        ldq acc
        stq acc3
        plp
        plz
        ply
        plx
        pla
        stq acc2
        plz
        ply
        plx
        pla
        stq acc
        bcs int_overflow
        bra _loop

int_overflow:
        #RAISE EXC_OVERFLOW, "integer overflow (ints are 32-bit)"

iop_lshift:
        jsr shift_count
_l:     dex
        bmi iop_done
        lda acc+3                       ; bits 31 and 30 must agree before each shift
        and #$c0
        beq +
        cmp #$c0
        bne int_overflow
+       asl acc
        rol acc+1
        rol acc+2
        rol acc+3
        bra _l
iop_rshift:
        jsr shift_count
-       dex
        bmi iop_done
        lda acc+3
        asr
        sta acc+3
        ror acc+2
        ror acc+1
        ror acc
        bra -
; X = shift count (acc2), 0-31 (more than 31 saturates), negative = ValueError
shift_count:
        lda acc+3
        sta acc3+3                      ; the original sign
        bit acc2+3
        bpl +
        #RAISE EXC_VALUE, "negative shift count"
+       lda acc2+3
        ora acc2+2
        ora acc2+1
        bne _big
        ldx acc2
        cpx #32
        bcc +
_big:   ldx #32
+       rts

iop_and:
        lda acc
        and acc2
        sta acc
        lda acc+1
        and acc2+1
        sta acc+1
        lda acc+2
        and acc2+2
        sta acc+2
        lda acc+3
        and acc2+3
        sta acc+3
        jmp iop_bool
iop_or:
        lda acc
        ora acc2
        sta acc
        lda acc+1
        ora acc2+1
        sta acc+1
        lda acc+2
        ora acc2+2
        sta acc+2
        lda acc+3
        ora acc2+3
        sta acc+3
        jmp iop_bool
iop_xor:
        lda acc
        eor acc2
        sta acc
        lda acc+1
        eor acc2+1
        sta acc+1
        lda acc+2
        eor acc2+2
        sta acc+2
        lda acc+3
        eor acc2+3
        sta acc+3
; bool & bool stays a bool
iop_bool:
        lda bop_types
        cmp #T_BOOL
        bne +
        lda bop_types+1
        cmp #T_BOOL
        bne +
        lda acc
        jmp bool_from_a
+       jmp int_new

; A = 0 / non-zero -> A/X = False / True
bool_from_a:
        ldx #0
        cmp #0
        beq +
        lda #R_TRUE
        rts
+       lda #R_FALSE
        rts

; acc += acc2, V set on signed overflow
acc_add:
        clc
        lda acc
        adc acc2
        sta acc
        lda acc+1
        adc acc2+1
        sta acc+1
        lda acc+2
        adc acc2+2
        sta acc+2
        lda acc+3
        adc acc2+3
        sta acc+3
        rts
; acc -= acc2, V set on signed overflow
acc_sub:
        sec
        lda acc
        sbc acc2
        sta acc
        lda acc+1
        sbc acc2+1
        sta acc+1
        lda acc+2
        sbc acc2+2
        sta acc+2
        lda acc+3
        sbc acc2+3
        sta acc+3
        rts

; acc2 = -acc2
acc2_neg:
        sec
        lda #0
        sbc acc2
        sta acc2
        lda #0
        sbc acc2+1
        sta acc2+1
        lda #0
        sbc acc2+2
        sta acc2+2
        lda #0
        sbc acc2+3
        sta acc2+3
        rts

; acc *= acc2 (signed), C set on overflow
mul_sign:       .byte 0
acc_mul:
        lda acc+3
        eor acc2+3
        sta mul_sign
        bit acc+3
        bpl +
        jsr acc_neg
+       bit acc2+3
        bpl +
        jsr acc2_neg
+       ldq acc
        stq MULTINA
        ldq acc2
        stq MULTINB
        ldq MULTOUT
        stq acc
        lda MULTOUT+4
        ora MULTOUT+5
        ora MULTOUT+6
        ora MULTOUT+7
        bne _ovf
        bit acc+3
        bpl _ok
        ; only -2^31 itself fits
        bit mul_sign
        bpl _ovf
        lda acc+3
        cmp #$80
        bne _ovf
        lda acc+2
        ora acc+1
        ora acc
        bne _ovf
_ok:    bit mul_sign
        bpl +
        jsr acc_neg
+       clc
        rts
_ovf:   sec
        rts

; Python floor division: acc = acc // acc2, acc3 = acc % acc2
div_sa:         .byte 0                 ; sign of the dividend
div_sb:         .byte 0                 ; sign of the divisor
div_b:          .dword 0                ; |divisor|
acc_divmod:
        lda acc2
        ora acc2+1
        ora acc2+2
        ora acc2+3
        bne +
        #RAISE EXC_ZERODIV, "integer division or modulo by zero"
+       lda acc+3
        sta div_sa
        lda acc2+3
        sta div_sb
        bit acc+3
        bpl +
        jsr acc_neg
+       bit acc2+3
        bpl +
        jsr acc2_neg
+       ldq acc2
        stq div_b
        ldq acc
        stq MULTINA
        ldq acc2
        stq MULTINB
-       bit MATHBUSY
        bmi -
        ldq DIVOUT+4
        stq acc3                        ; q0
        stq MULTINA
        ; r0 = |a| - q0 * |b|
        sec
        lda acc
        sbc MULTOUT
        sta acc
        lda acc+1
        sbc MULTOUT+1
        sta acc+1
        lda acc+2
        sbc MULTOUT+2
        sta acc+2
        lda acc+3
        sbc MULTOUT+3
        sta acc+3
        ; acc = r0, acc3 = q0
        lda div_sa
        eor div_sb
        bmi _diff
        ; same signs: q = q0, r = r0 with the divisor's sign
        bit div_sb
        bpl _swap
        jsr acc_neg
        bra _swap
_diff:  lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        bne _rem
        ; exact: q = -q0, r = 0
        ldq acc3
        stq acc2
        jsr acc2_neg
        ldq acc2
        stq acc3
        bra _swap
_rem:   ; q = -q0 - 1, r = |b| - r0 with the divisor's sign
        ldq acc
        pha
        phx
        phy
        phz
        ldq acc3
        stq acc2
        jsr acc2_neg
        sec
        lda acc2
        sbc #1
        sta acc2
        lda acc2+1
        sbc #0
        sta acc2+1
        lda acc2+2
        sbc #0
        sta acc2+2
        lda acc2+3
        sbc #0
        sta acc2+3
        ldq acc2
        stq acc3                        ; q
        ldq div_b                       ; |b|
        stq acc
        plz
        ply
        plx
        pla
        stq acc2                        ; r0
        jsr acc_sub                     ; |b| - r0
        bit div_sb
        bpl _swap
        jsr acc_neg
_swap:  ; acc = r, acc3 = q -> acc = q, acc3 = r
        ldq acc
        pha
        phx
        phy
        phz
        ldq acc3
        stq acc
        plz
        ply
        plx
        pla
        stq acc3
        rts

;---------------------------------------------------------------------------------------
; sequences
;---------------------------------------------------------------------------------------
; str_concat: r2 + r3
str_concat:
        lda r2
        ldx r2+1
        jsr str_info
        lda str_len
        sta t3
        lda str_len+1
        sta t3+1
        lda r3
        ldx r3+1
        jsr str_info
        clc
        lda str_len
        adc t3
        sta str_len
        lda str_len+1
        adc t3+1
        sta str_len+1
        bcc +
        jmp raise_memory
+       jsr str_alloc
        sta r1
        stx r1+1
        ; copy both halves
        lda #6
        sta t5
        lda #0
        sta t5+1
        lda r2
        ldx r2+1
        jsr _part
        lda r3
        ldx r3+1
        jsr _part
        lda r1
        ldx r1+1
        rts
; append string A/X into r1 at offset t5
_part:  jsr str_info
        lda str_len
        ora str_len+1
        beq +
        clc
        lda r1
        adc t5
        sta fp1
        lda r1+1
        adc t5+1
        sta fp1+1
        lda #HEAP_BANK
        sta fp1+2
        lda #0
        sta fp1+3
        lda str_len
        sta t0
        lda str_len+1
        sta t0+1
        clc
        lda t5
        adc str_len
        sta t5
        lda t5+1
        adc str_len+1
        sta t5+1
        jmp dma_copy
+       rts

; seq_concat: list + list or tuple + tuple
seq_concat:
        lda r2
        ldx r2+1
        jsr seq_len
        lda t0
        sta t3
        lda t0+1
        sta t3+1
        lda r3
        ldx r3+1
        jsr seq_len
        clc
        lda t0
        adc t3
        sta nitems
        lda t0+1
        adc t3+1
        sta nitems+1
        lda bop_types
        cmp #T_TUPLE
        beq _tup
        jsr list_new
        sta r1
        stx r1+1
        lda r1
        sta r0
        lda r1+1
        sta r0+1
        lda r2
        ldx r2+1
        jsr list_extend_r0
        lda r3
        ldx r3+1
        jsr list_extend_r0
        lda r0
        ldx r0+1
        rts
_tup:   jsr tuple_new
        sta r1
        stx r1+1
        lda #0
        sta t5
        sta t5+1
        lda r2
        ldx r2+1
        jsr tuple_fill
        lda r3
        ldx r3+1
        jsr tuple_fill
        lda r1
        ldx r1+1
        rts

; tuple_fill - copy the items of tuple/list A/X into tuple r1 from index t5
tuple_fill:
        sta r0
        stx r0+1
        jsr seq_len
        lda t0
        sta t6
        lda t0+1
        sta t6+1
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp t6
        bne +
        lda t2+1
        cmp t6+1
        beq _done
+       lda r0
        ldx r0+1
        jsr seq_get_t2
        pha
        phx
        lda t5
        asl
        sta t0
        lda t5+1
        rol
        sta t0+1
        clc
        lda r1
        adc t0
        sta p1
        lda r1+1
        adc t0+1
        sta p1+1
        ldz #7
        pla
        sta [p1],z
        dez
        pla
        sta [p1],z
        inw t2
        inw t5
        bra -
_done:  lda #0
        sta r0
        sta r0+1
        rts

; list_extend_r0 - append every item of list/tuple A/X to list r0
list_extend_r0:
        sta groot+2
        stx groot+3
        jsr seq_len
        lda t0
        pha
        lda t0+1
        pha
        lda #0
        sta t6
        sta t6+1
_loop:  pla
        sta t7+1
        pla
        sta t7
        lda t6
        cmp t7
        bne +
        lda t6+1
        cmp t7+1
        beq _done
+       lda t7
        pha
        lda t7+1
        pha
        lda t6
        sta t2
        lda t6+1
        sta t2+1
        lda groot+2
        ldx groot+3
        jsr seq_get_t2
        sta r1
        stx r1+1
        lda t6
        pha
        lda t6+1
        pha
        jsr list_append
        pla
        sta t6+1
        pla
        sta t6
        inw t6
        bra _loop
_done:  lda #0
        sta groot+2
        sta groot+3
        sta r1
        sta r1+1
        rts

; list += iterable (in place): r2 = list, r3 = list/tuple
list_iadd:
        lda r2
        sta r0
        lda r2+1
        sta r0+1
        lda r3
        ldx r3+1
        jsr list_extend_r0
        lda r2
        ldx r2+1
        rts

; seq_repeat: r2 (str/list/tuple) * r3 (int)
seq_repeat:
        lda r3
        ldx r3+1
        jsr int_val
        bit acc+3
        bmi _zero
        lda acc+2
        ora acc+3
        bne _mem
        lda acc
        sta t6
        lda acc+1
        sta t6+1
        lda bop_types
        cmp #T_STR
        bne _seq
        ; string: build in the string builder
        lda sbp
        pha
        lda sbp+1
        pha
-       lda t6
        ora t6+1
        beq +
        lda r2
        ldx r2+1
        jsr sb_put_str
        dew t6
        bra -
+       plx
        pla
        jmp sb_take
_zero:  lda #0
        sta t6
        sta t6+1
        lda bop_types
        cmp #T_STR
        bne _seq
        lda #0
        sta str_len
        sta str_len+1
        jmp str_alloc
_mem:   jmp raise_memory
_seq:   ; list or tuple: make a list of len * n, then convert for tuples
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        sta r1
        stx r1+1
        lda r1
        sta r0
        lda r1+1
        sta r0+1
-       lda t6
        ora t6+1
        beq +
        lda t6
        pha
        lda t6+1
        pha
        lda r2
        ldx r2+1
        jsr list_extend_r0
        pla
        sta t6+1
        pla
        sta t6
        dew t6
        bra -
+       lda bop_types
        cmp #T_TUPLE
        bne +
        lda r0
        ldx r0+1
        jmp tuple_from_list
+       lda r0
        ldx r0+1
        rts

;---------------------------------------------------------------------------------------
; comparisons
;---------------------------------------------------------------------------------------
op_lt:
        ldy #0
        lda (vsp),y
        lsr
        bcc _slow
        ldy #2
        lda (vsp),y
        lsr
        bcc _slow
        ; signed 16-bit compare of the refs: a < b
        ldy #2
        lda (vsp),y
        ldy #0
        cmp (vsp),y
        ldy #3
        lda (vsp),y
        ldy #1
        sbc (vsp),y
        bvc +
        eor #$80
+       bmi _true                       ; N set: a < b
        lda #R_FALSE
        bra +
_true:  lda #R_TRUE
+       ldx #0
        #DROP 1
        #POKE 0
        jmp vm_loop
_slow:  ldx #2*OP_LT
        ; fall through
op_cmp:
        txa
        lsr
        sec
        sbc #OP_EQ
        sta bop
        #PEEK 1
        sta r2
        stx r2+1
        #PEEK 0
        sta r3
        stx r3+1
        jsr compare
        jsr bool_from_a
        sta t0
        #DROP 1
        lda t0
        ldx #0
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

; compare - r2 <cmp bop> r3 (bop 0 ==, 1 !=, 2 <, 3 >, 4 <=, 5 >=) -> A = 1 true / 0
compare:
        lda bop
        cmp #2
        bcs _order
        jsr obj_eq
        lda #0
        rol
        ldx bop
        beq +
        eor #1
+       rts
_order: ; an instance: its own __lt__ / __gt__ / __le__ / __ge__, else the other side's
        ; reflected one (as Python does: a >= b tries a.__ge__(b), then b.__le__(a))
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_INST
        bne _refl
        ldx bop
        lda cmp_dunder-2,x
        ldx #0
        jsr inst_binop
        bcs _refl
        jmp obj_truth
_refl:  lda r3
        ldx r3+1
        jsr type_of
        cmp #T_INST
        bne _3way
        ldx bop
        lda cmp_rdunder-2,x
        ldx #0
        jsr inst_rbinop
        bcs _3way
        jmp obj_truth
_3way:  jsr obj_cmp                     ; -> A = $ff less, 0 equal, 1 greater
        cmp #2
        beq _f                          ; (unordered: a nan)
        ldx bop
        cpx #2
        bne +
        cmp #$ff
        beq _t
        bra _f
+       cpx #3
        bne +
        cmp #1
        beq _t
        bra _f
+       cpx #4
        bne +
        cmp #1
        bne _t
        bra _f
+       cmp #$ff                        ; >=
        bne _t
_f:     lda #0
        rts
_t:     lda #1
        rts
cmp_dunder:     .byte S_LT, S_GT, S_LE, S_GE        ; < > <= >=
cmp_rdunder:    .byte S_GT, S_LT, S_GE, S_LE        ; (the reflected ones)

; obj_cmp - order r2 vs r3 -> A = $ff (less), 0, 1 (greater)
obj_cmp:
        lda r2
        ldx r2+1
        jsr type_of
        sta t2
        lda r3
        ldx r3+1
        jsr type_of
        sta t2+1
        lda t2
        jsr is_inttype
        bcc _notint
        lda t2+1
        jsr is_inttype
        bcc _flt
        lda r3
        ldx r3+1
        jsr int_val
        ldq acc
        stq acc2
        lda r2
        ldx r2+1
        jsr int_val
        jsr acc_sub
        ; sign of a - b (with overflow correction)
        lda acc+3
        bvc +
        eor #$80
        ora #1                          ; not zero
        bra _sign
+       ora acc+2
        ora acc+1
        ora acc
        beq _eq
        lda acc+3
        bvc _sign
        eor #$80
_sign:  bmi _lt
        lda #1
        rts
_lt:    lda #$ff
        rts
_eq:    lda #0
        rts
_notint:
        lda t2
        cmp #T_FLOAT
        beq _flt
        cmp t2+1
        bne _bad
        cmp #T_STR
        beq _str
        cmp #T_LIST
        beq _seq
        cmp #T_TUPLE
        beq _seq
        cmp #T_INST
        bne _bad
        jmp inst_cmp
_bad:   jmp raise_cmp_types
_flt:   jmp float_order
_str:   lda r2
        ldx r2+1
        jsr str_info
        lda fp0
        sta fp1
        lda fp0+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        lda str_len
        sta t3
        lda str_len+1
        sta t3+1
        lda r3
        ldx r3+1
        jsr str_info                    ; fp0 = b chars, str_len = len b
-       lda t3
        ora t3+1
        bne +
        lda str_len                     ; a ran out
        ora str_len+1
        beq _eq
        bra _lt
+       lda str_len
        ora str_len+1
        bne +
        lda #1                          ; b ran out
        rts
+       ldz #0
        lda [fp1],z
        cmp [fp0],z
        bcc _lt
        bne _gt
        inw fp0
        inw fp1
        dew t3
        dew str_len
        bra -
_gt:    lda #1
        rts
_seq:   ; lexicographic: first unequal item decides, else the lengths
        jsr seq_info2
        lda #0
        sta t2
        sta t2+1
_item:  lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _lens
+       lda t2
        cmp t1
        bne +
        lda t2+1
        cmp t1+1
        beq _lens
+       ; save state, compare items with == then order
        ldx #0
-       lda r2,x
        pha
        inx
        cpx #4
        bne -
        lda t0
        pha
        lda t0+1
        pha
        lda t1
        pha
        lda t1+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        lda r2
        ldx r2+1
        jsr seq_get_t2
        pha
        phx
        lda r3
        ldx r3+1
        jsr seq_get_t2
        sta r3
        stx r3+1
        plx
        pla
        sta r2
        stx r2+1
        jsr obj_eq
        lda #0
        bcs +
        jsr obj_cmp
+       sta t7
        pla
        sta t2+1
        pla
        sta t2
        pla
        sta t1+1
        pla
        sta t1
        pla
        sta t0+1
        pla
        sta t0
        ldx #3
-       pla
        sta r2,x
        dex
        bpl -
        lda t7
        bne _done
        inw t2
        bra _item
_lens:  ; compare t0 (len a) with t1 (len b)
        lda t0+1
        cmp t1+1
        bne +
        lda t0
        cmp t1
        beq _eq2
+       bcc _lt2
        lda #1
_done:  rts
_lt2:   lda #$ff
        rts
_eq2:   lda #0
        rts

op_is:
        txa
        lsr
        sta t1                          ; OP_IS or OP_IS_NOT
        ldy #0
        lda (vsp),y
        ldy #2
        cmp (vsp),y
        bne _ne
        ldy #1
        lda (vsp),y
        ldy #3
        cmp (vsp),y
        bne _ne
        lda #1
        bra +
_ne:    lda #0
+       ldx t1
        cpx #OP_IS
        beq +
        eor #1
+       jsr bool_from_a
        sta t0
        #DROP 1
        lda t0
        ldx #0
        #POKE 0
        jmp vm_loop

op_in:
        txa
        lsr
        sta t6                          ; OP_IN or OP_NOT_IN
        #PEEK 1
        sta r2
        stx r2+1
        #PEEK 0
        sta r3
        stx r3+1
        jsr contains                    ; r2 in r3 -> A
        ldx t6
        cpx #OP_IN
        beq +
        eor #1
+       jsr bool_from_a
        sta t0
        #DROP 1
        lda t0
        ldx #0
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

; contains - r2 in r3 -> A = 1 / 0
contains:
        lda r3
        ldx r3+1
        jsr type_of
        cmp #T_LIST
        beq _seq
        cmp #T_TUPLE
        beq _seq
        cmp #T_DICT
        beq _dict
        cmp #T_STR
        beq _str
        cmp #T_RANGE
        beq _range
        ; anything iterable: walk it
        lda r3
        ldx r3+1
        jsr list_from_iterable
        sta r3
        stx r3+1
_seq:   lda r3
        ldx r3+1
        jsr seq_len
        lda t0
        sta t5
        lda t0+1
        sta t5+1
        lda #0
        sta t6+1                        ; t6 holds the IN/NOT_IN op: keep t6 lo
        sta t4
        sta t4+1
-       lda t4
        cmp t5
        bne +
        lda t4+1
        cmp t5+1
        bne +
        lda #0
        rts
+       lda r2
        pha
        lda r2+1
        pha
        lda r3
        pha
        lda r3+1
        pha
        lda t4
        pha
        lda t4+1
        pha
        lda t5
        pha
        lda t5+1
        pha
        lda t4
        sta t2
        lda t4+1
        sta t2+1
        lda r3
        ldx r3+1
        jsr seq_get_t2
        sta r3
        stx r3+1
        jsr obj_eq
        pla
        sta t5+1
        pla
        sta t5
        pla
        sta t4+1
        pla
        sta t4
        pla
        sta r3+1
        pla
        sta r3
        pla
        sta r2+1
        pla
        sta r2
        bcs _yes
        inw t4
        bra -
_yes:   lda #1
        rts
_dict:  lda r3
        sta r0
        lda r3+1
        sta r0+1
        lda r2
        sta r1
        lda r2+1
        sta r1+1
        jsr dict_find
        lda #0
        bcs +
        lda #1
+       rts
_str:   lda r2
        ldx r2+1
        jsr type_of
        cmp #T_STR
        beq +
        #RAISE EXC_TYPE, "'in <string>' requires string as left operand"
+       jsr str_find                    ; r3.find(r2) -> C clear if found
        lda #0
        bcs +
        lda #1
+       rts
_range: ; start <= x < stop (step 1) or the general test
        lda r2
        ldx r2+1
        jsr int_val
        bcc +
        lda #0
        rts
+       ldq acc
        stq acc3
        lda r3
        ldx r3+1
        jsr range_index                 ; acc3 in range r3 -> A
        rts

;---------------------------------------------------------------------------------------
; unary operators
;---------------------------------------------------------------------------------------
op_not:
        #PEEK 0
        jsr obj_truth
        eor #1
        jsr bool_from_a
        #POKE 0
        jmp vm_loop

op_unary:
        txa
        lsr
        sta t6
        #PEEK 0
        sta r2
        stx r2+1
        jsr int_val
        bcc _int
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_FLOAT
        bne +
        lda r2
        ldx r2+1
        ldy t6
        jsr float_unary
        #POKE 0
        jsr clear_rregs
        jmp vm_loop
+       cmp #T_INST
        bne _bad
        ldx t6
        lda #S_NEG
        cpx #OP_NEG
        beq +
        lda #S_POS
        cpx #OP_POS
        beq +
        lda #S_INVERT
+       ldx #0
        jsr inst_unary
        bcs _bad
        #POKE 0
        jsr clear_rregs
        jmp vm_loop
_bad:   jmp raise_unary_type
_int:   lda t6
        cmp #OP_POS
        beq _done
        cmp #OP_NEG
        bne _inv
        lda acc+3
        sta t0
        jsr acc_neg
        lda acc+3
        and t0
        bmi _ovf                        ; -(-2^31)
        bra _done
_inv:   ; ~x = -x - 1
        lda acc
        eor #$ff
        sta acc
        lda acc+1
        eor #$ff
        sta acc+1
        lda acc+2
        eor #$ff
        sta acc+2
        lda acc+3
        eor #$ff
        sta acc+3
_done:  jsr int_new
        #POKE 0
        jsr clear_rregs
        jmp vm_loop
_ovf:   jmp int_overflow
