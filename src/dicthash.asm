;=======================================================================================
; Dict lookups by hash (resident part 1).
;
; A dict keeps its pairs in insertion order (obj.asm: +4 count, +8 the pair array); a
; dict of DH_MIN pairs or more also has an index at +10: a T_ARR with the mask at +4
; and then 2^n slots of 16 bits (0 = empty, i + 1 = pair i), open addressing with
; linear probing, at most half full. Smaller dicts (instance attributes, keyword
; arguments) have none and are searched pair by pair (dict_scan).
;
; The index is updated when a pair is added (dict_set -> dict_index_add) and rebuilt
; when it fills up or a pair is removed (dict_reindex). Lists, dicts and sets cannot
; be keys (TypeError, as in CPython).
;=======================================================================================
DH_MIN          = 8                     ; dicts with this many pairs get an index

dh_slot:        .word 0                 ; dict_find's miss in an index: the free slot

; SAVE_R / REST_R - r0-r3 on the CPU stack (REST_R keeps A; uses X, t7)
SAVE_R  .macro
        ldx #7
-       lda r0,x
        pha
        dex
        bpl -
        .endm
REST_R  .macro
        sta t7
        ldx #0
-       pla
        sta r0,x
        inx
        cpx #8
        bne -
        lda t7
        .endm

;---------------------------------------------------------------------------------------
; dict_find - r0 = dict, r1 = key -> C clear if found, t3 = pair index, p1 -> pair.
; Keeps r0, r1. (A key's __eq__ / __hash__ may run Python code.)
;---------------------------------------------------------------------------------------
dict_find:
        lda r1
        ldx r1+1
        jsr need_hashable
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #11
        lda [p0],z
        bne _index
        jmp dict_scan
_index: lda r1
        ldx r1+1
        jsr obj_hash
        sta t5
        stx t5+1
        jsr dh_mask                     ; t5 = the first slot
_probe: jsr dh_entry                    ; A/X = slot t5's entry, p2 -> it
        cpx #0
        bne _full
        cmp #0
        bne _full
        lda t5                          ; an empty slot: not there
        sta dh_slot
        lda t5+1
        sta dh_slot+1
        sec
        rts
_full:  sec                             ; pair = entry - 1
        sbc #1
        sta t3
        txa
        sbc #0
        sta t3+1
        jsr dh_pair                     ; p1 -> the pair, r3 = its key
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
        lda t3                          ; (obj_eq uses the t registers, may run Python)
        pha
        lda t3+1
        pha
        lda t5
        pha
        lda t5+1
        pha
        jsr obj_eq
        pla
        sta t5+1
        pla
        sta t5
        pla
        sta t3+1
        pla
        sta t3
        bcs _hit2
        inw t5                          ; the next slot
        jsr dh_mask
        bra _probe
_hit2:  jsr dh_pair
_hit:   lda #0
        sta r3
        sta r3+1
        clc
        rts

; dh_pair - p1 -> pair t3 of dict r0, r3 = its key
dh_pair:
        lda r0
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
        rts

; dh_index - p3 = the index of dict r0 (p0 = the dict)
dh_index:
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #10
        lda [p0],z
        sta p3
        inz
        lda [p0],z
        sta p3+1
        rts

; dh_mask - t5 &= the mask of dict r0's index (p3 = the index)
dh_mask:
        jsr dh_index
        ldz #4
        lda [p3],z
        and t5
        sta t5
        inz
        lda [p3],z
        and t5+1
        sta t5+1
        rts

; dh_entry - A/X = slot t5 of dict r0's index; p2 -> the slot (-6)
dh_entry:
        jsr dh_index
        lda t5
        asl
        sta p2
        lda t5+1
        rol
        sta p2+1
        clc
        lda p2
        adc p3
        sta p2
        lda p2+1
        adc p3+1
        sta p2+1
        ldz #7
        lda [p2],z
        tax
        dez
        lda [p2],z
        rts

;---------------------------------------------------------------------------------------
; dict_index_add - (dict_set, after appending pair count - 1 to dict r0) enter it in the
; index at the slot dict_find found free, or build the index when the dict has grown
; to DH_MIN pairs or the index would be more than half full
;---------------------------------------------------------------------------------------
dict_index_add:
        jsr dh_index
        ldz #4                          ; t4 = count
        lda [p0],z
        sta t4
        inz
        lda [p0],z
        sta t4+1
        lda p3+1
        bne +
        lda t4+1                        ; no index yet
        bne dict_reindex
        lda t4
        cmp #DH_MIN
        bcs dict_reindex
        rts
+       asw t4                          ; 2 * count > slots (= mask + 1)?
        ldz #5
        lda [p3],z
        cmp t4+1
        bcc dict_reindex
        bne +
        dez
        lda [p3],z
        cmp t4
        bcc dict_reindex
+       lda dh_slot
        sta t5
        lda dh_slot+1
        sta t5+1
        jsr dh_entry                    ; p2 -> the free slot
        ldz #4                          ; entry = count (the new pair's index + 1)
        lda [p0],z
        ldz #6
        sta [p2],z
        ldz #5
        lda [p0],z
        ldz #7
        sta [p2],z
        rts

;---------------------------------------------------------------------------------------
; dict_reindex - (re)build the index of dict r0 for its pairs (none below DH_MIN).
; Keeps r0-r3.
;---------------------------------------------------------------------------------------
dict_reindex:
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #10                         ; no index while it is rebuilt
        lda #0
        sta [p0],z
        inz
        sta [p0],z
        ldz #4
        lda [p0],z
        sta t4
        inz
        lda [p0],z
        sta t4+1
        bne +
        lda t4
        cmp #DH_MIN
        bcs +
        rts
+       asw t4                          ; slots = the power of two > 2 * count (>= 16):
        lda #16                         ; below the rebuild point (dict_index_add)
        sta t5
        lda #0
        sta t5+1
-       lda t4+1                        ; while slots <= 2 * count: double
        cmp t5+1
        bcc +
        bne _dbl
        lda t4
        cmp t5
        bcc +
_dbl:   asw t5
        bra -
+       lda t5                          ; the index: 6 + 2 * slots bytes, zeroed
        asl
        sta alloc_size
        lda t5+1
        rol
        sta alloc_size+1
        clc
        lda alloc_size
        adc #6
        sta alloc_size
        bcc +
        inc alloc_size+1
+       lda t5
        pha
        lda t5+1
        pha
        lda #T_ARR
        jsr alloc
        pla
        sta t5+1
        pla
        sta t5
        ldz #4                          ; mask = slots - 1
        sec
        lda t5
        sbc #1
        sta [p0],z
        inz
        lda t5+1
        sbc #0
        sta [p0],z
        lda p0
        sta p3
        lda p0+1
        sta p3+1
        lda r0
        ldx r0+1
        sta p0
        stx p0+1
        ldz #10
        lda p3
        sta [p0],z
        inz
        lda p3+1
        sta [p0],z
        ; enter the pairs: pair i -> the first free slot from hash(key i)
        lda #0
        pha
        pha                             ; [i lo][i hi] on the CPU stack
_pair:  pla
        sta t3+1
        pla
        sta t3
        lda r0
        ldx r0+1
        jsr seq_len                     ; t0 = count
        lda t3
        cmp t0
        bne +
        lda t3+1
        cmp t0+1
        bne +
        rts
+       lda t3
        pha
        lda t3+1
        pha
        lda r3                          ; (keep r3: dh_pair uses it)
        pha
        lda r3+1
        pha
        jsr dh_pair
        lda r3
        ldx r3+1
        jsr obj_hash                    ; (may run Python: __hash__)
        sta t5
        stx t5+1
        pla
        sta r3+1
        pla
        sta r3
        jsr dh_mask
-       jsr dh_entry
        cpx #0
        bne +
        cmp #0
        beq _put
+       inw t5
        jsr dh_mask
        bra -
_put:   pla                             ; entry = i + 1
        tax
        pla
        pha
        phx
        clc
        adc #1
        ldz #6
        sta [p2],z
        txa
        adc #0
        ldz #7
        sta [p2],z
        pla                             ; i += 1
        tax
        pla
        clc
        adc #1
        pha
        txa
        adc #0
        pha
        bra _pair

;---------------------------------------------------------------------------------------
; need_hashable - A/X: TypeError "unhashable type" for a list, dict or set, and for an
; instance whose class defines __eq__ but not __hash__ (as CPython, which sets its
; __hash__ to None). Keeps A/X and r0-r3.
;---------------------------------------------------------------------------------------
nh_obj:         .word 0
need_hashable:
        pha
        phx
        jsr type_of
        cmp #T_LIST
        beq _no
        cmp #T_DICT
        beq _no
        cmp #T_SET
        beq _no
        cmp #T_INST
        beq _inst
_ok:    plx
        pla
        rts
_inst:  plx
        pla
        sta nh_obj
        stx nh_obj+1
        pha
        phx
        #SAVE_R
        lda #<S_HASH
        ldx #>S_HASH
        jsr nh_lookup
        bcc _has
        lda #<S_EQ
        ldx #>S_EQ
        jsr nh_lookup
        bcc _uneq
_has:   #REST_R
        bra _ok
_uneq:  #REST_R
_no:    jsr sb_mark_t5
        #SBPRINT "unhashable type: '"
        plx
        pla
        jsr sb_type_name
        lda #"'"
        jsr sb_putc
        lda #EXC_TYPE
        jmp raise_sb

; nh_lookup - does the class of instance nh_obj have symbol A/X? -> C clear if so
nh_lookup:
        jsr sym_name
        sta r1
        stx r1+1
        lda nh_obj
        ldx nh_obj+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        sta r2
        inz
        lda [p0],z
        sta r2+1
        jmp class_lookup

;---------------------------------------------------------------------------------------
; obj_hash - A/X = a hashable value (need_hashable) -> A/X = its hash (16 bits).
; Values that are == hash alike: 1, 1.0 and True; -1 hashes as -2, as in CPython
; (and float_hash). An instance hashes by its __hash__, else by identity. Keeps r0-r3.
;---------------------------------------------------------------------------------------
obj_hash:
        bit #1
        bne _small
        cpx #0
        bne _heap
        cmp #R_TRUE
        bne +
        lda #1                          ; (X = 0)
        rts
+       cmp #R_FALSE
        bne +
        lda #0
        rts
+       lda #$5a                        ; None
        rts
_small: cpx #$ff                        ; ref $ffff = -1
        bne +
        cmp #$ff
        bne +
        lda #$fe
        rts
+       pha                             ; value = ref >> 1 (signed)
        txa
        cmp #$80
        ror a
        tax
        pla
        ror a
        rts
_heap:  sta t6
        stx t6+1
        jsr type_of
        tay
        lda t6
        ldx t6+1
        cpy #T_INT
        beq _int
        cpy #T_STR
        beq _str
        cpy #T_FLOAT
        beq _float
        cpy #T_TUPLE
        beq _tuple
        cpy #T_FSET
        beq _fset
        cpy #T_INST
        bne +
        jmp _inst
+       rts                             ; anything else: by identity
_int:   jsr is_big                      ; a big int: as its float
        bcc +
        jsr big_float
        sta t6
        stx t6+1
        jmp _float
+       jsr int_val
        lda acc
        and acc+1
        and acc+2
        and acc+3
        cmp #$ff
        bne +
        lda #$fe                        ; -1
        ldx #$ff
        rts
+       lda acc
        ldx acc+1
        rts
_fset:  jsr seq_len                     ; equal frozensets have the same size
        lda t0
        ldx t0+1
        rts
_float: #SAVE_R                         ; hash(x) as CPython: an int, hashed as one
        lda t6
        ldx t6+1
        jsr float_hash
        stx t6+1
        #REST_R
        ldx t6+1
        jmp obj_hash
_str:   jsr str_info                    ; len, then h = h * 31 + c for the first 32
        lda str_len
        sta t6
        lda str_len+1
        sta t6+1
        ldy #32                         ; Y = min(len, 32)
        lda str_len+1
        bne +
        lda str_len
        cmp #32
        bcs +
        tay
+       cpy #0
        beq _sdone
-       ldz #0
        lda [fp0],z
        jsr hash_mix
        inw fp0
        dey
        bne -
_sdone: lda t6
        ldx t6+1
        rts
_tuple: #PUSH                           ; h = len, then h = h * 31 ^ hash(item)
        jsr seq_len
        lda t0
        pha
        lda t0+1
        pha                             ; [h lo][h hi]
        lda #0
        pha
        pha                             ; [i lo][i hi]
_titem: pla
        sta t2+1
        pla
        sta t2
        #PEEK 0
        jsr seq_len
        lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        bne +
        pla                             ; done: h
        tax
        pla
        #DROP 1
        rts
+       lda t2
        pha
        lda t2+1
        pha
        #PEEK 0
        jsr seq_get_t2
        jsr obj_hash
        sta t4
        stx t4+1
        pla
        sta t2+1
        pla
        sta t2
        pla
        sta t6+1
        pla
        sta t6
        lda #0
        jsr hash_mix                    ; h * 31
        lda t6
        eor t4
        pha
        lda t6+1
        eor t4+1
        pha
        inw t2
        lda t2
        pha
        lda t2+1
        pha
        bra _titem
_inst:  #SAVE_R
        lda t6
        ldx t6+1
        sta r2
        stx r2+1
        lda #S_HASH
        jsr inst_unary
        bcs _noh
        stx t6+1                        ; its __hash__(): an int, hashed as one
        #REST_R
        ldx t6+1
        jmp obj_hash
_noh:   #REST_R                         ; no __hash__: by identity
        lda t6
        ldx t6+1
        rts

; hash_mix - t6 = t6 * 31 + A (16 bits); keeps Y
hash_mix:
        pha
        lda t6
        sta t7
        lda t6+1
        sta t7+1
        asw t6
        asw t6
        asw t6
        asw t6
        asw t6
        sec
        lda t6
        sbc t7
        sta t6
        lda t6+1
        sbc t7+1
        sta t6+1
        pla
        clc
        adc t6
        sta t6
        bcc +
        inc t6+1
+       rts
