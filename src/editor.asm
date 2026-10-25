;=======================================================================================
; Full-screen editor for the program in SRC (attic RAM, src_len bytes, LF lines).
; Rows 0-23 show the text, row 24 is the status line.
;   cursor keys move, HOME = line start, CLR (shift+HOME) = top, F1/F3 = page up/down
;   RETURN = new line (keeps the indentation, +4 after ':'), DEL = backspace,
;   INST (shift+DEL) = delete forward, TAB = indent to the next multiple of 4
;   F5 = run the program, ESC or RUN/STOP = back to the REPL
; ed_cur (the cursor offset) is on the base page.
;=======================================================================================
ED_ROWS         = 24

ed_top:         .word 0                 ; offset of the first line shown
ed_row:         .byte 0
ed_col:         .word 0
ed_hs:          .byte 0                 ; horizontal scroll
ed_want:        .word 0                 ; column wanted by up/down

; editor - C set on return if the program should run (F5)
editor:
        lda #$80                        ; no transcript while editing
        sta log_on
        lda ed_cur+1                    ; keep the cursor inside the text
        cmp src_len+1
        bcc +
        bne _clamp
        lda ed_cur
        cmp src_len
        bcc +
        beq +
_clamp: lda src_len
        sta ed_cur
        lda src_len+1
        sta ed_cur+1
        lda #0
        sta ed_top
        sta ed_top+1
+       lda ed_top+1
        cmp ed_cur+1
        bcc _loop
        bne +
        lda ed_top
        cmp ed_cur
        bcc _loop
        beq _loop
+       lda #0
        sta ed_top
        sta ed_top+1
_loop:  jsr ed_draw
        jsr getkey
        cmp #K_ESC
        beq _exit
        cmp #K_STOP
        beq _exit
        cmp #K_F5
        beq _run
        jsr ed_key
        bra _loop
_exit:  jsr ed_leave
        clc
        rts
_run:   jsr ed_leave
        sec
        rts

ed_leave:
        lda #0
        sta log_on
        jsr src_terminate
        lda #COL_NORMAL
        sta scr_color
        jmp scr_clear

ed_key:
        cmp #K_RETURN
        bne +
        jmp ed_newline
+       cmp #K_DEL
        bne +
        jmp ed_backspace
+       cmp #K_INST
        bne +
        jmp ed_delete
+       cmp #K_LEFT
        bne +
        jmp ed_left
+       cmp #K_RIGHT
        bne +
        jmp ed_right
+       cmp #K_UP
        bne +
        jmp ed_up
+       cmp #K_DOWN
        bne +
        jmp ed_down
+       cmp #K_HOME
        bne +
        jmp ed_home
+       cmp #K_CLR
        bne +
        lda #0
        sta ed_cur
        sta ed_cur+1
        rts
+       cmp #K_F1
        bne +
        ldx #ED_ROWS
-       phx
        jsr ed_up
        plx
        dex
        bne -
        rts
+       cmp #K_F3
        bne +
        ldx #ED_ROWS
-       phx
        jsr ed_down
        plx
        dex
        bne -
        rts
+       cmp #K_TAB
        bne +
-       lda #' '
        jsr ed_insert
        jsr ed_colnow
        lda ed_col
        and #3
        bne -
        rts
+       cmp #32
        bcc _no
        cmp #127
        bcs _no
        jmp ed_insert
_no:    rts

;---------------------------------------------------------------------------------------
; text access
;---------------------------------------------------------------------------------------
; ed_ptr - A/X = offset -> fp0 = its address
ed_ptr:
        sta fp0
        stx fp0+1
        lda #<(SRC >> 16)
        sta fp0+2
        lda #>(SRC >> 16)
        sta fp0+3
        rts
; ed_get - A/X = offset -> A = char (0 past the end)
ed_get:
        cpx src_len+1
        bcc +
        bne _end
        cmp src_len
        bcs _end
+       jsr ed_ptr
        ldz #0
        lda [fp0],z
        rts
_end:   lda #0
        rts

; ed_line_start - A/X = offset -> A/X = the start of its line
ed_line_start:
        sta t4
        stx t4+1
-       lda t4
        ora t4+1
        beq +
        lda t4
        sec
        sbc #1
        tay
        lda t4+1
        sbc #0
        tax
        tya
        jsr ed_get
        cmp #10
        beq +
        dew t4
        bra -
+       lda t4
        ldx t4+1
        rts

; ed_line_end - A/X = offset -> A/X (and t4) = the offset of its line's LF (or the end)
ed_line_end:
        sta t4
        stx t4+1
-       lda t4
        ldx t4+1
        jsr ed_at_end
        bcs +
        lda t4
        ldx t4+1
        jsr ed_get
        cmp #10
        beq +
        inw t4
        bra -
+       lda t4
        ldx t4+1
        rts

; ed_at_end - A/X = offset -> C set if >= src_len
ed_at_end:
        cpx src_len+1
        bcc +
        bne _y
        cmp src_len
        bcc +
_y:     sec
        rts
+       clc
        rts

; ed_colnow -> ed_col = the cursor's column
ed_colnow:
        lda ed_cur
        ldx ed_cur+1
        jsr ed_line_start
        sta t5
        stx t5+1
        sec
        lda ed_cur
        sbc t5
        sta ed_col
        lda ed_cur+1
        sbc t5+1
        sta ed_col+1
        rts

;---------------------------------------------------------------------------------------
; editing
;---------------------------------------------------------------------------------------
; ed_insert - A = char at the cursor
ed_insert:
        sta t6
        lda src_len+1
        cmp #>SRC_MAX
        bcc +
        rts                             ; full
+       ; move [cur, len) up by one, from the end
        lda src_len
        sta t1
        lda src_len+1
        sta t1+1
-       lda t1
        cmp ed_cur
        bne +
        lda t1+1
        cmp ed_cur+1
        beq ++
+       dew t1
        lda t1
        ldx t1+1
        jsr ed_ptr
        ldz #0
        lda [fp0],z
        inz
        sta [fp0],z
        bra -
+       lda ed_cur
        ldx ed_cur+1
        jsr ed_ptr
        ldz #0
        lda t6
        sta [fp0],z
        inw src_len
        inw ed_cur
        rts

; ed_remove - delete the char at offset t1
ed_remove:
        lda t1
        ldx t1+1
        jsr ed_at_end
        bcs _done
-       lda t1
        clc
        adc #1
        tay
        lda t1+1
        adc #0
        tax
        tya
        jsr ed_at_end
        bcs +
        lda t1
        ldx t1+1
        jsr ed_ptr
        ldz #1
        lda [fp0],z
        dez
        sta [fp0],z
        inw t1
        bra -
+       dew src_len
_done:  rts

ed_backspace:
        lda ed_cur
        ora ed_cur+1
        beq +
        dew ed_cur
        lda ed_cur
        sta t1
        lda ed_cur+1
        sta t1+1
        jmp ed_remove
+       rts

ed_delete:
        lda ed_cur
        sta t1
        lda ed_cur+1
        sta t1+1
        jmp ed_remove

ed_newline:
        ; the current line's indentation, +4 when the text before the cursor ends in ':'
        lda ed_cur
        ldx ed_cur+1
        jsr ed_line_start
        sta t2
        stx t2+1
        lda #0
        sta t3
-       lda t2
        cmp ed_cur
        bne +
        lda t2+1
        cmp ed_cur+1
        beq ++
+       lda t2
        ldx t2+1
        jsr ed_get
        cmp #' '
        bne +
        inc t3
        inw t2
        bra -
+       ; the last non-space before the cursor
        lda ed_cur
        sta t2
        lda ed_cur+1
        sta t2+1
-       lda t2
        ora t2+1
        beq +
        dew t2
        lda t2
        ldx t2+1
        jsr ed_get
        cmp #' '
        beq -
        cmp #':'
        bne +
        lda t3
        clc
        adc #4
        sta t3
+       lda t3
        pha
        lda #10
        jsr ed_insert
        pla
        sta t3
-       lda t3
        beq +
        lda #' '
        jsr ed_insert
        dec t3
        bra -
+       rts

;---------------------------------------------------------------------------------------
; cursor movement
;---------------------------------------------------------------------------------------
ed_left:
        lda ed_cur
        ora ed_cur+1
        beq +
        dew ed_cur
+       jmp ed_setwant
ed_right:
        lda ed_cur
        ldx ed_cur+1
        jsr ed_at_end
        bcs +
        inw ed_cur
+       jmp ed_setwant
ed_home:
        lda ed_cur
        ldx ed_cur+1
        jsr ed_line_start
        sta ed_cur
        stx ed_cur+1
ed_setwant:
        jsr ed_colnow
        lda ed_col
        sta ed_want
        lda ed_col+1
        sta ed_want+1
        rts

ed_up:
        lda ed_cur
        ldx ed_cur+1
        jsr ed_line_start
        sta t2
        stx t2+1
        ora t2+1
        beq _done                       ; already on the first line
        lda t2
        sec
        sbc #1
        tay
        lda t2+1
        sbc #0
        tax
        tya
        jsr ed_line_start
        jmp ed_to_want
_done:  rts

ed_down:
        lda ed_cur
        ldx ed_cur+1
        jsr ed_line_end
        jsr ed_at_end
        bcs _done
        inw t4                          ; past the LF
        lda t4
        ldx t4+1
        jmp ed_to_want
_done:  rts

; ed_to_want - A/X = a line start: the cursor goes to column ed_want of that line
ed_to_want:
        sta ed_cur
        stx ed_cur+1
        lda ed_want
        sta t3
        lda ed_want+1
        sta t3+1
-       lda t3
        ora t3+1
        beq +
        lda ed_cur
        ldx ed_cur+1
        jsr ed_get
        cmp #10
        beq +
        cmp #0
        beq +
        inw ed_cur
        dew t3
        bra -
+       rts

;---------------------------------------------------------------------------------------
; drawing
;---------------------------------------------------------------------------------------
ed_draw:
        ; scroll so the cursor's line is visible
        lda ed_cur+1
        cmp ed_top+1
        bcc _up
        bne _rows
        lda ed_cur
        cmp ed_top
        bcs _rows
_up:    lda ed_cur
        ldx ed_cur+1
        jsr ed_line_start
        sta ed_top
        stx ed_top+1
_rows:  ; ed_row = lines between ed_top and the cursor
        lda #0
        sta ed_row
        lda ed_top
        sta t2
        lda ed_top+1
        sta t2+1
-       lda t2
        cmp ed_cur
        bne +
        lda t2+1
        cmp ed_cur+1
        beq ++
+       lda t2
        ldx t2+1
        jsr ed_get
        inw t2
        cmp #10
        bne -
        inc ed_row
        bra -
+       lda ed_row
        cmp #ED_ROWS
        bcc _ok
        ; move the top down one line and count again
        lda ed_top
        ldx ed_top+1
        jsr ed_line_end
        inw t4
        lda t4
        sta ed_top
        lda t4+1
        sta ed_top+1
        bra _rows
_ok:    jsr ed_colnow
        lda #0
        sta ed_hs
        lda ed_col+1
        bne _hs
        lda ed_col
        cmp #COLS
        bcc _draw
_hs:    sec
        lda ed_col
        sbc #COLS-1
        sta ed_hs
_draw:  lda #COL_NORMAL
        sta scr_color
        jsr scr_clear
        ; the text
        lda ed_top
        sta t2
        lda ed_top+1
        sta t2+1
        lda #0
        sta t6                          ; row
_row:   lda t6
        cmp #ED_ROWS
        bcs _status
        ldx t6
        ldy #0
        jsr scr_goto
        lda #0
        sta t7                          ; column in the line
_ch:    lda t2
        ldx t2+1
        jsr ed_at_end
        bcs _status
        lda t2
        ldx t2+1
        jsr ed_get
        inw t2
        cmp #10
        beq _nextrow
        ldx t7
        inc t7
        cpx ed_hs
        bcc _ch
        ldy scr_col
        cpy #COLS-1
        bcs _ch                         ; past the right edge (no wrapping)
        jsr putc
        bra _ch
_nextrow:
        inc t6
        bra _row
_status:
        ldx #ROWS-1
        ldy #0
        jsr scr_goto
        lda #COL_STATUS | ATTR_REVERSE
        sta scr_color
        jsr sb_mark_t5
        #SBPRINT " Python editor   F5 run   ESC back to >>>   line "
        jsr ed_lineno
        jsr sb_int
        #SBPRINT "  col "
        lda ed_col
        clc
        adc #1
        sta acc
        lda ed_col+1
        adc #0
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_int
        #SBPRINT "  "
        lda src_len
        sta acc
        lda src_len+1
        sta acc+1
        jsr sb_int
        #SBPRINT " bytes "
        lda t5
        ldx t5+1
        jsr sb_flush
-       lda scr_col
        cmp #COLS-1
        bcs +
        lda #' '
        jsr putc
        bra -
+       lda #COL_NORMAL
        sta scr_color
        ; the cursor
        sec
        lda ed_col
        sbc ed_hs
        tay
        ldx ed_row
        jmp scr_goto

; ed_lineno -> acc = the cursor's line number (1-based)
ed_lineno:
        lda #1
        sta acc
        lda #0
        sta acc+1
        sta acc+2
        sta acc+3
        sta t2
        sta t2+1
-       lda t2
        cmp ed_cur
        bne +
        lda t2+1
        cmp ed_cur+1
        beq ++
+       lda t2
        ldx t2+1
        jsr ed_get
        inw t2
        cmp #10
        bne -
        inw acc
        bra -
+       rts
