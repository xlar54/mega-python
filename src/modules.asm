;=======================================================================================
; Built-in modules (import). None yet: graphics and system modules come later; their
; memory (bank 5, the framebuffer) is reserved in platform.asm.
;=======================================================================================

; import_module - A/X = module symbol -> A/X = the module object
import_module:
        sta vtmp
        stx vtmp+1
        jsr sb_mark_t5
        #SBPRINT "No module named '"
        lda vtmp
        ldx vtmp+1
        jsr sym_name
        jsr sb_put_str
        lda #"'"
        jsr sb_putc
        lda #EXC_IMPORT
        jmp raise_sb
