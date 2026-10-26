;=======================================================================================
; Tail H: help(), mem(), and the program load / save / directory of the REPL; error
; messages that name a type.
;=======================================================================================
; xh_raise_typed - (raise_typed) A/X = an object, Y = RT_*: raise the error about it as
; CPython words it, with its type's name: "'int' object is not subscriptable"
rt_obj:         .word 0
rt_msg:         .byte 0
xh_raise_typed:
        sta rt_obj
        stx rt_obj+1
        sty rt_msg
        jsr sb_mark_t5
        lda rt_msg
        cmp #RT_LEN
        bne +
        #SBPRINT "object of type "
+       lda #$27
        jsr sb_putc
        lda rt_obj
        ldx rt_obj+1
        jsr sb_type_name
        lda #$27
        jsr sb_putc
        lda rt_msg
        asl a
        tay
        lda rt_text,y
        ldx rt_text+1,y
        jsr sb_puts
        lda #EXC_TYPE
        ldy rt_msg
        cpy #RT_SEND
        bne +
        lda #EXC_ATTR
+       jmp raise_sb
rt_text:        .word _sub, _set, _del, _iter, _next, _len, _map, _send
_sub:   .text " object is not subscriptable", 0
_set:   .text " object does not support item assignment", 0
_del:   .text " object doesn't support item deletion", 0
_iter:  .text " object is not iterable", 0
_next:  .text " object is not an iterator", 0
_len:   .text " has no len()", 0
_map:   .text " object is not a mapping", 0
_send:  .text " object has no attribute 'send'", 0

xh_help:
        jsr scr_fresh_line
        lda #COL_INFO
        sta scr_color
        lda #<help_text
        ldx #>help_text
        jsr puts
        lda #COL_NORMAL
        sta scr_color
        lda #R_NONE
        ldx #0
        rts
help_text:
        .text "MEGA65 Python - commands:", 10
        .text "  edit()          full-screen editor for the program (ESC = back, F5 = run)", 10
        .text "  run()           run the program", 10
        .text "  new()           clear the program and all variables", 10
        .text "  load('name')    load name.py from disk;  save('name') saves it", 10
        .text "  files()         list the .py files on the disk", 10
        .text "  cls()  mem()  gc()  peek(addr)  poke(addr, byte)", 10
        .text "Keys: cursor keys edit the line, up/down = history, RUN/STOP = break", 10, 0

; mem() - collect garbage, then what is free in each area
xh_mem:
        jsr gc_collect
        jsr heap_free
        lda acc                         ; the free amounts, in the order of the rows
        sta mem_free
        lda acc+1
        sta mem_free+1
        sec                             ; bytecode
        lda #<CODE_END
        sbc cp
        sta mem_free+2
        lda #>CODE_END
        sbc cp+1
        sta mem_free+3
        sec                             ; names
        lda #<MAXSYMS
        sbc nsyms
        sta mem_free+4
        lda #>MAXSYMS
        sbc nsyms+1
        sta mem_free+5
        sec                             ; source
        lda #<SRC_MAX
        sbc src_len
        sta mem_free+6
        lda #>SRC_MAX
        sbc src_len+1
        sta mem_free+7
        sec                             ; value stack slots
        lda vsp
        sbc #<VSTACK
        sta mem_free+8
        lda vsp+1
        sbc #>VSTACK
        lsr a
        sta mem_free+9
        ror mem_free+8
        lda sbp
        pha
        lda sbp+1
        pha
        ldx #0
_row:   phx
        lda mem_label,x                 ; the label
        pha
        lda mem_label+1,x
        tax
        pla
        jsr sb_puts
        plx
        phx
        lda mem_free,x                  ; "free of total unit free"
        ldy mem_free+1,x
        jsr _num
        #SBPRINT " of "
        plx
        phx
        lda mem_total,x
        ldy mem_total+1,x
        jsr _num
        plx
        phx
        lda mem_unit,x
        pha
        lda mem_unit+1,x
        tax
        pla
        jsr sb_puts
        #SBPRINT " free"
        lda #10
        jsr sb_putc
        plx
        inx
        inx
        cpx #2*5
        bne _row
        #SBPRINT "bank 5 (64 KB) is kept for graphics."
        lda #10
        jsr sb_putc
        plx
        pla
        jsr sb_flush
        lda #R_NONE
        ldx #0
        rts
_num:   ; A/Y, right-aligned in 5 columns
        sta acc
        sty acc+1
        lda #0
        sta acc+2
        sta acc+3
        ldx #4                          ; a space for each power of 10 above it
-       lda acc+1
        cmp _p10hi-1,x
        bcc +
        bne _wide
        lda acc
        cmp _p10lo-1,x
        bcs _wide
+       lda #' '
        jsr sb_putc
        dex
        bne -
_wide:  jmp sb_int
_p10lo: .byte <10, <100, <1000, <10000
_p10hi: .byte >10, >100, >1000, >10000
mem_free:       .fill 10
mem_label:      .word mem_l0, mem_l1, mem_l2, mem_l3, mem_l4
mem_total:      .word HEAP_LIMIT - HEAP_START, CODE_END - CODE_START, MAXSYMS, SRC_MAX
                .word (VSTACK_END - VSTACK) / 2
mem_unit:       .word mem_u0, mem_u0, mem_u2, mem_u0, mem_u4
mem_l0:    .text "objects (heap, bank 4)  ", 0
mem_l1:    .text "bytecode (bank 1)       ", 0
mem_l2:    .text "names (symbol table)    ", 0
mem_l3:    .text "program source (attic)  ", 0
mem_l4:    .text "value stack (bank 0)    ", 0
mem_u0:    .text " bytes", 0
mem_u2:    .text " names", 0
mem_u4:    .text " slots", 0

;---------------------------------------------------------------------------------------
; load() / save() / files() (from the REPL's requests) and the exception classes' names
;---------------------------------------------------------------------------------------
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
; It is walked with fsp, not fp0: putc's screen scrolling (a DMA) uses fp0.
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
        sta fsp
        lda #>STAGE
        sta fsp+1
        lda #`STAGE
        sta fsp+2
        lda #0
        sta fsp+3
        ; a load address in front? ($01 $01, then a link, then line number 0)
        ldz #0
        lda [fsp],z
        cmp #$01
        bne _nohdr
        inz
        lda [fsp],z
        cmp #$01
        bne _nohdr
        ldz #4
        lda [fsp],z
        inz
        ora [fsp],z
        bne _nohdr
        inw fsp
        inw fsp
_nohdr: inw fsp                         ; skip the first link
        inw fsp
_line:  jsr _left                       ; room for the line number?
        cmp #3
        bcc _end
        ldz #0
        lda [fsp],z
        sta acc
        inz
        lda [fsp],z
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
        inw fsp
        inw fsp
-       jsr _left                       ; the text, up to its zero
        beq _nl
        ldz #0
        lda [fsp],z
        beq +
        jsr petscii_to_ascii
        cmp #$12                        ; reverse-on in the header
        beq _skip
        cmp #32
        bcc _skip
        jsr putc
_skip:  inw fsp
        bra -
+       inw fsp
        lda #10
        jsr putc
        jsr _left                       ; the next link: zero ends the listing
        cmp #2
        bcc _end
        ldz #0
        lda [fsp],z
        inz
        ora [fsp],z
        beq _end
        inw fsp
        inw fsp
        bra _line
_nl:    lda #10
        jsr putc
_end:   rts
; A = bytes left to read (255 when more than that), Z flag set when none
_left:  sec
        lda dir_end
        sbc fsp
        tax
        lda dir_end+1
        sbc fsp+1
        bcc _none
        bne _many
        txa
        rts
_many:  lda #255
        rts
_none:  lda #0
        rts
dir_end:        .word 0

; xh_type_name - (sb_type_name) append the type name of A/X
xh_type_name:
        sta t0
        stx t0+1
        jsr type_of
        cmp #T_INST
        bne +
        ldz #4                          ; the class name
        lda [p0],z
        sta p1
        inz
        lda [p0],z
        sta p1+1
        ldz #5
        lda [p1],z
        tax
        dez
        lda [p1],z
        jmp sb_put_str
+       cmp #T_CLASS
        bne +
        #SBPRINT "type"
        rts
+       asl
        tax
        lda type_names,x
        pha
        lda type_names+1,x
        tax
        pla
        jmp sb_puts

type_names:
        .word tn_null, tn_int, tn_str, tn_list, tn_tuple, tn_dict, tn_arr, tn_func
        .word tn_builtin, tn_method, tn_type, tn_object, tn_range, tn_iter, tn_float
        .word tn_none, tn_bool, tn_slice, tn_super, tn_file, tn_module, tn_desc, tn_gen
        .word tn_set, tn_fset
tn_gen:         .text "generator", 0
tn_desc:        .text "property", 0     ; (or staticmethod / classmethod)
tn_file:        .text "TextIOWrapper", 0
tn_module:      .text "module", 0
tn_set:         .text "set", 0
tn_fset:        .text "frozenset", 0
tn_null:        .text "NULL", 0
tn_int:         .text "int", 0
tn_str:         .text "str", 0
tn_list:        .text "list", 0
tn_tuple:       .text "tuple", 0
tn_dict:        .text "dict", 0
tn_arr:         .text "array", 0
tn_func:        .text "function", 0
tn_builtin:     .text "builtin_function_or_method", 0
tn_method:      .text "method", 0
tn_type:        .text "type", 0
tn_object:      .text "object", 0
tn_range:       .text "range", 0
tn_iter:        .text "iterator", 0
tn_float:       .text "float", 0
tn_none:        .text "NoneType", 0
tn_bool:        .text "bool", 0
tn_slice:       .text "slice", 0
tn_super:       .text "super", 0

;---------------------------------------------------------------------------------------
; tracebacks (builtins.asm keeps their record: tb_*)
;---------------------------------------------------------------------------------------
xh_print_exception:
        jsr scr_fresh_line
        lda #COL_ERROR
        sta scr_color
        lda cur_exc
        ldx cur_exc+1
        sta r2
        stx r2+1
        ; syntax errors carry their own line; others: the levels of calls
        lda #EXC_SYNTAX
        jsr exc_is
        bcs _msg
        jsr print_tb
_msg:   ; "Name: message", or just "Name" when str(exc) is empty
        lda sbp
        pha
        lda sbp+1
        pha
        lda cur_exc
        ldx cur_exc+1
        jsr sb_type_name
        lda sbp
        pha
        lda sbp+1
        pha
        #SBPRINT ": "
        lda sbp
        pha
        lda sbp+1
        pha
        lda cur_exc
        ldx cur_exc+1
        jsr obj_str
        pla
        sta t1+1
        pla
        sta t1
        pla
        sta t2+1
        pla
        sta t2
        lda sbp
        cmp t1
        bne +
        lda sbp+1
        cmp t1+1
        bne +
        lda t2                          ; empty message: drop the ": "
        sta sbp
        lda t2+1
        sta sbp+1
+       plx
        pla
        jsr sb_flush
        lda #10
        jsr putc
        lda #COL_NORMAL
        sta scr_color
        rts
xh_tb_capture:
        lda cur_exc
        sta tb_exc
        lda cur_exc+1
        sta tb_exc+1
        lda #0
        sta tb_more
        lda frp
        sta fp1
        lda frp+1
        sta fp1+1
        lda #<(FSTACK >> 16)
        sta fp1+2
        lda #0
        sta fp1+3
        ldy #0                          ; Y = 2 * entries
_loop:  lda fp1
        cmp #<FSTACK
        bne +
        lda fp1+1
        cmp #>FSTACK
        beq _done
+       cpy #2 * TB_N
        bcc +
        inc tb_more
        bra _done
+       sec
        lda fp1
        sbc #8
        sta fp1
        bcs +
        dec fp1+1
+       ldz #0                          ; the return ip
        lda [fp1],z
        sta tb_ip,y
        inz
        lda [fp1],z
        sta tb_ip+1,y
        ldz #4                          ; the callee: in the result slot, or a
        lda [fp1],z                     ; generator's function
        sta t0
        inz
        lda [fp1],z
        sta t0+1
        phy
        ldz #6
        lda [fp1],z
        and #FR_GEN
        beq _slot
        ldy #2
        lda (t0),y
        sta p0
        iny
        lda (t0),y
        sta p0+1
        ldz #4
        lda [p0],z
        pha
        inz
        lda [p0],z
        tax
        pla
        bra _f
_slot:  ldy #1
        lda (t0),y
        tax
        dey
        lda (t0),y
_f:     sta p0
        stx p0+1
        jsr type_of
        cmp #T_FUNC
        beq +
        lda #0
        tax
        bra _put
+       ldz #9                          ; its name
        lda [p0],z
        tax
        dez
        lda [p0],z
_put:   ply
        sta tb_name,y
        txa
        sta tb_name+1,y
        iny
        iny
        bra _loop
_done:  tya
        lsr a
        sta tb_n
        rts

print_tb:
        lda tb_exc                      ; (recorded for this exception?)
        cmp cur_exc
        bne _rts
        lda tb_exc+1
        cmp cur_exc+1
        bne _rts
        #PRINT "Traceback (most recent call last):"
        lda #10
        jsr putc
        lda tb_more
        beq +
        #PRINT "  ..."
        lda #10
        jsr putc
+       ldx tb_n
_lvl:   dex                             ; frame X: its return ip, and the function
        bmi _last                       ; of the frame outside it (X + 1)
        phx
        txa
        asl a
        tay
        lda tb_ip,y
        ldx tb_ip+1,y
        jsr _line
        plx
        phx
        inx
        cpx tb_n
        bcc _named
        lda tb_more
        bne _eol
        jsr _module
        bra _eol
_named: txa
        asl a
        tay
        lda tb_name,y
        ldx tb_name+1,y
        jsr _in
_eol:   lda #10
        jsr putc
        plx
        bra _lvl
_last:  lda exc_ip                      ; where it was raised
        ldx exc_ip+1
        jsr _line
        lda tb_n
        beq _mod
        lda tb_name
        ldx tb_name+1
        jsr _in
        bra +
_mod:   jsr _module
+       lda #10
        jmp putc
_rts:   rts
_line:  jsr line_of_ip                  ; "  line N"
        bcc +
        #PRINT "  ?"
        rts
+       pha
        phx
        #PRINT "  line "
        plx
        pla
        sta acc
        stx acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_mark_t5
        jsr sb_int
        lda t5
        ldx t5+1
        jmp sb_flush
_in:    cpx #0                          ; ", in name"
        beq _rts
        pha
        phx
        #PRINT ", in "
        plx
        pla
        jmp put_str
_module:
        #PRINT ", in <module>"
        rts
line_of_ip:
        sta t0
        stx t0+1
        lda #<LINETAB
        sta fp0
        lda #>LINETAB
        sta fp0+1
        lda #<(LINETAB >> 16)
        sta fp0+2
        lda #>(LINETAB >> 16)
        sta fp0+3
        lda #0
        sta t1                          ; best line
        sta t1+1
        lda #1
        sta t2                          ; none found yet
_loop:  lda fp0
        cmp linetab_end
        bne +
        lda fp0+1
        cmp linetab_end+1
        beq _done
+       ldz #1
        lda [fp0],z
        cmp t0+1
        bcc _take
        bne _skip
        dez
        lda [fp0],z
        cmp t0
        bcs _skip
_take:  ldz #2
        lda [fp0],z
        sta t1
        inz
        lda [fp0],z
        sta t1+1
        lda #0
        sta t2
_skip:  clc
        lda fp0
        adc #4
        sta fp0
        bcc _loop
        inc fp0+1
        bra _loop
_done:  lda t2
        lsr
        lda t1
        ldx t1+1
        rts

;---------------------------------------------------------------------------------------
; UNPACK_EX b, a - value -> a list of b + 1 + a items: its first b items, a list of
; the ones between, its last a items (an UNPACK of that follows): a, *b, c = value
;---------------------------------------------------------------------------------------
ux_b:           .byte 0
ux_a:           .byte 0
ux_n:           .word 0
ux_i:           .word 0
xh_unpack_ex:
        #FETCHB
        sta ux_b
        #FETCHB
        sta ux_a
        #PEEK 0
        jsr list_from_iterable          ; (a copy: may run Python code)
        #POKE 0                         ; [items]
        jsr seq_len
        lda t0
        sta ux_n
        lda t0+1
        sta ux_n+1
        clc
        lda ux_b
        adc ux_a
        sta nitems
        lda ux_n+1
        bne +
        lda ux_n
        cmp nitems
        bcs +
        #RAISE EXC_VALUE, "not enough values to unpack"
+       inc nitems                      ; the result
        lda #0
        sta nitems+1
        sta ux_i
        sta ux_i+1
        jsr list_new
        #PUSH                           ; [items][result]
-       lda ux_i                        ; the first b
        cmp ux_b
        bcs +
        ldy #1
        jsr _take
        bra -
+       lda #0                          ; the ones between
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [items][result][middle]
-       sec
        lda ux_n
        sbc ux_a
        sta t1
        lda ux_n+1
        sbc #0
        sta t1+1
        lda ux_i
        cmp t1
        lda ux_i+1
        sbc t1+1
        bcs +
        ldy #2
        jsr _take
        bra -
+       #POP
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append                 ; [items][result]
-       lda ux_i                        ; the last a
        cmp ux_n
        lda ux_i+1
        sbc ux_n+1
        bcs +
        ldy #1
        jsr _take
        bra -
+       #POP
        #POKE 0
        jsr clear_rregs
        rts
; _take - append items[ux_i] (Y = its depth on the stack) to the list on top
_take:  phy
        lda ux_i
        sta t2
        lda ux_i+1
        sta t2+1
        ply
        tya                             ; (the slot at depth Y: 2Y, 2Y + 1)
        asl a
        tay
        lda (vsp),y
        pha
        iny
        lda (vsp),y
        tax
        pla
        jsr seq_get_t2
        sta r1
        stx r1+1
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
        inc ux_i
        bne +
        inc ux_i+1
+       rts

;---------------------------------------------------------------------------------------
; IMPORT_STAR w target - module -> (nothing): from module import * binds the module's
; names (its __all__, else those not starting with '_') in the target: 0 = the main
; program's globals, else that module's hidden names (gsym with c_mod = target)
;---------------------------------------------------------------------------------------
is_tgt:         .word 0
is_all:         .byte 0                 ; the names came from __all__ (keep '_' ones)
is_i:           .word 0
is_s:           .word 0
is_ml:          .byte 0
is_buf:         .fill 16                ; the module's name

xh_import_star:
        #FETCHW
        sta is_tgt
        stx is_tgt+1
        lda #0
        sta is_all
        #PEEK 0                         ; [module]
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_MODULE
        beq _mod
        jsr _dict                       ; math, os: the keys of their dict
        lda #IT_DICT
        jsr iter_alloc
        jsr list_from_iterable
        bra _have
_mod:   jsr _modsym
        lda #<_all
        ldx #>_all
        jsr intern_cstr
        lda int_ref
        ldx int_ref+1
        jsr mod_sym
        jsr sym_val_addr
        ldz #1
        lda [fp1],z
        tax
        dez
        lda [fp1],z
        cpx #0
        bne +
        cmp #0
        beq _scan
+       inc is_all                      ; __all__: a copy of it
        jsr list_from_iterable
        bra _have
_scan:  lda #0                          ; else its bound hidden names
        sta nitems
        sta nitems+1
        jsr list_new
        #PUSH                           ; [module][names]
        lda #1
        sta is_s
        lda #0
        sta is_s+1
_next:  lda is_s
        cmp nsyms
        lda is_s+1
        sbc nsyms+1
        bcs _scanned
        jsr _public
        bcs +
        #PEEK 0
        sta r0
        stx r0+1
        jsr list_append
+       inc is_s
        bne _next
        inc is_s+1
        bra _next
_scanned:
        #POP
_have:  #PUSH                           ; [module][names]
        lda #0
        sta is_i
        sta is_i+1
_loop:  #PEEK 0
        jsr seq_len
        lda is_i
        cmp t0
        lda is_i+1
        sbc t0+1
        bcs _done
        lda is_i
        sta t2
        lda is_i+1
        sta t2+1
        #PEEK 0
        jsr seq_get_t2
        sta r1
        stx r1+1
        jsr type_of
        cmp #T_STR
        beq +
        lda r1
        ldx r1+1
        jmp raise_need_str
+       lda is_all
        bne +
        lda r1
        ldx r1+1
        jsr str_info
        ldz #0
        lda [fp0],z
        cmp #'_'
        beq _skip
+       #PEEK 1                         ; its value
        sta r0
        stx r0+1
        jsr type_of
        cmp #T_MODULE
        bne +
        jsr module_getattr
        bra _store
+       jsr _dict
        jsr dict_get
        bcs _skip
_store: sta r2
        stx r2+1
        jsr _bind
_skip:  inc is_i
        bne _loop
        inc is_i+1
        bra _loop
_done:  #DROP 2
        jmp clear_rregs

; _dict - r0 = math / os -> r0 = its dict
_dict:  lda r0
        sta p0
        lda r0+1
        sta p0+1
        ldz #8
        lda [p0],z
        sta r0
        inz
        lda [p0],z
        sta r0+1
        rts

; _modsym - r0 = module -> ms_mod = its symbol, is_buf / is_ml = its name
_modsym:
        lda r0
        sta p0
        lda r0+1
        sta p0+1
        ldz #6
        lda [p0],z
        sta ms_mod
        inz
        lda [p0],z
        sta ms_mod+1
        ldz #5
        lda [p0],z
        tax
        dez
        lda [p0],z
        jsr str_info
        ldz #0
-       cpz str_len
        beq +
        cpz #16
        beq +
        tza
        tax
        lda [fp0],z
        sta is_buf,x
        inz
        bra -
+       stz is_ml
        rts

; _public - symbol is_s: "<module>.name", bound, name not starting with '_' -> C clear,
; r1 = name (interned)
_public:
        lda is_s
        ldx is_s+1
        jsr sym_val_addr
        ldz #0
        lda [fp1],z
        inz
        ora [fp1],z
        beq _no
        lda is_s
        ldx is_s+1
        jsr sym_name
        jsr str_info
        lda str_len+1
        bne +
        lda is_ml                       ; longer than "<module>."
        ina
        cmp str_len
        bcs _no
+       ldz #0
-       cpz is_ml
        beq +
        tza
        tax
        lda [fp0],z
        cmp is_buf,x
        bne _no
        inz
        bra -
+       lda [fp0],z
        cmp #'.'
        bne _no
        inz
        lda [fp0],z
        cmp #'_'
        beq _no
        tza                             ; intern what follows the dot
        clc
        adc fp0
        sta fp2
        lda fp0+1
        adc #0
        sta fp2+1
        lda fp0+2
        adc #0
        sta fp2+2
        lda fp0+3
        adc #0
        sta fp2+3
        tza
        eor #$ff
        sec
        adc str_len
        sta str_len
        lda str_len+1
        sbc #0
        sta str_len+1
        jsr intern
        lda int_ref
        sta r1
        lda int_ref+1
        sta r1+1
        clc
        rts
_no:    sec
        rts

; _bind - r1 = name, r2 = value: bound in the target
_bind:  lda r1
        ldx r1+1
        jsr str_info
        lda fp0
        sta fp2
        lda fp0+1
        sta fp2+1
        lda fp0+2
        sta fp2+2
        lda #0
        sta fp2+3
        jsr intern                      ; A/X = its plain symbol
        ldy c_mod
        phy
        ldy c_mod+1
        phy
        ldy is_tgt
        sty c_mod
        ldy is_tgt+1
        sty c_mod+1
        jsr gsym                        ; (target 0: the plain symbol)
        ply
        sty c_mod+1
        ply
        sty c_mod
        jsr sym_val_addr
        ldz #0
        lda r2
        sta [fp1],z
        inz
        lda r2+1
        sta [fp1],z
        rts
_all:   .null "__all__"
