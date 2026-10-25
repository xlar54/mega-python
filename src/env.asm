;=======================================================================================
; Closures (overlay R): the variables a function shares with the functions nested in it.
;
; The compiler finds a function's cell variables (its locals that nested functions use)
; before compiling its body. A call of a function that has some makes an environment:
; a tuple of (parent environment, cell 0, cell 1, ...); the parent is the function's
; closure, the environment of the frame it was made in (MAKE_FUNCTION, SET_CLOSURE).
; A function without cells uses its closure as its environment. The environment lives
; in the function's last local (frame offset 0), so it needs no operand:
;   ENTER_ENV n        prologue: the environment (n cells: a new one; 0: the closure)
;   LOAD_DEREF d, c    cell c of the environment d parents up
;   STORE_DEREF d, c
;   SET_CLOSURE        func -> func: it keeps the frame's environment
; A class body runs in its function's frame, so it reaches the same environment.
;=======================================================================================

op_load_deref:
        jsr env_cell
        lda [p1],z
        pha
        inz
        lda [p1],z
        tax
        pla
        cpx #0
        bne +
        cmp #0
        bne +
        #RAISE EXC_NAME, "cannot access free variable where it is not associated with a value"
+       #PUSH
        jmp vm_loop

op_store_deref:
        jsr env_cell
        #POP                            ; (keeps Z)
        sta [p1],z
        inz
        txa
        sta [p1],z
        jmp vm_loop

; env_cell - the operands (depth, cell) -> p1 = that environment, Z = the cell's offset
env_cell:
        #FETCHB
        sta t0
        #FETCHB
        sta t1
        ldy #0                          ; the frame's environment (its last local)
        lda (vfp),y
        sta p1
        iny
        lda (vfp),y
        sta p1+1
        ldx t0
-       cpx #0
        beq +
        ldz #6                          ; parent (item 0)
        lda [p1],z
        pha
        inz
        lda [p1],z
        sta p1+1
        pla
        sta p1
        dex
        bra -
+       lda t1                          ; cell c = item c + 1
        asl a
        clc
        adc #8
        taz
        rts

op_enter_env:
        #FETCHB                         ; cells
        pha
        lda c_func                      ; (still the function being entered)
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #14
        lda [p0],z
        sta t2
        inz
        lda [p0],z
        sta t2+1
        pla
        beq _store                      ; no cells: the closure is the environment
        clc
        adc #1
        sta nitems
        lda #0
        sta nitems+1
        lda t2                          ; (allocating clobbers the t registers)
        pha
        lda t2+1
        pha
        jsr tuple_new                   ; zeroed: the cells start unbound
        pla
        ldz #7
        sta [p0],z
        pla
        dez
        sta [p0],z
        lda p0
        sta t2
        lda p0+1
        sta t2+1
_store: ldy #0
        lda t2
        sta (vfp),y
        iny
        lda t2+1
        sta (vfp),y
        jmp vm_loop

op_set_closure:
        #PEEK 0
        sta p0
        stx p0+1
        ldy #0
        lda (vfp),y
        ldz #14
        sta [p0],z
        iny
        lda (vfp),y
        inz
        sta [p0],z
        jmp vm_loop
