;=======================================================================================
; Classes, tail M: the bases of a new class and its method resolution order (MRO);
; a class's __mro__ and __bases__.
;
; A class keeps its first base at +6. When that chain of +6 bases is not the whole MRO
; (several bases, or a base that has several), +10 holds the MRO as a tuple, the class
; itself first and object left out, and +12 the tuple of its bases. Lookups follow +10
; when it is set, else the +6 chain (class_lookup, isinstance_r2_r3).
;=======================================================================================
cm_n:           .byte 0                 ; the number of bases
cm_i:           .byte 0
cm_j:           .byte 0
cm_k:           .byte 0
cm_any:         .byte 0                 ; a round found a list that is not empty
cm_s:           .word 0
cm_t:           .word 0

; xm_bases - r0 = the new class, the base value on top of the stack (None, a class,
; object, or a tuple of those): +6, +10, +12 and F_PROPS (a base holds a property)
xm_bases:
        lda r0
        ldx r0+1
        #PUSH                           ; [value][cls]
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [value][cls][bases]
        #PEEK 2
        jsr type_of
        cmp #T_TUPLE
        bne _one
        lda #0
        sta cm_i
_each:  #PEEK 2
        jsr cm_len
        cmp cm_i
        beq _have
        bcc _have
        #PEEK 2
        ldy cm_i
        jsr cm_item
        jsr cm_add
        inc cm_i
        bra _each
_one:   #PEEK 2
        jsr cm_add
_have:  #PEEK 0
        jsr cm_len
        sta cm_n
        bne +
        jmp cm_done                     ; no bases
+       #PEEK 0                         ; +6 = the first base
        ldy #0
        jsr cm_item
        pha
        phx
        #PEEK 1
        sta p0
        stx p0+1
        ldz #7
        plx
        txa
        sta [p0],z
        dez
        pla
        sta [p0],z
        lda #0                          ; F_PROPS from any base
        sta cm_i
-       #PEEK 0
        ldy cm_i
        jsr cm_item
        sta p1
        stx p1+1
        #PEEK 1
        sta p0
        stx p0+1
        ldz #1
        lda [p1],z
        and #F_PROPS
        ora [p0],z
        sta [p0],z
        inc cm_i
        lda cm_i
        cmp cm_n
        bcc -
        lda cm_n                        ; several: the bases tuple, and the MRO
        cmp #2
        bcs _several
        #PEEK 0                         ; one: an MRO only if the base has one
        ldy #0
        jsr cm_item
        sta p0
        stx p0+1
        ldz #11
        lda [p0],z
        bne cm_c3
        jmp cm_done
_several:
        #PEEK 0
        jsr tuple_from_list
        pha
        phx
        #PEEK 1
        sta p0
        stx p0+1
        ldz #13
        plx
        txa
        sta [p0],z
        dez
        pla
        sta [p0],z

; C3: MRO = the class, then merge(MRO of each base, the bases): take the first head
; that is in no list's tail, drop it from the heads, until the lists are empty
cm_c3:
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [value][cls][bases][lists]
        lda #0
        sta cm_i
-       #PEEK 1                         ; each base's MRO, as a list
        ldy cm_i
        jsr cm_item
        jsr cm_linear
        jsr cm_append
        inc cm_i
        lda cm_i
        cmp cm_n
        bcc -
        #PEEK 1                         ; and the bases
        jsr list_from_iterable
        jsr cm_append
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [value][cls][bases][lists][mro]
        #PEEK 3
        sta r1
        stx r1+1
        jsr cm_put
_round: lda #0
        sta cm_i
        sta cm_any
_cand:  #PEEK 1                         ; list i's head
        jsr cm_len
        cmp cm_i
        beq _end
        bcc _end
        #PEEK 1
        ldy cm_i
        jsr cm_item
        sta cm_s
        stx cm_s+1
        jsr cm_len
        beq _next
        inc cm_any
        ldy #0
        lda cm_s
        ldx cm_s+1
        jsr cm_item
        sta r1
        stx r1+1
        lda #0                          ; in some list's tail?
        sta cm_j
_lists: #PEEK 1
        jsr cm_len
        cmp cm_j
        beq _take
        bcc _take
        #PEEK 1
        ldy cm_j
        jsr cm_item
        sta cm_t                        ; (refs only: nothing allocates here)
        stx cm_t+1
        jsr cm_len
        sta cm_k
_tail:  dec cm_k
        beq _nextl
        bmi _nextl
        ldy cm_k
        lda cm_t
        ldx cm_t+1
        jsr cm_item
        cmp r1
        bne _tail
        cpx r1+1
        beq _next                       ; yes: not this one
        bra _tail
_nextl: inc cm_j
        bra _lists
_next:  inc cm_i
        bra _cand
_end:   lda cm_any
        beq _fin
        #RAISE EXC_TYPE, "Cannot create a consistent method resolution order (MRO)"
_take:  jsr cm_put                      ; r1 is next in the MRO; off the heads
        lda #0
        sta cm_j
-       #PEEK 1
        jsr cm_len
        cmp cm_j
        beq _round
        bcc _round
        #PEEK 1
        ldy cm_j
        jsr cm_item
        sta r0
        stx r0+1
        jsr cm_len
        beq +
        ldy #0
        lda r0
        ldx r0+1
        jsr cm_item
        cmp r1
        bne +
        cpx r1+1
        bne +
        lda #0
        tax
        jsr list_del_at
+       inc cm_j
        bra -
_fin:   #PEEK 0                         ; +10 = the MRO, as a tuple
        jsr tuple_from_list
        pha
        phx
        #DROP 2
        #PEEK 1
        sta p0
        stx p0+1
        ldz #11
        plx
        txa
        sta [p0],z
        dez
        pla
        sta [p0],z
cm_done:
        jsr clear_rregs
        #PEEK 1                         ; -> A/X = the class
        #DROP 2                         ; [value]
        rts

; cm_add - A/X = a base value: a class onto the bases list (top of the stack); None and
; object add nothing; another builtin type cannot be a base
cm_add: sta r1
        stx r1+1
        jsr type_of
        cmp #T_CLASS
        beq _add
        cmp #T_NONE
        beq _rts
        cmp #T_BUILTIN
        bne _bad
        ldz #4
        lda [p0],z
        cmp #B_OBJECT
        beq _rts
        jmp raise_subclass
_bad:   #RAISE EXC_TYPE, "bases must be classes"
_add:   #PEEK 0
        sta r0
        stx r0+1
        jmp list_append
_rts:   rts

; cm_append - A/X = a list: onto the list of lists (top of the stack)
cm_append:
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jmp list_append
; cm_put - r1 onto the MRO list (top of the stack)
cm_put: #PEEK 0
        sta r0
        stx r0+1
        jmp list_append

; cm_linear - A/X = a class -> A/X = its MRO as a new list (its +10, else the +6 chain)
cm_linear:
        sta p0
        stx p0+1
        ldz #11
        lda [p0],z
        beq _chain
        tax
        dez
        lda [p0],z
        jmp list_from_iterable
_chain: lda p0
        pha
        lda p0+1
        pha
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH
        pla
        sta r1+1
        pla
        sta r1
-       #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        lda r1
        sta p0
        lda r1+1
        sta p0+1
        ldz #6
        lda [p0],z
        sta r1
        inz
        lda [p0],z
        sta r1+1
        bne -
        #POP
        rts

; cm_len - A/X = a list or tuple -> A = its length (< 256 here)
cm_len: jsr seq_len
        lda t0
        rts
; cm_item - A/X = a list or tuple, Y = index -> A/X = the item
cm_item:
        sty t2
        ldy #0
        sty t2+1
        jmp seq_get_t2

;---------------------------------------------------------------------------------------
; xm_class_attr - groot+10 = a class, r1 = name (not in the class): __mro__ and __bases__
; (with object, as CPython shows them), else AttributeError (groot+10: the object)
;---------------------------------------------------------------------------------------
xm_class_attr:
        lda groot+10                    ; (get_method keeps the class there; the
        sta r2                          ; lookup clobbered r2)
        lda groot+11
        sta r2+1
        lda #<_mro
        ldx #>_mro
        jsr _is
        bcc _getmro
        lda #<_bases
        ldx #>_bases
        jsr _is
        bcc _getbases
        lda groot+10
        sta r0
        lda groot+11
        sta r0+1
        jmp raise_attr
_getmro:
        lda r2
        ldx r2+1
        jsr cm_linear
        bra _obj
_getbases:
        lda r2
        sta p0
        lda r2+1
        sta p0+1
        ldz #13
        lda [p0],z
        beq +
        tax
        dez
        lda [p0],z
        clc
        rts
+       lda #0                          ; (base,) or (object,)
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH
        sta r0
        stx r0+1
        lda r2
        sta p0
        lda r2+1
        sta p0+1
        ldz #6
        lda [p0],z
        sta r1
        inz
        lda [p0],z
        sta r1+1
        beq +
        jsr list_append
        bra _tup
+       #POP
_obj:   #PUSH                           ; the list, then object
        sta r0
        stx r0+1
        lda #B_OBJECT
        jsr builtin_obj
        sta r1
        stx r1+1
        jsr list_append
_tup:   #PEEK 0                         ; (the list stays on the stack while the tuple
        jsr tuple_from_list             ; is made)
        #DROP 1
        clc
        rts
_is:    jsr intern_cstr                 ; is r1 the name A/X? -> C clear
        lda int_ref
        cmp r1
        bne +
        lda int_ref+1
        cmp r1+1
        bne +
        clc
        rts
+       sec
        rts
_mro:   .null "__mro__"
_bases: .null "__bases__"
