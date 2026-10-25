;=======================================================================================
; Floats: exp, log, sin, cos, atan, atan2, pow. Argument reduction, then a power series
; in the registers' 64-bit precision (using the reciprocals 1/k from fconst).
;=======================================================================================
ft_mode:        .byte 0                 ; 0 exp, 1 sin/cos, 2 log/atan (see f_series)
ft_k:           .byte 0
ft_n:           .byte 0
ft_alt:         .byte 0                 ; $80: alternate the signs
ft_sign:        .byte 0
ft_flag:        .byte 0
ft_ys:          .byte 0                 ; atan2: the signs of y and x
ft_xs:          .byte 0

; f_const - register X = the extended constant A (FK_*)
f_const:
        phx
        sta ff_i                        ; ff_i = fconst + 10 * A
        lda #0
        sta ff_i+1
        asl ff_i
        rol ff_i+1
        lda ff_i
        ldy ff_i+1
        asl ff_i
        rol ff_i+1
        asl ff_i
        rol ff_i+1
        clc
        adc ff_i
        sta ff_i
        tya
        adc ff_i+1
        sta ff_i+1
        clc
        lda ff_i
        adc #<fconst
        sta ff_i
        lda ff_i+1
        adc #>fconst
        sta ff_i+1
        plx
        lda #0
        sta fa+F_CLS,x
        sta fa+F_SIGN,x
        ldy #0
-       lda (ff_i),y
        sta fa+F_EXP,x
        inx
        iny
        cpy #10
        bne -
        rts

; small helpers: fa = fa op register Y
f_mul_y:
        jsr f_yfb
        jmp f_mul
f_add_y:
        jsr f_yfb
        jmp f_add
f_sub_y:
        jsr f_yfb
        jmp f_sub
f_yfb:  tya
        tax
        ldy #FB
        jmp f_mov
; fa = register X
f_get:  ldy #FA
        jmp f_mov
; register Y = fa
f_put:  ldx #FA
        jmp f_mov

;---------------------------------------------------------------------------------------
; f_series - fa = sum of the series with the first term in fe and the variable in fc:
;   mode 0: term *= x / k                 (k = ft_k, ft_k + 1, ...)
;   mode 1: term *= x / (k (k + 1))       (k += 2)
;   mode 2: p *= x; term = p / k          (k += 2)
; ft_n terms after the first, signs alternating with ft_alt = $80.
;---------------------------------------------------------------------------------------
f_series:
        ldx #FE
        ldy #FG
        jsr f_mov                       ; fg = sum
        ldx #FE
        ldy #FF
        jsr f_mov                       ; ff = p (the term itself for modes 0, 1)
_loop:  ldx #FF
        jsr f_get
        ldy #FC
        jsr f_mul_y
        lda ft_alt
        eor fa+F_SIGN
        sta fa+F_SIGN
        lda ft_mode
        cmp #2
        bne +
        ldy #FF
        jsr f_put
+       lda ft_k
        jsr _recip
        lda ft_mode
        cmp #1
        bne +
        lda ft_k
        inc a
        jsr _recip
+       lda ft_mode
        cmp #2
        beq +
        ldy #FF
        jsr f_put
+       ldy #FG
        jsr f_add_y
        ldy #FG
        jsr f_put
        lda ft_k
        inc a
        ldx ft_mode
        beq +
        inc a
+       sta ft_k
        dec ft_n
        bne _loop
        ldx #FG
        jmp f_get
_recip: dec a                           ; fa *= 1/A
        ldx #FB
        jsr f_const
        jmp f_mul

; f_round_int - fa = the integer nearest fa (halves away from zero), acc = it as an
; int; C set if it does not fit
f_round_int:
        ldx #FB
        lda #$ff
        jsr f_one
        lda fa+F_SIGN
        sta fb+F_SIGN
        jsr f_add
        jsr f_trunc
        jmp f_to_int

;---------------------------------------------------------------------------------------
; f_exp - fa = e^fa
;---------------------------------------------------------------------------------------
f_exp:
        lda fa+F_CLS
        cmp #FC_NAN
        beq _ret
        cmp #FC_INF
        beq _big
        ldx #FA
        jsr m_zero
        bne +
        ldx #FA
        lda #0
        jmp f_one
+       lda fa+F_EXP+1                  ; |x| >= 2048: overflow or zero
        bmi +
        bne _big
        lda fa+F_EXP
        cmp #11
        bcs _big
+       ldy #FC
        jsr f_put                       ; fc = x
        ldx #FB
        lda #FK_INV_LN2
        jsr f_const
        jsr f_mul
        jsr f_round_int                 ; n = round(x / ln 2)
        ldy #FD
        jsr f_put                       ; fd = n
        ldq acc
        stq ft_q
        ; r = x - n ln2_hi - n ln2_lo
        lda #FK_LN2_HI
        jsr f_nk
        lda #FK_LN2_LO
        jsr f_nk
        ; e^r, times 2^n
        ldx #FE
        lda #0
        jsr f_one
        lda #0
        sta ft_mode
        sta ft_alt
        lda #1
        sta ft_k
        lda #18
        sta ft_n
        jsr f_series
        clc
        lda fa+F_EXP
        adc ft_q
        sta fa+F_EXP
        lda fa+F_EXP+1
        adc ft_q+1
        sta fa+F_EXP+1
_ret:   rts
_big:   lda fa+F_SIGN
        bmi +
        lda #FC_INF
        sta fa+F_CLS
        rts
+       jmp fa_zero
; f_nk - fc -= fd * constant A
f_nk:   ldx #FB
        jsr f_const
        ldx #FD
        jsr f_get
        jsr f_mul
        ldy #FB
        jsr f_put
        ldx #FC
        jsr f_get
        jsr f_sub
        ldy #FC
        jmp f_put
ft_q:           .dword 0

;---------------------------------------------------------------------------------------
; f_log - fa = ln(fa) (A = 0), or log2(fa) (A = 1); ValueError for x <= 0
;---------------------------------------------------------------------------------------
f_log:
        sta ft_flag
        lda fa+F_CLS
        cmp #FC_NAN
        beq _ret
        ldx #FA
        jsr m_zero
        bne +
        lda fa+F_CLS
        beq _dom                        ; log(0)
+       lda fa+F_SIGN
        bmi _dom
        lda fa+F_CLS
        bne _ret                        ; inf
        ; x = m * 2^E, m in [sqrt(1/2), sqrt(2))
        lda fa+F_EXP
        sta acc
        lda fa+F_EXP+1
        sta acc+1
        lda #0
        sta fa+F_EXP
        sta fa+F_EXP+1
        ldx #FB
        lda #FK_SQRT2
        jsr f_const
        ldx #7
-       lda fa+F_MAN,x
        cmp fb+F_MAN,x
        bne +
        dex
        bpl -
+       bcc +
        dec fa+F_EXP                    ; m > sqrt(2): m / 2, E + 1
        dec fa+F_EXP+1
        inc acc
        bne +
        inc acc+1
+       lda #0                          ; E as a 32-bit int
        bit acc+1
        bpl +
        lda #$ff
+       sta acc+2
        sta acc+3
        ldq acc
        stq ft_q
        ; s = (m - 1) / (m + 1); ln m = 2 (s + s^3/3 + s^5/5 + ...)
        ldy #FC
        jsr f_put
        ldx #FB
        lda #0
        jsr f_one
        jsr f_sub
        ldy #FD
        jsr f_put                       ; fd = m - 1
        ldx #FC
        jsr f_get
        ldx #FB
        lda #0
        jsr f_one
        jsr f_add
        ldy #FB
        jsr f_put
        ldx #FD
        jsr f_get
        jsr f_div
        ldy #FE
        jsr f_put                       ; fe = s
        ldy #FE
        jsr f_mul_y
        ldy #FC
        jsr f_put                       ; fc = s^2
        lda #2
        sta ft_mode
        lda #3
        sta ft_k
        lda #0
        sta ft_alt
        lda #14
        sta ft_n
        jsr f_series
        jsr fa_inc_exp                  ; * 2
        lda ft_flag
        beq _ln
        ; log2: E + ln m / ln 2
        ldx #FB
        lda #FK_INV_LN2
        jsr f_const
        jsr f_mul
        ldy #FD
        jsr f_put
        ldq ft_q
        stq acc
        jsr f_from_int
        ldy #FD
        jmp f_add_y
_ln:    ; E ln2_hi + (E ln2_lo + ln m)
        ldy #FD
        jsr f_put
        ldq ft_q
        stq acc
        jsr f_from_int
        ldy #FC
        jsr f_put                       ; fc = E
        ldx #FB
        lda #FK_LN2_LO
        jsr f_const
        jsr f_mul
        ldy #FD
        jsr f_add_y
        ldy #FD
        jsr f_put
        ldx #FC
        jsr f_get
        ldx #FB
        lda #FK_LN2_HI
        jsr f_const
        jsr f_mul
        ldy #FD
        jmp f_add_y
_ret:   rts
_dom:   jmp m_domain

;---------------------------------------------------------------------------------------
; f_trig - fa = sin(fa) (A = 0) or cos(fa) (A = 1)
;---------------------------------------------------------------------------------------
f_trig:
        sta ft_flag
        lda fa+F_CLS
        cmp #FC_NAN
        beq _ret
        cmp #FC_INF
        bne +
        jmp m_domain
+       ; n = round(x * 2/pi), r = x - n pi/2 (in three parts)
        ldy #FC
        jsr f_put
        ldx #FB
        lda #FK_TWO_OVER_PI
        jsr f_const
        jsr f_mul
        jsr f_round_int
        bcc +
        jmp m_domain                    ; (too big to reduce)
+       ldy #FD
        jsr f_put
        clc
        lda acc
        adc ft_flag                     ; cos x = sin(x + pi/2)
        and #3
        sta ft_flag
        lda #FK_PIO2_HI
        jsr f_nk
        lda #FK_PIO2_MID
        jsr f_nk
        lda #FK_PIO2_LO
        jsr f_nk
        ldx #FC
        jsr f_get
        ldy #FE
        jsr f_put                       ; fe = r
        ldy #FC
        jsr f_mul_y
        ldy #FC
        jsr f_put                       ; fc = r^2
        lda #1
        sta ft_mode
        lda #$80
        sta ft_alt
        lda #11
        sta ft_n
        lda ft_flag                     ; quadrant 0/2: sin r, 1/3: cos r
        lsr a
        bcs _cos
        lda #2
        sta ft_k
        bra _go
_cos:   ldx #FE
        lda #0
        jsr f_one
        lda #1
        sta ft_k
_go:    jsr f_series
        lda ft_flag                     ; quadrants 2, 3: negative
        and #2
        beq _ret
        lda fa+F_SIGN
        eor #$80
        sta fa+F_SIGN
_ret:   rts

;---------------------------------------------------------------------------------------
; f_atan - fa = atan(fa)
;---------------------------------------------------------------------------------------
f_atan:
        lda fa+F_CLS
        cmp #FC_NAN
        beq _ret
        lda fa+F_SIGN
        sta ft_sign
        lda #0
        sta fa+F_SIGN
        sta ft_flag
        lda fa+F_CLS
        beq +
        ldx #FA                         ; atan(inf) = pi/2
        lda #FK_PIO2
        jsr f_const
        bra _sign
+       ldx #FA
        jsr m_zero
        beq _sign
        lda fa+F_EXP+1                  ; x >= 1: pi/2 - atan(1/x)
        bmi +
        inc ft_flag
        ldy #FB
        jsr f_put
        ldx #FA
        lda #0
        jsr f_one
        jsr f_div
+       jsr _half                       ; x / (1 + sqrt(1 + x^2)), twice: atan / 4
        jsr _half
        ldy #FE
        jsr f_put
        ldy #FE
        jsr f_mul_y
        ldy #FC
        jsr f_put
        lda #2
        sta ft_mode
        lda #3
        sta ft_k
        lda #$80
        sta ft_alt
        lda #15
        sta ft_n
        jsr f_series
        jsr fa_inc_exp
        jsr fa_inc_exp
        lda ft_flag
        beq _sign
        lda #$80
        sta fa+F_SIGN
        ldx #FB
        lda #FK_PIO2
        jsr f_const
        jsr f_add
_sign:  lda ft_sign
        sta fa+F_SIGN
_ret:   rts
_half:  ldy #FH
        jsr f_put
        ldy #FH
        jsr f_mul_y
        ldx #FB
        lda #0
        jsr f_one
        jsr f_add
        jsr f_sqrt
        ldx #FB
        lda #0
        jsr f_one
        jsr f_add
        ldy #FB
        jsr f_put
        ldx #FH
        jsr f_get
        jmp f_div

; f_atan2 - fa = atan2(fa = y, fb = x)
f_atan2:
        lda fa+F_CLS
        cmp #FC_NAN
        beq _nan
        lda fb+F_CLS
        cmp #FC_NAN
        beq _nan
        lda fa+F_SIGN
        sta ft_ys
        lda fb+F_SIGN
        sta ft_xs
        ldx #FB
        jsr m_zero
        bne _div
        lda fb+F_CLS
        bne _div
        ; x = 0: +-pi/2, or for y = 0 the zero (x = +0) or +-pi (x = -0)
        ldx #FA
        jsr m_zero
        bne +
        lda fa+F_CLS
        bne +
        lda ft_xs
        bpl _ret
        lda #FK_PI
        bra _k
+       lda #FK_PIO2
_k:     ldx #FA
        jsr f_const
        lda ft_ys
        sta fa+F_SIGN
_ret:   rts
_nan:   jmp f_set_nan
_div:   jsr f_div
        jsr f_atan
        lda ft_xs                     ; x < 0: +-pi
        bpl _ret
        ldx #FB
        lda #FK_PI
        jsr f_const
        lda ft_ys
        sta fb+F_SIGN
        jmp f_add

; f_sqrt1m - fb = sqrt((1 - x)(1 + x)) for fa = x (kept); ValueError if |x| > 1
f_sqrt1m:
        lda fa+F_CLS
        bne _dom
        ldy #FH
        jsr f_put
        ldx #FB
        lda #0
        jsr f_one
        jsr f_add
        ldy #FI
        jsr f_put                       ; fi = 1 + x
        ldx #FH
        jsr f_get
        lda fa+F_SIGN
        eor #$80
        sta fa+F_SIGN
        ldx #FB
        lda #0
        jsr f_one
        jsr f_add                       ; 1 - x
        ldy #FI
        jsr f_mul_y
        lda fa+F_SIGN
        bmi _dom
        jsr f_sqrt
        ldy #FB
        jsr f_put
        ldx #FH
        jmp f_get
_dom:   jmp m_domain

;---------------------------------------------------------------------------------------
; xb_pow (f_pow) - fa = fa ** fb
;---------------------------------------------------------------------------------------
xb_pow:
        lda fb+F_CLS                    ; x ** 0 = 1
        bne +
        ldx #FB
        jsr m_zero
        bne +
        ldx #FA
        lda #0
        jmp f_one
+       ldy #FC
        jsr f_put                       ; fc = x
        ldx #FB
        ldy #FD
        jsr f_mov                       ; fd = y
        lda #FC_NAN
        cmp fa+F_CLS
        beq _ret
        cmp fb+F_CLS
        bne +
        jmp f_set_nan
+       ; an integral y that fits in 32 bits: by squaring
        ldx #FD
        jsr f_get
        jsr f_trunc
        bcs _real
        jsr f_to_int
        bcs _real
        jmp _ipow
_real:  ; x ** y = e^(y ln x), x > 0
        ldx #FC
        jsr f_get
        ldx #FA
        jsr m_zero
        bne +
        lda fa+F_CLS
        bne +
        lda fd+F_SIGN                   ; 0 ** y
        bmi _zdiv
        jmp fa_zero
+       lda fa+F_SIGN
        bpl +
        #RAISE EXC_VALUE, "negative number cannot be raised to a fractional power"
+       lda fd+F_CLS
        bne _yinf
        lda fa+F_CLS
        bne _xinf
        ; y = 0.5: the square root
        lda fd+F_EXP
        cmp #$ff
        bne +
        lda fd+F_EXP+1
        cmp #$ff
        bne +
        lda fd+F_MAN+7
        cmp #$80
        bne +
        ldx #FD
        lda fd+F_MAN
        ora fd+F_MAN+1
        ora fd+F_MAN+2
        ora fd+F_MAN+3
        ora fd+F_MAN+4
        ora fd+F_MAN+5
        ora fd+F_MAN+6
        bne +
        lda fd+F_SIGN
        bne +
        jmp f_sqrt
+       ldx #FD                         ; (f_log uses fd)
        ldy #FH
        jsr f_mov
        lda #0
        jsr f_log
        ldy #FH
        jsr f_mul_y
        jmp f_exp
_xinf:  lda fd+F_SIGN                   ; inf ** y
        bmi +
        rts
+       jmp fa_zero
_yinf:  ; x ** +-inf: 1 for x = 1, else inf or 0
        ldx #FB
        lda #0
        jsr f_one
        jsr f_cmp
        cmp #0
        beq _one
        eor fd+F_SIGN                   ; (|x| > 1) xor (y < 0)
        cmp #1
        beq +
        cmp #$ff^$80
        beq +
        jmp fa_zero
+       lda #FC_INF
        sta fa+F_CLS
        lda #0
        sta fa+F_SIGN
_ret:   rts
_one:   ldx #FA
        lda #0
        jmp f_one
_zdiv:  #RAISE EXC_ZERODIV, "0.0 cannot be raised to a negative power"
_ipow:  ; acc = n: result fe = 1, base fc
        lda acc+3
        sta ft_sign
        bpl +
        jsr acc_neg
        ldx #FC
        jsr f_get
        lda fa+F_CLS
        bne +
        ldx #FA
        jsr m_zero
        beq _zdiv
+       ldx #FE
        lda #0
        jsr f_one
_ploop: lda acc
        and #1
        beq +
        ldx #FE
        jsr f_get
        ldy #FC
        jsr _mulc
        ldy #FE
        jsr f_put
+       lsr acc+3
        ror acc+2
        ror acc+1
        ror acc
        lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        beq +
        ldx #FC
        jsr f_get
        ldy #FC
        jsr _mulc
        ldy #FC
        jsr f_put
        bra _ploop
+       ldx #FE
        jsr f_get
        lda ft_sign
        bpl +
        ldy #FB
        jsr f_put
        ldx #FA
        lda #0
        jsr f_one
        jmp f_div
+       rts
; fa *= register Y, keeping the exponent within +-16000 (beyond: inf or 0)
_mulc:  jsr f_mul_y
        lda fa+F_CLS
        bne +
        lda fa+F_EXP+1
        bmi _low
        cmp #>16000
        bcc +
        lda #FC_INF
        sta fa+F_CLS
+       rts
_low:   cmp #>-16000
        bcs +
        jmp fa_zero_signed
+       rts
