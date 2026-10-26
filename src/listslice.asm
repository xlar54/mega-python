;=======================================================================================
; List slice assignment, tail T: a[i:j] = iterable, a[i:j:k] = iterable, del a[i:j:k].
; A plain slice (step 1) rebuilds the list in place as a[:i] + values + a[j:]; an
; extended one stores (or deletes) item by item, so its size must match the values'.
;=======================================================================================
ls_del:         .byte 0                 ; deleting (no values)
ls_n:           .word 0                 ; extended: the number of positions
ls_i:           .word 0
ls_start:       .dword 0                ; slice_bounds' start, kept for a second walk

; xt_delslice - del r0[r1] (r0 a list, r1 a slice)
xt_delslice:
        lda #1
        sta ls_del
        lda #0
        sta r2
        sta r2+1
        bra ls_go
; xt_setslice - r0[r1] = r2
xt_setslice:
        lda #0
        sta ls_del
ls_go:  lda r0
        ldx r0+1
        #PUSH
        lda r1
        ldx r1+1
        #PUSH
        lda r2
        ldx r2+1
        #PUSH                           ; [list][slice][values]
        lda ls_del
        bne +
        #PEEK 0
        jsr list_from_iterable          ; (a copy, so a[:] = a works; may run Python)
        #POKE 0
+       jsr ls_len                      ; the bounds, for the list as it is now
        #PEEK 1
        sta r3
        stx r3+1
        jsr slice_bounds
        ldq sl_start
        stq ls_start
        lda sl_step
        dec a
        ora sl_step+1
        ora sl_step+2
        ora sl_step+3
        beq ls_plain
        jmp ls_ext

; step 1: a new list of a[:start] + values + a[stop:], then copied back into a
ls_plain:
        lda sl_stop                     ; (both clamped to 0..len: stop < start is empty)
        cmp sl_start
        lda sl_stop+1
        sbc sl_start+1
        bcs +
        lda sl_start
        sta sl_stop
        lda sl_start+1
        sta sl_stop+1
+       lda #0
        sta nitems
        sta nitems+1
        sta ls_i
        sta ls_i+1
        jsr list_new
        #PUSH                           ; [list][slice][values][new]
-       lda ls_i                        ; a[:start]
        cmp sl_start
        lda ls_i+1
        sbc sl_start+1
        bcs +
        jsr ls_take
        bra -
+       lda ls_del
        bne +
        #PEEK 0                         ; the values
        sta r0
        stx r0+1
        #PEEK 1
        jsr list_extend_r0
+       lda sl_stop                     ; a[stop:]
        sta ls_i
        lda sl_stop+1
        sta ls_i+1
-       jsr ls_len3
        lda ls_i
        cmp t5
        lda ls_i+1
        sbc t5+1
        bcs +
        jsr ls_take
        bra -
+       #PEEK 3                         ; a = new
        sta r0
        stx r0+1
        sta p0
        stx p0+1
        ldz #4
        lda #0
        sta [p0],z
        inz
        sta [p0],z
        #PEEK 0
        jsr list_extend_r0
ls_done:
        #DROP 4
        jmp clear_rregs

; ls_take - append a[ls_i] to the new list (on top of the stack), ls_i + 1
ls_take:
        #PEEK 0
        sta r0
        stx r0+1
        lda ls_i
        sta t2
        lda ls_i+1
        sta t2+1
        #PEEK 3
        jsr seq_get_t2
        sta r1
        stx r1+1
        jsr list_append
        inc ls_i
        bne +
        inc ls_i+1
+       rts

; ls_len - t5 = the list's length now (ls_len3: with the new list above the values)
ls_len3:
        #PEEK 3
        bra +
ls_len: #PEEK 2
+       sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        sta t5
        inz
        lda [p0],z
        sta t5+1
        rts

; an extended slice: count its positions, then store or delete at each
ls_ext: lda #0
        sta ls_n
        sta ls_n+1
-       jsr slice_more
        bcs +
        inc ls_n
        bne *+5
        inc ls_n+1
        jsr slice_step
        bra -
+       ldq ls_start
        stq sl_start
        lda #0
        sta ls_i
        sta ls_i+1
        lda ls_del
        bne _del
        #PEEK 0                         ; as many values as positions
        jsr seq_len
        lda t0
        cmp ls_n
        bne _size
        lda t0+1
        cmp ls_n+1
        beq _set
_size:  #RAISE EXC_VALUE, "attempt to assign sequence of wrong size to extended slice"
_set:   jsr slice_more
        bcs _done
        lda ls_i                        ; values[i] ...
        sta t2
        lda ls_i+1
        sta t2+1
        #PEEK 0
        jsr seq_get_t2
        pha
        phx
        #PEEK 2                         ; ... into a[position]
        sta p0
        stx p0+1
        lda sl_start
        sta t0
        lda sl_start+1
        sta t0+1
        jsr list_item_ptr
        ldz #1
        plx
        txa
        sta [p1],z
        dez
        pla
        sta [p1],z
        inc ls_i
        bne +
        inc ls_i+1
+       jsr slice_step
        bra _set
_del:   jsr slice_more                  ; ascending positions move down by the number
        bcs _done                       ; deleted before them (ls_i)
        #PEEK 2
        sta r0
        stx r0+1
        lda sl_start
        ldx sl_start+1
        bit sl_step+3
        bmi +
        sec
        sbc ls_i
        pha
        txa
        sbc ls_i+1
        tax
        pla
+       jsr list_del_at
        inc ls_i
        bne +
        inc ls_i+1
+       jsr slice_step
        bra _del
_done:  #DROP 3                         ; [list][slice][values]
        jmp clear_rregs
