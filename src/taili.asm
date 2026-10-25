;=======================================================================================
; Tail I: setting up a fresh interpreter (py_reset): the heap, the symbol table with
; the fixed symbols (their names: gen/symnames.asm) and the exception classes.
;=======================================================================================

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
