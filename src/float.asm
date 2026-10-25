;=======================================================================================
; Floats in the interpreter: conversions, operators, repr/format, float(), round(),
; and the math module (with the transcendental functions, computed in the registers'
; 64-bit precision and rounded once at the end).
;=======================================================================================

; num_to_fa - A/X = int, bool or float -> fa; C set for anything else
num_to_fa:
        pha
        phx
        jsr type_of
        cmp #T_FLOAT
        bne _int
        plx
        pla
        jsr float_load
        jsr f_unpack
        clc
        rts
_int:   plx
        pla
        jsr int_val
        bcs +
        jsr f_from_int
        clc
+       rts

; num_to_fb - the same, into fb (fa is kept)
num_to_fb:
        pha
        phx
        ldx #FA
        ldy #FG
        jsr f_mov
        plx
        pla
        jsr num_to_fa
        php
        ldx #FA
        ldy #FB
        jsr f_mov
        ldx #FG
        ldy #FA
        jsr f_mov
        plp
        rts

; is_float - A/X -> C set for a float
is_float:
        jsr type_of
        cmp #T_FLOAT
        beq +
        clc
        rts
+       sec
        rts

; f_to_int - fa -> acc, truncated; C set if it is not finite or not a 32-bit int
f_to_int:
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
        lda fa+F_CLS
        bne _ovf
        ldx #FA
        jsr m_zero
        beq _ok
        lda fa+F_EXP+1
        bmi _ok                         ; |x| < 1
        bne _ovf
        lda fa+F_EXP
        cmp #32
        bcs _ovf
        ldq fa+F_MAN+4                  ; the top 32 bits >> (31 - exponent)
        stq acc
        sec
        lda #31
        sbc fa+F_EXP
        tax
        beq +
-       lsr acc+3
        ror acc+2
        ror acc+1
        ror acc
        dex
        bne -
+       bit acc+3                       ; 2^31 and up: only -2^31 fits
        bpl _sign
        lda fa+F_SIGN
        beq _ovf
        lda acc+3
        cmp #$80
        bne _ovf
        lda acc+2
        ora acc+1
        ora acc
        bne _ovf
_ok:    clc
        rts
_sign:  lda fa+F_SIGN
        beq _ok
        jsr acc_neg
        clc
        rts
_ovf:   sec
        rts

; f_int_result - fa (integral) -> A/X = int, or ValueError / OverflowError
f_int_result:
        lda fa+F_CLS
        cmp #FC_NAN
        bne +
        #RAISE EXC_VALUE, "cannot convert float NaN to integer"
+       jsr f_to_int
        bcc +
        #RAISE EXC_OVERFLOW, "int too large to convert (ints are 32-bit)"
+       jmp int_new

;---------------------------------------------------------------------------------------
; operators (from binop: r2 <bop> r3 where one side is a float, or int / int, or
; int ** negative int)
;---------------------------------------------------------------------------------------
float_binop:
        lda r3
        ldx r3+1
        jsr num_to_fa
        bcs _bad
        ldx #FA
        ldy #FB
        jsr f_mov
        lda r2
        ldx r2+1
        jsr num_to_fa
        bcs _bad
        lda bop
        cmp #BOP_IADD
        bne +
        lda #BOP_ADD
+       cmp #BOP_POW+1
        bcs _bad
        asl a
        tax
        jsr (fop_tab,x)
        jmp float_new
_bad:   jmp binop_inst
fop_tab:        .word f_add, f_sub, f_mul, f_div, f_divmod, f_modulo, f_pow
f_modulo:
        jsr f_divmod
        ldx #FE
        ldy #FA
        jmp f_mov

; float_order - r2 vs r3 (numbers, one a float) -> A = $ff, 0, 1, or 2 (unordered)
float_order:
        lda r2
        ldx r2+1
        jsr num_to_fa
        bcs _bad
        lda r3
        ldx r3+1
        jsr num_to_fb
        bcs _bad
        jmp f_cmp
_bad:   jmp raise_cmp_types

; float_eq - r2 == r3 (one a float) -> C set if equal
float_eq:
        lda r2
        ldx r2+1
        jsr num_to_fa
        bcs _ne
        lda r3
        ldx r3+1
        jsr num_to_fb
        bcs _ne
        jsr f_cmp
        cmp #0
        bne _ne
        sec
        rts
_ne:    clc
        rts

; float_unary - -x / +x of the float A/X (Y = opcode)
float_unary:
        cpy #OP_POS
        beq _done
        cpy #OP_NEG
        beq +
        jmp raise_unary_type
+       jsr float_load
        lda fdbl+7
        eor #$80
        sta fdbl+7
        jmp float_new_dbl
_done:  rts

; float_abs - abs() of the float A/X
float_abs:
        jsr float_load
        lda fdbl+7
        and #$7f
        sta fdbl+7
        jmp float_new_dbl

; float_type_code - C set if A is a float format type (for ints)
float_type_code:
        ora #$20
        ldx #3
-       cmp _codes,x
        beq +
        dex
        bpl -
        clc
        rts
+       sec
        rts
_codes: .text "feg%"

;---------------------------------------------------------------------------------------
; entries into the tails (floata.asm, floatb.asm): bring the tail in, then go
;---------------------------------------------------------------------------------------
TAILA   .macro target
        jsr need_a
        jmp \target
        .endm
TAILB   .macro target
        jsr need_b
        jmp \target
        .endm
repr_float:     #TAILA xa_repr_float
format_float:   #TAILA xa_format_float
bi_float:       #TAILA xa_bi_float
float_round:    #TAILA xa_float_round
float_hash:     #TAILA xa_float_hash
float_divmod:   #TAILA xa_float_divmod
math_init:      #TAILB xb_math_init
TAILF   .macro target
        jsr need_f
        jmp \target
        .endm
bi_open:        #TAILF xf_open
bi_file_read:   #TAILF xf_read
bi_file_readline: #TAILF xf_readline
bi_file_readlines: #TAILF xf_readlines
bi_file_write:  #TAILF xf_write
bi_file_close:  #TAILF xf_close
bi_file_enter:  #TAILF xf_enter
bi_file_exit:   #TAILF xf_exit
file_iter_next: #TAILF xf_iter_next
repr_file:      #TAILF xf_repr
files_reset:    #TAILF xf_reset
f_pow:          #TAILB xb_pow
bi_m_sqrt:    #TAILB xb_m_sqrt
bi_m_floor:   #TAILB xb_m_floor
bi_m_ceil:    #TAILB xb_m_ceil
bi_m_trunc:   #TAILB xb_m_trunc
bi_m_fabs:    #TAILB xb_m_fabs
bi_m_isnan:   #TAILB xb_m_isnan
bi_m_isinf:   #TAILB xb_m_isinf
bi_m_isfinite:#TAILB xb_m_isfinite
bi_m_exp:     #TAILB xb_m_exp
bi_m_log:     #TAILB xb_m_log
bi_m_log10:   #TAILB xb_m_log10
bi_m_log2:    #TAILB xb_m_log2
bi_m_pow:     #TAILB xb_m_pow
bi_m_sin:     #TAILB xb_m_sin
bi_m_cos:     #TAILB xb_m_cos
bi_m_tan:     #TAILB xb_m_tan
bi_m_asin:    #TAILB xb_m_asin
bi_m_acos:    #TAILB xb_m_acos
bi_m_atan:    #TAILB xb_m_atan
bi_m_atan2:   #TAILB xb_m_atan2
bi_m_degrees: #TAILB xb_m_degrees
bi_m_radians: #TAILB xb_m_radians
bi_m_hypot:   #TAILB xb_m_hypot
bi_m_copysign:#TAILB xb_m_copysign
bi_m_fmod:    #TAILB xb_m_fmod

; import_math - C set if A/X is the math module's symbol, A/X = the module
import_math:
        cmp #<S_MATH
        bne +
        cpx #>S_MATH
        bne +
        lda math_mod
        ldx math_mod+1
        sec
        rts
+       clc
        rts

