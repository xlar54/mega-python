;=======================================================================================
; Floats, tail A: float <-> text for repr(), format(),
; float(), and round(), hash(), divmod().
;=======================================================================================
; float_hash - hash() of the float A/X: the int's hash when integral
xa_float_hash:
        jsr float_load
        jsr f_unpack
        ldx #FA
        ldy #FC
        jsr f_mov
        jsr f_trunc
        bcs _bits
        jsr f_to_int
        bcs _bits
        jmp int_new
_bits:  lda fdbl                        ; mix the bits into 30
        eor fdbl+4
        sta acc
        lda fdbl+1
        eor fdbl+5
        sta acc+1
        lda fdbl+2
        eor fdbl+6
        sta acc+2
        lda fdbl+3
        eor fdbl+7
        and #$3f
        sta acc+3
        jmp int_new

; repr_float - append repr(float A/X)
xa_repr_float:
        jsr float_load
        lda #'r'
        sta ff_type
        lda #'-'
        sta ff_sign
        lda #0
        sta ff_upper
        sta ff_comma
        jmp sb_float

; format_float - append r2 (int or float) formatted by the fs_* fields
xa_format_float:
        lda #0
        sta ff_upper
        lda fs_type
        bne +
        lda #'r'                        ; no type: repr, or 'g'-like with a precision
        ldx fs_prec+1
        cpx #$ff
        beq ++
        lda #'n'
        bra ++
+       cmp #'A'
        bcc +
        cmp #'a'
        bcs +
        ora #$20                        ; E F G: upper case
        ldx #$20
        stx ff_upper
+       ldx #_ntypes-1
-       cmp _types,x
        beq +
        dex
        bpl -
        #RAISE EXC_VALUE, "unknown format code for a float"
+       sta ff_type
        lda fs_sign
        sta ff_sign
        lda fs_comma
        sta ff_comma
        lda fs_prec
        sta ff_prec
        lda fs_prec+1
        sta ff_prec+1
        lda r2
        ldx r2+1
        jsr is_float
        bcc +
        lda r2
        ldx r2+1
        jsr float_load
        jmp sb_float
+       lda r2
        ldx r2+1
        jsr int_val
        jsr f_from_int
        jsr f_pack
        jmp sb_float
_types: .text "rnfeg%"
_ntypes = * - _types

xa_bi_float:
        #NARGS 0, 1
        lda npos
        bne +
        jsr fa_zero
        jmp float_new
+       #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_FLOAT
        bne +
        lda r2
        ldx r2+1
        rts
+       cmp #T_STR
        beq _str
        lda r2
        ldx r2+1
        jsr num_to_fa
        bcs +
        jmp float_new
+       #RAISE EXC_TYPE, "float() argument must be a string or a real number"
_str:   ; copy the text to LINEBUF (zero-terminated), then parse it
        lda r2
        ldx r2+1
        jsr str_info
        lda str_len+1
        bne _bad
        lda str_len
        cmp #255
        bcs _bad
        ldx #0
        ldz #0
-       cpx str_len
        beq +
        lda [fp0],z
        sta LINEBUF,x
        inx
        inz
        bra -
+       lda #0
        sta LINEBUF,x
        jsr parse_float_buf
        bcs _bad
        jmp float_new_dbl
_bad:   jsr sb_mark_t5
        #SBPRINT "could not convert string to float: "
        lda r2
        ldx r2+1
        jsr obj_repr
        lda #EXC_VALUE
        jmp raise_sb

; parse_float_buf - LINEBUF -> fdbl: [ws][sign](digits | inf | infinity | nan)[ws]
; C set if malformed
parse_float_buf:
        lda #<LINEBUF
        sta fsp
        lda #>LINEBUF
        sta fsp+1
        lda #0
        sta fsp+2
        sta fsp+3
        jsr _ws
        lda #0
        sta fw+3                        ; sign
        jsr fp_peek
        cmp #'+'
        beq +
        cmp #'-'
        bne ++
        lda #$80
        sta fw+3
+       inw fsp
+       jsr fp_peek
        ora #$20
        cmp #'i'
        beq _inf
        cmp #'n'
        beq _nan
        jsr f_parse
        bcs _no
        lda fw+3
        pha
        jsr f_from_digits
        pla
        sta fw+3
_end:   jsr _ws
        jsr fp_peek
        bne _no
        lda fdbl+7
        ora fw+3
        sta fdbl+7
        clc
        rts
_no:    sec
        rts
_inf:   ldx #_tinf-_words
        jsr _word
        bcs _no
        lda #FC_INF
        bra _spec
_nan:   ldx #_tnan-_words
        jsr _word
        bcs _no
        lda #FC_NAN
_spec:  pha
        jsr fa_zero
        pla
        sta fa+F_CLS
        jsr f_pack
        bra _end
_word:  ; match the word at _tinf / _tnan (X = its offset in _words), case-insensitively
        ldz #0
-       lda _words,x
        beq _wok
        lda [fsp],z
        ora #$20
        cmp _words,x
        bne _wno
        inz
        inx
        bra -
_wok:   tza
        clc
        adc fsp
        sta fsp
        bcc +
        inc fsp+1
+       ldx #0                          ; "inf" may go on to "infinity"
        ldz #0
-       lda _tinity,x
        beq +
        lda [fsp],z
        ora #$20
        cmp _tinity,x
        bne _wdone
        inz
        inx
        bra -
+       tza
        clc
        adc fsp
        sta fsp
        bcc _wdone
        inc fsp+1
_wdone: clc
        rts
_wno:   sec
        rts
_ws:    jsr fp_peek
        cmp #' '
        beq +
        cmp #9
        bne ++
+       inw fsp
        bra _ws
+       rts
_words:
_tinf:  .text "inf", 0
_tnan:  .text "nan", 0
_tinity: .text "inity", 0

; round(x[, n])
xa_float_round:
        lda npos
        cmp #2
        bne _int
        #ARG 1
        cpx #0
        bne +
        cmp #R_NONE
        beq _int
+       jsr need_int
        #ARG 0
        jsr float_load
        jsr f_unpack
        lda fa+F_CLS
        beq +
        #ARG 0                          ; inf, nan: as they are
        rts
+       lda acc+3                       ; more than 300 decimals: unchanged
        bmi _neg
        ora acc+2
        bne _same
        lda acc
        cmp #<301
        lda acc+1
        sbc #>301
        bcc _go
_same:  #ARG 0
        rts
_neg:   lda acc+3                       ; fewer than -330: zero
        and acc+2
        cmp #$ff
        bne _zero
        lda acc
        cmp #<-330
        lda acc+1
        sbc #>-330
        bvc +
        eor #$80
+       bmi _zero
_go:    lda #2                          ; the digits, rounded half-to-even, read back
        sta fd_mode
        lda acc
        sta fd_prec
        lda acc+1
        sta fd_prec+1
        lda fdbl+7
        and #$80
        pha
        jsr f_digits
        sec                             ; D * 10^(dec - n)
        lda fd_dec
        sbc fd_n
        sta fd_exp
        lda fd_dec+1
        sbc #0
        sta fd_exp+1
        lda #0
        sta fd_sticky
        jsr f_from_digits
        pla
        ora fdbl+7
        sta fdbl+7
        jmp float_new_dbl
_zero:  lda fdbl+7
        and #$80
        pha
        jsr fa_zero
        jsr f_pack
        pla
        sta fdbl+7
        jmp float_new_dbl
_int:   ; round half to even -> int
        #ARG 0
        jsr float_load
        jsr f_unpack
        ldx #FA
        ldy #FC
        jsr f_mov                       ; fc = x
        jsr f_trunc
        bcs +
        jmp f_int_result
+       ldx #FA
        ldy #FD
        jsr f_mov                       ; fd = t
        ldx #FD
        ldy #FB
        jsr f_mov
        ldx #FC
        ldy #FA
        jsr f_mov
        jsr f_sub                       ; |x - t| vs 0.5
        lda #0
        sta fa+F_SIGN
        ldx #FB
        lda #$ff
        jsr f_one
        jsr f_cmp
        pha
        ldx #FD
        ldy #FA
        jsr f_mov
        jsr f_to_int
        pla
        bcs _ovf
        cmp #$ff
        beq _done
        cmp #1
        beq _away
        lda acc                         ; a tie: to even
        and #1
        beq _done
_away:  lda fc+F_SIGN
        bmi +
        lda #1
        sta acc2
        lda #0
        sta acc2+1
        sta acc2+2
        sta acc2+3
        jsr acc_add
        bra _done
+       lda #1
        sta acc2
        lda #0
        sta acc2+1
        sta acc2+2
        sta acc2+3
        jsr acc_sub
_done:  jmp int_new
_ovf:   jmp f_int_result

; divmod(a, b) with a float
xa_float_divmod:
        #ARG 1
        jsr num_to_fa
        bcs _bad
        ldx #FA
        ldy #FB
        jsr f_mov
        #ARG 0
        jsr num_to_fa
        bcs _bad
        jsr f_divmod
        jsr float_new
        sta r2
        stx r2+1
        ldx #FE
        ldy #FA
        jsr f_mov
        jsr float_new
        sta r3
        stx r3+1
        jmp tuple2
_bad:   jmp raise_need_int

;---------------------------------------------------------------------------------------
; the math module: a class object whose dict holds the functions and constants
;---------------------------------------------------------------------------------------
