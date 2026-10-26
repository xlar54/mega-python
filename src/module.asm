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
_load:  jsr module_load                   ; name.py -> MODSRC, the module object bound
        lda ms_key                      ; (kept across the compile and the run)
        pha
        lda ms_key+1
        pha
        lda ms_sym
        sta cr_mod
        lda ms_sym+1
        sta cr_mod+1
        lda #0
        sta cr_mode
        jsr compile_run
        pla
        sta ms_key+1
        pla
        sta ms_key
        bcs _fail
        lda #1                          ; (the REPL keeps this code)
        sta c_made_func
        lda ms_key
        ldx ms_key+1
        jsr sym_val_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        rts
_fail:  lda ms_key                      ; it did not import: forget it
        ldx ms_key+1
        jsr sym_val_addr
        ldz #0
        lda #0
        sta [fp1],z
        inz
        sta [fp1],z
        jmp throw
ms_key:         .word 0

;---------------------------------------------------------------------------------------
; compile_run - the source at MODSRC compiled after the running code (c_mod = cr_mod,
; c_repl = cr_mode) and run as a nested VM run -> C set if it raised (a compile error
; too: cur_exc). The compiler's scopes use the bottom of the value stack.
;---------------------------------------------------------------------------------------
cr_mod:         .word 0
cr_mode:        .byte 0
cs_perm:        .byte F_PERM            ; the flags of compile-time objects (al_perm)
compile_run:
        lda vsp+1
        cmp #>(COMPILER_END + $ff)
        bcs +
        #RAISE EXC_MEMORY, "no room to compile"
+       lda c_repl
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
        lda cr_mod
        sta c_mod
        lda cr_mod+1
        sta c_mod+1
        lda cr_mode
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
        lda #F_PERM                     ; (an eval's tag is for its own compile only)
        sta cs_perm
        jsr _restore
        lda ip                          ; run its top level
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
        rts                             ; (C from vm_run)
_cerr:  jsr ovl_runtime                 ; (SP is back at the saved context)
        jsr _restore
        sec
        rts
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

;---------------------------------------------------------------------------------------
; eval(source) / exec(source): the string compiled after the running code, in the main
; program's globals, and run; eval gives the value of its (last) expression. Their code
; is dropped again unless it made a function or class (or imported a module).
;---------------------------------------------------------------------------------------
ev_sym:         .word 0
ev_lt:          .word 0
ev_cp:          .word 0
ev_err:         .byte 0
bi_exec:
        lda #0
        bra +
bi_eval:
        lda #2
+       pha                             ; CPU: [mode]
        #NARGS 1, 1
        #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq +
        lda r2
        ldx r2+1
        jmp raise_need_str
+       lda r2
        ldx r2+1
        jsr str_info
-       lda str_len                     ; (leading blanks are not an indentation)
        ora str_len+1
        beq +
        ldz #0
        lda [fp0],z
        cmp #' '
        beq _blank
        cmp #9
        bne +
_blank: inw fp0
        dew str_len
        bra -
+       clc                             ; the text, a newline and a 0 at MODSRC
        lda #<MODSRC
        adc str_len
        sta fp2
        lda #>MODSRC
        adc str_len+1
        sta fp2+1
        lda #<(MODSRC >> 16)
        adc #0
        sta fp2+2
        lda #>(MODSRC >> 16)
        sta fp2+3
        lda #<MODSRC
        sta fp1
        lda #>MODSRC
        sta fp1+1
        lda #<(MODSRC >> 16)
        sta fp1+2
        lda #>(MODSRC >> 16)
        sta fp1+3
        lda str_len
        sta t0
        lda str_len+1
        sta t0+1
        ora t0
        beq +
        jsr dma_copy
+       ldz #0
        lda #10
        sta [fp2],z
        inz
        lda #0
        sta [fp2],z
        lda #<ev_text0                  ; " eval" = None (only statements: None)
        ldx #>ev_text0
        jsr intern_cstr
        sta ev_sym
        stx ev_sym+1
        jsr sym_val_addr
        ldz #0
        lda #R_NONE
        sta [fp1],z
        inz
        lda #0
        sta [fp1],z
        pla                             ; the mode
        sta cr_mode
        pha
        lda c_made_func                 ; CPU: [mode][made][cp][line table end]
        pha
        lda #0
        sta c_made_func
        lda cp
        pha
        lda cp+1
        pha
        lda linetab_end
        pha
        lda linetab_end+1
        pha
        lda #0
        sta cr_mod
        sta cr_mod+1
        jsr ev_begin
        jsr compile_run
        lda #0
        rol a
        sta ev_err
        pla
        sta ev_lt+1
        pla
        sta ev_lt
        pla
        sta ev_cp+1
        pla
        sta ev_cp
        ldx #0
        lda c_made_func                 ; nothing made: its code goes (its constants too)
        bne +
        lda ev_cp
        sta cp
        lda ev_cp+1
        sta cp+1
        lda ev_lt
        sta linetab_end
        lda ev_lt+1
        sta linetab_end+1
        inx
+       jsr ev_end
        pla
        ora c_made_func
        sta c_made_func
        pla                             ; the mode
        ldx ev_err
        beq +
        jmp throw
+       cmp #2
        beq +
        #RET_NONE
+       lda ev_sym                      ; eval: the value (and " eval" lets it go)
        ldx ev_sym+1
        jsr sym_val_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        pha
        lda #R_NONE
        sta [fp1],z
        inz
        lda #0
        sta [fp1],z
        pla
        rts
ev_text0:       .null " eval"

;---------------------------------------------------------------------------------------
; module attributes and repr: in tail F
;---------------------------------------------------------------------------------------
module_getattr: #TAILCALL TAIL_F, xm_getattr
module_setattr: #TAILCALL TAIL_F, xm_setattr
repr_module:    #TAILCALL TAIL_F, xm_repr
module_load:    #TAILCALL TAIL_F, xm_load
