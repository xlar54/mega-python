;=======================================================================================
; Methods of the built-in types (argv[0] is self), string formatting and sorting.
;=======================================================================================
RET_NONE .macro
        lda #R_NONE
        ldx #0
        rts
        .endm

; fp0 / str_len = self (argv[0]) as a string; also r2 = self
self_str:
        #ARG 0
        sta r2
        stx r2+1
        jmp str_info

; A/X must be a string -> str_info of it
need_str:
        sta r3
        stx r3+1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       lda r3
        ldx r3+1
        jmp str_info

; copy fp0 -> fp1 (both far pointers)
fp0_to_fp1:
        ldx #3
-       lda fp0,x
        sta fp1,x
        dex
        bpl -
        rts

; A -> upper (t6 = 0) or lower (t6 = 1) case
case_char:
        ldy t6
        bne _lower
        cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        and #$df
+       rts
_lower: cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        ora #$20
+       rts


;---------------------------------------------------------------------------------------
; str methods (and a few list methods): in tail S (strmeth.asm)
;---------------------------------------------------------------------------------------
TAILS   .macro target
        #TAILCALL TAIL_S, \target
        .endm
bi_str_upper:             #TAILS xs_str_upper
bi_str_lower:             #TAILS xs_str_lower
bi_str_isdigit:           #TAILS xs_str_isdigit
bi_str_isalpha:           #TAILS xs_str_isalpha
bi_str_isalnum:           #TAILS xs_str_isalnum
bi_str_isspace:           #TAILS xs_str_isspace
bi_str_isupper:           #TAILS xs_str_isupper
bi_str_islower:           #TAILS xs_str_islower
bi_str_find_m:            #TAILS xs_str_find_m
bi_str_index:             #TAILS xs_str_index
bi_str_count:             #TAILS xs_str_count
bi_str_replace:           #TAILS xs_str_replace
bi_str_startswith:        #TAILS xs_str_startswith
bi_str_endswith:          #TAILS xs_str_endswith
bi_str_strip:             #TAILS xs_str_strip
bi_str_lstrip:            #TAILS xs_str_lstrip
bi_str_rstrip:            #TAILS xs_str_rstrip
bi_str_split:             #TAILS xs_str_split
bi_str_splitlines:        #TAILS xs_str_splitlines
bi_str_join:              #TAILS xs_str_join
bi_str_center:            #TAILS xs_str_center
bi_str_ljust:             #TAILS xs_str_ljust
bi_str_rjust:             #TAILS xs_str_rjust
bi_str_zfill:             #TAILS xs_str_zfill
bi_str_title:             #TAILS xs_str_title
bi_str_capitalize:        #TAILS xs_str_capitalize
bi_str_swapcase:          #TAILS xs_str_swapcase
bi_str_casefold:          #TAILS xs_str_casefold
bi_str_isascii:           #TAILS xs_str_isascii
bi_str_rfind:             #TAILS xs_str_rfind
bi_str_rindex:            #TAILS xs_str_rindex
bi_str_partition:         #TAILS xs_str_partition
bi_str_rpartition:        #TAILS xs_str_rpartition
bi_str_removeprefix:      #TAILS xs_str_removeprefix
bi_str_removesuffix:      #TAILS xs_str_removesuffix
bi_str_expandtabs:        #TAILS xs_str_expandtabs
bi_str_rsplit:            #TAILS xs_str_rsplit

;---------------------------------------------------------------------------------------
; str_find - r3 = haystack, r2 = needle -> C clear and acc = index if found
; (t5 = start offset)
;---------------------------------------------------------------------------------------
str_find:
        lda #0
        sta t5
        sta t5+1
str_find_from:
        lda r2
        ldx r2+1
        jsr str_info
        lda str_len
        sta t3
        lda str_len+1
        sta t3+1
        jsr fp0_to_fp1                  ; fp1 = needle
        lda r3
        ldx r3+1
        jsr str_info                    ; fp0 = haystack, str_len = its length
        ; positions t5 .. len - nlen
        sec
        lda str_len
        sbc t3
        sta t4
        lda str_len+1
        sbc t3+1
        sta t4+1
        bcc _no
        clc
        lda fp0
        adc t5
        sta fp0
        lda fp0+1
        adc t5+1
        sta fp0+1
_pos:   lda t4+1
        cmp t5+1
        bcc _no
        bne +
        lda t4
        cmp t5
        bcc _no
+       ; compare t3 bytes at fp0 with fp1
        lda t3
        sta t0
        lda t3+1
        sta t0+1
        ldx #3
-       lda fp0,x
        sta fp2,x
        dex
        bpl -
        lda fp1
        sta t1
        lda fp1+1
        sta t1+1
-       lda t0
        ora t0+1
        beq _found
        ldz #0
        lda [fp2],z
        cmp [fp1],z
        bne _miss
        inw fp2
        inw fp1
        dew t0
        bra -
_miss:  lda t1
        sta fp1
        lda t1+1
        sta fp1+1
        inw fp0
        inw t5
        bra _pos
_found: lda t5
        sta acc
        lda t5+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        clc
        rts
_no:    sec
        rts


bi_list_sort:      #TAILCALL TAIL_P, xp_bi_list_sort
bi_sorted:         #TAILCALL TAIL_P, xp_bi_sorted
bi_str_format:     #TAILCALL TAIL_P, xp_bi_str_format
format_spec:       #TAILCALL TAIL_P, xp_format_spec
pad_body:          #TAILCALL TAIL_P, xp_pad_body
str_percent:       #TAILCALL TAIL_P, xp_str_percent
fs_fill:        .byte ' '
fs_align:       .byte 0
fs_sign:        .byte '-'
fs_width:       .word 0
fs_prec:        .word $ffff
fs_type:        .byte 0
fs_comma:       .byte 0

;---------------------------------------------------------------------------------------
; list
;---------------------------------------------------------------------------------------
self_list:
        #ARG 0
        sta r0
        stx r0+1
        rts

bi_list_append:
        #NARGS 2, 2
        jsr self_list
        #ARG 1
        sta r1
        stx r1+1
        jsr list_append
        #RET_NONE

bi_list_extend:
        #NARGS 2, 2
        #ARG 0                          ; self (Python code in the iteration reuses argv)
        #PUSH
        #ARG 1
        jsr list_from_iterable
        sta r3
        stx r3+1
        #POP
        sta r0
        stx r0+1
        lda r3
        ldx r3+1
        jsr list_extend_r0
        #RET_NONE

bi_list_pop:
        #NARGS 1, 2
        jsr self_list
        jsr seq_len
        lda t0
        ora t0+1
        bne +
        #RAISE EXC_INDEX, "pop from empty list"
+       lda t0
        sta t5
        lda t0+1
        sta t5+1
        lda npos
        cmp #2
        beq +
        lda #$ff                        ; -1
        ldx #$ff
        bra ++
+       #ARG 1
+       jsr norm_index
        bcc +
        jmp raise_index
+       lda t0
        ldx t0+1
        jmp list_del_at

bi_list_insert:          #TAILS xs_list_insert

; index of argv[1] in self (list or tuple) -> t2, C set if absent
list_find:
        #ARG 0
        sta r3
        stx r3+1
        jsr seq_len
        lda t0
        sta t5
        lda t0+1
        sta t5+1
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp t5
        bne +
        lda t2+1
        cmp t5+1
        bne +
        sec
        rts
+       lda t2
        pha
        lda t2+1
        pha
        lda t5
        pha
        lda t5+1
        pha
        #ARG 0
        jsr seq_get_t2
        sta r3
        stx r3+1
        #ARG 1
        sta r2
        stx r2+1
        jsr obj_eq
        pla
        sta t5+1
        pla
        sta t5
        pla
        sta t2+1
        pla
        sta t2
        bcs +
        inw t2
        bra -
+       clc
        rts

bi_list_index:
        #NARGS 2, 2
        jsr list_find
        bcc +
        #RAISE EXC_VALUE, "value is not in list"
+       lda t2
        sta acc
        lda t2+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jmp int_new

bi_list_remove:
        #NARGS 2, 2
        jsr list_find
        bcc +
        #RAISE EXC_VALUE, "list.remove(x): x not in list"
+       jsr self_list
        lda t2
        ldx t2+1
        jsr list_del_at
        #RET_NONE

bi_list_count:
        #NARGS 2, 2
        #ARG 0
        jsr seq_len
        lda #0
        sta t6
        sta t6+1
        sta t2
        sta t2+1
-       lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _done
+       ldx #0
-       lda t0,x
        pha
        inx
        cpx #6
        bne -
        lda t6
        pha
        lda t6+1
        pha
        #ARG 0
        jsr seq_get_t2
        sta r3
        stx r3+1
        #ARG 1
        sta r2
        stx r2+1
        jsr obj_eq
        pla
        sta t6+1
        pla
        sta t6
        ldx #5
-       pla
        sta t0,x
        dex
        bpl -
        bcc +
        inw t6
+       inw t2
        bra ---
_done:  lda t6
        sta acc
        lda t6+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jmp int_new

bi_list_reverse:         #TAILS xs_list_reverse

bi_list_copy:
        #NARGS 1, 1
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        sta r0
        stx r0+1
        #ARG 0
        jsr list_extend_r0
        lda r0
        ldx r0+1
        rts

bi_list_clear:
        #NARGS 1, 1
        jsr self_list
        sta p0
        stx p0+1
        ldz #4
        lda #0
        sta [p0],z
        inz
        sta [p0],z
        #RET_NONE

;---------------------------------------------------------------------------------------
; dict
;---------------------------------------------------------------------------------------
; iter_view_init - p0 = a new dict iterator over r0: its size, keys left = size
; (last key: 0 from alloc)
iter_view_init:
        lda r0
        sta p1
        lda r0+1
        sta p1+1
        ldz #4
        lda [p1],z
        ldz #12
        sta [p0],z
        ldz #14
        sta [p0],z
        ldz #5
        lda [p1],z
        ldz #13
        sta [p0],z
        ldz #15
        sta [p0],z
        rts

;---------------------------------------------------------------------------------------
; it_dpair - the next pair of the dict iterator p2 (seq.asm it_dict, it_values,
; it_items): C clear and p1 -> the pair, or C set at the end. As CPython: a change of
; size raises RuntimeError, and so does finding more keys than the dict had ("keys
; changed": a key deleted and another added). A delete moves the later pairs down, so
; the position follows the last key returned (CPython leaves a hole instead).
; Uses t0-t3.
;---------------------------------------------------------------------------------------
it_dpair:
        ldz #6
        lda [p2],z
        sta p0
        inz
        lda [p2],z
        sta p0+1
        ldz #12                         ; the size
        lda [p2],z
        ldz #4
        cmp [p0],z
        bne _size
        ldz #13
        lda [p2],z
        ldz #5
        cmp [p0],z
        beq +
_size:  jmp raise_dict_changed
+       ldz #8                          ; t2 = position
        lda [p2],z
        sta t2
        inz
        lda [p2],z
        sta t2+1
        ora t2
        beq _at
        dew t2                          ; the last key is still just before it?
        lda t2
        sta t3
        lda t2+1
        sta t3+1
        jsr _is_last
        beq _found
_down:  lda t2                          ; no: pairs moved down; find it lower
        ora t2+1
        beq _gone
        dew t2
        jsr _is_last
        bne _down
_found: inw t2
        bra _at
_gone:  lda t3                          ; it was deleted itself: one back
        sta t2
        lda t3+1
        sta t2+1
_at:    ldz #4                          ; the end?
        lda t2
        cmp [p0],z
        inz
        lda t2+1
        sbc [p0],z
        bcc _more
        rts
_more:  ldz #1
        lda [p0],z
        and #F_SET                      ; (sets do not count)
        bne _take
        ldz #14                         ; keys left
        lda [p2],z
        inz
        ora [p2],z
        bne +
        #RAISE EXC_RUNTIME, "dictionary keys changed during iteration"
+       ldz #14
        lda [p2],z
        sec
        sbc #1
        sta [p2],z
        inz
        lda [p2],z
        sbc #0
        sta [p2],z
_take:  jsr _pair
        ldz #0                          ; the last key; the position after it
        lda [p1],z
        ldz #16
        sta [p2],z
        ldz #1
        lda [p1],z
        ldz #17
        sta [p2],z
        inw t2
        ldz #8
        lda t2
        sta [p2],z
        inz
        lda t2+1
        sta [p2],z
        clc
        rts
; p1 -> pair t2
_pair:  lda t2
        asl
        sta t0
        lda t2+1
        rol
        sta t0+1
        jmp list_item_ptr
; Z set when pair t2's key is the last key returned
_is_last:
        jsr _pair
        ldz #0
        lda [p1],z
        ldz #16
        cmp [p2],z
        bne +
        ldz #1
        lda [p1],z
        ldz #17
        cmp [p2],z
+       rts

; the dict or set p0 changed size while an iterator went through it (it_dpair)
raise_dict_changed:
        ldz #1
        lda [p0],z
        and #F_SET
        bne _set
        #RAISE EXC_RUNTIME, "dictionary changed size during iteration"
_set:   #RAISE EXC_RUNTIME, "Set changed size during iteration"

bi_dict_keys:
        lda #IT_DICT
        bra dict_view
bi_dict_values:
        lda #IT_VALUES
        bra dict_view
bi_dict_items:
        lda #IT_ITEMS
dict_view:
        ; a list snapshot (Python 3 returns a live view)
        pha
        #NARGS 1, 1
        #ARG 0
        sta r0
        stx r0+1
        pla
        jsr iter_alloc
        jmp list_from_iterable

bi_dict_get_m:
        #NARGS 2, 3
        #ARG 0
        sta r0
        stx r0+1
        #ARG 1
        sta r1
        stx r1+1
        jsr dict_get
        bcs +
        rts
+       lda npos
        cmp #3
        beq +
        #RET_NONE
+       #ARG 2
        rts

bi_dict_pop:
        #NARGS 2, 3
        #ARG 0
        sta r0
        stx r0+1
        #ARG 1
        sta r1
        stx r1+1
        jsr dict_get
        bcs _miss
        pha
        phx
        jsr dict_del
        plx
        pla
        rts
_miss:  lda npos
        cmp #3
        beq +
        jmp raise_key
+       #ARG 2
        rts

bi_dict_setdefault:
        #NARGS 2, 3
        #ARG 0
        sta r0
        stx r0+1
        #ARG 1
        sta r1
        stx r1+1
        jsr dict_get
        bcs +
        rts
+       lda #R_NONE
        ldx #0
        ldy npos
        cpy #3
        bne +
        #ARG 2
+       sta r2
        stx r2+1
        jsr dict_set
        lda r2
        ldx r2+1
        rts

bi_dict_update:
        #NARGS 1, 2
        lda npos
        cmp #2
        bne +
        #ARG 1
        sta r2
        stx r2+1
        #ARG 0
        sta r0
        stx r0+1
        jsr dict_update_from
+       #RET_NONE

bi_dict_clear:
        #NARGS 1, 1
        #ARG 0
dict_clear:                             ; (A/X = dict or set) no pairs, no index
        sta p0
        stx p0+1
        ldz #4
        lda #0
        sta [p0],z
        inz
        sta [p0],z
        ldz #10
        sta [p0],z
        inz
        sta [p0],z
        #RET_NONE

bi_dict_copy:
        #NARGS 1, 1
        jsr dict_new
        sta r0
        stx r0+1
        #ARG 0
        sta r2
        stx r2+1
        lda r0
        pha
        lda r0+1
        pha
        jsr dict_update_from
        plx
        pla
        rts

;---------------------------------------------------------------------------------------
; SEND - iterator value -> iterator next-item (into the loop) | result (to the exit):
; a step of yield from. A generator gets the value and runs inline, as FOR_ITER runs it
; (gen.asm: its return value is the result); another iterator gives its next item, and
; takes only None.
;---------------------------------------------------------------------------------------
op_send:
        #POP
        ldy send_throw                  ; throw() / close() for the iterator
        bne _thrown
        sta gen_sent
        stx gen_sent+1
        #PEEK 0
        jsr type_of
        cmp #T_GEN
        bne _iter
        lda #0
        sta gen_exc
        sta gen_exc+1
        lda #FR_FORIT | FR_SENDX
        jmp gen_resume
_iter:  lda gen_sent+1
        bne _bad
        lda gen_sent
        cmp #R_NONE
        bne _bad
        #PEEK 0
        jsr iter_next
        bcs _end
        #PUSH
        inw ip
        inw ip
        jmp vm_loop
_end:   lda #FR_SENDX                   ; its result: None
        sta gen_mode
        lda #R_NONE
        ldx #0
        jmp gen_exit
_bad:
        #PEEK 0
        ldy #RT_SEND
        jmp raise_typed
_thrown:
        ldy #0
        sty send_throw
        sta gen_exc
        stx gen_exc+1
        #PEEK 0
        jsr type_of
        cmp #T_GEN
        bne _here
        lda #R_NONE                     ; a generator: raised at its yield
        sta gen_sent
        lda #0
        sta gen_sent+1
        lda #FR_FORIT | FR_SENDX
        jmp gen_resume
_here:  lda gen_exc                     ; another iterator: raised here
        ldx gen_exc+1
; gen_raise - raise A/X (an exception instance) at the current ip
gen_raise:
        sta cur_exc
        stx cur_exc+1
        lda #0
        sta gen_exc
        sta gen_exc+1
        sta exc_ip_set
        jmp throw
send_throw:     .byte 0

;---------------------------------------------------------------------------------------
; gen_throw_at - (gen_resume) its frame is back and gen_exc is to be raised at its yield.
; At a yield from (the next instruction is a JUMP to a SEND) the iterator gets it:
; SEND throws it in (send_throw), as CPython's throw() and close() do.
;---------------------------------------------------------------------------------------
gen_throw_at:
        ldz #0
        lda [ip],z
        cmp #OP_JUMP
        bne _raise
        inz
        lda [ip],z
        sta fp1
        inz
        lda [ip],z
        sta fp1+1
        lda ip+2
        sta fp1+2
        lda #0
        sta fp1+3
        ldz #0
        lda [fp1],z
        cmp #OP_SEND
        bne _raise
        lda gen_exc                     ; what SEND gets, and how
        ldx gen_exc+1
        #PUSH
        inc send_throw
        lda #0
        sta gen_exc
        sta gen_exc+1
        jmp vm_loop
_raise: lda gen_exc
        ldx gen_exc+1
        bra gen_raise

;---------------------------------------------------------------------------------------
; gen_p479 - (vm_except, before frames are dropped) a StopIteration leaving a
; generator's frame becomes RuntimeError (PEP 479)
;---------------------------------------------------------------------------------------
gen_p479:
        lda cur_exc
        sta r2
        lda cur_exc+1
        sta r2+1
        lda #EXC_STOPITER
        jsr exc_is
        bcc _no
        ldx runlev                      ; the frame it unwinds to: the newest handler's
        dex                             ; in this level, or the level's
        lda hsp
        cmp lev_hsp_lo,x
        bne _hnd
        lda hsp+1
        cmp lev_hsp_hi,x
        bne _hnd
        lda lev_frp_lo,x
        sta t0
        lda lev_frp_hi,x
        sta t0+1
        bra _walk
_hnd:   sec
        lda hsp
        sbc #8
        sta fp1
        lda hsp+1
        sbc #0
        sta fp1+1
        lda #<(HSTACK >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        ldz #4
        lda [fp1],z
        sta t0
        inz
        lda [fp1],z
        sta t0+1
_walk:  lda frp                         ; the frames it leaves: frp down to t0
        sta fp1
        lda frp+1
        sta fp1+1
        lda #<(FSTACK >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
-       lda fp1+1
        cmp t0+1
        bcc _no
        bne +
        lda fp1
        cmp t0
        bcc _no
        beq _no
+       sec
        lda fp1
        sbc #8
        sta fp1
        bcs +
        dec fp1+1
+       ldz #6
        lda [fp1],z
        and #FR_GEN
        beq -
        #RAISE EXC_RUNTIME, "generator raised StopIteration"
_no:    rts

op_unpack_ex:
        jsr x_unpack_ex
        jmp vm_loop
x_unpack_ex:    #TAILCALL TAIL_H, xh_unpack_ex   ; (tailh.asm)

; gen_stop - raise StopIteration for a generator that returned A/X (stop_value)
gen_stop:       #TAILCALL TAIL_X, xg_stop

; gen_make - (call_py) a generator instead of the call (tail X, args.asm)
gen_make:       #TAILCALL TAIL_X, xg_create

;---------------------------------------------------------------------------------------
; gen_alive - p0 = generator gen_ref, state GS_RUN: C set if its frame is still on the
; frame stack (it is running), clear if an exception dropped it
;---------------------------------------------------------------------------------------
gen_alive:
        ldz #14
        lda [p0],z
        sta fp2
        inz
        lda [p0],z
        sta fp2+1
        lda #<(FSTACK >> 16)
        sta fp2+2
        lda #0
        sta fp2+3
        lda fp2+1                       ; below the top frame?
        cmp frp+1
        bcc +
        bne _no
        lda fp2
        cmp frp
        bcs _no
+       ldz #6
        lda [fp2],z
        and #FR_GEN
        beq _no
        ldz #4                          ; and that frame's generator is this one
        lda [fp2],z
        sta t0
        inz
        lda [fp2],z
        sta t0+1
        ldy #2
        lda (t0),y
        cmp gen_ref
        bne _no
        iny
        lda (t0),y
        cmp gen_ref+1
        bne _no
        sec
        rts
_no:    clc
        rts

; gen_end - p0 = a generator: it is finished (it lets go of its frame)
gen_end:
        lda #GS_DONE
        ldz #12
        sta [p0],z
        lda #0
        inz
        sta [p0],z
        ldz #6
        sta [p0],z
        inz
        sta [p0],z
        inz
        sta [p0],z
        inz
        sta [p0],z
        rts

; gen_next_native - A/X = generator -> C clear and A/X = the next value, or C set (it
; is exhausted). gen_send_native: the same with gen_sent = the value for its yield.
gen_next_native:
        ldy #R_NONE
        sty gen_sent
        ldy #0
        sty gen_sent+1
gen_send_native:
        ldy #0
        sty gen_exc
        sty gen_exc+1
gen_resume_native:                      ; (gen_exc set: throw() / close())
        #PUSH
        #NATIVE_SAVE
        jsr _run
        sta vcn_a
        stx vcn_x
        lda #0
        rol a
        sta gen_c
        #NATIVE_RESTORE
        #DROP 1
        lda gen_c
        lsr a
        lda vcn_a
        ldx vcn_x
        rts
_run:   jsr lev_enter
        lda #FR_NESTED
        jmp gen_resume

;---------------------------------------------------------------------------------------
; generator methods (gen.asm has the rest; these are in overlay R)
;---------------------------------------------------------------------------------------
bi_gen_send:    #TAILCALL TAIL_X, xg_send        ; (args.asm)
bi_gen_close:   #TAILCALL TAIL_X, xg_close
bi_gen_throw:   #TAILCALL TAIL_X, xg_throw
