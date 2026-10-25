;=======================================================================================
; 80x25 text console, screen RAM in bank 1 (SCREEN). Characters are ASCII: font A (ROM
; $29800, the lower-case half) has the ASCII punctuation; ascii2scr maps to its codes.
; Colour RAM bit 5 (VIC-III attributes on) is used as reverse video for the cursor.
;=======================================================================================
COLS            = 80
ROWS            = 25
COL_NORMAL      = 1                     ; white
COL_PROMPT      = 13                    ; light green
COL_ERROR       = 10                    ; light red
COL_INFO        = 15                    ; light grey
COL_STATUS      = 14                    ; light blue
ATTR_REVERSE    = $20

scr_init:
        lda #$47
        sta VIC4_KEY
        lda #$53
        sta VIC4_KEY
        lda VIC3_CTRL
        ora #%11100000                  ; H640, FAST, ATTR
        sta VIC3_CTRL
        lda #80
        sta VIC4_LINESTEP
        lda #0
        sta VIC4_LINESTEP+1
        lda #80
        sta VIC4_CHRCOUNT
        jsr scr_setptr
        lda #$00                        ; font A, lower/upper case half
        sta VIC4_CHARPTR
        lda #$98
        sta VIC4_CHARPTR+1
        lda #$02
        sta VIC4_CHARPTR+2
        lda #0
        sta BORDERCOL
        sta BACKCOL
        lda #COL_NORMAL
        sta scr_color
        ; fall through
scr_clear:
        lda #<SCREEN
        sta fp1
        lda #>SCREEN
        sta fp1+1
        lda #<(SCREEN >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        lda #<(COLS*ROWS)
        sta t0
        lda #>(COLS*ROWS)
        sta t0+1
        lda #32
        jsr dma_fill
        jsr set_fp1_colram
        lda scr_color
        jsr dma_fill
        ldx #0
        ldy #0
        ; fall through
; scr_goto: X = row, Y = column
scr_goto:
        stx scr_row
        sty scr_col
scr_sync:
        ldx scr_row
        clc
        lda row_lo,x
        adc scr_col
        sta scr_ptr
        sta cur_ptr
        lda row_hi,x
        adc #0
        sta cur_ptr+1
        clc
        adc #>SCREEN
        sta scr_ptr+1
        lda #<(SCREEN >> 16)
        sta scr_ptr+2
        lda #0
        sta scr_ptr+3
        lda #<(COLRAM >> 16)
        sta cur_ptr+2
        lda #>(COLRAM >> 16)
        sta cur_ptr+3
        rts

; scr_setptr - point the VIC-IV at the screen (also after KERNAL calls)
scr_setptr:
        lda #<SCREEN
        sta VIC4_SCRNPTR
        lda #>SCREEN
        sta VIC4_SCRNPTR+1
        lda #<(SCREEN >> 16)
        sta VIC4_SCRNPTR+2
        lda #0
        sta VIC4_SCRNPTR+3
        rts

set_fp1_colram:
        lda #<COLRAM
        sta fp1
        lda #>COLRAM
        sta fp1+1
        lda #<(COLRAM >> 16)
        sta fp1+2
        lda #>(COLRAM >> 16)
        sta fp1+3
        rts

row_lo: .byte <(range(ROWS) * COLS)
row_hi: .byte >(range(ROWS) * COLS)

;---------------------------------------------------------------------------------------
; putc - print ASCII A at the cursor. Handles \n and \t. Preserves X, Y, Z.
;---------------------------------------------------------------------------------------
putc:
        phx
        phy
        phz
        jsr log_putc
        cmp #10
        beq _nl
        cmp #13
        beq _nl
        cmp #9
        beq _tab
        and #$7f
        cmp #32
        bcc _out
        tax
        lda ascii2scr,x
        ldz #0
        sta [scr_ptr],z
        lda scr_color
        sta [cur_ptr],z
        inw scr_ptr
        inw cur_ptr
        inc scr_col
        lda scr_col
        cmp #COLS
        bcc _out
_nl:    jsr scr_newline
_out:   plz
        ply
        plx
        rts
_tab:   lda log_on                      ; the TAB is logged; its padding is not
        pha
        lda #$80
        sta log_on
-       lda #32
        jsr putc
        lda scr_col
        and #3
        bne -
        pla
        sta log_on
        bra _out

scr_newline:
        lda #0
        sta scr_col
        inc scr_row
        lda scr_row
        cmp #ROWS
        bcc +
        jsr scr_scroll
        lda #ROWS-1
        sta scr_row
+       jmp scr_sync

; scroll the whole screen up one line
scr_scroll:
        lda #<(SCREEN+COLS)
        sta fp0
        lda #>(SCREEN+COLS)
        sta fp0+1
        lda #<(SCREEN >> 16)
        sta fp0+2
        lda #0
        sta fp0+3
        lda #<SCREEN
        sta fp1
        lda #>SCREEN
        sta fp1+1
        lda #<(SCREEN >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        lda #<(COLS*(ROWS-1))
        sta t0
        lda #>(COLS*(ROWS-1))
        sta t0+1
        jsr dma_copy
        lda #<(SCREEN+COLS*(ROWS-1))
        sta fp1
        lda #>(SCREEN+COLS*(ROWS-1))
        sta fp1+1
        lda #COLS
        sta t0
        lda #0
        sta t0+1
        lda #32
        jsr dma_fill
        lda #<(COLRAM+COLS)
        sta fp0
        lda #>(COLRAM+COLS)
        sta fp0+1
        lda #<(COLRAM >> 16)
        sta fp0+2
        lda #>(COLRAM >> 16)
        sta fp0+3
        jsr set_fp1_colram
        lda #<(COLS*(ROWS-1))
        sta t0
        lda #>(COLS*(ROWS-1))
        sta t0+1
        jsr dma_copy
        lda #<(COLRAM+COLS*(ROWS-1))
        sta fp1
        lda #>(COLRAM+COLS*(ROWS-1))
        sta fp1+1
        lda #COLS
        sta t0
        lda #0
        sta t0+1
        lda scr_color
        jmp dma_fill

; puts - print the zero-terminated string at A (lo) / X (hi) in bank 0
puts:
        sta t7
        stx t7+1
        ldy #0
-       lda (t7),y
        beq +
        jsr putc
        iny
        bne -
        inc t7+1
        bra -
+       rts

; print the string that follows the jsr (zero-terminated)
PRINT   .macro text
        jsr puts_inline
        .text \text, 0
        .endm

puts_inline:
        pla
        sta t7
        pla
        sta t7+1
        ldy #1
-       lda (t7),y
        beq +
        jsr putc
        iny
        bra -
+       tya
        clc
        adc t7
        tax
        lda t7+1
        adc #0
        pha
        phx
        rts

; put_far - print t6 bytes from the far pointer fp2
put_far:
        lda t6
        ora t6+1
        beq +
        ldz #0
        lda [fp2],z
        jsr putc
        inw fp2
        dew t6
        bra put_far
+       rts

; log_putc - copy A to the output transcript in attic RAM (read by the test runner).
; log_fp is the write pointer; the log is 1 MB and wraps.
LOG             = $8000000
log_on:         .byte 1
log_putc:
        bit log_on
        bmi ++                          ; $80 = off
        pha
        ldz #0
        sta [log_fp],z
        inw log_fp
        bne +
        inc log_fp+2
        lda log_fp+2
        and #$0f
        sta log_fp+2
+       pla
+       rts

; newline unless the cursor is already in column 0
scr_fresh_line:
        lda scr_col
        beq +
        jmp scr_newline
+       rts

; toggle the reverse attribute of the cell under the cursor
cursor_toggle:
        ldz #0
        lda [cur_ptr],z
        eor #ATTR_REVERSE
        sta [cur_ptr],z
        rts

; ASCII -> font A screen code (lower-case set)
ascii2scr:
        .fill 32, 32                    ; control characters: blank
        .byte range(32, 64)             ; space .. ?
        .byte 0                         ; @
        .byte range(65, 91)             ; A-Z
        .byte 27, 28, 29, 30, 31        ; [ \ ] ^ _
        .byte $40                       ; `
        .byte range(1, 27)              ; a-z
        .byte $5b, $5c, $5d, $5e        ; { | } ~
        .byte $66                       ; DEL: checker block
