;=======================================================================================
; Disk I/O through the KERNAL. The interpreter normally runs with interrupts off, a
; 16-bit stack and base page $16; kernal_call puts back what the KERNAL expects
; (page-1 stack, B = 0, interrupts on) around one call. Keep this file below $8000:
; the KERNAL's DOS maps itself in at $8000 during disk calls.
;
; Files are PRGs whose 2-byte load address is ignored: the contents are plain ASCII
; Python source. Names are .py files on drive 8.
;=======================================================================================
KERNAL_SETMSG           = $FF90

kc_addr:        .word 0
kc_a:           .byte 0
kc_x:           .byte 0
kc_y:           .byte 0
kc_p:           .byte 0                 ; the flags after the call (bit 0 = carry)
kc_spl:         .byte 0
kc_sph:         .byte 0

; kernal_call - call the KERNAL routine at kc_addr with kc_a/kc_x/kc_y
kernal_call:
        jsr map_kernal
        tsx
        stx kc_spl
        tsy
        sty kc_sph
        ldx #$fb
        txs
        ldy #$01
        tys
        see                             ; 8-bit stack in page 1
        lda #0
        tab
        cli
        lda kc_a
        ldx kc_x
        ldy kc_y
        jsr _call
        php
        sei
        sta kc_a
        stx kc_x
        sty kc_y
        pla
        sta kc_p
        lda #BP_PAGE
        tab
        cle
        ldy kc_sph
        tys
        ldx kc_spl
        txs
        jmp map_running

_call:  jmp (kc_addr)

KCALL   .macro addr
        lda #<\addr
        sta kc_addr
        lda #>\addr
        sta kc_addr+1
        jsr kernal_call
        .endm

kernal_init:
        lda #0                          ; no KERNAL messages
        sta kc_a
        #KCALL KERNAL_SETMSG
        rts

; the file name for KERNAL calls: ASCII -> PETSCII (swap the letter cases)
; FNAMEBUF holds fname_len chars; kc_name gets the converted copy, with a prefix
kc_name:        .fill 24, 0
kc_name_len:    .byte 0
make_kname:                             ; A = 1: prefix "@0:" (save with replace)
        ldy #0
        cmp #0
        beq +
        lda #'@'
        sta kc_name
        lda #'0'
        sta kc_name+1
        lda #':'
        sta kc_name+2
        ldy #3
+       ldx #0
-       cpx fname_len
        bcs +
        lda FNAMEBUF,x
        jsr ascii_to_petscii
        sta kc_name,y
        iny
        inx
        bra -
+       sty kc_name_len
        rts

ascii_to_petscii:
        cmp #'a'
        bcc +
        cmp #'z'+1
        bcs +
        and #$df                        ; a-z -> $41-$5A (shown lower case)
        rts
+       cmp #'A'
        bcc +
        cmp #'Z'+1
        bcs +
        ora #$80                        ; A-Z -> $C1-$DA
+       rts
petscii_to_ascii:
        cmp #$41
        bcc +
        cmp #$5b
        bcs +
        ora #$20
        rts
+       cmp #$c1
        bcc +
        cmp #$db
        bcs +
        and #$7f
+       rts

; SETNAM with kc_name, SETBNK data bank 5 / name bank 0, SETLFS 1,8,0
kc_setup:
        lda #(STAGE >> 16)
        sta kc_a
        lda #0
        sta kc_x
        #KCALL KERNAL_SETBNK
        lda kc_name_len
        sta kc_a
        lda #<kc_name
        sta kc_x
        lda #>kc_name
        sta kc_y
        #KCALL KERNAL_SETNAM
        lda #1
        sta kc_a
        lda #8
        sta kc_x
        lda #0
        sta kc_y
        #KCALL KERNAL_SETLFS
        rts

; kc_load - LOAD to STAGE -> C set on error, t0 = bytes loaded
kc_load:
        jsr kc_setup
        lda #0
        sta kc_a
        lda #<STAGE
        sta kc_x
        lda #>STAGE
        sta kc_y
        #KCALL KERNAL_LOAD
        lda kc_p
        lsr
        bcs +
        sec
        lda kc_x
        sbc #<STAGE
        sta t0
        lda kc_y
        sbc #>STAGE
        sta t0+1
        clc
+       rts

disk_load:
        lda #0
        jsr make_kname
        jsr kc_load
        bcc +
        jmp disk_error
+       lda t0
        sta src_len
        lda t0+1
        sta src_len+1
        ora t0
        beq _done
        ; STAGE -> SRC
        lda #<STAGE
        sta fp0
        lda #>STAGE
        sta fp0+1
        lda #`STAGE
        sta fp0+2
        lda #0
        sta fp0+3
        lda #<SRC
        sta fp1
        lda #>SRC
        sta fp1+1
        lda #<(SRC >> 16)
        sta fp1+2
        lda #>(SRC >> 16)
        sta fp1+3
        jsr dma_copy
_done:  jsr src_terminate
        jsr src_clean
        lda src_len
        sta acc
        lda src_len+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_mark_t5
        jsr sb_int
        #SBPRINT " bytes loaded"
        lda t5
        ldx t5+1
        jsr sb_flush
        lda #10
        jmp putc

; src_clean - CR or CR LF line ends -> LF; tabs stay (the lexer handles them)
src_clean:
        lda #<SRC
        sta fp0
        lda #>SRC
        sta fp0+1
        lda #<(SRC >> 16)
        sta fp0+2
        lda #>(SRC >> 16)
        sta fp0+3
        lda src_len
        sta t1
        lda src_len+1
        sta t1+1
-       lda t1
        ora t1+1
        beq +
        ldz #0
        lda [fp0],z
        cmp #13
        bne _n
        lda #10                         ; CR -> LF; a following LF becomes a space
        sta [fp0],z
        inz
        lda [fp0],z
        cmp #10
        bne _n
        lda #' '
        sta [fp0],z
_n:     inw fp0
        dew t1
        bra -
+       rts

disk_save:
        ; SRC -> STAGE, then SAVE STAGE .. STAGE + len
        lda src_len
        ora src_len+1
        beq +
        lda #<SRC
        sta fp0
        lda #>SRC
        sta fp0+1
        lda #<(SRC >> 16)
        sta fp0+2
        lda #>(SRC >> 16)
        sta fp0+3
        lda #<STAGE
        sta fp1
        lda #>STAGE
        sta fp1+1
        lda #`STAGE
        sta fp1+2
        lda #0
        sta fp1+3
        lda src_len
        sta t0
        lda src_len+1
        sta t0+1
        jsr dma_copy
+       lda #1
        jsr make_kname
        jsr kc_setup
        lda #<STAGE                     ; the start pointer lives at $FB (page 0)
        sta $00fb
        lda #>STAGE
        sta $00fc
        lda #$fb
        sta kc_a
        clc
        lda #<STAGE
        adc src_len
        sta kc_x
        lda #>STAGE
        adc src_len+1
        sta kc_y
        #KCALL KERNAL_SAVE
        lda kc_p
        lsr
        bcc +
        jmp disk_error
+       #PRINT "saved"
        lda #10
        jmp putc

disk_error:
        lda #COL_ERROR
        sta scr_color
        #PRINT "disk error (file not found?)"
        lda #10
        jsr putc
        lda #COL_NORMAL
        sta scr_color
        rts

; disk_dir - LOAD "$" and print the listing (blocks and names). The listing is BASIC
; lines: link (2), number (2) = blocks, text, 0; a zero link ends it. Some DOS versions
; keep the load address ($0101) in front: skip it. Never read past the loaded bytes.
disk_dir:
        lda #'$'
        sta kc_name
        lda #1
        sta kc_name_len
        jsr kc_load
        bcc +
        jmp disk_error
+       clc                             ; dir_end = the end of the loaded data
        lda #<STAGE
        adc t0
        sta dir_end
        lda #>STAGE
        adc t0+1
        sta dir_end+1
        lda #<STAGE
        sta fp0
        lda #>STAGE
        sta fp0+1
        lda #`STAGE
        sta fp0+2
        lda #0
        sta fp0+3
        ; a load address in front? ($01 $01, then a link, then line number 0)
        ldz #0
        lda [fp0],z
        cmp #$01
        bne _nohdr
        inz
        lda [fp0],z
        cmp #$01
        bne _nohdr
        ldz #4
        lda [fp0],z
        inz
        ora [fp0],z
        bne _nohdr
        inw fp0
        inw fp0
_nohdr: inw fp0                         ; skip the first link
        inw fp0
_line:  jsr _left                       ; room for the line number?
        cmp #3
        bcc _end
        ldz #0
        lda [fp0],z
        sta acc
        inz
        lda [fp0],z
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_mark_t5
        jsr sb_int
        lda #' '
        jsr sb_putc
        lda t5
        ldx t5+1
        jsr sb_flush
        inw fp0
        inw fp0
-       jsr _left                       ; the text, up to its zero
        beq _nl
        ldz #0
        lda [fp0],z
        beq +
        jsr petscii_to_ascii
        cmp #$12                        ; reverse-on in the header
        beq _skip
        cmp #32
        bcc _skip
        jsr putc
_skip:  inw fp0
        bra -
+       inw fp0
        lda #10
        jsr putc
        jsr _left                       ; the next link: zero ends the listing
        cmp #2
        bcc _end
        ldz #0
        lda [fp0],z
        inz
        ora [fp0],z
        beq _end
        inw fp0
        inw fp0
        bra _line
_nl:    lda #10
        jsr putc
_end:   rts
; A = bytes left to read (255 when more than that), Z flag set when none
_left:  sec
        lda dir_end
        sbc fp0
        tax
        lda dir_end+1
        sbc fp0+1
        bcc _none
        bne _many
        txa
        rts
_many:  lda #255
        rts
_none:  lda #0
        rts
dir_end:        .word 0
