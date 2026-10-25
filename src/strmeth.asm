;=======================================================================================
; Tail S (swapped in at TAIL by need_s): the str methods that never run Python code
; (case, is*, find/index/count, replace, startswith/endswith, strip, split,
; splitlines, join, center/ljust/rjust/zfill, title/capitalize). Overlay R has a
; bi_str_* stub for each (methods.asm). str_find stays in R: "in" uses it.
;=======================================================================================
;---------------------------------------------------------------------------------------
; str
;---------------------------------------------------------------------------------------
xs_str_upper:
        lda #0
        bra str_case
xs_str_lower:
        lda #1
str_case:
        sta t6
        #NARGS 1, 1
        jsr self_str
        lda sbp
        pha
        lda sbp+1
        pha
-       lda str_len
        ora str_len+1
        beq +
        ldz #0
        lda [fp0],z
        jsr case_char
        jsr sb_putc
        inw fp0
        dew str_len
        bra -
+       plx
        pla
        jmp sb_take
; is* predicates: every char passes (and at least one char)
xs_str_isdigit:
        lda #0
        bra str_is
xs_str_isalpha:
        lda #1
        bra str_is
xs_str_isalnum:
        lda #2
        bra str_is
xs_str_isspace:
        lda #3
        bra str_is
xs_str_isupper:
        lda #4
        bra str_is
xs_str_islower:
        lda #5
str_is: sta t6
        #NARGS 1, 1
        jsr self_str
        lda str_len
        ora str_len+1
        beq _no
        lda #0
        sta t5                          ; cased chars seen (isupper/islower)
-       lda str_len
        ora str_len+1
        beq _yes
        ldz #0
        lda [fp0],z
        jsr char_class                  ; -> t7 bits: 1 digit 2 alpha 4 space 8 upper 16 lower
        ldx t6
        lda t7
        and is_mask,x
        bne _ok
        ; isupper/islower allow uncased chars
        cpx #4
        bcc _no
        lda t7
        and #24
        bne _no
        bra _next
_ok:    cpx #4
        bcc _next
        inc t5
_next:  inw fp0
        dew str_len
        bra -
_yes:   lda t6
        cmp #4
        bcc +
        lda t5
        beq _no
+       lda #1
        jmp bool_from_a
_no:    lda #0
        jmp bool_from_a
is_mask:        .byte 1, 2, 3, 4, 8, 16

char_class:
        ldx #0
        cmp #'0'
        bcc +
        cmp #'9'+1
        bcs +
        ldx #1
+       cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        ldx #2+8
+       cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        ldx #2+16
+       cmp #33
        bcs +
        ldx #4
+       stx t7
        rts

; is A whitespace? -> C set
is_space:
        cmp #33
        rts
; inverted: C clear means space
; (callers use: jsr is_space / bcc -> space)


xs_str_find_m:
        #NARGS 2, 3
        jsr find_args
        jsr str_find_from
        bcc +
        lda #$ff
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
+       jmp int_new
xs_str_index:
        #NARGS 2, 3
        jsr find_args
        jsr str_find_from
        bcc +
        #RAISE EXC_VALUE, "substring not found"
+       jmp int_new
; r3 = self, r2 = sub, t5 = start
find_args:
        #ARG 1
        jsr need_str
        lda r3
        sta r2
        lda r3+1
        sta r2+1
        #ARG 0
        sta r3
        stx r3+1
        lda #0
        sta t5
        sta t5+1
        lda npos
        cmp #3
        bne +
        #ARG 2
        jsr need_int
        bit acc+3
        bmi +
        lda acc
        sta t5
        lda acc+1
        sta t5+1
+       rts

xs_str_count:
        #NARGS 2, 2
        jsr find_args
        lda #0
        sta t6
        sta t6+1
-       jsr str_find_from
        bcs +
        inw t6
        ; continue after the match (at least one char)
        lda r2
        ldx r2+1
        jsr str_info
        clc
        lda acc
        adc str_len
        sta t5
        lda acc+1
        adc str_len+1
        sta t5+1
        lda str_len
        ora str_len+1
        bne -
        inw t5
        bra -
+       lda t6
        sta acc
        lda t6+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jmp int_new

xs_str_replace:
        #NARGS 3, 4
        #ARG 1
        jsr need_str
        #ARG 2
        jsr need_str
        lda #$ff                        ; count limit
        sta t6
        sta t6+1
        lda npos
        cmp #4
        bne +
        #ARG 3
        jsr need_int
        lda acc
        sta t6
        lda acc+1
        sta t6+1
+       lda sbp
        pha
        lda sbp+1
        pha
        lda #0
        sta t7                          ; copied up to
        sta t7+1
        sta t5
        sta t5+1
_loop:  lda t6
        ora t6+1
        beq _tail
        #ARG 1
        sta r2
        stx r2+1
        #ARG 0
        sta r3
        stx r3+1
        jsr str_find_from
        bcs _tail
        ; copy self[t7 : acc], then new
        jsr _copy_to_acc
        #ARG 2
        jsr sb_put_str
        #ARG 1
        jsr str_info
        clc
        lda acc
        adc str_len
        sta t7
        sta t5
        lda acc+1
        adc str_len+1
        sta t7+1
        sta t5+1
        dew t6
        lda str_len
        ora str_len+1
        bne _loop
        ; empty pattern: copy one char and step past it
        #ARG 0
        jsr str_info
        lda t5+1
        cmp str_len+1
        bcc +
        lda t5
        cmp str_len
        bcs _tail
+       clc
        lda fp0
        adc t5
        sta fp0
        lda fp0+1
        adc t5+1
        sta fp0+1
        ldz #0
        lda [fp0],z
        jsr sb_putc
        inw t5
        inw t7
        bra _loop
_tail:  #ARG 0
        jsr str_info
        lda str_len
        sta acc
        lda str_len+1
        sta acc+1
        jsr _copy_to_acc
        plx
        pla
        jmp sb_take
; append self[t7 : acc]
_copy_to_acc:
        #ARG 0
        jsr str_info
        clc
        lda fp0
        adc t7
        sta fp2
        lda fp0+1
        adc t7+1
        sta fp2+1
        lda fp0+2
        sta fp2+2
        lda #0
        sta fp2+3
        sec
        lda acc
        sbc t7
        sta t0
        lda acc+1
        sbc t7+1
        sta t0+1
-       lda t0
        ora t0+1
        beq +
        ldz #0
        lda [fp2],z
        jsr sb_putc
        inw fp2
        dew t0
        bra -
+       rts

; startswith / endswith (prefix may be a tuple)
xs_str_startswith:
        lda #0
        bra str_sw
xs_str_endswith:
        lda #1
str_sw: sta t6
        #NARGS 2, 2
        #ARG 1
        sta r3
        stx r3+1
        jsr type_of
        cmp #T_TUPLE
        bne _one
        lda r3
        ldx r3+1
        jsr seq_len
        lda t0
        sta t6+1
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp t6+1
        bcs _no
        lda t2
        pha
        #ARG 1
        jsr seq_get_t2
        jsr _test
        pla
        sta t2
        bcs _yes
        inc t2
        bra -
_one:   lda r3
        ldx r3+1
        jsr _test
        bcs _yes
_no:    lda #0
        jmp bool_from_a
_yes:   lda #1
        jmp bool_from_a
; does self start/end with string A/X? -> C set
_test:  jsr need_str
        lda str_len
        sta t3
        lda str_len+1
        sta t3+1
        jsr fp0_to_fp1
        jsr self_str
        sec
        lda str_len
        sbc t3
        sta t4
        lda str_len+1
        sbc t3+1
        sta t4+1
        bcc _f
        lda t6
        beq +
        clc                             ; endswith: compare at len - plen
        lda fp0
        adc t4
        sta fp0
        lda fp0+1
        adc t4+1
        sta fp0+1
+       lda t3
        sta str_len
        lda t3+1
        sta str_len+1
        jmp mem_eq
_f:     clc
        rts

; strip / lstrip / rstrip([chars])
xs_str_strip:
        lda #3
        bra str_strip
xs_str_lstrip:
        lda #1
        bra str_strip
xs_str_rstrip:
        lda #2
str_strip:
        sta t6
        #NARGS 1, 2
        lda #0
        sta r3+1
        lda npos
        cmp #2
        bne +
        #ARG 1
        jsr none_to_null
        sta r3
        stx r3+1
        cpx #0
        beq +
        jsr need_str                    ; r3 = chars
+       jsr self_str
        lda t6
        and #1
        beq _right
_l:     lda str_len
        ora str_len+1
        beq _right
        ldz #0
        lda [fp0],z
        jsr strip_char
        bcc _right
        inw fp0
        dew str_len
        bra _l
_right: lda t6
        and #2
        beq _done
_r:     lda str_len
        ora str_len+1
        beq _done
        ; last char
        clc
        lda fp0
        adc str_len
        sta fp1
        lda fp0+1
        adc str_len+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        dew fp1
        ldz #0
        lda [fp1],z
        jsr strip_char
        bcc _done
        dew str_len
        bra _r
_done:  ldx #3
-       lda fp0,x
        sta fp2,x
        dex
        bpl -
        jmp str_from_far
; strip_char - A: strip it? -> C set (whitespace, or one of the chars in r3)
strip_char:
        ldx r3+1
        bne _set
        cmp #33
        bcc _yes
        clc
        rts
_yes:   sec
        rts
_set:   sta t0
        lda fp0
        pha
        lda fp0+1
        pha
        lda str_len
        pha
        lda str_len+1
        pha
        lda r3
        ldx r3+1
        jsr str_info
        ldz #0
-       cpz str_len
        bcs _not
        lda [fp0],z
        cmp t0
        beq _in
        inz
        bra -
_in:    sec
        bra +
_not:   clc
+       pla
        sta str_len+1
        pla
        sta str_len
        pla
        sta fp0+1
        pla
        sta fp0
        lda #HEAP_BANK
        sta fp0+2
        lda #0
        sta fp0+3
        rts

; split(sep=None, maxsplit=-1)
xs_str_split:
        #NARGS 1, 3
        lda #$ff
        sta t6                          ; maxsplit (-1 = no limit)
        sta t6+1
        lda #0
        sta r3+1
        lda npos
        cmp #2
        bcc +
        #ARG 1
        jsr none_to_null
        sta r3
        stx r3+1
        cpx #0
        beq ++
        jsr need_str
        lda str_len
        ora str_len+1
        bne +
        #RAISE EXC_VALUE, "empty separator"
+       lda npos
        cmp #3
        bne +
        #ARG 2
        jsr need_int
        lda acc
        sta t6
        lda acc+1
        sta t6+1
+       lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [out]
        lda #0
        sta t7                          ; position
        sta t7+1
        lda r3+1
        bne _sep
        ; whitespace split
_ws:    jsr self_str
        jsr _skip_ws
        jsr sp_at_end
        bcs _done
        lda t6
        ora t6+1
        bne +
        ; maxsplit reached: the rest (rstripped) is one item
        jsr _rest
        bra _done
+       lda t7
        sta t5
        lda t7+1
        sta t5+1
-       jsr sp_at_end
        bcs +
        jsr sp_char
        cmp #33
        bcc +
        inw t7
        bra -
+       jsr sp_piece                      ; self[t5:t7]
        dew t6
        bra _ws
_done:  #POP
        rts
_sep:   ; explicit separator
        lda t7
        sta t5
        lda t7+1
        sta t5+1
        lda t6
        ora t6+1
        beq _last
        #ARG 0
        sta r3
        stx r3+1
        lda r3
        pha
        lda r3+1
        pha
        #ARG 1
        sta r2
        stx r2+1
        lda t5
        pha
        lda t5+1
        pha
        jsr str_find_from
        pla
        sta t5+1
        pla
        sta t5
        pla
        sta r3+1
        pla
        sta r3
        bcs _last
        lda acc
        sta t7
        lda acc+1
        sta t7+1
        jsr sp_piece
        #ARG 1
        jsr str_info
        clc
        lda t7
        adc str_len
        sta t7
        lda t7+1
        adc str_len+1
        sta t7+1
        dew t6
        #ARG 1
        sta r3
        stx r3+1
        bra _sep
_last:  jsr self_str
        lda str_len
        sta t7
        lda str_len+1
        sta t7+1
        jsr sp_piece
        bra _done
_rest:  lda t7
        sta t5
        lda t7+1
        sta t5+1
        jsr self_str
        ; end = len minus trailing whitespace
        lda str_len
        sta t7
        lda str_len+1
        sta t7+1
-       lda t7
        cmp t5
        bne +
        lda t7+1
        cmp t5+1
        beq ++
+       dew t7
        jsr sp_char
        inw t7
        cmp #33
        bcs +
        dew t7
        bra -
+       jmp sp_piece
_skip_ws:
-       jsr sp_at_end
        bcs +
        jsr sp_char
        cmp #33
        bcs +
        inw t7
        bra -
+       rts
sp_at_end:                                ; C set when t7 >= len (fp0/str_len = self)
        lda t7+1
        cmp str_len+1
        bcc +
        bne _y
        lda t7
        cmp str_len
        bcc +
_y:     sec
        rts
+       clc
        rts
sp_char:                                ; A = self[t7]
        clc
        lda fp0
        adc t7
        sta fp1
        lda fp0+1
        adc t7+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        ldz #0
        lda [fp1],z
        rts
; append self[t5:t7] to the list on the stack
sp_piece:
        jsr self_str
        clc
        lda fp0
        adc t5
        sta fp2
        lda fp0+1
        adc t5+1
        sta fp2+1
        lda fp0+2
        sta fp2+2
        lda #0
        sta fp2+3
        sec
        lda t7
        sbc t5
        sta str_len
        lda t7+1
        sbc t5+1
        sta str_len+1
        ldx #0
-       lda t5,x
        pha
        inx
        cpx #6
        bne -
        jsr str_from_far
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        ldx #5
-       pla
        sta t5,x
        dex
        bpl -
        lda #0
        sta r0
        sta r0+1
        sta r1
        sta r1+1
        jmp self_str

xs_str_splitlines:
        #NARGS 1, 1
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH
        lda #0
        sta t5
        sta t5+1
        sta t7
        sta t7+1
        jsr self_str
_loop:  jsr sp_at_end
        bcs _end
        jsr sp_char
        cmp #10
        beq _nl
        inw t7
        bra _loop
_nl:    jsr sp_piece
        inw t7
        lda t7
        sta t5
        lda t7+1
        sta t5+1
        bra _loop
_end:   lda t7
        cmp t5
        bne +
        lda t7+1
        cmp t5+1
        beq ++
+       jsr sp_piece
+       #POP
        rts

xs_str_join:
        #NARGS 2, 2
        #ARG 0                          ; the separator (Python code reuses argv)
        #PUSH
        #ARG 1
        jsr list_from_iter_s            ; (it may run Python: back to tail S after)
        #PUSH
        lda sbp
        pha
        lda sbp+1
        pha
        lda #0
        sta t2
        sta t2+1
-       #PEEK 0
        jsr seq_len
        lda t2
        cmp t0
        bne +
        lda t2+1
        cmp t0+1
        beq _done
+       lda t2
        ora t2+1
        beq +
        #PEEK 1
        jsr sb_put_str
+       #PEEK 0
        jsr seq_get_t2
        pha
        phx
        jsr type_of
        cmp #T_STR
        beq +
        #RAISE EXC_TYPE, "join() expects strings"
+       plx
        pla
        jsr sb_put_str
        inw t2
        bra -
_done:  plx
        pla
        jsr sb_take
        sta t0
        stx t0+1
        #DROP 2
        lda t0
        ldx t0+1
        rts

; center / ljust / rjust(width[, fill]); zfill(width)
xs_str_center:
        lda #'^'
        bra str_just
xs_str_ljust:
        lda #'<'
        bra str_just
xs_str_rjust:
        lda #'>'
str_just:
        sta fs_align
        #NARGS 2, 3
        lda #' '
        sta fs_fill
        lda npos
        cmp #3
        bne +
        #ARG 2
        jsr need_str
        ldz #0
        lda [fp0],z
        sta fs_fill
+       #ARG 1
        jsr need_int
        lda acc
        sta fs_width
        lda acc+1
        sta fs_width+1
        bit acc+3
        bpl +
        lda #0
        sta fs_width
        sta fs_width+1
+       lda sbp
        pha
        lda sbp+1
        pha
        #ARG 0
        jsr pad_body
        plx
        pla
        jmp sb_take
xs_str_zfill:
        #NARGS 2, 2
        lda #'='
        sta fs_align
        lda #'0'
        sta fs_fill
        #ARG 1
        jsr need_int
        lda acc
        sta fs_width
        lda acc+1
        sta fs_width+1
        lda sbp
        pha
        lda sbp+1
        pha
        #ARG 0
        jsr pad_body
        plx
        pla
        jmp sb_take

xs_str_title:
        lda #1
        bra str_title
xs_str_capitalize:
        lda #0
str_title:
        sta t4                          ; 1 = title, 0 = capitalize
        #NARGS 1, 1
        jsr self_str
        lda sbp
        pha
        lda sbp+1
        pha
        lda #1
        sta t5                          ; the next char starts a word
-       lda str_len
        ora str_len+1
        beq _done
        ldz #0
        lda [fp0],z
        ldy #1                          ; lower unless at a word start
        ldx t5
        beq +
        dey
+       sty t6
        jsr case_char
        jsr sb_putc
        lda #0
        sta t5
        lda t4
        beq _next
        ldz #0                          ; title: a word starts after a non-letter
        lda [fp0],z
        jsr char_class
        lda t7
        and #2
        eor #2
        sta t5
_next:  inw fp0
        dew str_len
        bra -
_done:  plx
        pla
        jmp sb_take

;---------------------------------------------------------------------------------------
; list methods that never run Python code
;---------------------------------------------------------------------------------------
xs_list_insert:
        #NARGS 3, 3
        jsr self_list
        jsr seq_len
        lda t0
        sta t5
        lda t0+1
        sta t5+1
        #ARG 1
        jsr need_int
        ; clamp to 0..len (negative counts from the end)
        bit acc+3
        bpl +
        clc
        lda acc
        adc t5
        sta acc
        lda acc+1
        adc t5+1
        sta acc+1
        lda acc+2
        adc #0
        sta acc+2
        lda acc+3
        adc #0
        sta acc+3
        bpl +
        lda #0
        sta acc
        sta acc+1
        sta acc+2
        sta acc+3
+       lda acc+2
        ora acc+3
        bne _end
        lda acc+1
        cmp t5+1
        bcc _ok
        bne _end
        lda acc
        cmp t5
        bcc _ok
_end:   lda t5
        sta acc
        lda t5+1
        sta acc+1
_ok:    lda acc
        pha
        lda acc+1
        pha
        ; append (grows), then shift items index..len-1 up one
        #ARG 2
        sta r1
        stx r1+1
        jsr list_append
        pla
        sta t6+1
        pla
        sta t6
        jsr self_list
        sta p0
        stx p0+1
        jsr seq_len
        ; move (len - 1 - index) items from &items[index] to &items[index+1], backwards
        lda t6
        sta t0
        lda t6+1
        sta t0+1
        jsr list_item_ptr               ; p1 = &items[index]
        lda r0
        ldx r0+1
        jsr seq_len
        sec
        lda t0
        sbc #1
        sta t1
        lda t0+1
        sbc #0
        sta t1+1
        sec
        lda t1
        sbc t6
        sta t1
        lda t1+1
        sbc t6+1
        sta t1+1                        ; count
        ; from the end: dst = p1 + 2*count, src = dst - 2
        asw t1
        clc
        lda p1
        adc t1
        sta p2
        lda p1+1
        adc t1+1
        sta p2+1
-       lda p2
        cmp p1
        bne +
        lda p2+1
        cmp p1+1
        beq _put
+       ldz #0
        sec
        lda p2
        sbc #2
        sta p3
        lda p2+1
        sbc #0
        sta p3+1
        lda [p3],z
        sta [p2],z
        inz
        lda [p3],z
        sta [p2],z
        lda p3
        sta p2
        lda p3+1
        sta p2+1
        bra -
_put:   ldz #0
        #ARG 2
        sta [p1],z
        inz
        txa
        sta [p1],z
        #RET_NONE

xs_list_reverse:
        #NARGS 1, 1
        jsr self_list
        sta p0
        stx p0+1
        jsr seq_len
        lda #0
        sta t0
        sta t0+1
        jsr list_item_ptr
        lda p1
        sta p2
        lda p1+1
        sta p2+1                        ; p2 = first
        jsr self_list
        jsr seq_len
        lda t0
        ora t0+1
        beq _done
        sec
        lda t0
        sbc #1
        sta t0
        lda t0+1
        sbc #0
        sta t0+1
        jsr list_item_ptr               ; p1 = last
-       lda p2+1
        cmp p1+1
        bcc +
        bne _done
        lda p2
        cmp p1
        bcs _done
+       ldz #0
        lda [p2],z
        tax
        lda [p1],z
        sta [p2],z
        txa
        sta [p1],z
        inz
        lda [p2],z
        tax
        lda [p1],z
        sta [p2],z
        txa
        sta [p1],z
        inw p2
        inw p2
        dew p1
        dew p1
        bra -
_done:  #RET_NONE
