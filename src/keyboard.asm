;=======================================================================================
; Keyboard: the MEGA65 hardware typing queue ($D610, ASCII). The KERNAL only reads
; it from GETIN, which we never call. tools/xemu_run.py can inject keys through
; dbg_keys / dbg_klen / dbg_kpos.
;=======================================================================================
K_RETURN        = $0d
K_DEL           = $14
K_INST          = $94
K_LEFT          = $9d
K_RIGHT         = $1d
K_UP            = $91
K_DOWN          = $11
K_HOME          = $13
K_CLR           = $93
K_STOP          = $03
K_ESC           = $1b
K_TAB           = $09
K_F1            = $f1
K_F3            = $f3
K_F5            = $f5
K_F7            = $f7

HIST_N          = 8                     ; HIST (attic): 8 x 256 bytes, length + text

; key_poll - A = next key or 0 (does not wait)
key_poll:
        phx
        ldx dbg_kpos
        cpx dbg_klen
        bcs _hw
        lda dbg_keys,x
        inc dbg_kpos
        plx
        ora #0
        rts
_hw:    lda ASCIIKEY
        beq _done
        sta ASCIIKEY                    ; dequeue
        cmp #$ff
        bne _done
        lda #0
_done:  plx
        ora #0
        rts

; getkey - wait for a key, showing the cursor. A = key.
getkey:
        jsr cursor_toggle
-       jsr key_poll
        beq -
        pha
        jsr cursor_toggle
        pla
        rts

;---------------------------------------------------------------------------------------
; rl_read - edit a line at the cursor into LINEBUF. rl_len may be preset (auto-indent).
; Returns C clear on RETURN (rl_len = length, LINEBUF zero-terminated), C set if
; RUN/STOP or ESC cancelled the line.
;---------------------------------------------------------------------------------------
RL_MAX          = 200
rl_len:         .byte 0
rl_cur:         .byte 0
rl_base:        .word 0                 ; screen offset of the line start
rl_hidx:        .byte 0                 ; history browse position
rl_prev:        .byte 0                 ; length drawn last time
hist_count:     .byte 0
hist_head:      .byte 0                 ; next slot to write

rl_read:
        lda #$80                        ; no transcript while editing the line
        sta log_on
        ldx scr_row
        clc
        lda row_lo,x
        adc scr_col
        sta rl_base
        lda row_hi,x
        adc #0
        sta rl_base+1
        lda rl_len
        sta rl_cur
        sta rl_prev
        lda #0
        sta rl_hidx
_redraw:
        jsr rl_draw
_key:   jsr getkey
        cmp #K_RETURN
        beq _ret
        cmp #K_STOP
        beq _cancel
        cmp #K_ESC
        beq _cancel
        cmp #K_DEL
        beq _del
        cmp #K_LEFT
        beq _left
        cmp #K_RIGHT
        beq _right
        cmp #K_HOME
        beq _home
        cmp #K_UP
        beq _up
        cmp #K_DOWN
        beq _down
        cmp #K_TAB
        beq _tab
        cmp #K_CLR
        beq _clrline
        cmp #32
        bcc _key
        cmp #127
        bcs _key
        jsr rl_insert
        bra _redraw
_tab:   lda #32
        jsr rl_insert
        lda rl_cur
        and #3
        bne _tab
        bra _redraw
_del:   lda rl_cur
        beq _key
        dec rl_cur
        ldx rl_cur
-       lda LINEBUF+1,x
        sta LINEBUF,x
        inx
        cpx rl_len
        bcc -
        dec rl_len
        bra _redraw
_left:  lda rl_cur
        beq _key
        dec rl_cur
        bra _redraw
_right: lda rl_cur
        cmp rl_len
        bcs _key
        inc rl_cur
        bra _redraw
_home:  lda #0
        sta rl_cur
        bra _redraw
_clrline:
        lda #0
        sta rl_len
        sta rl_cur
        bra _redraw
_up:    lda rl_hidx
        cmp hist_count
        bcs _key
        inc rl_hidx
        jsr rl_hist_get
        bra _redraw
_down:  lda rl_hidx
        beq _key
        dec rl_hidx
        beq _clrline
        jsr rl_hist_get
        bra _redraw
_cancel:
        jsr rl_end
        sec
        rts
_ret:   jsr rl_end
        jsr rl_hist_put
        clc
        rts

; move the cursor to the end of the line, then to a new line; terminate LINEBUF.
; The finished line goes to the transcript once.
rl_end:
        lda rl_len
        sta rl_cur
        jsr rl_draw
        ldx rl_len
        lda #0
        sta LINEBUF,x
        sta log_on
        ldx #0
-       cpx rl_len
        bcs +
        lda LINEBUF,x
        jsr log_putc
        inx
        bra -
+       lda #10
        jsr log_putc
        jmp scr_newline

; insert A at the cursor
rl_insert:
        ldx rl_len
        cpx #RL_MAX
        bcs _full
-       cpx rl_cur
        beq +
        pha
        lda LINEBUF-1,x
        sta LINEBUF,x
        pla
        dex
        bra -
+       sta LINEBUF,x
        inc rl_len
        inc rl_cur
_full:  rts

; draw the line from rl_base and place the cursor at rl_cur
rl_draw:
        ; scroll until base + len + 2 fits on the screen
-       clc
        lda rl_base
        adc rl_len
        sta t0
        lda rl_base+1
        adc #0
        sta t0+1
        lda t0
        clc
        adc #2
        sta t0
        bcc +
        inc t0+1
+       lda t0+1
        cmp #>(COLS*ROWS)
        bcc _fits
        bne _scroll
        lda t0
        cmp #<(COLS*ROWS)
        bcc _fits
        beq _fits
_scroll:
        jsr scr_scroll
        sec
        lda rl_base
        sbc #COLS
        sta rl_base
        lda rl_base+1
        sbc #0
        sta rl_base+1
        bra -
_fits:  lda rl_base
        sta t0
        lda rl_base+1
        sta t0+1
        jsr scr_goto_lin
        ldx #0
-       cpx rl_len
        bcs _pad
        lda LINEBUF,x
        jsr putc
        inx
        bra -
_pad:   lda #32                         ; erase what a longer line left behind
        jsr putc
        inx
        cpx rl_prev
        bcc _pad
        beq _pad
        lda rl_len
        sta rl_prev
        clc
        lda rl_base
        adc rl_cur
        sta t0
        lda rl_base+1
        adc #0
        sta t0+1
        ; fall through
; place the cursor at screen offset t0
scr_goto_lin:
        ldx #0
-       lda t0+1
        bne +
        lda t0
        cmp #COLS
        bcc ++
+       sec
        lda t0
        sbc #COLS
        sta t0
        lda t0+1
        sbc #0
        sta t0+1
        inx
        bra -
+       ldy t0
        jmp scr_goto

; history: store LINEBUF (if not empty) in the ring
rl_hist_put:
        lda rl_len
        beq _done
        jsr rl_hist_ptr_head
        ldz #0
        lda rl_len
        sta [fp0],z
        ldx #0
-       inz
        lda LINEBUF,x
        sta [fp0],z
        inx
        cpx rl_len
        bcc -
        lda hist_head
        inc a
        and #HIST_N-1
        sta hist_head
        lda hist_count
        cmp #HIST_N
        bcs _done
        inc hist_count
_done:  rts

rl_hist_ptr_head:
        lda hist_head
        ; fall through
rl_hist_ptr:                            ; A = slot -> fp0
        clc
        adc #>(HIST & $ffff)
        sta fp0+1
        lda #0
        sta fp0
        lda #<(HIST >> 16)
        sta fp0+2
        lda #>(HIST >> 16)
        sta fp0+3
        rts

; load history entry rl_hidx (1 = most recent) into LINEBUF
rl_hist_get:
        sec
        lda hist_head
        sbc rl_hidx
        and #HIST_N-1
        jsr rl_hist_ptr
        ldz #0
        lda [fp0],z
        sta rl_len
        sta rl_cur
        ldx #0
-       cpx rl_len
        bcs +
        inz
        lda [fp0],z
        sta LINEBUF,x
        inx
        bra -
+       rts

dbg_klen:       .byte 0
dbg_keys:       .fill 256, 0
