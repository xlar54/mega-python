;=======================================================================================
; Object heap (bank 4) and mark-sweep garbage collector.
;
; A value is a 16-bit ref:
;   odd             small int, value = ref >> 1 (signed 15 bit)
;   0               NULL (internal: unbound local, no value)
;   2 / 4 / 6       None / False / True
;   $0100-$FFFE     object at $40000 + ref (even aligned)
; Object header: +0 type, +1 flags, +2 size in bytes (word, header included).
;=======================================================================================
T_FREE          = 0
T_INT           = 1                     ; +4 dword
T_STR           = 2                     ; +4 len word, +6 chars
T_LIST          = 3                     ; +4 len, +6 cap, +8 items (T_ARR ref or 0)
T_TUPLE         = 4                     ; +4 len, +6 refs
T_DICT          = 5                     ; +4 count, +6 cap (pairs), +8 items (T_ARR), +10 index
T_ARR           = 6                     ; +4 refs
T_FUNC          = 7                     ; +4 code, +6 nargs, +7 nlocals, +8 name, +10 defaults, +12 params, +14 closure, +16 kwdefaults, +18 flags, +19 nkwonly
T_BUILTIN       = 8                     ; +4 id, +5 flags, +6 name
T_BOUND         = 9                     ; +4 self, +6 func
T_CLASS         = 10                    ; +4 name, +6 base, +8 dict
T_INST          = 11                    ; +4 class, +6 dict
T_RANGE         = 12                    ; +4 start, +8 stop, +12 step (dwords)
T_ITER          = 13                    ; +4 kind, +6 seq, +8 index/cur dword, +12 stop, +16 step
T_FLOAT         = 14                    ; +4 dword (reserved)
T_NONE          = 15                    ; pseudo types returned by type_of
T_BOOL          = 16
T_SLICE         = 17                    ; +4 start, +6 stop, +8 step (refs)
T_FILE          = 19                    ; +4 lfn, +5 mode, +6 flags, +8 pos, +9 len, +10 name
T_MODULE        = 20                    ; +4 name, +6 module symbol (module.asm)
T_DESC          = 21                    ; +4 kind, +6 function, +8 setter (desc.asm)
T_GEN           = 22                    ; +4 function, +6 saved slots, +8 handlers (gen.asm)
T_SET           = 23                    ; type_of only: a T_DICT with F_SET (keys -> None)
T_FSET          = 24                    ; type_of only: ... with F_SET | F_FROZEN (frozenset)
T_NTYPES        = 25                    ; (sets stay last: code tests >= T_SET for "a set")

F_MARK          = $80
F_PERM          = $40                   ; never freed (compile-time constants, builtins)
F_INTERN        = $20
F_SET           = $10                   ; (dicts) a set: the GC and len() see a dict
F_PROPS         = $10                   ; (classes) it or a base holds a property
F_FROZEN        = $08                   ; (sets) a frozenset

R_NULL          = 0
R_NONE          = 2
R_FALSE         = 4
R_TRUE          = 6

HEAP_LIMIT      = $FFF0

SETP0   .macro
        sta p0
        stx p0+1
        .endm
SETP1   .macro
        sta p1
        stx p1+1
        .endm
SETP2   .macro
        sta p2
        stx p2+1
        .endm
SETP3   .macro
        sta p3
        stx p3+1
        .endm

al_perm:        .byte 0                 ; F_PERM while compiling
al_type:        .byte 0
gc_free:        .word 0                 ; bytes free after the last collection
gc_ovf:         .byte 0

heap_init:
        lda #HEAP_BANK
        sta p0+2
        sta p1+2
        sta p2+2
        sta p3+2
        lda #0
        sta p0+3
        sta p1+3
        sta p2+3
        sta p3+3
        sta free_list
        sta free_list+1
        sta al_perm
        ; forget every root: a ref left by an earlier program (an exception leaves
        ; groot slots set) would point into the middle of a new object
        ldx #15
-       sta groot,x
        dex
        bpl -
        ldy #gc_roots_n-1
-       ldx gc_roots,y
        sta $1600,x
        sta $1600+1,x
        dey
        bpl -
        lda #<HEAP_START
        sta heap_top
        lda #>HEAP_START
        sta heap_top+1
        rts

al_tries:       .byte 0                 ; alloc: collections tried for this request
gc_stress:      .byte 0                 ; non-zero: a collection at every allocation
                                        ; (tools/run_tests.py --gc pokes it)
;---------------------------------------------------------------------------------------
; alloc - A = type, alloc_size = bytes (header included). Returns A/X = ref and p0
; pointing at the object, with the header written and the body zeroed.
;---------------------------------------------------------------------------------------
alloc:
        sta al_type
        lda alloc_size
        and #1
        beq +
        inw alloc_size
+       lda alloc_size+1
        bne +
        lda alloc_size
        cmp #6
        bcs +
        lda #6
        sta alloc_size
+       lda #0
        sta al_tries                    ; collections tried (not gc_n: the GC uses that)
        lda gc_stress                   ; (testing: collect before every allocation, so a
        beq _retry                      ; reference held unrooted across one shows; not
        lda al_perm                     ; for permanent objects: py_reset's setup, which
        bne _retry                      ; never collects for real on its fresh heap)
        jsr gc_collect
_retry:
        ; first fit through the free list; t1 = current, t2 = previous (0 = head)
        lda free_list
        sta t1
        lda free_list+1
        sta t1+1
        lda #0
        sta t2
        sta t2+1
_walk:  lda t1+1
        beq _bump
        lda t1
        sta p1
        lda t1+1
        sta p1+1
        ldz #2
        sec
        lda [p1],z
        sbc alloc_size
        sta t3
        inz
        lda [p1],z
        sbc alloc_size+1
        sta t3+1
        bcc _next                       ; too small
        ; remainder t3 >= 8: shrink the free block, take its tail
        lda t3+1
        bne _split
        lda t3
        cmp #8
        bcs _split
        ; take the whole block: unlink it
        ldz #2
        lda [p1],z
        sta alloc_size
        inz
        lda [p1],z
        sta alloc_size+1
        ldz #4
        lda [p1],z
        tax
        inz
        lda [p1],z
        tay
        lda t2+1
        bne +
        stx free_list
        sty free_list+1
        bra _take
+       lda t2
        sta p1
        lda t2+1
        sta p1+1
        ldz #4
        txa
        sta [p1],z
        inz
        tya
        sta [p1],z
_take:  lda t1
        ldx t1+1
        bra _init
_split: ldz #2
        lda t3
        sta [p1],z
        inz
        lda t3+1
        sta [p1],z
        clc
        lda t1
        adc t3
        pha
        lda t1+1
        adc t3+1
        tax
        pla
        bra _init
_next:  lda t1
        sta t2
        lda t1+1
        sta t2+1
        ldz #4
        lda [p1],z
        sta t1
        inz
        lda [p1],z
        sta t1+1
        bra _walk
_bump:  clc
        lda heap_top
        adc alloc_size
        sta t3
        lda heap_top+1
        adc alloc_size+1
        sta t3+1
        bcs _full
        cmp #>HEAP_LIMIT
        bcc _ok
        bne _full
        lda t3
        cmp #<HEAP_LIMIT
        bcc _ok
_full:  lda al_tries
        bne _oom
        inc al_tries
        jsr gc_collect
        lda gc_free+1                   ; under 1 KB free even after collecting: give
        cmp #>1024                      ; up rather than collect on every allocation
        bcc _oom
        jmp _retry
_oom:   jmp raise_memory
_ok:    lda heap_top
        ldx heap_top+1
        ldy t3
        sty heap_top
        ldy t3+1
        sty heap_top+1
_init:  sta p0
        stx p0+1
        pha
        phx
        ldz #0
        lda al_type
        sta [p0],z
        inz
        lda al_perm
        sta [p0],z
        inz
        lda alloc_size
        sta [p0],z
        inz
        lda alloc_size+1
        sta [p0],z
        ; zero the body
        lda alloc_size+1
        bne _big
        ldz #4
        lda #0
-       cpz alloc_size
        bcs _done
        sta [p0],z
        inz
        bra -
_big:   clc
        lda p0
        adc #4
        sta fp1
        lda p0+1
        adc #0
        sta fp1+1
        lda #HEAP_BANK
        sta fp1+2
        lda #0
        sta fp1+3
        sec
        lda alloc_size
        sbc #4
        sta t0
        lda alloc_size+1
        sbc #0
        sta t0+1
        lda #0
        jsr dma_fill
_done:  plx
        pla
        rts

; free_obj - A/X = ref: return an object to the free list now (it must be unreferenced)
free_obj:
        cpx #0
        beq +
        sta p1
        stx p1+1
        ldz #0
        lda #T_FREE
        sta [p1],z
        ldz #4
        lda free_list
        sta [p1],z
        inz
        lda free_list+1
        sta [p1],z
        lda p1
        sta free_list
        lda p1+1
        sta free_list+1
+       rts

;---------------------------------------------------------------------------------------
; gc_collect - mark from the roots, then sweep into a coalesced free list
;---------------------------------------------------------------------------------------
gc_collect:
        inw gc_count
        lda #0
        sta gc_msp
        sta gc_msp+1
        sta gc_ovf
        ; value stack (grows down: live slots are vsp .. VSTACK_END-1)
        lda vsp
        sta t4
        lda vsp+1
        sta t4+1
-       lda t4+1
        cmp #>VSTACK_END
        bcs _vs_done
        ldy #0
        lda (t4),y
        iny
        tax
        lda (t4),y
        sta t5
        txa
        ldx t5
        jsr gc_mark
        inw t4
        inw t4
        bra -
_vs_done:
        ; globals
        lda #<SYM_VAL
        sta fp2
        lda #>SYM_VAL
        sta fp2+1
        lda #`SYM_VAL
        sta fp2+2
        lda #0
        sta fp2+3
        lda nsyms
        sta t4
        lda nsyms+1
        sta t4+1
-       lda t4
        ora t4+1
        beq _g_done
        ldz #1
        lda [fp2],z
        tax
        dez
        lda [fp2],z
        jsr gc_mark
        inw fp2
        inw fp2
        dew t4
        bra -
_g_done:
        ; temp roots and other root variables
        ldy #0
-       phy
        lda groot+1,y
        tax
        lda groot,y
        jsr gc_mark
        ply
        iny
        iny
        cpy #16
        bcc -
        ldy #0
-       phy
        ldx gc_roots,y
        lda $1600+1,x
        pha
        lda $1600,x
        plx
        jsr gc_mark
        ply
        iny
        cpy #gc_roots_n
        bcc -
_drain: jsr gc_drain
        lda gc_ovf
        beq gc_sweep
        ; the mark stack overflowed: rescan the heap for marked objects
        lda #0
        sta gc_ovf
        lda #<HEAP_START
        sta t4
        lda #>HEAP_START
        sta t4+1
-       lda t4+1
        cmp heap_top+1
        bcc +
        bne _drain
        lda t4
        cmp heap_top
        bcs _drain
+       lda t4
        sta p2
        lda t4+1
        sta p2+1
        ldz #2
        clc
        lda [p2],z
        adc t4
        sta t6                          ; t6 = next object
        inz
        lda [p2],z
        adc t4+1
        sta t6+1
        ldz #1
        lda [p2],z
        bpl +
        dez
        lda [p2],z
        cmp #T_FREE
        beq +
        lda t4
        ldx t4+1
        jsr gc_children
        jsr gc_drain
+       lda t6
        sta t4
        lda t6+1
        sta t4+1
        bra -

; base-page offsets of extra root variables
gc_roots:       .byte <cur_exc, <r0, <r1, <r2, <r3, <c_func, <int_ref
gc_roots_n = * - gc_roots

gc_sweep:
        lda #0
        sta free_list
        sta free_list+1
        sta gc_free
        sta gc_free+1
        sta t5                          ; t5 = start of the current free run (0 = none)
        sta t5+1
        lda #<HEAP_START
        sta t4
        lda #>HEAP_START
        sta t4+1
_loop:  lda t4+1
        cmp heap_top+1
        bcc +
        bne _end
        lda t4
        cmp heap_top
        bcs _end
+       lda t4
        sta p2
        lda t4+1
        sta p2+1
        ldz #0
        lda [p2],z
        beq _dead                       ; T_FREE
        inz
        lda [p2],z
        bit #F_MARK | F_PERM
        beq _dead
        and #$ff ^ F_MARK
        sta [p2],z
        jsr _close
        bra _adv
_dead:  lda t5+1
        bne _adv
        lda t4
        sta t5
        lda t4+1
        sta t5+1
_adv:   ldz #2
        clc
        lda [p2],z
        adc t4
        sta t4
        inz
        lda [p2],z
        adc t4+1
        sta t4+1
        bra _loop
_end:   lda t5+1
        beq +
        lda t5                          ; a free run at the top: give it back
        sta heap_top
        lda t5+1
        sta heap_top+1
+       sec                             ; gc_free += the untouched top
        lda #<HEAP_LIMIT
        sbc heap_top
        tax
        lda #>HEAP_LIMIT
        sbc heap_top+1
        tay
        clc
        txa
        adc gc_free
        sta gc_free
        tya
        adc gc_free+1
        sta gc_free+1
        rts
; turn the run t5..t4 into one free block
_close: lda t5+1
        beq +
        lda t5
        sta p1
        lda t5+1
        sta p1+1
        ldz #0
        lda #T_FREE
        sta [p1],z
        inz
        lda #0
        sta [p1],z
        inz
        sec                             ; t6 = the run's size
        lda t4
        sbc t5
        sta t6
        lda t4+1
        sbc t5+1
        sta t6+1
        lda t6
        sta [p1],z
        inz
        lda t6+1
        sta [p1],z
        clc                             ; gc_free += it
        lda t6
        adc gc_free
        sta gc_free
        lda t6+1
        adc gc_free+1
        sta gc_free+1
        inz
        lda free_list
        sta [p1],z
        inz
        lda free_list+1
        sta [p1],z
        lda t5
        sta free_list
        lda t5+1
        sta free_list+1
        lda #0
        sta t5
        sta t5+1
+       rts

; gc_mark - A/X = ref: mark it; push it if it has children
gc_mark:
        cpx #0
        beq _no
        bit #1
        bne _no
        sta p1
        stx p1+1
        ldz #1
        lda [p1],z
        bmi _no
        ora #F_MARK
        sta [p1],z
        dez
        lda [p1],z
        tay
        lda gc_kind,y
        beq _no
        ; push
        lda gc_msp+1
        cmp #>MARKSTACK_N
        bcc +
        lda #1
        sta gc_ovf
_no:    rts
+       lda gc_msp
        asl
        sta fp1
        lda gc_msp+1
        rol
        clc
        adc #>(MARKSTACK & $ffff)
        sta fp1+1
        lda #`MARKSTACK
        sta fp1+2
        lda #0
        sta fp1+3
        ldz #0
        lda p1
        sta [fp1],z
        inz
        lda p1+1
        sta [fp1],z
        inw gc_msp
        rts

gc_drain:
        lda gc_msp
        ora gc_msp+1
        beq +
        dew gc_msp
        lda gc_msp
        asl
        sta fp1
        lda gc_msp+1
        rol
        clc
        adc #>(MARKSTACK & $ffff)
        sta fp1+1
        lda #`MARKSTACK
        sta fp1+2
        lda #0
        sta fp1+3
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        jsr gc_children
        bra gc_drain
+       rts

; gc_children - A/X = ref (marked): mark everything it references
gc_children:
        sta p2
        stx p2+1
        ldz #0
        lda [p2],z
        tay
        lda gc_kind,y
        cmp #1
        beq _seq
        cmp #2
        beq _tuple
        cmp #3
        beq _dict
        ; fixed ref fields: gc_kind = offset | count << 5 ... encoded as kind 4+: table
        cpy #T_ITER                     ; a dict iterator also holds its last key (+16)
        bne _fixed
        ldz #4
        lda [p2],z
        cmp #IT_DICT
        beq _view
        cmp #IT_ITEMS
        bcc _fixed
        cmp #IT_VALUES+1
        bcs _fixed
_view:  ldz #17
        lda [p2],z
        tax
        dez
        lda [p2],z
        jsr gc_mark                     ; (uses p1, fp1, Y)
        ldy #T_ITER
_fixed: tya
        tax
        lda gc_off,x
        sta p3
        lda gc_cnt,x
        sta gc_n
        lda #0
        sta gc_n+1
        clc
        lda p3
        adc p2
        sta p3
        lda p2+1
        adc #0
        sta p3+1
        jmp _refs
_seq:   ; list: items array at +8, len at +4
        ldz #4
        lda [p2],z
        sta gc_n
        inz
        lda [p2],z
        sta gc_n+1
_arr:   ldz #8
        lda [p2],z
        sta p3
        inz
        lda [p2],z
        sta p3+1
        beq _none
        ldz #1                          ; mark the array itself (no children of its own)
        lda [p3],z
        ora #F_MARK
        sta [p3],z
        clc
        lda p3
        adc #4
        sta p3
        bcc _refs
        inc p3+1
        bra _refs
_dict:  ldz #11                         ; the hash index (a T_ARR of slots, no refs)
        lda [p2],z
        tax
        dez
        lda [p2],z
        jsr gc_mark                     ; (uses p1, fp1)
        ldz #4
        lda [p2],z
        asl
        sta gc_n
        inz
        lda [p2],z
        rol
        sta gc_n+1
        bra _arr
_tuple: ldz #4
        lda [p2],z
        sta gc_n
        inz
        lda [p2],z
        sta gc_n+1
        clc
        lda p2
        adc #6
        sta p3
        lda p2+1
        adc #0
        sta p3+1
_refs:  lda gc_n
        ora gc_n+1
        beq _none
        ldz #1
        lda [p3],z
        tax
        dez
        lda [p3],z
        jsr gc_mark
        inw p3
        inw p3
        dew gc_n
        bra _refs
_none:  rts

; per type: 0 no children, 1 list, 2 tuple, 3 dict, 4 fixed fields (gc_off/gc_cnt)
gc_kind:
        .byte 0, 0, 0, 1, 2, 3, 0, 4    ; FREE INT STR LIST TUPLE DICT ARR FUNC
        .byte 0, 4, 4, 4, 0, 4, 0, 0    ; BUILTIN BOUND CLASS INST RANGE ITER FLOAT NONE
        .byte 0, 4, 4, 4, 4             ; BOOL SLICE SUPER FILE MODULE
        .byte 4, 4, 0, 0                ; DESC GEN (SET, FSET: dicts)
gc_off:
        .byte 0, 0, 0, 0, 0, 0, 0, 8
        .byte 0, 4, 4, 4, 0, 6, 0, 0
        .byte 0, 4, 4, 10, 4
        .byte 6, 4, 0, 0
gc_cnt:
        .byte 0, 0, 0, 0, 0, 0, 0, 5    ; (FUNC: name, defaults, params, closure, kwdefaults)
        .byte 0, 2, 3, 2, 0, 1, 0, 0
        .byte 0, 3, 2, 1, 1
        .byte 2, 3, 0, 0                ; (GEN: function, slots, handlers: a raw T_ARR)
