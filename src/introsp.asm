;=======================================================================================
; Introspection builtins, tail T: dir(), vars(), globals(), delattr(), slice() and the
; attributes of a slice.
;
; globals() is a snapshot: the global table (SYM_VAL) holds the builtins too, so it
; leaves out each symbol whose value is still the one it had at boot (SYM_BOOT,
; py_reset), and the hidden "module.name" symbols.
;=======================================================================================
in_s:           .word 0
in_i:           .word 0
in_j:           .word 0
in_depth:       .byte 0                 ; dir(): the stack slot of the set of names

; slice(stop) | slice(start, stop[, step])
xt_slice:
        #NARGS 1, 3
        lda #10
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_SLICE
        jsr alloc
        ldz #4                          ; all None
-       lda #R_NONE
        sta [p0],z
        inz
        lda #0
        sta [p0],z
        inz
        cpz #10
        bne -
        lda npos
        cmp #1
        bne +
        #ARG 0                          ; slice(stop)
        ldz #6
        bra _put
+       #ARG 0
        ldz #4
        jsr _set
        #ARG 1
        ldz #6
        jsr _set
        lda npos
        cmp #3
        bne _done
        #ARG 2
        ldz #8
_put:   jsr _set
_done:  lda p0
        ldx p0+1
        rts
_set:   sta [p0],z
        inz
        txa
        sta [p0],z
        rts

; xt_slice_attr - r0 = slice, r1 = name: its start, stop or step (else AttributeError)
xt_slice_attr:
        ldy #4
        lda #<_start
        ldx #>_start
        jsr _is
        bcc _get
        ldy #6
        lda #<_stop
        ldx #>_stop
        jsr _is
        bcc _get
        ldy #8
        lda #<_step
        ldx #>_step
        jsr _is
        bcc _get
        jmp raise_attr
_get:   lda r0
        sta p0
        lda r0+1
        sta p0+1
        tya
        taz
        inz
        lda [p0],z
        tax
        dez
        lda [p0],z
        clc
        rts
_is:    phy                             ; is r1 the name A/X? -> C clear
        jsr intern_cstr
        ply
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
_start: .null "start"
_stop:  .null "stop"
_step:  .null "step"

; delattr(obj, name): an instance's or a class's own attribute
xt_delattr:
        #NARGS 2, 2
        jsr attr_name_arg
        #ARG 0
        sta r0
        stx r0+1
        jsr in_attrs
        bcs _bad
        ldy r0                          ; (the object, for the error message)
        sty in_j
        ldy r0+1
        sty in_j+1
        sta r0
        stx r0+1
        jsr dict_del
        lda in_j
        sta r0
        lda in_j+1
        sta r0+1
        bcs _bad
        jsr clear_rregs
        #RET_NONE
_bad:   jmp raise_attr

; in_attrs - r0 = instance or class -> C clear, A/X = its attribute dict (an instance
; without one gets one); C set for other objects
in_attrs:
        lda r0
        ldx r0+1
        jsr type_of
        ldz #8
        cmp #T_CLASS
        beq _get
        cmp #T_INST
        bne _no
        ldz #7
        lda [p0],z
        bne +
        jsr dict_new                    ; (the instance has no attributes yet)
        pha
        phx
        lda r0
        sta p0
        lda r0+1
        sta p0+1
        ldz #7
        pla
        sta [p0],z
        tax
        dez
        pla
        sta [p0],z
        clc
        rts
+       ldz #6
_get:   inz
        lda [p0],z
        tax
        dez
        lda [p0],z
        clc
        rts
_no:    sec
        rts

; globals(): a new dict of the program's global names
xt_globals:
        #NARGS 0, 0
in_globals:
        jsr dict_new
        #PUSH                           ; [dict]
        lda #1
        sta in_s
        lda #0
        sta in_s+1
_next:  lda in_s
        cmp nsyms
        lda in_s+1
        sbc nsyms+1
        bcs _end
        lda in_s
        ldx in_s+1
        jsr sym_val_addr
        ldz #0
        lda [fp1],z
        sta r2
        inz
        lda [fp1],z
        sta r2+1
        ora r2
        beq _skip                       ; not bound
        lda in_s+1                      ; bound at boot, and still that value?
        cmp nsyms_boot+1
        bcc +
        bne _user
        lda in_s
        cmp nsyms_boot
        bcs _user
+       lda in_s
        asl a
        sta fp1
        lda in_s+1
        rol a
        clc
        adc #>(SYM_BOOT & $ffff)
        sta fp1+1
        lda #<(SYM_BOOT >> 16)
        sta fp1+2
        lda #>(SYM_BOOT >> 16)
        sta fp1+3
        ldz #0
        lda [fp1],z
        cmp r2
        bne _user
        inz
        lda [fp1],z
        cmp r2+1
        beq _skip
_user:  lda in_s
        ldx in_s+1
        jsr sym_name
        sta r1
        stx r1+1
        jsr str_info                    ; a hidden module name has a '.'
        ldz #0
-       cpz str_len
        beq +
        lda [fp0],z
        cmp #'.'
        beq _skip
        inz
        bra -
+       #PEEK 0
        sta r0
        stx r0+1
        jsr dict_set
_skip:  inc in_s
        bne _next
        inc in_s+1
        bra _next
_end:   #POP
        jmp in_done

; vars([obj]): globals(); an instance's or class's attribute dict; a module's names
xt_vars:
        #NARGS 0, 1
        lda npos
        bne +
        jmp in_globals
+       #ARG 0
        sta r0
        stx r0+1
        jsr in_attrs
        bcs +
        rts
+       lda r0
        ldx r0+1
        jsr type_of
        cmp #T_MODULE
        beq +
        #RAISE EXC_TYPE, "vars() argument must have __dict__ attribute"
+       lda r0                          ; a module: {name: value}
        ldx r0+1
        #PUSH                           ; [module]
        jsr mod_names
        #PUSH                           ; [module][names]
        jsr dict_new
        #PUSH                           ; [module][names][dict]
        lda #0
        sta in_i
        sta in_i+1
_loop:  #PEEK 1
        jsr seq_len
        lda in_i
        cmp t0
        lda in_i+1
        sbc t0+1
        bcs _end
        lda in_i
        sta t2
        lda in_i+1
        sta t2+1
        #PEEK 1
        jsr seq_get_t2
        sta r1
        stx r1+1
        #PEEK 2
        sta r0
        stx r0+1
        jsr module_getattr
        sta r2
        stx r2+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_set
        inc in_i
        bne _loop
        inc in_i+1
        bra _loop
_end:   #POP
        #DROP 2
in_done:
        pha
        phx
        jsr clear_rregs
        plx
        pla
        rts

; dir([obj]): the sorted names of the globals, or of the object's attributes (an
; instance's and its classes', a class's and its bases', a module's, a builtin type's
; methods)
xt_dir:
        #NARGS 0, 1
        jsr dict_new                    ; (a set of names: name -> None)
        #PUSH                           ; [names]
        lda #0
        sta in_depth
        lda npos
        bne +
        jsr in_globals                  ; dir(): the global names
        jsr in_keys
        jmp _list
+       #ARG 0
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_MODULE
        bne +
        jsr mod_names
        jmp in_sorted
+       cmp #T_INST
        bne _cls
        jsr in_attrs                    ; the instance's own names
        jsr in_keys
        #ARG 0
        sta p0
        stx p0+1
        ldz #4                          ; then its class's
        lda [p0],z
        tay
        inz
        lda [p0],z
        tax
        tya
        bra _chain0
_cls:   cmp #T_CLASS
        bne _type
        #ARG 0
_chain0:
        sta r0                          ; a class with an MRO (classm.asm): its classes
        stx r0+1
        ora r0+1
        beq _list
        lda r0
        sta p0
        lda r0+1
        sta p0+1
        ldz #11
        lda [p0],z
        beq _c1
        sta in_s+1
        dez
        lda [p0],z
        sta in_s
        lda #0
        sta in_j
_mro:   lda in_s
        ldx in_s+1
        jsr seq_len
        lda in_j
        cmp t0
        bcs _list
        sta t2
        lda #0
        sta t2+1
        lda in_s
        ldx in_s+1
        jsr seq_get_t2
        sta r0
        stx r0+1
        jsr in_attrs
        jsr in_keys
        inc in_j
        bra _mro
_c1:    lda r0
        ldx r0+1
_chain: sta r0                          ; the class, then its bases
        stx r0+1
        ora r0+1
        beq _list
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_CLASS
        bne _list
        lda r0
        pha
        lda r0+1
        pha
        jsr in_attrs
        jsr in_keys
        pla
        sta p0+1
        pla
        sta p0
        ldz #7
        lda [p0],z
        tax
        dez
        lda [p0],z
        bra _chain
_type:  cmp #T_BUILTIN                  ; dir(str): the methods str makes
        bne _meth
        #ARG 0
        sta p0
        stx p0+1
        jsr type_made
        bcs _list
_meth:  jsr meth_table                  ; a value: its type's methods
        bcs _list
_mnext: ldy #1
        lda (t6),y
        cmp #$ff
        beq _list
        tax
        dey
        lda (t6),y
        jsr sym_name
        sta r1
        stx r1+1
        lda t6
        pha
        lda t6+1
        pha
        jsr in_add
        pla
        sta t6+1
        pla
        clc
        adc #4
        sta t6
        bcc _mnext
        inc t6+1
        bra _mnext
_list:  #PEEK 0                         ; the names, as a list
        sta r0
        stx r0+1
        lda #IT_DICT
        jsr iter_alloc
        jsr list_from_iterable
in_sorted:
        #POKE 0                         ; [list]
        jsr in_sort
        #POP
        jmp in_done

; in_keys - A/X = a dict: add its keys (names) to the set on top of the stack
in_keys:
        sta r0
        stx r0+1
        #PUSH
        inc in_depth
        lda #0
        sta in_i
        sta in_i+1
_next:  #PEEK 0
        sta p0
        stx p0+1
        ldz #4
        lda in_i
        cmp [p0],z
        inz
        lda in_i+1
        sbc [p0],z
        bcs _end
        lda in_i                        ; key = pair i's first ref
        asl a
        sta t0
        lda in_i+1
        rol a
        sta t0+1
        jsr list_item_ptr
        ldz #0
        lda [p1],z
        sta r1
        inz
        lda [p1],z
        sta r1+1
        jsr in_add
        inc in_i
        bne _next
        inc in_i+1
        bra _next
_end:   #DROP 1
        dec in_depth
        rts

; in_add - r1 = a name: into the set of names (stack slot in_depth)
in_add:
        lda in_depth
        asl a
        tay
        lda (vsp),y
        sta r0
        iny
        lda (vsp),y
        sta r0+1
        lda #R_NONE
        sta r2
        lda #0
        sta r2+1
        jmp dict_set

; in_sort - the list on top of the stack: sorted in place (insertion sort; the names of
; one object are few)
in_sort:
        lda #1
        sta in_i
        lda #0
        sta in_i+1
_outer: #PEEK 0
        jsr seq_len
        lda in_i
        cmp t0
        lda in_i+1
        sbc t0+1
        bcs _done
        lda in_i
        sta in_j
        lda in_i+1
        sta in_j+1
_inner: lda in_j
        ora in_j+1
        beq _nexti
        sec                             ; items[j - 1] > items[j]?
        lda in_j
        sbc #1
        sta t0
        lda in_j+1
        sbc #0
        sta t0+1
        jsr _ptr
        ldz #0
        lda [p1],z
        sta r2
        inz
        lda [p1],z
        sta r2+1
        ldz #2
        lda [p1],z
        sta r3
        inz
        lda [p1],z
        sta r3+1
        jsr obj_cmp
        cmp #1
        bne _nexti
        sec                             ; swap them
        lda in_j
        sbc #1
        sta t0
        lda in_j+1
        sbc #0
        sta t0+1
        jsr _ptr
        ldz #0
        lda r3
        sta [p1],z
        inz
        lda r3+1
        sta [p1],z
        inz
        lda r2
        sta [p1],z
        inz
        lda r2+1
        sta [p1],z
        lda in_j
        bne +
        dec in_j+1
+       dec in_j
        bra _inner
_nexti: inc in_i
        bne _outer
        inc in_i+1
        bra _outer
_done:  rts
_ptr:   #PEEK 0                         ; p1 = &items[t0]
        sta p0
        stx p0+1
        jmp list_item_ptr
