;=======================================================================================
; Lexer. Reads ASCII source through the far pointer lx_ptr (zero-terminated) and
; leaves one token in tok / tok_sym / tok_ref / tok_num.
;=======================================================================================
TK_EOF          = 0
TK_NEWLINE      = 1
TK_INDENT       = 2
TK_DEDENT       = 3
TK_NAME         = 4                     ; tok_sym = symbol, tok_ref = name string
TK_INT          = 5                     ; tok_num
TK_STR          = 6                     ; tok_ref
TK_FSTR         = 7                     ; tok_num = far pointer to raw text, tok_sym = length
TK_FLOAT        = 8                     ; tok_ref
TK_LPAREN       = 16
TK_RPAREN       = 17
TK_LBRACK       = 18
TK_RBRACK       = 19
TK_LBRACE       = 20
TK_RBRACE       = 21
TK_COMMA        = 22
TK_COLON        = 23
TK_SEMI         = 24
TK_DOT          = 25
TK_ASSIGN       = 26
TK_ARROW        = 27
TK_AT           = 28
TK_WALRUS       = 29
TK_BANG         = 30
TK_PLUS         = 32                    ; binary operators 32-43 (order = opcode order)
TK_MINUS        = 33
TK_STAR         = 34
TK_SLASH        = 35
TK_DSLASH       = 36
TK_PERCENT      = 37
TK_POW          = 38
TK_LSHIFT       = 39
TK_RSHIFT       = 40
TK_AMP          = 41
TK_PIPE         = 42
TK_CARET        = 43
TK_TILDE        = 44
TK_EQ           = 48
TK_NE           = 49
TK_LT           = 50
TK_GT           = 51
TK_LE           = 52
TK_GE           = 53
TK_AUG          = 64                    ; += is TK_AUG + (TK_PLUS - 32), ...
TK_KW           = 96                    ; keyword with symbol id n is TK_KW + n

; keyword symbols (interned first, in this order: see sym_init)
KW_FALSE        = TK_KW + 0
KW_NONE         = TK_KW + 1
KW_TRUE         = TK_KW + 2
KW_AND          = TK_KW + 3
KW_AS           = TK_KW + 4
KW_ASSERT       = TK_KW + 5
KW_BREAK        = TK_KW + 6
KW_CLASS        = TK_KW + 7
KW_CONTINUE     = TK_KW + 8
KW_DEF          = TK_KW + 9
KW_DEL          = TK_KW + 10
KW_ELIF         = TK_KW + 11
KW_ELSE         = TK_KW + 12
KW_EXCEPT       = TK_KW + 13
KW_FINALLY      = TK_KW + 14
KW_FOR          = TK_KW + 15
KW_FROM         = TK_KW + 16
KW_GLOBAL       = TK_KW + 17
KW_IF           = TK_KW + 18
KW_IMPORT       = TK_KW + 19
KW_IN           = TK_KW + 20
KW_IS           = TK_KW + 21
KW_LAMBDA       = TK_KW + 22
KW_NONLOCAL     = TK_KW + 23
KW_NOT          = TK_KW + 24
KW_OR           = TK_KW + 25
KW_PASS         = TK_KW + 26
KW_RAISE        = TK_KW + 27
KW_RETURN       = TK_KW + 28
KW_TRY          = TK_KW + 29
KW_WHILE        = TK_KW + 30
KW_WITH         = TK_KW + 31
KW_YIELD        = TK_KW + 32
NKEYWORDS       = 33

lx_istack:      .fill 32, 0
lx_quote:       .byte 0
lx_raw:         .byte 0
lx_fstr:        .byte 0
lx_bytes:       .byte 0                 ; a b'...' literal
lx_triple:      .byte 0

; lx_init - start lexing at the far pointer lx_ptr
lx_init:
        lda #1
        sta lx_line
        sta lx_bol
        lda #0
        sta lx_line+1
        sta lx_paren
        sta lx_isp
        sta lx_pend
        sta lx_istack
        lda #TK_NEWLINE
        sta lx_last
        rts

; save / restore the whole lexer state (a stack of 4 slots, for look-ahead)
LXSAVE_N = 8
lx_saves:       .fill LXSAVE_N * LX_STATE_SIZE, 0
lx_savesp:      .byte 0
lx_push:
        ldy lx_savesp
        ldx #0
-       lda lx_ptr,x
        sta lx_saves,y
        iny
        inx
        cpx #LX_STATE_SIZE
        bne -
        sty lx_savesp
        rts
lx_pop:
        sec
        lda lx_savesp
        sbc #LX_STATE_SIZE
        sta lx_savesp
        tay
        ldx #0
-       lda lx_saves,y
        sta lx_ptr,x
        iny
        inx
        cpx #LX_STATE_SIZE
        bne -
        rts
lx_drop:
        sec
        lda lx_savesp
        sbc #LX_STATE_SIZE
        sta lx_savesp
        rts

; current char (Z = 0) / advance
LXC     .macro
        ldz #0
        lda [lx_ptr],z
        .endm

;---------------------------------------------------------------------------------------
lex:
        jsr _lex
        lda tok
        sta lx_last
        rts
_lex:
        lda lx_pend
        beq +
        dec lx_pend
        lda #TK_DEDENT
        sta tok
        rts
+       lda lx_bol
        beq _ws
        lda lx_paren
        bne _ws
        jsr lx_indent
        bcc _ws
        rts
_ws:    #LXC
        cmp #32
        beq _skip
        cmp #9
        beq _skip
        cmp #13
        beq _skip
        cmp #12
        beq _skip
        cmp #'\'
        bne +
        ldz #1
        lda [lx_ptr],z
        cmp #10
        bne _bad
        inw lx_ptr
        inw lx_line
        bra _skip
+       cmp #'#'
        bne +
-       inw lx_ptr
        #LXC
        beq _ws
        cmp #10
        bne -
        bra _ws
+       cmp #10
        bne _notnl
        inw lx_ptr
        inw lx_line
        lda lx_paren
        bne _ws
        lda #1
        sta lx_bol
        lda lx_last                     ; never two NEWLINEs in a row
        cmp #TK_NEWLINE
        beq _lex
        lda #TK_NEWLINE
        sta tok
        rts
_skip:  inw lx_ptr
        bra _ws
_bad:   jsr syntax_error
        .text "unexpected character", 0
_notnl: ldx #3
-       lda lx_ptr,x
        sta tok_start,x
        dex
        bpl -
        lda lx_line
        sta tok_line
        lda lx_line+1
        sta tok_line+1
        #LXC
        bne _tok
        ; end of input: NEWLINE, then DEDENTs, then EOF
        lda lx_last
        cmp #TK_NEWLINE
        beq +
        cmp #TK_DEDENT
        beq +
        cmp #TK_INDENT
        beq +
        lda #TK_NEWLINE
        sta tok
        rts
+       lda lx_isp
        beq +
        dec lx_isp
        lda #TK_DEDENT
        sta tok
        rts
+       lda #TK_EOF
        sta tok
        rts
_tok:   jsr is_name_start
        bcc +
        jmp lx_name
+       cmp #'0'
        bcc +
        cmp #'9'+1
        bcs +
        jmp lx_number
+       cmp #'.'
        bne +
        ldz #1
        lda [lx_ptr],z
        cmp #'0'
        bcc _dot
        cmp #'9'+1
        bcs _dot
        jmp lx_float
_dot:   lda #'.'
+       cmp #"'"
        beq _str
        cmp #'"'
        bne +
_str:   lda #0
        sta lx_raw
        sta lx_fstr
        sta lx_bytes
        jmp lx_string
+       jmp lx_op

; A = char -> C set for [A-Za-z_]
is_name_start:
        cmp #'_'
        beq _y
        cmp #'A'
        bcc _n
        cmp #'Z'+1
        bcc _y
        cmp #'a'
        bcc _n
        cmp #'z'+1
        bcc _y
_n:     clc
        rts
_y:     sec
        rts
; A = char -> C set for [A-Za-z0-9_]
is_name_char:
        cmp #'0'
        bcc is_name_start
        cmp #'9'+1
        bcs is_name_start
        sec
        rts

;---------------------------------------------------------------------------------------
; indentation at the start of a logical line. C set if a token was produced.
;---------------------------------------------------------------------------------------
lx_indent:
_line:  ldz #0
        ldx #0                          ; X = column
-       lda [lx_ptr],z
        cmp #32
        bne +
        inx
        inz
        bra -
+       cmp #9
        bne +
        txa
        clc
        adc #8
        and #$f8
        tax
        inz
        bra -
+       cmp #12
        bne +
        inz
        bra -
+       cmp #13
        bne +
        inz
        bra -
+       ; blank or comment-only line: skip it
        cmp #10
        beq _blank
        cmp #'#'
        bne _real
-       inz
        lda [lx_ptr],z
        beq _real                       ; comment at end of input
        cmp #10
        bne -
_blank: inz
        tza
        clc
        adc lx_ptr
        sta lx_ptr
        bcc +
        inc lx_ptr+1
+       inw lx_line
        bra _line
_real:  pha
        tza
        clc
        adc lx_ptr
        sta lx_ptr
        bcc +
        inc lx_ptr+1
+       pla
        bne +
        clc                             ; end of input: no indent change here
        rts
+       lda #0
        sta lx_bol
        ldy lx_isp
        txa
        cmp lx_istack,y
        beq _same
        bcc _dedent
        cpy #31
        bcc +
        jsr syntax_error
        .text "too many indentation levels", 0
+       iny
        sta lx_istack,y
        sty lx_isp
        lda #TK_INDENT
        sta tok
        sec
        rts
_same:  clc
        rts
_dedent:
        stx t0
        ldx #0                          ; X = DEDENTs
-       ldy lx_isp
        beq +
        lda lx_istack,y
        cmp t0
        beq +
        bcc +
        dec lx_isp
        inx
        bra -
+       ldy lx_isp
        lda lx_istack,y
        cmp t0
        beq +
        jsr indent_error
        .text "unindent does not match any outer indentation level", 0
+       dex
        stx lx_pend
        lda #TK_DEDENT
        sta tok
        sec
        rts

;---------------------------------------------------------------------------------------
; names and keywords (a name directly followed by a quote may be a string prefix)
;---------------------------------------------------------------------------------------
lx_name:
        ldz #0
-       inz
        lda [lx_ptr],z
        jsr is_name_char
        bcs -
        cmp #"'"
        beq _prefix
        cmp #'"'
        beq _prefix
_plain: stz str_len
        lda #0
        sta str_len+1
        tza
        clc
        adc lx_ptr
        sta lx_ptr
        bcc +
        inc lx_ptr+1
+       ldx #3
-       lda tok_start,x
        sta fp2,x
        dex
        bpl -
        jsr intern
        sta tok_sym
        stx tok_sym+1
        lda int_ref
        sta tok_ref
        lda int_ref+1
        sta tok_ref+1
        lda tok_sym+1
        bne +
        lda tok_sym
        cmp #NKEYWORDS
        bcs +
        adc #TK_KW
        sta tok
        rts
+       lda #TK_NAME
        sta tok
        rts
_prefix:
        ; r, b, f, rb, br, rf, fr in either case
        cpz #3
        bcs _plain
        lda #0
        sta lx_raw
        sta lx_fstr
        sta lx_bytes
        ldy #0
-       phz
        tya
        taz
        lda [lx_ptr],z
        plz
        ora #$20
        cmp #'r'
        bne +
        sta lx_raw
        bra _pn
+       cmp #'f'
        bne +
        sta lx_fstr
        bra _pn
+       cmp #'b'
        bne _plain
        sta lx_bytes
_pn:    iny
        sty t0
        cpz t0
        bne -
        tza
        clc
        adc lx_ptr
        sta lx_ptr
        bcc +
        inc lx_ptr+1
+       jmp lx_string

;---------------------------------------------------------------------------------------
; numbers: decimal, 0x, 0o, 0b, with _ separators. Ints are 32-bit.
;---------------------------------------------------------------------------------------
lx_number:
        lda #0
        sta tok_num
        sta tok_num+1
        sta tok_num+2
        sta tok_num+3
        lda #10
        sta t1                          ; base
        #LXC
        cmp #'0'
        bne _digits
        ldz #1
        lda [lx_ptr],z
        ora #$20
        ldx #16
        cmp #'x'
        beq _base
        ldx #8
        cmp #'o'
        beq _base
        ldx #2
        cmp #'b'
        bne _digits
_base:  stx t1
        inw lx_ptr
        inw lx_ptr
_digits:
        #LXC
        cmp #'_'
        beq _next
        jsr digit_value
        bcs _end
        cmp t1
        bcs _end
        sta t2
        ; tok_num = tok_num * base + digit
        ldq tok_num
        stq MULTINA
        lda t1
        sta MULTINB
        lda #0
        sta MULTINB+1
        sta MULTINB+2
        sta MULTINB+3
        lda MULTOUT+4
        ora MULTOUT+5
        ora MULTOUT+6
        ora MULTOUT+7
        bne _big
        lda MULTOUT+3
        bmi _big
        clc
        lda MULTOUT
        adc t2
        sta tok_num
        lda MULTOUT+1
        adc #0
        sta tok_num+1
        lda MULTOUT+2
        adc #0
        sta tok_num+2
        lda MULTOUT+3
        adc #0
        sta tok_num+3
        bmi _big
_next:  inw lx_ptr
        bra _digits
_end:   lda t1
        cmp #10
        bne +
        #LXC
        cmp #'.'
        beq lx_float
        ora #$20
        cmp #'e'
        beq lx_float
        cmp #'j'
        beq lx_float
+       lda #TK_INT
        sta tok
        rts
_big:   ; too big for an int: a float if a '.' or exponent follows the digits
        lda t1
        cmp #10
        bne _toobig
-       #LXC
        cmp #'_'
        beq +
        cmp #'0'
        bcc ++
        cmp #'9'+1
        bcs ++
+       inw lx_ptr
        bra -
+       cmp #'.'
        beq lx_float
        ora #$20
        cmp #'e'
        beq lx_float
_toobig:
        jmp lx_bigint

; lx_bigint - an int literal beyond 32 bits (base t1): a big int object (bigint.asm's
; form, made here: overlay C cannot reach tail N), as a TK_FLOAT token (a constant)
LB_MAX          = 210                   ; (bigint.asm's BG_MAX)
lb_len:         .byte 0
lb_carry:       .byte 0
lb_d:           .byte 0
lx_bigint:
        ldx #3
-       lda tok_start,x
        sta lx_ptr,x
        dex
        bpl -
        lda t1
        cmp #10
        beq +
        inw lx_ptr                      ; (past 0x, 0o, 0b)
        inw lx_ptr
+       lda #<BIGNUM
        sta bnA
        lda #>BIGNUM
        sta bnA+1
        lda #`BIGNUM
        sta bnA+2
        lda #0
        sta bnA+3
        sta lb_len
        tay
        ldz #0
-       sta [bnA],z
        inz
        bne -
        ldx #3
-       sta MULTINA,x
        sta MULTINB,x
        dex
        bpl -
_dig:   #LXC
        cmp #'_'
        beq _next
        jsr digit_value
        bcs _end
        cmp t1
        bcs _end
        sta lb_carry                    ; value = value * base + digit
        lda t1
        sta MULTINB
        ldz #0
-       cpz lb_len
        beq +
        lda [bnA],z
        sta MULTINA
        clc
        lda MULTOUT
        adc lb_carry
        sta [bnA],z
        lda MULTOUT+1
        adc #0
        sta lb_carry
        inz
        bra -
+       lda lb_carry
        beq _next
        sta [bnA],z
        inc lb_len
        lda lb_len
        cmp #LB_MAX+1
        bcc _next
        jsr syntax_error
        .text "integer literal too large (at most 505 digits)", 0
_next:  inw lx_ptr
        bra _dig
_end:   lda #TK_FLOAT
        sta tok
        lda lx_scan
        bne _rts
        clc
        lda lb_len
        adc #6
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_INT
        jsr alloc
        ldz #1
        lda [p0],z
        ora #F_BIG
        sta [p0],z
        ldz #4
        lda lb_len
        sta [p0],z
        inz
        lda #0
        sta [p0],z
        ldx #0
-       txa
        taz
        lda [bnA],z
        pha
        txa
        clc
        adc #6
        taz
        pla
        sta [p0],z
        inx
        cpx lb_len
        bne -
        lda p0
        sta tok_ref
        lda p0+1
        sta tok_ref+1
_rts:   rts

; a float literal: parsed again from its start
lx_float:
        ldx #3
-       lda tok_start,x
        sta fsp,x
        dex
        bpl -
        jsr c_fbig.f_parse              ; (overlay C's own copy of fbig.asm)
        bcc +
        jsr syntax_error
        .text "invalid decimal literal", 0
+       ldx #3
-       lda fsp,x
        sta lx_ptr,x
        dex
        bpl -
        #LXC
        ora #$20
        cmp #'j'
        bne +
        jsr syntax_error
        .text "complex numbers are not supported", 0
+       lda #TK_FLOAT
        sta tok
        lda lx_scan
        bne +
        jsr c_fbig.f_from_digits
        jsr float_new_dbl
        sta tok_ref
        stx tok_ref+1
+       rts


;---------------------------------------------------------------------------------------
; strings: '...' "..." '''...''' """...""", with escapes unless raw.
; Plain strings are decoded into the string builder and made into a TK_STR object.
; f-strings return the raw text (TK_FSTR) for the compiler to parse.
;---------------------------------------------------------------------------------------
lx_string:
        #LXC
        sta lx_quote
        lda #0
        sta lx_triple
        ldz #1
        lda [lx_ptr],z
        cmp lx_quote
        bne _single
        inz
        lda [lx_ptr],z
        cmp lx_quote
        bne _single
        lda #1
        sta lx_triple
        inw lx_ptr
        inw lx_ptr
_single:
        inw lx_ptr
        ; raw start (for f-strings)
        ldx #3
-       lda lx_ptr,x
        sta tok_num,x
        dex
        bpl -
        lda sbp
        pha
        lda sbp+1
        pha
_loop:  #LXC
        bne +
_unterm:
        jsr syntax_error
        .text "unterminated string literal", 0
+       cmp #10
        bne +
        ldx lx_triple
        beq _unterm
        inw lx_line
        bra _put
+       cmp lx_quote
        bne _notq
        lda lx_triple
        beq _close1
        ldz #1
        lda [lx_ptr],z
        cmp lx_quote
        bne _q
        inz
        lda [lx_ptr],z
        cmp lx_quote
        bne _q
        ; closing triple quote
        sec
        lda lx_ptr
        sbc tok_num
        sta tok_sym
        lda lx_ptr+1
        sbc tok_num+1
        sta tok_sym+1
        inw lx_ptr
        inw lx_ptr
        inw lx_ptr
        bra _done
_q:     lda lx_quote
        bra _put
_close1:
        sec
        lda lx_ptr
        sbc tok_num
        sta tok_sym
        lda lx_ptr+1
        sbc tok_num+1
        sta tok_sym+1
        inw lx_ptr
        bra _done
_notq:  cmp #'\'
        bne _put
        ldz #1                          ; escapes: the char after \ is never a closing quote
        lda [lx_ptr],z
        cmp #10
        bne +
        inw lx_line
+       lda lx_raw
        ora lx_fstr
        beq _esc
        lda #'\'
        jsr sb_putc
        inw lx_ptr
        #LXC
        bra _put
_esc:   inw lx_ptr
        jsr lx_escape
        bcs _loop                       ; nothing to add (line continuation)
_put:   jsr sb_putc
        inw lx_ptr
        jmp _loop
_done:  pla                             ; builder mark: hi, then lo
        sta t0+1
        pla
        sta t0
        lda lx_fstr
        bne _f
        lda lx_scan
        bne _skip
        lda t0
        ldx t0+1
        jsr sb_take
        sta tok_ref
        stx tok_ref+1
        lda lx_bytes                    ; b'...': a bytes object (bytes.asm)
        beq +
        lda tok_ref                     ; (its flags: F_BYTES)
        sta p0
        lda tok_ref+1
        sta p0+1
        ldz #1
        lda [p0],z
        ora #F_BYTES
        sta [p0],z
+       lda #TK_STR
        sta tok
        rts
_skip:  lda #TK_STR
        bra +
_f:     lda #TK_FSTR
+       sta tok
        lda t0
        sta sbp
        lda t0+1
        sta sbp+1
        rts

; lx_escape - lx_ptr at the char after \ : A = decoded char (C clear), lx_ptr on the
; last char of the escape; C set if the escape produces nothing.
lx_escape:
        #LXC
        cmp #'n'
        bne +
        lda #10
        clc
        rts
+       cmp #'t'
        bne +
        lda #9
        clc
        rts
+       cmp #'r'
        bne +
        lda #13
        clc
        rts
+       cmp #'0'
        bne +
        lda #0
        clc
        rts
+       cmp #10
        bne +
        inw lx_ptr
        sec
        rts
+       cmp #'x'
        bne +
        ldz #1
        lda [lx_ptr],z
        jsr digit_value
        asl
        asl
        asl
        asl
        sta t0
        ldz #2
        lda [lx_ptr],z
        jsr digit_value
        ora t0
        inw lx_ptr
        inw lx_ptr
        clc
        rts
+       cmp #'\'
        beq _same
        cmp #"'"
        beq _same
        cmp #'"'
        beq _same
        ; unknown escape: keep the backslash
        pha
        lda #'\'
        jsr sb_putc
        pla
_same:  clc
        rts

;---------------------------------------------------------------------------------------
; operators
;---------------------------------------------------------------------------------------
lx_op:
        ldz #0
        ldx #0
-       lda op1_chars,x
        beq _multi
        cmp [lx_ptr],z                  ; Z = 0
        beq _one
        inx
        bra -
_one:   lda op1_tok,x
        sta tok
        inw lx_ptr
        cmp #TK_LPAREN
        beq _open
        cmp #TK_LBRACK
        beq _open
        cmp #TK_LBRACE
        beq _open
        cmp #TK_RPAREN
        beq _close
        cmp #TK_RBRACK
        beq _close
        cmp #TK_RBRACE
        beq _close
        cmp #TK_COLON
        bne +
        #LXC
        cmp #'='
        bne +
        inw lx_ptr
        lda #TK_WALRUS
        sta tok
+       rts
_open:  inc lx_paren
        rts
_close: lda lx_paren
        beq +
        dec lx_paren
+       rts
_multi: ldx #0
-       lda opm_chars,x
        bne +
        jmp lx_bad_char
+       cmp [lx_ptr],z
        beq +
        inx
        bra -
+       lda opm_tok,x
        sta tok
        inw lx_ptr
        ; doubled operator: ** // << >>
        lda opm_dbl,x
        beq _eq
        sta t0
        lda opm_chars,x
        cmp [lx_ptr],z
        bne _eq
        lda t0
        sta tok
        inw lx_ptr
_eq:    lda opm_chars,x
        cmp #'-'
        bne +
        lda [lx_ptr],z
        cmp #'>'
        bne +
        inw lx_ptr
        lda #TK_ARROW
        sta tok
        rts
+       lda [lx_ptr],z
        cmp #'='
        bne _nq
        inw lx_ptr
        lda tok
        cmp #TK_ASSIGN
        bne +
        lda #TK_EQ
        sta tok
        rts
+       cmp #TK_LT
        bne +
        lda #TK_LE
        sta tok
        rts
+       cmp #TK_GT
        bne +
        lda #TK_GE
        sta tok
        rts
+       cmp #TK_NE
        bne +
        rts
+       clc
        adc #TK_AUG - TK_PLUS
        sta tok
        rts
_nq:    lda tok
        cmp #TK_NE                      ; a lone ! (f-string conversions)
        bne +
        lda #TK_BANG
        sta tok
+       rts

lx_bad_char:
        jsr syntax_error
        .text "invalid character", 0

op1_chars:      .text "()[]{},:;.~@", 0
op1_tok:        .byte TK_LPAREN, TK_RPAREN, TK_LBRACK, TK_RBRACK, TK_LBRACE, TK_RBRACE
                .byte TK_COMMA, TK_COLON, TK_SEMI, TK_DOT, TK_TILDE, TK_AT
opm_chars:      .text "+-*/%<>&|^=!", 0
opm_tok:        .byte TK_PLUS, TK_MINUS, TK_STAR, TK_SLASH, TK_PERCENT, TK_LT, TK_GT
                .byte TK_AMP, TK_PIPE, TK_CARET, TK_ASSIGN, TK_NE
opm_dbl:        .byte 0, 0, TK_POW, TK_DSLASH, 0, TK_LSHIFT, TK_RSHIFT, 0, 0, 0, 0, 0
