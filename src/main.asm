;=======================================================================================
; MEGA65 Python - a Python 3 subset interpreter for the MEGA65, in 45GS02 assembly.
;
; Boot: set up the machine (40 MHz, base page $16, 16-bit stack, interrupts off), put
; the code pieces in place, unmap the ROMs, build the interpreter state (symbols,
; builtins, exception classes), then the REPL. The KERNAL stays available for disk
; I/O through kernal_call (see disk.asm).
;
; Built in two passes (-D PASS=1 / 2) that assemble the same code, so the labels agree:
;   pass 1 -> the program mega-python:
;     $2001-$7FFF  resident part 1 (resident.asm)
;     $8000-$CFFF  overlay R, loaded straight into the window
;     $D000-       resident part 2, assembled for $F000 (moved there at boot)
;   pass 2 -> the file mpy-ovl: overlay C (lexer, compiler, editor), assembled for the
;     window, loaded at boot and kept in attic
; Whatever a pass does not output is assembled in a .virtual block.
;=======================================================================================
        .cpu "45gs02"
        .dpage $1600

        .include "platform.asm"
        .include "zp.asm"

; (every section is spelled out in both branches: 64tass macros or segments would
; substitute the rguments of the macros the included files define)
        .if PASS == 1
        * = $2001
        .include "resident.asm"
part1_end:
        .cerror * > WINDOW, "resident part 1 overflows into the overlay window"
        * = WINDOW
ovl_r_start:
        .include "builtins.asm"
        .include "methods.asm"
        .include "modules.asm"
        .include "gen/tables.asm"
ovl_r_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay R is too big"
        * = PART2_LOAD
        .logical PART2
part2_start:
        .include "seq.asm"
part2_end:
        .cerror * > PART2_END, "resident part 2 overflows into the reserved 0.FF00 page"
        .endlogical
        .virtual WINDOW
ovl_c_start:
        .include "lexer.asm"
        .include "compiler.asm"
        .include "editor.asm"
ovl_c_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay C is too big"
        .endv
        .else
        .virtual $2001
        .include "resident.asm"
part1_end:
        .cerror * > WINDOW, "resident part 1 overflows into the overlay window"
        .endv
        .virtual WINDOW
ovl_r_start:
        .include "builtins.asm"
        .include "methods.asm"
        .include "modules.asm"
        .include "gen/tables.asm"
ovl_r_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay R is too big"
        .endv
        .virtual PART2
part2_start:
        .include "seq.asm"
part2_end:
        .cerror * > PART2_END, "resident part 2 overflows into the reserved 0.FF00 page"
        .endv
        * = $1000
        .logical WINDOW
ovl_c_start:
        .include "lexer.asm"
        .include "compiler.asm"
        .include "editor.asm"
ovl_c_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay C is too big"
        .endlogical
        .endif

part2_len = part2_end - part2_start
        .cerror PART2_LOAD + part2_len > $e000, "part 2's load image is too big"

        .if PASS == 1
        .warn format("part 1 $%04x, overlay R $%04x, part 2 $%04x, overlay C $%04x bytes", part1_end - $2001, ovl_r_end - ovl_r_start, part2_len, ovl_c_end - ovl_c_start)
        .endif
