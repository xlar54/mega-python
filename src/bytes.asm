;=======================================================================================
; bytes, tail M (with the classes): a bytes object is a T_STR with F_BYTES in its header
; flags, so the string code does most of the work (len, slices, +, *, in, find, split,
; join, ...). The places that differ test the flag: indexing and iteration give ints
; (char_or_byte), repr is b'...', a bytes never equals a str, type() is bytes, and a str
; method called on bytes gives bytes back (call_native -> xy_wrap). bytes(), str.encode,
; bytes.decode and bytes.hex are here.
;=======================================================================================
yb_flag:        .byte 0
yb_mark:        .word 0
yb_kind:        .byte 0
yb_i:           .word 0

; yb_copy - A/X = a string -> A/X = a new one with its chars, F_BYTES as yb_flag
yb_copy:
        ldy sbp
        sty yb_mark
        ldy sbp+1
        sty yb_mark+1
        jsr sb_put_str
        lda yb_mark
        ldx yb_mark+1
        jsr sb_take
yb_setflag:                             ; A/X = a new string: F_BYTES as yb_flag
        sta p1
        stx p1+1
        pha
        ldz #1
        lda [p1],z
        and #$ff - F_BYTES
        ora yb_flag
        sta [p1],z
        pla
        rts

;---------------------------------------------------------------------------------------
; xy_wrap - A/X = what a str method gave for bytes: strings (also in a list or tuple)
; become bytes
;---------------------------------------------------------------------------------------
xy_wrap:
        sta r1
        stx r1+1
        jsr type_of
        cmp #T_STR
        beq _str
        cmp #T_LIST
        beq _seq
        cmp #T_TUPLE
        beq _seq
        lda r1
        ldx r1+1
        rts
_str:   lda #F_BYTES
        sta yb_flag
        lda r1
        ldx r1+1
        jmp yb_copy
_seq:   sta yb_kind
        lda r1
        ldx r1+1
        #PUSH                           ; [items]
        lda #0
        sta nitems
        sta nitems+1
        sta yb_i
        sta yb_i+1
        jsr list_new
        #PUSH                           ; [items][new]
_loop:  #PEEK 1
        jsr seq_len
        lda yb_i
        cmp t0
        lda yb_i+1
        sbc t0+1
        bcs _end
        lda yb_i
        sta t2
        lda yb_i+1
        sta t2+1
        #PEEK 1
        jsr seq_get_t2
        sta r1
        stx r1+1
        jsr type_of
        cmp #T_STR
        bne +
        lda #F_BYTES
        sta yb_flag
        lda r1
        ldx r1+1
        jsr yb_copy
        sta r1
        stx r1+1
+       #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        inc yb_i
        bne _loop
        inc yb_i+1
        bra _loop
_end:   lda yb_kind
        cmp #T_TUPLE
        bne +
        #PEEK 0
        jsr tuple_from_list
        bra ++
+       #PEEK 0
+       #DROP 2
        rts

;---------------------------------------------------------------------------------------
; xy_repr - A/X = bytes: b'...' onto the string builder (\\, the quote, \t \n \r, and
; \xhh for the bytes below 32 or above 126)
;---------------------------------------------------------------------------------------
xy_repr:
        jsr str_info
        lda #0                          ; ' unless there is a ' and no "
        sta yb_kind
        sta yb_flag
        lda fp0
        sta fp1
        lda fp0+1
        sta fp1+1
        lda fp0+2
        sta fp1+2
        lda #0
        sta fp1+3
        lda str_len
        sta yb_i
        lda str_len+1
        sta yb_i+1
_scan:  lda yb_i
        ora yb_i+1
        beq _quote
        ldz #0
        lda [fp1],z
        cmp #"'"
        bne +
        sta yb_kind
+       cmp #'"'
        bne +
        sta yb_flag
+       inw fp1
        lda yb_i
        bne +
        dec yb_i+1
+       dec yb_i
        bra _scan
_quote: lda yb_kind
        beq +
        lda yb_flag
        bne +
        lda #'"'
        bra ++
+       lda #"'"
+       sta yb_kind
+       lda #'b'
        jsr sb_putc
        lda yb_kind
        jsr sb_putc
        lda str_len
        sta yb_i
        lda str_len+1
        sta yb_i+1
_char:  lda yb_i
        ora yb_i+1
        beq _done
        ldz #0
        lda [fp0],z
        cmp yb_kind
        beq _bs
        cmp #'\'
        beq _bs
        ldx #'t'
        cmp #9
        beq _esc
        ldx #'n'
        cmp #10
        beq _esc
        ldx #'r'
        cmp #13
        beq _esc
        cmp #32
        bcc _hex
        cmp #127
        bcs _hex
        jsr sb_putc
        bra _next
_bs:    pha
        lda #'\'
        jsr sb_putc
        pla
        jsr sb_putc
        bra _next
_esc:   lda #'\'
        jsr sb_putc
        txa
        jsr sb_putc
        bra _next
_hex:   pha
        lda #'\'
        jsr sb_putc
        lda #'x'
        jsr sb_putc
        pla
        jsr yb_hex2
_next:  inw fp0
        lda yb_i
        bne +
        dec yb_i+1
+       dec yb_i
        bra _char
_done:  lda yb_kind
        jmp sb_putc

; yb_hex2 - A: two lower-case hex digits onto the string builder
yb_hex2:
        pha
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        lda hex_digits,x
        jsr sb_putc
        pla
        and #15
        tax
        lda hex_digits,x
        jmp sb_putc

;---------------------------------------------------------------------------------------
; bytes() / bytes(n) / bytes(iterable of ints) / bytes(str, encoding) / bytes(bytes)
;---------------------------------------------------------------------------------------
xy_bytes:
        #NARGS 0, 3
        lda #F_BYTES
        sta yb_flag
        lda npos
        bne +
        lda #0                          ; b''
        sta str_len
        sta str_len+1
        jsr str_alloc
        jmp yb_setflag
+       #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        bne _notstr
        lda r2
        ldx r2+1
        jsr is_bytes
        bcc +
        lda r2                          ; bytes(b): b
        ldx r2+1
        rts
+       lda npos
        cmp #2
        bcs _enc
        #RAISE EXC_TYPE, "string argument without an encoding"
_enc:   lda r2
        ldx r2+1
        jmp yb_copy
_notstr:
        jsr is_inttype
        bcc _iter
        lda r2                          ; bytes(n): n zero bytes
        ldx r2+1
        jsr need_int
        bit acc+3
        bpl +
        #RAISE EXC_VALUE, "negative count"
+       lda acc
        sta str_len
        lda acc+1
        sta str_len+1
        lda acc+2
        ora acc+3
        beq +
        jmp raise_memory
+       jsr str_alloc                   ; (a new body is all zeros)
        jmp yb_setflag
_iter:  lda r2                          ; bytes(iterable): each an int 0-255
        ldx r2+1
        jsr list_from_iterable
        #PUSH
        lda sbp
        sta yb_mark
        lda sbp+1
        sta yb_mark+1
        lda #0
        sta yb_i
        sta yb_i+1
_item:  #PEEK 0
        jsr seq_len
        lda yb_i
        cmp t0
        lda yb_i+1
        sbc t0+1
        bcs _made
        lda yb_i
        sta t2
        lda yb_i+1
        sta t2+1
        #PEEK 0
        jsr seq_get_t2
        jsr need_int
        lda acc+1
        ora acc+2
        ora acc+3
        beq +
        #RAISE EXC_VALUE, "bytes must be in range(0, 256)"
+       lda acc
        jsr sb_putc
        inc yb_i
        bne _item
        inc yb_i+1
        bra _item
_made:  #DROP 1
        lda yb_mark
        ldx yb_mark+1
        jsr sb_take
        jmp yb_setflag

; str.encode(encoding='utf-8', errors='strict') -> bytes (the same chars)
xy_encode:
        #NARGS 1, 3
        lda #F_BYTES
        bra yb_conv
; bytes.decode(encoding='utf-8', errors='strict') -> str
xy_decode:
        #NARGS 1, 3
        lda #0
yb_conv:
        sta yb_flag
        #ARG 0
        jmp yb_copy

; bytes.hex() -> str of two hex digits a byte
xy_hex: #NARGS 1, 1
        #ARG 0
        jsr str_info
        lda sbp
        sta yb_mark
        lda sbp+1
        sta yb_mark+1
        lda str_len
        sta yb_i
        lda str_len+1
        sta yb_i+1
-       lda yb_i
        ora yb_i+1
        beq +
        ldz #0
        lda [fp0],z
        jsr yb_hex2
        inw fp0
        lda yb_i
        bne _lo
        dec yb_i+1
_lo:    dec yb_i
        bra -
+       lda yb_mark
        ldx yb_mark+1
        jmp sb_take
