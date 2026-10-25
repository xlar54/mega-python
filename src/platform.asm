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
; Memory map. The KERNAL stays resident (SYS map: $2000-$BFFF RAM, KERNAL at $E000),
; so the program can LOAD/SAVE .py files at any time.
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
;   bank 0  $0800-$0FCF   80x25 screen
;           $1600-$16FF   base page (B = $16, away from KERNAL and BASIC)
;           $1700-$17FF   REPL line buffer
;           $1800-$1DFF   CPU stack (16-bit SP)
;           $1E00-$1EFF   file name buffer for KERNAL calls
;           $2001-$7FFF   resident code, part 1
;           $8000-$BFFF   overlay window: R (builtins, methods) or C (compiler, editor),
;                         copied in from attic by DMA
;           $C000-$CFFF   value stack (2048 refs, grows down); while compiling (the VM
;                         is idle) the compiler scopes use $C000-$C3FF
;           $E000-$E3FF   call frame stack (128 x 8)
;           $E400-$E7FF   exception handler stack (128 x 8)
;           $E800-$FFF9   resident code, part 2 (loaded at $C000, moved by DMA at boot)
;   bank 1  $12000-$12FFF global value of each symbol
;           $13000-$137FF GC mark stack
;           $14000-$15FFF string builder
;           $16000-$1EFFF bytecode (36 KB)
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
SCREEN                  = $0800
COLRAM                  = $FF80000
LINEBUF                 = $1700
CPUSTACK                = $1800
CPUSTACK_TOP            = $1DFF
CPUSTACK_LIMIT          = $1880         ; RecursionError below this
FNAMEBUF                = $1E00
WINDOW                  = $8000
WINDOW_SIZE             = $4000
PART2                   = $E800         ; resident part 2 runs here
PART2_LOAD              = $C000         ; ... and its place in the build image
OVL_R_ATTIC             = $8180000
OVL_C_ATTIC             = $8190000
SCOPEMEM                = $C000         ; 5 compiler scopes x 192 bytes
SCOPE_SIZE              = 192
SCOPE_MAX               = 5
TARGETS                 = $C3C0         ; assignment targets, 8 x 8 bytes
TARGETS_N               = 8
CUTBUF                  = $8170010      ; compiler code cut stack (attic; handle 0 = none)
FSTACK                  = $E000
FSTACK_END              = $E400
HSTACK                  = $E400
HSTACK_END              = $E800
VSTACK                  = $C000         ; lowest slot
VSTACK_END              = $D000         ; empty stack: vsp = VSTACK_END


SYM_VAL                 = $12000        ; global value of each symbol
MARKSTACK               = $13000        ; GC mark stack, 1024 refs
MARKSTACK_N             = 1024
SBUF                    = $14000        ; string builder, 8 KB
SBUF_SIZE               = $2000
CODE_BANK               = $01
CODE_START              = $6000         ; bytecode at $16000-$1EFFF
CODE_END                = $EF00
HEAP_BANK               = $04
HEAP_START              = $0100
GFXMEM                  = $50000
STAGE                   = $50000

SRC                     = $8100000      ; program source
SRC_MAX                 = $FFF0
SYM_NAME                = $8110000      ; ref of each symbol's interned name
SYM_NEXT                = $8111000      ; hash chain (+1 = sym id, 0 = end)
SYM_HASH                = $8112000      ; 256 bucket heads
MAXSYMS                 = 2048
LINETAB                 = $8120000      ; (code offset, line) pairs
LINETAB_END             = $8130000
REPLBUF                 = $8130000      ; multi-line REPL input
REPLBUF_END             = $8138000
HIST                    = $8138000      ; REPL history, 8 x 256
