;=======================================================================================
; Float arithmetic on the unpacked registers (see fcore.asm). Each operation leaves
; its exact result in fa, truncated to 64 bits with a sticky bit: f_pack (or f_rnd)
; then rounds it the way IEEE double arithmetic does.
;=======================================================================================
fprod:          .fill 16                ; 128-bit product
frem:           .fill 9                 ; division / sqrt remainder (65+ bits)
ftry:           .fill 9

;---------------------------------------------------------------------------------------
; f_add / f_sub - fa = fa +/- fb
;---------------------------------------------------------------------------------------
f_sub:
        lda fb+F_SIGN
        eor #$80
        sta fb+F_SIGN
f_add:
        lda fa+F_CLS
        ora fb+F_CLS
        beq _fin
        lda #FC_NAN
        cmp fa+F_CLS
        beq _ret
        cmp fb+F_CLS
        beq _useb
        lda fa+F_CLS
        beq _useb                       ; finite + inf
        lda fb+F_CLS
        beq _ret                        ; inf + finite
        lda fa+F_SIGN                   ; inf + inf
        cmp fb+F_SIGN
        beq _ret
        jmp f_set_nan
_useb:  ldx #FB
        ldy #FA
        jmp f_mov
_ret:   rts
_fin:   ldx #FB
        jsr m_zero
        bne _bnz
        ldx #FA
        jsr m_zero
        bne _ret                        ; x + 0
        lda fa+F_SIGN                   ; 0 + 0 is -0 only for -0 + -0
        and fb+F_SIGN
        sta fa+F_SIGN
        rts
_bnz:   ldx #FA
        jsr m_zero
        beq _useb                       ; 0 + y
        ; fa gets the larger exponent; fw = the difference
        sec
        lda fa+F_EXP
        sbc fb+F_EXP
        sta fw
        lda fa+F_EXP+1
        sbc fb+F_EXP+1
        sta fw+1
        bvc +
        eor #$80
+       bpl _align
        jsr f_swap
        sec
        lda #0
        sbc fw
        sta fw
        lda #0
        sbc fw+1
        sta fw+1
_align: lda fw+1                        ; 66 or more: fb is only a sticky bit
        bne _tiny
        lda fw
        cmp #66
        bcs _tiny
        tay
        beq _op
-       ldx #FB
        jsr m_shr
        dey
        bne -
        bra _op
_tiny:  ldx #7
        lda #0
-       sta fb+F_MAN,x
        dex
        bpl -
        inc fb+F_MAN
_op:    lda fa+F_SIGN
        cmp fb+F_SIGN
        bne _subm
        clc
        ldx #0
        ldy #8
-       lda fa+F_MAN,x
        adc fb+F_MAN,x
        sta fa+F_MAN,x
        inx
        dey
        bne -
        bcc _ret
        ldx #FA                         ; carry out: shift it back in at bit 63
        jsr m_shr
        lda fa+F_MAN+7
        ora #$80
        sta fa+F_MAN+7
        jmp fa_inc_exp
_subm:  ldx #7                          ; subtract the smaller magnitude
-       lda fa+F_MAN,x
        cmp fb+F_MAN,x
        bne +
        dex
        bpl -
        lda #0                          ; equal: +0
        sta fa+F_SIGN
        bra _agt
+       bcs _agt
        lda fb+F_SIGN
        sta fa+F_SIGN
        sec
        ldx #0
        ldy #8
-       lda fb+F_MAN,x
        sbc fa+F_MAN,x
        sta fa+F_MAN,x
        inx
        dey
        bne -
        jmp fa_norm
_agt:   sec
        ldx #0
        ldy #8
-       lda fa+F_MAN,x
        sbc fb+F_MAN,x
        sta fa+F_MAN,x
        inx
        dey
        bne -
        jmp fa_norm

f_swap:
        ldx #11
-       lda fa,x
        ldy fb,x
        sta fb,x
        tya
        sta fa,x
        dex
        bpl -
        rts

;---------------------------------------------------------------------------------------
; specials shared by mul and div: sign = xor; C set when the result is decided
;---------------------------------------------------------------------------------------
f_xsign:
        lda fa+F_SIGN
        eor fb+F_SIGN
        sta fa+F_SIGN
        rts

;---------------------------------------------------------------------------------------
; f_mul - fa = fa * fb
;---------------------------------------------------------------------------------------
f_mul:
        jsr f_xsign
        lda fa+F_CLS
        ora fb+F_CLS
        beq _fin
        lda #FC_NAN
        cmp fa+F_CLS
        beq _ret
        cmp fb+F_CLS
        beq _nan
        lda fa+F_CLS
        bne _ainf
        ldx #FA                         ; finite * inf
        jsr m_zero
        beq _nan
        lda #FC_INF
        sta fa+F_CLS
_ret:   rts
_ainf:  lda fb+F_CLS                    ; inf * x
        bne _ret
        ldx #FB
        jsr m_zero
        bne _ret
_nan:   jmp f_set_nan
_fin:   ldx #FA
        jsr m_zero
        beq _ret                        ; 0 * y
        ldx #FB
        jsr m_zero
        bne +
        jmp fa_zero_signed              ; x * 0
+       clc
        lda fa+F_EXP
        adc fb+F_EXP
        sta fa+F_EXP
        lda fa+F_EXP+1
        adc fb+F_EXP+1
        sta fa+F_EXP+1
        ; 128-bit product: lo*lo, hi*hi, then the cross terms at byte 4
        ldq fa+F_MAN
        stq MULTINA
        ldq fb+F_MAN
        stq MULTINB
        ldq MULTOUT
        stq fprod
        ldq MULTOUT+4
        stq fprod+4
        ldq fa+F_MAN+4
        stq MULTINA
        ldq fb+F_MAN+4
        stq MULTINB
        ldq MULTOUT
        stq fprod+8
        ldq MULTOUT+4
        stq fprod+12
        ldq fb+F_MAN
        stq MULTINB
        jsr _cross
        ldq fa+F_MAN
        stq MULTINA
        ldq fb+F_MAN+4
        stq MULTINB
        jsr _cross
        ; normalise: bit 127 set adds one to the exponent, else shift left
        bit fprod+15
        bmi +
        ldx #0
        ldy #16
        clc
-       rol fprod,x
        inx
        dey
        bne -
        bra ++
+       jsr fa_inc_exp
+       ldx #7
-       lda fprod+8,x
        sta fa+F_MAN,x
        dex
        bpl -
        lda fprod                       ; sticky
        ora fprod+1
        ora fprod+2
        ora fprod+3
        ora fprod+4
        ora fprod+5
        ora fprod+6
        ora fprod+7
        beq +
        lda fa+F_MAN
        ora #1
        sta fa+F_MAN
+       rts
_cross: ; fprod[4..15] += MULTOUT
        clc
        ldx #0
        ldy #8
-       lda fprod+4,x
        adc MULTOUT,x
        sta fprod+4,x
        inx
        dey
        bne -
        ldy #4
-       lda fprod+4,x
        adc #0
        sta fprod+4,x
        inx
        dey
        bne -
        rts

; fa = 0 with the sign kept
fa_zero_signed:
        lda fa+F_SIGN
        pha
        jsr fa_zero
        pla
        sta fa+F_SIGN
        rts

;---------------------------------------------------------------------------------------
; f_div - fa = fa / fb (ZeroDivisionError for a zero divisor)
;---------------------------------------------------------------------------------------
f_div:
        jsr f_xsign
        lda fa+F_CLS
        ora fb+F_CLS
        beq _fin
        lda #FC_NAN
        cmp fa+F_CLS
        beq _ret
        cmp fb+F_CLS
        beq _nan
        lda fa+F_CLS
        beq _zero                       ; finite / inf
        lda fb+F_CLS
        beq _ret                        ; inf / finite
_nan:   jmp f_set_nan                   ; inf / inf
_zero:  jmp fa_zero_signed
_ret:   rts
_fin:   ldx #FB
        jsr m_zero
        bne +
        jmp raise_fzerodiv
+       ldx #FA
        jsr m_zero
        beq _ret                        ; 0 / y
        sec
        lda fa+F_EXP
        sbc fb+F_EXP
        sta fa+F_EXP
        lda fa+F_EXP+1
        sbc fb+F_EXP+1
        sta fa+F_EXP+1
        jsr m_to_rem                    ; frem = fa's mantissa
        jsr rem_cmp                     ; below the divisor: double it, one less exponent
        bcs _div
        jsr rem_shl
        lda fa+F_EXP
        bne +
        dec fa+F_EXP+1
+       dec fa+F_EXP
_div:   lda #64
        sta fw+2
-       ldx #FA
        jsr m_shl
        jsr rem_cmp
        bcc +
        jsr rem_sub
        inc fa+F_MAN
+       jsr rem_shl
        dec fw+2
        bne -
        ; sticky: a remainder left over
rem_sticky:
        ldx #8
        lda #0
-       ora frem,x
        dex
        bpl -
        cmp #0
        beq +
        lda fa+F_MAN
        ora #1
        sta fa+F_MAN
+       rts

raise_fzerodiv:
        #RAISE EXC_ZERODIV, "float division by zero"

; frem = mantissa of fa (9 bytes), fa's mantissa = 0
m_to_rem:
        ldx #7
-       lda fa+F_MAN,x
        sta frem,x
        lda #0
        sta fa+F_MAN,x
        dex
        bpl -
        sta frem+8
        rts
; rem_cmp - C set if frem >= fb's mantissa
rem_cmp:
        lda frem+8
        bne _ge
        ldx #7
-       lda frem,x
        cmp fb+F_MAN,x
        bne +
        dex
        bpl -
_ge:    sec
+       rts
; rem_sub - frem -= fb's mantissa
rem_sub:
        sec
        ldx #0
        ldy #8
-       lda frem,x
        sbc fb+F_MAN,x
        sta frem,x
        inx
        dey
        bne -
        lda frem+8
        sbc #0
        sta frem+8
        rts
rem_shl:
        asl frem
        ldx #1
        ldy #8
-       rol frem,x
        inx
        dey
        bne -
        rts

;---------------------------------------------------------------------------------------
; f_fmod - fa = fmod(fa, fb): exact, with the sign of fa. Returns nan for inf or a
; zero divisor (the callers check for those first).
;---------------------------------------------------------------------------------------
f_fmod:
        lda fa+F_CLS
        bne _nan
        lda fb+F_CLS
        cmp #FC_NAN
        beq _nan
        cmp #FC_INF
        beq _ret                        ; fmod(x, inf) = x
        ldx #FB
        jsr m_zero
        beq _nan
        ldx #FA
        jsr m_zero
        beq _ret
        ; |x| < |y|: x
        sec
        lda fa+F_EXP
        sbc fb+F_EXP
        sta fw
        lda fa+F_EXP+1
        sbc fb+F_EXP+1
        sta fw+1
        bvc +
        eor #$80
+       bmi _ret
        jsr m_to_rem
_loop:  jsr rem_cmp
        bcc +
        jsr rem_sub
+       lda fw
        ora fw+1
        beq _done
        jsr rem_shl
        lda fw
        bne +
        dec fw+1
+       dec fw
        bra _loop
_done:  ldx #7
-       lda frem,x
        sta fa+F_MAN,x
        dex
        bpl -
        lda fb+F_EXP
        sta fa+F_EXP
        lda fb+F_EXP+1
        sta fa+F_EXP+1
        jmp fa_norm
_nan:   jmp f_set_nan
_ret:   rts

;---------------------------------------------------------------------------------------
; f_cmp - compare fa with fb -> A = $ff (less), 0 (equal), 1 (greater), 2 (unordered).
; Changes fa and fb.
;---------------------------------------------------------------------------------------
f_cmp:
        lda #FC_NAN
        cmp fa+F_CLS
        beq _un
        cmp fb+F_CLS
        beq _un
        lda fa+F_CLS                    ; inf vs inf of the same sign: equal
        and fb+F_CLS
        beq +
        lda fa+F_SIGN
        cmp fb+F_SIGN
        beq _eq
+       jsr f_sub
        lda fa+F_CLS
        bne _sign                       ; inf
        ldx #FA
        jsr m_zero
        beq _eq
_sign:  lda fa+F_SIGN
        bmi _lt
        lda #1
        rts
_lt:    lda #$ff
        rts
_eq:    lda #0
        rts
_un:    lda #2
        rts

;---------------------------------------------------------------------------------------
; f_trunc - fa = trunc(fa); C set if a fraction was cut off
;---------------------------------------------------------------------------------------
f_trunc:
        lda fa+F_CLS
        bne _exact
        ldx #FA
        jsr m_zero
        beq _exact
        lda fa+F_EXP+1
        bpl +
        jsr fa_zero_signed              ; |x| < 1
        sec
        rts
+       bne _exact
        lda fa+F_EXP
        cmp #63
        bcs _exact
        ; clear the low 63 - exponent bits
        eor #$ff
        sec
        adc #63                         ; A = 63 - exponent
        sta fw
        lda #0
        sta fw+1                        ; anything cleared?
        ldx #0
-       lda fw
        cmp #8
        bcc +
        lda fa+F_MAN,x
        tsb fw+1
        lda #0
        sta fa+F_MAN,x
        inx
        lda fw
        sbc #8
        sta fw
        bra -
+       tay
        lda f_lomask,y
        and fa+F_MAN,x
        tsb fw+1
        lda f_lomask,y
        eor #$ff
        and fa+F_MAN,x
        sta fa+F_MAN,x
        lda fw+1
        cmp #1                          ; C set if non-zero
        rts
_exact: clc
        rts
f_lomask:       .byte 0, 1, 3, 7, 15, 31, 63, 127

; f_floor / f_ceil - fa = floor(fa) / ceil(fa)
f_floor:
        jsr f_trunc
        bcc +
        lda fa+F_SIGN
        bpl +
        bra f_addone_neg
f_ceil:
        jsr f_trunc
        bcc +
        lda fa+F_SIGN
        bmi +
        bra f_addone
+       rts
f_addone_neg:                           ; fa = fa - 1
        ldx #FB
        lda #0
        jsr f_one
        jsr f_sub
        jmp f_rnd
f_addone:                               ; fa = fa + 1
        ldx #FB
        lda #0
        jsr f_one
        jsr f_add
        jmp f_rnd

;---------------------------------------------------------------------------------------
; f_divmod - Python's float floor division and modulo (as CPython's float_divmod):
; fa = vx, fb = wx -> fa = vx // wx, fe = vx % wx
;---------------------------------------------------------------------------------------
dm_sign:        .byte 0
f_divmod:
        lda fb+F_CLS
        bne +
        ldx #FB
        jsr m_zero
        bne +
        jmp raise_fzerodiv
+       lda fa+F_SIGN
        eor fb+F_SIGN
        sta dm_sign
        ldx #FA
        ldy #FC
        jsr f_mov                       ; fc = vx
        ldx #FB
        ldy #FD
        jsr f_mov                       ; fd = wx
        jsr f_fmod
        ldx #FA
        ldy #FE
        jsr f_mov                       ; fe = mod
        ldx #FC                         ; div = (vx - mod) / wx
        ldy #FA
        jsr f_mov
        ldx #FE
        ldy #FB
        jsr f_mov
        jsr f_sub
        jsr f_rnd
        ldx #FD
        ldy #FB
        jsr f_mov
        jsr f_div
        jsr f_rnd
        ldx #FA
        ldy #FC
        jsr f_mov                       ; fc = div
        ; mod != 0: if its sign differs from wx's, mod += wx and div -= 1
        lda fe+F_CLS
        bne _modnz
        ldx #FE
        jsr m_zero
        bne _modnz
        lda fd+F_SIGN                   ; mod = 0 with the sign of wx
        sta fe+F_SIGN
        bra _floor
_modnz: lda fd+F_SIGN
        eor fe+F_SIGN
        bpl _floor
        ldx #FE
        ldy #FA
        jsr f_mov
        ldx #FD
        ldy #FB
        jsr f_mov
        jsr f_add
        jsr f_rnd
        ldx #FA
        ldy #FE
        jsr f_mov
        ldx #FC
        ldy #FA
        jsr f_mov
        jsr f_addone_neg
        ldx #FA
        ldy #FC
        jsr f_mov
_floor: ; div != 0: floordiv = floor(div), plus 1 if div - floordiv > 0.5
        ldx #FC
        ldy #FA
        jsr f_mov
        lda fa+F_CLS
        bne +
        ldx #FA
        jsr m_zero
        bne +
        lda dm_sign                     ; 0 with the sign of vx / wx
        sta fa+F_SIGN
        rts
+       jsr f_floor
        ldx #FA
        ldy #FD
        jsr f_mov                       ; fd = floordiv
        ldx #FD
        ldy #FB
        jsr f_mov
        ldx #FC
        ldy #FA
        jsr f_mov
        jsr f_sub
        ldx #FB
        lda #$ff
        jsr f_one
        jsr f_cmp
        pha
        ldx #FD
        ldy #FA
        jsr f_mov
        pla
        cmp #1
        bne +
        jmp f_addone
+       rts

;---------------------------------------------------------------------------------------
; f_sqrt - fa = sqrt(fa) (ValueError for negative numbers)
;---------------------------------------------------------------------------------------
f_sqrt:
        lda fa+F_CLS
        cmp #FC_NAN
        beq _ret
        ldx #FA
        jsr m_zero
        beq _ret                        ; sqrt(+-0) = +-0
        lda fa+F_SIGN
        beq +
        #RAISE EXC_VALUE, "math domain error"
+       lda fa+F_CLS
        bne _ret                        ; inf
        ; radicand N (128 bits, in fprod) = mantissa << 63, or << 64 for odd exponents
        ldx #7
-       lda fa+F_MAN,x
        sta fprod+8,x
        lda #0
        sta fprod,x
        sta fa+F_MAN,x
        dex
        bpl -
        lda fa+F_EXP
        and #1
        bne +
        lsr fprod+15                    ; even exponent: << 63
        ldx #14
-       ror fprod,x
        dex
        bpl -
+       lda fa+F_EXP+1                  ; the root's exponent: floor(exponent / 2)
        cmp #$80
        ror fa+F_EXP+1
        ror fa+F_EXP
        ; bit by bit: rem = rem << 2 | next two bits; trial = root << 2 | 1
        ldx #8
        lda #0
-       sta frem,x
        dex
        bpl -
        lda #64
        sta fw+2
_loop:  jsr _shl2                       ; (fprod and frem are one 25-byte number)
        jsr _shl2
        ; trial = root * 4 + 1 (66 bits)
        ldx #7
-       lda fa+F_MAN,x
        sta ftry,x
        dex
        bpl -
        lda #0
        sta ftry+8
        jsr _tshl
        jsr _tshl
        lda ftry
        ora #1
        sta ftry
        ; root <<= 1; if rem >= trial: rem -= trial, root |= 1
        ldx #FA
        jsr m_shl
        ldx #8
-       lda frem,x
        cmp ftry,x
        bne +
        dex
        bpl -
+       bcc _next
        sec
        ldx #0
        ldy #9
-       lda frem,x
        sbc ftry,x
        sta frem,x
        inx
        dey
        bne -
        inc fa+F_MAN
_next:  dec fw+2
        bne _loop
        jmp rem_sticky
_ret:   rts
_shl2:  asl fprod
        ldx #1
        ldy #24
-       rol fprod,x
        inx
        dey
        bne -
        rts
_tshl:  asl ftry
        ldx #1
        ldy #8
-       rol ftry,x
        inx
        dey
        bne -
        rts
