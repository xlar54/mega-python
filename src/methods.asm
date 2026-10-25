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
        sta p0
        stx p0+1
        ldz #4
        lda #0
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
