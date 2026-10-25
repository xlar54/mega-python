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


;---------------------------------------------------------------------------------------
; kio - Python files: runs inside the KERNAL (kernal_call with kc_addr = kio). Moves up
; to kio_n bytes (1-255) between logical file kio_lfn and FNAMEBUF: kio_dir 0 = read,
; 1 = write. -> kio_n = bytes moved, kio_st = READST ($40 = end of file; $ff = the
; channel would not open)
;---------------------------------------------------------------------------------------
KERNAL_CHKOUT           = $FFC9
KERNAL_CHROUT           = $FFD2
kio_lfn:        .byte 0
kio_dir:        .byte 0
kio_n:          .byte 0
kio_st:         .byte 0
file_used:      .byte 0                 ; logical files 2-5 in use (bits 2-5)
kio:    ldx kio_lfn
        ldy #0
        lda kio_dir
        bne _w
        jsr KERNAL_CHKIN
        bcs _err
-       jsr KERNAL_CHRIN
        sta FNAMEBUF,y
        iny
        jsr KERNAL_READST
        bne _end
        cpy kio_n
        bne -
        bra _end
_w:     jsr KERNAL_CHKOUT
        bcs _err
-       lda FNAMEBUF,y
        jsr KERNAL_CHROUT
        iny
        jsr KERNAL_READST
        bne _end
        cpy kio_n
        bne -
_end:   sta kio_st
        sty kio_n
        jmp KERNAL_CLRCHN
_err:   lda #$ff
        bra _end
