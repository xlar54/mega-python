;=======================================================================================
; Base page at $1600 (B register = $16). KERNAL calls switch B to 0 and back.
; Pointers named p* are 32-bit (for [p],z); bytes 2-3 select the bank.
;=======================================================================================
        .virtual $1600
; heap object pointers (bank 4 preset at init)
p0:             .dword ?
p1:             .dword ?
p2:             .dword ?
p3:             .dword ?
; general far pointers (any bank)
fp0:            .dword ?
fp1:            .dword ?
fp2:            .dword ?
; 32-bit integer accumulators
acc:            .dword ?
acc2:           .dword ?
acc3:           .dword ?
; scratch
t0:             .word ?
t1:             .word ?
t2:             .word ?
t3:             .word ?
t4:             .word ?
t5:             .word ?
t6:             .word ?
t7:             .word ?
r0:             .word ?                 ; refs passed between routines
r1:             .word ?
r2:             .word ?
r3:             .word ?
; GC temp roots (scanned by the collector)
groot:          .fill 16
; screen
scr_row:        .byte ?
scr_col:        .byte ?
scr_color:      .byte ?
scr_ptr:        .dword ?                ; screen address of the cursor cell
cur_ptr:        .dword ?                ; colour RAM address of the cursor cell
; heap
heap_top:       .word ?
free_list:      .word ?
alloc_size:     .word ?
; VM registers
ip:             .dword ?                ; bytecode pointer (bank 5)
vsp:            .word ?                 ; value stack: next free slot
vfp:            .word ?                 ; locals base of the running function
frp:            .dword ?                ; call frame stack pointer (bank 1)
hsp:            .dword ?                ; handler stack pointer (bank 1)
vtmp:           .word ?
argp:           .word ?                 ; native call: first argument
argc:           .byte ?                 ; a call's argument count (VM, and natives' own calls)
nargc:          .byte ?                 ; native call: its argument count (argv)
npos:           .byte ?                 ; native call: positional ones (check_nargs)
kwnames:        .word ?                 ; native call: keyword names tuple (0 = none)
nkw:            .byte ?
cur_exc:        .word ?
err_sp:         .word ?                 ; CPU SP to unwind to on an error
c_slot:         .word ?                 ; call: where the result goes
c_func:         .word ?                 ; call: the callable
sc:             .word ?                 ; compiler: current scope record
stop_count:     .byte ?
; lexer
lx_ptr:         .dword ?
lx_line:        .word ?
lx_paren:       .byte ?
lx_isp:         .byte ?                 ; indent stack depth
lx_pend:        .byte ?                 ; pending DEDENT tokens
lx_bol:         .byte ?                 ; at beginning of line
lx_last:        .byte ?                 ; last token type
lx_scan:        .byte ?                 ; 1 = pre-scan (no objects created)
tok:            .byte ?
tok_sym:        .word ?
tok_ref:        .word ?
tok_num:        .dword ?
tok_start:      .dword ?                ; source address of the token
tok_line:       .word ?
lx_state_end:
; compiler
cp:             .dword ?                ; code emit pointer (bank 5)
c_scope:        .byte ?                 ; 0 module, 1 function, 2 class
c_nlocals:      .byte ?
c_nglobals:     .byte ?
c_loop:         .byte ?                 ; loop nesting (index into loop table)
c_try:          .byte ?                 ; try nesting in the current function
c_last_op:      .word ?                 ; code offset of the last emitted load
c_last_kind:    .byte ?
c_depth:        .byte ?
c_line:         .word ?
; misc
str_len:        .word ?
nitems:         .word ?
sbp:            .dword ?                ; string builder write pointer (bank 1)
int_ref:        .word ?
rdepth:         .byte ?                 ; repr recursion depth
log_fp:         .dword ?                ; output transcript pointer (attic)
key_last:       .byte ?
dbg_kpos:       .byte ?
; variables that need base-page modes (inw/dew, [ptr],z)
rp:             .dword ?                ; REPL input pointer
cpat:           .dword ?                ; compiler code patch pointer
fs_p:           .dword ?                ; f-string scan pointer
gc_count:       .word ?
gc_msp:         .word ?
gc_n:           .word ?
nsyms:          .word ?
pc_pos:         .word ?
ms_i:           .word ?
ms_j:           .word ?
ms_k:           .word ?
src_len:        .word ?
ed_cur:         .word ?
bnA:            .dword ?                ; floats: bignum operands (bank 1)
bnB:            .dword ?
bnC:            .dword ?                ; big ints: a third operand (bigint.asm)
fsp:            .dword ?                ; floats: text being parsed
ff_i:           .word ?                 ; floats: layout digit index / count
ff_cnt:         .word ?
fd_dec:         .word ?                 ; floats: decimal point of the digits
fd_exp:         .word ?                 ; floats: decimal exponent while parsing
tcp:            .word ?                 ; tcall: the stub's data
zp_end:
        .endv
        .cerror zp_end > $1700, "base page overflow"
        .cerror lx_state_end - lx_ptr > 40, "lexer state too big"
LX_STATE_SIZE = lx_state_end - lx_ptr
