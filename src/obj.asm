;=======================================================================================
; Core object operations. Calling convention: a ref travels in A (lo) / X (hi).
; Anything that allocates can run the GC: refs that must survive go in r0-r3 or
; groot (GC roots), or on the value stack.
;=======================================================================================

; type_of - A/X = ref -> A = type (T_*); for heap objects p0 points at the object.
; X is preserved.
type_of:
        bit #1
        bne _int
        cpx #0
        bne _heap
        cmp #R_NONE
        beq _none
        cmp #R_FALSE
        beq _bool
        cmp #R_TRUE
        beq _bool
        lda #T_FREE                     ; NULL
        rts
_int:   lda #T_INT
        rts
_none:  lda #T_NONE
        rts
_bool:  lda #T_BOOL
        rts
_heap:  sta p0
        stx p0+1
        ldz #0
        lda [p0],z
        rts

;---------------------------------------------------------------------------------------
; ints
;---------------------------------------------------------------------------------------
; int_val - A/X = ref -> acc (32-bit signed). C set if it is not an int (or bool).
int_val:
        bit #1
        beq _notsmall
        sta acc
        stx acc+1
        txa
        asr
        sta acc+1
        ror acc
        lda #0
        bit acc+1
        bpl +
        lda #$ff
+       sta acc+2
        sta acc+3
        clc
        rts
_notsmall:
        cpx #0
        bne _heap
        ldy #0
        cmp #R_FALSE
        beq _bool
        iny
        cmp #R_TRUE
        beq _bool
        sec
        rts
_bool:  sty acc
        lda #0
        sta acc+1
        sta acc+2
        sta acc+3
        clc
        rts
_heap:  sta p0
        stx p0+1
        ldz #0
        lda [p0],z
        cmp #T_INT
        bne _no
        ldz #4
        lda [p0],z
        sta acc
        inz
        lda [p0],z
        sta acc+1
        inz
        lda [p0],z
        sta acc+2
        inz
        lda [p0],z
        sta acc+3
        clc
        rts
_no:    sec
        rts

; int_new - acc -> A/X ref (small when it fits in 15 bits, else a boxed T_INT)
int_new:
        lda acc+1
        and #$c0
        beq _pos
        cmp #$c0
        bne _box
        lda acc+2
        and acc+3
        cmp #$ff
        bne _box
        bra _small
_pos:   lda acc+2
        ora acc+3
        bne _box
_small: lda acc+1
        sta t0
        lda acc
        asl
        rol t0
        ora #1
        ldx t0
        rts
_box:   lda #8
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_INT
        jsr alloc
        ldz #4
        lda acc
        sta [p0],z
        inz
        lda acc+1
        sta [p0],z
        inz
        lda acc+2
        sta [p0],z
        inz
        lda acc+3
        sta [p0],z
        lda p0
        ldx p0+1
        rts

; small int ref for 0 <= A < 128
int_small:
        asl
        ora #1
        ldx #0
        rts

; A = char -> A = digit value (0-35), C set if not a digit/letter
digit_value:
        cmp #'0'
        bcc _no
        cmp #'9'+1
        bcs +
        sbc #'0'-1
        clc
        rts
+       ora #$20
        cmp #'a'
        bcc _no
        cmp #'z'+1
        bcs _no
        sbc #'a'-11
        clc
        rts
_no:    sec
        rts

;---------------------------------------------------------------------------------------
; strings
;---------------------------------------------------------------------------------------
; str_alloc - str_len = length -> A/X ref, p0; chars at +6
str_alloc:
        clc
        lda str_len
        adc #6
        sta alloc_size
        lda str_len+1
        adc #0
        sta alloc_size+1
        lda #T_STR
        jsr alloc
        ldz #4
        lda str_len
        sta [p0],z
        inz
        lda str_len+1
        sta [p0],z
        lda p0
        ldx p0+1
        rts

; str_info - A/X = string ref -> fp0 = address of the chars, str_len = length
str_info:
        sta p0
        stx p0+1
        clc
        adc #6
        sta fp0
        txa
        adc #0
        sta fp0+1
        lda #HEAP_BANK
        sta fp0+2
        lda #0
        sta fp0+3
        ldz #4
        lda [p0],z
        sta str_len
        inz
        lda [p0],z
        sta str_len+1
        rts

; str_from_far - new string from str_len bytes at fp2 (the source must stay rooted)
str_from_far:
        lda fp2
        pha
        lda fp2+1
        pha
        lda fp2+2
        pha
        lda fp2+3
        pha
        jsr str_alloc
        pla
        sta fp0+3
        pla
        sta fp0+2
        pla
        sta fp0+1
        pla
        sta fp0
str_fill_from_fp0:                      ; copy str_len bytes from fp0 into the new string p0
        lda p0
        pha
        lda p0+1
        pha
        lda str_len
        ora str_len+1
        beq +
        clc
        lda p0
        adc #6
        sta fp1
        lda p0+1
        adc #0
        sta fp1+1
        lda #HEAP_BANK
        sta fp1+2
        lda #0
        sta fp1+3
        lda str_len
        sta t0
        lda str_len+1
        sta t0+1
        jsr dma_copy
+       plx
        pla
        sta p0
        stx p0+1
        rts

; str_eq - strings r2, r3 -> C set if equal (same length and bytes)
str_eq:
        lda r2
        ldx r2+1
        jsr str_info
        lda fp0
        sta fp1
        lda fp0+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        lda str_len
        sta t1
        lda str_len+1
        sta t1+1
        lda r3
        ldx r3+1
        jsr str_info
        lda str_len
        cmp t1
        bne str_ne
        lda str_len+1
        cmp t1+1
        bne str_ne
; mem_eq - compare str_len bytes at fp0 and fp1 -> C set if equal
mem_eq:
-       lda str_len
        ora str_len+1
        beq _eq
        ldz #0
        lda [fp0],z
        cmp [fp1],z
        bne str_ne
        inw fp0
        inw fp1
        dew str_len
        bra -
_eq:    sec
        rts
str_ne: clc
        rts

;---------------------------------------------------------------------------------------
; symbols: interned identifier strings, numbered in creation order. Each symbol also
; holds the global variable of that name (SYM_VAL).
;---------------------------------------------------------------------------------------
; intern - str_len bytes at fp2 -> A/X = symbol id, int_ref = string ref
intern:
        jsr intern_find
        bcs +
        rts
+       ; create: a perm interned string
        lda al_perm
        pha
        lda #F_PERM | F_INTERN
        sta al_perm
        lda t1                          ; the hash
        pha
        jsr str_from_far
        sta int_ref
        stx int_ref+1
        pla
        sta t1
        pla
        sta al_perm
        lda nsyms+1
        cmp #>MAXSYMS
        bcc +
        jmp raise_memory
+       ; SYM_NAME[n] = ref, SYM_VAL[n] = 0, SYM_NEXT[n] = bucket head, head = n + 1
        lda nsyms
        ldx nsyms+1
        jsr sym_val_addr
        ldz #0
        lda #0
        sta [fp1],z
        inz
        sta [fp1],z
        lda nsyms
        ldx nsyms+1
        jsr sym_addr
        ldz #0
        lda int_ref
        sta [fp1],z
        inz
        lda int_ref+1
        sta [fp1],z
        jsr sym_to_next_array
        jsr hash_head
        ldz #0
        lda [fp0],z
        tax
        inz
        lda [fp0],z
        tay
        ldz #0
        txa
        sta [fp1],z
        inz
        tya
        sta [fp1],z
        clc
        lda nsyms
        adc #1
        ldz #0
        sta [fp0],z
        lda nsyms+1
        adc #0
        inz
        sta [fp0],z
        lda nsyms
        ldx nsyms+1
        inw nsyms
        rts

; intern_find - as intern but C set (and nothing created) when the name is new
intern_find:
        ; hash = rol/xor over the bytes, seeded with the length
        lda str_len
        sta t1
        ldz #0
-       cpz str_len
        bcs +
        lda t1
        asl
        adc #0
        eor [fp2],z
        sta t1
        inz
        bra -
+       jsr hash_head
        ldz #0
        lda [fp0],z
        sta t2
        inz
        lda [fp0],z
        sta t2+1
_chain: lda t2
        ora t2+1
        bne +
        sec
        rts
+       lda t2                          ; sym = t2 - 1
        bne +
        dec t2+1
+       dec t2
        lda t2
        ldx t2+1
        jsr sym_addr
        ldz #0
        lda [fp1],z
        sta p1
        inz
        lda [fp1],z
        sta p1+1
        ldz #4                          ; same length?
        lda [p1],z
        cmp str_len
        bne _next
        inz
        lda [p1],z
        cmp str_len+1
        bne _next
        ; compare bytes (names are short: Z indexes)
        clc
        lda p1
        adc #6
        sta fp0
        lda p1+1
        adc #0
        sta fp0+1
        lda #HEAP_BANK
        sta fp0+2
        lda #0
        sta fp0+3
        ldz #0
-       cpz str_len
        bcs _found
        lda [fp0],z
        cmp [fp2],z
        bne _next
        inz
        bra -
_found: lda p1
        sta int_ref
        lda p1+1
        sta int_ref+1
        lda t2
        ldx t2+1
        clc
        rts
_next:  jsr sym_to_next_array
        ldz #0
        lda [fp1],z
        sta t2
        inz
        lda [fp1],z
        sta t2+1
        bra _chain

; fp0 -> hash bucket head for hash t1
hash_head:
        lda t1
        asl
        sta fp0
        lda #0
        rol
        clc
        adc #>(SYM_HASH & $ffff)
        sta fp0+1
        lda #<(SYM_HASH >> 16)
        sta fp0+2
        lda #>(SYM_HASH >> 16)
        sta fp0+3
        rts

; sym_addr - A/X = symbol id -> fp1 = &SYM_NAME[id]; SYM_NEXT follows $1000 later
; (sym_to_next_array)
sym_addr:
        asl
        sta fp1
        txa
        rol
        clc
        adc #>(SYM_NAME & $ffff)
        sta fp1+1
        lda #<(SYM_NAME >> 16)
        sta fp1+2
        lda #>(SYM_NAME >> 16)
        sta fp1+3
        rts
sym_to_next_array:
        clc
        lda fp1+1
        adc #>(SYM_NEXT - SYM_NAME)
        sta fp1+1
        rts
; sym_val_addr - A/X = symbol id -> fp1 = &SYM_VAL[id]
sym_val_addr:
        asl
        sta fp1
        txa
        rol
        clc
        adc #>(SYM_VAL & $ffff)
        sta fp1+1
        lda #<(SYM_VAL >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        rts

; sym_name - A/X = symbol id -> A/X = name string ref
sym_name:
        jsr sym_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        rts

; intern a bank-0 zero-terminated string at A/X -> A/X symbol id
intern_cstr:
        sta fp2
        stx fp2+1
        lda #0
        sta fp2+2
        sta fp2+3
        sta str_len+1
        ldz #0
-       lda [fp2],z
        beq +
        inz
        bra -
+       stz str_len
        jmp intern

;---------------------------------------------------------------------------------------
; tuples, lists, dicts
;---------------------------------------------------------------------------------------
; tuple_new - nitems -> A/X ref, p0 (items NULL)
tuple_new:
        lda nitems
        asl
        sta alloc_size
        lda nitems+1
        rol
        sta alloc_size+1
        clc
        lda alloc_size
        adc #6
        sta alloc_size
        bcc +
        inc alloc_size+1
+       lda #T_TUPLE
        jsr alloc
        ldz #4
        lda nitems
        sta [p0],z
        inz
        lda nitems+1
        sta [p0],z
        lda p0
        ldx p0+1
        rts

; arr_new - nitems refs -> A/X ref (T_ARR)
arr_new:
        lda nitems
        asl
        sta alloc_size
        lda nitems+1
        rol
        sta alloc_size+1
        clc
        lda alloc_size
        adc #4
        sta alloc_size
        bcc +
        inc alloc_size+1
+       lda #T_ARR
        jsr alloc
        lda p0
        ldx p0+1
        rts

; list_new - nitems = capacity -> A/X ref (empty list)
list_new:
        lda nitems
        ora nitems+1
        beq +
        jsr arr_new
        sta groot
        stx groot+1
+       lda #10
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_LIST
        jsr alloc
        ldz #6
        lda nitems
        sta [p0],z
        inz
        lda nitems+1
        sta [p0],z
        lda nitems
        ora nitems+1
        beq +
        inz
        lda groot
        sta [p0],z
        inz
        lda groot+1
        sta [p0],z
+       lda #0
        sta groot
        sta groot+1
        lda p0
        ldx p0+1
        rts

; dict_new -> A/X ref (empty dict)
dict_new:
        lda #10
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_DICT
        jsr alloc
        lda p0
        ldx p0+1
        rts

; seq_grow - p0 = list or dict whose array (+8) is full; +4 = used, +6 = capacity, in
; units of t5 bytes (2 list, 4 dict). The object ref must be in r0. p0 stays valid.
seq_grow:
        ldz #6
        lda [p0],z
        sta t1
        inz
        lda [p0],z
        sta t1+1
        ; new capacity = cap * 2 + 4 (lists) / + 2 (dicts: pairs)
        asw t1
        lda #4
        ldx t5
        cpx #4
        bne +
        lda #2
+       clc
        adc t1
        sta t1
        bcc +
        inc t1+1
+       lda t1
        sta nitems
        lda t1+1
        sta nitems+1
        lda t5
        cmp #4
        bne +
        asw nitems
+       lda t1
        pha
        lda t1+1
        pha
        lda t5
        pha
        jsr arr_new                     ; may collect; r0 keeps the object alive
        sta r3
        stx r3+1
        pla
        sta t5
        pla
        sta t1+1
        pla
        sta t1
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ; copy used * t5 bytes from the old array
        ldz #8
        lda [p0],z
        sta t2
        inz
        lda [p0],z
        sta t2+1
        beq _noold
        ldz #4
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        asw t0
        lda t5
        cmp #4
        bne +
        asw t0
+       lda t0
        ora t0+1
        beq _free
        clc
        lda t2
        adc #4
        sta fp0
        lda t2+1
        adc #0
        sta fp0+1
        clc
        lda r3
        adc #4
        sta fp1
        lda r3+1
        adc #0
        sta fp1+1
        lda #HEAP_BANK
        sta fp0+2
        sta fp1+2
        lda #0
        sta fp0+3
        sta fp1+3
        jsr dma_copy
_free:  lda t2
        ldx t2+1
        jsr free_obj
_noold: lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #6
        lda t1
        sta [p0],z
        inz
        lda t1+1
        sta [p0],z
        inz
        lda r3
        sta [p0],z
        inz
        lda r3+1
        sta [p0],z
        lda #0
        sta r3
        sta r3+1
        rts

; list_append - r0 = list, r1 = item
list_append:
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        ldz #6
        cmp [p0],z
        bne _room
        ldz #5
        lda [p0],z
        ldz #7
        cmp [p0],z
        bne _room
        lda #2
        sta t5
        jsr seq_grow
_room:  ; items[len] = r1; len += 1
        jsr list_item_ptr_end
        ldz #0
        lda r1
        sta [p1],z
        inz
        lda r1+1
        sta [p1],z
        ldz #4
        lda [p0],z
        clc
        adc #1
        sta [p0],z
        inz
        lda [p0],z
        adc #0
        sta [p0],z
        rts

; p1 = &items[len] of the list p0
list_item_ptr_end:
        ldz #4
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
; p1 = &items[t0] of the list (or dict, with t0 = 2 * pair) p0
list_item_ptr:
        ldz #8
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        lda t0
        asl
        sta t1
        lda t0+1
        rol
        sta t1+1
        clc
        lda p1
        adc t1
        sta p1
        lda p1+1
        adc t1+1
        sta p1+1
        clc
        lda p1
        adc #4
        sta p1
        bcc +
        inc p1+1
+       rts

; dict_find - r0 = dict, r1 = key -> C clear if found, t3 = pair index, p1 -> pair
dict_find:
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        sta t4
        inz
        lda [p0],z
        sta t4+1
        lda #0
        sta t3
        sta t3+1
_loop:  lda t3
        cmp t4
        bne +
        lda t3+1
        cmp t4+1
        bne +
        sec
        rts
+       lda r0
        ldx r0+1
        sta p0
        stx p0+1
        lda t3
        asl
        sta t0
        lda t3+1
        rol
        sta t0+1
        jsr list_item_ptr
        ldz #0
        lda [p1],z
        sta r3
        inz
        lda [p1],z
        sta r3+1
        lda r3
        cmp r1
        bne _slow
        lda r3+1
        cmp r1+1
        beq _hit
_slow:  lda r1
        sta r2
        lda r1+1
        sta r2+1
        lda t3
        pha
        lda t3+1
        pha
        lda t4
        pha
        lda t4+1
        pha
        jsr obj_eq
        pla
        sta t4+1
        pla
        sta t4
        pla
        sta t3+1
        pla
        sta t3
        bcs _hit2
        inw t3
        bra _loop
_hit2:  lda r0                          ; recompute p1 (obj_eq clobbered it)
        ldx r0+1
        sta p0
        stx p0+1
        lda t3
        asl
        sta t0
        lda t3+1
        rol
        sta t0+1
        jsr list_item_ptr
_hit:   lda #0
        sta r3
        sta r3+1
        clc
        rts

; dict_get - r0 = dict, r1 = key -> C clear and A/X = value if found
dict_get:
        jsr dict_find
        bcs +
        ldz #3
        lda [p1],z
        tax
        dez
        lda [p1],z
        clc
+       rts

; dict_set - r0 = dict, r1 = key, r2 = value
dict_set:
        lda r2                          ; dict_find's comparisons use r2/r3
        sta groot+14
        lda r2+1
        sta groot+15
        jsr dict_find
        php
        lda groot+14
        sta r2
        lda groot+15
        sta r2+1
        lda #0
        sta groot+14
        sta groot+15
        plp
        bcs _new
        ldz #2
        lda r2
        sta [p1],z
        inz
        lda r2+1
        sta [p1],z
        rts
_new:   lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        ldz #6
        cmp [p0],z
        bne _room
        ldz #5
        lda [p0],z
        ldz #7
        cmp [p0],z
        bne _room
        lda #4
        sta t5
        lda r2                          ; obj_eq may have used r2/r3: keep the value safe
        pha
        lda r2+1
        pha
        jsr seq_grow
        pla
        sta r2+1
        pla
        sta r2
_room:  lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        asl
        sta t0
        inz
        lda [p0],z
        rol
        sta t0+1
        jsr list_item_ptr
        ldz #0
        lda r1
        sta [p1],z
        inz
        lda r1+1
        sta [p1],z
        inz
        lda r2
        sta [p1],z
        inz
        lda r2+1
        sta [p1],z
        ldz #4
        lda [p0],z
        clc
        adc #1
        sta [p0],z
        inz
        lda [p0],z
        adc #0
        sta [p0],z
        rts

;---------------------------------------------------------------------------------------
; obj_eq - r2 == r3 -> C set if equal. Uses r2, r3 (restored), p0-p3, t0-t2.
;---------------------------------------------------------------------------------------
obj_eq:
        lda r2
        cmp r3
        bne +
        lda r2+1
        cmp r3+1
        bne +
        sec
        rts
+       lda r2
        ldx r2+1
        jsr type_of
        sta t2
        lda r3
        ldx r3+1
        jsr type_of
        sta t2+1
        ; numbers (int, bool) compare by value
        lda t2
        cmp #T_FLOAT
        beq _flt
        jsr is_inttype
        bcc _notnum
        lda t2+1
        cmp #T_FLOAT
        beq _flt
        jsr is_inttype
        bcc _ne
        lda r2
        ldx r2+1
        jsr int_val
        ldq acc
        stq acc3
        lda r3
        ldx r3+1
        jsr int_val
        ldq acc
        cpq acc3
        bne _ne
        sec
        rts
_notnum:
        lda t2
        cmp t2+1
        bne _ne
        cmp #T_STR
        bne +
        jmp str_eq
+       cmp #T_TUPLE
        beq _seq
        cmp #T_LIST
        beq _seq
        cmp #T_DICT
        beq _dict
        cmp #T_INST
        bne _ne
        jmp inst_eq
_ne:    clc
        rts
_flt:   jmp float_eq
_dict:  jmp dict_eq
_seq:   ; same length, then item by item
        jsr seq_info2
        lda t0
        cmp t1
        bne _ne
        lda t0+1
        cmp t1+1
        bne _ne
        lda #0
        sta t2
        sta t2+1
_item:  lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        bne +
        sec
        rts
+       ; push state, compare items t2
        lda r2
        pha
        lda r2+1
        pha
        lda r3
        pha
        lda r3+1
        pha
        lda t0
        pha
        lda t0+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        lda r2
        ldx r2+1
        jsr seq_get_t2
        pha
        phx
        lda r3
        ldx r3+1
        jsr seq_get_t2
        sta r3
        stx r3+1
        plx
        pla
        sta r2
        stx r2+1
        jsr obj_eq
        pla
        sta t2+1
        pla
        sta t2
        pla
        sta t0+1
        pla
        sta t0
        pla
        sta r3+1
        pla
        sta r3
        pla
        sta r2+1
        pla
        sta r2
        bcc _ne2
        inw t2
        bra _item
_ne2:   clc
        rts

; A = type -> C set for int and bool
is_inttype:
        cmp #T_INT
        beq +
        cmp #T_BOOL
        beq +
        clc
        rts
+       sec
        rts

; seq_info2: t0 = len(r2), t1 = len(r3) (list or tuple)
seq_info2:
        lda r3
        ldx r3+1
        jsr seq_len
        lda t0
        sta t1
        lda t0+1
        sta t1+1
        lda r2
        ldx r2+1
; seq_len - A/X = list/tuple/str/dict -> t0 = length (all keep it at +4)
seq_len:
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        sta t0
        inz
        lda [p0],z
        sta t0+1
        rts

; seq_get_t2 - A/X = list or tuple -> A/X = item t2 (no bounds check)
seq_get_t2:
        sta p0
        stx p0+1
        lda t2
        sta t0
        lda t2+1
        sta t0+1
; seq_get - p0 = list or tuple, t0 = index -> A/X = item
seq_get:
        ldz #0
        lda [p0],z
        cmp #T_TUPLE
        beq _tup
        jsr list_item_ptr
        ldz #1
        lda [p1],z
        tax
        dez
        lda [p1],z
        rts
_tup:   lda t0
        asl
        sta t1
        lda t0+1
        rol
        sta t1+1
        clc
        lda p0
        adc t1
        sta p1
        lda p0+1
        adc t1+1
        sta p1+1
        ldz #7
        lda [p1],z
        tax
        dez
        lda [p1],z
        rts

; dict_eq - same number of pairs, and every key of r2 maps to an equal value in r3
dict_eq:
        jsr seq_info2
        lda t0
        cmp t1
        bne _ne
        lda t0+1
        cmp t1+1
        bne _ne
        lda #0
        sta t2
        sta t2+1
_loop:  lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        bne +
        sec
        rts
+       lda r0
        pha
        lda r0+1
        pha
        lda r1
        pha
        lda r1+1
        pha
        lda r2
        pha
        lda r2+1
        pha
        lda r3
        pha
        lda r3+1
        pha
        lda t0
        pha
        lda t0+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        ; key/value of pair t2 in r2
        lda r2
        ldx r2+1
        sta p0
        stx p0+1
        lda t2
        asl
        sta t0
        lda t2+1
        rol
        sta t0+1
        jsr list_item_ptr
        ldz #0
        lda [p1],z
        sta r1
        inz
        lda [p1],z
        sta r1+1
        inz
        lda [p1],z
        pha
        inz
        lda [p1],z
        pha
        lda r3
        sta r0
        lda r3+1
        sta r0+1
        jsr dict_get
        bcs _miss
        sta r3
        stx r3+1
        pla
        sta r2+1
        pla
        sta r2
        jsr obj_eq
        bra _cont
_miss:  pla
        pla
        clc
_cont:  pla
        sta t2+1
        pla
        sta t2
        pla
        sta t0+1
        pla
        sta t0
        pla
        sta r3+1
        pla
        sta r3
        pla
        sta r2+1
        pla
        sta r2
        pla
        sta r1+1
        pla
        sta r1
        pla
        sta r0+1
        pla
        sta r0
        bcc _ne
        inw t2
        bra _loop
_ne:    clc
        rts

;---------------------------------------------------------------------------------------
; obj_truth - A/X = ref -> A = 1 (true) or 0, flags from A
;---------------------------------------------------------------------------------------
obj_truth:
        cpx #0
        bne _heap
        cmp #R_TRUE
        beq _t
        cmp #2
        bcc _f                          ; NULL
        beq _f                          ; None
        cmp #R_FALSE
        beq _f
        cmp #1                          ; small int 0
        beq _f
_t:     lda #1
        rts
_f:     lda #0
        rts
_heap:  bit #1
        bne _t                          ; small ints with a high byte are non-zero
        sta p0
        stx p0+1
        ldz #0
        lda [p0],z
        cmp #T_INT
        beq _t                          ; boxed ints are never zero
        cmp #T_FLOAT
        beq _float
        cmp #T_STR
        beq _len
        cmp #T_LIST
        beq _len
        cmp #T_TUPLE
        beq _len
        cmp #T_DICT
        beq _len
        cmp #T_INST
        bne _t
        lda p0
        ldx p0+1
        jmp inst_truth
_len:   ldz #4
        lda [p0],z
        inz
        ora [p0],z
        beq _f
        bra _t
_float: ldz #11                         ; +-0.0 is false
        lda [p0],z
        and #$7f
-       dez
        ora [p0],z
        cpz #4
        bne -
        cmp #0
        beq _f
        bra _t

;---------------------------------------------------------------------------------------
; string builder (SBUF in bank 1). sbp is the write pointer; sb_len = sbp - SBUF.
;---------------------------------------------------------------------------------------
sb_reset:
        lda #<SBUF
        sta sbp
        lda #>SBUF
        sta sbp+1
        lda #`SBUF
        sta sbp+2
        lda #0
        sta sbp+3
        rts

; sb_putc - append A; preserves A, X, Y
sb_putc:
        phz
        pha
        lda sbp+1
        cmp #>(SBUF + SBUF_SIZE - 1)
        bcs +
        pla
        pha
        ldz #0
        sta [sbp],z
        inw sbp
+       pla
        plz
        rts

; append the zero-terminated bank-0 string after the jsr
SBPRINT .macro text
        jsr sb_puts_inline
        .text \text, 0
        .endm
sb_puts_inline:
        pla
        sta t7
        pla
        sta t7+1
        ldy #1
-       lda (t7),y
        beq +
        jsr sb_putc
        iny
        bra -
+       tya
        clc
        adc t7
        tax
        lda t7+1
        adc #0
        pha
        phx
        rts

; sb_puts - append zero-terminated bank-0 string A/X
sb_puts:
        sta t7
        stx t7+1
        ldy #0
-       lda (t7),y
        beq +
        jsr sb_putc
        iny
        bne -
+       rts

; sb_put_str - append the chars of string A/X
sb_put_str:
        jsr str_info
-       lda str_len
        ora str_len+1
        beq +
        ldz #0
        lda [fp0],z
        jsr sb_putc
        inw fp0
        dew str_len
        bra -
+       rts

; sb_take - A/X = mark (sbp low word saved earlier): make a string of everything
; appended since, and rewind the builder to the mark. -> A/X = string ref
sb_take:
        sta fp2
        stx fp2+1
        lda #`SBUF
        sta fp2+2
        lda #0
        sta fp2+3
        sec
        lda sbp
        sbc fp2
        sta str_len
        lda sbp+1
        sbc fp2+1
        sta str_len+1
        lda fp2
        sta sbp
        lda fp2+1
        sta sbp+1
        jmp str_from_far

; sb_flush - print everything appended since mark A/X, and rewind to it
sb_flush:
        sta fp2
        stx fp2+1
        lda #`SBUF
        sta fp2+2
        lda #0
        sta fp2+3
        sec
        lda sbp
        sbc fp2
        sta t6
        lda sbp+1
        sbc fp2+1
        sta t6+1
        lda fp2
        sta sbp
        lda fp2+1
        sta sbp+1
        jmp put_far

; sb_int - append the decimal form of acc (signed 32-bit)
sb_int:
        bit acc+3
        bpl +
        lda #'-'
        jsr sb_putc
        jsr acc_neg
+       lda #0                          ; digits pushed on the CPU stack
        sta t3
-       ldq acc
        stq MULTINA
        lda #10
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
-       bit MATHBUSY
        bmi -
        ldq DIVOUT+4
        stq acc2
        stq MULTINA                     ; q * 10 -> remainder = acc - q * 10
        sec
        lda acc
        sbc MULTOUT
        ora #'0'
        pha
        inc t3
        ldq acc2
        stq acc
        lda acc
        ora acc+1
        ora acc+2
        ora acc+3
        bne --
-       pla
        jsr sb_putc
        dec t3
        bne -
        rts

; acc = -acc
acc_neg:
        sec
        lda #0
        sbc acc
        sta acc
        lda #0
        sbc acc+1
        sta acc+1
        lda #0
        sbc acc+2
        sta acc+2
        lda #0
        sbc acc+3
        sta acc+3
        rts

; sb_hex - append A as two hex digits
sb_hex:
        pha
        lsr
        lsr
        lsr
        lsr
        jsr _nib
        pla
        and #15
_nib:   cmp #10
        bcc +
        adc #'a' - '0' - 10 - 1
+       adc #'0'
        jmp sb_putc

;---------------------------------------------------------------------------------------
; obj_str / obj_repr - append str(x) / repr(x) to the string builder
;---------------------------------------------------------------------------------------
obj_str:
        pha
        phx
        jsr type_of
        cmp #T_STR
        beq _str
        cmp #T_INST
        beq _inst
        plx
        pla
        jmp obj_repr
_str:   plx
        pla
        jmp sb_put_str
_inst:  plx
        pla
        jmp inst_str

obj_repr:
        ldy rdepth
        cpy #20
        bcc +
        SBPRINT "..."
        rts
+       inc rdepth
        jsr _repr
        dec rdepth
        rts
_repr:  pha
        phx
        jsr type_of
        asl
        tay
        plx
        pla
        jmp repr_dispatch

repr_dispatch:                          ; Y = 2 * type
        pha
        lda repr_tab,y
        sta repr_vec
        lda repr_tab+1,y
        sta repr_vec+1
        pla
        jmp (repr_vec)
repr_vec:       .word 0
repr_tab:

        .word repr_null, repr_int, repr_str, repr_list
        .word repr_tuple, repr_dict, repr_null, repr_func
        .word repr_builtin, repr_bound, repr_class, inst_repr
        .word repr_range, repr_iter, repr_float, repr_none
        .word repr_bool, repr_slice

repr_null:
        SBPRINT "<NULL>"
        rts
repr_none:
        SBPRINT "None"
        rts
repr_bool:
        cmp #R_TRUE
        beq +
        SBPRINT "False"
        rts
+       SBPRINT "True"
        rts
repr_int:
        jsr int_val
        jmp sb_int
repr_str:
        jsr str_info
        ; use ' unless the string has ' and no "
        lda #0
        sta t1
        sta t1+1
        lda fp0
        sta fp1
        lda fp0+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        lda str_len
        sta t2
        lda str_len+1
        sta t2+1
-       lda t2
        ora t2+1
        beq +
        ldz #0
        lda [fp1],z
        cmp #"'"
        bne _nsq
        sta t1
_nsq:   cmp #'"'
        bne _ndq
        sta t1+1
_ndq:   inw fp1
        dew t2
        bra -
+       ldx #"'"
        lda t1
        beq +
        lda t1+1
        bne +
        ldx #'"'
+       stx t1
        txa
        jsr sb_putc
_ch:    lda str_len
        ora str_len+1
        beq _end
        ldz #0
        lda [fp0],z
        inw fp0
        dew str_len
        cmp t1
        beq _esc
        cmp #'\'
        beq _esc
        cmp #10
        beq _nl
        cmp #9
        beq _tab
        cmp #13
        beq _cr
        cmp #32
        bcc _hex
        cmp #127
        bcs _hex
        jsr sb_putc
        bra _ch
_esc:   pha
        lda #'\'
        jsr sb_putc
        pla
        jsr sb_putc
        bra _ch
_nl:    lda #'n'
        bra _esc2
_tab:   lda #'t'
        bra _esc2
_cr:    lda #'r'
_esc2:  pha
        lda #'\'
        jsr sb_putc
        pla
        jsr sb_putc
        bra _ch
_hex:   pha
        lda #'\'
        jsr sb_putc
        lda #'x'
        jsr sb_putc
        pla
        jsr sb_hex
        bra _ch
_end:   lda t1
        jmp sb_putc

repr_list:
        ldy #'['
        sty t5
        ldy #']'
        sty t5+1
        bra repr_seq
repr_tuple:
        ldy #'('
        sty t5
        ldy #')'
        sty t5+1
repr_seq:
        ; items are printed recursively: keep (ref, index, len, brackets) on the CPU stack
        sta r2
        stx r2+1
        jsr seq_len
        lda t5
        jsr sb_putc
        lda #0
        sta t2
        sta t2+1
_loop:  lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _done
+       lda t2
        ora t2+1
        beq +
        SBPRINT ", "
+       lda r2
        pha
        lda r2+1
        pha
        lda t0
        pha
        lda t0+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        lda t5
        pha
        lda t5+1
        pha
        lda r2
        ldx r2+1
        jsr seq_get_t2
        jsr obj_repr
        pla
        sta t5+1
        pla
        sta t5
        pla
        sta t2+1
        pla
        sta t2
        pla
        sta t0+1
        pla
        sta t0
        pla
        sta r2+1
        pla
        sta r2
        inw t2
        bra _loop
_done:  lda t5
        cmp #'('
        bne +
        lda t0                          ; one-item tuple: (x,)
        cmp #1
        bne +
        lda t0+1
        bne +
        lda #','
        jsr sb_putc
+       lda t5+1
        jmp sb_putc

repr_dict:
        sta r2
        stx r2+1
        jsr seq_len
        lda #'{'
        jsr sb_putc
        lda #0
        sta t2
        sta t2+1
_loop:  lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _done
+       lda t2
        ora t2+1
        beq +
        SBPRINT ", "
+       lda r2
        pha
        lda r2+1
        pha
        lda t0
        pha
        lda t0+1
        pha
        lda t2
        pha
        lda t2+1
        pha
        jsr _pair
        jsr obj_repr                    ; key
        SBPRINT ": "
        pla
        sta t2+1
        pla
        sta t2
        pla
        pla
        pla
        sta r2+1
        pla
        sta r2
        pha
        lda r2+1
        pha
        lda #0
        pha
        pha
        lda t2
        pha
        lda t2+1
        pha
        jsr _pair
        ldz #3
        lda [p1],z
        tax
        dez
        lda [p1],z
        jsr obj_repr                    ; value
        pla
        sta t2+1
        pla
        sta t2
        pla
        pla
        pla
        sta r2+1
        pla
        sta r2
        lda r2
        ldx r2+1
        jsr seq_len
        inw t2
        bra _loop
_done:  lda #'}'
        jmp sb_putc
_pair:  lda r2                          ; p1 -> pair t2, A/X = key
        ldx r2+1
        sta p0
        stx p0+1
        lda t2
        asl
        sta t0
        lda t2+1
        rol
        sta t0+1
        jsr list_item_ptr
        ldz #1
        lda [p1],z
        tax
        dez
        lda [p1],z
        rts

repr_func:
        sta p0
        stx p0+1
        SBPRINT "<function "
        ldz #9
        lda [p0],z
        tax
        dez
        lda [p0],z
        jsr sb_put_str
        lda #'>'
        jmp sb_putc

repr_builtin:
        sta p0
        stx p0+1
        ldz #6                          ; the name (lo, then hi: pulled back as X, A)
        lda [p0],z
        pha
        inz
        lda [p0],z
        pha
        ldz #5
        lda [p0],z
        and #BF_TYPE
        bne _type
        #SBPRINT "<built-in function "
        plx
        pla
        jsr sb_put_str
        lda #'>'
        jmp sb_putc
_type:  #SBPRINT "<class '"
        bra repr_cls_tail

repr_class:
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        pha
        inz
        lda [p0],z
        pha
        #SBPRINT "<class '"
repr_cls_tail:
        plx
        pla
        jsr sb_put_str
        #SBPRINT "'>"
        rts

repr_bound:
        SBPRINT "<bound method>"
        rts

repr_range:
        sta p0
        stx p0+1
        lda p0
        pha
        lda p0+1
        pha
        SBPRINT "range("
        plx
        pla
        sta p3
        stx p3+1
        ldz #4
        jsr _dw
        jsr sb_int
        SBPRINT ", "
        ldz #8
        jsr _dw
        jsr sb_int
        ldz #12
        jsr _dw
        lda acc
        cmp #1
        bne +
        lda acc+1
        ora acc+2
        ora acc+3
        beq ++
+       SBPRINT ", "
        jsr sb_int
+       lda #')'
        jmp sb_putc
_dw:    ldx #0
-       lda [p3],z
        sta acc,x
        inz
        inx
        cpx #4
        bne -
        rts

repr_iter:
        SBPRINT "<iterator>"
        rts

repr_slice:
        SBPRINT "<slice>"
        rts
