;=======================================================================================
; Bytecode VM.
;
; Value stack grows down from VSTACK_END; vsp points at the top of stack (TOS).
; A function's locals are contiguous: local i is at vfp + 2*(nlocals-1-i), which is
; the operand the compiler emits for LOAD_FAST / STORE_FAST.
;
; Call frame (FSTACK, grows up, 8 bytes): +0 return ip, +2 caller vfp, +4 result slot,
; +6 flags. Handler (HSTACK, 8 bytes): +0 handler ip, +2 vsp, +4 frp, +6 vfp.
;
; Run levels: vm_run (from the REPL) and vm_call_nested (from native code calling back
; into Python) each start a level that records where the CPU stack, handler stack and
; frame stack were. throw resets the CPU stack to the level and unwinds to the newest
; handler of that level, or leaves the level and re-throws in the one outside it.
;=======================================================================================
FR_CTOR         = 1                     ; return the instance (arg 0), not the result
FR_NESTED       = 2                     ; return to native code (vm_call_nested)
FR_EXTRA        = 4                     ; the result slot is one below the callable
FR_GEN          = 8                     ; a generator's frame (gen.asm), resumed by
FR_FORIT        = 16                    ; FOR_ITER (else FR_NESTED: native code)
FR_SENDX        = 32                    ; (with FR_FORIT) SEND: yield from

PUSH    .macro                          ; push A/X
        dew vsp
        dew vsp
        ldy #0
        sta (vsp),y
        iny
        pha
        txa
        sta (vsp),y
        pla
        .endm
POP     .macro                          ; pop -> A/X
        ldy #1
        lda (vsp),y
        tax
        dey
        lda (vsp),y
        inw vsp
        inw vsp
        .endm
PEEK    .macro n                        ; stack slot n (0 = TOS) -> A/X
        ldy #2*\n+1
        lda (vsp),y
        tax
        dey
        lda (vsp),y
        .endm
POKE    .macro n                        ; A/X -> stack slot n
        ldy #2*\n
        sta (vsp),y
        iny
        pha
        txa
        sta (vsp),y
        pla
        .endm
DROP    .macro n
        .rept \n
        inw vsp
        inw vsp
        .endrept
        .endm
FETCHB  .macro                          ; next code byte -> A
        ldz #0
        lda [ip],z
        inw ip
        .endm
FETCHW  .macro                          ; next code word -> A/X
        ldz #1
        lda [ip],z
        tax
        dez
        lda [ip],z
        inw ip
        inw ip
        .endm

; DBG_HOLD: when dbg_hold is armed (non-zero) the CPU spins here until the debugger
; clears it, so tools/trace.py can single-step from this point
DBG_HOLD .macro
        bit dbg_hold
        bpl +
-       bit dbg_hold
        bmi -
+
        .endm
dbg_hold:       .byte 0

MAXLEV          = 8
runlev:         .byte 0
lev_esp_lo:     .fill MAXLEV
lev_esp_hi:     .fill MAXLEV
lev_evec_lo:    .fill MAXLEV
lev_evec_hi:    .fill MAXLEV
lev_hsp_lo:     .fill MAXLEV
lev_hsp_hi:     .fill MAXLEV
lev_frp_lo:     .fill MAXLEV
lev_frp_hi:     .fill MAXLEV
err_vec:        .word 0
exc_ip:         .word 0                 ; ip where the current exception was raised
exc_ip_set:     .byte 0

vm_reset:
        lda #<VSTACK_END
        sta vsp
        sta vfp
        lda #>VSTACK_END
        sta vsp+1
        sta vfp+1
        lda #<FSTACK
        sta frp
        lda #>FSTACK
        sta frp+1
        lda #<HSTACK
        sta hsp
        lda #>HSTACK
        sta hsp+1
        lda #<(FSTACK >> 16)            ; (both stacks are in bank 1)
        sta frp+2
        sta hsp+2
        lda #0
        sta frp+3
        sta hsp+3
        lda #0
        sta runlev
        sta cur_exc
        sta cur_exc+1
        sta nargc                       ; (no native call yet: NATIVE_SAVE keeps none)
        sta cb_sp                       ; (no class body)
        lda #CODE_BANK
        sta ip+2
        lda #0
        sta ip+3
        rts

;---------------------------------------------------------------------------------------
; vm_run - run bytecode from code offset A/X until HALT.
; Returns C clear, or C set with cur_exc = the uncaught exception.
;---------------------------------------------------------------------------------------
vm_run:
        sta ip
        stx ip+1
        jsr lev_enter
        jmp vm_loop

; start a run level: the caller's return address must be on top of the CPU stack
lev_enter:
        ldx runlev
        cpx #MAXLEV
        bcc +
        jmp raise_recursion
+       lda err_sp
        sta lev_esp_lo,x
        lda err_sp+1
        sta lev_esp_hi,x
        lda err_vec
        sta lev_evec_lo,x
        lda err_vec+1
        sta lev_evec_hi,x
        lda hsp
        sta lev_hsp_lo,x
        lda hsp+1
        sta lev_hsp_hi,x
        lda frp
        sta lev_frp_lo,x
        lda frp+1
        sta lev_frp_hi,x
        inc runlev
        ; the level's CPU stack is the caller's (drop our own return address)
        pla
        sta t7
        pla
        sta t7+1
        tsx
        stx err_sp
        tsy
        sty err_sp+1
        lda #<vm_except
        sta err_vec
        lda #>vm_except
        sta err_vec+1
        lda t7+1
        pha
        lda t7
        pha
        rts

; leave the current level (restore the outer error context)
lev_leave:
        dec runlev
        ldx runlev
        lda lev_esp_lo,x
        sta err_sp
        lda lev_esp_hi,x
        sta err_sp+1
        lda lev_evec_lo,x
        sta err_vec
        lda lev_evec_hi,x
        sta err_vec+1
        rts

;---------------------------------------------------------------------------------------
; throw - raise cur_exc: unwind the CPU stack to the error context and handle it
;---------------------------------------------------------------------------------------
throw:
        lda exc_ip_set
        bne +
        lda ip
        sta exc_ip
        lda ip+1
        sta exc_ip+1
        inc exc_ip_set
        lda ovl_cur                     ; the levels of calls (overlay R: builtins.asm)
        bne +
        jsr tb_capture
+       ldx err_sp
        ldy err_sp+1
        tys
        txs
        jmp (err_vec)

vm_except:
        #DBG_HOLD
        jsr gen_p479                    ; (methods.asm)
        ldx runlev
        dex
        lda hsp+1
        cmp lev_hsp_hi,x
        bne _handler
        lda hsp
        cmp lev_hsp_lo,x
        bne _handler
        ; no handler in this level: leave it
        lda lev_frp_lo,x
        sta frp
        lda lev_frp_hi,x
        sta frp+1
        jsr lev_leave
        lda runlev
        bne +
        sec                             ; outermost: back to vm_run's caller
        rts
+       jmp throw
_handler:
        sec
        lda hsp
        sbc #8
        sta hsp
        lda hsp+1
        sbc #0
        sta hsp+1
        ldz #0
        lda [hsp],z
        sta ip
        inz
        lda [hsp],z
        sta ip+1
        inz
        lda [hsp],z
        sta vsp
        inz
        lda [hsp],z
        sta vsp+1
        inz
        lda [hsp],z
        sta frp
        inz
        lda [hsp],z
        sta frp+1
        inz
        lda [hsp],z
        sta vfp
        inz
        lda [hsp],z
        sta vfp+1
        lda cur_exc
        ldx cur_exc+1
        #PUSH
        jmp vm_loop

;---------------------------------------------------------------------------------------
; the dispatch loop
;---------------------------------------------------------------------------------------
vm_loop:
        ldz #0
        lda [ip],z
        inw ip
        asl
        tax
        jmp (op_table,x)

op_table:
        .word op_halt, op_nop, op_const, op_load_fast, op_store_fast         ; 0-4
        .word op_load_global, op_store_global, op_load_attr, op_store_attr   ; 5-8
        .word op_load_subscr, op_store_subscr, op_pop, op_dup, op_dup2       ; 9-13
        .word op_rot2, op_rot3                                               ; 14-15
        .word op_add, op_sub, op_binop, op_binop, op_binop, op_binop         ; 16-21
        .word op_binop, op_binop, op_binop, op_binop, op_binop, op_binop     ; 22-27
        .word op_binop, op_unary, op_unary, op_not, op_unary                 ; 28-32
        .word op_cmp, op_cmp, op_lt, op_cmp, op_cmp, op_cmp                  ; 33-38
        .word op_in, op_in, op_is, op_is                                     ; 39-42
        .word op_jump, op_jump_if_false, op_jump_if_true                     ; 43-45
        .word op_jump_if_false_or_pop, op_jump_if_true_or_pop                ; 46-47
        .word op_get_iter, op_for_iter                                       ; 48-49
        .word op_build_list, op_build_tuple, op_build_dict                   ; 50-52
        .word op_call, op_call_kw, op_load_method, op_call_method            ; 53-56
        .word op_call_method_kw, op_return, op_make_function                 ; 57-59
        .word op_make_class, op_store_classattr, op_unpack                   ; 60-62
        .word op_setup_except, op_pop_block, op_exc_match, op_raise          ; 63-66
        .word op_pop_except, op_print_expr, op_format, op_build_string       ; 67-70
        .word op_build_slice, op_delete_fast, op_delete_global               ; 71-73
        .word op_delete_subscr, op_delete_attr, op_list_append, op_map_add   ; 74-77
        .word op_assert_fail, op_import, op_load_super, op_build_set         ; 78-81
        .word op_set_add, op_lift3                                           ; 82-83
        .word op_load_deref, op_store_deref, op_enter_env, op_set_closure    ; 84-87 (env.asm)
        .word op_load_classname, op_end_class                                ; 88-89
        .word op_pack_args, op_ex_arg, op_call_ex                            ; 90-92 (args.asm)
        .word op_yield, op_send, op_unpack_ex, op_import_star                ; 93-96 (gen.asm, methods.asm)
        .word op_inplace                                                     ; 97 (setsr.asm)

op_bad:
        #RAISE EXC_SYSTEM, "bad opcode"

op_halt:
        jsr lev_leave
        clc
        rts

op_nop:
        jmp vm_loop

op_const:
        #FETCHW
        #PUSH
        jmp vm_loop

op_load_fast:
        #FETCHB
        tay
        iny
        lda (vfp),y
        tax
        dey
        lda (vfp),y
        bne +
        cpx #0
        bne +
        jmp raise_unbound
+       #PUSH
        jmp vm_loop

op_store_fast:
        #FETCHB
        sta vtmp
        #POP
        ldy vtmp
        sta (vfp),y
        iny
        txa
        sta (vfp),y
        jmp vm_loop


op_delete_fast:
        #FETCHB
        tay
        lda #0
        sta (vfp),y
        iny
        sta (vfp),y
        jmp vm_loop

; fp1 = &SYM_VAL[next code word]
global_addr:
        #FETCHW
        sta vtmp
        stx vtmp+1
        jmp sym_val_addr

op_load_global:
        jsr global_addr
; load_global_fp1 - push the global at fp1 (symbol vtmp; a module's hidden name falls
; back to the plain one). (LOAD_CLASSNAME ends here too.)
load_global_fp1:
_load:  ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        bne +
        cpx #0
        bne +
        lda vtmp                        ; a module's hidden name: try the plain one
        ldx vtmp+1
        jsr unmangle
        cmp vtmp
        bne _base
        cpx vtmp+1
        bne _base
        jmp raise_name_vtmp
_base:  sta vtmp
        stx vtmp+1
        jsr sym_val_addr
        bra _load
+       #PUSH
        jmp vm_loop

op_store_global:
        jsr global_addr
        #POP
        ldz #0
        sta [fp1],z
        inz
        txa
        sta [fp1],z
        jmp vm_loop

op_delete_global:
        jsr global_addr
        ldz #0
        lda [fp1],z
        inz
        ora [fp1],z
        bne +
        jmp raise_name_vtmp
+       lda #0
        sta [fp1],z
        dez
        sta [fp1],z
        jmp vm_loop

op_pop:
        #DROP 1
        jmp vm_loop

op_dup:
        #PEEK 0
        #PUSH
        jmp vm_loop

op_dup2:
        #PEEK 1
        #PUSH
        #PEEK 1
        #PUSH
        jmp vm_loop

op_rot2:
        #PEEK 0
        sta t0
        stx t0+1
        #PEEK 1
        #POKE 0
        lda t0
        ldx t0+1
        #POKE 1
        jmp vm_loop

op_rot3:                                ; a b c -> c a b (c = TOS)
        #PEEK 0
        sta t0
        stx t0+1
        #PEEK 1
        #POKE 0
        #PEEK 2
        #POKE 1
        lda t0
        ldx t0+1
        #POKE 2
        jmp vm_loop

op_lift3:                               ; a b c -> b c a (c = TOS)
        #PEEK 2
        sta t0
        stx t0+1
        #PEEK 1
        #POKE 2
        #PEEK 0
        #POKE 1
        lda t0
        ldx t0+1
        #POKE 0
        jmp vm_loop

;---------------------------------------------------------------------------------------
; jumps
;---------------------------------------------------------------------------------------
op_jump:
        #FETCHW
        cpx ip+1                        ; backward jump: check for RUN/STOP now and then
        bcc _back
        bne _go
        cmp ip
        bcs _go
_back:  jsr check_stop
_go:    sta ip
        stx ip+1
        jmp vm_loop

op_jump_if_false:
        #POP
        jsr obj_truth
        beq op_jump
        bra skip_word
op_jump_if_true:
        #POP
        jsr obj_truth
        bne op_jump
skip_word:
        inw ip
        inw ip
        jmp vm_loop

op_jump_if_false_or_pop:
        #PEEK 0
        jsr obj_truth
        beq op_jump
        #DROP 1
        bra skip_word
op_jump_if_true_or_pop:
        #PEEK 0
        jsr obj_truth
        bne op_jump
        #DROP 1
        bra skip_word

; poll the keyboard for RUN/STOP every 256 calls
check_stop:
        inc stop_count
        bne _done
        pha
        lda ASCIIKEY
        cmp #K_STOP
        bne _no
        sta ASCIIKEY
        lda dbg_kpos                    ; drop injected keys too
        sta dbg_klen
        #RAISE EXC_KEYBOARD, ""
_no:    pla
_done:  rts

;---------------------------------------------------------------------------------------
; calls
;---------------------------------------------------------------------------------------
argv:           .fill 32                ; native call arguments (copied from the stack)
c_argc_save:    .byte 0
c_flags:        .byte 0

op_call:
        #FETCHB
        sta argc
        lda #0
        sta kwnames
        sta kwnames+1
        sta nkw
call_setup:
        ; c_slot = vsp + 2 * argc, c_func = *c_slot
        lda argc
        asl
        clc
        adc vsp
        sta c_slot
        lda vsp+1
        adc #0
        sta c_slot+1
        ldy #0
        lda (c_slot),y
        sta c_func
        iny
        lda (c_slot),y
        sta c_func+1
        lda #0
        sta c_flags
        jmp do_call

op_call_kw:
        #FETCHB
        sta argc
        #FETCHW
        sta kwnames
        stx kwnames+1
        jsr kw_count
        bra call_setup

; nkw = len(kwnames)
kw_count:
        lda kwnames
        ldx kwnames+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        sta nkw
        rts

op_load_method:
        #FETCHW                         ; name ref
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr get_method                  ; -> A/X callable, C set if it needs self
        bcs _self
        #POKE 0                         ; callable NULL
        lda #0
        tax
        #PUSH
        jmp vm_loop
_self:  #POKE 0                         ; meth self (get_method kept the object)
        lda groot+10
        ldx groot+11
        #PUSH
        lda #0
        sta groot+10
        sta groot+11
        jmp vm_loop

op_call_method:
        #FETCHB
        sta argc
        lda #0
        sta kwnames
        sta kwnames+1
        sta nkw
method_setup:
        ; slots: [meth][self or NULL][args...]
        lda argc
        asl
        clc
        adc vsp
        sta c_slot
        lda vsp+1
        adc #0
        sta c_slot+1
        ldy #0                          ; self slot
        lda (c_slot),y
        iny
        ora (c_slot),y
        beq _null
        inc argc                        ; self is argument 0
        lda c_slot
        clc
        adc #2
        sta c_slot
        bcc +
        inc c_slot+1
+       bra _func
_null:  lda c_slot                      ; the result goes to the callable's slot
        clc
        adc #2
        sta c_slot
        bcc _func
        inc c_slot+1
_func:  ldy #0
        lda (c_slot),y
        sta c_func
        iny
        lda (c_slot),y
        sta c_func+1
        lda #0
        sta c_flags
        jmp do_call

op_call_method_kw:
        #FETCHB
        sta argc
        #FETCHW
        sta kwnames
        stx kwnames+1
        jsr kw_count
        bra method_setup

;---------------------------------------------------------------------------------------
; do_call - call c_func with the argc values on top of the stack; the result replaces
; everything from c_slot down. kwnames/nkw describe keyword arguments (the last nkw).
;---------------------------------------------------------------------------------------
do_call:
        lda c_func
        ldx c_func+1
        jsr type_of
        cmp #T_FUNC
        bne +
        jmp call_py
+       cmp #T_BUILTIN
        bne +
        jmp call_native
+       cmp #T_CLASS
        bne +
        jmp call_class
+       cmp #T_BOUND
        bne +
        ; insert self above the arguments
        ldz #4
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        inz
        lda [p0],z
        pha
        inz
        lda [p0],z
        sta c_func+1
        pla
        sta c_func
        jsr insert_arg0
        bra do_call
+       cmp #T_INST                     ; an instance: its class's __call__(self, ...)
        bne _bad
        jsr inst_call
        jmp do_call
_bad:   lda c_func
        ldx c_func+1
        jmp raise_not_callable

; inst_call - c_func is an instance: c_func = its __call__, the instance argument 0
inst_call:
        lda c_func
        sta r0
        lda c_func+1
        sta r0+1
        lda #<S_CALL
        ldx #>S_CALL
        jsr sym_name
        sta r1
        stx r1+1
        jsr get_method                  ; (AttributeError if there is none)
        sta c_func
        stx c_func+1
        lda groot+10                    ; (the instance: get_method kept it there)
        sta r0
        lda groot+11
        sta r0+1
        lda #0
        sta groot+10
        sta groot+11
        sta r1
        sta r1+1
        bcc +
        jmp insert_arg0                 ; self
+       rts

; insert_arg0 - make r0 argument 0: it goes in the slot above the current argument 0
; (the callable's or the NULL slot); shifts nothing if that slot is c_slot.
insert_arg0:
        lda argc
        asl
        clc
        adc vsp
        sta t0
        lda vsp+1
        adc #0
        sta t0+1
        ldy #0
        lda r0
        sta (t0),y
        iny
        lda r0+1
        sta (t0),y
        inc argc
        lda t0
        cmp c_slot
        bne _null
        lda t0+1
        cmp c_slot+1
        beq +
_null:  ; it was the NULL slot of a method call: the result goes there, then moves up
        lda t0
        sta c_slot
        lda t0+1
        sta c_slot+1
        lda c_flags
        ora #FR_EXTRA
        sta c_flags
+       rts

;---------------------------------------------------------------------------------------
; call_native - builtin id at c_func+4: copy the arguments to argv, call, store result
;---------------------------------------------------------------------------------------
call_native:
        lda argc
        cmp #17
        bcc +
        #RAISE EXC_TYPE, "too many arguments"
+       ; argv[i] = arg i = vsp + 2*(argc-1-i)
        ldx #0
        lda argc
        beq _call
        asl
        tay
        dey
        dey
-       lda (vsp),y
        sta argv,x
        iny
        lda (vsp),y
        sta argv+1,x
        inx
        inx
        dey
        dey
        dey
        bpl -
_call:  lda argc
        sta nargc
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        tax
        lda #0
        sta bm_wrap
        lda builtin_flags,x             ; a method checks its self (str.upper(5))
        cmp #8
        bcc +
        jsr bm_check                    ; (builtins.asm; keeps X)
+       lda bm_wrap                     ; (a str method on bytes: the result as bytes)
        pha
        lda c_flags
        pha
        lda c_slot
        pha
        lda c_slot+1
        pha
        jsr native_jmp
        sta t0
        stx t0+1
        pla
        sta c_slot+1
        pla
        sta c_slot
        pla
        sta c_flags
        pla
        beq +
        lda t0
        ldx t0+1
        jsr bytes_wrap
        sta t0
        stx t0+1
+       lda c_slot
        sta vsp
        lda c_slot+1
        sta vsp+1
        lda t0
        ldx t0+1
        jmp store_result

; store_result - A/X = result; vsp = the result slot, c_flags = the call's flags
store_result:
        sta r0
        stx r0+1
        lda c_flags
        and #FR_CTOR
        beq +
        #PEEK 0                         ; a constructor returns argument 0, the instance
        sta r0
        stx r0+1
+       lda c_flags
        and #FR_EXTRA
        beq +
        #DROP 1                         ; arg 0 went in a method call's NULL slot
+       lda r0
        ldx r0+1
        #POKE 0
        lda #0
        sta r0
        sta r0+1
        lda c_flags
        and #FR_NESTED
        bne +
        jmp vm_loop
+       #POP
        pha
        phx
        jsr lev_leave
        plx
        pla
        rts                             ; back into vm_call_nested's caller
native_jmp:                             ; X = builtin id
        lda builtin_tab_lo,x
        sta native_vec
        lda builtin_tab_hi,x
        sta native_vec+1
        jmp (native_vec)
native_vec:     .word 0

;---------------------------------------------------------------------------------------
; call_py - call the Python function c_func
;---------------------------------------------------------------------------------------
call_py:
        jsr check_stop
        lda c_func                      ; *args, **kwargs, keyword-only parameters?
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #18
        lda [p0],z
        and #FF_VARARGS | FF_VARKW
        inz
        ora [p0],z
        beq _plain
        jsr bind_ex                     ; (args.asm) -> argc = all the parameters
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #7
        lda [p0],z
        sta t1+1                        ; nlocals
        jmp _locals
_plain: lda nkw
        beq +
        jsr kw_to_positional
+       lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #6
        lda [p0],z
        sta t1                          ; nargs
        inz
        lda [p0],z
        sta t1+1                        ; nlocals
        lda argc
        cmp t1
        beq _locals
        bcc _defaults
        jmp raise_arg_count
_defaults:
        ; arguments argc .. nargs-1 come from the defaults tuple (the last nd params)
        ldz #10
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        beq _missing
        ldz #4
        lda [p1],z                      ; nd
        sta t2
        sec
        lda t1
        sbc t2                          ; first param with a default
        sta t2+1
        lda argc
        cmp t2+1
        bcs +
_missing:
        jmp raise_arg_count
+       ; push defaults[argc - first] .. for argc < nargs
-       lda argc
        cmp t1
        bcs _locals
        sec
        sbc t2+1
        asl
        clc
        adc #6
        taz
        lda [p1],z
        pha
        inz
        lda [p1],z
        tax
        pla
        #PUSH
        inc argc
        bra -
_locals:
        ; NULL for the other locals
-       lda argc
        cmp t1+1
        bcs +
        lda #0
        tax
        #PUSH
        inc argc
        bra -
+       lda c_func                      ; a generator function: the generator instead
        sta p0
        lda c_func+1
        sta p0+1
        ldz #18
        lda [p0],z
        and #FF_GEN
        beq +
        jsr gen_make                    ; (methods.asm)
        jmp store_result
+       ; stack and frame limits
        lda vsp+1
        cmp #>(VSTACK + $100)
        bcs +
        jmp raise_recursion
+       lda frp+1
        cmp #>(FSTACK_END - 8)
        bcc +
        lda frp
        cmp #<(FSTACK_END - 8)
        bcc +
        jmp raise_recursion
+       ; push the frame
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
        lda c_flags
        sta [frp],z
        clc
        lda frp
        adc #8
        sta frp
        bcc +
        inc frp+1
+       lda vsp
        sta vfp
        lda vsp+1
        sta vfp+1
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #4
        lda [p0],z
        sta ip
        inz
        lda [p0],z
        sta ip+1
        jmp vm_loop

op_return:
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
        inz
        lda [frp],z
        sta vsp
        inz
        lda [frp],z
        sta vsp+1
        inz
        lda [frp],z
        sta c_flags
        ; drop the exception handlers the returning function left (return in a try)
-       lda hsp
        cmp #<HSTACK
        bne +
        lda hsp+1
        cmp #>HSTACK
        beq _ret
+       sec
        lda hsp
        sbc #8
        sta fp2
        lda hsp+1
        sbc #0
        sta fp2+1
        lda #<(HSTACK >> 16)
        sta fp2+2
        lda #0
        sta fp2+3
        ldz #5                          ; the handler's frame pointer
        lda [fp2],z
        cmp frp+1
        bcc _ret
        bne +
        dez
        lda [fp2],z
        cmp frp
        bcc _ret
        beq _ret
+       lda fp2
        sta hsp
        lda fp2+1
        sta hsp+1
        bra -
_ret:   lda c_flags
        and #FR_GEN
        beq +
        jmp gen_return                  ; (a generator ends)
+       lda r0
        ldx r0+1
        jmp store_result

;---------------------------------------------------------------------------------------
; NATIVE_SAVE / NATIVE_RESTORE - keep native code's state on the CPU stack across Python
; code it runs: the tail in the window and the arguments of the native call it is part
; of (argv[0 .. 2 * nargc), nargc, npos, nkw, kwnames). A, X, Y are not kept.
;---------------------------------------------------------------------------------------
NATIVE_SAVE .macro
        lda tail_cur
        pha
        lda kwnames
        pha
        lda kwnames+1
        pha
        lda nkw
        pha
        lda npos
        pha
        lda nargc
        asl
        tay                             ; Y = bytes left, X = index
        ldx #0
-       tya
        beq +
        lda argv,x
        pha
        inx
        dey
        bra -
+       lda nargc
        pha
        .endm
NATIVE_RESTORE .macro
        pla
        sta nargc
        asl
        tax
-       cpx #0
        beq +
        dex
        pla
        sta argv,x
        bra -
+       pla
        sta npos
        pla
        sta nkw
        pla
        sta kwnames+1
        pla
        sta kwnames
        pla
        jsr need_tail
        .endm

;---------------------------------------------------------------------------------------
; vm_call_nested - native code calls c_func with argc arguments it pushed (after
; pushing the callable). Returns A/X = the result, the stack popped back.
; The caller's own state comes back afterwards, whatever the Python code did: its
; arguments (argv, nargc, npos, nkw, kwnames: the native call it is part of) and its
; tail (it may be tail code).
;---------------------------------------------------------------------------------------
vm_call_nested:
        #NATIVE_SAVE
        jsr vcn_run
        sta vcn_a
        stx vcn_x
        #NATIVE_RESTORE
        lda vcn_a
        ldx vcn_x
        rts
vcn_a:  .byte 0
vcn_x:  .byte 0
vcn_run:
        lda #0
        sta kwnames
        sta kwnames+1
        sta nkw
        sta c_flags
        lda argc
        asl
        clc
        adc vsp
        sta c_slot
        lda vsp+1
        adc #0
        sta c_slot+1
        ldy #0
        lda (c_slot),y
        sta c_func
        iny
        lda (c_slot),y
        sta c_func+1
_again: lda c_func
        ldx c_func+1
        jsr type_of
        cmp #T_FUNC
        beq _py
        cmp #T_INST
        bne +
        jsr inst_call
        bra _again
+       cmp #T_BOUND
        bne _native
        ldz #4
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        inz
        lda [p0],z
        pha
        inz
        lda [p0],z
        sta c_func+1
        pla
        sta c_func
        jsr insert_arg0
        bra _again
_native:
        ; run a one-instruction trampoline: CALL argc; HALT
        lda argc
        sta tramp+1
        lda ip
        pha
        lda ip+1
        pha
        lda ip+2
        pha
        lda #<tramp_code
        ldx #>tramp_code
        jsr vm_run_bank0
        pla
        sta ip+2
        pla
        sta ip+1
        pla
        sta ip
        bcc +
        jmp throw
+       #POP
        rts
_py:    jsr lev_enter
        lda c_flags
        ora #FR_NESTED
        sta c_flags
        jmp call_py

; a CALL n / HALT pair for native callables, run from bank 0
tramp_code = tramp
tramp:          .byte OP_CALL, 0, OP_HALT
vm_run_bank0:
        sta ip
        stx ip+1
        lda #0
        sta ip+2
        jsr lev_enter
        jmp vm_loop

; call A/X (a callable) with no arguments / one argument r1 / two r1 r2 from native code
call0:
        #PUSH
        lda #0
        sta argc
        jmp vm_call_nested
call1:
        #PUSH
        lda r1
        ldx r1+1
        #PUSH
        lda #1
        sta argc
        jmp vm_call_nested
call2:
        #PUSH
        lda r1
        ldx r1+1
        #PUSH
        lda r2
        ldx r2+1
        #PUSH
        lda #2
        sta argc
        jmp vm_call_nested

;---------------------------------------------------------------------------------------
; keyword arguments for a Python function: reorder the last nkw values into their
; parameter slots. Leaves argc = nargs (missing ones filled from defaults later by
; call_py, which sees argc < nargs only when trailing params are missing).
;---------------------------------------------------------------------------------------
kw_to_positional: #TAILCALL TAIL_X, xx_kw_to_positional  ; (args.asm)

;---------------------------------------------------------------------------------------
; call_class - instantiate c_func
;---------------------------------------------------------------------------------------
call_class:
        lda #8
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_INST
        jsr alloc
        ldz #4
        lda c_func
        sta [p0],z
        inz
        lda c_func+1
        sta [p0],z
        sta r0+1
        lda p0
        sta r0
        lda p0+1
        sta r0+1
        jsr insert_arg0                 ; instance = argument 0 (also rooted there)
        ; __init__ through the class chain
        lda c_func
        ldx c_func+1
        sta r2
        stx r2+1
        lda #<S_INIT
        ldx #>S_INIT
        jsr sym_name
        sta r1
        stx r1+1
        jsr class_lookup                ; r2 = class, r1 = name -> C clear, A/X
        bcs _noinit
        sta c_func
        stx c_func+1
        lda c_flags
        ora #FR_CTOR
        sta c_flags
        jmp do_call
_noinit:
        lda argc
        cmp #2
        bcc +
        jmp raise_no_init_args
+       lda c_slot
        sta vsp
        lda c_slot+1
        sta vsp+1
        lda c_flags
        ora #FR_CTOR
        sta c_flags
        jmp store_result

;---------------------------------------------------------------------------------------
; functions and classes
;---------------------------------------------------------------------------------------
; *args / **kwargs / keyword-only parameters, f(*a, **k) calls: in tail X (args.asm)
bind_ex:        #TAILCALL TAIL_X, xx_bind_ex
x_pack_args:    #TAILCALL TAIL_X, xx_pack_args
x_ex_arg:       #TAILCALL TAIL_X, xx_ex_arg
x_call_ex:      #TAILCALL TAIL_X, xx_call_ex
op_pack_args:
        jsr x_pack_args
        jmp vm_loop
op_ex_arg:
        jsr x_ex_arg
        jmp vm_loop
op_call_ex:
        jsr x_call_ex                   ; C set: a method call
        bcc +
        jmp method_setup
+       jmp call_setup

op_make_function:
        ; [defaults tuple if ndefaults] [keyword-only defaults if nkwonly] -> func
        ; (+14 closure: SET_CLOSURE, env.asm; +16 keyword-only defaults, +18 flags
        ; FF_VARARGS / FF_VARKW, +19 keyword-only parameters: args.asm)
        lda #20
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_FUNC
        jsr alloc
        ldz #4
-       phz
        ldz #0
        lda [ip],z
        inw ip
        plz
        cpz #10
        bcs +
        sta [p0],z
        inz
        bra -
+       ; Z = 10: A = ndefaults; then params ref
        sta t0
        ldz #12
        phz
        #FETCHW
        plz
        sta [p0],z
        inz
        txa
        sta [p0],z
        #FETCHB                         ; flags, keyword-only parameters
        ldz #18
        sta [p0],z
        #FETCHB
        ldz #19
        sta [p0],z
        cmp #0
        beq +
        #POP                            ; their defaults
        ldz #16
        sta [p0],z
        inz
        txa
        sta [p0],z
+       lda t0
        beq _nodef
        #PEEK 0
        ldz #10
        sta [p0],z
        inz
        txa
        sta [p0],z
        lda p0
        ldx p0+1
        #POKE 0
        jmp vm_loop
_nodef: lda p0
        ldx p0+1
        #PUSH
        jmp vm_loop

op_make_class:
        jsr x_make_class
        jmp vm_loop
x_make_class:   #TAILCALL TAIL_X, xx_make_class  ; (args.asm)

; the classes whose bodies are running, innermost last: (class, its value stack slot);
; the class is also on the value stack (no GC root needed). END_CLASS pops one; a class
; body left by an exception leaves its entry, which cb_prune drops once the stack is
; back above that slot.
CB_MAX          = 8
cb_sp:          .byte 0
cb_stack:       .fill 4 * CB_MAX

op_end_class:
        lda cb_sp
        beq +
        sec
        sbc #4
        sta cb_sp
+       jmp vm_loop

; cb_prune - drop the entries of class bodies an exception left. The stack grows down:
; a running body's class slot is at vsp or above it, a left one's below (the handler
; reset vsp above it). cb_prune_lim: drop those below cb_lim.
cb_lim:         .word 0
cb_prune:
        lda vsp
        sta cb_lim
        lda vsp+1
        sta cb_lim+1
cb_prune_lim:
        ldx cb_sp
        beq _done
        lda cb_stack-1,x                ; slot < cb_lim: stale
        cmp cb_lim+1
        bcc _drop
        bne _done
        lda cb_stack-2,x
        cmp cb_lim
        bcs _done
_drop:  txa
        sec
        sbc #4
        sta cb_sp
        bra cb_prune_lim
_done:  rts

op_store_classattr:
        #FETCHW                         ; name ref
        sta r1
        stx r1+1
        #POP
        sta r2
        stx r2+1
        #PEEK 0
        sta p0
        stx p0+1
        ldz #8
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        jsr dict_set
        #PEEK 0                         ; a property makes the class F_PROPS
        jsr desc_mark
        jsr clear_rregs
        jmp vm_loop

clear_rregs:
        lda #0
        sta r0
        sta r0+1
        sta r1
        sta r1+1
        sta r2
        sta r2+1
        sta r3
        sta r3+1
        rts

;---------------------------------------------------------------------------------------
; containers
;---------------------------------------------------------------------------------------
op_build_tuple:
        #FETCHW
        sta nitems
        stx nitems+1
        jsr tuple_new
        ; items: item i is at vsp + 2*(n-1-i); tuple item i at +6+2i
        jsr items_from_stack
        lda p3
        ldx p3+1
        #PUSH
        jmp vm_loop

; copy the top nitems stack values (oldest first) to p0+6.., pop them; p3 = p0
items_from_stack:
        lda p0
        sta p3
        lda p0+1
        sta p3+1
        clc
        lda p0
        adc #6
        sta fp1
        lda p0+1
        adc #0
        sta fp1+1
items_to_fp1:                           ; same, into any bank-4 address fp1 (p3 = object)
        lda #HEAP_BANK
        sta fp1+2
        lda #0
        sta fp1+3
        lda nitems
        ora nitems+1
        beq _done
        ; the stack region vsp .. vsp+2n-1 holds them newest first: copy backwards
        lda nitems
        asl
        sta t1
        lda nitems+1
        rol
        sta t1+1
        clc
        lda vsp
        adc t1
        sta t2
        lda vsp+1
        adc t1+1
        sta t2+1                        ; t2 = just above the oldest
-       lda t2
        cmp vsp
        bne +
        lda t2+1
        cmp vsp+1
        beq _pop
+       dew t2
        dew t2
        ldy #0
        ldz #0
        lda (t2),y
        sta [fp1],z
        iny
        inz
        lda (t2),y
        sta [fp1],z
        inw fp1
        inw fp1
        bra -
_pop:   clc
        lda vsp
        adc t1
        sta vsp
        lda vsp+1
        adc t1+1
        sta vsp+1
_done:  rts

op_build_list:
        #FETCHW
        sta nitems
        stx nitems+1
        jsr list_new
        sta p3
        stx p3+1
        lda nitems
        ora nitems+1
        beq _empty
        lda p3
        sta p0
        lda p3+1
        sta p0+1
        ldz #4                          ; len = cap = n
        lda nitems
        sta [p0],z
        inz
        lda nitems+1
        sta [p0],z
        ldz #8
        lda [p0],z
        clc
        adc #4
        sta fp1
        inz
        lda [p0],z
        adc #0
        sta fp1+1
        lda p3
        pha
        lda p3+1
        pha
        jsr items_to_fp1
        pla
        tax
        pla
        #PUSH
        jmp vm_loop
_empty: lda p3
        ldx p3+1
        #PUSH
        jmp vm_loop

op_build_dict:
        ; k0 v0 k1 v1 ... (oldest first)
        #FETCHW
        pha
        phx
        jsr dict_new                    ; (allocating clobbers the t registers)
        sta r0
        stx r0+1
        plx
        pla
        sta t3
        stx t3+1
        pha
        phx
        ; insert oldest first: the oldest remaining pair is at vsp + 4*(t3-1)
-       lda t3
        ora t3+1
        beq +
        dew t3
        lda t3
        asl
        sta t4
        lda t3+1
        rol
        sta t4+1
        asw t4
        clc
        lda vsp
        adc t4
        sta t5
        lda vsp+1
        adc t4+1
        sta t5+1
        ldy #2
        lda (t5),y
        sta r1
        iny
        lda (t5),y
        sta r1+1
        ldy #0
        lda (t5),y
        sta r2
        iny
        lda (t5),y
        sta r2+1
        lda t3
        pha
        lda t3+1
        pha
        jsr dict_set
        pla
        sta t3+1
        pla
        sta t3
        bra -
+       pla                             ; pop the pairs
        sta t4+1
        pla
        sta t4
        asw t4
        asw t4
        clc
        lda vsp
        adc t4
        sta vsp
        lda vsp+1
        adc t4+1
        sta vsp+1
        lda r0
        ldx r0+1
        #PUSH
        jsr clear_rregs
        jmp vm_loop

op_build_set:   jmp set_build_op            ; (sets.asm, overlay R)
op_set_add = op_bad                         ; (unused: the compiler builds a list first)

op_list_append:
        ; list at slot depth+1 (TOS = value)
        #FETCHB
        asl
        tay
        iny
        iny
        lda (vsp),y
        sta r0
        iny
        lda (vsp),y
        sta r0+1
        #POP
        sta r1
        stx r1+1
        jsr list_append
        jsr clear_rregs
        jmp vm_loop

op_map_add:
        ; dict at slot depth+2 (TOS = value, TOS1 = key)
        #FETCHB
        asl
        tay
        iny
        iny
        iny
        iny
        lda (vsp),y
        sta r0
        iny
        lda (vsp),y
        sta r0+1
        #POP
        sta r2
        stx r2+1
        #POP
        sta r1
        stx r1+1
        jsr dict_set
        jsr clear_rregs
        jmp vm_loop

op_unpack:
        ; seq -> item n-1 ... item 0 (item 0 on top)
        #FETCHB
        sta t6
        #POP
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_TUPLE
        beq _seq
        cmp #T_LIST
        beq _seq
        ; anything else: materialise it as a list first (keeping the count: that
        ; allocates, and may run Python code)
        lda t6
        pha
        lda r0
        ldx r0+1
        jsr list_from_iterable
        sta r0
        stx r0+1
        pla
        sta t6
_seq:   lda r0
        ldx r0+1
        jsr seq_len
        lda t0+1
        bne _bad
        lda t0
        cmp t6
        bne _bad
        ; push item n-1 first
        lda t6
        sta t2
        lda #0
        sta t2+1
-       lda t2
        beq _done
        dec t2
        lda r0
        ldx r0+1
        jsr seq_get_t2
        #PUSH
        bra -
_done:  lda #0
        sta r0
        sta r0+1
        jmp vm_loop
_bad:   lda t0
        cmp t6
        bcc +
        #RAISE EXC_VALUE, "too many values to unpack"
+       #RAISE EXC_VALUE, "not enough values to unpack"

op_build_slice:
        ; start stop [step] -> slice
        #FETCHB
        pha                             ; (2 or 3: allocating may clobber the t registers)
        lda #10
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_SLICE
        jsr alloc
        pla
        sta t6
        lda #R_NONE
        ldz #8
        sta [p0],z
        inz
        lda #0
        sta [p0],z
        lda t6
        cmp #3
        bne +
        #POP
        ldz #8
        sta [p0],z
        inz
        txa
        sta [p0],z
+       #POP
        ldz #6
        sta [p0],z
        inz
        txa
        sta [p0],z
        #PEEK 0
        ldz #4
        sta [p0],z
        inz
        txa
        sta [p0],z
        lda p0
        ldx p0+1
        #POKE 0
        jmp vm_loop

;---------------------------------------------------------------------------------------
; exceptions
;---------------------------------------------------------------------------------------
op_setup_except:
        lda hsp+1
        cmp #>(HSTACK_END - 8)
        bcc +
        jmp raise_recursion
+       #FETCHW
        ldz #0
        sta [hsp],z
        inz
        txa
        sta [hsp],z
        inz
        lda vsp
        sta [hsp],z
        inz
        lda vsp+1
        sta [hsp],z
        inz
        lda frp
        sta [hsp],z
        inz
        lda frp+1
        sta [hsp],z
        inz
        lda vfp
        sta [hsp],z
        inz
        lda vfp+1
        sta [hsp],z
        clc
        lda hsp
        adc #8
        sta hsp
        bcc +
        inc hsp+1
+       jmp vm_loop

op_pop_block:
        sec
        lda hsp
        sbc #8
        sta hsp
        lda hsp+1
        sbc #0
        sta hsp+1
        jmp vm_loop

op_exc_match:
        ; exc cls -> bool (the compiler DUPs the exception first)
        #POP
        sta r3
        stx r3+1
        #PEEK 0
        sta r2
        stx r2+1
        jsr isinstance_r2_r3
        lda #R_FALSE
        bcc +
        lda #R_TRUE
+       ldx #0
        #POKE 0
        jsr clear_rregs
        jmp vm_loop

op_raise:
        #FETCHB
        cmp #0
        bne +
        lda cur_exc                     ; bare raise: re-raise the active exception
        ora cur_exc+1
        bne _rethrow
        #RAISE EXC_RUNTIME, "No active exception to reraise"
_rethrow:
        jmp throw
+       #POP
        jsr make_exception              ; class -> instance; instance stays
        sta cur_exc
        stx cur_exc+1
        lda #0
        sta exc_ip_set
        jmp throw

op_pop_except:
        ; the handled exception is TOS (if the handler kept it): nothing to do but
        ; forget the "current" exception
        lda #0
        sta cur_exc
        sta cur_exc+1
        jmp vm_loop

op_assert_fail:
        #FETCHB
        cmp #0
        beq +
        #POP
        sta r1
        stx r1+1
        lda #EXC_ASSERT
        jmp raise_with_obj
+       #RAISE EXC_ASSERT, ""

;---------------------------------------------------------------------------------------
; misc
;---------------------------------------------------------------------------------------
op_print_expr:
        #POP
        cpx #0
        bne +
        cmp #R_NONE
        beq _done
+       tay
        lda sbp                         ; the builder mark stays on the CPU stack
        pha
        lda sbp+1
        pha
        tya
        jsr obj_repr
        lda #COL_NORMAL
        sta scr_color
        plx
        pla
        jsr sb_flush
        lda #10
        jsr putc
_done:  jmp vm_loop

op_format:
        ; value -> str(value) or repr(value), with an optional format spec
        #FETCHB
        sta t6
        #FETCHW
        sta r3
        stx r3+1
        lda sbp
        pha
        lda sbp+1
        pha
        #PEEK 0
        ldy r3+1
        bne _spec
        ldy t6
        bne +
        jsr obj_str
        bra _take
+       jsr obj_repr
        bra _take
_spec:  ldy t6                           ; !r: the spec formats repr(value)
        beq _sp
        jsr obj_repr
        plx
        pla
        pha
        phx
        jsr sb_take
        #POKE 0
_sp:    sta r2
        stx r2+1
        jsr format_spec                 ; r2 value, r3 spec string
_take:  plx
        pla
        jsr sb_take
        #POKE 0
        jmp vm_loop

op_build_string:
        ; n strings -> one string
        #FETCHW
        sta nitems
        stx nitems+1
        lda sbp
        pha
        lda sbp+1
        pha
        lda nitems
        asl
        sta t3
        lda nitems+1
        rol
        sta t3+1
-       lda t3                          ; oldest first: string i at vsp + t3 - 2
        ora t3+1
        beq +
        dew t3
        dew t3
        lda t3
        clc
        adc vsp
        sta t4
        lda t3+1
        adc vsp+1
        sta t4+1
        ldy #1
        lda (t4),y
        tax
        dey
        lda (t4),y
        jsr sb_put_str
        bra -
+       lda nitems
        asl
        sta t3
        lda nitems+1
        rol
        sta t3+1
        clc
        lda vsp
        adc t3
        sta vsp
        lda vsp+1
        adc t3+1
        sta vsp+1
        plx
        pla
        jsr sb_take
        #PUSH
        jmp vm_loop

op_import:
        #FETCHW
        jsr mod_import
        #PUSH
        jmp vm_loop

op_load_super:
        ; w class sym, b self offset -> super proxy
        jsr global_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        sta r2
        stx r2+1
        #FETCHB
        tay
        iny
        lda (vfp),y
        sta r3+1
        dey
        lda (vfp),y
        sta r3
        jsr make_super
        #PUSH
        jsr clear_rregs
        jmp vm_loop
