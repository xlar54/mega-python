;======================================================================================
; Sets: the code is in tail T (sets.asm). Overlay R keeps BUILD_SET's handler (it
; goes on with vm_loop) and the stubs that lead into the tail.
;======================================================================================
set_build_op:                           ; BUILD_SET: the list on top -> a set
        #FETCHW
        #PEEK 0
        ldy #F_SET
        jsr sets_from_iter
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

set_binop:      #TAILCALL TAIL_T, xt_set_binop
set_compare:    #TAILCALL TAIL_T, xt_set_compare
repr_set:       #TAILCALL TAIL_T, xt_repr_set
bi_set:         #TAILCALL TAIL_T, xt_set
bi_frozenset:   #TAILCALL TAIL_T, xt_frozenset
bi_set_copy:    #TAILCALL TAIL_T, xt_set_copy
bi_set_add_m:   #TAILCALL TAIL_T, xt_set_add_m
bi_set_remove:  #TAILCALL TAIL_T, xt_set_remove
bi_set_discard: #TAILCALL TAIL_T, xt_set_discard
bi_set_pop:     #TAILCALL TAIL_T, xt_set_pop
bi_set_clear:   #TAILCALL TAIL_T, xt_set_clear
set_method:     #TAILCALL TAIL_T, xt_set_method
sets_from_iter: #TAILCALL TAIL_T, set_from_iter
; the methods with another iterable: A = the operation (sets.asm, xt_set_method)
bi_set_union:           lda #0
                        bra set_method
bi_set_intersection:    lda #1
                        bra set_method
bi_set_difference:      lda #2
                        bra set_method
bi_set_symdiff:         lda #3
                        bra set_method
bi_set_update:          lda #$80
                        bra set_method
bi_set_inter_update:    lda #$81
                        bra set_method
bi_set_diff_update:     lda #$82
                        bra set_method
bi_set_symdiff_update:  lda #$83
                        bra set_method
bi_set_issubset:        lda #$42
                        bra set_method
bi_set_issuperset:      lda #$62
                        bra set_method
bi_set_isdisjoint:      lda #$41
                        bra set_method
