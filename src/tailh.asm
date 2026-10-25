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

; mem() - collect garbage, then what is free in each area
xh_mem:
        jsr gc_collect
        jsr heap_free
        lda acc                         ; the free amounts, in the order of the rows
        sta mem_free
        lda acc+1
        sta mem_free+1
        sec                             ; bytecode
        lda #<CODE_END
        sbc cp
        sta mem_free+2
        lda #>CODE_END
        sbc cp+1
        sta mem_free+3
        sec                             ; names
        lda #<MAXSYMS
        sbc nsyms
        sta mem_free+4
        lda #>MAXSYMS
        sbc nsyms+1
        sta mem_free+5
        sec                             ; source
        lda #<SRC_MAX
        sbc src_len
        sta mem_free+6
        lda #>SRC_MAX
        sbc src_len+1
        sta mem_free+7
        sec                             ; value stack slots
        lda vsp
        sbc #<VSTACK
        sta mem_free+8
        lda vsp+1
        sbc #>VSTACK
        lsr a
        sta mem_free+9
        ror mem_free+8
        lda sbp
        pha
        lda sbp+1
        pha
        ldx #0
_row:   phx
        lda mem_label,x                 ; the label
        pha
        lda mem_label+1,x
        tax
        pla
        jsr sb_puts
        plx
        phx
        lda mem_free,x                  ; "free of total unit free"
        ldy mem_free+1,x
        jsr _num
        #SBPRINT " of "
        plx
        phx
        lda mem_total,x
        ldy mem_total+1,x
        jsr _num
        plx
        phx
        lda mem_unit,x
        pha
        lda mem_unit+1,x
        tax
        pla
        jsr sb_puts
        #SBPRINT " free"
        lda #10
        jsr sb_putc
        plx
        inx
        inx
        cpx #2*5
        bne _row
        #SBPRINT "bank 5 (64 KB) is kept for graphics."
        lda #10
        jsr sb_putc
        plx
        pla
        jsr sb_flush
        lda #R_NONE
        ldx #0
        rts
_num:   ; A/Y, right-aligned in 5 columns
        sta acc
        sty acc+1
        lda #0
        sta acc+2
        sta acc+3
        ldx #4                          ; a space for each power of 10 above it
-       lda acc+1
        cmp _p10hi-1,x
        bcc +
        bne _wide
        lda acc
        cmp _p10lo-1,x
        bcs _wide
+       lda #' '
        jsr sb_putc
        dex
        bne -
_wide:  jmp sb_int
_p10lo: .byte <10, <100, <1000, <10000
_p10hi: .byte >10, >100, >1000, >10000
mem_free:       .fill 10
mem_label:      .word mem_l0, mem_l1, mem_l2, mem_l3, mem_l4
mem_total:      .word HEAP_LIMIT - HEAP_START, CODE_END - CODE_START, MAXSYMS, SRC_MAX
                .word (VSTACK_END - VSTACK) / 2
mem_unit:       .word mem_u0, mem_u0, mem_u2, mem_u0, mem_u4
mem_l0:    .text "objects (heap, bank 4)  ", 0
mem_l1:    .text "bytecode (bank 1)       ", 0
mem_l2:    .text "names (symbol table)    ", 0
mem_l3:    .text "program source (attic)  ", 0
mem_l4:    .text "value stack (bank 0)    ", 0
mem_u0:    .text " bytes", 0
mem_u2:    .text " names", 0
mem_u4:    .text " slots", 0

        .include "gen/symnames.asm"
