;=======================================================================================
; Single-pass compiler: tokens -> bytecode at cp (bank CODE_BANK).
;
; Scopes (SCOPEMEM, one SCOPE_SIZE record per nesting level, sc -> current):
;   +0 kind  +1 nlocals  +2 nglobals  +3 nloops  +4 try depth  +5 class sym (word)
;   +7 flags  +8 function_body state  +20 open with blocks  +21 with statements so far
;   +24 global syms (8)  +40 local syms (48)
;   +136 loops (7 x 8: +0 continue target, +2 break chain, +4 try depth, +5 for,
;   +6 open with blocks)  +192 closures (SC_CELLMAP ...)
; Function locals are found by a token pre-scan of the body (prescan) before it is
; compiled, so a name is local everywhere in the function once it is assigned anywhere.
; The pre-scan also notes the names used in nested functions (def, lambda, class
; bodies): those locals become cells, shared through the environment (env.asm), and a
; nested function reaches them with LOAD_DEREF/STORE_DEREF (resolve_name).
;
; Code that has to move (the element of a comprehension, the true branch of a
; conditional expression, assignment target prefixes) is cut to the attic cut stack
; and pasted back later with its internal jumps relocated.
;=======================================================================================
SK_MODULE       = 0
SK_FUNC         = 1
SK_CLASS        = 2
SC_KIND         = 0
SC_NLOCALS      = 1
SC_NGLOBALS     = 2
SC_NLOOPS       = 3
SC_TRY          = 4
SC_CLASS        = 5
SC_FLAGS        = 7                     ; functions: 1 = lambda
FB_SYM          = 8                     ; function scopes: what function_body needs
FB_NAME         = 10
FB_PATCH        = 12                    ; MAKE_FUNCTION's code operand
FB_JUMP         = 14                    ; the jump over the body
FB_NDEF         = 16
FB_PARAMS       = 18
SC_WITH         = 20
SC_WCOUNT       = 21
SC_GLOBALS      = 24
SC_LOCALS       = 40
SC_LOOPS        = 136
SC_CELLMAP      = 192                   ; functions: per local, its cell number + 1 (0: none)
SC_NCELLS       = 240                   ; cells (env.asm)
SC_ENV          = 241                   ; 1: the last local is the environment
SC_NNONLOC      = 242
SC_NARGS        = 243
SC_NONLOCALS    = 244                   ; nonlocal syms (4)
SC_NDECO        = 252                   ; functions: decorators to apply (st_decorated)
SC_FFLAGS       = 253                   ; FF_VARARGS, FF_VARKW (MAKE_FUNCTION), FF_DEFS
SC_NKWONLY      = 254                   ; keyword-only parameters
SC_NPOS         = 255                   ; positional parameters + 1 (0: all of them)
FF_DEFS         = $80                   ; (compiling) the defaults tuple is built
                                        ; (FF_VARARGS, FF_VARKW: args.asm)
MAX_GLOBALS     = 8
MAX_LOCALS      = 48
MAX_LOOPS       = 7
MAX_NONLOCALS   = 4

; last emitted load (for turning it into a store)
LK_NONE         = 0

c_noin:         .byte 0                 ; 1: "in" ends the expression (for targets)
cut_top:        .dword CUTBUF           ; the cut stack's free pointer
tg_top:         .byte 0                 ; targets in use
c_start:        .word 0

;---------------------------------------------------------------------------------------
; code emission
;---------------------------------------------------------------------------------------
; emit - A = byte (X, Y preserved)
emit:
        phz
        ldz #0
        sta [cp],z
        plz
        inw cp
        pha
        lda cp+1
        cmp #>CODE_END
        bcs _full
        pla
        rts
_full:  jsr syntax_error
        .text "program too big", 0

; emit_word - A/X
emit_word:
        jsr emit
        txa
        jmp emit

; emit_op_word - Y = opcode, A/X = word
emit_op_word:
        pha
        tya
        jsr emit
        pla
        jmp emit_word

; emit_op_byte - Y = opcode, A = byte
emit_op_byte:
        pha
        tya
        jsr emit
        pla
        jmp emit

; c_here -> A/X = the current code offset
c_here:
        lda cp
        ldx cp+1
        rts

; patch_here - write the current offset at code offset A/X
patch_here:
        sta cpat
        stx cpat+1
        lda #CODE_BANK
        sta cpat+2
        lda #0
        sta cpat+3
        ldz #0
        lda cp
        sta [cpat],z
        inz
        lda cp+1
        sta [cpat],z
        rts

; read the code byte at offset A/X (+ Z) -> A
code_peek:
        sta cpat
        stx cpat+1
        lda #CODE_BANK
        sta cpat+2
        lda #0
        sta cpat+3
        lda [cpat],z
        rts

; emit_jump - Y = jump opcode -> A/X = offset of its operand (to patch)
emit_jump:
        tya
        jsr emit
        jsr c_here
        pha
        phx
        lda #0
        tax
        jsr emit_word
        plx
        pla
        rts

; emit_jump_to - Y = jump opcode, A/X = target
emit_jump_to = emit_op_word

; emit_const - A/X = ref
emit_const:
        ldy #OP_CONST
        jmp emit_op_word

; record the line of the statement being compiled in the line table
c_mark_line:
        lda tok_line
        cmp c_line
        bne +
        lda tok_line+1
        cmp c_line+1
        beq _done
+       lda tok_line
        sta c_line
        lda tok_line+1
        sta c_line+1
        lda linetab_end+1
        cmp #>(LINETAB_END & $ffff) - 1
        bcs _done
        lda linetab_end
        sta fp0
        lda linetab_end+1
        sta fp0+1
        lda #<(LINETAB >> 16)
        sta fp0+2
        lda #>(LINETAB >> 16)
        sta fp0+3
        ldz #0
        lda cp
        sta [fp0],z
        inz
        lda cp+1
        sta [fp0],z
        inz
        lda c_line
        sta [fp0],z
        inz
        lda c_line+1
        sta [fp0],z
        clc
        lda linetab_end
        adc #4
        sta linetab_end
        bcc _done
        inc linetab_end+1
_done:  rts

;---------------------------------------------------------------------------------------
; tokens
;---------------------------------------------------------------------------------------
; expect - A = token: it must be the current one; then lex the next
expect:
        cmp tok
        bne c_syntax
        jmp lex
c_syntax:
        jsr syntax_error
        .text "invalid syntax", 0

; accept - A = token: if current, lex and return C set
accept:
        cmp tok
        bne +
        jsr lex
        sec
        rts
+       clc
        rts

;---------------------------------------------------------------------------------------
; scopes
;---------------------------------------------------------------------------------------
scope_depth:    .byte 0

; sc_at - A = scope index -> sc = its record
        .cerror SCOPE_SIZE != 256 || (SCOPEMEM & $ff) != 0, "sc_at assumes 256-byte scope records"
sc_at:
        clc
        adc #>SCOPEMEM
        sta sc+1
        lda #<SCOPEMEM
        sta sc
        rts

; sc_inner / sc_outer - sc -> the innermost scope / the one around it
sc_inner:
        lda scope_depth
        sec
        sbc #1
        jmp sc_at
sc_outer:
        lda scope_depth
        sec
        sbc #2
        jmp sc_at

; scope_push - A = kind: a new zeroed scope record, sc -> it
scope_push:
        pha
        lda scope_depth
        cmp #SCOPE_MAX
        bcc +
        jsr syntax_error
        .text "too deeply nested", 0
+       jsr sc_at
        inc scope_depth
        ldy #SCOPE_SIZE-1
        lda #0
-       sta (sc),y
        dey
        bne -
        pla
        sta (sc),y
        rts

; scope_pop - back to the enclosing scope
scope_pop:
        dec scope_depth
        jmp sc_inner

; scope_kind -> A
scope_kind:
        ldy #SC_KIND
        lda (sc),y
        rts

; local_find - A/X = sym -> C clear, Y = local index; C set if not local
local_find:
        sta t0
        stx t0+1
        ldy #SC_NLOCALS
        lda (sc),y
        sta t1
        ldx #0
-       cpx t1
        bcs _no
        txa
        asl
        clc
        adc #SC_LOCALS
        tay
        lda (sc),y
        cmp t0
        bne +
        iny
        lda (sc),y
        cmp t0+1
        beq _yes
+       inx
        bra -
_yes:   txa
        tay
        clc
        rts
_no:    sec
        rts

; local_add - A/X = sym: add it unless already local or declared global / nonlocal
local_add:
        sta t2
        stx t2+1
        jsr global_find
        bcc _done
        lda t2
        ldx t2+1
        jsr nonlocal_find
        bcc _done
        lda t2
        ldx t2+1
        jsr local_find
        bcc _done
        ldy #SC_NLOCALS
        lda (sc),y
        cmp #MAX_LOCALS
        bcc +
        jsr syntax_error
        .text "too many local variables", 0
+       pha
        clc
        adc #1
        sta (sc),y
        pla
        asl
        clc
        adc #SC_LOCALS
        tay
        lda t2
        sta (sc),y
        iny
        lda t2+1
        sta (sc),y
_done:  rts

; global_find - A/X = sym -> C clear if declared global in this scope
global_find:
        sta t0
        stx t0+1
        ldy #SC_NGLOBALS
        lda (sc),y
        sta t1
        ldx #0
-       cpx t1
        bcs _no
        txa
        asl
        clc
        adc #SC_GLOBALS
        tay
        lda (sc),y
        cmp t0
        bne +
        iny
        lda (sc),y
        cmp t0+1
        beq _yes
+       inx
        bra -
_yes:   clc
        rts
_no:    sec
        rts

global_add:
        sta t2
        stx t2+1
        jsr global_find
        bcc _done
        ldy #SC_NGLOBALS
        lda (sc),y
        cmp #MAX_GLOBALS
        bcc +
        jsr syntax_error
        .text "too many global declarations", 0
+       pha
        clc
        adc #1
        sta (sc),y
        pla
        asl
        clc
        adc #SC_GLOBALS
        tay
        lda t2
        sta (sc),y
        iny
        lda t2+1
        sta (sc),y
_done:  rts

; nonlocal_find - A/X = sym -> C clear if declared nonlocal in this scope
nonlocal_find:
        sta t0
        stx t0+1
        ldy #SC_NNONLOC
        lda (sc),y
        sta t1
        ldx #0
-       cpx t1
        bcs _no
        txa
        asl
        clc
        adc #SC_NONLOCALS
        tay
        lda (sc),y
        cmp t0
        bne +
        iny
        lda (sc),y
        cmp t0+1
        beq _yes
+       inx
        bra -
_yes:   clc
        rts
_no:    sec
        rts

nonlocal_add:
        sta t2
        stx t2+1
        jsr nonlocal_find
        bcc _done
        ldy #SC_NNONLOC
        lda (sc),y
        cmp #MAX_NONLOCALS
        bcc +
        jsr syntax_error
        .text "too many nonlocal declarations", 0
+       pha
        clc
        adc #1
        sta (sc),y
        pla
        asl
        clc
        adc #SC_NONLOCALS
        tay
        lda t2
        sta (sc),y
        iny
        lda t2+1
        sta (sc),y
_done:  rts

; Y = local index -> A = its LOAD_FAST/STORE_FAST operand: 2*(nlocals-1-i)
local_offset:
        sty t0
        ldy #SC_NLOCALS
        lda (sc),y
        sec
        sbc #1
        sbc t0
        asl
        rts

;---------------------------------------------------------------------------------------
; names
;---------------------------------------------------------------------------------------
; emit_load_name - tok_sym (the current NAME)
emit_load_name:
        jsr c_here
        sta c_last_op
        stx c_last_op+1
        lda tok_sym
        ldx tok_sym+1
        jsr resolve_name
        cmp #RN_FAST
        bne +
        lda t6
        ldy #OP_LOAD_FAST
        jmp emit_op_byte
+       cmp #RN_DEREF
        bne _global
        lda t6
        ldx t6+1
        ldy #OP_LOAD_DEREF
        jmp emit_op_word
_global:
        lda tok_sym
        ldx tok_sym+1
        jsr gsym                        ; (a module's names are hidden symbols)
        pha
        jsr scope_kind
        tay
        pla
        cpy #SK_CLASS                   ; a class body: its own names first
        beq +
        ldy #OP_LOAD_GLOBAL
        jmp emit_op_word
+       ldy #OP_LOAD_CLASSNAME
        jmp emit_op_word

; resolve_name - A/X = sym, in the current scope -> A = RN_GLOBAL; RN_FAST (t6 = the
; LOAD_FAST operand); RN_DEREF (t6 = depth, t6+1 = cell). A function's own locals are
; fast unless they are cells; other names are cells of enclosing functions (found
; outward, past class scopes; depth = the environments in between) or globals.
RN_GLOBAL       = 0
RN_FAST         = 1
RN_DEREF        = 2
rn_sym:         .word 0
rn_cur:         .byte 0                 ; the current scope's index
rn_func:        .byte 0                 ; the function whose frame runs this code
rn_need:        .byte 0                 ; nonlocal: it must be found
resolve_name:
        sta rn_sym
        stx rn_sym+1
        lda scope_depth
        sec
        sbc #1
        sta rn_cur
        lda #0
        sta rn_need
        jsr scope_kind
        cmp #SK_MODULE
        bne +
        lda #RN_GLOBAL
        rts
+       cmp #SK_FUNC
        bne _search                     ; a class body: enclosing cells, else globals
        lda rn_sym
        ldx rn_sym+1
        jsr global_find
        bcs +
        lda #RN_GLOBAL
        rts
+       lda rn_sym
        ldx rn_sym+1
        jsr nonlocal_find
        bcs +
        inc rn_need
        bra _search
+       lda rn_sym
        ldx rn_sym+1
        jsr local_find
        bcc +
        jmp _search
+       jsr rn_cell                     ; Y = local -> A = cell + 1 (0: none)
        bne +
        jsr local_offset
        sta t6
        lda #RN_FAST
        rts
+       dec a
        sta t6+1
        lda #0
        sta t6
        lda #RN_DEREF
        rts
_search:                                ; the enclosing scopes, outward
        jsr rn_frame
        ldx rn_cur
-       dex
        bmi _none
        txa
        pha
        jsr sc_at
        jsr scope_kind
        tay
        pla
        tax
        cpy #SK_MODULE
        beq _none
        cpy #SK_FUNC
        bne -
        phx
        lda rn_sym
        ldx rn_sym+1
        jsr local_find
        plx
        bcs -
        jsr rn_cell                     ; a local there: shared only if it is a cell
        beq _none
        dec a
        sta t6+1
        jsr rn_depth                    ; X = its scope -> t6
        lda rn_cur
        jsr sc_at
        lda #RN_DEREF
        rts
_none:  lda rn_cur
        jsr sc_at
        lda rn_need
        bne +
        lda #RN_GLOBAL
        rts
+       jsr syntax_error
        .text "no binding for nonlocal name found", 0

; rn_cell - Y = local index (of sc, kept) -> A = its cell + 1, Z flag set if no cell
rn_cell:
        phy
        tya
        clc
        adc #SC_CELLMAP
        tay
        lda (sc),y
        ply
        cmp #0
        rts

; rn_frame - rn_func = the function scope at or around rn_cur whose frame runs it
rn_frame:
        ldx rn_cur
-       txa
        pha
        jsr sc_at
        jsr scope_kind
        tay
        pla
        tax
        cpy #SK_FUNC
        beq +
        dex
        bpl -
+       stx rn_func
        rts

; rn_depth - X = the scope holding the cell -> t6 = environments between it and the
; frame's function (those of the function scopes with cells, rn_func down to X + 1)
rn_depth:
        stx t5
        lda #0
        sta t6
        ldx rn_func
-       cpx t5
        beq +
        txa
        pha
        jsr sc_at
        jsr scope_kind
        cmp #SK_FUNC
        bne _next
        ldy #SC_NCELLS
        lda (sc),y
        beq _next
        inc t6
_next:  pla
        tax
        dex
        bra -
+       rts

; emit_store_sym - A/X = sym: store TOS into that name in the current scope
emit_store_sym:
        jsr store_op_for_sym
        jmp emit_store_op

; store_op_for_sym - A/X = sym -> A = store opcode, t6 = its operand
store_op_for_sym:
        sta t4
        stx t4+1
        jsr scope_kind
        cmp #SK_CLASS
        beq _class
        lda t4
        ldx t4+1
        jsr resolve_name
        cmp #RN_FAST
        bne +
        lda #OP_STORE_FAST
        rts
+       cmp #RN_DEREF
        bne _global
        lda #OP_STORE_DEREF
        rts
_global:
        lda t4
        ldx t4+1
        jsr gsym
        sta t6
        stx t6+1
        lda #OP_STORE_GLOBAL
        rts
_class: lda t4
        ldx t4+1
        jsr sym_name
        sta t6
        stx t6+1
        lda #OP_STORE_CLASSATTR
        rts

;---------------------------------------------------------------------------------------
; turning the last load into a store / delete
;---------------------------------------------------------------------------------------
; last_load - C clear if the last instruction emitted is a load we can assign to:
; A = its opcode, t6 = its operand (word; offset byte for LOAD_FAST)
last_load:
        lda c_last_op
        ldx c_last_op+1
        ldz #0
        jsr code_peek
        sta t5
        ; it must be the very last instruction: its end == cp
        tax
        lda op_len,x
        and #$7f
        sec                             ; + opcode byte
        adc c_last_op
        sta t1
        lda c_last_op+1
        adc #0
        cmp cp+1
        bne _no
        lda t1
        cmp cp
        bne _no
        lda t5
        cmp #OP_LOAD_FAST
        beq _ok
        cmp #OP_LOAD_GLOBAL
        beq _ok
        cmp #OP_LOAD_DEREF
        beq _ok
        cmp #OP_LOAD_CLASSNAME
        beq _ok
        cmp #OP_LOAD_ATTR
        beq _ok
        cmp #OP_LOAD_SUBSCR
        beq _ok
_no:    sec
        rts
_ok:    ldz #1
        lda c_last_op
        ldx c_last_op+1
        jsr code_peek
        sta t6
        ldz #2
        lda c_last_op
        ldx c_last_op+1
        jsr code_peek
        sta t6+1
        lda t5
        clc
        rts

; store_for_load - A = load opcode, t6 = operand -> A = store opcode (class scope:
; a global name becomes STORE_CLASSATTR with the name ref in t6)
store_for_load:
        cmp #OP_LOAD_FAST
        bne +
        lda #OP_STORE_FAST
        rts
+       cmp #OP_LOAD_DEREF
        bne +
        lda #OP_STORE_DEREF
        rts
+       cmp #OP_LOAD_ATTR
        bne +
        lda #OP_STORE_ATTR
        rts
+       cmp #OP_LOAD_SUBSCR
        bne +
        lda #OP_STORE_SUBSCR
        rts
+       jsr scope_kind
        cmp #SK_CLASS
        beq +
        lda #OP_STORE_GLOBAL
        rts
+       lda t6
        ldx t6+1
        jsr unmangle                    ; (the attribute's own name)
        jsr sym_name
        sta t6
        stx t6+1
        lda #OP_STORE_CLASSATTR
        rts

; emit_store_op - A = store opcode, t6 = operand
emit_store_op:
        tay
        tax
        lda op_len,x
        beq _none
        cmp #1
        beq _byte
        tya
        jsr emit
        lda t6
        ldx t6+1
        jmp emit_word
_byte:  tya
        jsr emit
        lda t6
        jmp emit
_none:  tya
        jmp emit

; cp = c_last_op (drop the last load)
drop_last:
        lda c_last_op
        sta cp
        lda c_last_op+1
        sta cp+1
        rts

;---------------------------------------------------------------------------------------
; the cut stack (attic): code moved away and pasted back elsewhere
; entry: +0 original offset (word), +2 length (word), +4 the code
;---------------------------------------------------------------------------------------
; cut_code - A/X = start offset: move code start..cp to the cut stack -> A/X = handle
cut_code:
        sta t0
        stx t0+1
        lda cut_top
        pha
        lda cut_top+1
        pha
        ; header
        ldx #3
-       lda cut_top,x
        sta fp1,x
        dex
        bpl -
        ldz #0
        lda t0
        sta [fp1],z
        inz
        lda t0+1
        sta [fp1],z
        sec
        lda cp
        sbc t0
        sta t1
        inz
        sta [fp1],z
        lda cp+1
        sbc t0+1
        sta t1+1
        inz
        sta [fp1],z
        ; body
        clc
        lda fp1
        adc #4
        sta fp1
        bcc +
        inc fp1+1
+       lda t1
        ora t1+1
        beq +
        lda t0
        sta fp0
        lda t0+1
        sta fp0+1
        lda #CODE_BANK
        sta fp0+2
        lda #0
        sta fp0+3
        lda t1
        sta t0
        lda t1+1
        sta t0+1
        jsr dma_copy
+       ; cut_top += 4 + len; cp = start
        clc
        lda fp1
        adc t1
        sta cut_top
        lda fp1+1
        adc t1+1
        sta cut_top+1
        lda cp
        sec
        sbc t1
        sta cp
        lda cp+1
        sbc t1+1
        sta cp+1
        plx
        pla
        rts

; paste_code - A/X = handle: emit the code at cp, relocating its jumps
paste_code:
        sta fp0
        stx fp0+1
        lda cut_top+2
        sta fp0+2
        lda cut_top+3
        sta fp0+3
        ldz #0
        lda [fp0],z
        sta t2                          ; original start
        inz
        lda [fp0],z
        sta t2+1
        inz
        lda [fp0],z
        sta t1                          ; length
        inz
        lda [fp0],z
        sta t1+1
        ; delta = cp - original start
        sec
        lda cp
        sbc t2
        sta t3
        lda cp+1
        sbc t2+1
        sta t3+1
        ; t4 = original end
        clc
        lda t2
        adc t1
        sta t4
        lda t2+1
        adc t1+1
        sta t4+1
        lda cp
        sta t5                          ; where the paste starts
        lda cp+1
        sta t5+1
        clc
        lda fp0
        adc #4
        sta fp0
        bcc +
        inc fp0+1
+       lda t1
        ora t1+1
        beq _done
        lda cp
        sta fp1
        lda cp+1
        sta fp1+1
        lda #CODE_BANK
        sta fp1+2
        lda #0
        sta fp1+3
        lda t1
        sta t0
        lda t1+1
        sta t0+1
        jsr dma_copy
        clc
        lda cp
        adc t1
        sta cp
        lda cp+1
        adc t1+1
        sta cp+1
        ; walk the pasted instructions
        lda t5
        sta fp1
        lda t5+1
        sta fp1+1
_walk:  lda fp1+1
        cmp cp+1
        bcc +
        lda fp1
        cmp cp
        bcs _done
+       ldz #0
        lda [fp1],z
        tax
        cmp #OP_MAKE_FUNCTION
        beq _reloc
        lda op_len,x
        bpl _skip
_reloc: ; operand word at +1: relocate if it points inside the moved code
        ldz #2
        lda [fp1],z
        cmp t2+1
        bcc _skip
        bne +
        dez
        lda [fp1],z
        cmp t2
        bcc _skip
+       ldz #2
        lda [fp1],z
        cmp t4+1
        bcc +
        bne _skip
        dez
        lda [fp1],z
        cmp t4
        beq +
        bcs _skip
+       ldz #1
        clc
        lda [fp1],z
        adc t3
        sta [fp1],z
        inz
        lda [fp1],z
        adc t3+1
        sta [fp1],z
_skip:  ldz #0
        lda [fp1],z
        tax
        lda op_len,x
        and #$7f
        sec
        adc fp1
        sta fp1
        bcc _walk
        inc fp1+1
        bra _walk
_done:  rts

; cut_mark / cut_release: free everything cut since a mark (A/X)
cut_mark:
        lda cut_top
        ldx cut_top+1
        rts
cut_release:
        sta cut_top
        stx cut_top+1
        rts

;---------------------------------------------------------------------------------------
; compile_source - lx_ptr = zero-terminated source. Compiles it all (module scope)
; -> A/X = code offset of the start. c_repl selects printing expression statements.
;---------------------------------------------------------------------------------------
compile_source:
        lda #F_PERM
        sta al_perm
        lda #0
        sta scope_depth
        sta tg_top
        sta c_noin
        sta lx_scan
        sta lx_savesp
        lda #0
        sta w_sp
        sta xb_n
        sta fin_n
        lda #<CUTBUF
        sta cut_top
        lda #>CUTBUF
        sta cut_top+1
        lda #<(CUTBUF >> 16)
        sta cut_top+2
        lda #>(CUTBUF >> 16)
        sta cut_top+3
        lda #$ff
        sta c_line
        sta c_line+1
        lda #SK_MODULE
        jsr scope_push
        jsr lx_init
        jsr c_here
        sta c_start
        stx c_start+1
        jsr lex
-       lda tok
        cmp #TK_EOF
        beq +
        jsr statement
        bra -
+       lda #OP_HALT
        jsr emit
        lda #0
        sta al_perm
        lda c_start
        ldx c_start+1
        rts

;---------------------------------------------------------------------------------------
; statements
;---------------------------------------------------------------------------------------
statement:
        jsr stack_check
        jsr c_mark_line
        lda tok
        cmp #KW_IF
        bne +
        jmp st_if
+       cmp #KW_WHILE
        bne +
        jmp st_while
+       cmp #KW_FOR
        bne +
        jmp st_for
+       cmp #KW_DEF
        bne +
        jmp st_def
+       cmp #KW_CLASS
        bne +
        jmp st_class
+       cmp #KW_TRY
        bne +
        jmp st_try
+       cmp #KW_WITH
        bne +
        jmp st_with
+       cmp #TK_AT
        bne +
        jmp st_decorated
+       cmp #TK_INDENT
        bne simple_line
        jsr indent_error
        .text "unexpected indent", 0

; simple statements separated by ; up to the NEWLINE
simple_line:
-       jsr simple_stmt
        lda #TK_SEMI
        jsr accept
        bcc +
        lda tok
        cmp #TK_NEWLINE
        bne -
+       lda tok
        cmp #TK_EOF
        beq +
        lda #TK_NEWLINE
        jmp expect
+       rts

; recursion guard for the compiler (16-bit stack: compare SP high byte)
stack_check:
        tsy
        cpy #>CPUSTACK_LIMIT
        bcc +
        bne ++
        tsx
        cpx #<CPUSTACK_LIMIT
        bcs ++
+       jsr syntax_error
        .text "too complex (nesting too deep)", 0
+       rts

simple_stmt:
        lda tok
        cmp #KW_PASS
        bne +
        jmp lex
+       cmp #KW_BREAK
        bne +
        jmp st_break
+       cmp #KW_CONTINUE
        bne +
        jmp st_continue
+       cmp #KW_RETURN
        bne +
        jmp st_return
+       cmp #KW_GLOBAL
        bne +
        jmp st_global
+       cmp #KW_NONLOCAL
        bne +
        jmp st_nonlocal
+       cmp #KW_DEL
        bne +
        jmp st_del
+       cmp #KW_RAISE
        bne +
        jmp st_raise
+       cmp #KW_ASSERT
        bne +
        jmp st_assert
+       cmp #KW_IMPORT
        bne +
        jmp st_import
+       cmp #KW_FROM
        bne +
        jmp st_from
+       jmp st_expr

; a block after ':' - an indented suite, or simple statements on the same line
block:
        lda #TK_COLON
        jsr expect
        lda tok
        cmp #TK_NEWLINE
        beq +
        jmp simple_line
+       jsr lex
        lda tok
        cmp #TK_INDENT
        beq +
        jsr indent_error
        .text "expected an indented block", 0
+       jsr lex
-       lda tok
        cmp #TK_DEDENT
        beq +
        cmp #TK_EOF
        beq ++
        jsr statement
        bra -
+       jsr lex
+       rts

;---------------------------------------------------------------------------------------
st_if:
        ; CPU stack while compiling: [end chain][false jump] (false on top); t-regs
        ; do not survive nested blocks
        lda #0                          ; end chain (0 = empty)
        pha
        pha
        jsr lex
_test:  jsr expr
        ldy #OP_JUMP_IF_FALSE
        jsr emit_jump
        pha
        phx
        jsr block
        lda tok
        cmp #KW_ELIF
        beq _more
        cmp #KW_ELSE
        beq _more
        plx                             ; no more branches: false -> here
        pla
        jsr patch_here
        plx
        pla
        jmp patch_chain
_more:  plx                             ; t2 = false jump, t3 = chain
        pla
        sta t2
        stx t2+1
        plx
        pla
        sta t3
        stx t3+1
        lda #OP_JUMP                    ; jump to the end, chained
        jsr emit
        jsr c_here
        pha
        phx
        lda t3
        ldx t3+1
        jsr emit_word
        lda t2
        ldx t2+1
        jsr patch_here                  ; the false jump comes to the next branch
        lda tok
        cmp #KW_ELSE
        beq _else
        jsr lex                         ; elif: the chain is already pushed
        bra _test
_else:  jsr lex
        jsr block
        plx
        pla
        jmp patch_chain

; patch_chain - A/X = head of a jump chain (each operand holds the next): all -> here
patch_chain:
-       cpx #0
        beq +
        sta t0
        stx t0+1
        ldz #0
        jsr code_peek
        pha
        ldz #1
        lda t0
        ldx t0+1
        jsr code_peek
        pha
        lda t0
        ldx t0+1
        jsr patch_here
        plx
        pla
        bra -
+       rts

;---------------------------------------------------------------------------------------
; loops
;---------------------------------------------------------------------------------------
; loop_push - A/X = continue target, Y = 1 for a for loop
loop_push:
        sta t0
        stx t0+1
        sty t1
        ldy #SC_NLOOPS
        lda (sc),y
        cmp #MAX_LOOPS
        bcc +
        jsr syntax_error
        .text "loops nested too deeply", 0
+       pha
        clc
        adc #1
        sta (sc),y
        pla
        jsr loop_rec
        lda t0
        sta (sc),y
        iny
        lda t0+1
        sta (sc),y
        iny
        lda #0
        sta (sc),y
        iny
        sta (sc),y
        iny
        lda xb_n                        ; the blocks open outside it (loop_exits)
        sta (sc),y
        iny
        lda t1
        sta (sc),y
        rts

; A = loop index -> Y = offset of its record
loop_rec:
        asl
        asl
        asl
        clc
        adc #SC_LOOPS
        tay
        rts

; current (innermost) loop -> Y = its record, C set if none
loop_top:
        ldy #SC_NLOOPS
        lda (sc),y
        bne +
        sec
        rts
+       sec
        sbc #1
        jsr loop_rec
        clc
        rts

; loop_pop - patch the break chain to here and drop the loop
loop_pop:
        jsr loop_top
        iny
        iny
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr patch_chain
        ldy #SC_NLOOPS
        lda (sc),y
        sec
        sbc #1
        sta (sc),y
        rts

st_break:
        jsr lex
        jsr loop_top
        bcc +
        jsr syntax_error
        .text "'break' outside loop", 0
+       jsr loop_exits                  ; (finally blocks, __exit__ calls)
        jsr loop_top
        tya
        clc
        adc #5
        tay
        lda (sc),y
        beq +
        lda #OP_POP                     ; leaving a for loop: drop its iterator
        jsr emit
+       lda #OP_JUMP
        jsr emit
        jsr loop_top
        iny
        iny
        jsr c_here
        pha
        phx
        lda (sc),y                      ; old chain head as the operand
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr emit_word
        plx
        pla
        dey
        sta (sc),y
        iny
        txa
        sta (sc),y
        rts

st_continue:
        jsr lex
        jsr loop_top
        bcc +
        jsr syntax_error
        .text "'continue' not properly in loop", 0
+       jsr loop_exits
        jsr loop_top
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        ldy #OP_JUMP
        jmp emit_op_word

st_while:
        jsr lex
        jsr c_here                      ; the loop top
        pha
        phx
        ldy #0
        jsr loop_push                   ; continue -> top
        jsr expr
        ldy #OP_JUMP_IF_FALSE
        jsr emit_jump
        pha                             ; CPU: [top][false]
        phx
        jsr block
        plx
        pla
        sta t2
        stx t2+1
        plx
        pla
        ldy #OP_JUMP                    ; back to the top
        jsr emit_op_word
        lda t2                          ; the false exit lands here (before else)
        ldx t2+1
        jsr patch_here
        lda tok
        cmp #KW_ELSE
        bne +
        jsr lex
        jsr block
+       jmp loop_pop

st_for:
        jsr lex
        ; targets (stored after FOR_ITER, so their code is cut away now)
        jsr target_list                 ; -> A = number of targets
        pha
        lda #KW_IN
        jsr expect
        jsr exprlist
        lda #OP_GET_ITER
        jsr emit
        jsr c_here                      ; loop top
        pha
        phx
        ldy #OP_FOR_ITER
        jsr emit_jump
        sta t0
        stx t0+1
        plx
        pla
        sta t1
        stx t1+1
        pla                             ; target count
        tay
        lda t0                          ; keep the exit patch on the CPU stack
        pha
        lda t0+1
        pha
        lda t1
        pha
        lda t1+1
        pha
        tya
        jsr store_targets
        ; loop record: continue = top
        pla
        tax
        pla
        pha
        phx
        ldy #1
        jsr loop_push
        jsr block
        ; jump back to the top
        pla
        tax
        pla
        ldy #OP_JUMP
        jsr emit_op_word
        ; FOR_ITER's exit (the iterator is already popped)
        pla
        tax
        pla
        jsr patch_here
        lda tok
        cmp #KW_ELSE
        bne +
        jsr lex
        jsr block
+       jmp loop_pop

;---------------------------------------------------------------------------------------
; with m [as x]: body
;   m; STORE w; LOAD w; LOAD_METHOD __enter__; CALL_METHOD 0; STORE x (or POP)
;   SETUP_EXCEPT f; body; POP_BLOCK; <w.__exit__(None, None, None)>; JUMP done
;   f: <w.__exit__(type(e), e, None)>; JUMP_IF_FALSE r; POP; POP_EXCEPT; JUMP done
;   r: RAISE 0; done:
; w is a hidden variable (" w<n>", a local in functions: see prescan). break, continue
; and return call the __exit__ of the with blocks they leave.
;---------------------------------------------------------------------------------------
w_stk:          .fill 2*16              ; the hidden variables of the open with blocks
w_sp:           .byte 0
w_name:         .text " w00", 0

; with_sym - A = number -> A/X = the symbol of hidden variable number A
with_sym:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        clc
        adc #'a'
        sta w_name+2
        pla
        and #15
        clc
        adc #'a'
        sta w_name+3
        lda #<w_name
        ldx #>w_name
        jmp intern_cstr

st_with:
        jsr lex
; with_item - one manager (tok at its expression); 'with a, b:' is 'with a: with b:'
with_item:
        jsr expr                        ; the context manager
        ldy #SC_WCOUNT
        lda (sc),y
        inc a
        sta (sc),y
        dec a
        jsr with_sym
        ldy w_sp
        cpy #2*16
        bcc +
        jsr syntax_error
        .text "with statements nested too deeply", 0
+       sta w_stk,y
        txa
        sta w_stk+1,y
        iny
        iny
        sty w_sp
        lda w_stk-2,y
        jsr emit_store_sym
        ldy w_sp
        jsr w_load
        lda #<S_ENTER
        ldx #>S_ENTER
        jsr sym_name
        ldy #OP_LOAD_METHOD
        jsr emit_op_word
        ldy #OP_CALL_METHOD
        lda #0
        jsr emit_op_byte
        lda #KW_AS
        jsr accept
        bcc _noas
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        ldx tok_sym+1
        jsr emit_store_sym
        jsr lex
        bra +
_noas:  lda #OP_POP
        jsr emit
+       ldy #OP_SETUP_EXCEPT
        jsr emit_jump
        pha                             ; CPU: [handler]
        phx
        lda #XB_WITH                    ; (an exit from the block: POP_BLOCK, __exit__)
        ldx #1
        ldy w_sp
        jsr xb_push
        lda #TK_COMMA                   ; another manager: the rest is inside this one
        jsr accept
        bcc +
        jsr with_item
        bra ++
+       jsr block
+       dec xb_n
        lda #OP_POP_BLOCK
        jsr emit
        lda #1
        jsr w_exits
        ldy #OP_JUMP
        jsr emit_jump
        sta t2
        stx t2+1
        plx                             ; the handler starts here
        pla
        jsr patch_here
        lda t2                          ; CPU: [done]
        pha
        lda t2+1
        pha
        ; [exc]: w.__exit__(type(exc), exc, None); a true result swallows it
        lda #OP_DUP
        jsr emit
        ldy w_sp
        jsr w_load
        lda #<S_EXIT
        ldx #>S_EXIT
        jsr sym_name
        ldy #OP_LOAD_METHOD
        jsr emit_op_word                ; [exc][exc][m][self]
        lda #OP_LIFT3
        jsr emit                        ; [exc][m][self][exc]
        lda #OP_DUP
        jsr emit
        lda #<S_CLASS
        ldx #>S_CLASS
        jsr sym_name
        ldy #OP_LOAD_ATTR
        jsr emit_op_word
        lda #OP_ROT2
        jsr emit                        ; [exc][m][self][type][exc]
        lda #R_NONE
        ldx #0
        jsr emit_const
        ldy #OP_CALL_METHOD
        lda #3
        jsr emit_op_byte
        ldy #OP_JUMP_IF_FALSE
        jsr emit_jump
        pha                             ; CPU: [done][reraise]
        phx
        lda #OP_POP                     ; swallowed
        jsr emit
        lda #OP_POP_EXCEPT
        jsr emit
        ldy #OP_JUMP
        jsr emit_jump
        sta t2
        stx t2+1
        plx
        pla
        jsr patch_here
        ldy #OP_RAISE
        lda #0
        jsr emit_op_byte
        lda t2
        ldx t2+1
        jsr patch_here
        plx
        pla
        jsr patch_here
        dec w_sp
        dec w_sp
        rts

; w_load - emit a load of the hidden variable of with block w_stk[Y-2]
w_load: lda tok_sym
        pha
        lda tok_sym+1
        pha
        lda w_stk-2,y
        sta tok_sym
        lda w_stk-1,y
        sta tok_sym+1
        jsr emit_load_name
        pla
        sta tok_sym+1
        pla
        sta tok_sym
        rts

; w_exits - emit the __exit__ calls of the innermost A with blocks (innermost first)
w_exits:
        cmp #0
        beq _done
        ldy w_sp
_loop:  pha
        phy
        jsr w_exit_y
        ply
        dey
        dey
        pla
        dec a
        bne _loop
_done:  rts
; w_exit_y - emit the __exit__ call of the with block w_stk[Y-2]
w_exit_y:
        jsr w_load
        lda #<S_EXIT
        ldx #>S_EXIT
        jsr sym_name
        ldy #OP_LOAD_METHOD
        jsr emit_op_word
        lda #R_NONE
        ldx #0
        jsr emit_const
        lda #R_NONE
        ldx #0
        jsr emit_const
        lda #R_NONE
        ldx #0
        jsr emit_const
        ldy #OP_CALL_METHOD
        lda #3
        jsr emit_op_byte
        lda #OP_POP
        jmp emit

;---------------------------------------------------------------------------------------
; Leaving blocks early (break, continue, return). The open try / with blocks are on the
; exit stack, innermost last, each with the handlers it holds now (POP_BLOCKs) and its
; exit code: a with's __exit__ call, or a try's finally body, compiled again in place
; (fin_lx holds the lexer state at its ':', found when the try started: try_scan).
;---------------------------------------------------------------------------------------
XB_N            = 16
XB_TRY          = 0                     ; handlers only
XB_WITH         = 1                     ; aux = its w_sp
XB_FIN          = 2                     ; aux = its finally record
xb_n:           .byte 0
xb_kind:        .fill XB_N
xb_pops:        .fill XB_N
xb_aux:         .fill XB_N
xb_scope:       .fill XB_N              ; the scope_depth it belongs to
xb_lim:         .byte 0
FIN_N           = 8
fin_n:          .byte 0
fin_lx:         .fill FIN_N * LX_STATE_SIZE

; xb_push - A = kind, X = handlers, Y = aux
xb_push:
        phy
        ldy xb_n
        cpy #XB_N
        bcc +
        jsr syntax_error
        .text "blocks nested too deeply", 0
+       sta xb_kind,y
        txa
        sta xb_pops,y
        pla
        sta xb_aux,y
        lda scope_depth
        sta xb_scope,y
        inc xb_n
        rts

; xb_exits - leave the current scope's blocks above A (an xb_n to keep): their exit
; code, innermost first. The stack is as it was afterwards (the code jumps away).
xb_exits:
        sta xb_lim
        lda xb_n
        pha
_next:  ldx xb_n
        cpx xb_lim
        beq _done
        bcc _done
        dex
        lda xb_scope,x
        cmp scope_depth
        bne _done
        stx xb_n                        ; (its finally code sees the blocks outside)
        lda xb_pops,x
        beq _code
-       pha
        lda #OP_POP_BLOCK
        jsr emit
        pla
        dec a
        bne -
_code:  ldx xb_n
        lda xb_kind,x
        cmp #XB_WITH
        bne +
        ldy xb_aux,x
        jsr w_exit_y
        bra _next
+       cmp #XB_FIN
        bne _next
        lda xb_lim                      ; (a break in it leaves blocks of its own)
        pha
        lda xb_aux,x
        jsr fin_inline
        pla
        sta xb_lim
        bra _next
_done:  pla
        sta xb_n
        rts

; fin_inline - A = a finally record: compile its body here (the lexer comes back)
fin_inline:
        pha
        jsr lx_push
        pla
        jsr fin_lexer
        jsr block
        jmp lx_pop

; fin_lexer - A = a finally record -> the lexer state at its ':'
fin_lexer:
        jsr fin_addr                    ; t0 -> the record
        ldy #0
-       lda (t0),y
        sta lx_ptr,y
        iny
        cpy #LX_STATE_SIZE
        bne -
        lda #0
        sta lx_scan
        rts
; fin_addr - A = a finally record -> t0 = its address
fin_addr:
        tax
        lda #<fin_lx
        sta t0
        lda #>fin_lx
        sta t0+1
_loop:  cpx #0
        beq _done
        clc
        lda t0
        adc #LX_STATE_SIZE
        sta t0
        bcc +
        inc t0+1
+       dex
        bra _loop
_done:  rts

; try_scan - (tok = the ':' after 'try') does a finally clause follow? -> C set and
; A = a new finally record with the lexer state at its ':'; the lexer comes back
try_scan:
        jsr lx_push
        lda #1
        sta lx_scan
        jsr skip_block                  ; the try body
-       lda tok
        cmp #KW_EXCEPT
        beq +
        cmp #KW_ELSE
        bne ++
+       jsr skip_header                 ; 'except ...:' / 'else:'
        jsr skip_block
        bra -
+       cmp #KW_FINALLY
        clc
        bne _out
        jsr lex                         ; its ':'
        lda fin_n
        cmp #FIN_N
        bcc +
        jsr syntax_error
        .text "try statements nested too deeply", 0
+       inc fin_n
        pha
        jsr fin_addr
        ldy #0
-       lda lx_ptr,y
        sta (t0),y
        iny
        cpy #LX_STATE_SIZE
        bne -
        pla
        sec
_out:   php
        pha
        jsr lx_pop
        pla
        plp
        rts

; skip_header - lex to the ':' that ends a clause header (outside brackets)
skip_header:
        ldx #0
-       lda tok
        cmp #TK_COLON
        bne +
        cpx #0
        beq _done
+       cmp #TK_EOF
        beq _done
        jsr ge_depth
        phx
        jsr lex
        plx
        bra -
_done:  rts

; skip_block - (tok = ':') lex past a block: an indented suite or the rest of the line
skip_block:
        jsr lex
        lda tok
        cmp #TK_NEWLINE
        beq _suite
-       lda tok                         ; simple statements on this line
        cmp #TK_EOF
        beq _done
        cmp #TK_NEWLINE
        beq _last
        jsr lex
        bra -
_suite: jsr lex                         ; INDENT
        ldx #0
-       lda tok
        cmp #TK_EOF
        beq _done
        cmp #TK_INDENT
        bne +
        inx
+       cmp #TK_DEDENT
        bne +
        dex
        beq _last
+       phx
        jsr lex
        plx
        bra -
_last:  jmp lex
_done:  rts

; loop_exits - break / continue: leave the blocks opened inside the current loop
loop_exits:
        jsr loop_top
        iny
        iny
        iny
        iny
        lda (sc),y
        jmp xb_exits

;---------------------------------------------------------------------------------------
; try / except / else / finally
;---------------------------------------------------------------------------------------
st_try:
        ; [NOP NOP NOP] SETUP_EXCEPT h; body; POP_BLOCK; JUMP ok
        ; h: except clauses (each ends with POP_EXCEPT; JUMP end) ... RAISE 0
        ; ok: else block
        ; end:  with finally, the NOPs become SETUP_EXCEPT f, and then
        ;       POP_BLOCK; <finally>; JUMP done; f: POP; <finally>; RAISE 0; done:
        ; Its exit stack entry: the body holds 1 handler (2 with finally: the outer one
        ; too); the except / else clauses of a try with finally hold the outer one.
        jsr lex
        jsr try_scan                    ; a finally clause? (A = its record)
        tay
        lda #XB_TRY
        ldx #1
        bcc +
        lda #XB_FIN
        inx
+       jsr xb_push
        jsr c_here                      ; the placeholder for an outer handler
        pha
        phx
        lda #OP_NOP
        jsr emit
        jsr emit
        jsr emit
        lda #OP_SETUP_EXCEPT
        jsr emit
        jsr c_here
        pha                             ; CPU: [outer][handler]
        phx
        lda #0
        tax
        jsr emit_word
        jsr block
        ldx xb_n                        ; past the body: a finally's outer handler only
        dex
        lda xb_kind,x
        cmp #XB_FIN
        beq +
        stx xb_n
        bra ++
+       lda #1
        sta xb_pops,x
+       lda #OP_POP_BLOCK
        jsr emit
        ldy #OP_JUMP                    ; to else/end
        jsr emit_jump
        sta t0
        stx t0+1
        plx                             ; the handler starts here
        pla
        jsr patch_here
        lda t0                          ; CPU: [outer][ok jump][end chain]
        pha
        lda t0+1
        pha
        lda #0
        pha
        pha
_excepts:
        lda tok
        cmp #KW_EXCEPT
        beq +
        jmp _noexc
+       jsr lex
        lda tok
        cmp #TK_COLON
        bne _typed
        lda #OP_POP                     ; a bare except catches everything
        jsr emit
        jsr block
        jsr _to_end
        bra _excepts
_typed: lda #OP_DUP
        jsr emit
        jsr expr                        ; the class (or a tuple)
        lda #OP_EXC_MATCH
        jsr emit
        ldy #OP_JUMP_IF_FALSE
        jsr emit_jump
        pha
        phx
        lda #KW_AS
        jsr accept
        bcc _noas
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        ldx tok_sym+1
        jsr emit_store_sym
        jsr lex
        bra +
_noas:  lda #OP_POP
        jsr emit
+       jsr block
        plx                             ; the no-match jump
        pla
        sta t2
        stx t2+1
        jsr _to_end
        lda t2
        ldx t2+1
        jsr patch_here
        bra _excepts
_noexc: ldy #OP_RAISE                   ; no clause matched (or none): re-raise
        lda #0
        jsr emit_op_byte
        pla                             ; the try body's normal exit: else block
        sta t1+1
        pla
        sta t1
        plx
        pla
        jsr patch_here
        lda t1
        pha
        lda t1+1
        pha
        lda tok
        cmp #KW_ELSE
        bne +
        jsr lex
        jsr block
+       pla                             ; all handlers end here
        tax
        pla
        jsr patch_chain
        plx                             ; the placeholder
        pla
        ldy tok
        cpy #KW_FINALLY
        beq _finally
        rts
_finally:
        dec xb_n                        ; (its body runs outside the try)
        sta t2
        stx t2+1
        lda #OP_POP_BLOCK               ; normal exit: leave the outer block
        jsr emit
        jsr lex                         ; 'finally'
        lda t2
        pha
        lda t2+1
        pha
        jsr lx_push                     ; the finally block is compiled twice
        jsr block
        ldy #OP_JUMP
        jsr emit_jump
        sta t0
        stx t0+1
        plx                             ; the placeholder becomes SETUP_EXCEPT here
        pla
        sta cpat
        stx cpat+1
        lda #CODE_BANK
        sta cpat+2
        lda #0
        sta cpat+3
        ldz #0
        lda #OP_SETUP_EXCEPT
        sta [cpat],z
        inz
        lda cp
        sta [cpat],z
        inz
        lda cp+1
        sta [cpat],z
        lda t0
        pha
        lda t0+1
        pha
        lda #OP_POP                     ; the exception value
        jsr emit
        jsr lx_pop                      ; the finally block again
        jsr block
        ldy #OP_RAISE
        lda #0
        jsr emit_op_byte
        dec fin_n                       ; (try_scan's record)
        plx
        pla
        jmp patch_here

; jump to the end of the try statement: chained on the CPU stack under the return
_to_end:
        lda #OP_POP_EXCEPT
        jsr emit
        pla                             ; our return address
        sta t7
        pla
        sta t7+1
        pla                             ; chain head
        tax
        pla
        sta t0
        stx t0+1
        lda #OP_JUMP
        jsr emit
        jsr c_here
        pha
        phx
        lda t0
        ldx t0+1
        jsr emit_word
        plx
        pla
        pha                             ; the new chain head
        txa
        pha
        lda t7+1
        pha
        lda t7
        pha
        rts

; lx_rewind - go back to the most recent lx_push state, keeping nothing else
lx_rewind:
        jmp lx_pop

;---------------------------------------------------------------------------------------
; @decorator lines, then a def or class: the decorators are evaluated first and stay on
; the stack; the function (class) is made, then CALL 1 for each, innermost first, and
; the result is stored under the name (fb_ndeco -> SC_NDECO / st_class)
fb_ndeco:       .byte 0
st_decorated:
        lda #0
        pha                             ; decorators so far
-       jsr lex                         ; past '@'
        jsr expr
        lda #TK_NEWLINE
        jsr expect
        pla
        inc a
        pha
        lda tok
        cmp #TK_AT
        beq -
        pla
        sta fb_ndeco
        lda tok
        cmp #KW_DEF
        beq st_def
        cmp #KW_CLASS
        bne +
        jmp st_class
+       jsr syntax_error
        .text "a decorator must be followed by def or class", 0

; emit_deco_calls - A = decorators: CALL 1 for each
emit_deco_calls:
        tax
-       beq +
        phx
        lda #1
        ldy #OP_CALL
        jsr emit_op_byte
        plx
        dex
        bra -
+       rts

st_def:
        jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        sta fb_sym
        lda tok_sym+1
        sta fb_sym+1
        lda tok_ref
        pha
        lda tok_ref+1
        pha
        jsr lex
        plx
        pla
        ldy #0
        jmp function_body

lambda_expr:
        jsr lex
        lda #$ff                        ; no name to store
        sta fb_sym
        sta fb_sym+1
        lda #<lambda_text
        ldx #>lambda_text
        jsr intern_cstr
        lda int_ref
        ldx int_ref+1
        ldy #1
        jsr function_body
        lda #$ff
        sta c_last_op+1
        rts
lambda_text:    .text "<lambda>", 0

;---------------------------------------------------------------------------------------
; genexp - a generator expression (at '(' or a call's argument; tok = its 'for'). A/X =
; where the element's code (compiled already, in this scope) starts; the lexer state at
; the element is pushed. As CPython, it is a generator function of its own:
;   <first iterable> GET_ITER  MAKE_FUNCTION <genexpr>  JUMP x  <body>  x: ROT2  CALL 1
; whose body is the comprehension over its one parameter (" 0"), yielding the items.
; The element is compiled again, in the new scope.
;---------------------------------------------------------------------------------------
ge_psym:        .word 0                 ; the parameter's symbol
ge_name:        .text "<genexpr>", 0
ge_param:       .text " 0", 0           ; (a name no source can spell)
genexp:
        sta cp                          ; drop the element's code
        stx cp+1
        jsr lx_pop                      ; back to the element
        jsr lx_push
        ; the first iterable, here: after the first 'for ... in' outside brackets
        jsr ge_to_iter
        lda #1
        sta c_noin
        jsr or_test
        lda #0
        sta c_noin
        lda #OP_GET_ITER
        jsr emit
        jsr lx_pop                      ; back to the element
        jsr lx_push
        lda #1                          ; (the REPL must keep the code)
        sta c_made_func
        ; the function's scope (as function_body does)
        ldy #SC_CLASS
        lda (sc),y
        sta t6
        iny
        lda (sc),y
        sta t6+1
        lda #SK_FUNC
        jsr scope_push
        ldy #SC_CLASS
        lda t6
        sta (sc),y
        iny
        lda t6+1
        sta (sc),y
        ldy #SC_FLAGS                   ; (not a def: no name to store, no yield)
        lda #2
        sta (sc),y
        lda #<ge_name
        ldx #>ge_name
        jsr intern_cstr
        ldy #FB_NAME
        lda int_ref
        sta (sc),y
        iny
        lda int_ref+1
        sta (sc),y
        lda #<ge_param                  ; the parameter: the iterator
        ldx #>ge_param
        jsr intern_cstr
        sta ge_psym
        stx ge_psym+1
        jsr local_add
        lda #1
        ldy #SC_NARGS
        sta (sc),y
        jsr ge_scan                     ; the 'for' targets are its locals
        jsr fb_cells
        jsr params_tuple
        ldy #FB_PARAMS
        sta (sc),y
        iny
        txa
        sta (sc),y
        ; MAKE_FUNCTION code nargs nlocals name ndefaults params flags nkwonly
        lda #OP_MAKE_FUNCTION
        jsr emit
        jsr c_here
        ldy #FB_PATCH
        sta (sc),y
        iny
        txa
        sta (sc),y
        lda #0
        tax
        jsr emit_word
        lda #1
        jsr emit
        ldy #SC_NLOCALS
        lda (sc),y
        jsr emit
        ldy #FB_NAME
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr emit_word
        lda #0
        jsr emit
        ldy #FB_PARAMS
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr emit_word
        lda #FF_GEN
        jsr emit
        lda #0
        jsr emit
        jsr fb_outer_env
        bcc +
        lda #OP_SET_CLOSURE
        jsr emit
+       ldy #OP_JUMP                    ; jump over the body
        jsr emit_jump
        ldy #FB_JUMP
        sta (sc),y
        iny
        txa
        sta (sc),y
        ldy #FB_PATCH
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr patch_here
        ; the body
        jsr fb_prologue
        jsr lx_pop                      ; the element again, in this scope
        jsr c_here
        pha
        phx
        jsr expr
        plx
        pla
        ldy #2
        jsr comprehension
        lda #R_NONE
        ldx #0
        jsr emit_const
        lda #OP_RETURN
        jsr emit
        ldy #FB_JUMP
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr patch_here
        jsr scope_pop
        lda #OP_ROT2                    ; [iterator][function] -> call it
        jsr emit
        lda #1
        ldy #OP_CALL
        jsr emit_op_byte
        lda #$ff
        sta c_last_op+1
        rts

; ge_load_param - (comp_for) load the generator expression's parameter
ge_load_param:
        lda tok_sym
        pha
        lda tok_sym+1
        pha
        lda ge_psym
        sta tok_sym
        lda ge_psym+1
        sta tok_sym+1
        jsr emit_load_name
        pla
        sta tok_sym+1
        pla
        sta tok_sym
        rts

; ge_to_iter - (at the element) lex on past the first 'for ... in' outside brackets:
; tok = the first token of the first iterable
ge_to_iter:
        lda #1
        sta lx_scan
        ldx #0                          ; X = bracket depth
_tok:   lda tok
        jsr ge_depth
        bcs _eof
        cpx #0
        bne _next
        lda tok
        cmp #KW_IN
        bne _next
        lda ge_seen
        bne _eof
_next:  phx
        jsr lex
        plx
        bra _tok
_eof:   lda #0
        sta lx_scan
        sta ge_seen
        jmp lex
ge_seen:        .byte 0
; ge_depth - A = tok: brackets change X; a 'for' at depth 0 sets ge_seen -> C set at
; the end of the input
ge_depth:
        cmp #TK_LPAREN
        beq _open
        cmp #TK_LBRACK
        beq _open
        cmp #TK_LBRACE
        beq _open
        cmp #TK_RPAREN
        beq _close
        cmp #TK_RBRACK
        beq _close
        cmp #TK_RBRACE
        beq _close
        cmp #KW_FOR
        bne +
        cpx #0
        bne +
        sta ge_seen
+       cmp #TK_EOF
        beq _end
        cmp #TK_NEWLINE
        beq _end
        clc
        rts
_end:   sec
        rts
_open:  inx
        clc
        rts
_close: dex
        clc
        rts

; ge_scan - (at the element) the names after each 'for' up to its 'in' become locals;
; a nested lambda or generator expression makes them all cells. Ends at the ')'
; that closes the generator expression; the lexer state is kept.
ge_tgt:         .byte 0
ge_scan:
        jsr ps_inner_reset
        jsr lx_push
        lda #1
        sta lx_scan
        lda #0
        sta ge_tgt
        ldx #0
        bra _tok
_lex:   phx
        jsr lex
        plx
_tok:   lda tok
        cmp #TK_RPAREN
        bne +
        cpx #0
        beq _end
+       jsr ge_depth
        bcs _end
        lda tok
        cmp #KW_FOR
        bne +
        sta ge_tgt
        cpx #0                          ; (a 'for' in brackets: a nested comprehension)
        beq _lex
        sta ps_allcells
        bra _lex
+       cmp #KW_IN
        bne +
        lda #0
        sta ge_tgt
        bra _lex
+       cmp #KW_LAMBDA
        bne +
        sta ps_allcells
        bra _lex
+       cmp #TK_NAME
        bne _lex
        lda ge_tgt
        beq _lex
        phx
        lda tok_sym
        ldx tok_sym+1
        jsr local_add
        plx
        bra _lex
_end:   lda #0
        sta lx_scan
        sta ge_seen
        jmp lx_pop

; yield_expr - 'yield' [exprlist] or 'yield from' expr (the pre-scan made the function
; a generator). yield from is the loop  GET_ITER; None; t: SEND x; YIELD_VALUE; JUMP t;
; x:  (SEND passes the sent values on; at x its result is on the stack).
yf_exit:        .word 0
yield_expr:
        jsr scope_kind
        cmp #SK_FUNC
        beq +
        jsr syntax_error
        .text "'yield' outside function", 0
+       ldy #SC_FLAGS
        lda (sc),y
        beq +
        jsr syntax_error
        .text "yield in a lambda is not supported", 0
+       jsr lex
        lda tok
        cmp #KW_FROM
        beq _from
        ldx #yield_ends_n - 1           ; nothing follows: None
-       cmp yield_ends,x
        beq _none
        dex
        bpl -
        jsr exprlist
        bra _emit
_none:  lda #R_NONE
        ldx #0
        jsr emit_const
_emit:  lda #OP_YIELD_VALUE
        jsr emit
_done:  lda #$ff                        ; (not an assignment target)
        sta c_last_op+1
        rts
_from:  jsr lex
        jsr expr
        lda #OP_GET_ITER
        jsr emit
        lda #R_NONE                     ; the first value sent
        ldx #0
        jsr emit_const
        jsr c_here                      ; the loop top
        pha
        phx
        ldy #OP_SEND
        jsr emit_jump
        sta yf_exit
        stx yf_exit+1
        lda #OP_YIELD_VALUE             ; (what it yields; what is sent comes back)
        jsr emit
        plx
        pla
        ldy #OP_JUMP
        jsr emit_op_word
        lda yf_exit                     ; the exit: its result is on the stack
        ldx yf_exit+1
        jsr patch_here
        bra _done
yield_ends:     .byte TK_NEWLINE, TK_SEMI, TK_EOF, TK_RPAREN, TK_RBRACK, TK_RBRACE
yield_ends_n = * - yield_ends

; function_body - after a def's name ('(' next) or after 'lambda' (Y = 1).
; A/X = the name ref, fb_sym = the name's symbol. Emits the defaults, MAKE_FUNCTION,
; the store of the name (def), and the body (jumped over).
fb_sym:         .word 0
fb_tmp:         .byte 0
function_body:
        sty fb_tmp
        pha
        phx
        ; the class a method belongs to (for super()): the enclosing scope's SC_CLASS
        ; (a class scope holds its own symbol there)
        ldy #SC_CLASS
        lda (sc),y
        sta t6
        iny
        lda (sc),y
        sta t6+1
        lda #SK_FUNC
        jsr scope_push
        ldy #SC_CLASS
        lda t6
        sta (sc),y
        iny
        lda t6+1
        sta (sc),y
        lda fb_ndeco                    ; (taken now: a lambda in a default is not ours)
        ldy #SC_NDECO
        sta (sc),y
        lda #0
        sta fb_ndeco
        ldy #FB_NAME+1
        pla
        sta (sc),y
        dey
        pla
        sta (sc),y
        ldy #FB_SYM
        lda fb_sym
        sta (sc),y
        iny
        lda fb_sym+1
        sta (sc),y
        ldy #SC_FLAGS
        lda fb_tmp
        sta (sc),y
        bne _param
        lda #TK_LPAREN
        jsr expect
_param: ldy #SC_FLAGS
        lda (sc),y
        beq +
        lda tok                         ; lambda: the parameters end at ':'
        cmp #TK_COLON
        beq _pend
        bra ++
+       lda tok
        cmp #TK_RPAREN
        beq _pend
+       ldy #SC_FFLAGS                  ; nothing after **kwargs
        lda (sc),y
        and #FF_VARKW
        beq +
        jsr syntax_error
        .text "arguments cannot follow **kwargs", 0
+       lda tok
        cmp #TK_STAR
        bne _nstar
        jsr fb_posend                   ; '*' / '*name': the rest are keyword-only
        jsr lex
        lda tok
        cmp #TK_NAME
        bne _next                       ; (a bare '*')
        lda #FF_VARARGS
        jsr fb_vparam
        bra _next
_nstar: cmp #TK_POW
        bne _nds
        jsr fb_posend                   ; '**name'
        jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda #FF_VARKW
        jsr fb_vparam
        bra _next
_nds:   cmp #TK_NAME
        beq +
        jmp c_syntax
+       jsr fb_pname
        ldy #SC_NPOS                    ; after '*': keyword-only (default or NULL)
        lda (sc),y
        beq _dflt
        ldy #SC_NKWONLY
        lda (sc),y
        inc a
        sta (sc),y
        lda #TK_ASSIGN
        jsr accept
        bcc +
        jsr sc_outer
        jsr expr
        jsr sc_inner
        bra _next
+       lda #0                          ; required: NULL
        tax
        jsr emit_const
        bra _next
_dflt:  lda #TK_ASSIGN
        jsr accept
        bcc _nodef
        jsr sc_outer                    ; defaults are evaluated in the enclosing scope
        jsr expr
        jsr sc_inner
        ldy #FB_NDEF
        lda (sc),y
        inc a
        sta (sc),y
        bra _next
_nodef: ldy #FB_NDEF
        lda (sc),y
        beq _next
        jsr syntax_error
        .text "non-default argument follows default argument", 0
_next:  lda #TK_COMMA
        jsr accept
        bcs _param
_pend:  ldy #SC_FLAGS
        lda (sc),y
        bne _ndef
        lda #TK_RPAREN
        jsr expect
        lda #TK_ARROW
        jsr accept
        bcc _ndef
        jsr sc_outer
        jsr discard_expr
        jsr sc_inner
_ndef:  jsr fb_defaults                 ; the defaults tuple (unless '*' built it)
        ldy #SC_NKWONLY                 ; the keyword-only defaults tuple
        lda (sc),y
        beq +
        ldy #OP_BUILD_TUPLE
        ldx #0
        jsr emit_op_word
+       jsr params_tuple
        ldy #FB_PARAMS
        sta (sc),y
        iny
        txa
        sta (sc),y
        ldy #SC_NLOCALS                 ; parameters (for the prologue)
        lda (sc),y
        ldy #SC_NARGS
        sta (sc),y
        sta fb_tmp                      ; positional ones (MAKE_FUNCTION's nargs)
        ldy #SC_NPOS
        lda (sc),y
        beq +
        dec a
        sta fb_tmp
+
        ; a def: pre-scan the body for the names it assigns (and those nested functions
        ; use); a lambda: only for those
        ldy #SC_FLAGS
        lda (sc),y
        beq +
        jsr lambda_scan
        bra _cells
+       lda tok
        cmp #TK_COLON
        beq +
        jmp c_syntax
+       lda fb_tmp
        pha
        jsr lx_push
        jsr lex
        lda #1
        sta lx_scan
        jsr prescan
        lda #0
        sta lx_scan
        jsr lx_pop
        pla
        sta fb_tmp
        lda ps_yield                    ; a yield: a generator function
        beq _cells
        ldy #SC_FFLAGS
        lda (sc),y
        ora #FF_GEN
        sta (sc),y
_cells: jsr fb_cells
        ; MAKE_FUNCTION code nargs nlocals name ndefaults params
        lda #1
        sta c_made_func
        lda #OP_MAKE_FUNCTION

        jsr emit
        jsr c_here
        ldy #FB_PATCH
        sta (sc),y
        iny
        txa
        sta (sc),y
        lda #0
        tax
        jsr emit_word
        lda fb_tmp
        jsr emit
        ldy #SC_NLOCALS
        lda (sc),y
        jsr emit
        ldy #FB_NAME
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr emit_word
        ldy #FB_NDEF
        lda (sc),y
        jsr emit
        ldy #FB_PARAMS
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr emit_word
        ldy #SC_FFLAGS                  ; *args / **kwargs, keyword-only parameters
        lda (sc),y
        and #FF_VARARGS | FF_VARKW | FF_GEN
        jsr emit
        ldy #SC_NKWONLY
        lda (sc),y
        jsr emit
        jsr fb_outer_env                ; made where there is an environment: keep it
        bcc +
        lda #OP_SET_CLOSURE
        jsr emit
+       ; a def stores the function (decorated) under its name, in the enclosing scope
        ldy #SC_FLAGS
        lda (sc),y
        bne +
        ldy #SC_NDECO
        lda (sc),y
        jsr emit_deco_calls
        ldy #FB_SYM
        lda (sc),y
        sta fb_sym
        iny
        lda (sc),y
        sta fb_sym+1
        jsr sc_outer
        lda fb_sym
        ldx fb_sym+1
        jsr emit_store_sym
        jsr sc_inner
+       ; jump over the body
        ldy #OP_JUMP
        jsr emit_jump
        ldy #FB_JUMP
        sta (sc),y
        iny
        txa
        sta (sc),y
        ldy #FB_PATCH
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr patch_here
        ; the body
        jsr fb_prologue
        ldy #SC_FLAGS
        lda (sc),y
        bne _lambda
        jsr block
        lda #R_NONE
        ldx #0
        jsr emit_const
        bra _ret
_lambda:
        lda #TK_COLON
        jsr expect
        jsr expr
_ret:   lda #OP_RETURN
        jsr emit
        ldy #FB_JUMP
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr patch_here
        jmp scope_pop

;---------------------------------------------------------------------------------------
; parameters: positional (with defaults), *args, keyword-only (each with its default or
; NULL), **kwargs; their locals are in that order (args.asm binds them)
;---------------------------------------------------------------------------------------
; fb_pname - tok = a parameter name: make it a local; skip an annotation (def)
fb_pname:
        lda tok_sym
        ldx tok_sym+1
        jsr local_add
        jsr lex
        ldy #SC_FLAGS
        lda (sc),y
        bne +
        lda #TK_COLON
        jsr accept
        bcc +
        jsr sc_outer
        jsr discard_expr
        jsr sc_inner
+       rts

; fb_vparam - A = FF_VARARGS / FF_VARKW, tok = its name
fb_vparam:
        ldy #SC_FFLAGS
        ora (sc),y
        sta (sc),y
        jmp fb_pname

; fb_posend - (at '*' or '**') the positional parameters end here: their defaults tuple
; is built now, before any keyword-only defaults. A second '*' is an error.
fb_posend:
        ldy #SC_NPOS
        lda (sc),y
        beq +
        lda tok
        cmp #TK_POW
        beq fb_rts
        jsr syntax_error
        .text "only one * is allowed", 0
+       ldy #SC_NLOCALS
        lda (sc),y
        inc a
        ldy #SC_NPOS
        sta (sc),y
; fb_defaults - BUILD_TUPLE of the positional defaults, once
fb_defaults:
        ldy #SC_FFLAGS
        lda (sc),y
        bmi fb_rts                      ; (FF_DEFS: built)
        ora #FF_DEFS
        sta (sc),y
        ldy #FB_NDEF
        lda (sc),y
        beq fb_rts
        ldy #OP_BUILD_TUPLE
        ldx #0
        jmp emit_op_word
fb_rts: rts

;---------------------------------------------------------------------------------------
; closures (env.asm has the runtime side)
;---------------------------------------------------------------------------------------
; fb_cells - (after the pre-scan) the locals used in nested functions become cells;
; a function with cells, or inside another function, gets the environment as its last
; local (frame offset 0: nothing is added after it)
fb_cells:
        ldy #SC_NLOCALS
        lda (sc),y
        sta t3
        lda #0
        sta t4                          ; cells so far
        ldx #0
-       cpx t3
        bcs _done
        txa
        asl
        clc
        adc #SC_LOCALS
        tay
        lda (sc),y
        sta t0
        iny
        lda (sc),y
        sta t0+1
        phx
        jsr ps_inner_has
        plx
        lda #0
        bcs +
        inc t4
        lda t4
+       pha
        txa
        clc
        adc #SC_CELLMAP
        tay
        pla
        sta (sc),y
        inx
        bra -
_done:  lda t4
        ldy #SC_NCELLS
        sta (sc),y
        bne _env
        jsr fb_enclosed
        bcc _rts
_env:   lda #<_text
        ldx #>_text
        jsr intern_cstr
        jsr local_add
        lda #1
        ldy #SC_ENV
        sta (sc),y
_rts:   rts
_text:  .text " env", 0

; fb_enclosed - C set if a function scope encloses the current one
fb_enclosed:
        ldx scope_depth
        dex
-       dex
        bmi _no
        phx
        txa
        jsr sc_at
        jsr scope_kind
        plx
        cmp #SK_FUNC
        bne -
        jsr sc_inner
        sec
        rts
_no:    jsr sc_inner
        clc
        rts

; fb_outer_env - C set if the code around the current function (past class bodies)
; runs in a frame with an environment
fb_outer_env:
        ldx scope_depth
        dex
-       dex
        bmi _no
        phx
        txa
        jsr sc_at
        jsr scope_kind
        plx
        cmp #SK_CLASS
        beq -
        cmp #SK_FUNC
        bne _no
        ldy #SC_ENV
        lda (sc),y
        beq _no
        jsr sc_inner
        sec
        rts
_no:    jsr sc_inner
        clc
        rts

; fb_prologue - (at the body's start) ENTER_ENV, and the parameters that are cells
; into their cells
fb_prologue:
        ldy #SC_ENV
        lda (sc),y
        beq _rts
        ldy #SC_NCELLS
        lda (sc),y
        ldy #OP_ENTER_ENV
        jsr emit_op_byte
        ldx #0
-       txa
        ldy #SC_NARGS
        cmp (sc),y
        bcs _rts
        phx
        tay
        jsr rn_cell                     ; Y = the parameter -> A = cell + 1
        beq _next
        dec a
        pha
        jsr local_offset
        ldy #OP_LOAD_FAST
        jsr emit_op_byte
        pla
        tax
        lda #0                          ; depth 0
        ldy #OP_STORE_DEREF
        jsr emit_op_word
_next:  plx
        inx
        bra -
_rts:   rts

; lambda_scan - (tok = the ':' of a lambda) note the names after a nested lambda in
; its body, to the end of the expression (a ',' or closing bracket at depth 0, or the
; end of the line); the lexer state is restored
ls_brk:         .byte 0
ls_seen:        .byte 0
lambda_scan:
        jsr ps_inner_reset
        lda #0
        sta ls_brk
        sta ls_seen
        jsr lx_push
        lda #1
        sta lx_scan
_lex:   jsr lex
        lda tok
        cmp #TK_EOF
        beq _end
        cmp #TK_NEWLINE
        beq _end
        cmp #TK_SEMI
        beq _end
        cmp #TK_LPAREN
        beq _open
        cmp #TK_LBRACK
        beq _open
        cmp #TK_LBRACE
        beq _open
        cmp #TK_RPAREN
        beq _close
        cmp #TK_RBRACK
        beq _close
        cmp #TK_RBRACE
        beq _close
        cmp #TK_COMMA
        bne +
        lda ls_brk
        beq _end
        bra _lex
+       cmp #KW_LAMBDA
        bne +
        sta ls_seen
        bra _lex
+       cmp #KW_FOR                     ; a generator expression (or a comprehension)
        bne +                           ; uses the parameters: make them all cells
        lda ls_brk
        beq _lex
        sta ps_allcells
        bra _lex
+       cmp #TK_NAME
        bne _lex
        lda ls_seen
        beq _lex
        jsr ps_inner_tok
        bra _lex
_open:  inc ls_brk
        bra _lex
_close: lda ls_brk
        beq _end
        dec ls_brk
        bra _lex
_end:   lda #0
        sta lx_scan
        jmp lx_pop

; params_tuple - a perm tuple of the current scope's local names (the parameters)
params_tuple:
        ldy #SC_NLOCALS
        lda (sc),y
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        lda p0
        sta t5
        lda p0+1
        sta t5+1
        lda #0
        sta t3
-       lda t3
        cmp nitems
        bcs +
        asl
        clc
        adc #SC_LOCALS
        tay
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr sym_name
        pha
        lda t5
        sta p0
        lda t5+1
        sta p0+1
        lda t3
        asl
        clc
        adc #6
        taz
        pla
        sta [p0],z
        inz
        txa
        sta [p0],z
        inc t3
        bra -
+       lda t5
        ldx t5+1
        rts

; discard_expr - compile an expression (annotation) and drop its code
discard_expr:
        jsr c_here
        pha
        phx
        jsr expr
        plx
        pla
        sta cp
        stx cp+1
        rts

;---------------------------------------------------------------------------------------
; prescan - from the token after a def's ':' through its body: every name that is
; assigned (=, augmented, for, as, import, def, class, :=) becomes a local of sc,
; unless declared global or nonlocal. Nested def/class bodies are skipped, but the
; names in them, and in lambdas, are noted (ps_inner): fb_cells makes those locals
; cells. (A nested function's own variable of the same name makes an unneeded cell:
; slower, not wrong.)
;---------------------------------------------------------------------------------------
ps_level:       .byte 0                 ; indentation depth inside the body
ps_brk:         .byte 0                 ; bracket depth
ps_start:       .byte 0                 ; at the start of a statement / target list
ps_lastc:       .byte 0                 ; the last token was a candidate name
ps_infor:       .byte 0
ps_ncand:       .byte 0
ps_annot:       .byte 0
ps_cand:        .fill 16
ps_last:        .word 0                 ; last name seen
ps_single:      .byte 0                 ; one-line body (ends at NEWLINE)
ps_wcount:      .byte 0                 ; with statements seen
ps_lam:         .byte 0                 ; in a lambda (to the end of the statement)
ps_yield:       .byte 0                 ; the body has a yield (not 0)
; generator expressions are functions of their own: the names in them must be cells.
; Names inside brackets wait in ps_pend until it is clear whether a 'for' makes their
; '(' group a generator expression (then they, and the group's later names, go to
; ps_inner)
PS_PEND_N       = 24
ps_bkind:       .fill 16                ; the bracket opened at each depth
ps_pend:        .fill 2 * PS_PEND_N
ps_npend:       .byte 0
ps_pover:       .byte 0                 ; ps_pend overflowed
ps_gdepth:      .byte 0                 ; inside a generator expression at this depth (0: no)

; ps_gname - (a name in the body) note it for the generator expressions
ps_gname:
        lda ps_gdepth
        beq +
        jmp ps_inner_tok
+       lda ps_brk
        beq _done
        ldx ps_npend
        cpx #PS_PEND_N
        bcc +
        sta ps_pover
        rts
+       inc ps_npend
        txa
        asl
        tax
        lda tok_sym
        sta ps_pend,x
        lda tok_sym+1
        sta ps_pend+1,x
_done:  rts

; ps_gfor - a 'for': in a '(' group it is a generator expression
ps_gfor:
        lda ps_gdepth
        bne _done
        ldx ps_brk
        beq _done
        cpx #16
        bcs _done
        lda ps_bkind,x
        cmp #TK_LPAREN
        bne _done
        stx ps_gdepth
        lda ps_pover
        beq +
        sta ps_allcells
+       ldx #0
-       cpx ps_npend
        bcs _done
        phx
        txa
        asl
        tay
        lda ps_pend,y
        ldx ps_pend+1,y
        jsr ps_inner_add
        plx
        inx
        bra -
_done:  rts
PS_INNER_N      = 64
ps_ninner:      .byte 0
ps_allcells:    .byte 0                 ; ps_inner overflowed: every local is a cell
ps_inner:       .fill 2 * PS_INNER_N    ; names used in nested functions

; ps_inner_tok - note tok_sym as used in a nested function
ps_inner_tok:
        lda tok_sym
        ldx tok_sym+1
; ps_inner_add - note A/X
ps_inner_add:
        sta t0
        stx t0+1
        jsr ps_inner_has
        bcc _done
        ldx ps_ninner
        cpx #PS_INNER_N
        bcc +
        lda #1
        sta ps_allcells
        rts
+       inc ps_ninner
        txa
        asl
        tax
        lda t0
        sta ps_inner,x
        lda t0+1
        sta ps_inner+1,x
_done:  rts

; ps_inner_has - is t0 a noted name? -> C clear if so (or if every local is a cell)
ps_inner_has:
        lda ps_allcells
        bne _yes
        ldx #0
-       cpx ps_ninner
        bcs _no
        txa
        asl
        tay
        lda ps_inner,y
        cmp t0
        bne +
        lda ps_inner+1,y
        cmp t0+1
        beq _yes
+       inx
        bra -
_yes:   clc
        rts
_no:    sec
        rts

; ps_inner_reset - before a pre-scan
ps_inner_reset:
        lda #0
        sta ps_ninner
        sta ps_allcells
        sta ps_lam
        rts

prescan:
        jsr ps_inner_reset
        lda #0
        sta ps_yield
        sta ps_npend
        sta ps_pover
        sta ps_gdepth
        sta ps_wcount
        sta ps_level
        sta ps_brk
        sta ps_ncand
        sta ps_infor
        sta ps_annot
        lda #1
        sta ps_start
        sta ps_single
        lda tok
        cmp #TK_NEWLINE
        bne _loop
        lda #0
        sta ps_single
        jsr lex                         ; INDENT
        lda tok
        cmp #TK_INDENT
        beq +
        rts
+       jsr lex
_loop:  lda tok
        cmp #TK_EOF
        bne +
        rts
+       ; a candidate name followed by something that makes it not a target
        lda ps_lastc
        beq _tok
        lda #0
        sta ps_lastc
        lda tok
        cmp #TK_COMMA
        beq _tok
        cmp #TK_ASSIGN
        beq _tok
        cmp #TK_COLON
        beq _tok
        cmp #TK_AUG
        bcc +
        cmp #TK_AUG+12
        bcc _tok
+       dec ps_ncand                    ; drop it
_tok:   lda tok
        cmp #TK_NAME
        bne _notname
        jsr ps_gname
        lda ps_lam
        beq +
        jsr ps_inner_tok                ; (a name in a lambda)
+       lda tok_sym
        sta ps_last
        lda tok_sym+1
        sta ps_last+1
        lda ps_infor
        beq +
        jsr ps_local
        jmp _next
+       lda ps_annot
        bne _cont
        lda ps_brk
        bne _cont
        lda ps_start
        beq _cont
        ldx ps_ncand
        cpx #8
        bcs _cont
        txa
        asl
        tax
        lda tok_sym
        sta ps_cand,x
        lda tok_sym+1
        sta ps_cand+1,x
        inc ps_ncand
        lda #1
        sta ps_lastc
        lda #0
        sta ps_start
_cont:  jmp _next
_notname:
        cmp #TK_LPAREN
        beq _open
        cmp #TK_LBRACK
        beq _open
        cmp #TK_LBRACE
        beq _open
        cmp #TK_RPAREN
        beq _close
        cmp #TK_RBRACK
        beq _close
        cmp #TK_RBRACE
        beq _close
        cmp #TK_COMMA
        beq _comma
        cmp #TK_ASSIGN
        beq _assign
        cmp #TK_WALRUS
        beq _walrus
        cmp #TK_COLON
        beq _colon
        cmp #TK_NEWLINE
        beq _nl
        cmp #TK_SEMI
        beq _stmt
        cmp #TK_INDENT
        beq _indent
        cmp #TK_DEDENT
        beq _dedent
        cmp #KW_FOR
        beq _for
        cmp #KW_IN
        beq _in
        cmp #KW_GLOBAL
        bne +
        jmp _global
+       cmp #KW_NONLOCAL
        bne +
        jmp _nonloc
+       cmp #KW_LAMBDA
        bne +
        lda #1
        sta ps_lam
        jmp _next
+       cmp #KW_YIELD                   ; the function is a generator
        bne +
        sta ps_yield
        jmp _next
+       cmp #KW_DEF
        bne +
        jmp _def
+       cmp #KW_CLASS
        bne +
        jmp _def
+       cmp #KW_IMPORT
        bne +
        jmp _import
+       cmp #KW_AS
        bne +
        jmp _as
+       cmp #KW_WITH
        bne +
        jsr ps_wvar
        jsr ps_wcommas                  ; 'with a, b:': one for each
        jmp _next
+       cmp #TK_AUG
        bcc _other
        cmp #TK_AUG+12
        bcs _other
        jsr ps_mark
        lda #0
        sta ps_start
        jmp _next
_other: lda #0
        sta ps_start
        jmp _next
_open:  inc ps_brk
        ldx ps_brk
        cpx #16
        bcs +
        lda tok
        sta ps_bkind,x
+       lda #0
        sta ps_start
        jmp _next
_close: lda ps_brk
        beq +
        dec ps_brk
        lda ps_brk
        cmp ps_gdepth                   ; out of a generator expression
        bcs +
        lda #0
        sta ps_gdepth
+       lda ps_brk
        bne +
        sta ps_npend                    ; (no brackets open: nothing pending)
        sta ps_pover
+       jmp _next
_comma: lda ps_brk
        bne +
        lda ps_ncand
        beq +
        lda #1
        sta ps_start
+       jmp _next
_assign:
        lda ps_brk
        bne +
        jsr ps_mark
        lda #0
        sta ps_annot
        lda #1
        sta ps_start
+       jmp _next
_walrus:
        lda ps_last
        ldx ps_last+1
        jsr local_add
        jmp _next
_colon: lda ps_brk
        bne _cn
        lda ps_ncand                    ; "name: annotation" keeps the name
        beq +
        lda #1
        sta ps_annot
        jmp _next
+       lda #1
        sta ps_start
_cn:    jmp _next
_nl:    lda ps_single
        beq _stmt
        rts                             ; a one-line body ends here
_stmt:  lda #0
        sta ps_ncand
        sta ps_annot
        sta ps_infor
        sta ps_lam
        lda #1
        sta ps_start
        jmp _next
_indent:
        inc ps_level
        bra _stmt
_dedent:
        lda ps_level
        bne +
        rts                             ; the end of the body
+       dec ps_level
        bra _stmt
_for:   jsr ps_gfor
        lda #1
        sta ps_infor
        jmp _next
_in:    lda #0
        sta ps_infor
        jmp _next
_global:
-       jsr lex
        lda tok
        cmp #TK_NAME
        bne +
        lda tok_sym
        ldx tok_sym+1
        jsr global_add
        bra -
+       cmp #TK_COMMA
        beq -
        jmp _loop
_nonloc:
-       jsr lex
        lda tok
        cmp #TK_NAME
        bne +
        lda tok_sym
        ldx tok_sym+1
        jsr nonlocal_add
        bra -
+       cmp #TK_COMMA
        beq -
        jmp _loop
_def:   jsr lex                         ; the name
        lda tok
        cmp #TK_NAME
        bne +
        jsr ps_local
+       ; skip to the ':' at bracket depth 0
        lda #0
        sta ps_brk
-       jsr lex
        jsr ps_note
        cmp #TK_EOF
        beq _ret
        cmp #TK_LPAREN
        bne +
        inc ps_brk
+       cmp #TK_RPAREN
        bne +
        dec ps_brk
+       cmp #TK_COLON
        bne -
        lda ps_brk
        bne -
        ; the nested body
        jsr lex
        lda tok
        cmp #TK_NEWLINE
        bne _skipline
        jsr lex                         ; INDENT
        ldx #0
-       jsr ps_note
        cmp #TK_EOF
        beq _ret
        cmp #TK_INDENT
        bne +
        inx
+       cmp #TK_DEDENT
        bne +
        dex
        beq _skipped
+       phx
        jsr lex
        plx
        bra -
_skipped:
        jsr lex
        jmp _stmt_loop
_skipline:
-       jsr ps_note
        cmp #TK_NEWLINE
        beq +
        cmp #TK_EOF
        beq _ret
        jsr lex
        bra -
+       jmp _nl
_ret:   rts
_stmt_loop:
        lda #0
        sta ps_ncand
        lda #1
        sta ps_start
        jmp _loop
_import:
-       jsr lex
        lda tok
        cmp #TK_NAME
        bne +
        jsr ps_local
        bra -
+       cmp #TK_COMMA
        beq -
        cmp #TK_DOT
        bne +
        jsr lex                         ; a.b: skip b
        bra -
+       cmp #KW_AS
        beq -
        jmp _loop
_as:    jsr lex
        lda tok
        cmp #TK_NAME
        bne +
        jsr ps_local
        jmp _next
+       jmp _loop
_next:  jsr lex
        jmp _loop

ps_local:
        lda tok_sym
        ldx tok_sym+1
        jmp local_add

; ps_wvar - a with block's hidden variable is a local
ps_wvar:
        lda ps_wcount
        inc ps_wcount
        jsr with_sym
        jmp local_add
; ps_wcommas - (at 'with') a hidden variable for each further manager: the commas up
; to the ':', outside brackets (the lexer comes back)
ps_wcommas:
        jsr lx_push
        ldx #0
_lex:   phx
        jsr lex
        plx
        lda tok
        cmp #TK_EOF
        beq _done
        cmp #TK_NEWLINE
        beq _done
        cpx #0
        bne _depth
        cmp #TK_COLON
        beq _done
        cmp #TK_COMMA
        bne _depth
        phx
        jsr ps_wvar
        plx
        bra _lex
_depth: lda tok
        jsr ge_depth
        bra _lex
_done:  jmp lx_pop

; ps_note - (inside a nested def/class) note the token if it is a name -> A = tok;
; keeps X
ps_note:
        lda tok
        cmp #TK_NAME
        bne +
        phx
        jsr ps_inner_tok
        plx
        lda tok
+       rts

; mark the candidates local
ps_mark:
        ldx #0
-       cpx ps_ncand
        bcs +
        phx
        txa
        asl
        tay
        lda ps_cand,y
        ldx ps_cand+1,y
        jsr local_add
        plx
        inx
        bra -
+       lda #0
        sta ps_ncand
        rts

;---------------------------------------------------------------------------------------
; simple statements
;---------------------------------------------------------------------------------------
st_return:
        jsr scope_kind
        cmp #SK_FUNC
        beq +
        jsr syntax_error
        .text "'return' outside function", 0
+       jsr lex
        lda tok
        cmp #TK_NEWLINE
        beq _none
        cmp #TK_SEMI
        beq _none
        cmp #TK_EOF
        beq _none
        jsr exprlist
        bra +
_none:  lda #R_NONE
        ldx #0
        jsr emit_const
+       lda #0                          ; leave this function's blocks (finally,
        jsr xb_exits                    ; __exit__), the value on the stack
        lda #OP_RETURN
        jmp emit

st_global:
-       jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       jsr scope_kind
        cmp #SK_FUNC
        bne +
        lda tok_sym
        ldx tok_sym+1
        jsr global_add
+       jsr lex
        lda tok
        cmp #TK_COMMA
        beq -
        rts

; nonlocal names: (the pre-scan declared them) each must be a variable of an enclosing
; function (resolve_name raises SyntaxError if not)
st_nonlocal:
        jsr scope_kind
        cmp #SK_FUNC
        beq +
        jsr syntax_error
        .text "nonlocal declaration not allowed here", 0
-
+       jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        ldx tok_sym+1
        jsr nonlocal_add
        lda tok_sym
        ldx tok_sym+1
        jsr resolve_name
        jsr lex
        lda tok
        cmp #TK_COMMA
        beq -
        rts

st_del:
        jsr lex
_one:   jsr bitor_expr
        jsr last_load
        bcc +
        jsr syntax_error
        .text "cannot delete this", 0
+       cmp #OP_LOAD_DEREF
        bne +
        jsr syntax_error
        .text "cannot delete a variable a nested function uses", 0
+       cmp #OP_LOAD_CLASSNAME
        bne +
        jsr syntax_error
        .text "cannot delete a class attribute in its class body", 0
+       pha
        jsr drop_last
        pla
        cmp #OP_LOAD_FAST
        bne +
        ldy #OP_DELETE_FAST
        lda t6
        jsr emit_op_byte
        bra _next
+       cmp #OP_LOAD_GLOBAL
        bne +
        ldy #OP_DELETE_GLOBAL
        bra _word
+       cmp #OP_LOAD_ATTR
        bne +
        ldy #OP_DELETE_ATTR
_word:  lda t6
        ldx t6+1
        jsr emit_op_word
        bra _next
+       lda #OP_DELETE_SUBSCR
        jsr emit
_next:  lda #TK_COMMA
        jsr accept
        bcs _one
        rts

st_raise:
        jsr lex
        lda tok
        cmp #TK_NEWLINE
        beq _bare
        cmp #TK_SEMI
        beq _bare
        cmp #TK_EOF
        beq _bare
        jsr expr
        lda #KW_FROM                    ; raise X from Y: Y is evaluated and dropped
        jsr accept
        bcc +
        jsr expr
        lda #OP_POP
        jsr emit
+       ldy #OP_RAISE
        lda #1
        jmp emit_op_byte
_bare:  ldy #OP_RAISE
        lda #0
        jmp emit_op_byte

st_assert:
        jsr lex
        jsr expr
        ldy #OP_JUMP_IF_TRUE
        jsr emit_jump
        pha
        phx
        lda #TK_COMMA
        jsr accept
        bcc +
        jsr expr
        ldy #OP_ASSERT_FAIL
        lda #1
        jsr emit_op_byte
        bra ++
+       ldy #OP_ASSERT_FAIL
        lda #0
        jsr emit_op_byte
+       plx
        pla
        jmp patch_here

; import a [as b], c
st_import:
-       jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        sta t6
        lda tok_sym+1
        sta t6+1
        ldy #OP_IMPORT
        lda t6
        ldx t6+1
        jsr emit_op_word
        jsr lex
        lda #KW_AS
        jsr accept
        bcc +
        lda tok
        cmp #TK_NAME
        beq ++
        jmp c_syntax
+       lda t6
        ldx t6+1
        jsr emit_store_sym
        bra _more
+       lda tok_sym
        ldx tok_sym+1
        jsr emit_store_sym
        jsr lex
_more:  lda tok
        cmp #TK_COMMA
        beq -
        rts

; from m import a [as b], c   |   from m import *
st_from:
        jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       ldy #OP_IMPORT
        lda tok_sym
        ldx tok_sym+1
        jsr emit_op_word
        jsr lex
        lda #KW_IMPORT
        jsr expect
        lda tok
        cmp #TK_STAR
        bne _names
        jsr syntax_error
        .text "'from module import *' is not supported yet", 0
_names: lda #OP_DUP
        jsr emit
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        sta t6
        lda tok_sym+1
        sta t6+1
        ldy #OP_LOAD_ATTR
        lda tok_ref
        ldx tok_ref+1
        jsr emit_op_word
        jsr lex
        lda #KW_AS
        jsr accept
        bcc +
        lda tok_sym
        sta t6
        lda tok_sym+1
        sta t6+1
        jsr lex
+       lda t6
        ldx t6+1
        jsr emit_store_sym
        lda #TK_COMMA
        jsr accept
        bcs _names
        lda #OP_POP
        jmp emit

;---------------------------------------------------------------------------------------
; expression statements and assignments
;---------------------------------------------------------------------------------------
st_expr:
        jsr cut_mark
        pha
        phx
        lda tg_top
        pha                             ; CPU: [cut mark][target mark]
        jsr target_or_exprlist          ; -> se_n elements, se_tuple
        lda tok
        cmp #TK_ASSIGN
        beq _assign
        cmp #TK_AUG
        bcc _expr
        cmp #TK_AUG+12
        bcs _expr
        jmp _aug
_expr:  pla
        pla
        pla
        lda c_repl                      ; the REPL prints expression statements
        beq +
        jsr scope_kind
        bne +
        lda #OP_PRINT_EXPR
        jmp emit
+       lda #OP_POP
        jmp emit
_assign:
        lda se_n                        ; one plain target: store in place
        cmp #1
        bne _multi
        lda se_tuple
        bne _multi
        jsr try_group_target            ; (a, b) = ... / [a, b] = ...
        bcs +
        jmp _nextv
+       jsr last_load
        bcc +
        jmp bad_target
+       jsr store_for_load
        pha
        lda t6
        pha
        lda t6+1
        pha                             ; CPU: [cut][tg][op][operand]
        lda el_start
        pha
        lda el_start+1
        pha                             ; ... [start of the first target]
        jsr drop_last
        jsr lex
        jsr target_or_exprlist          ; the value (or the next target)
        pla
        sta ch_start+1
        pla
        sta ch_start
        pla
        sta t6+1
        pla
        sta t6
        pla
        ldy tok
        cpy #TK_ASSIGN
        beq _chain
        jsr emit_store_op
        pla
        pla
        pla
        rts
_chain: ; a = b = ...: the first target becomes a saved target too (its prefix code
        ; is cut after the next targets', so the targets are stored left to right)
        sta ch_op
        lda t6
        sta ch_operand
        lda t6+1
        sta ch_operand+1
        lda #1
        jsr tg_alloc
        lda t5
        sta ch_idx
        jsr save_elements_as_targets
        lda ch_start
        ldx ch_start+1
        jsr cut_code
        sta t2
        stx t2+1
        lda ch_operand
        sta t6
        lda ch_operand+1
        sta t6+1
        ldx ch_idx
        ldy #0
        lda ch_op
        jsr tg_set
        jmp _nextv
_multi: jsr save_elements_as_targets
+
_nextv: jsr lex                         ; past '='
        jsr target_or_exprlist
        lda tok
        cmp #TK_ASSIGN
        beq _multi
        ; the value is on the stack: store it into every target, left to right
        pla
        sta se_mark
        pha
        jsr store_saved_targets
        pla
        jsr tg_release
        plx
        pla
        jmp cut_release
_aug:   pla
        pla
        pla
        lda se_n
        cmp #1
        beq +
        jmp bad_target
+       lda se_tuple
        beq +
        jmp bad_target
+       jsr last_load
        bcc +
        jmp bad_target
+       sta se_op
        cmp #OP_LOAD_SUBSCR             ; obj key -> obj key obj key -> obj key val
        bne +
        jsr drop_last
        lda #OP_DUP2
        jsr emit
        lda #OP_LOAD_SUBSCR
        jsr emit
        bra _rhs
+       cmp #OP_LOAD_ATTR               ; obj -> obj obj -> obj val
        bne _rhs
        jsr drop_last
        lda #OP_DUP
        jsr emit
        ldy #OP_LOAD_ATTR
        lda t6
        ldx t6+1
        jsr emit_op_word
_rhs:   lda tok
        sec
        sbc #TK_AUG
        pha
        lda t6
        pha
        lda t6+1
        pha
        lda se_op
        pha
        jsr lex
        jsr exprlist
        pla
        sta se_op
        pla
        sta t6+1
        pla
        sta t6
        pla
        bne +                           ; += uses the in-place add
        lda #OP_IADD
        bra ++
+       clc
        adc #OP_ADD
+       jsr emit
        lda se_op
        jsr store_for_load
        jmp emit_store_op

bad_target:
        jsr syntax_error
        .text "cannot assign to this expression", 0

se_n:           .byte 0
se_tuple:       .byte 0
se_op:          .byte 0
se_mark:        .byte 0
se_first:       .byte 0
ch_start:       .word 0
ch_op:          .byte 0
ch_operand:     .word 0
ch_idx:         .byte 0

;---------------------------------------------------------------------------------------
; assignment targets
;
; target_or_exprlist parses "a, b[i], c.d" recording where each element starts and
; its last load, so the elements can become targets. Only statements use it (they do
; not nest), so el_* need no saving.
;---------------------------------------------------------------------------------------
EL_MAX          = 8
el_start:       .fill 2*EL_MAX
el_last:        .fill 2*EL_MAX
el_n:           .byte 0

; -> se_n = number of elements; se_tuple = 1 if it is a tuple (comma)
target_or_exprlist:
        lda #0
        sta el_n
        sta el_star
        sta se_tuple
_elem:  lda el_n
        cmp #EL_MAX
        bcc +
        jsr syntax_error
        .text "too many items", 0
+       asl
        tax
        lda cp
        sta el_start,x
        lda cp+1
        sta el_start+1,x
        lda #$ff                        ; no load yet
        sta c_last_op+1
        lda tok
        cmp #TK_STAR
        bne _expr
        jsr ux_scan                     ; a, *b = ...: a starred target
        bcs _star
        lda el_n                        ; x = a, *b: one tuple
        ldy #7
        jsr ds_rest
        lda #1
        sta se_n
        lda #0
        sta se_tuple
        rts
_star:  lda el_star
        beq +
        jsr syntax_error
        .text "multiple starred expressions in assignment", 0
+       ldx el_n
        inx
        stx el_star
        jsr lex
        lda #$ff
        sta c_last_op+1
_expr:  jsr expr
        lda el_n
        asl
        tax
        lda c_last_op
        sta el_last,x
        lda c_last_op+1
        sta el_last+1,x
        inc el_n
        lda tok
        cmp #TK_COMMA
        bne _end
        lda #1
        sta se_tuple
        jsr lex
        jsr at_expr_end
        bcc _elem
_end:   lda el_n
        sta se_n
        lda se_tuple
        beq +
        ldy #OP_BUILD_TUPLE
        lda el_n
        ldx #0
        jsr emit_op_word
+       rts

; at_expr_end -> C set if the current token cannot start an expression
at_expr_end:
        lda tok
        cmp #TK_NEWLINE
        beq _yes
        cmp #TK_ASSIGN
        beq _yes
        cmp #TK_RPAREN
        beq _yes
        cmp #TK_RBRACK
        beq _yes
        cmp #TK_RBRACE
        beq _yes
        cmp #TK_COLON
        beq _yes
        cmp #TK_SEMI
        beq _yes
        cmp #TK_EOF
        beq _yes
        cmp #KW_IN
        beq _yes
        cmp #TK_AUG
        bcc +
        cmp #TK_AUG+12
        bcc _yes
+       clc
        rts
_yes:   sec
        rts

; exprlist - an expression or a comma-separated tuple of them
exprlist:
        lda tok                         ; *a, b
        cmp #TK_STAR
        bne +
        lda #0
        ldy #7
        jmp ds_rest
+       jsr expr
        lda tok
        cmp #TK_COMMA
        bne +
        jmp tuple_rest
+       rts

; The target table (TARGETS, a stack): +0 cut handle of the prefix code (0 = none),
; +2 store opcode, +3 operand, +5 tuple group size (0 = a single target)
tg_mark:
        lda tg_top
        rts
tg_release:
        sta tg_top
        rts

; tg_entry - X = index -> t0 = address of the entry
tg_entry:
        txa
        asl
        asl
        asl
        clc
        adc #<TARGETS
        sta t0
        lda #>TARGETS
        adc #0
        sta t0+1
        rts

; tg_alloc - A = number of entries -> t5 = the first one
tg_alloc:
        sta t1
        lda tg_top
        sta t5
        clc
        adc t1
        cmp #TARGETS_N+1
        bcc +
        jmp bad_target
+       sta tg_top
        rts

; tg_set - X = entry: handle t2, store op A, operand t6, group size Y
tg_set: pha
        phy
        jsr tg_entry
        ldy #0
        lda t2
        sta (t0),y
        iny
        lda t2+1
        sta (t0),y
        iny
        ply
        pla
        phy
        ldy #2
        sta (t0),y
        iny
        lda t6
        sta (t0),y
        iny
        lda t6+1
        sta (t0),y
        iny
        pla
        sta (t0),y
        iny                             ; +6: entries the group spans (= its size here)
        sta (t0),y
        iny                             ; +7: its starred item + 1 (0: none)
        lda #0
        sta (t0),y
        rts

; tg_add_noprefix - A = store op, t6 = operand: a single target
tg_add_noprefix:
        pha
        lda #1
        jsr tg_alloc
        lda #0
        sta t2
        sta t2+1
        ldx t5
        ldy #0
        pla
        jmp tg_set

; save_elements_as_targets - the el_* elements just parsed become targets: each one's
; prefix code is cut away (last element first, so the offsets stay valid)
save_elements_as_targets:
        lda se_tuple                    ; drop the BUILD_TUPLE
        beq +
        sec
        lda cp
        sbc #3
        sta cp
        lda cp+1
        sbc #0
        sta cp+1
+       lda el_n
        jsr tg_alloc
        lda t5
        sta se_first
        ldx el_n
_each:  dex
        bmi _done
        phx
        txa
        asl
        tax
        lda el_last,x
        sta c_last_op
        lda el_last+1,x
        sta c_last_op+1
        lda el_start,x
        pha
        lda el_start+1,x
        pha
        jsr last_load                   ; it must end the code here and be a load
        bcc +
        jmp bad_target
+       jsr store_for_load
        sta se_op
        jsr drop_last
        pla                             ; the element's start
        tax
        pla
        jsr cut_code                    ; the prefix (maybe empty) -> cut stack
        sta t2
        stx t2+1
        plx                             ; element index
        phx
        txa
        clc
        adc se_first
        tax
        ldy #0
        lda se_tuple
        beq +
        ldy el_n
+       lda se_op
        jsr tg_set
        plx
        bra _each
_done:  lda el_star                     ; a, *b = ...: the group's starred item
        beq +
        ldx se_first
        jsr tg_entry
        ldy #7
        lda el_star
        sta (t0),y
+       rts
el_star:        .byte 0                 ; target_or_exprlist: the starred element + 1

; try_group_target - the single element parsed is "(a, b)" / "[a, b]": loads of names
; then BUILD_TUPLE/BUILD_LIST n. Make the names one target group and drop the code.
; C clear if done, C set (nothing changed) if the element is something else.
try_group_target:
        sec
        lda cp
        sbc #3
        sta t3
        lda cp+1
        sbc #0
        sta t3+1                        ; where a BUILD would be
        ldz #0
        lda t3
        ldx t3+1
        jsr code_peek
        cmp #OP_BUILD_TUPLE
        beq +
        cmp #OP_BUILD_LIST
        beq +
_no:    sec
        rts
+       ldz #1
        lda t3
        ldx t3+1
        jsr code_peek
        sta tgg_n
        cmp #EL_MAX+1
        bcs _no
        ldz #2
        lda t3
        ldx t3+1
        jsr code_peek
        bne _no
        ; pass 1: n name loads, ending exactly at the BUILD
        jsr _walk_start
        ldx tgg_n
-       beq +
        jsr _load
        bcs _no
        dex
        bra -
+       lda tgg_pos
        cmp t3
        bne _no
        lda tgg_pos+1
        cmp t3+1
        bne _no
        ; pass 2: the targets
        lda tgg_n
        jsr tg_alloc
        lda t5
        sta se_first
        jsr _walk_start
        lda #0
        sta tgg_i
-       lda tgg_i
        cmp tgg_n
        bcs +
        jsr _load                       ; A = opcode, t6 = operand
        jsr store_for_load
        pha
        lda #0
        sta t2
        sta t2+1
        lda tgg_i
        clc
        adc se_first
        tax
        ldy tgg_n
        pla
        jsr tg_set
        inc tgg_i
        bra -
+       ldx #0                          ; drop the element's code
        lda el_start,x
        sta cp
        lda el_start+1,x
        sta cp+1
        clc
        rts
_walk_start:
        lda el_start
        sta tgg_pos
        lda el_start+1
        sta tgg_pos+1
        rts
; the load at tgg_pos -> A = opcode, t6 = operand, tgg_pos past it; C set if not a
; name load (X preserved)
_load:  phx
        ldz #0
        lda tgg_pos
        ldx tgg_pos+1
        jsr code_peek
        sta tgg_op
        ldz #1
        lda tgg_pos
        ldx tgg_pos+1
        jsr code_peek
        sta t6
        lda #0
        sta t6+1
        lda tgg_op
        cmp #OP_LOAD_FAST
        beq _fast
        cmp #OP_LOAD_DEREF
        beq +
        cmp #OP_LOAD_CLASSNAME
        beq +
        cmp #OP_LOAD_GLOBAL
        bne _bad
+
        ldz #2
        lda tgg_pos
        ldx tgg_pos+1
        jsr code_peek
        sta t6+1
        lda #3
        bra _adv
_fast:  lda #2
_adv:   clc
        adc tgg_pos
        sta tgg_pos
        bcc +
        inc tgg_pos+1
+       plx
        lda tgg_op
        clc
        rts
_bad:   plx
        sec
        rts
tgg_n:          .byte 0
tgg_i:          .byte 0
tgg_op:         .byte 0
tgg_pos:        .word 0

; ux_emit - A = the starred item + 1 of a group of t3 targets: UNPACK_EX before, after
ux_emit:
        dec a
        pha                             ; before
        ldy #OP_UNPACK_EX
        jsr emit_op_byte
        pla
        eor #$ff                        ; after = t3 - before - 1
        sec
        adc t3
        sec
        sbc #1
        jmp emit

; ux_scan - (at a '*' in an element list) is this an assignment target list? -> C set
; if an '=' follows outside brackets before the statement ends (the lexer comes back)
ux_scan:
        jsr lx_push
        lda #1
        sta lx_scan
        ldx #0
_lex:   phx
        jsr lex
        plx
        lda tok
        cmp #TK_SEMI
        beq _no
        cpx #0
        bne +
        cmp #TK_ASSIGN
        beq _yes
        cmp #TK_COLON
        beq _no
+       jsr ge_depth
        bcc _lex
_no:    clc
        bra +
_yes:   sec
+       php
        jsr lx_pop
        lda #0
        sta ge_seen
        plp
        rts

; store_saved_targets - the value is TOS: store it into every target from se_mark up
store_saved_targets:
        ldx se_mark
_loop:  cpx tg_top
        bcc +
        rts
+       jsr tg_entry
        ldy #5
        lda (t0),y                      ; group size (0 = a single target)
        beq _single
        sta t3
        phx
        ldy #6
        txa                             ; DUP unless this group is the last
        clc
        adc (t0),y
        cmp tg_top
        beq +
        lda #OP_DUP
        jsr emit
+       plx                             ; a starred item: UNPACK_EX first
        phx
        jsr tg_entry
        ldy #7
        lda (t0),y
        beq +
        jsr ux_emit
+       ldy #OP_UNPACK
        lda t3
        jsr emit_op_byte
        plx
-       lda t3                          ; the items in order (item 0 is on top)
        beq _loop
        jsr tg_entry
        ldy #2
        lda (t0),y
        cmp #OP_UNPACK                  ; a nested group: UNPACK m, then its m names
        beq _nest
        phx
        lda t3
        pha
        jsr tg_store_one
        pla
        sta t3
        plx
        inx
        dec t3
        bra -
_nest:  ldy #3
        lda (t0),y
        pha                             ; m
        ldy #OP_UNPACK
        jsr emit_op_byte
        inx
        pla
-       pha
        phx
        lda t3
        pha
        jsr tg_store_one
        pla
        sta t3
        plx
        inx
        pla
        dec a
        bne -
        dec t3
        bra --
_single:
        phx
        inx
        cpx tg_top
        beq +
        lda #OP_DUP
        jsr emit
+       plx
        phx
        jsr tg_store_one
        plx
        inx
        bra _loop

; tg_store_one - X = entry: store TOS there (pasting its prefix code first)
tg_store_one:
        jsr tg_entry
        ldy #0
        lda (t0),y
        sta t2
        iny
        lda (t0),y
        sta t2+1
        iny
        lda (t0),y
        sta se_op
        iny
        lda (t0),y
        sta t6
        iny
        lda (t0),y
        sta t6+1
        lda t2
        ora t2+1
        beq _store
        lda t2
        ldx t2+1
        jsr cut_len
        beq _store
        lda t6
        pha
        lda t6+1
        pha
        lda se_op
        pha
        lda t2
        ldx t2+1
        jsr paste_code
        pla
        sta se_op
        ldy #OP_LIFT3                   ; val obj key -> obj key val
        cmp #OP_STORE_SUBSCR
        beq +
        ldy #OP_ROT2                    ; val obj -> obj val
+       tya
        jsr emit
        pla
        sta t6+1
        pla
        sta t6
_store: lda se_op
        jmp emit_store_op

; cut_len - A/X = handle -> Z set if the cut code is empty
cut_len:
        sta fp0
        stx fp0+1
        lda cut_top+2
        sta fp0+2
        lda cut_top+3
        sta fp0+3
        ldz #2
        lda [fp0],z
        inz
        ora [fp0],z
        rts

; target_list - for-loop / comprehension targets: "a", "a, b" or "(a, b)" (names)
; -> A = the target mark (pass it to store_targets)
target_list:
        lda tg_top
        pha
        lda #0
        sta tl_count                    ; items
        sta tl_comma                    ; comma seen
        sta tl_star                     ; the starred item + 1
        lda #TK_LPAREN
        jsr accept
        lda #0
        rol
        pha                             ; parenthesised?
_name:  lda tok
        cmp #TK_LPAREN
        bne _plain
        ; a nested group "(m, n)": a marker entry (UNPACK m), then the names
        jsr lex
        lda tl_count
        pha
        lda #1
        jsr tg_alloc
        lda t5
        pha                             ; the marker's index
        lda #0
        sta t2
        sta t2+1
        sta t6
        sta t6+1
        ldx t5
        ldy #0
        lda #OP_UNPACK
        jsr tg_set
        lda #0
        pha                             ; m
_inner: lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        ldx tok_sym+1
        jsr store_op_for_sym
        pha
        lda #1
        jsr tg_alloc
        lda #0
        sta t2
        sta t2+1
        ldx t5
        ldy #0
        pla
        jsr tg_set
        pla
        inc a
        pha
        jsr lex
        lda #TK_COMMA
        jsr accept
        lda tok
        cmp #TK_NAME
        beq _inner
        lda #TK_RPAREN
        jsr expect
        pla                             ; m -> the marker's operand
        sta t6
        plx
        jsr tg_entry
        ldy #3
        lda t6
        sta (t0),y
        pla
        sta tl_count
        inc tl_count
        bra _after
_plain: cmp #TK_STAR                    ; for a, *b in ...
        bne _pname
        lda tl_star
        beq +
        jsr syntax_error
        .text "multiple starred expressions in assignment", 0
+       ldx tl_count
        inx
        stx tl_star
        jsr lex
        lda tok
_pname: cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        ldx tok_sym+1
        jsr store_op_for_sym
        pha
        lda tl_count
        pha
        lda #1
        jsr tg_alloc
        pla
        sta tl_count
        lda #0
        sta t2
        sta t2+1
        ldx t5
        ldy #0
        pla
        jsr tg_set
        inc tl_count
        jsr lex
_after: lda tok
        cmp #TK_COMMA
        bne _end
        inc tl_comma
        jsr lex
        lda tok
        cmp #TK_NAME
        beq _name
        cmp #TK_LPAREN
        beq _name
        cmp #TK_STAR
        beq _name
_end:   pla
        beq +
        lda #TK_RPAREN
        jsr expect
+       pla                             ; the mark
        pha
        ldx tl_comma
        beq +
        ; a tuple: every entry gets the group size
        tax
        ldy tl_count
-       phx
        phy
        jsr tg_entry
        pla
        pha
        ldy #5
        lda tl_count
        sta (t0),y
        ply
        plx
        inx
        dey
        bne -
+       pla
        pha
        tax
        jsr tg_entry
        sec
        lda tg_top
        tsx                             ; (16-bit SP: re-read the mark)
        pla
        pha
        sta tl_mark
        lda tg_top
        sec
        sbc tl_mark
        ldy #6
        sta (t0),y
        iny                             ; +7: the starred item + 1
        lda tl_star
        sta (t0),y
        pla
        rts

tl_mark:        .byte 0
tl_count:       .byte 0
tl_comma:       .byte 0
tl_star:        .byte 0

; store_targets - A = mark from target_list: store TOS into those targets
store_targets:
        sta se_mark
        pha
        jsr store_saved_targets
        pla
        jmp tg_release

;---------------------------------------------------------------------------------------
; expressions
;---------------------------------------------------------------------------------------
; expr - conditional expressions and lambda
expr:
        jsr stack_check
        lda tok
        cmp #KW_LAMBDA
        bne +
        jmp lambda_expr
+       cmp #KW_YIELD
        bne +
        jmp yield_expr
+       jsr c_here
        pha
        phx
        jsr or_test
        lda tok
        cmp #KW_IF
        beq _cond
        pla
        pla
        rts
_cond:  ; x if c else y: x's code moves after the test
        plx
        pla
        jsr cut_code                    ; x -> the cut stack
        pha                             ; CPU: [handle]
        phx
        jsr lex
        jsr or_test                     ; c
        ldy #OP_JUMP_IF_FALSE
        jsr emit_jump
        pha                             ; CPU: [handle][false]
        phx
        lda #KW_ELSE
        jsr expect
        plx
        pla
        sta t2
        stx t2+1
        plx
        pla
        sta t3
        stx t3+1
        lda t3
        pha
        lda t3+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        lda t3
        ldx t3+1
        jsr paste_code                  ; x
        ldy #OP_JUMP
        jsr emit_jump
        sta t0
        stx t0+1
        plx
        pla
        jsr patch_here                  ; false -> y
        lda t0
        pha                             ; CPU: [handle][end]
        lda t0+1
        pha
        jsr expr                        ; y
        plx
        pla
        jsr patch_here
        plx
        pla
        jsr cut_release
        lda #$ff
        sta c_last_op+1
        rts

;---------------------------------------------------------------------------------------
or_test:
        jsr and_test
        lda tok
        cmp #KW_OR
        bne _done
        lda #0                          ; chain
        pha
        pha
-       lda #OP_JUMP_IF_TRUE_OR_POP
        jsr emit
        pla
        tax
        pla
        sta t0
        stx t0+1
        jsr c_here
        pha
        phx
        lda t0
        ldx t0+1
        jsr emit_word
        jsr lex
        jsr and_test
        lda tok
        cmp #KW_OR
        beq -
        plx
        pla
        jsr patch_chain
        lda #$ff
        sta c_last_op+1
_done:  rts

and_test:
        jsr not_test
        lda tok
        cmp #KW_AND
        bne _done
        lda #0
        pha
        pha
-       lda #OP_JUMP_IF_FALSE_OR_POP
        jsr emit
        pla
        tax
        pla
        sta t0
        stx t0+1
        jsr c_here
        pha
        phx
        lda t0
        ldx t0+1
        jsr emit_word
        jsr lex
        jsr not_test
        lda tok
        cmp #KW_AND
        beq -
        plx
        pla
        jsr patch_chain
        lda #$ff
        sta c_last_op+1
_done:  rts

not_test:
        lda tok
        cmp #KW_NOT
        bne comparison
        jsr lex
        jsr not_test
        lda #OP_NOT
        jsr emit
        lda #$ff
        sta c_last_op+1
        rts

; comparison operators: A = token -> A = opcode, C set if not a comparison.
; "not in" and "is not" consume their extra token.
cmp_op:
        lda tok
        cmp #TK_EQ
        bcc +
        cmp #TK_GE+1
        bcs +
        sec
        sbc #TK_EQ
        clc
        adc #OP_EQ
        pha
        jsr lex
        pla
        clc
        rts
+       cmp #KW_IN
        bne +
        lda c_noin
        bne _no
        jsr lex
        lda #OP_IN
        clc
        rts
+       cmp #KW_IS
        bne +
        jsr lex
        lda #KW_NOT
        jsr accept
        lda #OP_IS
        bcc _ok
        lda #OP_IS_NOT
_ok:    clc
        rts
+       cmp #KW_NOT
        bne _no
        ; "not in" (a lone "not" here is a syntax error later)
        jsr lex
        lda #KW_IN
        jsr expect
        lda #OP_NOT_IN
        clc
        rts
_no:    sec
        rts

comparison:
        jsr bitor_expr
        jsr cmp_op
        bcc +
        rts
+       pha                             ; the operator
        lda #0                          ; cleanup chain (0 = none)
        pha
        pha
_next:  jsr bitor_expr
        jsr cmp_op
        bcs _last
        ; chained: a op b op2 c -> DUP ROT3 op JUMP_IF_FALSE_OR_POP cleanup ...
        sta t3
        lda #OP_DUP
        jsr emit
        lda #OP_ROT3
        jsr emit
        pla
        sta t0+1
        pla
        sta t0
        pla                             ; the previous operator
        jsr emit
        lda t3
        pha
        lda #OP_JUMP_IF_FALSE_OR_POP
        jsr emit
        jsr c_here
        pha
        phx
        lda t0
        ldx t0+1
        jsr emit_word
        ; stack: [op2][chain]
        plx
        pla
        sta t0
        stx t0+1
        lda t0
        pha
        lda t0+1
        pha
        bra _next
_last:  pla
        sta t0+1
        pla
        sta t0
        pla
        jsr emit
        lda t0+1
        beq _done
        ; JUMP end; cleanup: ROT2 POP; end:
        ldy #OP_JUMP
        jsr emit_jump
        pha
        phx
        lda t0
        ldx t0+1
        jsr patch_chain
        lda #OP_ROT2
        jsr emit
        lda #OP_POP
        jsr emit
        plx
        pla
        jsr patch_here
_done:  lda #$ff
        sta c_last_op+1
        rts

; binary operators by precedence climbing: A = minimum precedence
bin_prec:
        ; tok -> A = precedence (0 = not a binary operator)
        lda tok
        cmp #TK_PLUS
        bcc _no
        cmp #TK_CARET+1
        bcs _no
        tax
        lda prec_tab-TK_PLUS,x
        rts
_no:    lda #0
        rts
prec_tab:       ; + - * / // % ** << >> & | ^
        .byte 5, 5, 6, 6, 6, 6, 0, 4, 4, 3, 1, 2

bitor_expr:
        lda #1
binary:
        pha
        jsr unary
_loop:  jsr bin_prec
        beq _done
        sta t3
        pla
        pha
        cmp t3
        beq +
        bcs _done                       ; min > prec
+       lda tok
        pha
        lda t3
        pha
        jsr lex
        pla
        inc a
        jsr binary
        pla
        sec
        sbc #TK_PLUS
        clc
        adc #OP_ADD
        jsr emit
        lda #$ff
        sta c_last_op+1
        bra _loop
_done:  pla
        rts

unary:
        lda tok
        cmp #TK_MINUS
        beq _neg
        cmp #TK_PLUS
        beq _pos
        cmp #TK_TILDE
        beq _inv
        jmp power
_neg:   jsr lex
        ; -<number literal>: fold (but not -2 ** 2, which is -(2 ** 2))
        jsr peek_pow
        bcs _nofold
        lda tok
        cmp #TK_FLOAT
        bne +
        lda tok_ref
        ldx tok_ref+1
        jsr float_load
        lda fdbl+7
        eor #$80
        sta fdbl+7
        jsr float_new_dbl
        sta tok_ref
        stx tok_ref+1
        jmp power
+       cmp #TK_INT
        bne _nofold
        lda tok_num
        sta acc
        lda tok_num+1
        sta acc+1
        lda tok_num+2
        sta acc+2
        lda tok_num+3
        sta acc+3
        jsr acc_neg
        ldx #3
-       lda acc,x
        sta tok_num,x
        dex
        bpl -
        jmp power
_nofold:
        jsr unary
        lda #OP_NEG
        bra _emit
_pos:   jsr lex
        jsr unary
        lda #OP_POS
        bra _emit
_inv:   jsr lex
        jsr unary
        lda #OP_INVERT
_emit:  jsr emit
        lda #$ff
        sta c_last_op+1
        rts

; peek_pow - C set if the source after the current token starts with ** (after spaces)
peek_pow:
        ldz #0
-       lda [lx_ptr],z
        cmp #' '
        bne +
        inz
        bra -
+       cmp #'*'
        bne _no
        inz
        lda [lx_ptr],z
        cmp #'*'
        bne _no
        sec
        rts
_no:    clc
        rts

power:
        jsr primary
        lda tok
        cmp #TK_POW
        bne +
        jsr lex
        jsr unary
        lda #OP_POW
        jsr emit
        lda #$ff
        sta c_last_op+1
+       rts

; primary - an atom with its trailers: .name, (args), [subscript]
primary:
        jsr atom
_trail: lda tok
        cmp #TK_DOT
        beq _attr
        cmp #TK_LPAREN
        beq _call
        cmp #TK_LBRACK
        beq _sub
        rts
_attr:  jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       jsr c_here
        sta c_last_op
        stx c_last_op+1
        ldy #OP_LOAD_ATTR
        lda tok_ref
        ldx tok_ref+1
        jsr emit_op_word
        jsr lex
        lda tok
        cmp #TK_LPAREN
        bne _trail
        ; obj.name( : a method call
        lda c_last_op
        ldx c_last_op+1
        sta cpat
        stx cpat+1
        lda #CODE_BANK
        sta cpat+2
        lda #0
        sta cpat+3
        ldz #0
        lda #OP_LOAD_METHOD
        sta [cpat],z
        jsr call_args                   ; -> A = argc, Y = 0 / 1 (ca_kw) / 2 (* or **)
        cpy #2
        bne +
        lda #1                          ; CALL_EX for a method
        bra _ex
+       cpy #0
        bne +
        ldy #OP_CALL_METHOD
        jsr emit_op_byte
        bra _called
+       pha
        lda #OP_CALL_METHOD_KW
        bra _kw
_call:  jsr call_args
        cpy #2
        bne +
        lda #0
_ex:    ldy #OP_CALL_EX                 ; then drop the names it leaves under the result
        jsr emit_op_byte
        lda #OP_ROT2
        jsr emit
        lda #OP_POP
        jsr emit
        bra _called
+       cpy #0
        bne +
        ldy #OP_CALL
        jsr emit_op_byte
        bra _called
+       pha
        lda #OP_CALL_KW
_kw:    jsr emit
        pla
        jsr emit
        lda ca_kw
        ldx ca_kw+1
        jsr emit_word
_called:
        lda #$ff
        sta c_last_op+1
        bra _trail
_sub:   jsr lex
        jsr subscript
        lda #TK_RBRACK
        jsr expect
        jsr c_here
        sta c_last_op
        stx c_last_op+1
        lda #OP_LOAD_SUBSCR
        jsr emit
        bra _trail

; subscript - an index or a slice [a:b:c]
subscript:
        lda tok
        cmp #TK_COLON
        beq _slice
        jsr expr_or_tuple
        lda tok
        cmp #TK_COLON
        beq _slice2
        rts
_slice: lda #R_NONE                     ; no start
        ldx #0
        jsr emit_const
_slice2:
        jsr lex                         ; past ':'
        lda tok
        cmp #TK_RBRACK
        beq _nostop
        cmp #TK_COLON
        beq _nostop
        jsr expr
        bra +
_nostop:
        lda #R_NONE
        ldx #0
        jsr emit_const
+       lda tok
        cmp #TK_COLON
        bne _two
        jsr lex
        lda tok
        cmp #TK_RBRACK
        beq _two
        jsr expr
        ldy #OP_BUILD_SLICE
        lda #3
        jmp emit_op_byte
_two:   ldy #OP_BUILD_SLICE
        lda #2
        jmp emit_op_byte

; expr_or_tuple - d[1, 2] style
expr_or_tuple:
        jsr expr
        lda tok
        cmp #TK_COMMA
        beq tuple_rest
        rts

; tuple_rest - one item compiled and tok = ',': the rest of a tuple, then BUILD_TUPLE
;---------------------------------------------------------------------------------------
; unpacking in displays: from the first *x (**m in a dict) on, the items go into a
; [list][dict] pair with EX_ARG, as a call's arguments do (args.asm); the last EX_ARG
; makes the list, tuple, set or dict
;---------------------------------------------------------------------------------------
; ds_rest - A = items compiled so far (on the stack), tok = the '*' of the next one,
; Y = 6 list / 7 tuple / 8 set: the rest of the display, to the token that ends it
ds_rest:
        phy
        ldy #OP_PACK_ARGS
        jsr emit_op_byte
        lda #0
        tax
        jsr emit_word
_item:  lda tok
        cmp #TK_STAR
        bne +
        jsr lex                         ; *iterable: its items
        jsr expr
        lda #1
        bra _ex
+       jsr expr
        lda #0
_ex:    ldy #OP_EX_ARG
        jsr emit_op_byte
        lda tok
        cmp #TK_COMMA
        bne _end
        jsr lex
        jsr at_expr_end
        bcc _item
_end:   pla
        ldy #OP_EX_ARG
        jsr emit_op_byte
        lda #$ff
        sta c_last_op+1
        rts

; dd_rest - the dict so far is on the stack, tok = '**' of the next item: the rest
; of the dict display (to the '}')
dd_rest:
        ldy #OP_BUILD_LIST              ; [list][dict]
        lda #0
        tax
        jsr emit_op_word
        lda #OP_ROT2
        jsr emit
_item:  lda tok
        cmp #TK_POW
        bne +
        jsr lex                         ; **mapping: its items
        jsr expr
        lda #5
        bra _ex
+       jsr expr                        ; key: value
        lda #TK_COLON
        jsr expect
        jsr expr
        lda #4
_ex:    ldy #OP_EX_ARG
        jsr emit_op_byte
        lda tok
        cmp #TK_COMMA
        bne _end
        jsr lex
        lda tok
        cmp #TK_RBRACE
        bne _item
_end:   lda #9
        ldy #OP_EX_ARG
        jmp emit_op_byte

tuple_rest:
        lda #1
-       pha
        jsr lex                         ; past ','
        jsr at_expr_end
        bcs +
        lda tok                         ; (a, *b): the rest unpacks
        cmp #TK_STAR
        bne _plain
        pla
        ldy #7
        jmp ds_rest
_plain: jsr expr
        pla
        inc a
        pha
        lda tok
        cmp #TK_COMMA
        beq _again
+       pla
        ldy #OP_BUILD_TUPLE
        ldx #0
        jmp emit_op_word
_again: pla
        bra -

; call_args - after '(' ... ')' -> Y = 0: A = argc; Y = 1: A = argc (the last ones
; keywords), ca_kw = their names tuple; Y = 2: a * or ** was used: the arguments are a
; list and a dict on the stack, for CALL_EX (the ones before the first * / ** were
; compiled plainly and packed by PACK_ARGS; each later one goes in with EX_ARG).
; Per call nesting level: ca_* [ca_d - 1]; the keyword names on the ca_names stack.
CA_DEPTH        = 16
CA_NAMES        = 64
ca_kw:          .word 0
ca_d:           .byte 0                 ; calls being compiled (nesting)
ca_argc:        .fill CA_DEPTH          ; plain arguments so far (keyword ones too)
ca_nkw:         .fill CA_DEPTH          ; plain keyword arguments so far
ca_ex:          .fill CA_DEPTH          ; 1: list and dict (after a * / **)
ca_kwseen:      .fill CA_DEPTH          ; a keyword argument or ** seen
ca_base:        .fill CA_DEPTH          ; its names start here on ca_names
ca_ntop:        .byte 0
ca_names:       .fill 2 * CA_NAMES
call_args:
        jsr lex                         ; past '('
        ldx ca_d
        cpx #CA_DEPTH
        bcc +
        jsr syntax_error
        .text "calls nested too deeply", 0
+       inc ca_d
        lda #0
        sta ca_argc,x
        sta ca_nkw,x
        sta ca_ex,x
        sta ca_kwseen,x
        lda ca_ntop
        sta ca_base,x
_arg:   lda tok
        cmp #TK_RPAREN
        bne +
        jmp _end
+       cmp #TK_STAR
        bne +
        jmp _star
+       cmp #TK_POW
        bne +
        jmp _dstar
+       cmp #TK_NAME
        bne _pos
        jsr lx_push                     ; name= ?
        jsr lex
        lda tok
        cmp #TK_ASSIGN
        bne _notkw
        jsr lx_pop                      ; back to the name
        jsr ca_x
        lda #1
        sta ca_kwseen,x
        lda ca_ex,x
        bne _exkw
        ldy ca_ntop                     ; a plain keyword: note its name
        cpy #CA_NAMES
        bcc +
        jsr syntax_error
        .text "too many keyword arguments", 0
+       tya
        asl a
        tay
        lda tok_ref
        sta ca_names,y
        lda tok_ref+1
        sta ca_names+1,y
        inc ca_ntop
        inc ca_nkw,x
        jsr lex                         ; name
        jsr lex                         ; =
        jsr expr
        jsr ca_count
        jmp _next
_exkw:  lda tok_ref                     ; after * / **: name and value into the dict
        ldx tok_ref+1
        jsr emit_const
        jsr lex
        jsr lex
        jsr expr
        lda #2
        jsr ca_exarg
        jmp _next
_notkw: jsr lx_pop
_pos:   jsr ca_x
        lda ca_kwseen,x
        beq +
        jsr syntax_error
        .text "positional argument follows keyword argument", 0
+       jsr lx_push                     ; (a generator expression compiles it again)
        jsr c_here
        pha
        phx
        jsr expr
        plx
        pla
        ldy tok
        cpy #KW_FOR                     ; f(x for x in y): a generator expression
        bne +
        jsr genexp
        bra ++
+       jsr lx_drop
+       jsr ca_x
        lda ca_ex,x
        beq +
        lda #0                          ; append
        jsr ca_exarg
        bra _next
+       jsr ca_count
        bra _next
_star:  jsr ca_enter_ex                 ; *iterable
        jsr lex
        jsr expr
        lda #1                          ; extend
        jsr ca_exarg
        bra _next
_dstar: jsr ca_enter_ex                 ; **mapping
        jsr ca_x
        lda #1
        sta ca_kwseen,x
        jsr lex
        jsr expr
        lda #3                          ; merge
        jsr ca_exarg
_next:  lda #TK_COMMA
        jsr accept
        bcc _end
        jmp _arg
_end:   lda #TK_RPAREN
        jsr expect
        jsr ca_x
        dec ca_d
        lda ca_ex,x
        beq +
        lda ca_base,x                   ; * / **: CALL_EX
        sta ca_ntop
        ldy #2
        rts
+       lda ca_argc,x
        pha
        lda ca_nkw,x
        bne +
        lda ca_base,x
        sta ca_ntop
        pla
        ldy #0
        rts
+       jsr ca_names_tuple              ; keywords: their names
        sta ca_kw
        stx ca_kw+1
        ldx ca_d                        ; (the level just left)
        lda ca_base,x
        sta ca_ntop
        pla
        ldy #1
        rts

; ca_x - X = the current call's level
ca_x:   ldx ca_d
        dex
        rts

; ca_count - one more plain argument (at most 16)
ca_count:
        jsr ca_x
        inc ca_argc,x
        lda ca_argc,x
        cmp #17
        bcc +
        jsr syntax_error
        .text "too many arguments", 0
+       rts

; ca_exarg - A = kind: EX_ARG kind
ca_exarg:
        ldy #OP_EX_ARG
        jmp emit_op_byte

; ca_enter_ex - (the first * or **) PACK_ARGS: the plain arguments so far become the list
; and the dict
ca_enter_ex:
        jsr ca_x
        lda ca_ex,x
        bne _done
        lda #1
        sta ca_ex,x
        lda #0
        sta t4
        sta t4+1
        lda ca_nkw,x
        beq +
        jsr ca_names_tuple
        sta t4
        stx t4+1
        jsr ca_x
        lda ca_base,x                   ; (the names are in the tuple now)
        sta ca_ntop
+       jsr ca_x
        sec
        lda ca_argc,x                   ; positional ones
        sbc ca_nkw,x
        pha
        lda #OP_PACK_ARGS
        jsr emit
        pla
        jsr emit
        lda t4
        ldx t4+1
        jmp emit_word
_done:  rts

; ca_names_tuple - X = a call level: its keyword names as a tuple -> A/X
ca_names_tuple:
        lda ca_nkw,x
        sta nitems
        lda #0
        sta nitems+1
        lda ca_base,x
        asl a
        pha
        jsr tuple_new
        plx
        ldz #6
-       cpx #2 * CA_NAMES
        bcs +
        txa
        lsr a
        cmp ca_ntop
        bcs +
        lda ca_names,x
        sta [p0],z
        inz
        lda ca_names+1,x
        sta [p0],z
        inz
        inx
        inx
        bra -
+       lda p0
        ldx p0+1
        rts

;---------------------------------------------------------------------------------------
; atoms
;---------------------------------------------------------------------------------------
atom:
        lda tok
        cmp #TK_NAME
        bne +
        jmp at_name
+       cmp #TK_INT
        bne +
        ldx #3
-       lda tok_num,x
        sta acc,x
        dex
        bpl -
        jsr int_new
        jsr emit_const
        jmp lex
+       cmp #TK_FLOAT
        bne +
        lda tok_ref
        ldx tok_ref+1
        jsr emit_const
        jmp lex
+       cmp #TK_STR
        bne +
        jmp at_string
+       cmp #TK_FSTR
        bne +
        jmp at_fstring
+       cmp #KW_NONE
        bne +
        lda #R_NONE
        bra _const
+       cmp #KW_TRUE
        bne +
        lda #R_TRUE
        bra _const
+       cmp #KW_FALSE
        bne +
        lda #R_FALSE
_const: ldx #0
        jsr emit_const
        lda #$ff
        sta c_last_op+1
        jmp lex
+       cmp #TK_LPAREN
        bne +
        jmp at_paren
+       cmp #TK_LBRACK
        bne +
        jmp at_list
+       cmp #TK_LBRACE
        bne +
        jmp at_dict
+       jmp c_syntax

at_name:
        ; super() inside a method
        lda tok_sym+1
        bne _plain
        lda tok_sym
        cmp #<S_SUPER
        bne _plain
        jsr scope_kind
        cmp #SK_FUNC
        bne _plain
        ldy #SC_CLASS+1
        lda (sc),y
        dey
        ora (sc),y
        beq _plain
        jsr lx_push
        jsr lex
        lda tok
        cmp #TK_LPAREN
        bne _undo
        jsr lex
        lda tok
        cmp #TK_RPAREN
        bne _undo
        jsr lx_drop
        jsr lex
        lda #OP_LOAD_SUPER
        jsr emit
        ldy #SC_CLASS
        lda (sc),y
        pha
        iny
        lda (sc),y
        tax
        pla
        jsr gsym
        jsr emit_word
        ldy #0                          ; self = local 0
        jsr local_offset
        jsr emit
        lda #$ff
        sta c_last_op+1
        rts
_undo:  jsr lx_pop
_plain: jsr emit_load_name
        jmp lex

; adjacent string literals are concatenated
at_string:
        lda tok_ref
        sta r2
        lda tok_ref+1
        sta r2+1
        jsr lex
        lda tok
        cmp #TK_STR
        bne _done
        lda sbp
        pha
        lda sbp+1
        pha
        lda r2
        ldx r2+1
        jsr sb_put_str
-       lda tok
        cmp #TK_STR
        bne +
        lda tok_ref
        ldx tok_ref+1
        jsr sb_put_str
        jsr lex
        bra -
+       plx
        pla
        jsr sb_take
        sta r2
        stx r2+1
_done:  lda r2
        ldx r2+1
        jsr emit_const
        lda #0
        sta r2
        sta r2+1
        lda #$ff
        sta c_last_op+1
        rts

; ( ) / (expr) / (a, b) / (x for x in y)
at_paren:
        jsr lex
        lda tok
        cmp #TK_RPAREN
        bne +
        ldy #OP_BUILD_TUPLE
        lda #0
        tax
        jsr emit_op_word
        jmp lex
+       lda c_noin
        pha
        lda #0
        sta c_noin
        lda tok                         ; (*a, b)
        cmp #TK_STAR
        bne +
        lda #0
        ldy #7
        jsr ds_rest
        bra _close
+       jsr walrus
        bcc _close
        jsr lx_push                     ; (a generator expression compiles it again)
        jsr c_here
        pha
        phx
        jsr expr
        plx
        pla
        ldy tok
        cpy #KW_FOR
        bne +
        jsr genexp
        bra _close
+       pha
        jsr lx_drop
        pla
        cpy #TK_COMMA
        bne _close
        jsr tuple_rest
_close: pla
        sta c_noin
        lda #TK_RPAREN
        jmp expect

; walrus - "name := expr" here? Then compile it (the value stays) -> C clear;
; C set (nothing consumed) otherwise
walrus:
        lda tok
        cmp #TK_NAME
        bne _no
        jsr lx_push
        lda tok_sym
        pha
        lda tok_sym+1
        pha
        jsr lex
        lda tok
        cmp #TK_WALRUS
        beq +
        pla
        pla
        jsr lx_pop
_no:    sec
        rts
+       jsr lx_drop
        jsr lex
        jsr expr
        lda #OP_DUP
        jsr emit
        plx
        pla
        jsr emit_store_sym
        lda #$ff
        sta c_last_op+1
        clc
        rts

; [ ] / [a, b] / [x for x in y]
at_list:
        jsr lex
        lda c_noin
        pha
        lda #0
        sta c_noin
        lda tok
        cmp #TK_RBRACK
        bne +
        ldy #OP_BUILD_LIST
        lda #0
        tax
        jsr emit_op_word
        bra _close
+       cmp #TK_STAR                    ; [*a, b]
        bne +
        lda #0
        bra _star
+       jsr c_here
        pha
        phx
        jsr expr
        plx
        pla
        ldy tok
        cpy #KW_FOR
        bne +
        ldy #0                          ; a list
        jsr comprehension
        bra _close
+       lda #1
-       pha
        lda tok
        cmp #TK_COMMA
        bne +
        jsr lex
        lda tok
        cmp #TK_RBRACK
        beq +
        cmp #TK_STAR
        beq _star1
        jsr expr
        pla
        inc a
        bne -
        jmp c_syntax
+       pla
        ldy #OP_BUILD_LIST
        ldx #0
        jsr emit_op_word
        bra _close
_star1: pla                             ; [a, *b]
_star:  ldy #6
        jsr ds_rest
_close: pla
        sta c_noin
        lda #$ff
        sta c_last_op+1
        lda #TK_RBRACK
        jmp expect
lc_start:       .word 0

; { } / {k: v, ...} / {k: v for ...}
at_dict:
        jsr lex
        lda c_noin
        pha
        lda #0
        sta c_noin
        lda tok
        cmp #TK_RBRACE
        bne +
        ldy #OP_BUILD_DICT
        lda #0
        tax
        jsr emit_op_word
        bra _close
+       cmp #TK_STAR                    ; {*a, b}
        bne +
        lda #0
        bra _sstar
+       cmp #TK_POW                     ; {**m, k: v}
        bne +
        lda #0
        bra _dstar
+       jsr c_here
        pha
        phx
        jsr expr
        lda tok
        cmp #TK_COLON
        beq _dict
        ; a set: {a, b} / {x for ...} - built as a list, then BUILD_SET makes it a set
        cmp #KW_FOR
        bne _set
        plx
        pla
        ldy #0
        jsr comprehension
        bra _toset
_set:   pla
        pla
        lda #1
-       pha
        lda tok
        cmp #TK_COMMA
        bne +
        jsr lex
        lda tok
        cmp #TK_RBRACE
        beq +
        cmp #TK_STAR
        beq _sstar1
        jsr expr
        pla
        inc a
        bne -
        jmp c_syntax
+       pla
        ldy #OP_BUILD_LIST
        ldx #0
        jsr emit_op_word
_toset: ldy #OP_BUILD_SET
        lda #0
        tax
        jsr emit_op_word
        bra _close
_dict:  jsr lex
        jsr expr
        lda tok
        cmp #KW_FOR
        bne +
        plx
        pla
        ldy #1                          ; a dict
        jsr comprehension
        bra _close
+       pla
        pla
        lda #1
-       pha
        lda tok
        cmp #TK_COMMA
        bne +
        jsr lex
        lda tok
        cmp #TK_RBRACE
        beq +
        cmp #TK_POW
        beq _dstar1
        jsr expr
        lda #TK_COLON
        jsr expect
        jsr expr
        pla
        inc a
        bne -
        jmp c_syntax
+       pla
        ldy #OP_BUILD_DICT
        ldx #0
        jsr emit_op_word
        bra _close
_sstar1:
        pla                             ; {a, *b}
_sstar: ldy #8
        jsr ds_rest
        bra _close
_dstar1:
        pla                             ; {k: v, **m}: the dict so far
_dstar: ldy #OP_BUILD_DICT
        ldx #0
        jsr emit_op_word
        jsr dd_rest
_close: pla
        sta c_noin
        lda #$ff
        sta c_last_op+1
        lda #TK_RBRACE
        jmp expect

; comprehension - A/X = element code start, Y = 0 list / 1 dict / 2 a generator
; expression's body (genexp); tok = 'for'
comprehension:
        sta t1
        stx t1+1
        sty t2
        lda cm_kind                     ; an enclosing comprehension's state
        pha
        lda cm_handle
        pha
        lda cm_handle+1
        pha
        lda t2
        sta cm_kind
        lda t1
        ldx t1+1
        jsr cut_code                    ; the element moves into the loop
        sta cm_handle
        stx cm_handle+1
        lda cm_kind
        cmp #2                          ; (a generator expression yields its items)
        beq _go
        ldy #OP_BUILD_LIST
        lda cm_kind
        beq +
        ldy #OP_BUILD_DICT
+       lda #0
        tax
        jsr emit_op_word
_go:    lda #0
        jsr comp_for                    ; depth 0
        lda cm_handle
        ldx cm_handle+1
        jsr cut_release
        pla
        sta cm_handle+1
        pla
        sta cm_handle
        pla
        sta cm_kind
        rts
cm_kind:        .byte 0

; comp_for - A = depth (iterators between the container and the value); tok = 'for'
comp_for:
        pha
        sta cf_depth
        jsr lex
        jsr target_list
        pha                             ; target mark
        lda #KW_IN
        jsr expect
        lda #1
        sta c_noin
        lda cm_kind                     ; a generator expression's first iterable was
        cmp #2                          ; evaluated outside: compile it away, iterate
        bne _iter                       ; over the parameter instead
        lda cf_depth
        bne _iter
        jsr c_here
        pha
        phx
        jsr or_test
        plx
        pla
        sta cp
        stx cp+1
        jsr ge_load_param
        bra _iterd
_iter:  jsr or_test
_iterd: lda #0
        sta c_noin
        lda #OP_GET_ITER
        jsr emit
        jsr c_here
        pha                             ; loop top
        phx
        ldy #OP_FOR_ITER
        jsr emit_jump
        sta t0
        stx t0+1
        ; CPU: [depth][mark][top] -> keep exit patch too
        plx
        pla
        sta t1
        stx t1+1
        pla                             ; mark
        tay
        lda t0
        pha
        lda t0+1
        pha
        lda t1
        pha
        lda t1+1
        pha
        tya
        jsr store_targets
        ; CPU: [depth][exit][top]
_ifs:   lda tok
        cmp #KW_IF
        bne _body
        jsr lex
        lda #0                          ; (a condition may use "in": [x for x in a if x in b])
        sta c_noin
        jsr or_test
        pla
        tax
        pla
        pha
        phx
        ldy #OP_JUMP_IF_FALSE
        jsr emit_op_word
        bra _ifs
_body:  lda tok
        cmp #KW_FOR
        bne _elt
        ; a nested for: one more iterator on the stack
        pla
        sta t1+1
        pla
        sta t1
        pla
        sta t0+1
        pla
        sta t0
        pla                             ; depth
        pha
        tay
        lda t0
        pha
        lda t0+1
        pha
        lda t1
        pha
        lda t1+1
        pha
        tya
        inc a
        jsr comp_for
        bra _back
_elt:   ; the element (cut earlier: the handle is just above our frames - use lc_handle)
        lda cm_handle
        ldx cm_handle+1
        jsr paste_code
        ; depth from the CPU stack
        pla
        sta t1+1
        pla
        sta t1
        pla
        sta t0+1
        pla
        sta t0
        pla
        pha
        tay
        lda t0
        pha
        lda t0+1
        pha
        lda t1
        pha
        lda t1+1
        pha
        tya
        inc a                           ; this level's iterator is on the stack too
        ldx cm_kind
        bne +
        ldy #OP_LIST_APPEND
        jsr emit_op_byte
        bra _back
+       cpx #2
        bne +
        lda #OP_YIELD_VALUE             ; a generator expression
        jsr emit
        lda #OP_POP
        jsr emit
        bra _back
+       ldy #OP_MAP_ADD
        jsr emit_op_byte
_back:  pla
        tax
        pla
        ldy #OP_JUMP
        jsr emit_op_word
        pla
        tax
        pla
        jsr patch_here
        pla
        rts
cm_handle:      .word 0
cf_depth:       .byte 0

;---------------------------------------------------------------------------------------
; f-strings: TK_FSTR has the raw text at tok_num (far pointer), length tok_sym
;---------------------------------------------------------------------------------------
fs_end:         .word 0
fs_n:           .byte 0
at_fstring:
        ldx #3
-       lda tok_num,x
        sta fs_p,x
        dex
        bpl -
        clc
        lda tok_num
        adc tok_sym
        sta fs_end
        lda tok_num+1
        adc tok_sym+1
        sta fs_end+1
        lda #0
        sta fs_n
        lda sbp
        pha
        lda sbp+1
        pha
_loop:  lda fs_p
        cmp fs_end
        bne +
        lda fs_p+1
        cmp fs_end+1
        bne +
        jmp _finish
+       ldz #0
        lda [fs_p],z
        cmp #'{'
        beq _open
        cmp #'}'
        beq _close
        cmp #'\'
        beq _esc
_lit:   jsr sb_putc
        inw fs_p
        bra _loop
_esc:   inw fs_p
        ldz #0
        lda [fs_p],z
        ldx #fs_esc_n-1
-       cmp fs_esc_in,x
        beq +
        dex
        bpl -
        pha
        lda #'\'
        jsr sb_putc
        pla
        bra _lit
+       lda fs_esc_out,x
        bra _lit
_close: inw fs_p
        ldz #0
        lda [fs_p],z
        cmp #'}'
        beq _lit
        jsr syntax_error
        .text "f-string: single '}' is not allowed", 0
_open:  inw fs_p
        ldz #0
        lda [fs_p],z
        cmp #'{'
        beq _lit
        ; flush the literal part
        jsr _flush
        ; compile the expression with the lexer pointed at it
        jsr lx_push
        ldx #3
-       lda fs_p,x
        sta lx_ptr,x
        dex
        bpl -
        lda #1
        sta lx_paren
        lda #0
        sta lx_bol
        lda fs_p
        pha
        lda fs_p+1
        pha
        lda fs_end
        pha
        lda fs_end+1
        pha
        lda fs_n
        pha
        jsr lex
        jsr expr
        pla
        sta fs_n
        pla
        sta fs_end+1
        pla
        sta fs_end
        pla
        sta fs_p+1
        pla
        sta fs_p
        ; conversion and spec
        lda #0
        sta t6                          ; 0 str / 1 repr
        lda #0
        sta r3
        sta r3+1
        lda tok
        cmp #TK_BANG
        bne _conv_done
        ldz #0                          ; !r / !s: the letter follows the '!'
        lda [lx_ptr],z
        cmp #'r'
        bne _conv_skip
        inc t6
_conv_skip:
        inw lx_ptr
        jsr lex
_conv_done:
        lda tok
        cmp #TK_COLON
        bne _nospec
        ; the spec: raw chars from lx_ptr up to '}'
        ldx #3
-       lda lx_ptr,x
        sta fp2,x
        dex
        bpl -
        ldz #0
-       lda [lx_ptr],z
        cmp #'}'
        beq +
        inz
        bne -
+       stz str_len
        lda #0
        sta str_len+1
        tza
        clc
        adc lx_ptr
        sta lx_ptr
        bcc +
        inc lx_ptr+1
+       lda t6
        pha
        jsr str_from_far
        sta r3
        stx r3+1
        pla
        sta t6
        jsr lex                         ; '}'
_nospec:
        lda tok
        cmp #TK_RBRACE
        beq +
        jsr syntax_error
        .text "f-string: expecting '}'", 0
+       ; the text continues after the '}': the lexer pointer is just past it
        ldx #3
-       lda lx_ptr,x
        sta fs_p,x
        dex
        bpl -
        jsr lx_pop
        ldy #OP_FORMAT
        lda t6
        jsr emit_op_byte
        lda r3
        ldx r3+1
        jsr emit_word
        lda #0
        sta r3
        sta r3+1
        inc fs_n
        ; the builder mark is still on the CPU stack: reset it as the new mark
        pla
        sta t0+1
        pla
        sta t0
        lda sbp
        pha
        lda sbp+1
        pha
        jmp _loop
_finish:
        jsr _flush
        pla
        pla
        lda fs_n
        bne +
        lda #0                          ; f"" -> ""
        sta str_len
        sta str_len+1
        jsr str_alloc
        jsr emit_const
        bra _done
+       cmp #1
        beq _done
        ldy #OP_BUILD_STRING
        ldx #0
        jsr emit_op_word
_done:  lda #$ff
        sta c_last_op+1
        jmp lex
; emit the literal collected since the mark (on the CPU stack under our return) as a
; CONST, and restart the builder there
_flush: pla
        sta t7
        pla
        sta t7+1
        pla
        sta t0+1
        pla
        sta t0
        lda sbp
        cmp t0
        bne +
        lda sbp+1
        cmp t0+1
        beq ++
+       lda t0
        ldx t0+1
        jsr sb_take
        jsr emit_const
        inc fs_n
+       lda t0
        pha
        lda t0+1
        pha
        lda t7+1
        pha
        lda t7
        pha
        rts
fs_esc_in:      .text "ntr\'", '"', "0"
fs_esc_n = * - fs_esc_in
fs_esc_out:     .byte 10, 9, 13, '\', "'", '"', 0

;---------------------------------------------------------------------------------------
st_class:
        lda fb_ndeco                    ; decorators (st_decorated), applied at the end
        pha
        lda #0
        sta fb_ndeco
        jsr lex
        lda tok
        cmp #TK_NAME
        beq +
        jmp c_syntax
+       lda tok_sym
        pha
        lda tok_sym+1
        pha
        lda tok_ref
        pha
        lda tok_ref+1
        pha
        jsr lex
        lda #TK_LPAREN
        jsr accept
        bcc _nobase
        lda tok
        cmp #TK_RPAREN
        beq +
        jsr expr
        lda #TK_RPAREN
        jsr expect
        bra _make
+       jsr lex
_nobase:
        lda #R_NONE
        ldx #0
        jsr emit_const
_make:  pla
        tax
        pla
        ldy #OP_MAKE_CLASS
        jsr emit_op_word
        lda #1
        sta c_made_func
        ; the body runs in class scope; SC_CLASS holds the class symbol (for super())
        lda #SK_CLASS
        jsr scope_push
        pla                             ; the class symbol (kept on the CPU stack)
        sta t0+1
        pla
        sta t0
        pha
        lda t0+1
        pha
        ldy #SC_CLASS
        lda t0
        sta (sc),y
        iny
        lda t0+1
        sta (sc),y
        jsr block
        lda #OP_END_CLASS
        jsr emit
        jsr scope_pop
        pla                             ; the class symbol
        sta t4+1
        pla
        sta t4
        pla                             ; the decorators
        jsr emit_deco_calls
        lda t4
        ldx t4+1
        jmp emit_store_sym
