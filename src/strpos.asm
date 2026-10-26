;=======================================================================================
; Tail O: str (and bytes) methods with start / end positions. s.find(x, start, end)
; and the like (BF_POS in their flags) run on the slice s[start:end]: bm_check calls
; xw_window first; find, rfind, index and rindex then get start added to an index they
; find (xy_wrap, with sw_off).
;=======================================================================================
xw_len:         .word 0
xw_s:           .word 0                 ; start, end (clamped as slice bounds)
xw_e:           .word 0

; xw_window - X = the method (builtin id): argv 0 becomes self[start:end], nargc 2
xw_window:
        phx
        lda nargc
        cmp #5
        bcc +
        jmp raise_args
+       lda argv
        ldx argv+1
        jsr str_info
        lda str_len
        sta xw_len
        sta xw_e
        lda str_len+1
        sta xw_len+1
        sta xw_e+1
        lda argv+4                      ; start (None: 0)
        ldx argv+5
        jsr _bound
        bcs +
        lda acc
        sta xw_s
        lda acc+1
        sta xw_s+1
        bra ++
+       lda #0
        sta xw_s
        sta xw_s+1
+       lda nargc
        cmp #4
        bcc +
        lda argv+6                      ; end (None: the length)
        ldx argv+7
        jsr _bound
        bcs +
        lda acc
        sta xw_e
        lda acc+1
        sta xw_e+1
+       lda argv                        ; the slice: a new string (bytes stay bytes)
        ldx argv+1
        sta r2
        stx r2+1
        jsr str_info
        clc
        lda fp0
        adc xw_s
        sta fp2
        lda fp0+1
        adc xw_s+1
        sta fp2+1
        lda fp0+2
        sta fp2+2
        lda #0
        sta fp2+3
        sec                             ; its length (end < start: empty)
        lda xw_e
        sbc xw_s
        sta str_len
        lda xw_e+1
        sbc xw_s+1
        sta str_len+1
        bcs +
        lda #0
        sta str_len
        sta str_len+1
+
        jsr str_from_far
        jsr str_like_r2
        sta argv
        stx argv+1
        lda #0
        sta r2
        sta r2+1
        lda #2
        sta nargc
        lda xw_s
        sta sw_off
        lda xw_s+1
        sta sw_off+1
        plx                             ; find, rfind, index, rindex: start added
        cpx #B_STR_FIND
        beq +
        cpx #B_STR_RFIND
        beq +
        cpx #B_STR_INDEX
        beq +
        cpx #B_STR_RINDEX
        bne ++
+       lda bm_wrap
        ora #$80
        sta bm_wrap
+       rts

; _bound - A/X = a position (None: C set) -> acc, clamped to 0 ... xw_len as a slice's
_bound: cpx #0
        bne +
        cmp #R_NONE
        bne +
        sec
        rts
+       jsr need_int
        bit acc+3
        bpl _pos
        clc                             ; negative: from the end
        lda acc
        adc xw_len
        sta acc
        lda acc+1
        adc xw_len+1
        sta acc+1
        lda acc+2
        adc #0
        sta acc+2
        lda acc+3
        adc #0
        sta acc+3
        bpl _pos
        lda #0                          ; still negative: 0
        sta acc
        sta acc+1
        clc
        rts
_pos:   lda acc+3                       ; beyond the length: the length
        ora acc+2
        bne _len
        lda acc+1
        cmp xw_len+1
        bcc _ok
        bne _len
        lda acc
        cmp xw_len
        bcc _ok
_len:   lda xw_len
        sta acc
        lda xw_len+1
        sta acc+1
_ok:    clc
        rts
