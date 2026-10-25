;=======================================================================================
; MEGA65 Python - a Python 3 subset interpreter for the MEGA65, in 45GS02 assembly.
;
; Boot: set up the machine (40 MHz, base page $16, 16-bit stack, interrupts off), put
; the code pieces in place (part 2, the overlays in attic), unmap the ROMs, build the
; interpreter state (symbols, builtins, exception classes), then the REPL.
; The KERNAL stays available for disk I/O through kernal_call (see disk.asm).
;
; The build image (tools/split.py cuts it into two files):
;   $2001-$7FFF   resident part 1           } the program file mega-python
;   $8000-$BFFF   overlay R (in the window) }
;   $C000-        resident part 2 (assembled for $E800), then overlay C (assembled for
;                 $8000): the file mpy-ovl, loaded at boot and moved into place
;=======================================================================================
        .cpu "45gs02"
        .dpage $1600

        .include "platform.asm"
        .include "zp.asm"

        * = $2001                       ; BASIC stub: BANK 0 : SYS 8210
        .word (+), 2026
        .byte $fe, $02, $30
        .byte ':'
        .byte $9e
        .text "8210"
        .byte 0
+       .word 0

        * = $2012
entry:
        cld
        sei
        lda #BP_PAGE                    ; base page = $16xx before touching variables
        tab
        ; 16-bit stack at CPUSTACK
        ldy #>CPUSTACK_TOP
        tys
        ldx #<CPUSTACK_TOP
        txs
        cle
        lda #65                         ; 40 MHz
        sta $00
        lda #<LOG                       ; the output transcript (attic)
        sta log_fp
        lda #>LOG
        sta log_fp+1
        lda #<(LOG >> 16)
        sta log_fp+2
        lda #>(LOG >> 16)
        sta log_fp+3
        lda $0001                       ; the boot banking, for KERNAL calls
        sta boot_01
        lda VIC3_ROMBANK
        sta boot_d030
        jsr scr_init
        jsr kernal_init
        jsr load_pieces
        jsr boot_pieces
        jsr map_running
        jsr mem_test
        jsr py_reset
        lda #COL_INFO
        sta scr_color
        lda #<banner
        ldx #>banner
        jsr puts
        lda #COL_NORMAL
        sta scr_color
        jmp repl_start

banner: .text "MEGA65 Python 0.1 (a Python 3.15 subset)", 10
        .text "Type help() for the commands, edit() for the editor.", 10, 0

boot_01:        .byte 0
boot_d030:      .byte 0
ovl_cur:        .byte 0                 ; the overlay in the window: 0 = R, 1 = C

; boot_pieces - resident part 2 (from the loaded mpy-ovl) to $E800, overlay R (in the
; window) to attic
boot_pieces:
        lda #<STAGE
        sta fp0
        lda #>STAGE
        sta fp0+1
        lda #`STAGE
        sta fp0+2
        lda #0
        sta fp0+3
        lda #<PART2
        sta fp1
        lda #>PART2
        sta fp1+1
        lda #0
        sta fp1+2
        sta fp1+3
        lda #<part2_len
        sta t0
        lda #>part2_len
        sta t0+1
        jsr dma_copy
        lda #<WINDOW
        sta fp0
        lda #>WINDOW
        sta fp0+1
        lda #0
        sta fp0+2
        sta fp0+3
        lda #<OVL_R_ATTIC
        sta fp1
        lda #>OVL_R_ATTIC
        sta fp1+1
        lda #<(OVL_R_ATTIC >> 16)
        sta fp1+2
        lda #>(OVL_R_ATTIC >> 16)
        sta fp1+3
        lda #<WINDOW_SIZE
        sta t0
        lda #>WINDOW_SIZE
        sta t0+1
        jsr dma_copy
        lda #0
        sta ovl_cur
        rts

; load_pieces - the file mpy-ovl to STAGE: part 2, then overlay C (-> attic)
load_pieces:
        ldx #0
-       lda ovl_name,x
        sta FNAMEBUF,x
        inx
        cpx #ovl_name_len
        bne -
        stx fname_len
        lda #0
        jsr make_kname
        jsr kc_load
        bcc +
        #PRINT "cannot load mpy-ovl"
-       bra -
+       lda #<(STAGE + OVL_C_LOAD - PART2_LOAD)
        sta fp0
        lda #>(STAGE + OVL_C_LOAD - PART2_LOAD)
        sta fp0+1
        lda #`STAGE
        sta fp0+2
        lda #0
        sta fp0+3
        lda #<OVL_C_ATTIC
        sta fp1
        lda #>OVL_C_ATTIC
        sta fp1+1
        lda #<(OVL_C_ATTIC >> 16)
        sta fp1+2
        lda #>(OVL_C_ATTIC >> 16)
        sta fp1+3
        lda #<WINDOW_SIZE
        sta t0
        lda #>WINDOW_SIZE
        sta t0+1
        jmp dma_copy
ovl_name:       .text "mpy-ovl"
ovl_name_len = * - ovl_name

; map_running - no MAP, no ROMs: RAM everywhere but I/O at $D000
map_running:
        lda #0
        tax
        tay
        taz
        map
        eom
        lda #$35
        sta $0001
        lda boot_d030
        and #%00000111
        sta VIC3_ROMBANK
        ; vectors in RAM: NMI and IRQ just return (interrupts stay off)
        lda #<nmi_rti
        sta $fffa
        sta $fffe
        lda #>nmi_rti
        sta $fffb
        sta $ffff
        rts
nmi_rti:
        rti

; map_kernal - the boot (SYS) state: KERNAL at $E000, ROM banking as at boot
map_kernal:
        lda boot_01
        sta $0001
        lda boot_d030
        sta VIC3_ROMBANK
        lda #0
        tax
        tay
        ldz #$83                        ; MAPHI: $E000-$FFFF from $30000
        map
        eom
        rts

; ovl_runtime / ovl_compiler - put overlay R / C in the window
ovl_runtime:
        lda ovl_cur
        bne +
        rts
+       lda #0
        sta ovl_cur
        lda #<OVL_R_ATTIC
        sta fp0
        lda #>OVL_R_ATTIC
        sta fp0+1
        lda #<(OVL_R_ATTIC >> 16)
        sta fp0+2
        lda #>(OVL_R_ATTIC >> 16)
        sta fp0+3
        bra ovl_load
ovl_compiler:
        lda ovl_cur
        beq +
        rts
+       lda #1
        sta ovl_cur
        lda #<OVL_C_ATTIC
        sta fp0
        lda #>OVL_C_ATTIC
        sta fp0+1
        lda #<(OVL_C_ATTIC >> 16)
        sta fp0+2
        lda #>(OVL_C_ATTIC >> 16)
        sta fp0+3
ovl_load:
        lda #<WINDOW
        sta fp1
        lda #>WINDOW
        sta fp1+1
        lda #0
        sta fp1+2
        sta fp1+3
        lda #<WINDOW_SIZE
        sta t0
        lda #>WINDOW_SIZE
        sta t0+1
        jmp dma_copy

; compile - compile_source with the compiler overlay in the window
compile:
        jsr ovl_compiler
        jsr compile_source
        pha
        phx
        jsr ovl_runtime
        plx
        pla
        rts

; mem_test - the RAM the interpreter uses above $8000 must really be RAM
mem_test:
        ldx #0
-       lda mt_addr_lo,x
        sta t0
        lda mt_addr_hi,x
        sta t0+1
        ldy #0
        lda #$a5
        sta (t0),y
        lda (t0),y
        cmp #$a5
        bne _bad
        inx
        cpx #3
        bne -
        rts
_bad:   #PRINT "RAM above $C000 is not writable"
-       bra -
mt_addr_lo:     .byte <VSTACK, <FSTACK, <$fff0
mt_addr_hi:     .byte >VSTACK, >FSTACK, >$fff0

;---------------------------------------------------------------------------------------
; py_reset - a fresh interpreter: empty heap, symbols, globals and code
;---------------------------------------------------------------------------------------
py_reset:
        jsr heap_init
        jsr sb_reset
        jsr vm_reset
        ; zero the symbol tables: hash buckets (attic) and globals (bank 1)
        lda #<SYM_HASH
        sta fp1
        lda #>SYM_HASH
        sta fp1+1
        lda #<(SYM_HASH >> 16)
        sta fp1+2
        lda #>(SYM_HASH >> 16)
        sta fp1+3
        lda #<512
        sta t0
        lda #>512
        sta t0+1
        lda #0
        jsr dma_fill
        lda #<SYM_VAL
        sta fp1
        lda #>SYM_VAL
        sta fp1+1
        lda #`SYM_VAL
        sta fp1+2
        lda #0
        sta fp1+3
        lda #<(2*MAXSYMS)
        sta t0
        lda #>(2*MAXSYMS)
        sta t0+1
        lda #0
        jsr dma_fill
        lda #0
        sta nsyms
        sta nsyms+1
        ldx #0
-       sta char_cache,x
        inx
        bne -
        ; the code area
        lda #<CODE_START
        sta cp
        lda #>CODE_START
        sta cp+1
        lda #CODE_BANK
        sta cp+2
        lda #0
        sta cp+3
        lda #<(LINETAB & $ffff)
        sta linetab_end
        lda #>(LINETAB & $ffff)
        sta linetab_end+1
        ; the fixed symbols, in order
        lda #F_PERM
        sta al_perm
        lda #<sym_init_names
        sta t6
        lda #>sym_init_names
        sta t6+1
-       ldy #0
        lda (t6),y
        beq +
        lda t6
        ldx t6+1
        jsr intern_cstr
        ldy #0
-       lda (t6),y
        iny
        cmp #0
        bne -
        tya
        clc
        adc t6
        sta t6
        bcc --
        inc t6+1
        bra --
+       lda #0
        sta al_perm
        jsr exc_init
        jsr builtins_init
        rts

;---------------------------------------------------------------------------------------
; the REPL
;---------------------------------------------------------------------------------------
REQ_NONE        = 0
REQ_RUN         = 1
REQ_EDIT        = 2
REQ_NEW         = 3
REQ_LOAD        = 4
REQ_SAVE        = 5
REQ_FILES       = 6

repl_req:       .byte 0
repl_sp:        .word 0
repl_code:      .word 0                 ; where the current REPL input's code starts
repl_lt:        .word 0

repl_start:
repl_restart:
        ldy #>CPUSTACK_TOP
        tys
        ldx #<CPUSTACK_TOP
        txs
        tsx
        stx err_sp
        tsy
        sty err_sp+1
        lda #<repl_error
        sta err_vec
        lda #>repl_error
        sta err_vec+1
        jsr vm_reset_stacks
repl_loop:
        jsr sb_reset
        jsr scr_fresh_line
        lda #COL_PROMPT
        sta scr_color
        #PRINT ">>> "
        lda #COL_NORMAL
        sta scr_color
        lda #0
        sta rl_len
        jsr rl_read
        bcc +
        jsr print_interrupt
        bra repl_loop
+       lda rl_len
        beq repl_loop
        ; collect the input in REPLBUF
        lda #<REPLBUF
        sta rp
        lda #>REPLBUF
        sta rp+1
        lda #<(REPLBUF >> 16)
        sta rp+2
        lda #>(REPLBUF >> 16)
        sta rp+3
        jsr repl_append
        jsr needs_more
        bcc _go
_more:  ; continuation lines until an empty one
        lda #COL_PROMPT
        sta scr_color
        #PRINT "... "
        lda #COL_NORMAL
        sta scr_color
        lda #0                          ; no auto-indent: pasted code keeps its own
        sta rl_len
        jsr rl_read
        bcc +
        jsr print_interrupt
        jmp repl_loop
+       jsr line_blank
        bcs _go
        jsr repl_append
        bra _more
_go:    ldz #0
        lda #0
        sta [rp],z
        ; compile and run it
        lda #1
        sta c_repl
        lda cp
        sta repl_code
        lda cp+1
        sta repl_code+1
        lda linetab_end
        sta repl_lt
        lda linetab_end+1
        sta repl_lt+1
        lda #0
        sta c_made_func
        lda #<REPLBUF
        sta lx_ptr
        lda #>REPLBUF
        sta lx_ptr+1
        lda #<(REPLBUF >> 16)
        sta lx_ptr+2
        lda #>(REPLBUF >> 16)
        sta lx_ptr+3
        jsr compile
        jsr vm_run
        bcc +
        jsr report_exception
+       jsr reclaim_repl_code
        jmp repl_loop

; reclaim_repl_code - drop the REPL input's code unless it defined a function/class
reclaim_repl_code:
        lda c_made_func
        bne +
        lda repl_code
        sta cp
        lda repl_code+1
        sta cp+1
        lda repl_lt
        sta linetab_end
        lda repl_lt+1
        sta linetab_end+1
+       rts

; compile errors arrive here (throw with the REPL's error context)
repl_error:
        jsr ovl_runtime
        jsr report_exception
        jsr reclaim_repl_code
        jsr vm_reset_stacks
        jmp repl_loop

; report_exception - print cur_exc (quietly for SystemExit)
report_exception:
        lda cur_exc
        ldx cur_exc+1
        sta r2
        stx r2+1
        lda #EXC_SYSEXIT
        jsr exc_is
        bcs +
        jsr print_exception
+       lda #0
        sta cur_exc
        sta cur_exc+1
        jsr vm_reset_stacks
        jmp clear_rregs

print_interrupt:
        lda #COL_ERROR
        sta scr_color
        #PRINT "KeyboardInterrupt"
        lda #10
        jsr putc
        lda #COL_NORMAL
        sta scr_color
        rts

; vm_reset_stacks - empty the value, frame and handler stacks
vm_reset_stacks:
        lda #<VSTACK_END
        sta vsp
        sta vfp
        lda #>VSTACK_END
        sta vsp+1
        sta vfp+1
        lda #<FSTACK
        sta frp
        lda #>FSTACK
        sta frp+1
        lda #<HSTACK
        sta hsp
        lda #>HSTACK
        sta hsp+1
        lda #0
        sta runlev
        sta exc_ip_set
        sta al_perm
        rts

; repl_append - LINEBUF (rl_len chars) + newline -> rp
repl_append:
        ldx #0
        ldz #0
-       cpx rl_len
        bcs +
        lda LINEBUF,x
        sta [rp],z
        inw rp
        inx
        bra -
+       lda #10
        sta [rp],z
        inw rp
        rts

; needs_more - C set if LINEBUF starts a block (ends with ':' ignoring spaces and a
; comment, or has unclosed brackets, or ends with a backslash)
needs_more:
        ldx #0
        ldy #0                          ; bracket depth
        lda #0
        sta t0                          ; last non-space char
        sta t1                          ; inside a string quote char
-       cpx rl_len
        bcs _end
        lda LINEBUF,x
        ldz t1
        beq _nostr
        cmp t1
        bne +
        lda #0
        sta t1
+       inx
        bra -
_nostr: cmp #'#'
        beq _end
        cmp #"'"
        beq _q
        cmp #'"'
        beq _q
        cmp #'('
        beq _open
        cmp #'['
        beq _open
        cmp #'{'
        beq _open
        cmp #')'
        beq _close
        cmp #']'
        beq _close
        cmp #'}'
        beq _close
        bra _ch
_q:     sta t1
        bra _ch
_open:  iny
        bra _ch
_close: dey
_ch:    cmp #' '
        beq +
        sta t0
+       inx
        bra -
_end:   cpy #0
        beq +
        bmi +
        sec
        rts
+       lda t0
        cmp #':'
        beq +
        cmp #'\'
        beq +
        clc
        rts
+       sec
        rts

; line_blank - C set if LINEBUF is empty or only spaces
line_blank:
        ldx #0
-       cpx rl_len
        bcs +
        lda LINEBUF,x
        inx
        cmp #' '
        beq -
        clc
        rts
+       sec
        rts

;---------------------------------------------------------------------------------------
; requests from run(), edit(), new(), load(), save(), files(): leave the VM and do
; them at the REPL level
;---------------------------------------------------------------------------------------
repl_request:
        sta repl_req
        ldy #>CPUSTACK_TOP
        tys
        ldx #<CPUSTACK_TOP
        txs
        lda #<repl_error
        sta err_vec
        lda #>repl_error
        sta err_vec+1
        tsx
        stx err_sp
        tsy
        sty err_sp+1
        jsr vm_reset_stacks
        jsr reclaim_repl_code
        lda repl_req
        cmp #REQ_RUN
        bne _edit
        jsr do_run
        jmp repl_loop
_edit:  cmp #REQ_EDIT
        bne _new
        jsr ovl_compiler
        jsr editor
        php
        jsr ovl_runtime
        plp
        bcc _done
        jsr do_run                      ; F5 in the editor
        jmp repl_loop
_new:   cmp #REQ_NEW
        bne _load
        lda #0
        sta src_len
        sta src_len+1
        sta ed_cur
        sta ed_cur+1
        jsr src_terminate
        jsr py_reset
        jmp repl_loop
_load:  cmp #REQ_LOAD
        bne _save
        jsr disk_load
        lda #0
        sta ed_cur
        sta ed_cur+1
        jmp repl_loop
_save:  cmp #REQ_SAVE
        bne _files
        jsr disk_save
        jmp repl_loop
_files: cmp #REQ_FILES
        bne _done
        jsr disk_dir
_done:  jmp repl_loop

; do_run - a fresh interpreter, then compile and run the program in SRC
do_run:
        jsr py_reset
        jsr vm_reset_stacks
        lda #0
        sta c_repl
        jsr src_terminate
        lda #<SRC
        sta lx_ptr
        lda #>SRC
        sta lx_ptr+1
        lda #<(SRC >> 16)
        sta lx_ptr+2
        lda #>(SRC >> 16)
        sta lx_ptr+3
        jsr compile
        jsr vm_run
        bcc +
        jsr report_exception
+       lda cp                          ; the program's code stays (its functions)
        sta repl_code
        lda cp+1
        sta repl_code+1
        lda linetab_end
        sta repl_lt
        lda linetab_end+1
        sta repl_lt+1
        rts

; src_terminate - a zero after the program text
src_terminate:
        clc
        lda #<SRC
        adc src_len
        sta fp0
        lda #>SRC
        adc src_len+1
        sta fp0+1
        lda #<(SRC >> 16)
        sta fp0+2
        lda #>(SRC >> 16)
        sta fp0+3
        ldz #0
        lda #0
        sta [fp0],z
        rts

; variables shared with the overlays (they must not live in an overlay: the window
; is reloaded from the pristine image on every switch)
c_made_func:    .byte 0
c_repl:         .byte 0                 ; 1: the compiler prints expression statements
linetab_end:    .word LINETAB & $ffff
fname_len:      .byte 0
builtin_refs:   .fill 2*NBUILTINS

        .include "dma.asm"
        .include "disk.asm"
        .include "screen.asm"
        .include "keyboard.asm"
        .include "heap.asm"
        .include "obj.asm"
        .include "errors.asm"
        .include "opcodes.asm"
        .include "vm.asm"
        .include "arith.asm"
        .include "classes.asm"
part1_end:
        .cerror * > WINDOW, "resident part 1 overflows into the overlay window"

;---------------------------------------------------------------------------------------
; overlay R: the builtins (runs in the window; also its initial contents at load)
;---------------------------------------------------------------------------------------
        * = WINDOW
ovl_r_start:
        .include "builtins.asm"
        .include "methods.asm"
        .include "modules.asm"
        .include "gen/tables.asm"
ovl_r_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay R is too big"

;---------------------------------------------------------------------------------------
; resident part 2: loaded at $C000, runs at $E800
;---------------------------------------------------------------------------------------
        * = PART2_LOAD
        .logical PART2
part2_start:
        .include "seq.asm"
part2_end:
        .cerror * > $fffa, "resident part 2 overflows the vectors"
        .endlogical
part2_len = part2_end - part2_start
OVL_C_LOAD = (PART2_LOAD + part2_len + $ff) & $ff00

;---------------------------------------------------------------------------------------
; overlay C: lexer, compiler, editor (the file mpy-ovl)
;---------------------------------------------------------------------------------------
        * = OVL_C_LOAD
        .logical WINDOW
ovl_c_start:
        .include "lexer.asm"
        .include "compiler.asm"
        .include "editor.asm"
ovl_c_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay C is too big"
        .endlogical

        .warn format("part 1 $%04x, overlay R $%04x, part 2 $%04x, overlay C $%04x bytes", part1_end - $2001, ovl_r_end - ovl_r_start, part2_len, ovl_c_end - ovl_c_start)

