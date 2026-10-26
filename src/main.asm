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
        .cerror * > USERCODE, "resident part 1 overflows into the user's machine code area"
        * = WINDOW
ovl_r_start:
        .include "builtins.asm"
        .include "methods.asm"
        .include "setsr.asm"
        .include "classes.asm"
        .include "env.asm"
        .include "desc.asm"
        .include "modules.asm"
        .include "fmath.asm"
        .include "float.asm"
        .include "gen/tables.asm"
r_main_end:
        .cerror * > TAIL, "overlay R runs into the tail"
        * = TAIL
        .include "fdtoa.asm"
        .include "floata.asm"
        .include "fbig.asm"                ; (also in overlay C, for the lexer)
ovl_r_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay R is too big"
        .virtual TAIL
tail_b_start:
        .include "ftrans.asm"
        .include "floatb.asm"
        .include "gen/fconst.asm"
tail_b_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail B is too big"
        .endv
        .virtual TAIL
tail_h_start:
        .include "tailh.asm"
tail_h_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail H is too big"
        .endv
        .virtual TAIL
tail_f_start:
        .include "file.asm"
tail_f_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail F is too big"
        .endv
        .virtual TAIL
tail_s_start:
        .include "strmeth.asm"
tail_s_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail S is too big"
        .endv
        .virtual TAIL
tail_p_start:
        .include "fmtsort.asm"
tail_p_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail P is too big"
        .endv
        .virtual TAIL
tail_i_start:
        .include "taili.asm"
tail_i_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail I is too big"
        .endv
        .virtual TAIL
tail_x_start:
        .include "args.asm"
tail_x_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail X is too big"
        .endv
        .virtual TAIL
tail_t_start:
        .include "sets.asm"
        .include "listslice.asm"
        .include "introsp.asm"
tail_t_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail T is too big"
        .endv
        .virtual TAIL
tail_m_start:
        .include "classm.asm"
        .include "bytes.asm"
tail_m_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail M is too big"
        .endv
        .virtual TAIL
tail_n_start:
        .include "bigint.asm"
tail_n_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail N is too big"
        .endv
        .virtual TAIL
tail_o_start:
        .include "strpos.asm"
tail_o_end:
        .cerror * > WINDOW + WINDOW_SIZE, "tail O is too big"
        .endv
        * = PART2_LOAD
        .logical PART2
part2_start:
        .include "seq.asm"
        .include "tailcall.asm"
part2_end:
        .cerror * > PART2_END, "resident part 2 overflows into the reserved 0.FF00 page"
        .endlogical
        .virtual WINDOW
ovl_c_start:
        .include "lexer.asm"
        .include "compiler.asm"
        .include "editor.asm"
c_fbig  .block                          ; the lexer's copy of fbig.asm (tail A has the
        .include "fbig.asm"                ; runtime's; C cannot reach a tail)
        .bend
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
        .include "setsr.asm"
        .include "classes.asm"
        .include "env.asm"
        .include "desc.asm"
        .include "modules.asm"
        .include "fmath.asm"
        .include "float.asm"
        .include "gen/tables.asm"
r_main_end:
        .cerror * > TAIL, "overlay R runs into the tail"
        * = TAIL
        .include "fdtoa.asm"
        .include "floata.asm"
        .include "fbig.asm"                ; (also in overlay C, for the lexer)
ovl_r_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay R is too big"
        .endv
        .virtual PART2
part2_start:
        .include "seq.asm"
        .include "tailcall.asm"
part2_end:
        .cerror * > PART2_END, "resident part 2 overflows into the reserved 0.FF00 page"
        .endv
        * = 0                           ; (pass 2's image: overlay C and 11 tails in 64 KB)
        .logical WINDOW
ovl_c_start:
        .include "lexer.asm"
        .include "compiler.asm"
        .include "editor.asm"
c_fbig  .block                          ; the lexer's copy of fbig.asm (tail A has the
        .include "fbig.asm"                ; runtime's; C cannot reach a tail)
        .bend
ovl_c_end:
        .cerror * > WINDOW + WINDOW_SIZE, "overlay C is too big"
        .endlogical
        * = WINDOW_SIZE
        .logical TAIL
tail_b_start:
        .include "ftrans.asm"
        .include "floatb.asm"
        .include "gen/fconst.asm"
tail_b_end:
        .endlogical
        * = WINDOW_SIZE + TAIL_SIZE
        .logical TAIL
tail_h_start:
        .include "tailh.asm"
tail_h_end:
        .endlogical
        * = WINDOW_SIZE + 2 * TAIL_SIZE
        .logical TAIL
tail_f_start:
        .include "file.asm"
tail_f_end:
        .endlogical
        * = WINDOW_SIZE + 3 * TAIL_SIZE
        .logical TAIL
tail_s_start:
        .include "strmeth.asm"
tail_s_end:
        .endlogical
        * = WINDOW_SIZE + 4 * TAIL_SIZE
        .logical TAIL
tail_p_start:
        .include "fmtsort.asm"
tail_p_end:
        .endlogical
        * = WINDOW_SIZE + 5 * TAIL_SIZE
        .logical TAIL
tail_i_start:
        .include "taili.asm"
tail_i_end:
        .endlogical
        * = WINDOW_SIZE + 6 * TAIL_SIZE
        .logical TAIL
tail_x_start:
        .include "args.asm"
tail_x_end:
        .endlogical
        * = WINDOW_SIZE + 7 * TAIL_SIZE
        .logical TAIL
tail_t_start:
        .include "sets.asm"
        .include "listslice.asm"
        .include "introsp.asm"
tail_t_end:
        .endlogical
        * = WINDOW_SIZE + 8 * TAIL_SIZE
        .logical TAIL
tail_m_start:
        .include "classm.asm"
        .include "bytes.asm"
tail_m_end:
        .endlogical
        * = WINDOW_SIZE + 9 * TAIL_SIZE
        .logical TAIL
tail_n_start:
        .include "bigint.asm"
tail_n_end:
        .endlogical
        * = WINDOW_SIZE + 10 * TAIL_SIZE   ; (the second file, mpy-ov2: split.py)
        .logical TAIL
tail_o_start:
        .include "strpos.asm"
tail_o_end:
        .endlogical
        .cerror TAILS_N != 11, "TAILS_N must count the tails written after overlay C"
        .endif

part2_len = part2_end - part2_start
        .cerror PART2_LOAD + part2_len > $e000, "part 2's load image is too big"

        .if PASS == 1
        .warn format("part 1 $%04x, overlay R $%04x + tail A $%04x / B $%04x / H $%04x / F $%04x / S $%04x / P $%04x / I $%04x / X $%04x / T $%04x / M $%04x / N $%04x / O $%04x, part 2 $%04x, overlay C $%04x bytes", part1_end - $2001, r_main_end - ovl_r_start, ovl_r_end - TAIL, tail_b_end - tail_b_start, tail_h_end - tail_h_start, tail_f_end - tail_f_start, tail_s_end - tail_s_start, tail_p_end - tail_p_start, tail_i_end - tail_i_start, tail_x_end - tail_x_start, tail_t_end - tail_t_start, tail_m_end - tail_m_start, tail_n_end - tail_n_start, tail_o_end - tail_o_start, part2_len, ovl_c_end - ovl_c_start)
        .endif
