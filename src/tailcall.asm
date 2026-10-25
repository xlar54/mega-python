;=======================================================================================
; Calls into the tails (resident part 2).
;
; The window's last 4 KB holds one tail at a time (TAIL_x and need_tail in
; resident.asm). Code reaches a tail routine only through a stub:
;
;   label:  #TAILCALL TAIL_x, target
;
; which loads tail x, runs target, and when target returns brings back the tail that
; was in before, so the caller may itself be tail code. A nested Python call can bring
; in other tails too: vm_call_nested puts its caller's tail back (vm.asm), and so does
; a native exception catcher (it_inst in seq.asm). Tail code must still not call into
; another tail other than through a stub.
;
; A, X, Y and the flags pass through unchanged in both directions (arguments in,
; results out). (The macro and the TAIL_x numbers are in resident.asm, before their
; first use.)
;=======================================================================================
tc_a:   .byte 0
tc_y:   .byte 0
tc_p:   .byte 0
tc_tgt: .word 0

; tcall - (from a stub) the stub's data follows its jsr: the tail and the target
tcall:
        sta tc_a
        php
        pla
        sta tc_p
        sty tc_y
        pla                             ; the stub's return address = its data - 1
        sta tcp
        pla
        sta tcp+1
        ldy #3
        lda (tcp),y
        sta tc_tgt+1
        dey
        lda (tcp),y
        sta tc_tgt
        lda tail_cur                    ; the caller's tail, then the way back
        pha
        lda #>(tcall_ret - 1)
        pha
        lda #<(tcall_ret - 1)
        pha
        dey
        lda (tcp),y
        jsr need_tail
        lda tc_p
        pha
        lda tc_a
        ldy tc_y
        plp
        jmp (tc_tgt)

; the target returns here: the caller's tail back, then to the caller
tcall_ret:
        sta tc_a
        php
        pla
        sta tc_p
        pla
        jsr need_tail
        lda tc_p
        pha
        lda tc_a
        plp
        rts
