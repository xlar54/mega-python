;=======================================================================================
; Tail F (swapped in at TAIL by need_f): Python files - open(), read(), readline(),
; readlines(), write(), close(), with, for line in f.
;
; A file is a sequential (SEQ) file on drive 8, opened through the KERNAL as logical
; file 2-5 (secondary address = the same number). Bytes go through FNAMEBUF 255 at a
; time (kio in disk.asm runs the KERNAL loop); each open file has a 256-byte read
; buffer at FILEBUF + 256 * (lfn - 2). Text is kept as it is (ASCII); reading turns a
; CR, or CR LF, into '\n'.
;
; File object (T_FILE): +4 lfn, +5 mode ('r', 'w', 'a'), +6 flags, +8 buffer position,
; +9 buffer length, +10 name (a string).
;=======================================================================================
FF_CLOSED       = 1
FF_EOF          = 2                     ; the KERNAL has delivered the last byte
FF_CR           = 4                     ; the last byte read was a CR
FF_FREED        = 8                     ; its KERNAL file is closed (at close() or at
                                        ; the end of a file being read)

fl_lfn:         .byte 0
fl_mode:        .byte 0
fl_len:         .word 0

; open(name, mode='r')
xf_open:
        #NARGS 1, 2
        #ARG 0
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       lda #'r'
        sta fl_mode
        lda npos
        cmp #2
        bne _mode
        #ARG 1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       #ARG 1
        jsr str_info
        lda str_len
        beq _badmode
        ldz #0
        lda [fp0],z
        sta fl_mode
_mode:  lda fl_mode
        cmp #'r'
        beq +
        cmp #'w'
        beq +
        cmp #'a'
        beq +
_badmode:
        #RAISE EXC_VALUE, "mode must be 'r', 'w' or 'a'"
+       ; a free logical file
        ldx #2
-       lda f_bit,x
        and file_used
        beq +
        inx
        cpx #6
        bne -
        #RAISE EXC_OS, "too many open files (4 at most)"
+       stx fl_lfn
        ; the name: "name,s,<mode>" (and "@0:" in front to replace a file)
_name:  lda r2
        ldx r2+1
        jsr str_info
        lda str_len+1
        bne _badname
        lda str_len
        beq _badname
        cmp #17
        bcc +
_badname:
        #RAISE EXC_VALUE, "file names are 1 to 16 characters"
+       sta fname_len
        ldx #0
        ldz #0
-       lda [fp0],z
        sta FNAMEBUF,x
        inx
        inz
        cpx fname_len
        bne -
        ldx fname_len
        lda #','
        sta FNAMEBUF,x
        sta FNAMEBUF+2,x
        lda #'s'
        sta FNAMEBUF+1,x
        lda fl_mode
        sta FNAMEBUF+3,x
        inx
        inx
        inx
        inx
        stx fl_len
        lda fname_len
        pha
        stx fname_len
        lda #0
        ldx fl_mode
        cpx #'w'
        bne +
        lda #1
+       jsr make_kname
        pla
        sta fname_len
        ; open it, then ask the drive how that went
        lda fl_lfn
        jsr f_kopen
        jsr drive_status
        bcc _ok
        pha
        lda fl_lfn
        jsr f_kclose
        pla
        cmp #62
        bne _oserr
        lda fl_mode                     ; append to a missing file: create it
        cmp #'a'
        bne _nofile
        lda #'w'
        sta fl_mode
        jmp _name
_nofile:
        jsr sb_mark_t5
        #SBPRINT "No such file or directory: "
        lda r2
        ldx r2+1
        jsr obj_repr
        lda #EXC_FILENOTFOUND
        jmp raise_sb
_oserr: jsr sb_mark_t5                  ; the drive's message
        lda #<FNAMEBUF
        ldx #>FNAMEBUF
        jsr sb_puts
        lda #EXC_OS
        jmp raise_sb
_ok:    ldx fl_lfn
        lda f_bit,x
        tsb file_used
        lda #12
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_FILE
        jsr alloc
        ldz #4
        lda fl_lfn
        sta [p0],z
        inz
        lda fl_mode
        sta [p0],z
        ldz #10
        lda r2
        sta [p0],z
        inz
        lda r2+1
        sta [p0],z
        lda p0
        ldx p0+1
        rts
f_bit:  .byte 1, 2, 4, 8, 16, 32

; f_kopen - OPEN logical file A (secondary address A) on drive 8 with kc_name
f_kopen:
        pha
        lda #0                          ; data and name in bank 0
        sta kc_a
        sta kc_x
        #KCALL KERNAL_SETBNK
        lda kc_name_len
        sta kc_a
        lda #<kc_name
        sta kc_x
        lda #>kc_name
        sta kc_y
        #KCALL KERNAL_SETNAM
        pla
        sta kc_a
        sta kc_y
        lda #8
        sta kc_x
        #KCALL KERNAL_SETLFS
        #KCALL KERNAL_OPEN
        rts

; f_kclose - CLOSE logical file A
f_kclose:
        sta kc_a
        #KCALL KERNAL_CLOSE
        rts

; drive_status - read the command channel: the message (zero-terminated) in FNAMEBUF.
; C set if it is an error (code 20 and up), A = the code
drive_status:
        lda #0
        sta kc_name_len
        lda #15
        jsr f_kopen
        lda #15
        sta kio_lfn
        lda #0
        sta kio_dir
        lda #255
        sta kio_n
        #KCALL kio
        lda #15
        jsr f_kclose
        ldx kio_n                       ; zero-terminate it (without the CR)
        beq +
        lda FNAMEBUF-1,x
        cmp #13
        bne +
        dex
+       lda #0
        sta FNAMEBUF,x
        lda FNAMEBUF                    ; the two digits
        and #15
        sta fl_len
        asl a
        asl a
        adc fl_len
        asl a
        sta fl_len
        lda FNAMEBUF+1
        and #15
        clc
        adc fl_len
        cmp #20
        rts

;---------------------------------------------------------------------------------------
; reading
;---------------------------------------------------------------------------------------
; f_self - argument 0 (the file) -> r3, p3; ValueError if it is closed
f_self: #ARG 0
        sta r3
        stx r3+1
f_p3:   lda r3
        sta p3
        lda r3+1
        sta p3+1
        ldz #6
        lda [p3],z
        and #FF_CLOSED
        bne +
        rts
+       #RAISE EXC_VALUE, "I/O operation on closed file."

; f_need - the file in r3 must have been opened for reading (A = 'r') or writing
f_need: ldz #5
        cmp #'r'
        bne +
        cmp [p3],z
        bne _no
        rts
+       lda [p3],z
        cmp #'r'
        beq _no
        rts
_no:    #RAISE EXC_OS, "the file is not open in that mode"

; f_getc - the next byte of file r3 -> C clear, A; C set at the end
f_getc: jsr f_p3
        ldz #8
        lda [p3],z
        inz
        cmp [p3],z
        bne _byte
        ldz #6                          ; the buffer is empty: refill it
        lda [p3],z
        and #FF_EOF
        beq +
        jsr f_release                   ; all read: give the KERNAL file back
        sec
        rts
+       ldz #4
        lda [p3],z
        sta kio_lfn
        lda #0
        sta kio_dir
        lda #255
        sta kio_n
        #KCALL kio
        jsr f_p3
        jsr f_buf
        ldx #0                          ; FNAMEBUF -> the file's buffer
        ldz #0
-       cpx kio_n
        beq +
        lda FNAMEBUF,x
        sta [fp2],z
        inx
        inz
        bra -
+       ldz #8
        lda #0
        sta [p3],z
        inz
        lda kio_n
        sta [p3],z
        lda kio_st
        beq +
        ldz #6
        lda [p3],z
        ora #FF_EOF
        sta [p3],z
+       lda kio_n
        bne _byte
        sec
        rts
_byte:  jsr f_buf
        ldz #8
        lda [p3],z
        inc a
        sta [p3],z
        dec a
        taz
        lda [fp2],z
        clc
        rts

; f_buf - fp2 = the read buffer of file p3
f_buf:  ldz #4
        lda [p3],z
        sec
        sbc #2
        clc
        adc #>(FILEBUF & $ffff)
        sta fp2+1
        lda #0
        sta fp2
        sta fp2+3
        lda #`FILEBUF
        sta fp2+2
        rts

; f_getch - f_getc with CR and CR LF read as '\n'
f_getch:
        jsr f_getc
        bcs _end
        cmp #13
        beq _cr
        pha
        ldz #6
        lda [p3],z
        and #FF_CR
        beq +
        lda [p3],z                      ; the LF of a CR LF: skip it
        and #$ff ^ FF_CR
        sta [p3],z
        pla
        cmp #10
        beq f_getch
        clc
        rts
+       pla
        clc
_end:   rts
_cr:    ldz #6
        lda [p3],z
        ora #FF_CR
        sta [p3],z
        lda #10
        clc
        rts

; f_line - append the next line of file r3 (with its '\n') to the string builder
f_line: jsr f_getch
        bcs +
        jsr sb_putc
        cmp #10
        bne f_line
+       rts

; read([n])
xf_read:
        #NARGS 1, 2
        jsr f_self
        lda #'r'
        jsr f_need
        lda #$ff
        sta fl_len
        sta fl_len+1
        lda npos
        cmp #2
        bne +
        #ARG 1
        jsr need_int
        bit acc+3
        bmi +
        lda acc
        sta fl_len
        lda acc+1
        sta fl_len+1
+       lda sbp
        pha
        lda sbp+1
        pha
-       lda fl_len
        ora fl_len+1
        beq +
        jsr f_getch
        bcs +
        jsr sb_putc
        lda fl_len
        bne _dec
        dec fl_len+1
_dec:   dec fl_len
        bra -
+       plx
        pla
        jmp sb_take

; readline()
xf_readline:
        #NARGS 1, 1
        jsr f_self
xf_next:                                ; (the next line of file r3, for iteration)
        lda #'r'
        jsr f_need
        lda sbp
        pha
        lda sbp+1
        pha
        jsr f_line
        plx
        pla
        jmp sb_take

; readlines()
xf_readlines:
        #NARGS 1, 1
        jsr f_self
        lda #'r'
        jsr f_need
        lda #0
        sta nitems
        sta nitems+1
        jsr list_new
        sta r0
        stx r0+1
-       lda sbp
        pha
        lda sbp+1
        pha
        jsr f_line
        plx
        pla
        jsr sb_take
        sta r1
        stx r1+1
        jsr str_info
        lda str_len
        ora str_len+1
        beq +
        lda r3                          ; (list_append uses r3)
        pha
        lda r3+1
        pha
        jsr list_append
        pla
        sta r3+1
        pla
        sta r3
        bra -
+       lda #0
        sta r1
        sta r1+1
        lda r0
        ldx r0+1
        rts

;---------------------------------------------------------------------------------------
; write(s) -> the number of characters
;---------------------------------------------------------------------------------------
xf_write:
        #NARGS 2, 2
        jsr f_self
        lda #'w'
        jsr f_need
        #ARG 1
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_STR
        beq +
        jmp raise_need_str
+       lda r2
        ldx r2+1
        jsr str_info
        lda str_len
        sta fl_len
        sta acc
        lda str_len+1
        sta fl_len+1
        sta acc+1
_chunk: lda fl_len                      ; up to 255 bytes at a time
        ora fl_len+1
        beq _done
        ldx #255
        lda fl_len+1
        bne +
        ldx fl_len
+       stx kio_n
        ldx #0
        ldz #0
-       lda [fp0],z
        sta FNAMEBUF,x
        inz
        inx
        cpx kio_n
        bne -
        sec
        lda fl_len
        sbc kio_n
        sta fl_len
        bcs +
        dec fl_len+1
+       clc
        lda fp0
        adc kio_n
        sta fp0
        bcc +
        inc fp0+1
+       lda fp0                         ; (kernal_call keeps fp0)
        pha
        lda fp0+1
        pha
        jsr f_p3
        ldz #4
        lda [p3],z
        sta kio_lfn
        lda #1
        sta kio_dir
        #KCALL kio
        pla
        sta fp0+1
        pla
        sta fp0
        lda kio_st
        and #$83                        ; time-out or no device
        beq _chunk
        #RAISE EXC_OS, "write error"
_done:  lda #0
        sta acc+2
        sta acc+3
        jmp int_new

;---------------------------------------------------------------------------------------
; close(), __enter__(), __exit__(...)
;---------------------------------------------------------------------------------------
xf_close:
        #NARGS 1, 1
f_close_self:
        #ARG 0
        sta p3
        stx p3+1
        ldz #6
        lda [p3],z
        and #FF_CLOSED
        bne +
        lda [p3],z
        ora #FF_CLOSED
        sta [p3],z
        jsr f_release
+       lda #R_NONE
        ldx #0
        rts

; f_release - close the KERNAL file of file p3 (once)
f_release:
        ldz #6
        lda [p3],z
        and #FF_FREED
        bne +
        lda [p3],z
        ora #FF_FREED
        sta [p3],z
        ldz #4
        lda [p3],z
        tax
        lda f_bit,x
        trb file_used
        txa
        jmp f_kclose
+       rts
xf_exit:
        #NARGS 1, 4
        jmp f_close_self
xf_enter:
        #NARGS 1, 1
        #ARG 0
        rts

; xf_iter_next - A/X = file -> C clear, A/X = its next line; C set at the end
xf_iter_next:
        sta r3
        stx r3+1
        jsr f_p3
        jsr xf_next
        sta r1
        stx r1+1
        jsr str_info
        lda str_len
        ora str_len+1
        bne +
        sec
        rts
+       lda r1
        ldx r1+1
        clc
        rts

; xf_repr - append <TextIOWrapper name='x' mode='r'> for the file A/X
xf_repr:
        sta p3
        stx p3+1
        ldz #5
        lda [p3],z
        pha                             ; the mode
        #SBPRINT "<TextIOWrapper name="
        ldz #11
        lda [p3],z
        tax
        dez
        lda [p3],z
        jsr obj_repr
        #SBPRINT " mode='"
        pla
        jsr sb_putc
        #SBPRINT "'>"
        rts

; xf_reset - close every open file (a fresh interpreter: run(), new())
xf_reset:
        ldx #2
-       lda f_bit,x
        and file_used
        beq +
        phx
        txa
        jsr f_kclose
        plx
+       inx
        cpx #6
        bne -
        lda #0
        sta file_used
        rts
