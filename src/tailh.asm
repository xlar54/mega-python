;=======================================================================================
; Tail H (swapped in at TAIL by need_h): what is needed only now and then - the names
; of the fixed symbols (for py_reset) and help().
;=======================================================================================
xh_help:
        jsr scr_fresh_line
        lda #COL_INFO
        sta scr_color
        lda #<help_text
        ldx #>help_text
        jsr puts
        lda #COL_NORMAL
        sta scr_color
        lda #R_NONE
        ldx #0
        rts
help_text:
        .text "MEGA65 Python - commands:", 10
        .text "  edit()          full-screen editor for the program (ESC = back, F5 = run)", 10
        .text "  run()           run the program", 10
        .text "  new()           clear the program and all variables", 10
        .text "  load('name')    load name.py from disk;  save('name') saves it", 10
        .text "  files()         list the .py files on the disk", 10
        .text "  cls()  mem()  gc()  peek(addr)  poke(addr, byte)", 10
        .text "Keys: cursor keys edit the line, up/down = history, RUN/STOP = break", 10, 0

        .include "gen/symnames.asm"
