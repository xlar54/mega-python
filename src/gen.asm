;=======================================================================================
; Generators. A function whose body has a yield (FF_GEN: the compiler's pre-scan finds
; it) makes a generator object when it is called (gen_create) instead of running.
;
; T_GEN: +4 the function, +6 a tuple of its saved stack slots (its locals, then what
; its expressions had pushed), +8 its saved exception handlers (a T_ARR of raw words,
; 3 per handler: ip, result slot - vsp, result slot - vfp), +10 the ip to resume at,
; +12 state (GS_*), +13 the number of saved handlers, +14 its frame while it runs.
;
; gen_resume rebuilds the frame on the value stack as
;     [generator][result slot][locals][temporaries]
; (the locals end just under the result slot, so vfp = result slot - 2 * nlocals) and
; pushes a call frame flagged FR_GEN, with FR_FORIT (a FOR_ITER resumed it: it runs in
; the VM loop like a call) or FR_NESTED (native code did: iter_next, send(); a run
; level of its own, like vm_call_nested). YIELD_VALUE saves what is under the result
; slot and returns like RETURN; a RETURN in a generator frame finishes it (gen_return).
; An exception that leaves the generator drops its frame on the way: the generator
; still says GS_RUN, and gen_alive tells that from a generator that really runs.
;=======================================================================================
GS_NEW          = 0
GS_SUSP         = 1
GS_RUN          = 2
GS_DONE         = 3
GEN_SIZE        = 16

gen_ref:        .word 0                 ; the generator being resumed / suspended
gen_sent:       .word 0                 ; the value a resumed yield returns
gen_exc:        .word 0                 ; or the exception it raises (throw(), close())
gen_mode:       .byte 0                 ; FR_FORIT or FR_NESTED
gen_c:          .byte 0
gen_n:          .word 0

; p0 = the generator gen_ref
gen_p0:
        lda gen_ref
        sta p0
        lda gen_ref+1
        sta p0+1
        rts

; gen_xfer - copy t0 bytes (t0 > 0) between the value stack (bank 0, at A/X) and the
; heap object p0 from +6: C clear = stack -> heap, C set = heap -> stack
gen_xfer:
        php
        sta fp0
        stx fp0+1
        lda #0
        sta fp0+2
        sta fp0+3
        sta fp1+3
        clc
        lda p0
        adc #6
        sta fp1
        lda p0+1
        adc #0
        sta fp1+1
        lda #HEAP_BANK
        sta fp1+2
        plp
        bcc +
        ldx #3                          ; swap: heap -> stack
-       lda fp0,x
        ldy fp1,x
        sta fp1,x
        tya
        sta fp0,x
        dex
        bpl -
+       jmp dma_copy

;---------------------------------------------------------------------------------------
; gen_resume - A = FR_FORIT / FR_NESTED, the generator on top of the stack, gen_sent =
; the value for its yield. Runs it until it yields or ends. An exhausted generator:
; FOR_ITER takes the loop's exit (ip points at its operand); native code gets C set.
;---------------------------------------------------------------------------------------
gen_resume:
        sta gen_mode
        #PEEK 0
        sta gen_ref
        stx gen_ref+1
        jsr gen_p0
        ldz #12
        lda [p0],z
        cmp #GS_RUN
        bne _state
        jsr gen_alive
        bcc _died
        #RAISE EXC_VALUE, "generator already executing"
_died:  jsr gen_end
        lda #GS_DONE
_state: cmp #GS_DONE
        bne _go
        lda gen_mode
        and #FR_NESTED
        bne _ndone
        lda #R_NONE                     ; FOR_ITER: drop it, leave the loop; SEND:
        ldx #0                          ; its result (None) instead of it
        jmp gen_exit
_ndone: jsr lev_leave
        lda #R_NONE
        ldx #0
        sec
        rts
_go:    pha                             ; (GS_NEW or GS_SUSP)
        ; room: the saved slots, the result slot and some
        ldz #6
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldz #4
        lda [p1],z
        asl
        sta gen_n                       ; bytes to restore
        inz
        lda [p1],z
        rol
        sta gen_n+1
        sec
        lda vsp
        sbc gen_n
        tax
        lda vsp+1
        sbc gen_n+1
        bcc _deep
        cmp #>(VSTACK + $100)
        bcc _deep
        lda frp+1
        cmp #>(FSTACK_END - 8)
        bcc +
        lda frp
        cmp #<(FSTACK_END - 8)
        bcc +
_deep:  jmp raise_recursion
+       ; the result slot
        lda #R_NONE
        ldx #0
        #PUSH
        lda vsp
        sta c_slot
        lda vsp+1
        sta c_slot+1
        ; the saved slots under it
        sec
        lda vsp
        sbc gen_n
        sta vsp
        lda vsp+1
        sbc gen_n+1
        sta vsp+1
        lda gen_n
        ora gen_n+1
        beq +
        lda gen_n
        sta t0
        lda gen_n+1
        sta t0+1
        lda p1
        sta p0
        lda p1+1
        sta p0+1
        lda vsp
        ldx vsp+1
        sec
        jsr gen_xfer
        jsr gen_p0
+       ; the frame
        ldz #0
        lda ip
        sta [frp],z
        inz
        lda ip+1
        sta [frp],z
        inz
        lda vfp
        sta [frp],z
        inz
        lda vfp+1
        sta [frp],z
        inz
        lda c_slot
        sta [frp],z
        inz
        lda c_slot+1
        sta [frp],z
        inz
        lda gen_mode
        ora #FR_GEN
        sta [frp],z
        ldz #14                         ; (gen_alive)
        lda frp
        sta [p0],z
        inz
        lda frp+1
        sta [p0],z
        clc
        lda frp
        adc #8
        sta frp
        bcc +
        inc frp+1
+       ; vfp = result slot - 2 * nlocals
        ldz #4
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldz #7
        lda [p1],z
        asl
        sta t0
        lda #0
        rol
        sta t0+1
        sec
        lda c_slot
        sbc t0
        sta vfp
        lda c_slot+1
        sbc t0+1
        sta vfp+1
        ldz #13                         ; its handlers (tail X, args.asm)
        lda [p0],z
        beq +
        jsr gen_hin
        jsr gen_p0
+
        ; run from where it stopped
        lda #GS_RUN
        ldz #12
        sta [p0],z
        ldz #10
        lda [p0],z
        sta ip
        inz
        lda [p0],z
        sta ip+1
        pla
        cmp #GS_NEW
        bne +
        ldz #4                          ; starting: ENTER_ENV takes the closure from
        lda [p0],z                      ; c_func, the function being entered
        sta c_func
        inz
        lda [p0],z
        sta c_func+1
        jmp vm_loop
+       lda gen_exc                     ; at a yield: throw() / close() raise there
        ora gen_exc+1
        bne _throw
        lda gen_sent                    ; else its value
        ldx gen_sent+1
        #PUSH
        jmp vm_loop
_throw: jmp gen_throw_at                ; (methods.asm: a yield from passes it on)

;---------------------------------------------------------------------------------------
; YIELD_VALUE - value -> (the generator's caller gets it; the sent value comes back)
;---------------------------------------------------------------------------------------
op_yield:
        sec                             ; fp2 -> this frame
        lda frp
        sbc #8
        sta fp2
        lda frp+1
        sbc #0
        sta fp2+1
        lda #<(FSTACK >> 16)
        sta fp2+2
        lda #0
        sta fp2+3
        ldz #4
        lda [fp2],z
        sta c_slot
        inz
        lda [fp2],z
        sta c_slot+1
        ldy #2                          ; the generator, above the result slot
        lda (c_slot),y
        sta gen_ref
        iny
        lda (c_slot),y
        sta gen_ref+1
        ; save the slots between the value and the result slot
        sec
        lda c_slot
        sbc vsp
        sta gen_n
        lda c_slot+1
        sbc vsp+1
        sta gen_n+1
        sec                             ; (bytes, less the value)
        lda gen_n
        sbc #2
        sta gen_n
        bcs +
        dec gen_n+1
+       lda gen_n+1
        lsr a
        sta nitems+1
        lda gen_n
        ror a
        sta nitems
        jsr tuple_new                   ; (may collect: all of it is on the stack)
        sta t1
        stx t1+1
        lda gen_n
        ora gen_n+1
        beq +
        lda gen_n
        sta t0
        lda gen_n+1
        sta t0+1
        clc
        lda vsp
        adc #2
        tay
        lda vsp+1
        adc #0
        tax
        tya
        clc
        jsr gen_xfer
+       jsr gen_p0
        ldz #6
        lda t1
        sta [p0],z
        inz
        lda t1+1
        sta [p0],z
        jsr gen_handlers_out
        jsr gen_p0
        ldz #10                         ; where it goes on
        lda ip
        sta [p0],z
        inz
        lda ip+1
        sta [p0],z
        lda #GS_SUSP
        ldz #12
        sta [p0],z
        ; return the value, as RETURN does
        #POP
        sta r0
        stx r0+1
        sec
        lda frp
        sbc #8
        sta frp
        lda frp+1
        sbc #0
        sta frp+1
        ldz #0
        lda [frp],z
        sta ip
        inz
        lda [frp],z
        sta ip+1
        inz
        lda [frp],z
        sta vfp
        inz
        lda [frp],z
        sta vfp+1
        ldz #6
        lda [frp],z
        sta c_flags
        lda c_slot
        sta vsp
        lda c_slot+1
        sta vsp+1
        lda r0
        ldx r0+1
        #POKE 0
        lda #0
        sta r0
        sta r0+1
        lda c_flags
        and #FR_NESTED
        bne _nested
        inw ip                          ; FOR_ITER: on into the loop body
        inw ip
        jmp vm_loop
_nested:
        #POP
        pha
        phx
        jsr lev_leave
        plx
        pla
        clc
        rts

; gen_handlers_out - (op_yield) the handlers of the frame fp2 -> the generator gen_ref
; (relative to the result slot c_slot), and off the handler stack
gen_handlers_out:
        lda #<(HSTACK >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        sta gen_c
        lda hsp                         ; count the handlers whose frp is this frame's
        sta fp1
        lda hsp+1
        sta fp1+1
_count: lda fp1
        cmp #<HSTACK
        bne +
        lda fp1+1
        cmp #>HSTACK
        beq _counted
+       sec
        lda fp1
        sbc #8
        sta fp1
        bcs +
        dec fp1+1
+       ldz #4
        lda [fp1],z
        cmp frp
        bne _counted
        inz
        lda [fp1],z
        cmp frp+1
        bne _counted
        inc gen_c
        bra _count
_counted:
        jsr gen_p0
        lda gen_c
        ldz #13
        sta [p0],z
        cmp #0
        bne +
        ldz #8
        sta [p0],z
        inz
        sta [p0],z
        rts
+       jmp gen_hout                    ; (copying them: tail X, args.asm)

;---------------------------------------------------------------------------------------
; gen_return - (op_return: a RETURN in a generator frame, r0 = the value, the frame
; popped, vsp = the result slot) the generator is finished
;---------------------------------------------------------------------------------------
gen_return:
        #PEEK 1
        sta p0
        stx p0+1
        jsr gen_end
        #DROP 1                         ; the result slot
        lda c_flags
        sta gen_mode
        and #FR_NESTED
        beq _loop
        jsr lev_leave
        lda r0
        ldx r0+1
        sec
        rts
_loop:  lda r0
        ldx r0+1
; gen_exit - leave a FOR_ITER / SEND loop (ip at its operand) for a finished generator
; on top: FOR_ITER drops it, SEND (gen_mode FR_SENDX) puts A/X there (its result)
gen_exit:
        pha
        lda gen_mode
        and #FR_SENDX
        bne +
        pla
        #DROP 1
        bra ++
+       pla
        #POKE 0
+       #FETCHW
        sta ip
        stx ip+1
        jmp vm_loop

;---------------------------------------------------------------------------------------
; entries: FOR_ITER (seq.asm) and native code (iter_next, send())
;---------------------------------------------------------------------------------------
gen_for_iter:                           ; the generator on top, ip at FOR_ITER's operand
        lda #R_NONE
        sta gen_sent
        lda #0
        sta gen_sent+1
        sta gen_exc
        sta gen_exc+1
        lda #FR_FORIT
        jmp gen_resume

; stubs: the handlers of a generator that yields inside a try (args.asm)
gen_hin:        #TAILCALL TAIL_X, xg_handlers_in
gen_hout:       #TAILCALL TAIL_X, xg_handlers_out
; and in overlay R (methods.asm): gen_create, gen_alive, gen_end, gen_next_native,
; gen_send_native, and the methods
