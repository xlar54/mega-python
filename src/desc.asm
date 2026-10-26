;=======================================================================================
; staticmethod, classmethod and property (overlay R).
;
; A T_DESC object (+4 kind, +6 function / getter, +8 setter or 0) in a class changes
; what an attribute lookup gives (desc_resolve, from get_method):
;   staticmethod: the function itself, for an instance or the class
;   classmethod:  the function bound to the class
;   property:     for an instance, its getter's result; for the class, the property
; A store into an instance attribute calls a property's setter (desc_store, from
; setattr). Classes holding a property have F_PROPS in their header flags (inherited
; by subclasses), so other stores skip the class lookup.
;=======================================================================================
DK_STATIC       = 0
DK_CLASS        = 1
DK_PROPERTY     = 2

; desc_new - A = kind, r1 = function, r2 = setter (0 = none) -> A/X
desc_new:
        pha
        lda #10
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_DESC
        jsr alloc
        pla
        ldz #4
        sta [p0],z
        ldz #6
        lda r1
        sta [p0],z
        inz
        lda r1+1
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

bi_staticmethod:
        lda #DK_STATIC
        bra desc_one
bi_classmethod:
        lda #DK_CLASS
desc_one:
        pha
        #NARGS 1, 1
        #ARG 0
        sta r1
        stx r1+1
        lda #0
        sta r2
        sta r2+1
        pla
        jmp desc_new

; property(fget, fset=None)
bi_property:
        #NARGS 1, 2
        #ARG 0
        sta r1
        stx r1+1
        lda #0
        sta r2
        sta r2+1
        lda npos
        cmp #2
        bcc +
        #ARG 1
        jsr none_to_null
        sta r2
        stx r2+1
+       lda #DK_PROPERTY
        jmp desc_new

; property.setter(f) / property.getter(f): a copy with that function
bi_desc_setter:
        jsr desc_args
        #ARG 1
        sta r2
        stx r2+1
        lda #DK_PROPERTY
        jmp desc_new
bi_desc_getter:
        jsr desc_args
        #ARG 1
        sta r1
        stx r1+1
        lda #DK_PROPERTY
        jmp desc_new
; r1 / r2 = the getter / setter of property argv[0]
desc_args:
        #NARGS 2, 2
        #ARG 0
        sta p0
        stx p0+1
        ldz #6
        lda [p0],z
        sta r1
        inz
        lda [p0],z
        sta r1+1
        inz
        lda [p0],z
        sta r2
        inz
        lda [p0],z
        sta r2+1
        rts

repr_desc:
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        cmp #DK_PROPERTY
        beq +
        cmp #DK_CLASS
        beq ++
        #SBPRINT "<staticmethod object>"
        rts
+       #SBPRINT "<property object>"
        rts
+       #SBPRINT "<classmethod object>"
        rts

;---------------------------------------------------------------------------------------
; desc_resolve - (get_method) A/X = what class_lookup found for an instance attribute
; (groot+10 = the instance) -> get_method's answer: A/X, C set to call it with
; groot+10 as self
;---------------------------------------------------------------------------------------
desc_resolve:
        sta t0
        stx t0+1
        jsr type_of
        cmp #T_FUNC
        beq _self
        cmp #T_BUILTIN
        beq _self
        cmp #T_DESC
        beq _desc
        lda t0                          ; anything else: as it is
        ldx t0+1
        clc
        rts
_self:  lda t0
        ldx t0+1
        sec
        rts
_desc:  ldz #4
        lda [p0],z
        pha
        ldz #6                          ; the function
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        pla
        cmp #DK_STATIC
        bne +
        lda t0
        ldx t0+1
        clc
        rts
+       cmp #DK_CLASS
        bne _prop
        lda groot+10                    ; self = the instance's class
        sta p0
        lda groot+11
        sta p0+1
        ldz #4
        lda [p0],z
        sta groot+10
        inz
        lda [p0],z
        sta groot+11
        bra _self
_prop:  lda groot+10                    ; the getter's result
        sta r1
        lda groot+11
        sta r1+1
        lda #0
        sta groot+10
        sta groot+11
        lda t0
        ldx t0+1
        jsr call1
        clc
        rts

; desc_class - (get_method) A/X = what class_lookup found for an attribute of the class
; itself (groot+10 = the class) -> A/X, C set to call it with the class as self
desc_class:
        sta t0
        stx t0+1
        jsr type_of
        cmp #T_DESC
        beq +
        lda t0
        ldx t0+1
        clc
        rts
+       ldz #4
        lda [p0],z
        cmp #DK_PROPERTY
        beq +                           ; a property: the property itself
        pha
        ldz #6
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        pla
        cmp #DK_CLASS
        bne +
        lda t0
        ldx t0+1
        sec
        rts
+       lda t0
        ldx t0+1
        clc
        rts

;---------------------------------------------------------------------------------------
; desc_store - (setattr) r0 = instance, r1 = name, r2 = value: if its class has a
; property of that name, its setter takes the value -> C set (done); else C clear
; (r0-r2 kept)
;---------------------------------------------------------------------------------------
desc_store:
        lda r0
        sta p0
        lda r0+1
        sta p0+1
        ldz #4                          ; the class: does it hold properties?
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldz #1
        lda [p1],z
        and #F_PROPS
        bne +
        clc
        rts
+       lda r0
        pha
        lda r0+1
        pha
        lda r2
        pha
        lda r2+1
        pha
        lda p1
        sta r2
        lda p1+1
        sta r2+1
        jsr class_lookup                ; (r1 = the name) -> C clear, A/X
        sta t0
        stx t0+1
        pla                             ; (keeps C)
        sta r2+1
        pla
        sta r2
        pla
        sta r0+1
        pla
        sta r0
        bcs _no
        lda t0
        ldx t0+1
        jsr type_of
        cmp #T_DESC
        bne _no
        ldz #4
        lda [p0],z
        cmp #DK_PROPERTY
        bne _no
        ldz #9                          ; the setter
        lda [p0],z
        tax
        dez
        lda [p0],z
        cpx #0
        bne +
        #RAISE EXC_ATTR, "property has no setter"
+       pha
        lda r0                          ; setter(instance, value)
        sta r1
        lda r0+1
        sta r1+1
        pla
        jsr call2
        sec
        rts
_no:    clc
        rts

;---------------------------------------------------------------------------------------
; LOAD_CLASSNAME sym - (a name in a class body) the class's attribute if it has one,
; else the global (as LOAD_GLOBAL): so a class body sees what it defined before
;---------------------------------------------------------------------------------------
op_load_classname:
        #FETCHW
        sta vtmp
        stx vtmp+1
        jsr cb_prune
        ldx cb_sp
        beq _global
        lda cb_stack-4,x                ; the class whose body runs
        sta p0
        lda cb_stack-3,x
        sta p0+1
        ldz #8
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        lda vtmp
        ldx vtmp+1
        jsr unmangle                    ; (class attributes have the plain name)
        jsr sym_name
        sta r1
        stx r1+1
        jsr dict_get
        bcs _global
        #PUSH
        jsr clear_rregs
        jmp vm_loop
_global:
        jsr clear_rregs
        lda vtmp
        ldx vtmp+1
        jsr sym_val_addr
        jmp load_global_fp1

; desc_mark - (a class attribute was set) r2 = the value, A/X = the class: a property
; gives the class F_PROPS
desc_mark:
        sta p1
        stx p1+1
        lda r2
        ldx r2+1
        jsr type_of
        cmp #T_DESC
        bne +
        ldz #4
        lda [p0],z
        cmp #DK_PROPERTY
        bne +
        ldz #1
        lda [p1],z
        ora #F_PROPS
        sta [p1],z
+       rts
