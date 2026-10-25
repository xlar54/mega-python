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
; str methods: in tail S (strmeth.asm)
;---------------------------------------------------------------------------------------
TAILS   .macro target
        jsr need_s
        jmp \target
        .endm
; list_from_iterable for tail S: the iteration may run Python code (a user __next__),
; which may bring in another tail
list_from_iter_s:
        jsr list_from_iterable
        jmp need_s
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


;---------------------------------------------------------------------------------------
; format specs: [[fill]align][sign][0][width][,][.precision][type]
;---------------------------------------------------------------------------------------
fs_fill:        .byte ' '
fs_align:       .byte 0
fs_sign:        .byte '-'
fs_width:       .word 0
fs_prec:        .word $ffff
fs_type:        .byte 0
fs_comma:       .byte 0

; format_spec - append format(r2, spec r3)
format_spec:
        lda #' '
        sta fs_fill
        lda #0
        sta fs_align
        sta fs_width
        sta fs_width+1
        sta fs_type
        sta fs_comma
        lda #'-'
        sta fs_sign
        lda #$ff
        sta fs_prec
        sta fs_prec+1
        lda r3
        ldx r3+1
        jsr str_info
        ; fill + align?
        ldz #1
        lda str_len+1
        bne +
        lda str_len
        cmp #2
        bcc _al1
+       lda [fp0],z
        jsr is_align
        bcc _al1
        sta fs_align
        dez
        lda [fp0],z
        sta fs_fill
        jsr _adv
        jsr _adv
        bra _sign
_al1:   jsr _peek
        bcs _end
        jsr is_align
        bcc _sign
        sta fs_align
        jsr _adv
_sign:  jsr _peek
        bcs _end
        cmp #'+'
        beq +
        cmp #' '
        beq +
        cmp #'-'
        bne _zero
+       sta fs_sign
        jsr _adv
_zero:  jsr _peek
        bcs _end
        cmp #'0'
        bne _width
        lda fs_align
        bne +
        lda #'='
        sta fs_align
        lda #'0'
        sta fs_fill
+       jsr _adv
_width: jsr _num
        lda acc
        sta fs_width
        lda acc+1
        sta fs_width+1
        jsr _peek
        bcs _end
        cmp #','
        bne +
        sta fs_comma
        jsr _adv
+       jsr _peek
        bcs _end
        cmp #'.'
        bne _type
        jsr _adv
        jsr _num
        lda acc
        sta fs_prec
        lda acc+1
        sta fs_prec+1
_type:  jsr _peek
        bcs _end
        sta fs_type
        jsr _adv
        lda str_len
        ora str_len+1
        beq _end
        #RAISE EXC_VALUE, "invalid format specifier"
_end:   jmp format_value
_peek:  lda str_len
        ora str_len+1
        bne +
        sec
        rts
+       ldz #0
        lda [fp0],z
        clc
        rts
_adv:   inw fp0
        dew str_len
        rts
_num:   lda #0
        sta acc
        sta acc+1
-       jsr _peek
        bcs +
        cmp #'0'
        bcc +
        cmp #'9'+1
        bcs +
        and #15
        pha
        ; acc = acc * 10 + d (16-bit)
        lda acc
        ldx acc+1
        asl acc
        rol acc+1
        asl acc
        rol acc+1
        clc
        adc acc
        sta acc
        txa
        adc acc+1
        sta acc+1
        asl acc
        rol acc+1
        pla
        clc
        adc acc
        sta acc
        bcc ++
        inc acc+1
+       rts
+       jsr _adv
        bra -

is_align:
        cmp #'<'
        beq +
        cmp #'>'
        beq +
        cmp #'^'
        beq +
        cmp #'='
        beq +
        clc
        rts
+       sec
        rts

; format_value - append r2 formatted by the fs_* fields
format_value:
        lda r2
        pha
        lda r2+1
        pha
        lda sbp
        pha
        lda sbp+1
        pha
        ; the body
        lda r2
        ldx r2+1
        jsr is_float
        bcs _float
        lda r2
        ldx r2+1
        jsr int_val
        bcs _notint
        lda fs_type
        cmp #'s'
        beq _notint
        jsr float_type_code
        bcs _float
        lda fs_align
        bne +
        lda #'>'
        sta fs_align
+       bit acc+3
        bpl _pos
        lda #'-'
        jsr sb_putc
        jsr acc_neg
        bra _digits
_pos:   lda fs_sign
        cmp #'-'
        beq _digits
        jsr sb_putc
_digits:
        lda fs_type
        cmp #'x'
        beq _hex
        cmp #'X'
        beq _hexu
        cmp #'o'
        beq _oct
        cmp #'b'
        beq _bin
        cmp #'c'
        beq _char
        lda fs_comma
        beq +
        jsr sb_int_commas
        bra _body
+       jsr sb_int
        bra _body
_hexu:  lda sbp
        pha
        lda sbp+1
        pha
        lda #16
        sta t6
        jsr sb_radix
        pla
        sta fp1+1
        pla
        sta fp1
        lda #`SBUF
        sta fp1+2
        lda #0
        sta fp1+3
-       lda fp1
        cmp sbp
        bne +
        lda fp1+1
        cmp sbp+1
        beq _body
+       ldz #0
        lda [fp1],z
        ldy #0
        sty t6
        jsr case_char
        sta [fp1],z
        inw fp1
        bra -
_hex:   lda #16
        bra _rad
_oct:   lda #8
        bra _rad
_bin:   lda #2
_rad:   sta t6
        jsr sb_radix
        bra _body
_char:  lda acc
        jsr sb_putc
        bra _body
_float: lda fs_align
        bne +
        lda #'>'
        sta fs_align
+       jsr format_float
        bra _body
_notint:
        lda fs_align
        bne +
        lda #'<'
        sta fs_align
+       lda r2
        ldx r2+1
        jsr obj_str
        ; precision truncates strings
        lda fs_prec+1
        cmp #$ff
        beq _body
        ; the mark is on top of the CPU stack: peek it
        pla
        sta t1+1
        pla
        sta t1
        pha
        lda t1+1
        pha
        clc
        lda t1
        adc fs_prec
        sta t2
        lda t1+1
        adc fs_prec+1
        sta t2+1
        lda t2+1
        cmp sbp+1
        bcc +
        bne _body
        lda t2
        cmp sbp
        bcs _body
+       lda t2
        sta sbp
        lda t2+1
        sta sbp+1
_body:  ; turn the body into a string, then pad it
        plx
        pla
        jsr sb_take
        sta r2
        stx r2+1
        jsr pad_body
        pla
        sta r2+1
        pla
        sta r2
        rts

; pad_body - append string A/X padded to fs_width with fs_fill / fs_align
pad_body:
        sta r2
        stx r2+1
        jsr str_info
        sec
        lda fs_width
        sbc str_len
        sta t3
        lda fs_width+1
        sbc str_len+1
        sta t3+1
        bcs +
        lda #0
        sta t3
        sta t3+1
+       lda fs_align
        cmp #'>'
        beq _right
        cmp #'^'
        beq _center
        cmp #'='
        beq _sign
        ; left
        lda r2
        ldx r2+1
        jsr sb_put_str
        jmp _fill3
_right: jsr _fill3
        lda r2
        ldx r2+1
        jmp sb_put_str
_center:
        lda t3
        pha
        lda t3+1
        pha
        lsr t3+1
        ror t3
        jsr _fill3
        lda r2
        ldx r2+1
        jsr sb_put_str
        pla
        sta t3+1
        pla
        sta t3
        ; the right half is the larger one
        lda t3
        pha
        lsr t3+1
        ror t3
        pla
        and #1
        beq +
        inw t3
+       jmp _fill3
_sign:  ; sign, then the fill, then the rest
        lda r2
        ldx r2+1
        jsr str_info
        lda str_len
        ora str_len+1
        beq _right
        ldz #0
        lda [fp0],z
        cmp #'-'
        beq +
        cmp #'+'
        beq +
        cmp #' '
        bne _right
+       jsr sb_putc
        jsr _fill3
        lda r2
        ldx r2+1
        jsr str_info
        inw fp0
        dew str_len
-       lda str_len
        ora str_len+1
        beq +
        ldz #0
        lda [fp0],z
        jsr sb_putc
        inw fp0
        dew str_len
        bra -
+       rts
_fill3: lda t3
        ora t3+1
        beq +
        lda fs_fill
        jsr sb_putc
        dew t3
        bra _fill3
+       rts

; sb_int_commas - acc (non-negative) with thousands separators
sb_int_commas:
        lda sbp
        pha
        lda sbp+1
        pha
        jsr sb_int
        pla
        sta t1+1
        pla
        sta t1
        ; digits t1..sbp: take them as a string, then re-emit with commas
        lda t1
        ldx t1+1
        jsr sb_take
        sta r3
        stx r3+1
        jsr str_info
        lda str_len
        sta t2                          ; digits left
_digit: lda t2
        beq _done
        ldz #0
        lda [fp0],z
        jsr sb_putc
        inw fp0
        dec t2
        beq _done
        lda t2                          ; a comma when the digits left are a multiple of 3
_mod3:  cmp #3
        bcc _rem
        sbc #3
        bra _mod3
_rem:   cmp #0
        bne _digit
        lda #','
        jsr sb_putc
        bra _digit
_done:  lda #0
        sta r3
        sta r3+1
        rts

; "%" formatting: fmt % args
str_percent:
        ; args: a tuple, or a single value
        lda r3
        ldx r3+1
        jsr type_of
        cmp #T_TUPLE
        beq +
        lda #1
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        ldz #6
        lda r3
        sta [p0],z
        inz
        lda r3+1
        sta [p0],z
        lda p0
        sta r3
        lda p0+1
        sta r3+1
+       lda r3
        ldx r3+1
        #PUSH                           ; [args]
        lda r2
        ldx r2+1
        #PUSH                           ; [args][fmt]
        lda sbp
        pha
        lda sbp+1
        pha
        lda #0
        sta pc_arg
        sta pc_pos
        sta pc_pos+1
_loop:  jsr pc_get
        bcs _done
        cmp #'%'
        beq _conv
        jsr sb_putc
        inw pc_pos
        bra _loop
_conv:  inw pc_pos
        jsr pc_get
        bcs _bad
        cmp #'%'
        bne +
        jsr sb_putc
        inw pc_pos
        bra _loop
+       ; flags, width, precision
        lda #'>'
        sta fs_align
        lda #' '
        sta fs_fill
        lda #'-'
        sta fs_sign
        lda #$ff
        sta fs_prec
        sta fs_prec+1
        lda #0
        sta fs_width
        sta fs_width+1
_flags: jsr pc_get
        bcs _bad
        cmp #'-'
        bne +
        lda #'<'
        sta fs_align
        inw pc_pos
        bra _flags
+       cmp #'+'
        beq _sgn
        cmp #' '
        bne +
_sgn:   sta fs_sign
        inw pc_pos
        bra _flags
+       cmp #'0'
        bne _wid
        lda #'='
        sta fs_align
        lda #'0'
        sta fs_fill
        inw pc_pos
        bra _flags
_wid:   jsr pc_get
        bcs _bad
        cmp #'.'
        bne +
        lda #0
        sta fs_prec
        sta fs_prec+1
        inw pc_pos
-       jsr pc_get                      ; the precision (up to 255)
        bcs _bad
        cmp #'0'
        bcc _type
        cmp #'9'+1
        bcs _type
        and #15
        pha
        lda fs_prec
        asl
        asl
        clc
        adc fs_prec
        asl
        sta fs_prec
        pla
        clc
        adc fs_prec
        sta fs_prec
        inw pc_pos
        bra -
+       cmp #'0'
        bcc _type
        cmp #'9'+1
        bcs _type
        and #15
        pha
        lda fs_width
        asl
        asl
        clc
        adc fs_width
        asl
        sta fs_width
        pla
        clc
        adc fs_width
        sta fs_width
        inw pc_pos
        bra _wid
_type:  inw pc_pos
        sta fs_type
        ; the next argument
        lda pc_arg
        sta t2
        lda #0
        sta t2+1
        #PEEK 1
        jsr seq_len
        lda t2
        cmp t0
        bcs _few
        #PEEK 1
        jsr seq_get_t2
        sta r2
        stx r2+1
        inc pc_arg
        lda fs_type
        cmp #'r'
        beq _repr
        cmp #'s'
        beq _str
        cmp #'d'
        beq _int
        cmp #'i'
        beq _int
        cmp #'x'
        beq _int
        cmp #'X'
        beq _int
        cmp #'o'
        beq _int
        cmp #'c'
        beq _int
        jsr float_type_code
        bcs _flt
_bad:   #RAISE EXC_VALUE, "unsupported format character"
_few:   #RAISE EXC_TYPE, "not enough arguments for format string"
_flt:   lda r2                          ; a number, as a float
        ldx r2+1
        jsr num_to_fa
        bcs _need
        jsr float_new
        sta r2
        stx r2+1
        bra _fmt
_need:  #RAISE EXC_TYPE, "must be real number"
_int:   cmp #'i'
        bne +
        lda #'d'
        sta fs_type
+       lda r2                          ; %d of a float: its int
        ldx r2+1
        jsr is_float
        bcc +
        lda r2
        ldx r2+1
        jsr float_load
        jsr f_unpack
        jsr f_trunc
        jsr f_int_result
        sta r2
        stx r2+1
+       lda #$ff
        sta fs_prec
        sta fs_prec+1
_fmt:   jsr pc_save
        lda #0
        sta fs_comma
        jsr format_value
        jsr pc_restore
        jmp _loop
_str:   jsr pc_save
        lda sbp
        pha
        lda sbp+1
        pha
        lda r2
        ldx r2+1
        jsr obj_str
        bra _pad
_repr:  jsr pc_save
        lda sbp
        pha
        lda sbp+1
        pha
        lda r2
        ldx r2+1
        jsr obj_repr
_pad:   plx
        pla
        jsr sb_take
        jsr pad_body
        jsr pc_restore
        jmp _loop
_done:  plx
        pla
        jsr sb_take
        sta t0
        stx t0+1
        #DROP 2
        lda t0
        ldx t0+1
        rts
pc_save:                                ; keep pc_* across nested str() calls
        pla
        sta t7
        pla
        sta t7+1
        lda pc_arg
        pha
        lda pc_pos
        pha
        lda pc_pos+1
        pha
        lda fs_align
        pha
        lda fs_fill
        pha
        lda fs_width
        pha
        lda t7+1
        pha
        lda t7
        pha
        rts
pc_restore:
        pla
        sta t7
        pla
        sta t7+1
        pla
        sta fs_width
        pla
        sta fs_fill
        pla
        sta fs_align
        pla
        sta pc_pos+1
        pla
        sta pc_pos
        pla
        sta pc_arg
        lda t7+1
        pha
        lda t7
        pha
        rts
; position fp0 at pc_pos of the format; C set at the end
pc_seek:
        sec
        lda pc_pos
        cmp str_len
        lda pc_pos+1
        sbc str_len+1
        bcs +
        clc
        lda fp0
        adc pc_pos
        sta fp0
        lda fp0+1
        adc pc_pos+1
        sta fp0+1
        clc
+       rts
pc_get: #PEEK 0
        jsr str_info
        jsr pc_seek
        bcs +
        ldz #0
        lda [fp0],z
        clc
+       rts
pc_arg:         .byte 0

; str.format(*args, **kwargs): {} {0} {name} with optional :spec
bi_str_format:
        sec
        lda argc
        sbc nkw
        sta npos
        ; keep the arguments as a tuple and a dict on the stack: [fmt][args][kw]
        #ARG 0
        #PUSH
        sec
        lda npos
        sbc #1
        sta nitems
        lda #0
        sta nitems+1
        jsr tuple_new
        ldx #2
        ldz #6
-       txa
        lsr
        cmp npos
        bcs +
        lda argv,x
        sta [p0],z
        inz
        lda argv+1,x
        sta [p0],z
        inz
        inx
        inx
        bra -
+       lda p0
        ldx p0+1
        #PUSH
        jsr dict_new
        #PUSH
        ldx #0
-       cpx nkw
        bcs +
        phx
        lda kwnames
        sta p1
        lda kwnames+1
        sta p1+1
        txa
        asl
        clc
        adc #6
        taz
        lda [p1],z
        sta r1
        inz
        lda [p1],z
        sta r1+1
        txa
        clc
        adc npos
        asl
        tay
        lda argv,y
        sta r2
        lda argv+1,y
        sta r2+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_set
        plx
        inx
        bra -
+       lda sbp
        pha
        lda sbp+1
        pha
        lda #0
        sta pc_pos
        sta pc_pos+1
        sta pc_arg
_loop:  jsr _ch
        bcs _done
        cmp #'{'
        beq _open
        cmp #'}'
        beq _close
_lit:   jsr sb_putc
        inw pc_pos
        bra _loop
_close: inw pc_pos                      ; }} -> }
        jsr _ch
        bcs _done
        cmp #'}'
        bne _loop
        bra _lit
_open:  inw pc_pos
        jsr _ch
        bcs _done
        cmp #'{'
        beq _lit
        ; field name up to : or }
        lda pc_pos
        sta t5
        lda pc_pos+1
        sta t5+1
-       jsr _ch
        bcs _bad
        cmp #':'
        beq +
        cmp #'}'
        beq +
        inw pc_pos
        bra -
+       ; t5..pc_pos = the field name
        jsr _field                      ; -> r2 = value
        lda #0
        sta r3+1
        jsr _ch
        cmp #':'
        bne _nospec
        inw pc_pos
        lda pc_pos
        sta t5
        lda pc_pos+1
        sta t5+1
-       jsr _ch
        bcs _bad
        cmp #'}'
        beq +
        inw pc_pos
        bra -
+       jsr _substr                     ; r3 = the spec
        sta r3
        stx r3+1
_nospec:
        inw pc_pos                      ; past }
        jsr pc_save
        lda r3+1
        bne +
        lda r2
        ldx r2+1
        jsr obj_str
        bra ++
+       jsr format_spec
+       jsr pc_restore
        jmp _loop
_bad:   #RAISE EXC_VALUE, "bad format string"
_done:  plx
        pla
        jsr sb_take
        sta t0
        stx t0+1
        #DROP 3
        lda t0
        ldx t0+1
        rts
_ch:    #PEEK 2                         ; the format string: A = char at pc_pos, C at end
        jsr str_info
        jsr pc_seek
        bcs +
        ldz #0
        lda [fp0],z
        clc
+       rts
; the value of field t5..pc_pos -> r2
_field: lda pc_pos
        cmp t5
        bne _named
        lda pc_pos+1
        cmp t5+1
        bne _named
        ; {} : the next positional
        lda pc_arg
        inc pc_arg
        bra _pos
_named: jsr _substr
        sta r2
        stx r2+1
        lda #10
        sta t6
        lda r2
        ldx r2+1
        jsr parse_int
        bcs _kw
        lda acc
_pos:   sta t2
        lda #0
        sta t2+1
        #PEEK 1
        jsr seq_len
        lda t2
        cmp t0
        bcc +
        #RAISE EXC_INDEX, "format index out of range"
+       #PEEK 1
        jsr seq_get_t2
        sta r2
        stx r2+1
        rts
_kw:    ; look the (interned) name up in the kwargs dict
        lda r2
        ldx r2+1
        jsr str_info
        ldx #3
-       lda fp0,x
        sta fp2,x
        dex
        bpl -
        jsr intern
        lda int_ref
        sta r1
        lda int_ref+1
        sta r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr dict_get
        bcc +
        jmp raise_key
+       sta r2
        stx r2+1
        rts
; the format string's chars t5..pc_pos as a new string -> A/X
_substr:
        #PEEK 2
        jsr str_info
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
        lda pc_pos
        sbc t5
        sta str_len
        lda pc_pos+1
        sbc t5+1
        sta str_len+1
        lda r2
        pha
        lda r2+1
        pha
        jsr str_from_far
        sta t0
        stx t0+1
        pla
        sta r2+1
        pla
        sta r2
        lda t0
        ldx t0+1
        rts


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

bi_list_insert:
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

bi_list_reverse:
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
; sorting: a stable merge sort of an index permutation (attic scratch), comparing
; keys with obj_cmp. key= and reverse= are supported.
;---------------------------------------------------------------------------------------
SORT_A          = $8140000              ; index arrays (2 bytes per item)
SORT_B          = $8150000
SORT_SAVE       = $8160000              ; the items, in their old order

bi_sorted:
        sec
        lda argc
        sbc nkw
        cmp #1
        beq +
        jmp raise_args
+       #ARG 0
        jsr list_from_iterable
        sta argv
        stx argv+1
        lda #1                          ; sorted() returns the list
        sta bi_sort_ret
        bra sort_common
bi_list_sort:
        sec
        lda argc
        sbc nkw
        cmp #1
        beq +
        jmp raise_args
+       lda #0                          ; list.sort() returns None
        sta bi_sort_ret
sort_common:
        lda #R_NONE                     ; key, reverse from the keywords
        sta srt_key
        lda #0
        sta srt_key+1
        sta srt_rev
        lda #1
        sta npos
        lda #<S_KEY
        ldx #>S_KEY
        jsr kw_get
        bcs +
        sta srt_key
        stx srt_key+1
+       lda #<S_REVERSE
        ldx #>S_REVERSE
        jsr kw_get
        bcs +
        jsr obj_truth
        sta srt_rev
+       #ARG 0
        #PUSH                           ; [list]
        jsr seq_len
        lda t0
        sta srt_n
        lda t0+1
        sta srt_n+1
        ; keys: the items themselves, or key(item) for each
        lda srt_key+1
        bne _keys
        #PEEK 0
        #PUSH                           ; [list][keys = list]
        bra _sort
_keys:  lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [list][keys]
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp srt_n
        bne +
        lda t2+1
        cmp srt_n+1
        beq _sort
+       lda t2
        pha
        lda t2+1
        pha
        lda srt_key
        ldx srt_key+1
        #PUSH
        #PEEK 2
        jsr seq_get_t2
        #PUSH
        lda #1
        sta argc
        jsr vm_call_nested
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        jsr clear_rregs
        pla
        sta t2+1
        pla
        sta t2
        inw t2
        bra -
_sort:  lda srt_rev
        pha
        jsr merge_sort                  ; SORT_A = the sorted permutation
        pla
        ; reorder the list: save the items, then items[i] = saved[perm[i]]
        #PEEK 1
        sta p0
        stx p0+1
        lda #0
        sta t0
        sta t0+1
        jsr list_item_ptr
        lda srt_n
        ora srt_n+1
        beq _done
        lda p1
        sta fp0
        lda p1+1
        sta fp0+1
        lda #HEAP_BANK
        sta fp0+2
        lda #0
        sta fp0+3
        lda #<SORT_SAVE
        sta fp1
        lda #>SORT_SAVE
        sta fp1+1
        lda #<(SORT_SAVE >> 16)
        sta fp1+2
        lda #>(SORT_SAVE >> 16)
        sta fp1+3
        lda srt_n
        asl
        sta t0
        lda srt_n+1
        rol
        sta t0+1
        lda p1
        pha
        lda p1+1
        pha
        jsr dma_copy
        pla
        sta p1+1
        pla
        sta p1
        jsr set_fp_a
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp srt_n
        bne +
        lda t2+1
        cmp srt_n+1
        beq _done
+       ldz #0                          ; perm[i]
        lda [fp0],z
        asl
        sta fp2
        inz
        lda [fp0],z
        rol
        clc
        adc #>(SORT_SAVE & $ffff)
        sta fp2+1
        lda #<(SORT_SAVE >> 16)
        sta fp2+2
        lda #>(SORT_SAVE >> 16)
        sta fp2+3
        ldz #0
        lda [fp2],z
        sta [p1],z
        inz
        lda [fp2],z
        sta [p1],z
        inw p1
        inw p1
        inw fp0
        inw fp0
        inw t2
        bra -
_done:  #DROP 1
        #POP
        ldy bi_sort_ret                 ; sorted() returns the list, sort() None
        bne +
        #RET_NONE
+       rts
srt_key:        .word 0
srt_rev:        .byte 0
srt_n:          .word 0
bi_sort_ret:    .byte 0

set_fp_a:
        lda #<SORT_A
        sta fp0
        lda #>SORT_A
        sta fp0+1
        lda #<(SORT_A >> 16)
        sta fp0+2
        lda #>(SORT_A >> 16)
        sta fp0+3
        rts

; merge_sort - keys on the stack top ([..][keys]), srt_n items, A = reverse.
; Leaves the permutation in SORT_A.
ms_rev:         .byte 0
ms_width:       .word 0
ms_lo:          .word 0
ms_mid:         .word 0
ms_hi:          .word 0
ms_src:         .byte 0                 ; 0: A is the source
merge_sort:
        sta ms_rev
        ; A[i] = i
        jsr set_fp_a
        lda #0
        sta t2
        sta t2+1
-       lda t2
        cmp srt_n
        bne +
        lda t2+1
        cmp srt_n+1
        beq ++
+       ldz #0
        lda t2
        sta [fp0],z
        inz
        lda t2+1
        sta [fp0],z
        inw fp0
        inw fp0
        inw t2
        bra -
+       lda #0
        sta ms_src
        lda #1
        sta ms_width
        lda #0
        sta ms_width+1
_pass:  ; while width < n
        lda ms_width+1
        cmp srt_n+1
        bcc +
        bne _end
        lda ms_width
        cmp srt_n
        bcs _end
+       lda #0
        sta ms_lo
        sta ms_lo+1
_run:   lda ms_lo+1
        cmp srt_n+1
        bcc +
        bne _next
        lda ms_lo
        cmp srt_n
        bcs _next
+       ; mid = min(lo + width, n), hi = min(lo + 2*width, n)
        clc
        lda ms_lo
        adc ms_width
        sta ms_mid
        lda ms_lo+1
        adc ms_width+1
        sta ms_mid+1
        jsr _clamp_mid
        clc
        lda ms_mid
        adc ms_width
        sta ms_hi
        lda ms_mid+1
        adc ms_width+1
        sta ms_hi+1
        jsr _clamp_hi
        jsr ms_merge
        lda ms_hi
        sta ms_lo
        lda ms_hi+1
        sta ms_lo+1
        bra _run
_next:  lda ms_src
        eor #1
        sta ms_src
        asw ms_width
        bra _pass
_end:   lda ms_src
        beq +
        ; the result is in B: copy it to A
        lda srt_n
        asl
        sta t0
        lda srt_n+1
        rol
        sta t0+1
        lda t0
        ora t0+1
        beq +
        lda #<SORT_B
        sta fp0
        lda #>SORT_B
        sta fp0+1
        lda #<(SORT_B >> 16)
        sta fp0+2
        lda #>(SORT_B >> 16)
        sta fp0+3
        lda #<SORT_A
        sta fp1
        lda #>SORT_A
        sta fp1+1
        lda #<(SORT_A >> 16)
        sta fp1+2
        lda #>(SORT_A >> 16)
        sta fp1+3
        jsr dma_copy
+       rts
_clamp_mid:
        lda ms_mid+1
        cmp srt_n+1
        bcc +
        bne _cm
        lda ms_mid
        cmp srt_n
        bcc +
_cm:    lda srt_n
        sta ms_mid
        lda srt_n+1
        sta ms_mid+1
+       rts
_clamp_hi:
        lda ms_hi+1
        cmp srt_n+1
        bcc +
        bne _ch
        lda ms_hi
        cmp srt_n
        bcc +
_ch:    lda srt_n
        sta ms_hi
        lda srt_n+1
        sta ms_hi+1
+       rts

; merge src[lo:mid] and src[mid:hi] into dst[lo:hi]
ms_merge:
        lda ms_lo
        sta ms_i
        sta ms_k
        lda ms_lo+1
        sta ms_i+1
        sta ms_k+1
        lda ms_mid
        sta ms_j
        lda ms_mid+1
        sta ms_j+1
_loop:  lda ms_k
        cmp ms_hi
        bne +
        lda ms_k+1
        cmp ms_hi+1
        beq _done
+       ; take from the left run unless it is empty, or right < left
        lda ms_i
        cmp ms_mid
        bne +
        lda ms_i+1
        cmp ms_mid+1
        beq _right
+       lda ms_j
        cmp ms_hi
        bne +
        lda ms_j+1
        cmp ms_hi+1
        beq _left
+       ; compare key[src[j]] with key[src[i]]: right first only if strictly less
        lda ms_j
        ldx ms_j+1
        jsr ms_get
        sta t6
        stx t6+1
        lda ms_i
        ldx ms_i+1
        jsr ms_get
        sta t7
        stx t7+1
        #PEEK 0                         ; keys
        sta p0
        stx p0+1
        lda t6
        sta t0
        lda t6+1
        sta t0+1
        jsr seq_get
        sta r2
        stx r2+1
        #PEEK 0
        sta p0
        stx p0+1
        lda t7
        sta t0
        lda t7+1
        sta t0+1
        jsr seq_get
        sta r3
        stx r3+1
        jsr obj_cmp                     ; right vs left
        ldx ms_rev
        beq +
        eor #$fe                        ; $ff <-> 1, 0 stays
        cmp #$fe
        bne +
        lda #0
+       cmp #$ff
        beq _right
_left:  lda ms_i
        ldx ms_i+1
        jsr ms_get
        jsr ms_put
        inw ms_i
        bra _loop
_right: lda ms_j
        ldx ms_j+1
        jsr ms_get
        jsr ms_put
        inw ms_j
        bra _loop
_done:  rts

; A/X = index -> fp2 at it in the source array
ms_ptr: asl
        sta fp2
        txa
        rol
        sta fp2+1
        lda #0
        sta fp2+3
        lda ms_src
        beq +
        clc
        lda fp2+1
        adc #>(SORT_B & $ffff)
        sta fp2+1
        lda #<(SORT_B >> 16)
        sta fp2+2
        lda #>(SORT_B >> 16)
        sta fp2+3
        rts
+       clc
        lda fp2+1
        adc #>(SORT_A & $ffff)
        sta fp2+1
        lda #<(SORT_A >> 16)
        sta fp2+2
        lda #>(SORT_A >> 16)
        sta fp2+3
        rts
; A/X = src[index]
ms_get: jsr ms_ptr
        ldz #1
        lda [fp2],z
        tax
        dez
        lda [fp2],z
        rts
; dst[ms_k] = A/X; ms_k += 1
ms_put: pha
        phx
        lda ms_src
        eor #1
        sta ms_src
        lda ms_k
        ldx ms_k+1
        jsr ms_ptr
        lda ms_src
        eor #1
        sta ms_src
        ldz #1
        pla
        sta [fp2],z
        dez
        pla
        sta [fp2],z
        inw ms_k
        rts

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
