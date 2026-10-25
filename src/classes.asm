;=======================================================================================
; Attributes, classes and instances.
; groot slots: +10 get_method object, +12 class_lookup cursor (+14 is dict_set's).
;=======================================================================================
T_SUPER         = 18                    ; +4 self, +6 class whose base starts the search

op_load_attr:
        #FETCHW
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr getattr
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

op_store_attr:
        ; obj val ->
        #FETCHW
        sta r1
        stx r1+1
        #PEEK 0
        sta r2
        stx r2+1
        #PEEK 1
        sta r0
        stx r0+1
        jsr setattr
        #DROP 2
        jsr clear_rregs
        jmp vm_loop

op_delete_attr:
        #FETCHW
        sta r1
        stx r1+1
        #POP
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_INST
        bne _bad
        ldz #6
        lda [p0],z
        tax
        dez
        lda [p0],z
        sta r0
        stx r0+1
        cpx #0
        beq _bad
        jsr dict_del
        bcs _bad
        jsr clear_rregs
        jmp vm_loop
_bad:   jmp raise_attr

; getattr - r0 = object, r1 = name ref -> A/X (methods come back bound)
getattr:
        jsr get_method
        bcc _done
        ; bind self
        sta r2
        stx r2+1
        lda #8
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_BOUND
        jsr alloc
        ldz #4
        lda groot+10
        sta [p0],z
        inz
        lda groot+11
        sta [p0],z
        inz
        lda r2
        sta [p0],z
        inz
        lda r2+1
        sta [p0],z
        lda p0
        ldx p0+1
_done:  pha
        lda #0
        sta groot+10
        sta groot+11
        pla
        rts

; get_method - r0 = object, r1 = name ref -> A/X; C set when it must be called with
; the object as self (the object is left in groot+10 for that)
get_method:
        lda r0
        sta groot+10
        lda r0+1
        sta groot+11
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_INST
        beq _inst
        cmp #T_CLASS
        bne +
        jmp _class
+       cmp #T_SUPER
        bne +
        jmp _super
+       cmp #T_MODULE
        bne +
        jmp module_getattr
+       ; built-in types: their method tables
        jsr builtin_method
        bcs +
        sec
        rts
+       ; __name__ of functions (+8), builtins and builtin types (+6)
        lda r0
        ldx r0+1
        jsr type_of
        ldy #9
        cmp #T_FUNC
        beq +
        ldy #7
        cmp #T_BUILTIN
        bne _err
+       phy
        lda r1
        ldx r1+1
        jsr is_name_attr
        plz
        bcc _err
        lda [p0],z
        tax
        dez
        lda [p0],z
        clc
        rts
_err:   lda groot+10
        sta r0
        lda groot+11
        sta r0+1
        jmp raise_attr
_inst:  ldz #6                          ; the instance dict first
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        ldz #4
        lda [p0],z
        sta r2
        inz
        lda [p0],z
        sta r2+1
        lda t0+1
        beq _cls
        lda t0
        sta r0
        lda t0+1
        sta r0+1
        lda r2
        pha
        lda r2+1
        pha
        jsr dict_get
        sta t0
        stx t0+1
        pla
        sta r2+1
        pla
        sta r2
        bcs _cls
        lda t0
        ldx t0+1
        clc
        rts
_cls:   lda r1                          ; __class__
        ldx r1+1
        jsr is_class_attr
        bcc +
        lda r2
        ldx r2+1
        clc
        rts
+       jsr class_lookup
        bcs _err
        jmp desc_resolve                ; functions take self; staticmethod, property...
_class: lda r1
        ldx r1+1
        jsr is_name_attr
        bcc +
        ldz #5
        lda [p0],z
        tax
        dez
        lda [p0],z
        clc
        rts
+       lda r0
        sta r2
        lda r0+1
        sta r2+1
        jsr class_lookup
        bcs _err
        jmp desc_class                  ; (classmethods bind to the class)
_super: ldz #4                          ; self
        lda [p0],z
        sta groot+10
        inz
        lda [p0],z
        sta groot+11
        inz
        lda [p0],z                      ; class -> its base
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldz #6
        lda [p1],z
        sta r2
        inz
        lda [p1],z
        sta r2+1
        jsr class_lookup
        bcs _err
        jmp desc_resolve

; is_name_attr / is_class_attr - A/X = name ref -> C set if it is __name__ / __class__
is_name_attr:
        ldy #<S_NAME
        bra +
is_class_attr:
        ldy #<S_CLASS
+       phx
        pha
        tya
        ldx #0
        jsr sym_name
        stx t1+1
        sta t1
        pla
        plx
        cmp t1
        bne _no
        cpx t1+1
        bne _no
        sec
        rts
_no:    clc
        rts

; class_lookup - r2 = class (or 0), r1 = name ref -> C clear and A/X if found.
; Follows the base chain. r2 is left as the class where it was found.
class_lookup:
        lda r2
        sta groot+12
        lda r2+1
        sta groot+13
_loop:  lda groot+13
        beq _miss
        sta p0+1
        lda groot+12
        sta p0
        ldz #8
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        beq _up
        jsr dict_get
        bcc _hit
_up:    lda groot+12
        sta p0
        lda groot+13
        sta p0+1
        ldz #6
        lda [p0],z
        sta groot+12
        inz
        lda [p0],z
        sta groot+13
        bra _loop
_miss:  lda #0
        sta groot+12
        sta groot+13
        sec
        rts
_hit:   pha
        lda groot+12
        sta r2
        lda groot+13
        sta r2+1
        lda #0
        sta groot+12
        sta groot+13
        pla
        clc
        rts

; setattr - r0 = object, r1 = name ref, r2 = value
setattr:
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_INST
        beq _inst
        cmp #T_MODULE
        bne +
        jmp module_setattr
+
        cmp #T_CLASS
        bne _bad
        lda r0                          ; (the class, for desc_mark)
        pha
        lda r0+1
        pha
        ldz #8
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        jsr dict_set
        plx
        pla
        jmp desc_mark
_bad:   jmp raise_attr
_inst:  jsr desc_store                  ; a property's setter?
        bcc +
        rts
+       lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #6
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        bne _set
        ; first attribute: give the instance its dict
        lda r0
        pha
        lda r0+1
        pha
        jsr dict_new
        sta t0
        stx t0+1
        pla
        sta r0+1
        sta p0+1
        pla
        sta r0
        sta p0
        ldz #6
        lda t0
        sta [p0],z
        inz
        lda t0+1
        sta [p0],z
_set:   lda t0
        sta r0
        lda t0+1
        sta r0+1
        jmp dict_set

; dict_del - r0 = dict, r1 = key: remove it (C set if missing)
dict_del:
        jsr dict_find
        bcc +
        rts
+       ; shift the pairs after t3 down by one; count -= 1
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #4
        sec
        lda [p0],z
        sbc #1
        sta [p0],z
        sta t4
        inz
        lda [p0],z
        sbc #0
        sta [p0],z
        sta t4+1
        ; bytes to move = (count_after - t3) * 4
        sec
        lda t4
        sbc t3
        sta t0
        lda t4+1
        sbc t3+1
        sta t0+1
        asw t0
        asw t0
        lda t0
        ora t0+1
        beq _done
        lda p1
        sta fp1
        lda p1+1
        sta fp1+1
        clc
        lda p1
        adc #4
        sta fp0
        lda p1+1
        adc #0
        sta fp0+1
        lda #HEAP_BANK
        sta fp0+2
        sta fp1+2
        lda #0
        sta fp0+3
        sta fp1+3
        jsr dma_copy
_done:  jsr dict_reindex                ; (the pairs after it moved down)
        clc
        rts

;---------------------------------------------------------------------------------------
; isinstance_r2_r3 - is r2 an instance of r3 (class, builtin type, or a tuple of them)?
; -> C set if yes
;---------------------------------------------------------------------------------------
isinstance_r2_r3:
        lda r3
        ldx r3+1
        jsr type_of
        cmp #T_TUPLE
        beq _tuple
        cmp #T_BUILTIN
        beq _builtin
        cmp #T_CLASS
        bne _no
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_INST
        bne _no
        ldz #4
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ; walk the class chain of the instance
_walk:  lda p1+1
        beq _no
        lda p1
        cmp r3
        bne +
        lda p1+1
        cmp r3+1
        beq _yes
+       ldz #6
        lda [p1],z
        tax
        inz
        lda [p1],z
        stx p1
        sta p1+1
        bra _walk
_yes:   sec
        rts
_no:    clc
        rts
_builtin:
        jsr builtin_type_of_r2          ; -> A/X = the builtin type object of r2
        cmp r3
        bne +
        cpx r3+1
        beq _yes
+       ; bool is a subclass of int
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_BOOL
        bne _no
        lda #B_INT
        jsr builtin_obj
        cmp r3
        bne _no
        cpx r3+1
        beq _yes
        bra _no
_tuple: lda r3
        pha
        lda r3+1
        pha
        lda r3
        ldx r3+1
        jsr seq_len
        lda t0
        sta t6
        lda #0
        sta t2
        sta t2+1
_each:  lda t2
        cmp t6
        bcs _tno
        pla
        sta r3+1
        pla
        sta r3
        pha
        lda r3+1
        pha
        lda t2
        pha
        lda t6
        pha
        lda r3
        ldx r3+1
        jsr seq_get_t2
        sta r3
        stx r3+1
        jsr isinstance_r2_r3
        pla
        sta t6
        pla
        sta t2
        bcs _tyes
        inc t2
        bra _each
_tno:   pla
        sta r3+1
        pla
        sta r3
        clc
        rts
_tyes:  pla
        sta r3+1
        pla
        sta r3
        sec
        rts

; make_super - r2 = class, r3 = self -> A/X super proxy
make_super:
        lda #8
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_SUPER
        jsr alloc
        ldz #4
        lda r3
        sta [p0],z
        inz
        lda r3+1
        sta [p0],z
        inz
        lda r2
        sta [p0],z
        inz
        lda r2+1
        sta [p0],z
        lda p0
        ldx p0+1
        rts

;---------------------------------------------------------------------------------------
; dunder methods of user classes, called from native code
;---------------------------------------------------------------------------------------
; inst_dunder - r0 = instance, A = method symbol (< 256), X = 0 or 1 arguments (r1).
; -> C clear, A/X = result if the class defines it; C set if not.
; r0-r3 and t0-t7 are preserved.
dun_sym:        .byte 0
dun_n:          .byte 0
inst_dunder:
        sta dun_sym
        stx dun_n
        ; save r0-r3 on the value stack (kept alive), t0-t7 on the CPU stack
        ldx #0
-       lda t0,x
        pha
        inx
        cpx #16
        bne -
        lda r0
        ldx r0+1
        #PUSH
        lda r1
        ldx r1+1
        #PUSH
        lda r2
        ldx r2+1
        #PUSH
        lda r3
        ldx r3+1
        #PUSH
        ; the class of r0
        lda r0
        ldx r0+1
        jsr type_of
        cmp #T_INST
        bne _none
        ldz #4
        lda [p0],z
        sta r2
        inz
        lda [p0],z
        sta r2+1
        lda dun_sym
        ldx #0
        jsr sym_name
        sta r1
        stx r1+1
        jsr class_lookup
        bcs _none
        #PUSH                           ; the method
        #PEEK 4                         ; self (saved r0)
        #PUSH
        lda dun_n
        beq +
        #PEEK 4                         ; the argument (saved r1)
        #PUSH
+       lda dun_n
        inc a
        sta argc
        jsr vm_call_nested
        sta vtmp
        stx vtmp+1
        clc
        bra _restore
_none:  sec
_restore:
        php
        #POP
        sta r3
        stx r3+1
        #POP
        sta r2
        stx r2+1
        #POP
        sta r1
        stx r1+1
        #POP
        sta r0
        stx r0+1
        plp
        ldx #15
-       pla
        sta t0,x
        dex
        bpl -
        lda vtmp
        ldx vtmp+1
        rts

; inst_binop - r2 op r3 with r2's method A -> C clear, A/X (C set: no such method)
; inst_rbinop - reflected: r3's method A with r2
; inst_unary - r2's method A, no arguments
; All keep r0-r3 (callers such as dict_scan keep their own state in r0/r1).
inst_binop:
        ldy #0
        bra inst_r23
inst_rbinop:
        ldy #1
        bra inst_r23
inst_unary:
        ldy #2
inst_r23:
        sta ir_sym
        lda r0
        pha
        lda r0+1
        pha
        lda r1
        pha
        lda r1+1
        pha
        ldx #1                          ; r0 = self, r1 = the argument
        cpy #1
        beq _refl
        lda r2
        sta r0
        lda r2+1
        sta r0+1
        lda r3
        sta r1
        lda r3+1
        sta r1+1
        cpy #2
        bne _call
        dex                             ; (unary: none)
        bra _call
_refl:  lda r3
        sta r0
        lda r3+1
        sta r0+1
        lda r2
        sta r1
        lda r2+1
        sta r1+1
_call:  lda ir_sym
        jsr inst_dunder
        sta ir_a
        stx ir_x
        php
        pla
        sta ir_p
        pla
        sta r1+1
        pla
        sta r1
        pla
        sta r0+1
        pla
        sta r0
        lda ir_p
        pha
        lda ir_a
        ldx ir_x
        plp
        rts
ir_sym: .byte 0
ir_a:   .byte 0
ir_x:   .byte 0
ir_p:   .byte 0

; inst_eq - r2 == r3 for instances: __eq__, else identity (already false) -> C
inst_eq:
        lda #S_EQ
        jsr inst_binop
        bcs _no
        jmp obj_truth_c
_no:    clc
        rts

; A/X -> C set if truthy
obj_truth_c:
        jsr obj_truth
        lsr
        rts

; inst_cmp - order instances with __lt__ -> A = $ff / 0 / 1
inst_cmp:
        lda #S_LT
        jsr inst_binop
        bcs _bad
        jsr obj_truth
        beq +
        lda #$ff
        rts
+       lda #S_LT
        jsr inst_rbinop
        bcs _bad
        jsr obj_truth
        rts
_bad:   jmp raise_cmp_types

; inst_truth - A/X instance -> A = 1 / 0 (__bool__, then __len__)
inst_truth:
        sta r2
        stx r2+1
        lda #S_BOOL
        jsr inst_unary
        bcc _got
        lda #S_LEN
        jsr inst_unary
        bcc _got
        lda #1
        rts
_got:   jmp obj_truth

; inst_str - append str(instance A/X)
inst_str:
        sta r2
        stx r2+1
        lda #S_STR
        jsr inst_unary
        bcs +
        jmp sb_put_str
+       lda #EXC_BASE                   ; exceptions: their message
        jsr exc_is
        bcc _repr
        lda #EXC_KEY                    ; (a KeyError shows its key's repr)
        jsr exc_is
        lda #0
        rol
        sta ist_key
        jsr exc_args
        jsr seq_len
        lda t0
        beq _empty
        cmp #1
        bne _many
        lda #0
        sta t2
        sta t2+1
        lda r3
        ldx r3+1
        jsr seq_get_t2
        ldy ist_key
        beq +
        jmp obj_repr
+       jmp obj_str
_many:  lda r3
        ldx r3+1
        jmp obj_repr
_empty: rts
_repr:  lda r2
        ldx r2+1
        jmp inst_repr

ist_key:        .byte 0

; r3 = the args tuple of exception r2
exc_args:
        lda r2
        sta r0
        lda r2+1
        sta r0+1
        lda #<S_ARGS
        ldx #>S_ARGS
        jsr sym_name
        sta r1
        stx r1+1
        jsr getattr
        sta r3
        stx r3+1
        rts

; inst_repr - append repr(instance A/X)
inst_repr:
        sta r2
        stx r2+1
        lda #S_REPR
        jsr inst_unary
        bcs +
        jmp sb_put_str
+       lda #EXC_BASE
        jsr exc_is
        bcc _obj
        lda r2
        ldx r2+1
        jsr sb_type_name
        jsr exc_args
        jsr seq_len
        lda t0
        cmp #1
        bne +
        lda #'('
        jsr sb_putc
        lda #0
        sta t2
        sta t2+1
        lda r3
        ldx r3+1
        jsr seq_get_t2
        jsr obj_repr
        lda #')'
        jmp sb_putc
+       lda r3
        ldx r3+1
        jmp obj_repr
_obj:   lda #'<'
        jsr sb_putc
        lda r2
        ldx r2+1
        jsr sb_type_name
        #SBPRINT " object>"
        rts
