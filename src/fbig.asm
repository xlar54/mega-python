;=======================================================================================
; Floats: bignums, and decimal text -> double (correctly rounded).
;
; Bignums are BN_LEN-byte little-endian numbers in the BIGNUM workspace (bank 1),
; reached through the base-page pointers bnA / bnB. add, sub, cmp, mul and shl1 work
; on the low bn_len bytes only (the conversions keep that just above what they need).
;
; Decimal digits live in DIGBUF (values 0-9): fd_n of them, the number being
; D * 10^fd_exp (D = the digits as an integer), or 0.D * 10^fd_exp for dtoa.
;=======================================================================================
BN_LEN          = 160
BN_R            = 0
BN_S            = 1
BN_MP           = 2
BN_MM           = 3
BN_T            = 4
FD_MAX          = 30                    ; digits kept when parsing

bn_len:         .byte 0
bn_c:           .word 0
bn_n:           .word 0
fd_n:           .byte 0                 ; digit count
fd_sticky:      .byte 0                 ; parsing: non-zero digits were dropped
fd_seen:        .byte 0
fd_frac:        .byte 0
bn_lo:          .byte <(BIGNUM + range(5) * BN_LEN)
bn_hi:          .byte >(BIGNUM + range(5) * BN_LEN)

; bn_a / bn_b - A = bignum number -> bnA / bnB
bn_a:   tax
        lda bn_lo,x
        sta bnA
        lda bn_hi,x
        sta bnA+1
        lda #`BIGNUM
        sta bnA+2
        lda #0
        sta bnA+3
        rts
bn_b:   tax
        lda bn_lo,x
        sta bnB
        lda bn_hi,x
        sta bnB+1
        lda #`BIGNUM
        sta bnB+2
        lda #0
        sta bnB+3
        rts

; bn_zero - [bnA] = 0
bn_zero:
        lda #0
        ldz #0
-       sta [bnA],z
        inz
        cpz #BN_LEN
        bne -
        rts

; bn_one - [bnA] = 1
bn_one: jsr bn_zero
        lda #1
        ldz #0
        sta [bnA],z
        rts

; bn_copy - [bnA] = [bnB]
bn_copy:
        ldz #0
-       lda [bnB],z
        sta [bnA],z
        inz
        cpz #BN_LEN
        bne -
        rts

; bn_add / bn_sub - [bnA] +/-= [bnB]
bn_add: clc
        ldz #0
        ldy bn_len
-       lda [bnA],z
        adc [bnB],z
        sta [bnA],z
        inz
        dey
        bne -
        rts
bn_sub: sec
        ldz #0
        ldy bn_len
-       lda [bnA],z
        sbc [bnB],z
        sta [bnA],z
        inz
        dey
        bne -
        rts

; bn_cmp - compare [bnA] with [bnB]: C set if >=, Z set if equal
bn_cmp: ldz bn_len
-       dez
        lda [bnA],z
        cmp [bnB],z
        bne +
        cpz #0
        bne -
+       rts

; bn_shl1 - [bnA] <<= 1
bn_shl1:
        clc
        ldz #0
        ldy bn_len
-       lda [bnA],z
        rol a
        sta [bnA],z
        inz
        dey
        bne -
        rts

; bn_mul - [bnA] = [bnA] * A/X + Y
bn_mul: sta MULTINB
        stx MULTINB+1
        sty bn_c
        lda #0
        sta bn_c+1
        sta MULTINB+2
        sta MULTINB+3
        sta MULTINA+1
        sta MULTINA+2
        sta MULTINA+3
        ldz #0
-       lda [bnA],z
        sta MULTINA
        clc
        lda MULTOUT
        adc bn_c
        sta [bnA],z
        lda MULTOUT+1
        adc bn_c+1
        sta bn_c
        lda MULTOUT+2
        adc #0
        sta bn_c+1
        inz
        cpz bn_len
        bne -
        rts

; bn_pow10 - [bnA] *= 10^(A/X)
bn_pow10:
        sta bn_n
        stx bn_n+1
-       lda bn_n+1
        bne +
        lda bn_n
        cmp #4
        bcc _rest
+       lda #<10000
        ldx #>10000
        ldy #0
        jsr bn_mul
        sec
        lda bn_n
        sbc #4
        sta bn_n
        bcs -
        dec bn_n+1
        bra -
_rest:  ldy bn_n
        beq +
        lda _p10hi,y
        tax
        lda _p10lo,y
        ldy #0
        jmp bn_mul
+       rts
_p10lo: .byte <1, <10, <100, <1000
_p10hi: .byte >1, >10, >100, >1000

; bn_shl - [bnA] <<= A/X bits (the whole number)
bn_shl: sta bn_n
        stx bn_n+1
        lda bn_len
        pha
        lda #BN_LEN
        sta bn_len
        lda bn_n
        and #7
        pha
        lsr bn_n+1                      ; whole bytes
        ror bn_n
        lsr bn_n+1
        ror bn_n
        lsr bn_n+1
        ror bn_n
        lda bn_n
        beq _bits
        sec                             ; bnB = bnA - bytes
        lda bnA
        sbc bn_n
        sta bnB
        lda bnA+1
        sbc #0
        sta bnB+1
        lda bnA+2
        sta bnB+2
        lda #0
        sta bnB+3
        ldz #BN_LEN-1
-       lda [bnB],z
        sta [bnA],z
        dez
        cpz bn_n
        bcs -
        lda #0
-       sta [bnA],z
        dez
        cpz #$ff
        bne -
_bits:  plx
        beq +
-       phx
        jsr bn_shl1
        plx
        dex
        bne -
+       pla
        sta bn_len
        rts

; bn_top - A = index of the top non-zero byte + 1 (0 for zero), Z from A
bn_top: ldz #BN_LEN
-       dez
        lda [bnA],z
        bne +
        cpz #0
        bne -
        lda #0
        rts
+       tza
        inc a
        rts

; bn_bitlen - A/X = number of bits in [bnA]
bn_bitlen:
        jsr bn_top
        bne +
        tax
        rts
+       dec a
        sta bn_n
        taz
        lda [bnA],z
        ldy #0
-       iny
        lsr a
        bne -
        lda #0
        sta bn_n+1
        asl bn_n
        rol bn_n+1
        asl bn_n
        rol bn_n+1
        asl bn_n
        rol bn_n+1
        tya
        clc
        adc bn_n
        ldx bn_n+1
        bcc +
        inx
+       rts

; bn_fit - bn_len = top byte of [bnA] + 3
bn_fit: jsr bn_top
        clc
        adc #3
        cmp #BN_LEN
        bcc +
        lda #BN_LEN
+       sta bn_len
        rts

;---------------------------------------------------------------------------------------
; f_parse - decimal text at fsp: digits, '.', digits, [eE][+-]digits (with _ between
; digits) -> DIGBUF / fd_n / fd_exp / fd_sticky, fsp past it. C set if malformed.
;---------------------------------------------------------------------------------------
f_parse:
        lda #0
        sta fd_n
        sta fd_exp
        sta fd_exp+1
        sta fd_sticky
        sta fd_seen
        sta fd_frac
_loop:  jsr fp_peek
        cmp #'_'
        beq _next
        cmp #'.'
        bne +
        lda fd_frac
        bne _exp
        inc fd_frac
        bra _next
+       sec
        sbc #'0'
        cmp #10
        bcs _exp
        sta fw
        inc fd_seen
        ldx fd_n
        bne _keep
        ora #0
        bne _keep
        lda fd_frac                     ; a leading zero: only moves the point
        beq _next
        bra _dec
_keep:  cpx #FD_MAX
        bcc +
        lda fw                          ; past FD_MAX: sticky
        tsb fd_sticky
        lda fd_frac
        bne _next
        inw fd_exp
        bra _next
+       lda fw
        sta DIGBUF,x
        inc fd_n
        lda fd_frac
        beq _next
_dec:   lda fd_exp
        bne +
        dec fd_exp+1
+       dec fd_exp
_next:  inw fsp
        bra _loop
_exp:   lda fd_seen
        beq _bad
        jsr fp_peek
        ora #$20
        cmp #'e'
        bne _ok
        inw fsp
        jsr fp_peek
        ldx #0
        cmp #'+'
        beq +
        cmp #'-'
        bne ++
        dex
+       inw fsp
+       stx fw+1                        ; $ff = negative
        lda #0
        sta bn_n
        sta bn_n+1
        sta fd_seen
_edig:  jsr fp_peek
        cmp #'_'
        beq _enext
        sec
        sbc #'0'
        cmp #10
        bcs _eend
        sta fw
        inc fd_seen
        lda bn_n+1                      ; (capped at 9999)
        cmp #>1000
        bcs _enext
        lda bn_n                        ; bn_n = bn_n * 10 + digit
        ldx bn_n+1
        asl bn_n
        rol bn_n+1
        asl bn_n
        rol bn_n+1
        clc
        adc bn_n
        sta bn_n
        txa
        adc bn_n+1
        sta bn_n+1
        asl bn_n
        rol bn_n+1
        clc
        lda bn_n
        adc fw
        sta bn_n
        bcc _enext
        inc bn_n+1
_enext: inw fsp
        bra _edig
_eend:  lda fd_seen
        beq _bad
        bit fw+1
        bpl +
        sec
        lda #0
        sbc bn_n
        sta bn_n
        lda #0
        sbc bn_n+1
        sta bn_n+1
+       clc
        lda fd_exp
        adc bn_n
        sta fd_exp
        lda fd_exp+1
        adc bn_n+1
        sta fd_exp+1
_ok:    clc
        rts
_bad:   sec
        rts
fp_peek:
        ldz #0
        lda [fsp],z
        rts

;---------------------------------------------------------------------------------------
; f_from_digits - DIGBUF / fd_n / fd_exp / fd_sticky -> fdbl (positive), correctly rounded
;---------------------------------------------------------------------------------------
f_from_digits:
        jsr fa_zero
        lda fd_n
        bne +
_zero:  jmp f_pack
+       ; magnitude t = fd_n + fd_exp: > 310 is inf, < -330 is 0
        clc
        lda fd_n
        adc fd_exp
        sta bn_n
        lda #0
        adc fd_exp+1
        sta bn_n+1
        bmi _small
        lda bn_n
        cmp #<311
        lda bn_n+1
        sbc #>311
        bcc _go
_inf:   lda #FC_INF
        sta fa+F_CLS
        jmp f_pack
_small: lda bn_n
        cmp #<-330
        lda bn_n+1
        sbc #>-330
        bvc +
        eor #$80
+       bmi _zero
_go:    lda #BN_LEN
        sta bn_len
        lda #BN_R                       ; R = D
        jsr bn_a
        jsr bn_zero
        ldx #0
-       phx
        ldy DIGBUF,x
        lda #10
        ldx #0
        jsr bn_mul
        plx
        inx
        cpx fd_n
        bne -
        bit fd_exp+1
        bmi _div
        ; D * 10^E: an integer; its top 64 bits are the mantissa
        lda fd_exp
        ldx fd_exp+1
        jsr bn_pow10
        jsr bn_bitlen
        sta fw
        stx fw+1
        sec                             ; exponent = bits - 1
        sbc #1
        sta fa+F_EXP
        txa
        sbc #0
        sta fa+F_EXP+1
        sec                             ; shift the top bit to the top of the buffer
        lda #<(BN_LEN * 8)
        sbc fw
        pha
        lda #>(BN_LEN * 8)
        sbc fw+1
        tax
        pla
        jsr bn_shl
        ldz #BN_LEN-8
        ldx #0
-       lda [bnA],z
        sta fa+F_MAN,x
        inz
        inx
        cpx #8
        bne -
        ldz #0
        lda fd_sticky
-       ora [bnA],z
        inz
        cpz #BN_LEN-8
        bne -
        cmp #0
        bra _round
_div:   ; D / 10^-E: long division, 64 quotient bits
        lda #BN_S
        jsr bn_a
        jsr bn_one
        sec
        lda #0
        sbc fd_exp
        pha
        lda #0
        sbc fd_exp+1
        tax
        pla
        jsr bn_pow10
        jsr bn_bitlen                   ; d = bits(S) - bits(R)
        sta fw
        stx fw+1
        lda #BN_R
        jsr bn_a
        jsr bn_bitlen
        sta fw+2
        stx fw+3
        sec
        lda fw
        sbc fw+2
        sta fw
        lda fw+1
        sbc fw+3
        sta fw+1
        bmi _shs
        lda fw                          ; R <<= d
        ldx fw+1
        jsr bn_shl
        bra _neg
_shs:   lda #BN_S                       ; S <<= -d
        jsr bn_a
        sec
        lda #0
        sbc fw
        pha
        lda #0
        sbc fw+1
        tax
        pla
        jsr bn_shl
_neg:   sec                             ; exponent = -d
        lda #0
        sbc fw
        sta fa+F_EXP
        lda #0
        sbc fw+1
        sta fa+F_EXP+1
        lda #BN_S
        jsr bn_a
        jsr bn_fit
        lda #BN_S
        jsr bn_b
        lda #BN_R
        jsr bn_a
        jsr bn_cmp                      ; R < S: R <<= 1, one less exponent
        bcs _q
        jsr bn_shl1
        lda fa+F_EXP
        bne +
        dec fa+F_EXP+1
+       dec fa+F_EXP
_q:     lda #64
        sta fw
-       ldx #FA
        jsr m_shl
        jsr bn_cmp
        bcc +
        jsr bn_sub
        inc fa+F_MAN
+       jsr bn_shl1
        dec fw
        bne -
        jsr bn_top
        ora fd_sticky
_round: beq +
        lda fa+F_MAN
        ora #1
        sta fa+F_MAN
+       jmp f_pack
