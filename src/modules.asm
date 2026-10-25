;=======================================================================================
; Built-in modules (import): math (floatb.asm) and os (file.asm). Graphics and system modules come later;
; their memory (bank 5, the framebuffer) is reserved in platform.asm.
;=======================================================================================

; import_module - A/X = module symbol -> A/X = the module object
import_module:
        jsr import_math
        bcc +
        rts
+       jmp os_import                   ; (os, or ImportError: file.asm)
