;=======================================================================================
; Tail H (swapped in at TAIL by need_h): what is needed only now and then - the names
; of the fixed symbols and exception classes (for py_reset), help(), mem(), and the
; program load / save / directory.
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

;---------------------------------------------------------------------------------------
; xh_reset - (py_reset) a fresh interpreter: empty heap, symbols, globals and code,
; the exception classes; py_reset then makes the builtins
;---------------------------------------------------------------------------------------
xh_reset:
        lda #0
        sta os_mod
        sta os_mod+1
        jsr heap_init
        jsr sb_reset
        jsr vm_reset
        ; zero the symbol tables: hash buckets (attic) and globals (bank 1)
        lda #<SYM_HASH
        sta fp1
        lda #>SYM_HASH
        sta fp1+1
        lda #<(SYM_HASH >> 16)
        sta fp1+2
        lda #>(SYM_HASH >> 16)
        sta fp1+3
        lda #<512
        sta t0
        lda #>512
        sta t0+1
        lda #0
        jsr dma_fill
        lda #<SYM_VAL
        sta fp1
        lda #>SYM_VAL
        sta fp1+1
        lda #`SYM_VAL
        sta fp1+2
        lda #0
        sta fp1+3
        lda #<(2*MAXSYMS)
        sta t0
        lda #>(2*MAXSYMS)
        sta t0+1
        lda #0
        jsr dma_fill
        lda #<SYM_BASE                  ; and the modules' hidden symbols
        sta fp1
        lda #>SYM_BASE
        sta fp1+1
        lda #<(SYM_BASE >> 16)
        sta fp1+2
        lda #>(SYM_BASE >> 16)
        sta fp1+3
        lda #<(2*MAXSYMS)
        sta t0
        lda #>(2*MAXSYMS)
        sta t0+1
        lda #0
        jsr dma_fill
        lda #0
        sta nsyms
        sta nsyms+1
        ldx #0
-       sta char_cache,x
        inx
        bne -
        ; the code area
        lda #<CODE_START
        sta cp
        lda #>CODE_START
        sta cp+1
        lda #CODE_BANK
        sta cp+2
        lda #0
        sta cp+3
        lda #<(LINETAB & $ffff)
        sta linetab_end
        lda #>(LINETAB & $ffff)
        sta linetab_end+1
        ; the fixed symbols, in order
        lda #F_PERM
        sta al_perm
        lda #<sym_init_names
        sta t6
        lda #>sym_init_names
        sta t6+1
-       ldy #0
        lda (t6),y
        beq +
        lda t6
        ldx t6+1
        jsr intern_cstr
        ldy #0
-       lda (t6),y
        iny
        cmp #0
        bne -
        tya
        clc
        adc t6
        sta t6
        bcc --
        inc t6+1
        bra --
+       lda #0
        sta al_perm
        jmp exc_init

; exc_init - create the classes (perm) and bind them as globals. A subclass's base
; may come later in the table (LookupError, ArithmeticError): bases are set in a
; second pass.
exc_init:
        lda #F_PERM
        sta al_perm
        lda #0
        sta t5                          ; class id
        lda #<exc_defs
        sta t6
        lda #>exc_defs
        sta t6+1
_loop:  ldy #0
        lda (t6),y
        bne +
        jmp _bases
+       lda t6
        ldx t6+1
        jsr intern_cstr                 ; A/X sym, int_ref = name
        pha
        phx
        jsr _skip
        ; class object (+4 name, +6 base, +8 dict)
        lda #10
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_CLASS
        jsr alloc
        ldz #4
        lda int_ref
        sta [p0],z
        inz
        lda int_ref+1
        sta [p0],z
        ldx t5
        lda p0
        sta exc_cls_lo,x
        sta r0
        lda p0+1
        sta exc_cls_hi,x
        sta r0+1
        jsr dict_new
        sta t0
        stx t0+1
        lda r0
        sta p0
        lda r0+1
        sta p0+1
        ldz #8
        lda t0
        sta [p0],z
        inz
        lda t0+1
        sta [p0],z
        ; the global binding
        plx
        pla
        jsr sym_val_addr
        ldz #0
        lda r0
        sta [fp1],z
        inz
        lda r0+1
        sta [fp1],z
        inc t5
        jmp _loop
_skip:  ; t6 past the name and the base byte
        ldy #0
-       lda (t6),y
        beq +
        iny
        bra -
+       iny
        iny
        tya
        clc
        adc t6
        sta t6
        bcc +
        inc t6+1
+       rts
_bases: ; second pass: the base of each class
        lda #<exc_defs
        sta t6
        lda #>exc_defs
        sta t6+1
        lda #0
        sta t5
-       ldy #0
        lda (t6),y
        beq _init
-       lda (t6),y                      ; Y -> the base byte
        beq +
        iny
        bra -
+       iny
        lda (t6),y
        cmp #$ff
        beq +
        tax
        ldy t5
        lda exc_cls_lo,y
        sta p0
        lda exc_cls_hi,y
        sta p0+1
        ldz #6
        lda exc_cls_lo,x
        sta [p0],z
        inz
        lda exc_cls_hi,x
        sta [p0],z
+       jsr _skip
        inc t5
        bra --
_init:  ; (BaseException.__init__ comes with the builtins: builtins_init)
        ; the MemoryError instance
        lda #EXC_MEMORY
        jsr exc_new_empty
        sta mem_error
        stx mem_error+1
        lda #0
        sta al_perm
        jmp clear_rregs


;---------------------------------------------------------------------------------------
; load() / save() / files() (from the REPL's requests) and the exception classes' names
;---------------------------------------------------------------------------------------
disk_load:
        lda #0
        jsr make_kname
        jsr kc_load
        bcc +
        jmp disk_error
+       lda t0
        sta src_len
        lda t0+1
        sta src_len+1
        ora t0
        beq _done
        ; STAGE -> SRC
        lda #<STAGE
        sta fp0
        lda #>STAGE
        sta fp0+1
        lda #`STAGE
        sta fp0+2
        lda #0
        sta fp0+3
        lda #<SRC
        sta fp1
        lda #>SRC
        sta fp1+1
        lda #<(SRC >> 16)
        sta fp1+2
        lda #>(SRC >> 16)
        sta fp1+3
        jsr dma_copy
_done:  jsr src_terminate
        jsr src_clean
        lda src_len
        sta acc
        lda src_len+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_mark_t5
        jsr sb_int
        #SBPRINT " bytes loaded"
        lda t5
        ldx t5+1
        jsr sb_flush
        lda #10
        jmp putc

; src_clean - CR or CR LF line ends -> LF; tabs stay (the lexer handles them)
src_clean:
        lda #<SRC
        sta fp0
        lda #>SRC
        sta fp0+1
        lda #<(SRC >> 16)
        sta fp0+2
        lda #>(SRC >> 16)
        sta fp0+3
        lda src_len
        sta t1
        lda src_len+1
        sta t1+1
-       lda t1
        ora t1+1
        beq +
        ldz #0
        lda [fp0],z
        cmp #13
        bne _n
        lda #10                         ; CR -> LF; a following LF becomes a space
        sta [fp0],z
        inz
        lda [fp0],z
        cmp #10
        bne _n
        lda #' '
        sta [fp0],z
_n:     inw fp0
        dew t1
        bra -
+       rts

disk_save:
        ; SRC -> STAGE, then SAVE STAGE .. STAGE + len
        lda src_len
        ora src_len+1
        beq +
        lda #<SRC
        sta fp0
        lda #>SRC
        sta fp0+1
        lda #<(SRC >> 16)
        sta fp0+2
        lda #>(SRC >> 16)
        sta fp0+3
        lda #<STAGE
        sta fp1
        lda #>STAGE
        sta fp1+1
        lda #`STAGE
        sta fp1+2
        lda #0
        sta fp1+3
        lda src_len
        sta t0
        lda src_len+1
        sta t0+1
        jsr dma_copy
+       lda #1
        jsr make_kname
        jsr kc_setup
        lda #<STAGE                     ; the start pointer lives at $FB (page 0)
        sta $00fb
        lda #>STAGE
        sta $00fc
        lda #$fb
        sta kc_a
        clc
        lda #<STAGE
        adc src_len
        sta kc_x
        lda #>STAGE
        adc src_len+1
        sta kc_y
        #KCALL KERNAL_SAVE
        lda kc_p
        lsr
        bcc +
        jmp disk_error
+       #PRINT "saved"
        lda #10
        jmp putc

disk_error:
        lda #COL_ERROR
        sta scr_color
        #PRINT "disk error (file not found?)"
        lda #10
        jsr putc
        lda #COL_NORMAL
        sta scr_color
        rts

; disk_dir - LOAD "$" and print the listing (blocks and names). The listing is BASIC
; lines: link (2), number (2) = blocks, text, 0; a zero link ends it. Some DOS versions
; keep the load address ($0101) in front: skip it. Never read past the loaded bytes.
; It is walked with fsp, not fp0: putc's screen scrolling (a DMA) uses fp0.
disk_dir:
        lda #'$'
        sta kc_name
        lda #1
        sta kc_name_len
        jsr kc_load
        bcc +
        jmp disk_error
+       clc                             ; dir_end = the end of the loaded data
        lda #<STAGE
        adc t0
        sta dir_end
        lda #>STAGE
        adc t0+1
        sta dir_end+1
        lda #<STAGE
        sta fsp
        lda #>STAGE
        sta fsp+1
        lda #`STAGE
        sta fsp+2
        lda #0
        sta fsp+3
        ; a load address in front? ($01 $01, then a link, then line number 0)
        ldz #0
        lda [fsp],z
        cmp #$01
        bne _nohdr
        inz
        lda [fsp],z
        cmp #$01
        bne _nohdr
        ldz #4
        lda [fsp],z
        inz
        ora [fsp],z
        bne _nohdr
        inw fsp
        inw fsp
_nohdr: inw fsp                         ; skip the first link
        inw fsp
_line:  jsr _left                       ; room for the line number?
        cmp #3
        bcc _end
        ldz #0
        lda [fsp],z
        sta acc
        inz
        lda [fsp],z
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_mark_t5
        jsr sb_int
        lda #' '
        jsr sb_putc
        lda t5
        ldx t5+1
        jsr sb_flush
        inw fsp
        inw fsp
-       jsr _left                       ; the text, up to its zero
        beq _nl
        ldz #0
        lda [fsp],z
        beq +
        jsr petscii_to_ascii
        cmp #$12                        ; reverse-on in the header
        beq _skip
        cmp #32
        bcc _skip
        jsr putc
_skip:  inw fsp
        bra -
+       inw fsp
        lda #10
        jsr putc
        jsr _left                       ; the next link: zero ends the listing
        cmp #2
        bcc _end
        ldz #0
        lda [fsp],z
        inz
        ora [fsp],z
        beq _end
        inw fsp
        inw fsp
        bra _line
_nl:    lda #10
        jsr putc
_end:   rts
; A = bytes left to read (255 when more than that), Z flag set when none
_left:  sec
        lda dir_end
        sbc fsp
        tax
        lda dir_end+1
        sbc fsp+1
        bcc _none
        bne _many
        txa
        rts
_many:  lda #255
        rts
_none:  lda #0
        rts
dir_end:        .word 0

; name, base class (in id order; a base comes before its subclasses)
exc_defs:
        .text "BaseException", 0, $ff
        .text "Exception", 0, EXC_BASE
        .text "TypeError", 0, EXC_EXCEPTION
        .text "ValueError", 0, EXC_EXCEPTION
        .text "NameError", 0, EXC_EXCEPTION
        .text "IndexError", 0, EXC_LOOKUP
        .text "KeyError", 0, EXC_LOOKUP
        .text "ZeroDivisionError", 0, EXC_ARITH
        .text "AttributeError", 0, EXC_EXCEPTION
        .text "OverflowError", 0, EXC_ARITH
        .text "MemoryError", 0, EXC_EXCEPTION
        .text "StopIteration", 0, EXC_EXCEPTION
        .text "RuntimeError", 0, EXC_EXCEPTION
        .text "SyntaxError", 0, EXC_EXCEPTION
        .text "KeyboardInterrupt", 0, EXC_BASE
        .text "AssertionError", 0, EXC_EXCEPTION
        .text "NotImplementedError", 0, EXC_RUNTIME
        .text "IndentationError", 0, EXC_SYNTAX
        .text "UnboundLocalError", 0, EXC_NAME
        .text "RecursionError", 0, EXC_RUNTIME
        .text "LookupError", 0, EXC_EXCEPTION
        .text "ArithmeticError", 0, EXC_EXCEPTION
        .text "ImportError", 0, EXC_EXCEPTION
        .text "OSError", 0, EXC_EXCEPTION
        .text "EOFError", 0, EXC_EXCEPTION
        .text "SystemError", 0, EXC_EXCEPTION
        .text "SystemExit", 0, EXC_BASE
        .text "FileNotFoundError", 0, EXC_OS
        .byte 0

        .include "gen/symnames.asm"
