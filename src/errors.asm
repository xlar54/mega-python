;=======================================================================================
; Exceptions. Built-in exception classes are ordinary T_CLASS objects; an exception is
; a T_INST whose dict holds 'args' (a tuple).
;=======================================================================================
EXC_BASE        = 0
EXC_EXCEPTION   = 1
EXC_TYPE        = 2
EXC_VALUE       = 3
EXC_NAME        = 4
EXC_INDEX       = 5
EXC_KEY         = 6
EXC_ZERODIV     = 7
EXC_ATTR        = 8
EXC_OVERFLOW    = 9
EXC_MEMORY      = 10
EXC_STOPITER    = 11
EXC_RUNTIME     = 12
EXC_SYNTAX      = 13
EXC_KEYBOARD    = 14
EXC_ASSERT      = 15
EXC_NOTIMPL     = 16
EXC_INDENT      = 17
EXC_UNBOUND     = 18
EXC_RECURSION   = 19
EXC_LOOKUP      = 20
EXC_ARITH       = 21
EXC_IMPORT      = 22
EXC_OS          = 23
EXC_EOF         = 24
EXC_SYSTEM      = 25
EXC_SYSEXIT     = 26
EXC_FILENOTFOUND = 27
EXC_N           = 28

exc_cls_lo:     .fill EXC_N
exc_cls_hi:     .fill EXC_N
mem_error:      .word 0                 ; preallocated MemoryError instance

RAISE   .macro cls, msg
        jsr raise_inline
        .byte \cls
        .text \msg, 0
        .endm

;---------------------------------------------------------------------------------------
; exc_new - A = class id, r1 = message object (or 0 for no args) -> A/X instance
;---------------------------------------------------------------------------------------
exc_new_empty:
        ldx #0
        stx r1
        stx r1+1
exc_new:
        tax
        lda exc_cls_lo,x
        sta r2
        lda exc_cls_hi,x
        sta r2+1
; exc_new_cls - r2 = class, r1 = message or 0 -> A/X instance
exc_new_cls:
        lda #0
        sta nitems+1
        lda r1+1
        ora r1
        beq +
        lda #1
+       sta nitems
        jsr tuple_new
        lda nitems
        beq +
        ldz #6
        lda r1
        sta [p0],z
        inz
        lda r1+1
        sta [p0],z
+       lda p0
        sta r1
        lda p0+1
        sta r1+1
; inst_with_args - r2 = class, r1 = args tuple -> A/X instance with .args
inst_with_args:
        lda #8
        sta alloc_size
        lda #0
        sta alloc_size+1
        lda #T_INST
        jsr alloc
        ldz #4
        lda r2
        sta [p0],z
        inz
        lda r2+1
        sta [p0],z
        lda p0
        sta r3
        lda p0+1
        sta r3+1
        jsr dict_new
        sta r0
        stx r0+1
        lda r3
        sta p0
        lda r3+1
        sta p0+1
        ldz #6
        lda r0
        sta [p0],z
        inz
        lda r0+1
        sta [p0],z
        lda r1
        sta r2
        lda r1+1
        sta r2+1
        lda #<S_ARGS
        ldx #>S_ARGS
        jsr sym_name
        sta r1
        stx r1+1
        lda r3
        pha
        lda r3+1
        pha
        jsr dict_set
        pla
        tax
        pla
        rts

;---------------------------------------------------------------------------------------
; raising from native code
;---------------------------------------------------------------------------------------
; RAISE macro: jsr raise_inline / class byte / message
raise_inline:
        pla
        sta t7
        pla
        sta t7+1
        inw t7
        ldy #0
        lda (t7),y
        pha
        inw t7
        jsr sb_mark_t5
        lda t7
        ldx t7+1
        jsr sb_puts
        pla
; raise_sb - A = class id, message = the string builder from mark t5
raise_sb:
        pha
        lda t5
        ldx t5+1
        jsr sb_take
        sta r1
        stx r1+1
        pla
        jsr exc_new
raise_obj:
        sta cur_exc
        stx cur_exc+1
        lda #0
        sta exc_ip_set
        jsr clear_rregs
        jmp throw

; A = class id, r1 = message object
raise_with_obj:
        jsr exc_new
        bra raise_obj

raise_memory:
        lda mem_error
        ldx mem_error+1
        bne raise_obj
        jmp fatal_oom                   ; out of memory before the instance exists

raise_recursion:
        #RAISE EXC_RECURSION, "maximum recursion depth exceeded"

raise_unbound:
        #RAISE EXC_UNBOUND, "local variable referenced before assignment"

; NameError for the symbol in vtmp
raise_name_vtmp:
        jsr sb_mark_t5
        #SBPRINT "name '"
        lda vtmp
        ldx vtmp+1
        jsr sym_name
        jsr sb_put_str
        #SBPRINT "' is not defined"
        lda #EXC_NAME
        jmp raise_sb

sb_mark_t5:
        lda sbp
        sta t5
        lda sbp+1
        sta t5+1
        rts

; "'<type>' object is not callable" for A/X
raise_not_callable:
        pha
        phx
        jsr sb_mark_t5
        lda #"'"
        jsr sb_putc
        plx
        pla
        jsr sb_type_name
        #SBPRINT "' object is not callable"
        lda #EXC_TYPE
        jmp raise_sb

raise_arg_count:
        jsr sb_mark_t5
        lda c_func
        ldx c_func+1
        sta p0
        stx p0+1
        ldz #9
        lda [p0],z
        tax
        dez
        lda [p0],z
        jsr sb_put_str
        #SBPRINT "() got the wrong number of arguments"
        lda #EXC_TYPE
        jmp raise_sb

raise_multiple:
        #RAISE EXC_TYPE, "got multiple values for an argument"
raise_unexpected_kw:
        #RAISE EXC_TYPE, "got an unexpected keyword argument"
raise_no_init_args:
        #RAISE EXC_TYPE, "this class takes no arguments"

raise_binop_types:
        jsr sb_mark_t5
        #SBPRINT "unsupported operand type(s) for "
        ldx bop
        lda bop_name_ofs,x
        clc
        adc #<bop_names
        pha
        lda #>bop_names
        adc #0
        tax
        pla
        jsr sb_puts
        #SBPRINT ": '"
        lda r2
        ldx r2+1
        jsr sb_type_name
        #SBPRINT "' and '"
        lda r3
        ldx r3+1
        jsr sb_type_name
        lda #"'"
        jsr sb_putc
        lda #EXC_TYPE
        jmp raise_sb

raise_cmp_types:
        jsr sb_mark_t5
        #SBPRINT "comparison not supported between instances of '"
        lda r2
        ldx r2+1
        jsr sb_type_name
        #SBPRINT "' and '"
        lda r3
        ldx r3+1
        jsr sb_type_name
        lda #"'"
        jsr sb_putc
        lda #EXC_TYPE
        jmp raise_sb

raise_unary_type:
        jsr sb_mark_t5
        #SBPRINT "bad operand type for unary operator: '"
        lda r2
        ldx r2+1
        jsr sb_type_name
        lda #"'"
        jsr sb_putc
        lda #EXC_TYPE
        jmp raise_sb

raise_need_int:
        #RAISE EXC_TYPE, "an integer is required"
raise_need_str:
        #RAISE EXC_TYPE, "a string is required"
raise_index:
        #RAISE EXC_INDEX, "index out of range"
; raise_index_of - A/X = the sequence: "list/tuple index out of range"
raise_index_of:
        jsr type_of
        cmp #T_TUPLE
        beq +
        #RAISE EXC_INDEX, "list index out of range"
+       #RAISE EXC_INDEX, "tuple index out of range"
raise_args:
        #RAISE EXC_TYPE, "wrong number of arguments"

; KeyError with the key r1
raise_key:
        lda #EXC_KEY
        jmp raise_with_obj

; AttributeError: '<type>' object has no attribute '<r1 name>'
raise_attr:
        jsr sb_mark_t5
        lda #"'"
        jsr sb_putc
        lda r0
        ldx r0+1
        jsr sb_type_name
        #SBPRINT "' object has no attribute '"
        lda r1
        ldx r1+1
        jsr sb_put_str
        lda #"'"
        jsr sb_putc
        lda #EXC_ATTR
        jmp raise_sb

; syntax_error / indent_error: jsr, then the message (zero-terminated)
syntax_error:
        lda #EXC_SYNTAX
        bra +
indent_error:
        lda #EXC_INDENT
+       sta t6
        pla
        sta t7
        pla
        sta t7+1
        inw t7
        jsr sb_mark_t5
        lda t7
        ldx t7+1
        jsr sb_puts
        #SBPRINT " (line "
        lda lx_line
        sta acc
        lda lx_line+1
        sta acc+1
        lda #0
        sta acc+2
        sta acc+3
        jsr sb_int
        lda #')'
        jsr sb_putc
        lda t6
        jmp raise_sb

; sb_type_name - append the type name of A/X
sb_type_name:
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
        .word tn_none, tn_bool, tn_slice, tn_super
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
; make_exception - raise X: X may be a class (instantiate it) or an instance
;---------------------------------------------------------------------------------------
make_exception:
        sta r2
        stx r2+1
        jsr type_of
        cmp #T_CLASS
        beq _cls
        cmp #T_INST
        beq _ok
        #RAISE EXC_TYPE, "exceptions must derive from BaseException"
_cls:   lda #0
        sta r1
        sta r1+1
        jmp exc_new_cls
_ok:    lda r2
        ldx r2+1
        rts

;---------------------------------------------------------------------------------------
; print_exception - print cur_exc: the line it was raised at, then "Name: message"
;---------------------------------------------------------------------------------------
print_exception:
        jsr scr_fresh_line
        lda #COL_ERROR
        sta scr_color
        lda cur_exc
        ldx cur_exc+1
        sta r2
        stx r2+1
        ; syntax errors carry their own line; others: look the ip up
        lda #EXC_SYNTAX
        jsr exc_is
        bcs _msg
        lda exc_ip
        ldx exc_ip+1
        jsr line_of_ip
        bcs _msg
        pha
        phx
        #PRINT "Traceback: line "
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
        jsr sb_flush
        lda #10
        jsr putc
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

; exc_is - is r2 (an instance) an instance of exception class id A? -> C set
exc_is:
        tax
        lda exc_cls_lo,x
        sta r3
        lda exc_cls_hi,x
        sta r3+1
        jmp isinstance_r2_r3

; line_of_ip - code offset A/X -> A/X = line (C clear), C set if unknown.
; The line table holds (offset, line) pairs in code order; take the last offset < ip.
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

fatal_oom:
        jsr scr_fresh_line
        #PRINT "out of memory"
        jmp repl_restart
