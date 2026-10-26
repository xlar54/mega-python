;=======================================================================================
; Sets (tail T; setsr.asm in overlay R has BUILD_SET and the entry stubs). A set is a dict whose keys are the members (values None) with F_SET
; in its header flags; a frozenset also has F_FROZEN. type_of tells them apart (T_SET,
; T_FSET), while the code that reads the header itself (the GC, truth, len) sees a
; dict. Lookups are the dict's (linear, with ==). Members keep insertion order.
;
; The operations build their results from lists of members (list_from_iterable) on the
; value stack, so a member's __eq__ can run Python code (and allocate) at any point.
;=======================================================================================

; set_new - A = flags (F_SET, or F_SET | F_FROZEN) -> A/X an empty set
set_new:
        pha
        jsr dict_new
        pla
        ldz #1
        ora [p0],z
        sta [p0],z
        lda p0
        ldx p0+1
        rts

; set_kind - A/X set -> A = its flags (F_SET, or F_SET | F_FROZEN)
set_kind:
        sta p0
        stx p0+1
        ldz #1
        lda [p0],z
        and #F_SET | F_FROZEN
        rts

; set_add - r0 = set, r1 = member to add (TypeError for lists, dicts and sets: dict_find)
set_add:
        lda #R_NONE
        sta r2
        lda #0
        sta r2+1
        jmp dict_set

; set_from_iter - A/X iterable, Y = flags -> A/X a new set of its items
set_from_iter:
        phy
        jsr list_from_iterable          ; (may run Python code: a user iterator)
        #PUSH                           ; [list]
        pla
        jsr set_new
        #PUSH                           ; [list][set]
        #PEEK 1
        #PUSH                           ; [list][set][list]
        lda #R_NONE
        ldx #0
        #PUSH                           ; [list][set][list][None]
        lda #0
        jsr set_addfrom
        #DROP 2
        #POP
        #DROP 1
        rts

; other_set - A/X: a set or frozenset as it is, anything else iterable as a new set
other_set:
        sta t6
        stx t6+1
        jsr type_of
        cmp #T_SET
        bcc +
        lda t6
        ldx t6+1
        rts
+       lda t6
        ldx t6+1
        ldy #F_SET
        jmp set_from_iter

;---------------------------------------------------------------------------------------
; set_addfrom - A = mode: add the items of a list to a set; value stack
; [result][src list][other]. Mode 0: all of them; 1: those in the set other; 2: those
; not in it. (sa_* are saved on the CPU stack around anything that may run Python.)
;---------------------------------------------------------------------------------------
sa_mode:        .byte 0
sa_i:           .word 0
SA_SAVE .macro
        lda sa_mode
        pha
        lda sa_i
        pha
        lda sa_i+1
        pha
        .endm
SA_REST .macro                          ; (keeps C)
        pla
        sta sa_i+1
        pla
        sta sa_i
        pla
        sta sa_mode
        .endm
set_addfrom:
        sta sa_mode
        lda #0
        sta sa_i
        sta sa_i+1
_loop:  #PEEK 1
        jsr seq_len
        lda sa_i
        cmp t0
        bne +
        lda sa_i+1
        cmp t0+1
        beq _done
+       lda sa_i
        sta t2
        lda sa_i+1
        sta t2+1
        #PEEK 1
        jsr seq_get_t2
        sta r1
        stx r1+1
        #SA_SAVE
        lda sa_mode
        beq _add
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_find                   ; C clear: found
        ldy #1
        bcc +
        iny                             ; Y = 1 found / 2 missing
+       #SA_REST
        cpy sa_mode
        bne _next
        #SA_SAVE
_add:   #PEEK 2
        sta r0
        stx r0+1
        jsr set_add
        #SA_REST
_next:  inc sa_i                        ; (inw is for the base page only)
        bne +
        inc sa_i+1
+       jmp _loop
_done:  rts

; sa_step - A = mode, Y = 0: add from a (other b) / 1: from b (other a); value stack
; [a][b][result]
sa_step:
        pha
        phy
        #PEEK 0
        #PUSH                           ; [a][b][res][res]
        ply
        phy
        cpy #0
        bne _b
        #PEEK 3
        bra _list
_b:     #PEEK 2
_list:  jsr list_from_iterable
        #PUSH                           ; [a][b][res][res][src]
        ply
        cpy #0
        bne _a
        #PEEK 3
        bra _other
_a:     #PEEK 4
_other: #PUSH                           ; [a][b][res][res][src][other]
        pla
        jsr set_addfrom
        #DROP 3
        rts

; set_op - A = 0 union, 1 intersection, 2 difference, 3 symmetric difference; r2, r3 =
; sets -> A/X a new set of r2's kind
set_op:
        pha
        lda r2
        ldx r2+1
        #PUSH                           ; [a]
        lda r3
        ldx r3+1
        #PUSH                           ; [a][b]
        #PEEK 1
        jsr set_kind
        jsr set_new
        #PUSH                           ; [a][b][res]
        pla
        beq _union
        cmp #3
        beq _sym
        ldy #0                          ; 1: a's in b, 2: a's not in b
        jsr sa_step
        bra _done
_union: ldy #0
        jsr sa_step
        lda #0
        ldy #1
        jsr sa_step
        bra _done
_sym:   lda #2
        ldy #0
        jsr sa_step
        lda #2
        ldy #1
        jsr sa_step
_done:  #POP
        #DROP 2
        rts

;---------------------------------------------------------------------------------------
; operators (from binop and compare, arith.asm): r2 is a set or frozenset
;---------------------------------------------------------------------------------------
xt_set_binop:
        lda bop_types+1
        cmp #T_SET
        bcc _no
        lda bop
        ldx #0
        cmp #BOP_OR
        beq _go
        inx
        cmp #BOP_AND
        beq _go
        inx
        cmp #BOP_SUB
        beq _go
        inx
        cmp #BOP_XOR
        beq _go
_no:    jmp binop_inst                  ; (TypeError)
_go:    txa
        jmp set_op

; xt_set_compare - bop 2 <, 3 >, 4 <=, 5 >=: subsets -> A = 1 / 0
xt_set_compare:
        lda r3
        ldx r3+1
        jsr type_of
        cmp #T_SET
        bcs +
        jmp raise_cmp_types
+       lda bop                         ; a > b is b < a
        lsr
        bcc +
        lda r2
        ldx r3
        sta r3
        stx r2
        lda r2+1
        ldx r3+1
        sta r3+1
        stx r2+1
+       lda r2                          ; Y = 1 if the lengths are equal
        ldx r2+1
        jsr seq_len
        lda t0
        sta t1
        lda t0+1
        sta t1+1
        lda r3
        ldx r3+1
        jsr seq_len
        ldy #0
        lda t0
        cmp t1
        bne +
        lda t0+1
        cmp t1+1
        bne +
        iny
+       lda bop
        cmp #4
        bcs +
        tya                             ; < and >: equal sizes are not a proper subset
        bne _no
+       lda #2                          ; a <= b: nothing of a outside b
        jsr set_op
        jsr seq_len
        lda t0
        ora t0+1
        bne _no
        lda #1
        rts
_no:    lda #0
        rts

;---------------------------------------------------------------------------------------
; repr: {1, 2} / set() / frozenset({1, 2}) / frozenset()
;---------------------------------------------------------------------------------------
xt_repr_set:
        sta r2
        stx r2+1
        jsr type_of
        pha                             ; [kind]
        cmp #T_FSET
        bne +
        #SBPRINT "frozenset("
+       lda r2
        ldx r2+1
        jsr seq_len
        lda t0
        ora t0+1
        bne _items
        pla
        cmp #T_FSET
        beq _close
        #SBPRINT "set()"
        rts
_items: lda r2
        ldx r2+1
        jsr list_from_iterable
        #PUSH
        ldy #'{'
        sty t5
        ldy #'}'
        sty t5+1
        #PEEK 0
        jsr repr_seq
        #DROP 1
        pla
        cmp #T_FSET
        bne +
_close: lda #')'
        jmp sb_putc
+       rts

;---------------------------------------------------------------------------------------
; set() / frozenset() and the methods
;---------------------------------------------------------------------------------------
xt_set:
        #NARGS 0, 1
        ldy #F_SET
        bra set_ctor
xt_frozenset:
        #NARGS 0, 1
        ldy #F_SET | F_FROZEN
set_ctor:
        lda npos
        bne +
        tya
        jmp set_new
+       #ARG 0
        jmp set_from_iter

xt_set_copy:
        #NARGS 1, 1
        #ARG 0
        jsr set_kind
        tay
        #ARG 0
        jmp set_from_iter

; r0 = self, r1 = argument 1
set_self_arg:
        #NARGS 2, 2
        #ARG 0
        sta r0
        stx r0+1
        #ARG 1
        sta r1
        stx r1+1
        rts

xt_set_add_m:
        jsr set_self_arg
        jsr set_add
        #RET_NONE
xt_set_remove:
        jsr set_self_arg
        jsr dict_del
        bcs +
        #RET_NONE
+       jmp raise_key                   ; (KeyError(x): r1)
xt_set_discard:
        jsr set_self_arg
        jsr dict_del
        #RET_NONE

xt_set_pop:
        #NARGS 1, 1
        #ARG 0
        sta r0
        stx r0+1
        jsr seq_len
        lda t0
        ora t0+1
        bne +
        #RAISE EXC_KEY, "pop from an empty set"
+       lda #0                          ; the first member
        sta t0
        sta t0+1
        jsr list_item_ptr
        ldz #0
        lda [p1],z
        sta r1
        inz
        lda [p1],z
        sta r1+1
        jsr dict_del
        lda r1
        ldx r1+1
        rts

xt_set_clear:
        #NARGS 1, 1
        #ARG 0
        jmp dict_clear

; the methods with other iterables: A = op (set_op) | $20 (other op self) | $40
; (return whether the result is empty) | $80 (make self the result, return None).
; union, intersection, difference and their updates take any number of others (folded
; left to right; none: a copy); the rest exactly one.
sm_op:          .byte 0
sm_k:           .byte 0                 ; the number of others
sm_d:           .byte 0

xt_set_method:
        sta sm_op
        and #$63
        cmp #3
        bcs _one
        #NARGS 1, 64
        bra +
_one:   #NARGS 2, 2
+       ldy #0                          ; push self and the others first (converting one
        lda npos                        ; may run Python code)
        sta sm_k
-       lda argv+1,y
        tax
        lda argv,y
        phy
        #PUSH
        ply
        iny
        iny
        dec sm_k
        bne -
        ldx npos                        ; [self][other 1]...[other k]
        dex
        stx sm_k
        lda #0                          ; each other as a set, in its slot
        sta sm_d
-       lda sm_d
        cmp sm_k
        bcs _fold
        jsr _slot
        jsr other_set
        pha
        jsr _ptr
        pla
        sta (vsp),y
        iny
        txa
        sta (vsp),y
        inc sm_d
        bra -
_fold:  lda sm_k                        ; none: a copy of self
        bne _step
        jsr _slot
        sta r2
        stx r2+1
        sta r3
        stx r3+1
        lda #0
        jsr set_op
        bra _res
_step:  dec sm_d                        ; the result so far (slot d + 1, self first)
        lda sm_d                        ; with slot d, the result into slot d
        inc a
        jsr _slot_a
        sta r2
        stx r2+1
        lda sm_d
        jsr _slot_a
        sta r3
        stx r3+1
        lda sm_op
        and #$20
        beq +
        lda r2
        ldx r3
        sta r3
        stx r2
        lda r2+1
        ldx r3+1
        sta r3+1
        stx r2+1
+       lda sm_op
        and #3
        jsr set_op
        pha
        jsr _ptr
        pla
        sta (vsp),y
        iny
        txa
        sta (vsp),y
        lda sm_d
        bne _step
        #PEEK 0
_res:   sta r2                          ; r2 = the result
        stx r2+1
        lda sm_op
        bmi _update
        and #$40
        bne _empty
        jsr _drop
        lda r2
        ldx r2+1
        rts
_empty: lda r2
        ldx r2+1
        jsr seq_len
        jsr _drop
        lda t0
        ora t0+1
        beq +
        lda #R_FALSE
        ldx #0
        rts
+       lda #R_TRUE
        ldx #0
        rts
_update:                                ; self takes the result's members and index
        lda r2                          ; (+4..+11)
        sta p1
        lda r2+1
        sta p1+1
        lda sm_k
        jsr _slot_a
        sta p0
        stx p0+1
        ldz #4
-       lda [p1],z
        sta [p0],z
        inz
        cpz #12
        bne -
        jsr _drop
        #RET_NONE
_slot:  lda sm_d                        ; A/X = slot sm_d (_slot_a: slot A)
_slot_a:
        asl a
        tay
        iny
        lda (vsp),y
        tax
        dey
        lda (vsp),y
        rts
_ptr:   lda sm_d                        ; Y = slot sm_d's offset
        asl a
        tay
        rts
_drop:  lda sm_k                        ; drop self and the others
        inc a
        asl a
        clc
        adc vsp
        sta vsp
        bcc +
        inc vsp+1
+       rts

; xt_inplace - INPLACE b: x op= y for - & | ^ (b = the binop). A set (not a frozenset)
; with a set or frozenset on the right changes in place (C clear); anything else -> C
; set, bop = b, for the plain operator
xt_inplace:
        #FETCHB
        sta bop
        #PEEK 1
        jsr type_of
        cmp #T_SET
        bne _no
        #PEEK 0
        jsr type_of
        cmp #T_SET
        bcc _no
        #PEEK 1
        sta r2
        stx r2+1
        #PEEK 0
        sta r3
        stx r3+1
        ldx #3                          ; the set operation of the binop
-       lda _bops,x
        cmp bop
        beq +
        dex
        bne -
+       txa
        jsr set_op
        sta p1                          ; x takes the result's members and index
        stx p1+1
        #PEEK 1
        sta p0
        stx p0+1
        ldz #4
-       lda [p1],z
        sta [p0],z
        inz
        cpz #12
        bne -
        #DROP 1
        jsr clear_rregs
        clc
        rts
_no:    sec
        rts
_bops:  .byte BOP_OR, BOP_AND, BOP_SUB, BOP_XOR  ; (set_op's order)
