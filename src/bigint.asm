;=======================================================================================
; Big ints, tail N: integers beyond 32 bits.
;
; A big int is a T_INT object with F_BIG in its header flags: +4 the number of bytes of
; its magnitude (5 to BG_MAX), +5 its sign ($80 = negative), +6 the magnitude, little-
; endian, without zero bytes on top. A value that fits in 32 bits is never big (bg_store
; makes a plain int of it), so the 32-bit code stays as it was: arithmetic that
; overflows, or meets a big int, comes here (big_binop, big_unary, ...).
;
; The work is done in four registers of 256 bytes, the BIGNUM workspace (bank 1; the
; float conversions use it too, never in the middle of these): bg_len / bg_neg hold
; each one's length and sign, and the bytes above the length are always zero. The
; routines reach them through bnA / bnB / bnC (and fp2 for the row of a product).
;=======================================================================================
BG_MAX          = 210                   ; bytes of magnitude: up to 505 decimal digits
BG_R0           = 0
BG_R1           = 1
BG_R2           = 2
BG_R3           = 3

bg_len:         .fill 4
bg_neg:         .fill 4
bg_a:           .byte 0                 ; the registers of a two-operand routine
bg_b:           .byte 0
bg_c:           .byte 0
bg_r:           .byte 0
bg_n:           .byte 0
bg_k:           .byte 0
bg_x:           .byte 0
bg_carry:       .byte 0
bg_ref:         .word 0
bg_exp:         .dword 0
bg_op:          .byte 0
bg_sgn:         .byte 0

; bg_ptr - X = register, Y = 0 / 4 / 8 -> bnA / bnB / bnC point at its buffer
bg_ptr: lda #<BIGNUM
        sta bnA,y
        txa
        clc
        adc #>BIGNUM
        sta bnA+1,y
        lda #`BIGNUM
        sta bnA+2,y
        lda #0
        sta bnA+3,y
        rts
; bg_ptrs - bnA / bnB / bnC for bg_a / bg_b / bg_c
bg_ptrs:
        ldx bg_a
        ldy #0
        jsr bg_ptr
        ldx bg_b
        ldy #4
        jsr bg_ptr
        ldx bg_c
        ldy #8
        jmp bg_ptr

; bg_zero - register X = 0 (all 256 bytes)
bg_zero:
        ldy #0
        jsr bg_ptr
        lda #0
        sta bg_len,x
        sta bg_neg,x
        ldz #0
-       sta [bnA],z
        inz
        bne -
        rts

; bg_copy - register bg_c = register bg_a
bg_copy:
        jsr bg_ptrs
        ldz #0
-       lda [bnA],z
        sta [bnC],z
        inz
        bne -
        ldx bg_a
        ldy bg_c
        lda bg_len,x
        sta bg_len,y
        lda bg_neg,x
        sta bg_neg,y
        rts

; bg_load - A/X = an int (or bool), Y = register: its value
bg_load:
        sty bg_r
        sta bg_ref
        stx bg_ref+1
        ldx bg_r
        jsr bg_zero
        lda bg_ref
        ldx bg_ref+1
        jsr is_big
        bcs _big
        lda bg_ref
        ldx bg_ref+1
        jsr int_val
        ldx bg_r
        bit acc+3
        bpl +
        lda #$80
        sta bg_neg,x
        jsr acc_neg                     ; (-2^31 stays $80000000: right as unsigned)
+       ldz #0
        lda acc
        sta [bnA],z
        inz
        lda acc+1
        sta [bnA],z
        inz
        lda acc+2
        sta [bnA],z
        inz
        lda acc+3
        sta [bnA],z
        lda #4
        sta bg_len,x
        jmp bg_norm
_big:   lda bg_ref                      ; bnB = its magnitude (heap, bank 4)
        clc
        adc #6
        sta bnB
        lda bg_ref+1
        adc #0
        sta bnB+1
        lda #HEAP_BANK
        sta bnB+2
        lda #0
        sta bnB+3
        lda bg_ref
        sta p0
        lda bg_ref+1
        sta p0+1
        ldx bg_r
        ldz #4
        lda [p0],z
        sta bg_len,x
        sta bg_n
        inz
        lda [p0],z
        sta bg_neg,x
        ldz #0
-       lda [bnB],z
        sta [bnA],z
        inz
        cpz bg_n
        bne -
        rts

; bg_norm - register X: its length without the zero bytes on top (zero: positive)
bg_norm:
        ldy #0
        jsr bg_ptr
        ldz bg_len,x
-       cpz #0
        beq _zero
        dez
        lda [bnA],z
        beq -
        inz
        stz bg_len,x
        rts
_zero:  lda #0
        sta bg_len,x
        sta bg_neg,x
        rts

; bg_store - register X -> A/X = the int (a plain one when it fits in 32 bits)
bg_store:
        stx bg_r
        jsr bg_norm
        lda bg_len,x
        cmp #5
        bcs _big
        ldz #0
        lda [bnA],z
        sta acc
        inz
        lda [bnA],z
        sta acc+1
        inz
        lda [bnA],z
        sta acc+2
        inz
        lda [bnA],z
        sta acc+3
        bit acc+3
        bpl _fits
        lda bg_neg,x                    ; 2^31: only -2^31 fits
        beq _big
        lda acc+3
        cmp #$80
        bne _big
        lda acc+2
        ora acc+1
        ora acc
        bne _big
        jmp int_new
_fits:  lda bg_neg,x
        beq +
        jsr acc_neg
+       jmp int_new
_big:   ldx bg_r
        lda bg_len,x
        cmp #BG_MAX+1
        bcc +
        jmp bg_toobig
+       clc
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
        ldx bg_r
        ldz #4
        lda bg_len,x
        sta [p0],z
        sta bg_n
        inz
        lda bg_neg,x
        sta [p0],z
        ldy #0
        jsr bg_ptr
        clc
        lda p0
        adc #6
        sta bnB
        lda p0+1
        adc #0
        sta bnB+1
        lda #HEAP_BANK
        sta bnB+2
        lda #0
        sta bnB+3
        ldz #0
-       lda [bnA],z
        sta [bnB],z
        inz
        cpz bg_n
        bne -
        lda p0
        ldx p0+1
        rts
bg_toobig:
        #RAISE EXC_OVERFLOW, "int too large (at most 505 digits)"

;---------------------------------------------------------------------------------------
; magnitudes (signs ignored): registers bg_a, bg_b, result bg_c
;---------------------------------------------------------------------------------------
; mag_cmp - |a| vs |b| -> A = $ff less, 0 equal, 1 greater
mag_cmp:
        ldx bg_a
        ldy bg_b
        lda bg_len,x
        cmp bg_len,y
        bne _len
        jsr bg_ptrs
        ldx bg_a
        ldz bg_len,x
-       cpz #0
        beq _eq
        dez
        lda [bnA],z
        cmp [bnB],z
        beq -
_len:   bcc _lt
        lda #1
        rts
_lt:    lda #$ff
        rts
_eq:    lda #0
        rts

; bg_maxlen - A = the longer of a's and b's lengths
bg_maxlen:
        ldx bg_a
        ldy bg_b
        lda bg_len,x
        cmp bg_len,y
        bcs +
        lda bg_len,y
+       rts

; mag_add - |c| = |a| + |b| (c may be a or b)
mag_add:
        jsr bg_maxlen
        inc a
        sta bg_n
        jsr bg_ptrs
        ldy bg_n                        ; (counted in Y: cpz would change the carry)
        clc
        ldz #0
-       lda [bnA],z
        adc [bnB],z
        sta [bnC],z
        inz
        dey
        bne -
        bra mag_done
; mag_sub - |c| = |a| - |b|, |a| >= |b| (c may be a or b)
mag_sub:
        ldx bg_a
        lda bg_len,x
        sta bg_n
        jsr bg_ptrs
        ldy bg_n
        beq mag_done
        sec
        ldz #0
-       lda [bnA],z
        sbc [bnB],z
        sta [bnC],z
        inz
        dey
        bne -
mag_done:
        ldx bg_c
        lda bg_n
        sta bg_len,x
        jmp bg_norm

; mag_mul - |c| = |a| * |b| (c another register)
mag_mul:
        ldx bg_a
        ldy bg_b
        clc
        lda bg_len,x
        adc bg_len,y
        bcs +
        cmp #BG_MAX+2
        bcc ++
+       jmp bg_toobig
+       sta bg_n
        ldx bg_c
        jsr bg_zero
        jsr bg_ptrs
        lda #0
        ldx #3
-       sta MULTINA,x
        sta MULTINB,x
        dex
        bne -
        lda #0                          ; row i: c[i + j] += a[i] * b[j]
        sta bg_k
_row:   ldx bg_a
        lda bg_k
        cmp bg_len,x
        bcs _end
        taz
        lda [bnA],z
        beq _next
        sta MULTINA
        clc                             ; fp2 = &c[i]
        lda bnC
        adc bg_k
        sta fp2
        lda bnC+1
        adc #0
        sta fp2+1
        lda bnC+2
        sta fp2+2
        lda #0
        sta fp2+3
        sta bg_carry
        ldx bg_b
        ldz #0
-       tza
        cmp bg_len,x
        beq +
        lda [bnB],z
        sta MULTINB
        clc
        lda MULTOUT
        adc [fp2],z
        sta bg_x
        lda MULTOUT+1
        adc #0
        sta bg_r
        clc
        lda bg_x
        adc bg_carry
        sta [fp2],z
        lda bg_r
        adc #0
        sta bg_carry
        inz
        bra -
+       lda bg_carry
        sta [fp2],z
_next:  inc bg_k
        bra _row
_end:   ldx bg_c
        lda bg_n
        sta bg_len,x
        jmp bg_norm

; mag_inc / mag_dec - |register X| +/- 1 (|X| > 0 for dec)
mag_inc:
        stx bg_r
        ldy #0
        jsr bg_ptr
        ldz #0
-       lda [bnA],z
        inc a
        sta [bnA],z
        bne +
        inz
        bra -
+       inz
        ldx bg_r
        tza
        cmp bg_len,x
        bcc +
        sta bg_len,x
+       rts
mag_dec:
        stx bg_r
        ldy #0
        jsr bg_ptr
        ldz #0
-       lda [bnA],z
        dec a
        sta [bnA],z
        cmp #$ff
        bne +
        inz
        bra -
+       ldx bg_r
        jmp bg_norm

; mag_divmod - |a| / |b| -> quotient in register 2, remainder in register 3 (a, b are
; registers 0 and 1, |b| > 0)
mag_divmod:
        ldx #BG_R2
        jsr bg_zero
        ldx #BG_R3
        jsr bg_zero
        lda bg_len+BG_R1
        cmp #1
        bne _long
        ; one byte: short division, from the top
        ldx #BG_R0
        ldy #0
        jsr bg_ptr
        ldx #BG_R2
        ldy #8
        jsr bg_ptr
        ldx #BG_R1
        ldy #4
        jsr bg_ptr
        ldz #0
        lda [bnB],z                     ; (the divisor's byte)
        sta bg_x
        lda #0
        sta bg_r                        ; the remainder
        ldz bg_len+BG_R0
-       cpz #0
        beq +
        dez
        lda [bnA],z
        jsr bg_div8
        sta [bnC],z
        bra -
+       lda bg_len+BG_R0
        sta bg_len+BG_R2
        ldx #BG_R3
        ldy #4
        jsr bg_ptr
        ldz #0
        lda bg_r
        sta [bnB],z
        lda #1
        sta bg_len+BG_R3
        ldx #BG_R3
        jsr bg_norm
        ldx #BG_R2
        jmp bg_norm
_long:  ; bit by bit: r = r << 1 | the next bit of a; r >= b: r -= b, that bit of q set
        lda bg_len+BG_R1
        inc a
        sta bg_n                        ; (r < 2b fits in |b| + 1 bytes)
        lda bg_len+BG_R0
        sta bg_k                        ; bytes of a, from the top
_byte:  lda bg_k
        beq _done
        dec bg_k
        ldx #BG_R0
        ldy #0
        jsr bg_ptr
        ldz bg_k
        lda [bnA],z
        sta bg_x
        lda #$80
        sta bg_carry                    ; the bit's mask
_bit:   ldx #BG_R3                      ; r <<= 1, in the next bit
        ldy #0
        jsr bg_ptr
        ldy bg_n
        asl bg_x
        ldz #0
-       lda [bnA],z
        rol a
        sta [bnA],z
        inz
        dey
        bne -
        ldx #BG_R3                      ; r >= b?
        ldy #0
        jsr bg_ptr
        ldx #BG_R1
        ldy #4
        jsr bg_ptr
        ldz bg_n
-       dez
        lda [bnA],z
        cmp [bnB],z
        bne +
        cpz #0
        bne -
        sec                             ; (equal)
+       bcc _nosub
        ldy bg_n
        sec
        ldz #0
-       lda [bnA],z
        sbc [bnB],z
        sta [bnA],z
        inz
        dey
        bne -
        ldx #BG_R2
        ldy #8
        jsr bg_ptr
        ldz bg_k
        lda [bnC],z
        ora bg_carry
        sta [bnC],z
_nosub: lsr bg_carry
        bcc _bit
        bra _byte
_done:  lda bg_len+BG_R0
        sta bg_len+BG_R2
        lda bg_n
        sta bg_len+BG_R3
        ldx #BG_R3
        jsr bg_norm
        ldx #BG_R2
        jmp bg_norm

; bg_div8 - (bg_r : A) / bg_x -> A = quotient, bg_r = remainder (bg_r < bg_x)
bg_div8:
        ldy #8
-       asl a
        rol bg_r
        bcs +
        pha
        lda bg_r
        cmp bg_x
        pla
        bcc ++
+       pha
        lda bg_r
        sbc bg_x
        sta bg_r
        pla
        ora #1
+       dey
        bne -
        rts

; bg_muladd - register X = register X * A + Y (A, Y bytes)
bg_muladd:
        sta MULTINB
        sty bg_carry
        stx bg_r
        lda #0
        ldy #3
-       sta MULTINA,y
        sta MULTINB,y
        dey
        bne -
        ldy #0
        jsr bg_ptr
        ldx bg_r
        lda bg_len,x
        inc a
        cmp #BG_MAX+1
        bcc +
        jmp bg_toobig
+       sta bg_n
        ldz #0
-       lda [bnA],z
        sta MULTINA
        clc
        lda MULTOUT
        adc bg_carry
        sta [bnA],z
        lda MULTOUT+1
        adc #0
        sta bg_carry
        inz
        cpz bg_n
        bne -
        lda bg_n
        sta bg_len,x
        jmp bg_norm

;---------------------------------------------------------------------------------------
; xn_binop - r2 <bop> r3, ints (one of them big, or a 32-bit result overflowed) -> A/X
;---------------------------------------------------------------------------------------
xn_binop:
        lda bop
        cmp #BOP_IADD
        bne +
        lda #BOP_ADD
+       sta bg_op
        cmp #BOP_TRUEDIV
        bne +
        jmp float_binop                 ; (as floats)
+       lda r2
        ldx r2+1
        ldy #BG_R0
        jsr bg_load
        lda bg_op
        cmp #BOP_POW
        bne +
        jmp bg_pow
+       cmp #BOP_LSHIFT
        bne +
        jmp bg_shl
+       cmp #BOP_RSHIFT
        bne +
        jmp bg_shr
+       lda r3
        ldx r3+1
        ldy #BG_R1
        jsr bg_load
        lda bg_op
        cmp #BOP_MUL
        beq bg_mul
        cmp #BOP_FLOORDIV
        beq bg_div
        cmp #BOP_MOD
        beq bg_div
        cmp #BOP_AND
        bcc bg_addsub
        jmp bg_bits

; a + b, a - b
bg_addsub:
        cmp #BOP_SUB
        bne +
        lda bg_len+BG_R1                ; a - b = a + (-b)
        beq +
        lda bg_neg+BG_R1
        eor #$80
        sta bg_neg+BG_R1
+       jsr bg_set01
        lda bg_neg+BG_R0
        cmp bg_neg+BG_R1
        bne _diff
        jsr mag_add                     ; the same signs: add the magnitudes
        lda bg_neg+BG_R0
        bra _sign
_diff:  jsr mag_cmp
        cmp #$ff
        beq +
        jsr mag_sub                     ; |a| >= |b|: a's sign
        lda bg_neg+BG_R0
        bra _sign
+       lda #BG_R1
        sta bg_a
        lda #BG_R0
        sta bg_b
        jsr mag_sub
        lda bg_neg+BG_R1
_sign:  sta bg_neg+BG_R2
        ldx #BG_R2
        jmp bg_store

; bg_set01 - a = register 0, b = register 1, c = register 2
bg_set01:
        lda #BG_R0
        sta bg_a
        lda #BG_R1
        sta bg_b
        lda #BG_R2
        sta bg_c
        rts

; a * b
bg_mul: jsr bg_set01
        jsr mag_mul
        lda bg_neg+BG_R0
        eor bg_neg+BG_R1
        sta bg_neg+BG_R2
        ldx #BG_R2
        jmp bg_store

; a // b, a % b: floored, as Python (the remainder has b's sign)
bg_div: lda bg_len+BG_R1
        bne +
        #RAISE EXC_ZERODIV, "integer division or modulo by zero"
+       jsr mag_divmod
        lda bg_neg+BG_R0
        cmp bg_neg+BG_R1
        beq _signs
        lda bg_len+BG_R3                ; signs differ, a remainder: q + 1, r = |b| - r
        beq _signs
        ldx #BG_R2
        jsr mag_inc
        lda #BG_R1
        sta bg_a
        lda #BG_R3
        sta bg_b
        sta bg_c
        jsr mag_sub
_signs: lda bg_neg+BG_R0
        eor bg_neg+BG_R1
        sta bg_neg+BG_R2
        lda bg_neg+BG_R1
        sta bg_neg+BG_R3
        ldx #BG_R2
        lda bg_op
        cmp #BOP_FLOORDIV
        beq +
        ldx #BG_R3
+       jmp bg_store

; a ** b (b a 32-bit int >= 0; negative: a float)
bg_pow: lda r3
        ldx r3+1
        jsr is_big
        bcc _small
        ldz #5                          ; (is_big pointed p0 at it)
        lda [p0],z
        bpl +
        jmp float_binop                 ; a negative power: a float
+       ldz #6                          ; a huge power: only 0, 1, -1 stay small
        lda [p0],z
        and #1
        bne +
        lda #2                          ; (an even power acts as 2, an odd one as 1)
+       sta bg_exp
        lda #0
        sta bg_exp+1
        sta bg_exp+2
        sta bg_exp+3
        lda bg_len+BG_R0
        cmp #2
        bcs _huge
        ldx #BG_R0
        ldy #0
        jsr bg_ptr
        ldz #0
        lda [bnA],z
        cmp #2
        bcc _go
_huge:  jmp bg_toobig
_small: lda r3
        ldx r3+1
        jsr int_val
        bit acc+3
        bpl +
        jmp float_binop                 ; a negative power: a float
+       ldq acc
        stq bg_exp
_go:    lda #0                          ; the sign: a negative base, an odd power
        sta bg_sgn
        lda bg_exp
        and #1
        beq +
        lda bg_neg+BG_R0
        sta bg_sgn
+       lda #0
        sta bg_neg+BG_R0
        ldx #BG_R1                      ; the result = 1
        jsr bg_zero
        ldz #0
        lda #1
        sta [bnA],z
        sta bg_len+BG_R1
_loop:  lda bg_exp
        ora bg_exp+1
        ora bg_exp+2
        ora bg_exp+3
        beq _done
        lda bg_exp
        and #1
        beq _sq
        lda #BG_R1                      ; result *= base
        sta bg_a
        lda #BG_R0
        sta bg_b
        lda #BG_R2
        sta bg_c
        jsr mag_mul
        lda #BG_R2
        sta bg_a
        lda #BG_R1
        sta bg_c
        jsr bg_copy
_sq:    lsr bg_exp+3
        ror bg_exp+2
        ror bg_exp+1
        ror bg_exp
        lda bg_exp
        ora bg_exp+1
        ora bg_exp+2
        ora bg_exp+3
        beq _done
        lda #BG_R0                      ; base *= base
        sta bg_a
        sta bg_b
        lda #BG_R2
        sta bg_c
        jsr mag_mul
        lda #BG_R2
        sta bg_a
        lda #BG_R0
        sta bg_c
        jsr bg_copy
        bra _loop
_done:  lda bg_sgn
        sta bg_neg+BG_R1
        ldx #BG_R1
        jmp bg_store

; bg_count - r3 = a shift count -> bg_exp (C clear), or C set if it is huge (big);
; negative: ValueError
bg_count:
        lda r3
        ldx r3+1
        jsr is_big
        bcc +
        ldz #5
        lda [p0],z
        bmi _neg
        sec
        rts
+       lda r3
        ldx r3+1
        jsr int_val
        bit acc+3
        bmi _neg
        ldq acc
        stq bg_exp
        lda bg_exp+2                    ; (more than 65535 bits: huge too)
        ora bg_exp+3
        cmp #1
        rts
_neg:   #RAISE EXC_VALUE, "negative shift count"

; bg_bytes - bg_exp bits -> bg_k = whole bytes (C set if more than 255), bg_x = bits
bg_bytes:
        lda bg_exp
        and #7
        sta bg_x
        lda bg_exp+1
        sta bg_r
        lda bg_exp
        lsr bg_r
        ror a
        lsr bg_r
        ror a
        lsr bg_r
        ror a
        sta bg_k
        lda bg_r
        cmp #1
        rts

; a << n
bg_shl: jsr bg_count
        bcs _huge
        jsr bg_shl_core
        lda bg_neg+BG_R0
        sta bg_neg+BG_R2
        ldx #BG_R2
        jmp bg_store
_huge:  lda bg_len+BG_R0
        bne +
        lda #1                          ; 0 << n = 0
        ldx #0
        rts
+       jmp bg_toobig
; bg_shl_core - |register 2| = |register 0| << bg_exp
bg_shl_core:
        jsr bg_bytes
        bcs _big
        clc
        lda bg_k
        adc bg_len+BG_R0
        bcs _big
        cmp #BG_MAX+1
        bcs _big
        inc a
        sta bg_n
        ldx #BG_R2
        jsr bg_zero
        ldx #BG_R0
        ldy #0
        jsr bg_ptr
        ldx #BG_R2
        ldy #8
        jsr bg_ptr
        clc                             ; fp2 = &r2[k]
        lda bnC
        adc bg_k
        sta fp2
        lda bnC+1
        adc #0
        sta fp2+1
        lda bnC+2
        sta fp2+2
        lda #0
        sta fp2+3
        ldz #0
-       cpz bg_len+BG_R0
        beq +
        lda [bnA],z
        sta [fp2],z
        inz
        bra -
+       lda bg_n
        sta bg_len+BG_R2
-       lda bg_x                        ; then the bits
        beq +
        dec bg_x
        ldy bg_n
        clc
        ldz #0
_rol:   lda [bnC],z
        rol a
        sta [bnC],z
        inz
        dey
        bne _rol
        bra -
+       ldx #BG_R2
        jmp bg_norm
_big:   lda bg_len+BG_R0
        beq +
        jmp bg_toobig
+       ldx #BG_R2
        jmp bg_zero

; a >> n (floored: -5 >> 1 = -3, as -((|a| - 1) >> n) - 1)
bg_shr: jsr bg_count
        bcc +
        lda #$ff                        ; huge: 0 or -1
        sta bg_exp
        sta bg_exp+1
+       lda bg_neg+BG_R0
        beq +
        ldx #BG_R0
        jsr mag_dec
+       jsr bg_shr_core
        lda bg_neg+BG_R0
        beq +
        ldx #BG_R2
        jsr mag_inc
        lda #$80
        sta bg_neg+BG_R2
+       ldx #BG_R2
        jmp bg_store
; bg_shr_core - |register 2| = |register 0| >> bg_exp (16 bits)
bg_shr_core:
        ldx #BG_R2
        jsr bg_zero
        jsr bg_bytes
        bcs _zero
        lda bg_k
        cmp bg_len+BG_R0
        bcs _zero
        sec
        lda bg_len+BG_R0
        sbc bg_k
        sta bg_n
        ldx #BG_R0
        ldy #0
        jsr bg_ptr
        ldx #BG_R2
        ldy #8
        jsr bg_ptr
        clc                             ; fp2 = &r0[k]
        lda bnA
        adc bg_k
        sta fp2
        lda bnA+1
        adc #0
        sta fp2+1
        lda bnA+2
        sta fp2+2
        lda #0
        sta fp2+3
        ldz #0
-       lda [fp2],z
        sta [bnC],z
        inz
        cpz bg_n
        bne -
        lda bg_n
        sta bg_len+BG_R2
-       lda bg_x
        beq +
        dec bg_x
        ldy bg_n
        clc
        ldz bg_n
_ror:   dez
        lda [bnC],z
        ror a
        sta [bnC],z
        dey
        bne _ror
        bra -
+       ldx #BG_R2
        jmp bg_norm
_zero:  rts

; a & b, a | b, a ^ b: on two's complement forms one byte longer than both
bg_bits:
        jsr bg_maxlen
        inc a
        sta bg_n
        ldx #BG_R0
        jsr bg_tc
        ldx #BG_R1
        jsr bg_tc
        ldx #BG_R2
        jsr bg_zero
        jsr bg_set01
        jsr bg_ptrs
        ldz #0
-       lda [bnA],z
        ldx bg_op
        cpx #BOP_AND
        bne +
        and [bnB],z
        bra _st
+       cpx #BOP_OR
        bne +
        ora [bnB],z
        bra _st
+       eor [bnB],z
_st:    sta [bnC],z
        inz
        cpz bg_n
        bne -
        lda bg_n
        sta bg_len+BG_R2
        dez
        lda [bnC],z
        bpl +
        ldx #BG_R2                      ; negative: the magnitude is ~r + 1
        jsr bg_inv
        ldx #BG_R2
        jsr bg_norm
        ldx #BG_R2
        jsr mag_inc
        lda #$80
        sta bg_neg+BG_R2
+       ldx #BG_R2
        jmp bg_store
; bg_tc - register X in two's complement over bg_n bytes
bg_tc:  lda bg_neg,x
        beq +
        stx bg_r
        jsr mag_dec
        ldx bg_r
        jmp bg_inv
+       rts
; bg_inv - register X: its first bg_n bytes inverted
bg_inv: ldy #0
        jsr bg_ptr
        ldz #0
-       lda [bnA],z
        eor #$ff
        sta [bnA],z
        inz
        cpz bg_n
        bne -
        rts

;---------------------------------------------------------------------------------------
; xn_unary - A = OP_NEG / OP_POS / OP_INVERT, r2 = an int -> A/X
;---------------------------------------------------------------------------------------
xn_unary:
        sta bg_op
        lda r2
        ldx r2+1
        ldy #BG_R0
        jsr bg_load
        lda bg_op
        cmp #OP_INVERT
        beq _inv
        cmp #OP_NEG
        bne _store
        lda bg_len+BG_R0
        beq _store
        lda bg_neg+BG_R0
        eor #$80
        sta bg_neg+BG_R0
        bra _store
_inv:   ldx #BG_R0                      ; ~x = -x - 1
        lda bg_neg+BG_R0
        bne +
        jsr mag_inc
        lda #$80
        sta bg_neg+BG_R0
        bra _store
+       jsr mag_dec
        lda #0
        sta bg_neg+BG_R0
_store: ldx #BG_R0
        jmp bg_store

; xn_cmp - order r2 vs r3 (ints, one big) -> A = $ff less, 0 equal, 1 greater
xn_cmp: lda r2
        ldx r2+1
        ldy #BG_R0
        jsr bg_load
        lda r3
        ldx r3+1
        ldy #BG_R1
        jsr bg_load
        lda bg_neg+BG_R0
        cmp bg_neg+BG_R1
        beq _same
        lda bg_neg+BG_R0
        bne _lt
        lda #1
        rts
_lt:    lda #$ff
        rts
_same:  jsr bg_set01
        jsr mag_cmp
        ldx bg_neg+BG_R0
        beq +
        cmp #0
        beq +
        eor #$fe                        ; both negative: the other way round
+       rts

;---------------------------------------------------------------------------------------
; xn_repr - A/X = a big int: its decimal digits onto the string builder
;---------------------------------------------------------------------------------------
xn_repr:
        ldy #BG_R3
        jsr bg_load
        lda bg_neg+BG_R3
        beq +
        lda #'-'
        jsr sb_putc
+       jmp bg_dec

; xn_digits - A/X = a big int, t6 = base (10, 16, 8, 2): the digits of its magnitude
; onto the string builder (lower-case)
xn_digits:
        ldy #BG_R3
        jsr bg_load
        lda t6
        cmp #10
        beq bg_dec
        ldx #4                          ; bits per digit
        cmp #16
        beq +
        dex
        cmp #8
        beq +
        ldx #1
+       stx bg_x
        lda #0                          ; bg_exp = the number of bits, rounded up to
        sta bg_exp+1                    ; whole digits
        lda bg_len+BG_R3
        asl a
        rol bg_exp+1
        asl a
        rol bg_exp+1
        asl a
        rol bg_exp+1
        sta bg_exp
-       jsr _mod                        ; (bits % bits per digit = 0?)
        beq +
        inc bg_exp
        bne -
        inc bg_exp+1
        bra -
+       lda #1
        sta bg_op                       ; still skipping leading zeros
_digit: lda bg_exp
        ora bg_exp+1
        bne +
        lda bg_op                       ; (all zero: "0")
        beq _end
        lda #'0'
        jmp sb_putc
_end:   rts
+       lda #0                          ; the next digit: its bits from the top
        sta bg_r
        ldy bg_x
-       lda bg_exp
        bne +
        dec bg_exp+1
+       dec bg_exp
        jsr _bit
        rol bg_r
        dey
        bne -
        lda bg_r
        bne +
        ldx bg_op
        bne _digit
+       ldx #0
        stx bg_op
        tax
        lda hex_digits,x
        jsr sb_putc
        bra _digit
_bit:   lda bg_exp+1                    ; C = bit bg_exp of register 3
        sta bg_k
        lda bg_exp
        lsr bg_k
        ror a
        lsr bg_k
        ror a
        lsr bg_k
        ror a
        taz
        lda bg_exp
        and #7
        tax
        lda [bnA],z
-       dex
        bmi +
        lsr a
        bra -
+       lsr a
        rts
_mod:   lda bg_exp                      ; Z set if bg_exp is a multiple of bg_x
        ldx bg_x
        cpx #3
        beq _m3
        and #3                          ; (4 bits: bg_exp is 8 * length; 1 bit: any)
        cpx #4
        beq +
        lda #0
+       rts
_m3:    clc                             ; 256 = 1 (mod 3): hi + lo, and its carry
        lda bg_exp+1
        adc bg_exp
        tay
        lda #0
        adc #0
        sta bg_k
        tya
_m3a:   cmp #3
        bcc _m3b
        sbc #3
        bra _m3a
_m3b:   clc
        adc bg_k
        cmp #3
        bcc +
        sbc #3
+       cmp #0
        rts

; bg_dec - register 3's magnitude in decimal onto the string builder
bg_dec: lda #0
        sta bg_k
_div:   lda #100                        ; two digits at a time into register 2
        sta bg_x
        lda #0
        sta bg_r
        ldx #BG_R3
        ldy #0
        jsr bg_ptr
        ldz bg_len+BG_R3
-       cpz #0
        beq +
        dez
        lda [bnA],z
        jsr bg_div8
        sta [bnA],z
        bra -
+       ldx #BG_R2
        ldy #8
        jsr bg_ptr
        ldz bg_k
        lda bg_r
        sta [bnC],z
        inc bg_k
        ldx #BG_R3
        jsr bg_norm
        lda bg_len+BG_R3
        bne _div
        dec bg_k                        ; the top pair without a leading zero
        lda #1
        sta bg_op
-       ldx #BG_R2
        ldy #8
        jsr bg_ptr
        ldz bg_k
        lda [bnC],z
        ldx #0
_ten:   cmp #10
        bcc +
        sbc #10
        inx
        bra _ten
+       pha
        txa
        ldx bg_op
        beq +
        cmp #0
        beq ++
+       ora #'0'
        jsr sb_putc
+       pla
        ora #'0'
        jsr sb_putc
        lda #0
        sta bg_op
        lda bg_k
        beq +
        dec bg_k
        bra -
+       rts

;---------------------------------------------------------------------------------------
; xn_to_fa - A/X = a big int -> fa (rounded once, by f_pack later)
xn_to_fa:
        ldy #BG_R0
        jsr bg_load
        jsr fa_zero
        lda bg_neg+BG_R0
        sta fa+F_SIGN
        lda bg_len+BG_R0                ; exponent = 8 * len - 1
        sta fa+F_EXP
        lda #0
        sta fa+F_EXP+1
        asl fa+F_EXP
        rol fa+F_EXP+1
        asl fa+F_EXP
        rol fa+F_EXP+1
        asl fa+F_EXP
        rol fa+F_EXP+1
        lda fa+F_EXP
        bne +
        dec fa+F_EXP+1
+       dec fa+F_EXP
        sec                             ; mantissa = the top 8 bytes
        lda bg_len+BG_R0
        sbc #8
        sta bg_r                        ; (the index of its lowest byte: may be < 0)
        ldx #0
-       txa
        clc
        adc bg_len+BG_R0
        cmp #8
        bcc +
        sbc #8
        taz
        lda [bnA],z
        sta fa+F_MAN,x
+       inx
        cpx #8
        bne -
        lda bg_len+BG_R0                ; anything below: a sticky 1 bit
        cmp #9
        bcc +
        ldz bg_r
-       dez
        lda [bnA],z
        bne _sticky
        cpz #0
        bne -
        bra +
_sticky:
        lda fa+F_MAN
        ora #1
        sta fa+F_MAN
+       jsr fa_norm
        clc
        rts

; xn_from_fa - fa (finite, integral, beyond 32 bits) -> A/X = the int
xn_from_fa:
        ldx #BG_R0
        jsr bg_zero
        ldx #0
        ldz #0
-       lda fa+F_MAN,x
        sta [bnA],z
        inx
        inz
        cpx #8
        bne -
        lda #8
        sta bg_len+BG_R0
        sec                             ; value = mantissa * 2^(exponent - 63)
        lda fa+F_EXP
        sbc #63
        sta bg_exp
        lda fa+F_EXP+1
        sbc #0
        sta bg_exp+1
        bmi _right
        jsr bg_shl_core
        bra _sign
_right: sec
        lda #63
        sbc fa+F_EXP
        sta bg_exp
        lda #0
        sbc fa+F_EXP+1
        sta bg_exp+1
        jsr bg_shr_core
_sign:  lda fa+F_SIGN
        sta bg_neg+BG_R2
        ldx #BG_R2
        jmp bg_store

;---------------------------------------------------------------------------------------
; xn_parse - r2 = a string, t6 = base (0: from its prefix) -> C clear and A/X = the int
; (int() of digits beyond 32 bits), C set if it is not a valid literal
;---------------------------------------------------------------------------------------
xn_parse:
        ldx #BG_R0
        jsr bg_zero
        lda #0
        sta bg_k                        ; digits seen
        lda r2
        ldx r2+1
        jsr str_info
        jsr _ws
        jsr _peek
        cmp #'-'
        bne +
        lda #$80
        sta bg_neg+BG_R0
        jsr _adv
        bra ++
+       cmp #'+'
        bne +
        jsr _adv
+       lda t6                          ; a prefix (for base 0, or that base)
        beq +
        cmp #16
        beq +
        cmp #8
        beq +
        cmp #2
        bne _dig
+       jsr _peek
        cmp #'0'
        bne _nopfx
        lda str_len+1
        bne +
        lda str_len
        cmp #2
        bcc _nopfx
+       ldz #1
        lda [fp0],z
        ora #$20
        ldx #16
        cmp #'x'
        beq _setb
        ldx #8
        cmp #'o'
        beq _setb
        ldx #2
        cmp #'b'
        bne _nopfx
_setb:  lda t6
        beq +
        cpx t6
        bne _nopfx
+       stx t6
        jsr _adv
        jsr _adv
_nopfx: lda t6
        bne _dig
        lda #10
        sta t6
_dig:   jsr _peek
        bcs _end
        cmp #'_'
        beq _skip
        jsr digit_value
        bcs _end
        cmp t6
        bcs _end
        tay
        lda bg_neg+BG_R0                ; (bg_muladd's norm would clear the sign of 0)
        pha
        ldx #BG_R0
        lda t6
        jsr bg_muladd
        pla
        sta bg_neg+BG_R0
        inc bg_k
_skip:  jsr _adv
        bra _dig
_end:   jsr _ws
        lda str_len
        ora str_len+1
        bne _bad
        lda bg_k
        beq _bad
        ldx #BG_R0
        jsr bg_store
        clc
        rts
_bad:   sec
        rts
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
_ws:    jsr _peek
        bcs +
        cmp #33
        bcs +
        jsr _adv
        bra _ws
+       rts
