;=======================================================================================
; MEGA65 hardware registers and the interpreter's memory map.
;=======================================================================================
VIC_CTRL1               = $D011         ; bit7 = raster bit 8, bit4 = DEN
VIC_RASTER              = $D012
BORDERCOL               = $D020
BACKCOL                 = $D021
VIC4_KEY                = $D02F         ; write $47,$53 to unlock VIC-IV
VIC3_ROMBANK            = $D030
VIC3_CTRL               = $D031         ; bit7 H640, bit6 FAST, bit5 ATTR
VIC4_HOTREG             = $D05D
VIC4_CHRCOUNT           = $D05E
VIC4_LINESTEP           = $D058
VIC4_SCRNPTR            = $D060
VIC4_COLPTR             = $D064
VIC4_CHARPTR            = $D068
VIC4_DISPROWS           = $D07B

ASCIIKEY                = $D610         ; hardware typing queue: ASCII, 0 = empty
MODKEY                  = $D611
FRAMECOUNT              = $D7FA

MULTINA                 = $D770
MULTINB                 = $D774
MULTOUT                 = $D778
DIVOUT                  = $D768         ; +0..3 fraction, +4..7 whole part
MATHBUSY                = $D70F         ; bit7 DIVBUSY

DMA_ADDRLSB_ETRIG       = $D705
DMA_ADDRMSB             = $D701
DMA_ADDRBANK            = $D702
DMA_ADDRMB              = $D704
DMAOPT_F018B            = $0B
DMAOPT_SRC_MB           = $80
DMAOPT_DST_MB           = $81
DMAOPT_SRC_STEP_INT     = $83
DMAOPT_DST_STEP_INT     = $85
DMAOPT_END              = $00
DMACMD_COPY             = $00
DMACMD_FILL             = $03

KERNAL_SETBNK           = $FF6B
KERNAL_SETLFS           = $FFBA
KERNAL_SETNAM           = $FFBD
KERNAL_OPEN             = $FFC0
KERNAL_CLOSE            = $FFC3
KERNAL_CHKIN            = $FFC6
KERNAL_CLRCHN           = $FFCC
KERNAL_CHRIN            = $FFCF
KERNAL_READST           = $FFB7
KERNAL_LOAD             = $FFD5
KERNAL_SAVE             = $FFD8

;---------------------------------------------------------------------------------------
; Memory map. The KERNAL stays available (through kernal_call) so programs can be
; loaded and saved at any time.
;
; Chip RAM holds what the VM touches all the time; attic RAM (slower, 8 MB) holds the
; bulky or compile-time-only data. Bank 5 is kept free for a graphics framebuffer
; (320x200x256 FCM = 64000 bytes) and doubles as the KERNAL load/save staging area.
;
; The interpreter runs with interrupts off, a 16-bit CPU stack and the ROMs unmapped
; (MAP clear, $01 = $35, no $D030 ROMs): bank 0 is RAM except I/O at $D000.
; kernal_call restores the boot MAP/$01/$D030, the page-1 stack, B = 0 and cli
; around each KERNAL call.
;
; The KERNAL's own regions are left alone (book, "The Chip RAM Memory Map"): 0.0002-
; 0.15FF KERNAL, 1.0000-1.1FFF DOS, 1.F700-1.F7FF reserved, 1.F800- colour window,
; 0.FF00-0.FFFF reserved (the NMI/IRQ vectors there are saved at boot and put back for
; every KERNAL call). BASIC's areas are free: BASIC never runs again.
;
;   bank 0  $1600-$16FF   base page (B = $16, away from KERNAL and BASIC)
;           $1700-$17FF   REPL line buffer
;           $1800-$1DFF   CPU stack (16-bit SP)
;           $1E00-$1EFF   file name buffer for KERNAL calls
;           $1F00-$1FFF   decimal digits of a float being converted
;           $2001-$7DFF   resident code, part 1
;           $7E00-$7FFF   free for the user's machine code (os.sys)
;           $8000-$CFFF   overlay window (20 KB): R (builtins, methods, floats) or
;                         C (compiler, editor), copied in from attic by DMA. With R
;                         in, its last 4 KB ($C000-) is a "tail", swapped as needed:
;                         A (float text), B (math), H (rare things), F (files, os,
;                         imports), S (str methods), P (formatting, sorting) or I
;                         (interpreter setup)
;           $E000-$EFFF   value stack (2048 refs, grows down); while compiling (the VM
;                         is idle) the compiler scopes and targets use $E000-$E53F
;           $F000-$FEFF   resident code, part 2 (loaded at $D000, moved by DMA at boot)
;   bank 1  $12000-$12FFF global value of each symbol
;           $13000-$137FF GC mark stack
;           $13800-$13BFF bignum workspace (float <-> decimal conversion)
;           $13C00-$13FFF read buffers of open Python files (4 x 256)
;           $14000-$15FFF string builder
;           $16000-$1D7FF bytecode (30 KB)
;           $1D800-$1DFCF graphics mode's character pointers (lib/gfx.py)
;           $1E000-$1E3FF call frame stack (128 x 8)
;           $1E400-$1E7FF exception handler stack (128 x 8)
;           $1E800-$1EFCF 80x25 screen
;   bank 4  $40000-$4FFFF object heap (refs are 16-bit offsets into this bank)
;   bank 5  $50000-$5FFFF graphics framebuffer / disk staging
;   attic   $8000000      output transcript (1 MB, for the test runner)
;           $8100000      program source (the editor buffer, 64 KB)
;           $8110000      symbol names, hash chains and buckets
;           $8120000      line table
;           $8130000      REPL block text
;           $8138000      REPL history
;---------------------------------------------------------------------------------------
BP_PAGE                 = $16
SCREEN                  = $1E800        ; bank 1 (BASIC's area; 1.F700- is reserved)
COLRAM                  = $FF80000
LINEBUF                 = $1700
CPUSTACK                = $1800
CPUSTACK_TOP            = $1DFF
CPUSTACK_LIMIT          = $1880         ; RecursionError below this
FNAMEBUF                = $1E00
DIGBUF                  = $1F00         ; float <-> decimal digits (256)
USERCODE                = $7E00         ; $7E00-$7FFF: free for os.sys() machine code
WINDOW                  = $8000
WINDOW_SIZE             = $5000
PART2                   = $F000         ; resident part 2 runs here (up to $FEFF)
PART2_END               = $FF00         ; 0.FF00-0.FFFF is reserved
PART2_LOAD              = $D000         ; ... and its place in the build image
OVL_R_ATTIC             = $8180000
OVL_C_ATTIC             = $8190000
OVL_B_ATTIC             = $81A0000      ; tail B (the math module)
OVL_H_ATTIC             = $81A1000      ; tail H (help, mem, load/save/files)
OVL_F_ATTIC             = $81A2000      ; tail F (Python files: open())
OVL_S_ATTIC             = $81A3000      ; tail S (str methods)
OVL_P_ATTIC             = $81A4000      ; tail P (formatting, sorting)
OVL_I_ATTIC             = $81A5000      ; tail I (interpreter setup: py_reset)
OVL_X_ATTIC             = $81A6000      ; tail X (*args / **kwargs binding, f(*a) calls)
OVL_T_ATTIC             = $81A7000      ; tail T (sets)
OVL_M_ATTIC             = $81A8000      ; tail M (classes: bases, MRO)
OVL_N_ATTIC             = $81A9000      ; tail N (big ints)
TAILS_N                 = 10            ; tails B, H, F, S, P, I, X, T, M, N: in a row in mpy-ovl
FILEBUF                 = $13C00        ; read buffers of open files 2-5 (4 x 256, bank 1)
TAIL_SIZE               = $1000         ; the window's last 4 KB: one of the tails
TAIL                    = WINDOW + WINDOW_SIZE - TAIL_SIZE
SCOPEMEM                = $E000         ; 5 compiler scopes x 256 bytes
SCOPE_SIZE              = 256
SCOPE_MAX               = 5
TARGETS                 = SCOPEMEM + SCOPE_MAX * SCOPE_SIZE ; assignment targets, 8 x 8 bytes
TARGETS_N               = 8
COMPILER_END            = TARGETS + 8 * TARGETS_N   ; (the compiler's part of the value stack)
CUTBUF                  = $8170010      ; compiler code cut stack (attic; handle 0 = none)
FSTACK                  = $1E000        ; call frames, bank 1
FSTACK_END              = $1E400
HSTACK                  = $1E400        ; exception handlers, bank 1
HSTACK_END              = $1E800
VSTACK                  = $E000         ; lowest slot
VSTACK_END              = $F000         ; empty stack: vsp = VSTACK_END


SYM_VAL                 = $12000        ; global value of each symbol
MARKSTACK               = $13000        ; GC mark stack, 1024 refs
MARKSTACK_N             = 1024
BIGNUM                  = $13800        ; bignum workspace (1 KB)
SBUF                    = $14000        ; string builder, 8 KB
SBUF_SIZE               = $2000
CODE_BANK               = $01
CODE_START              = $6000         ; bytecode at $16000-$1D7FF
CODE_END                = $D800
GFXCHARS                = $1D800        ; graphics mode: the 40 x 25 character pointers
HEAP_BANK               = $04
HEAP_START              = $0100
GFXMEM                  = $50000
STAGE                   = $50000

SRC                     = $8100000      ; program source
SRC_MAX                 = $FFF0
SYM_NAME                = $8110000      ; ref of each symbol's interned name
SYM_NEXT                = $8111000      ; hash chain (+1 = sym id, 0 = end)
SYM_HASH                = $8112000      ; 256 bucket heads
SYM_BASE                = $8113000      ; a module's hidden symbol -> its plain one
SYM_BOOT                = $8114000      ; SYM_VAL as py_reset left it (globals())
MODSRC                  = $81C0000      ; the source of a module being imported (64 KB)
MAXSYMS                 = 2048
LINETAB                 = $8120000      ; (code offset, line) pairs
LINETAB_END             = $8130000
REPLBUF                 = $8130000      ; multi-line REPL input
REPLBUF_END             = $8138000
HIST                    = $8138000      ; REPL history, 8 x 256
