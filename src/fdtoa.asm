;=======================================================================================
; Floats: double -> decimal digits (exact, with bignums) and the text layouts of
; repr(), str.format / format() ('f', 'e', 'g', '%', none) and the % operator.
;
; f_digits is Steele & White / Burger & Dybvig: value = R / S, with the rounding
; boundaries MP / MM for the shortest digits that read back as the same double
; (ties to even, as repr() does), or a fixed number of digits rounded half-to-even on
; the exact value.
;=======================================================================================
fd_mode:        .byte 0                 ; 0 shortest, 1 fd_prec digits, 2 fd_prec decimals
fd_prec:        .word 0                 ; (signed for mode 2)
fd_even:        .byte 0
fd_asym:        .byte 0
fd_e:           .word 0                 ; value = fd_f * 2^fd_e
fd_f:           .fill 8
fd_sh:          .word 0
fd_d:           .byte 0

; f_digits - fdbl (finite; the sign is ignored) -> DIGBUF / fd_n / fd_dec
f_digits:
        lda #0
        sta fd_n
        lda fdbl+7
        and #$7f
        sta fdbl+7
        jsr f_unpack
        ldx #FA
        jsr m_zero
        bne +
        lda #1                          ; zero: no digits, point after the first
        sta fd_dec
        lda #0
        sta fd_dec+1
        rts
+       ; fd_f = the 52-bit fraction, fw = the biased exponent
        ldx #6
-       lda fdbl,x
        sta fd_f,x
        dex
        bpl -
        lda fd_f+6
        and #$0f
        sta fd_f+6
        lda #0
        sta fd_f+7
        lda fdbl+7
        sta fw+1
        lda fdbl+6
        sta fw
        ldx #4
-       lsr fw+1
        ror fw
        dex
        bne -
        lda fd_f
        and #1
        eor #1
        sta fd_even
        lda #0
        sta fd_asym
        lda fd_f
        ora fd_f+1
        ora fd_f+2
        ora fd_f+3
        ora fd_f+4
        ora fd_f+5
        ora fd_f+6
        bne +
        lda fw+1
        bne _asym
        lda fw
        cmp #2
        bcc +
_asym:  inc fd_asym
+       lda fw
        ora fw+1
        bne _norm
        lda #<-1074                     ; subnormal
        sta fd_e
        lda #>-1074
        sta fd_e+1
        bra _setup
_norm:  lda fd_f+6
        ora #$10
        sta fd_f+6
        sec
        lda fw
        sbc #<1075
        sta fd_e
        lda fw+1
        sbc #>1075
        sta fd_e+1
_setup: lda #BN_LEN
        sta bn_len
        ; sh = 0 (fixed digits), else 2 for an asymmetric gap, else 1
        lda #0
        ldx fd_mode
        bne +
        lda fd_asym
        inc a
+       sta fd_sh
        ; R = f << (max(e, 0) + sh)
        lda #BN_R
        jsr bn_a
        jsr bn_zero
        ldx #0
        ldz #0
-       lda fd_f,x
        sta [bnA],z
        inx
        inz
        cpx #8
        bne -
        lda fd_e+1
        bmi +
        clc
        lda fd_e
        adc fd_sh
        ldx fd_e+1
        bcc ++
        inx
        bra ++
+       lda fd_sh
        ldx #0
+       jsr bn_shl
        ; S = 1 << (max(-e, 0) + sh)
        lda #BN_S
        jsr bn_a
        jsr bn_one
        lda fd_e+1
        bpl +
        sec
        lda fd_sh
        sbc fd_e
        pha
        lda #0
        sbc fd_e+1
        tax
        pla
        bra ++
+       lda fd_sh
        ldx #0
+       jsr bn_shl
        lda fd_mode
        bne _scale
        ; MM = 1 << max(e, 0), MP = MM << (sh - 1)
        lda #BN_MM
        jsr bn_a
        jsr bn_one
        lda fd_e+1
        bmi +
        lda fd_e
        ldx fd_e+1
        jsr bn_shl
+       lda #BN_MP
        jsr bn_a
        lda #BN_MM
        jsr bn_b
        jsr bn_copy
        lda fd_asym
        beq _scale
        lda #BN_MP
        jsr bn_a
        jsr bn_shl1
_scale: ; k = floor(E2 * log10(2)) + 1, E2 = the exponent of the top bit
        lda fa+F_EXP
        ldx fa+F_EXP+1
        bpl +
        eor #$ff
        tay
        txa
        eor #$ff
        tax
        tya
        inc a
        bne +
        inx
+       sta MULTINA
        stx MULTINA+1
        lda #0
        sta MULTINA+2
        sta MULTINA+3
        lda #<78913                     ; log10(2) * 2^18
        sta MULTINB
        lda #>78913
        sta MULTINB+1
        lda #`78913
        sta MULTINB+2
        lda #0
        sta MULTINB+3
        lda MULTOUT+2
        sta fd_dec
        lda MULTOUT+3
        sta fd_dec+1
        lsr fd_dec+1
        ror fd_dec
        lsr fd_dec+1
        ror fd_dec
        bit fa+F_EXP+1
        bmi +
        inw fd_dec                      ; E2 >= 0: q + 1
        bra _k
+       sec                             ; E2 < 0: -q
        lda #0
        sbc fd_dec
        sta fd_dec
        lda #0
        sbc fd_dec+1
        sta fd_dec+1
_k:     ; scale by 10^k: S for k >= 0, else R (and MP, MM)
        bit fd_dec+1
        bmi +
        lda #BN_S
        jsr bn_a
        lda fd_dec
        ldx fd_dec+1
        jsr bn_pow10
        bra _fix
+       sec
        lda #0
        sbc fd_dec
        sta fd_sh
        lda #0
        sbc fd_dec+1
        sta fd_sh+1
        lda #BN_R
        jsr _p10
        lda fd_mode
        bne _fix
        lda #BN_MP
        jsr _p10
        lda #BN_MM
        jsr _p10
_fix:   ; the estimate can be one too small: then S *= 10, k += 1
        lda fd_mode
        bne _fixf
        lda #BN_T                       ; shortest: R + MP >= S (> for odd)
        jsr bn_a
        lda #BN_R
        jsr bn_b
        jsr bn_copy
        lda #BN_MP
        jsr bn_b
        jsr bn_add
        lda #BN_S
        jsr bn_b
        jsr bn_cmp
        bcc _fitk
        bne _bump
        lda fd_even
        beq _fitk
        bra _bump
_fixf:  lda #BN_R
        jsr bn_a
        lda #BN_S
        jsr bn_b
        jsr bn_cmp
        bcc _fitk
_bump:  lda #BN_S
        jsr _x10
        inw fd_dec
_fitk:  lda #BN_S
        jsr bn_a
        jsr bn_fit
        lda fd_mode
        beq _short
        jmp _fixed
_p10:   jsr bn_a
        lda fd_sh
        ldx fd_sh+1
        jmp bn_pow10

        ;-------------------------------------------------------------------------------
_short: ; R, MP, MM *= 10; d = R / S; stop when inside the rounding interval
        lda #BN_R
        jsr _x10
        lda #BN_MP
        jsr _x10
        lda #BN_MM
        jsr _x10
        jsr _digit
        ; tc1: R < MM (<= for even)
        lda #BN_R
        jsr bn_a
        lda #BN_MM
        jsr bn_b
        ldy #0
        jsr bn_cmp
        bcc _tc1
        bne +
        ldy fd_even
        bra +
_tc1:   ldy #1
+       sty fw+2
        ; tc2: R + MP > S (>= for even)
        jsr _rplus
        lda #BN_MP
        jsr bn_b
        jsr bn_add
        lda #BN_S
        jsr bn_b
        jsr bn_cmp
        bcc _no2
        bne _yes2
        ldy fd_even
        bra +
_yes2:  ldy #1
        bra +
_no2:   ldy #0
+       sty fw+3
        tya
        ora fw+2
        bne _last
        jsr _store
        lda fd_n
        cmp #20
        bcc _short
        rts
_last:  lda fw+2
        beq _up                         ; only tc2: d + 1
        lda fw+3
        beq _store                      ; only tc1: d
        jsr _rplus                      ; both: compare 2R with S
        lda #BN_R
        jsr bn_b
        jsr bn_add
        lda #BN_S
        jsr bn_b
        jsr bn_cmp
        bcc _store
        bne _up
        lda fd_d                        ; a tie: to even
        and #1
        beq _store
_up:    inc fd_d
_store: ldx fd_n
        lda fd_d
        sta DIGBUF,x
        inc fd_n
        rts
_x10:   jsr bn_a
        lda #10
        ldx #0
        ldy #0
        jmp bn_mul
_rplus: lda #BN_T                       ; T = R
        jsr bn_a
        lda #BN_R
        jsr bn_b
        jmp bn_copy
_digit: ; fd_d = R / S, R = R mod S
        lda #BN_R
        jsr bn_a
        lda #BN_S
        jsr bn_b
        lda #0
        sta fd_d
-       jsr bn_cmp
        bcc +
        jsr bn_sub
        inc fd_d
        bra -
+       rts

        ;-------------------------------------------------------------------------------
_fixed: ; the digit count: fd_prec, or k + fd_prec for decimals; at most 250
        lda fd_prec
        ldx fd_prec+1
        ldy fd_mode
        cpy #1
        beq +
        clc
        adc fd_dec
        pha
        txa
        adc fd_dec+1
        tax
        pla
+       cpx #0
        beq +
        bmi _none                       ; < 0: rounds to zero (no digits)
        lda #250
+       cmp #251
        bcc +
        lda #250
+       sta fw+2
        beq _round
-       lda #BN_R
        jsr _x10
        jsr _digit
        jsr _store
        lda fd_n
        cmp fw+2
        bne -
        bra _round
_none:  rts
_round: ; half-to-even on the remainder: 2R vs S
        jsr _rplus
        lda #BN_R
        jsr bn_b
        jsr bn_add
        lda #BN_S
        jsr bn_b
        jsr bn_cmp
        bcc _done
        bne _carry
        ldx fd_n
        beq _done
        lda DIGBUF-1,x
        and #1
        beq _done
_carry: ldx fd_n
-       dex
        cpx #$ff
        beq _all9
        lda DIGBUF,x
        inc a
        sta DIGBUF,x
        cmp #10
        bcc _done
        lda #0
        sta DIGBUF,x
        bra -
_all9:  lda #1
        sta DIGBUF
        lda fd_n
        bne +
        inc fd_n
+       inw fd_dec
_done:  rts

;---------------------------------------------------------------------------------------
; sb_float - append fdbl formatted by ff_type ('r' repr, 'f', 'e', 'g', '%', or 'n' =
; no type but a precision), ff_prec ($ffff = default), ff_sign, ff_upper, ff_comma
;---------------------------------------------------------------------------------------
ff_type:        .byte 0
ff_prec:        .word 0
ff_sign:        .byte 0
ff_upper:       .byte 0                 ; $20 for E / F / G
ff_comma:       .byte 0

sb_float:
        jsr f_unpack                    ; a nan prints without its sign
        lda fa+F_CLS
        cmp #FC_NAN
        bne +
        lda fdbl+7
        and #$7f
        sta fdbl+7
+       lda fdbl+7
        bpl +
        and #$7f
        sta fdbl+7
        lda #'-'
        bra ++
+       lda ff_sign
        cmp #'-'
        beq ++
+       jsr sb_putc
+       jsr f_unpack
        lda fa+F_CLS
        beq _fin
        cmp #FC_INF
        bne +
        lda #'i'
        jsr _putcase
        lda #'n'
        jsr _putcase
        lda #'f'
        bra _spec
+       lda #'n'                        ; nan (no sign: CPython drops it)
        jsr _putcase
        lda #'a'
        jsr _putcase
        lda #'n'
_spec:  jsr _putcase
        bra _pct
_fin:   lda ff_type
        cmp #'%'
        bne _fmt
        lda #100                        ; x * 100, as a double
        sta acc
        lda #0
        sta acc+1
        sta acc+2
        sta acc+3
        ldx #FA
        ldy #FC
        jsr f_mov
        jsr f_from_int
        ldx #FA
        ldy #FB
        jsr f_mov
        ldx #FC
        ldy #FA
        jsr f_mov
        jsr f_mul
        jsr f_pack
        lda #'f'
        sta ff_type
        jsr _fmt
        lda #'%'
        sta ff_type
_pct:   lda ff_type
        cmp #'%'
        bne +
        jsr sb_putc
+       rts
_fmt:   lda ff_type
        cmp #'r'
        bne +
        jmp _repr
+       ldx ff_prec+1                   ; the default precision: 6
        cpx #$ff
        bne +
        lda #6
        sta ff_prec
        lda #0
        sta ff_prec+1
+       lda ff_type
        cmp #'f'
        bne _e
        lda #2
        sta fd_mode
        lda ff_prec
        sta fd_prec
        lda ff_prec+1
        sta fd_prec+1
        jsr f_digits
        jmp _flay
_e:     cmp #'e'
        bne _g
        lda ff_prec+1                   ; (at most 249)
        bne +
        lda ff_prec
        cmp #250
        bcc ++
+       lda #249
        sta ff_prec
        lda #0
        sta ff_prec+1
+       lda #1
        sta fd_mode
        clc
        lda ff_prec
        adc #1
        sta fd_prec
        lda ff_prec+1
        adc #0
        sta fd_prec+1
        jsr f_digits
        jmp _elay
_g:     ; 'g' / 'n': P significant digits (at least 1), trailing zeros dropped
        lda ff_prec
        ora ff_prec+1
        bne +
        inc ff_prec
+       lda ff_prec+1                   ; (more than 250 makes no difference)
        beq +
        lda #250
        sta ff_prec
        lda #0
        sta ff_prec+1
+       lda #1
        sta fd_mode
        lda ff_prec
        sta fd_prec
        lda #0
        sta fd_prec+1
        jsr f_digits
        jsr _strip
        ; exponent form if dec <= -4 or dec > P (P - 1 for 'n')
        lda ff_prec
        ldx ff_type
        cpx #'n'
        bne +
        dec a
+       sta fw
        jsr _dec_le_m4
        bcs _gexp
        lda fd_dec+1
        bmi _gfix                       ; (> -4 here)
        bne _gexp
        lda fw
        cmp fd_dec
        bcc _gexp
_gfix:  sec                             ; decimals: digits - dec, at least 0
        lda fd_n
        sbc fd_dec
        tay
        lda #0
        sbc fd_dec+1
        bpl +
        ldy #0
+       sty ff_prec
        lda #0
        sta ff_prec+1
        jsr _flay
        lda ff_type
        cmp #'n'
        bne +
        lda ff_prec
        bne +
        jmp _dot0
+       rts
_gexp:  ldx fd_n
        dex
        bpl +
        ldx #0
+       stx ff_prec
        lda #0
        sta ff_prec+1
        jmp _elay

_repr:  lda #0
        sta fd_mode
        jsr f_digits
        jsr _dec_le_m4                  ; exponent form if dec <= -4 or dec > 16
        bcs _rexp
        lda fd_dec+1
        bmi _rfix
        bne _rexp
        lda fd_dec
        cmp #17
        bcs _rexp
_rfix:  sec
        lda fd_n
        sbc fd_dec
        tay
        lda #0
        sbc fd_dec+1
        bpl +
        ldy #0
+       sty ff_prec
        lda #0
        sta ff_prec+1
        lda #0
        sta ff_comma
        jsr _flay
        lda ff_prec
        bne +
_dot0:  lda #'.'
        jsr sb_putc
        lda #'0'
        jmp sb_putc
+       rts
_rexp:  ldx fd_n
        dex
        stx ff_prec
        lda #0
        sta ff_prec+1
        jmp _elay

; C set if fd_dec <= -4
_dec_le_m4:
        lda fd_dec
        cmp #<-3
        lda fd_dec+1
        sbc #>-3
        bvc +
        eor #$80
+       asl a                           ; C = sign of dec - (-3)
        rts

; drop trailing zero digits
_strip: ldx fd_n
-       beq +
        lda DIGBUF-1,x
        bne +
        dex
        bra -
+       stx fd_n
        rts

; fixed: integer digits (0 if none), then ff_prec decimals
_flay:  lda fd_dec+1
        bmi _f0
        lda fd_dec
        bne +
_f0:    lda #'0'
        jsr sb_putc
        bra _frac
+       lda #0
        sta ff_i
        sta ff_i+1
        lda fd_dec
        sta ff_cnt
        lda fd_dec+1
        sta ff_cnt+1
-       jsr _dig_i
        jsr sb_putc
        inw ff_i
        dew ff_cnt
        lda ff_cnt
        ora ff_cnt+1
        beq _frac
        lda ff_comma                    ; a comma when the digits left are a multiple of 3
        beq -
        lda ff_cnt+1
        sta acc+1
        lda ff_cnt
        sta acc
        lda #0
        sta acc+2
        sta acc+3
        jsr _mod3
        bne -
        lda #','
        jsr sb_putc
        bra -
_frac:  lda ff_prec
        ora ff_prec+1
        beq _fdone
        lda #'.'
        jsr sb_putc
        lda fd_dec
        sta ff_i
        lda fd_dec+1
        sta ff_i+1
        lda ff_prec
        sta ff_cnt
        lda ff_prec+1
        sta ff_cnt+1
-       jsr _dig_i
        jsr sb_putc
        inw ff_i
        dew ff_cnt
        lda ff_cnt
        ora ff_cnt+1
        bne -
_fdone: rts
_mod3:  ldq acc                         ; Z set if acc % 3 == 0
        stq MULTINA
        lda #3
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
-       bit MATHBUSY
        bmi -
        ldq DIVOUT+4
        stq MULTINA
        lda acc
        cmp MULTOUT
        rts

; digit ff_i as a character ('0' outside the digits)
_dig_i: lda ff_i+1
        bne _zero
        ldx ff_i
        cpx fd_n
        bcs _zero
        lda DIGBUF,x
        ora #'0'
        rts
_zero:  lda #'0'
        rts

; exponent: d[.ddd]e+XX with ff_prec decimals
_elay:  lda #0
        sta ff_i
        sta ff_i+1
        jsr _dig_i
        jsr sb_putc
        lda ff_prec
        beq +
        lda #'.'
        jsr sb_putc
-       inw ff_i
        jsr _dig_i
        jsr sb_putc
        lda ff_i
        cmp ff_prec
        bne -
+       lda #'e'
        jsr _putcase
        sec                             ; exponent = dec - 1
        lda fd_dec
        sbc #1
        sta acc
        lda fd_dec+1
        sbc #0
        sta acc+1
        lda #'+'
        bit acc+1
        bpl +
        sec
        lda #0
        sbc acc
        sta acc
        lda #0
        sbc acc+1
        sta acc+1
        lda #'-'
+       jsr sb_putc
        lda acc+1
        bne +
        lda acc
        cmp #10
        bcs +
        lda #'0'
        jsr sb_putc
+       lda #0
        sta acc+2
        sta acc+3
        jmp sb_int

_putcase:
        ldx ff_upper
        beq +
        and #$df
+       jmp sb_putc
