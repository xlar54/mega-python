;=======================================================================================
; Floats (IEEE 754 double), core: packing, unpacking, int conversion, float objects.
;
; A float object is T_FLOAT: +4..+11 the double, little-endian.
; Arithmetic works on unpacked registers (fa, fb, ... fg; 12 bytes each, in a row):
;   +0 class (FC_FIN, FC_INF, FC_NAN)  +1 sign ($80 = negative)
;   +2 exponent (signed word)          +4 mantissa (8 bytes, little-endian)
; value = mantissa * 2^(exponent - 63); a finite non-zero mantissa has bit 63 set.
; The low 11 mantissa bits are extra precision: results are kept truncated to 64 bits
; with a lost 1 bit "jammed" into bit 0, so f_pack rounds them correctly (to nearest,
; ties to even). Routines that take a register in X use the offsets FA..FG.
;=======================================================================================
F_CLS           = 0
F_SIGN          = 1
F_EXP           = 2
F_MAN           = 4
FC_FIN          = 0
FC_INF          = 1
FC_NAN          = 2
FA              = 0
FB              = 12
FC              = 24
FD              = 36
FE              = 48
FF              = 60
FG              = 72
FH              = 84
FI              = 96

fa:             .fill 12
fb:             .fill 12
fc:             .fill 12
fd:             .fill 12
fe:             .fill 12
ff:             .fill 12
fg:             .fill 12
fh:             .fill 12
fi:             .fill 12
fdbl:           .fill 8                 ; a packed double
fw:             .fill 4                 ; scratch

; f_mov - copy register X to register Y
f_mov:
        lda #12
        sta fw
-       lda fa,x
        sta fa,y
        inx
        iny
        dec fw
        bne -
        rts

; m_zero - Z set if the mantissa of register X is zero
m_zero:
        lda fa+F_MAN,x
        ora fa+F_MAN+1,x
        ora fa+F_MAN+2,x
        ora fa+F_MAN+3,x
        ora fa+F_MAN+4,x
        ora fa+F_MAN+5,x
        ora fa+F_MAN+6,x
        ora fa+F_MAN+7,x
        rts

; m_shl - mantissa of register X << 1 (C = the bit shifted out)
m_shl:
        asl fa+F_MAN,x
        rol fa+F_MAN+1,x
        rol fa+F_MAN+2,x
        rol fa+F_MAN+3,x
        rol fa+F_MAN+4,x
        rol fa+F_MAN+5,x
        rol fa+F_MAN+6,x
        rol fa+F_MAN+7,x
        rts

; m_shr - mantissa of register X >> 1; a 1 shifted out stays in bit 0
m_shr:
        lsr fa+F_MAN+7,x
        ror fa+F_MAN+6,x
        ror fa+F_MAN+5,x
        ror fa+F_MAN+4,x
        ror fa+F_MAN+3,x
        ror fa+F_MAN+2,x
        ror fa+F_MAN+1,x
        ror fa+F_MAN,x
        bcc +
        lda fa+F_MAN,x
        ora #1
        sta fa+F_MAN,x
+       rts

; fa_zero - fa = +0
fa_zero:
        ldx #11
        lda #0
-       sta fa,x
        dex
        bpl -
        rts

; f_one - register X = 2^A (A = exponent: 0 for 1.0, $ff for 0.5)
f_one:
        sta fa+F_EXP,x
        and #$80
        beq +
        lda #$ff
+       sta fa+F_EXP+1,x
        lda #0
        sta fa+F_CLS,x
        sta fa+F_SIGN,x
        ldy #7
-       sta fa+F_MAN,x
        inx
        dey
        bne -
        lda #$80
        sta fa+F_MAN,x
        rts

; fa_norm / f_norm - normalise fa / register X (bit 63 set), adjusting the exponent;
; zero gets exponent 0
fa_norm:
        ldx #FA
f_norm: jsr m_zero
        beq _zero
_loop:  bit fa+F_MAN+7,x
        bmi _done
        jsr m_shl
        lda fa+F_EXP,x
        bne +
        dec fa+F_EXP+1,x
+       dec fa+F_EXP,x
        bra _loop
_done:  rts
_zero:  lda #0
        sta fa+F_EXP,x
        sta fa+F_EXP+1,x
        rts

fa_inc_exp:
        inc fa+F_EXP
        bne +
        inc fa+F_EXP+1
+       rts

f_set_nan:
        lda #FC_NAN
        sta fa+F_CLS
        rts

;---------------------------------------------------------------------------------------
; f_unpack - fdbl -> fa
;---------------------------------------------------------------------------------------
f_unpack:
        lda fdbl+7
        and #$80
        sta fa+F_SIGN
        lda fdbl+7                      ; exponent bits = ((b7 & $7f) << 8 | b6) >> 4
        and #$7f
        sta fa+F_EXP+1
        lda fdbl+6
        sta fa+F_EXP
        ldx #4
-       lsr fa+F_EXP+1
        ror fa+F_EXP
        dex
        bne -
        ldx #6                          ; mantissa = fraction << 11
-       lda fdbl,x
        sta fa+F_MAN+1,x
        dex
        bpl -
        lda fa+F_MAN+7
        and #$0f
        sta fa+F_MAN+7
        lda #0
        sta fa+F_MAN
        sta fa+F_CLS
        ldy #3
-       ldx #FA
        jsr m_shl
        dey
        bne -
        lda fa+F_EXP+1
        cmp #$07
        bne _notmax
        lda fa+F_EXP
        cmp #$ff
        bne _notmax
        ldx #FA                         ; exponent bits $7ff: inf or nan
        jsr m_zero
        beq +
        lda #FC_NAN
        sta fa+F_CLS
        rts
+       lda #FC_INF
        sta fa+F_CLS
        rts
_notmax:
        lda fa+F_EXP
        ora fa+F_EXP+1
        bne _normal
        ldx #FA                         ; zero or subnormal
        jsr m_zero
        bne +
        rts
+       lda #<-1022
        sta fa+F_EXP
        lda #>-1022
        sta fa+F_EXP+1
        jmp fa_norm
_normal:
        lda fa+F_MAN+7
        ora #$80
        sta fa+F_MAN+7
        sec
        lda fa+F_EXP
        sbc #<1023
        sta fa+F_EXP
        lda fa+F_EXP+1
        sbc #>1023
        sta fa+F_EXP+1
        rts

;---------------------------------------------------------------------------------------
; f_pack - fa -> fdbl, rounding to nearest even (overflow gives inf). Changes fa.
;---------------------------------------------------------------------------------------
f_pack:
        lda fa+F_CLS
        cmp #FC_NAN
        bne +
        ldx #7                          ; a quiet NaN
-       lda f_nan,x
        sta fdbl,x
        dex
        bpl -
        rts
+       cmp #FC_INF
        bne +
        jmp _inf
+       ldx #FA
        jsr m_zero
        bne _num
        ldx #6                          ; zero
        lda #0
-       sta fdbl,x
        dex
        bpl -
        lda fa+F_SIGN
        sta fdbl+7
        rts
_num:   ; below the normal range: shift right (keeping a sticky bit) to exponent -1022
        lda fa+F_EXP+1
        bpl _round
        cmp #>-1022
        bcc _sub
        bne _round
        lda fa+F_EXP
        cmp #<-1022
        bcs _round
_sub:   lda fa+F_EXP+1                  ; far below: just a sticky bit
        cmp #>-1100
        bcs +
        lda #<-1022
        sta fa+F_EXP
        lda #>-1022
        sta fa+F_EXP+1
        ldx #7
        lda #0
-       sta fa+F_MAN,x
        dex
        bpl -
        inc fa+F_MAN
        bra _round
+       ldx #FA
        jsr m_shr
        jsr fa_inc_exp
        bra _num
_round: ; the low 11 bits round: bit 10 is the half
        lda fa+F_MAN+1
        and #4
        beq _down                       ; below half
        lda fa+F_MAN+1
        and #3
        ora fa+F_MAN
        bne _up                         ; above half
        lda fa+F_MAN+1                  ; exactly half: to even (bit 11)
        and #8
        beq _down
_up:    clc                             ; add 1 at bit 11
        lda fa+F_MAN+1
        adc #8
        sta fa+F_MAN+1
        ldx #2
        ldy #6
-       lda fa+F_MAN,x
        adc #0
        sta fa+F_MAN,x
        inx
        dey
        bne -
        bcc _down
        ror fa+F_MAN+7                  ; carried out of bit 63: 1.000...
        jsr fa_inc_exp
_down:  ; normal (bit 63 set) or subnormal (exponent -1022, bit 63 clear)?
        lda #0
        sta fw                          ; biased exponent
        sta fw+1
        bit fa+F_MAN+7
        bpl _bits
        lda fa+F_EXP+1                  ; above 1023: overflow
        bmi +
        cmp #>1024
        bcc +
        jmp _inf
+       clc
        lda fa+F_EXP
        adc #<1023
        sta fw
        lda fa+F_EXP+1
        adc #>1023
        sta fw+1
_bits:  ; fraction = mantissa bits 11-62
        ldy #3
-       lsr fa+F_MAN+7
        ror fa+F_MAN+6
        ror fa+F_MAN+5
        ror fa+F_MAN+4
        ror fa+F_MAN+3
        ror fa+F_MAN+2
        ror fa+F_MAN+1
        dey
        bne -
        ldx #6
-       lda fa+F_MAN+1,x
        sta fdbl,x
        dex
        bpl -
        lda fdbl+6                      ; byte 6: fraction bits 48-51, exponent bits 0-3
        and #$0f
        sta fdbl+6
        lda fw
        asl
        asl
        asl
        asl
        ora fdbl+6
        sta fdbl+6
        lda fw+1                        ; byte 7: sign, exponent bits 4-10
        asl
        asl
        asl
        asl
        sta fdbl+7
        lda fw
        lsr
        lsr
        lsr
        lsr
        ora fdbl+7
        ora fa+F_SIGN
        sta fdbl+7
        rts
_inf:   lda #0
        ldx #5
-       sta fdbl,x
        dex
        bpl -
        lda #$f0
        sta fdbl+6
        lda #$7f
        ora fa+F_SIGN
        sta fdbl+7
        rts
f_nan:          .byte 0, 0, 0, 0, 0, 0, $f8, $7f

; f_rnd - round fa to a double in place
f_rnd:
        jsr f_pack
        jmp f_unpack

;---------------------------------------------------------------------------------------
; ints
;---------------------------------------------------------------------------------------
; f_from_int - acc (signed 32-bit) -> fa (exact)
f_from_int:
        jsr fa_zero
        bit acc+3
        bpl +
        lda #$80
        sta fa+F_SIGN
        jsr acc_neg                     ; (-2^31 stays $80000000: right as unsigned)
+       ldq acc
        stq fa+F_MAN+4
        lda #31
        sta fa+F_EXP
        jmp fa_norm

;---------------------------------------------------------------------------------------
; float objects
;---------------------------------------------------------------------------------------
; float_load - A/X = float object -> fdbl
float_load:
        sta p0
        stx p0+1
        ldz #4
        ldx #0
-       lda [p0],z
        sta fdbl,x
        inz
        inx
        cpx #8
        bne -
        rts

; float_new - fa -> A/X = a new float object (rounded); float_new_dbl - from fdbl
float_new:
        jsr f_pack
float_new_dbl:
        lda #12
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_FLOAT
        jsr alloc
        ldz #4
        ldx #0
-       lda fdbl,x
        sta [p0],z
        inz
        inx
        cpx #8
        bne -
        lda p0
        ldx p0+1
        rts
