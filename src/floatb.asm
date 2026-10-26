;=======================================================================================
; Floats, tail B: the math module.
;=======================================================================================
xb_math_init:
        lda #F_PERM
        sta al_perm
        lda #14
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_CLASS
        jsr alloc
        sta math_mod
        stx math_mod+1
        lda #<S_MATH
        ldx #>S_MATH
        jsr sym_name
        ldz #4
        sta [p0],z
        inz
        txa
        sta [p0],z
        jsr dict_new
        sta r0
        stx r0+1
        lda math_mod
        sta p0
        lda math_mod+1
        sta p0+1
        ldz #8
        lda r0
        sta [p0],z
        inz
        lda r0+1
        sta [p0],z
        ldx #0                          ; the functions
_fn:    lda math_funcs+1,x
        cmp #$ff
        beq _consts
        phx
        lda math_funcs+2,x
        jsr builtin_obj
        sta r2
        stx r2+1
        plx
        phx
        lda math_funcs,x
        pha
        lda math_funcs+1,x
        tax
        pla
        jsr _set
        plx
        inx
        inx
        inx
        inx
        bra _fn
_consts:
        ldx #0
-       phx
        txa
        asl a
        asl a
        asl a
        tay
        ldx #0
-       lda fdoubles,y
        sta fdbl,x
        iny
        inx
        cpx #8
        bne -
        jsr float_new_dbl
        sta r2
        stx r2+1
        plx
        phx
        lda _cnames,x
        ldx #0
        jsr _set
        plx
        inx
        cpx #5
        bne --
        lda #0
        sta al_perm
        sta r0
        sta r0+1
        sta r2
        sta r2+1
        rts
_set:   jsr sym_name                    ; dict[name of symbol A/X] = r2
        sta r1
        stx r1+1
        jmp dict_set
_cnames:        .byte S_PI, S_E, S_TAU, S_INF, S_NAN     ; (fdoubles order)
        .include "gen/mathfuncs.asm"
        .cerror S_NAN > 255 || S_MATH > 255, "math symbols must be below 256"

; argument helpers: m_arg0 / m_arg1 -> fa (TypeError if not a number)
m_arg1: #ARG 1
        bra +
m_arg0: #ARG 0
+       jsr num_to_fa
        bcc +
        #RAISE EXC_TYPE, "must be a real number"
+       rts
m_args2:                                ; fa = arg 0, fb = arg 1
        #NARGS 2, 2
        jsr m_arg1
        ldx #FA
        ldy #FB
        jsr f_mov
        jmp m_arg0
m_one:  #NARGS 1, 1
        jmp m_arg0
m_domain:
        #RAISE EXC_VALUE, "math domain error"

xb_m_sqrt:
        jsr m_one
        jsr f_sqrt
        jmp float_new
xb_m_floor:
        #NARGS 1, 1
        #ARG 0
        jsr int_val
        bcs +
        jmp int_new
+       jsr m_arg0
        jsr f_floor
        jmp f_int_result
xb_m_ceil:
        #NARGS 1, 1
        #ARG 0
        jsr int_val
        bcs +
        jmp int_new
+       jsr m_arg0
        jsr f_ceil
        jmp f_int_result
xb_m_trunc:
        jsr m_one
        jsr f_trunc
        jmp f_int_result
xb_m_fabs:
        jsr m_one
        lda #0
        sta fa+F_SIGN
        jmp float_new
xb_m_isnan:
        lda #FC_NAN
        bra m_isclass
xb_m_isinf:
        lda #FC_INF
m_isclass:
        pha
        jsr m_one
        pla
        cmp fa+F_CLS
        beq +
        lda #0
        jmp bool_from_a
+       lda #1
        jmp bool_from_a
xb_m_isfinite:
        jsr m_one
        lda fa+F_CLS
        eor #FC_FIN
        cmp #1
        lda #0
        rol a
        eor #1
        jmp bool_from_a
xb_m_exp:
        jsr m_one
        jsr f_exp
        jmp float_new
xb_m_log:
        #NARGS 1, 2
        jsr m_arg0
        jsr m_log
        lda npos
        cmp #2
        bne +
        ldx #FA
        ldy #FH
        jsr f_mov
        jsr m_arg1
        jsr m_log
        ldx #FA
        ldy #FB
        jsr f_mov
        ldx #FH
        ldy #FA
        jsr f_mov
        jsr f_div
+       jmp float_new
m_log:  lda #0
        jmp f_log
xb_m_log10:
        jsr m_one
        lda #0
        jsr f_log
        ldx #FB
        lda #FK_INV_LN10
        jsr f_const
        jsr f_mul
        jmp float_new
xb_m_log2:
        jsr m_one
        lda #1
        jsr f_log
        jmp float_new
xb_m_pow:
        jsr m_args2
        jsr f_pow
        jmp float_new
xb_m_sin:
        jsr m_one
        lda #0
        jsr f_trig
        jmp float_new
xb_m_cos:
        jsr m_one
        lda #1
        jsr f_trig
        jmp float_new
xb_m_tan:
        jsr m_one
        ldx #FA
        ldy #FH
        jsr f_mov
        lda #0
        jsr f_trig
        ldx #FA
        ldy #FI
        jsr f_mov
        ldx #FH
        ldy #FA
        jsr f_mov
        lda #1
        jsr f_trig
        ldx #FA
        ldy #FB
        jsr f_mov
        ldx #FI
        ldy #FA
        jsr f_mov
        jsr f_div
        jmp float_new
xb_m_atan:
        jsr m_one
        jsr f_atan
        jmp float_new
xb_m_atan2:
        jsr m_args2
        jsr f_atan2
        jmp float_new
xb_m_asin:
        lda #0
        bra +
xb_m_acos:
        lda #1
+       pha
        jsr m_one
        jsr f_sqrt1m                    ; fb = sqrt(1 - x^2), fa = x
        pla
        beq +
        jsr f_swap
+       jsr f_atan2
        jmp float_new
xb_m_degrees:
        lda #FD_DEGREES
        bra +
xb_m_radians:
        lda #FD_RADIANS
+       pha
        jsr m_one
        pla
        jsr f_double_fb
        jsr f_mul
        jmp float_new
xb_m_hypot:
        jsr m_args2
        ldx #FB
        ldy #FC
        jsr f_mov
        ldx #FA
        ldy #FB
        jsr f_mov
        jsr f_mul                       ; x*x
        ldx #FA
        ldy #FD
        jsr f_mov
        ldx #FC
        ldy #FA
        jsr f_mov
        ldx #FC
        ldy #FB
        jsr f_mov
        jsr f_mul                       ; y*y
        ldx #FD
        ldy #FB
        jsr f_mov
        jsr f_add
        lda #0
        sta fa+F_SIGN
        jsr f_sqrt
        jmp float_new
xb_m_copysign:
        jsr m_args2
        lda fb+F_SIGN
        sta fa+F_SIGN
        jmp float_new
xb_m_fmod:
        jsr m_args2
        lda fa+F_CLS
        cmp #FC_INF
        beq _dom
        ldx #FB
        jsr m_zero
        bne +
        lda fb+F_CLS
        beq _dom
+       jsr f_fmod
        jmp float_new
_dom:   jmp m_domain

; f_double_fb - fb = the double fdoubles[A]
f_double_fb:
        asl a
        asl a
        asl a
        tay
        ldx #0
-       lda fdoubles,y
        sta fdbl,x
        iny
        inx
        cpx #8
        bne -
        ldx #FA
        ldy #FG
        jsr f_mov
        jsr f_unpack
        ldx #FA
        ldy #FB
        jsr f_mov
        ldx #FG
        ldy #FA
        jmp f_mov

;---------------------------------------------------------------------------------------
; pow(base, exp[, mod]) (builtins.asm)
;---------------------------------------------------------------------------------------
xb_bi_pow:
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
