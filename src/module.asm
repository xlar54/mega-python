;=======================================================================================
; Modules loaded from the disk: import name -> name.py.
;
; A module's global names are compiled as hidden symbols "name.x" (a '.' cannot be in a
; source name). SYM_BASE (attic) maps each hidden symbol back to "x": a hidden name that
; is not bound falls back to the plain one (the builtins, as Python looks them up). The
; module object (T_MODULE: +4 name string, +6 symbol) reads and writes the hidden
; names, and is itself kept in the hidden global "name." (so a second import finds it).
; The source is loaded to MODSRC (attic), compiled after the running code, and its
; top level runs as a nested VM run.
;=======================================================================================
c_mod:          .word 0                 ; compiling a module: its symbol (0 = no)
ms_mod:         .word 0
ms_str:         .word 0

; mod_sym - "<module ms_mod>.<string A/X>" (A/X = 0: nothing after the dot)
; -> A/X = its symbol
mod_sym:
        sta ms_str
        stx ms_str+1
        lda ms_mod
        ldx ms_mod+1
        jsr sym_name
        ldy #0
        jsr _copy
        lda #'.'
        sta DIGBUF,y
        iny
        lda ms_str+1
        beq +
        lda ms_str
        ldx ms_str+1
        jsr _copy
+       lda #0
        sta DIGBUF,y
        lda #<DIGBUF
        ldx #>DIGBUF
        jmp intern_cstr
_copy:  phy                             ; append string A/X at DIGBUF + Y
        jsr str_info
        ply
        ldz #0
-       cpz str_len
        beq +
        cpy #250
        bcs +
        lda [fp0],z
        sta DIGBUF,y
        iny
        inz
        bra -
+       rts

; sym_base_addr - A/X = symbol -> fp1 = &SYM_BASE[symbol]
sym_base_addr:
        stx fp1+1
        asl a
        rol fp1+1
        sta fp1
        clc
        lda fp1+1
        adc #>(SYM_BASE & $ffff)
        sta fp1+1
        lda #<(SYM_BASE >> 16)
        sta fp1+2
        lda #>(SYM_BASE >> 16)
        sta fp1+3
        rts

; gsym - compiling a module: A/X = global symbol -> its hidden symbol (else unchanged)
gsym:   ldy c_mod+1                     ; (the whole word: a fixed symbol such as
        bne +                           ; sys is below 256)
        ldy c_mod
        bne +
        rts
+       sta ms_sym
        stx ms_sym+1
        lda c_mod
        sta ms_mod
        lda c_mod+1
        sta ms_mod+1
        lda ms_sym
        ldx ms_sym+1
        jsr sym_name
        jsr mod_sym
        pha
        phx
        jsr sym_base_addr               ; SYM_BASE[hidden] = the plain symbol
        ldz #0
        lda ms_sym
        sta [fp1],z
        inz
        lda ms_sym+1
        sta [fp1],z
        plx
        pla
        rts
ms_sym:         .word 0

; unmangle - A/X = symbol -> its plain symbol (a hidden one's base, else itself)
unmangle:
        pha
        phx
        jsr sym_base_addr
        ldz #0
        lda [fp1],z
        inz
        ora [fp1],z
        bne +
        plx
        pla
        rts
+       plx
        pla
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        rts

;---------------------------------------------------------------------------------------
; mod_import - A/X = module symbol -> A/X = the module (math, os, or name.py)
;---------------------------------------------------------------------------------------
mod_import:
        sta ms_sym
        stx ms_sym+1
        jsr import_module               ; math, os
        bcc +
        rts
+       lda ms_sym                      ; imported before?
        sta ms_mod
        lda ms_sym+1
        sta ms_mod+1
        lda #0
        tax
        jsr mod_sym
        sta ms_key
        stx ms_key+1
        jsr sym_val_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        cpx #0
        beq _load
        rts
_load:  jsr need_f                        ; name.py -> MODSRC, the module object bound
        jsr xm_load
        ; compile it (the compiler's scopes use the bottom of the value stack)
        lda vsp+1
        cmp #>(SCOPEMEM + $500)
        bcs +
        #RAISE EXC_MEMORY, "no room to compile the module"
+       lda ms_key                      ; (kept across the compile and the run)
        pha
        lda ms_key+1
        pha
        lda c_repl
        pha
        lda err_vec+1                   ; compile errors: back to the runtime overlay first
        pha
        lda err_vec
        pha
        lda err_sp+1
        pha
        lda err_sp
        pha
        tsx
        stx err_sp
        tsy
        sty err_sp+1
        lda #<_cerr
        sta err_vec
        lda #>_cerr
        sta err_vec+1
        lda ms_sym
        sta c_mod
        lda ms_sym+1
        sta c_mod+1
        lda #0
        sta c_repl
        lda #<MODSRC
        sta lx_ptr
        lda #>MODSRC
        sta lx_ptr+1
        lda #<(MODSRC >> 16)
        sta lx_ptr+2
        lda #>(MODSRC >> 16)
        sta lx_ptr+3
        jsr compile
        sta t0
        stx t0+1
        jsr _restore
        lda #1                          ; (the REPL keeps this code)
        sta c_made_func
        ; run its top level
        lda ip
        pha
        lda ip+1
        pha
        lda ip+2
        pha
        lda t0
        ldx t0+1
        jsr vm_run
        pla
        sta ip+2
        pla
        sta ip+1
        pla
        sta ip
        pla
        sta ms_key+1
        pla
        sta ms_key
        bcs _fail
        lda ms_key
        ldx ms_key+1
        jsr sym_val_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        rts
_fail:  jsr _unbind                     ; it did not import: forget it
        jmp throw
_cerr:  jsr ovl_runtime                 ; (SP is back at the saved context)
        jsr _restore
        pla
        sta ms_key+1
        pla
        sta ms_key
        jsr _unbind
        jmp throw
_restore:                               ; pull the saved error context and c_repl
        pla
        sta t7
        pla
        sta t7+1
        pla
        sta err_sp
        pla
        sta err_sp+1
        pla
        sta err_vec
        pla
        sta err_vec+1
        pla
        sta c_repl
        lda #0
        sta c_mod
        sta c_mod+1
        lda t7+1
        pha
        lda t7
        pha
        rts
_unbind:
        lda ms_key
        ldx ms_key+1
        jsr sym_val_addr
        ldz #0
        lda #0
        sta [fp1],z
        inz
        sta [fp1],z
        rts
ms_key:         .word 0

;---------------------------------------------------------------------------------------
; module attributes and repr: in tail F
;---------------------------------------------------------------------------------------
module_getattr:
        jsr need_f
        jmp xm_getattr
module_setattr:
        jsr need_f
        jmp xm_setattr
repr_module:
        jsr need_f
        jmp xm_repr
