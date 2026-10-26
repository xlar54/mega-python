;=======================================================================================
; Bytecode. One opcode byte, then operands (words little-endian). Jump targets are
; absolute code offsets in the bytecode bank.
;=======================================================================================
OP_HALT         = 0
OP_NOP          = 1
OP_CONST        = 2                     ; w ref
OP_LOAD_FAST    = 3                     ; b stack offset
OP_STORE_FAST   = 4                     ; b
OP_LOAD_GLOBAL  = 5                     ; w sym
OP_STORE_GLOBAL = 6                     ; w sym
OP_LOAD_ATTR    = 7                     ; w sym          obj -> val
OP_STORE_ATTR   = 8                     ; w sym          obj val ->
OP_LOAD_SUBSCR  = 9                     ;                obj key -> val
OP_STORE_SUBSCR = 10                    ;                obj key val ->
OP_POP          = 11
OP_DUP          = 12
OP_DUP2         = 13                    ; a b -> a b a b
OP_ROT2         = 14                    ; a b -> b a
OP_ROT3         = 15                    ; a b c -> c a b (TOS moves down two)
OP_ADD          = 16                    ; 16-27: binary ops in TK_PLUS order
OP_SUB          = 17
OP_MUL          = 18
OP_TRUEDIV      = 19
OP_FLOORDIV     = 20
OP_MOD          = 21
OP_POW          = 22
OP_LSHIFT       = 23
OP_RSHIFT       = 24
OP_AND          = 25
OP_OR           = 26
OP_XOR          = 27
OP_IADD         = 28                    ; += (extends lists in place)
OP_NEG          = 29
OP_POS          = 30
OP_NOT          = 31
OP_INVERT       = 32
OP_EQ           = 33                    ; 33-38: comparisons in TK_EQ order
OP_NE           = 34
OP_LT           = 35
OP_GT           = 36
OP_LE           = 37
OP_GE           = 38
OP_IN           = 39
OP_NOT_IN       = 40
OP_IS           = 41
OP_IS_NOT       = 42
OP_JUMP         = 43                    ; w target
OP_JUMP_IF_FALSE = 44                   ; w   pops
OP_JUMP_IF_TRUE = 45                    ; w   pops
OP_JUMP_IF_FALSE_OR_POP = 46            ; w
OP_JUMP_IF_TRUE_OR_POP = 47             ; w
OP_GET_ITER     = 48
OP_FOR_ITER     = 49                    ; w exit target
OP_BUILD_LIST   = 50                    ; w n
OP_BUILD_TUPLE  = 51                    ; w n
OP_BUILD_DICT   = 52                    ; w pairs
OP_CALL         = 53                    ; b argc
OP_CALL_KW      = 54                    ; b argc, w kwnames tuple
OP_LOAD_METHOD  = 55                    ; w sym   obj -> meth self | callable NULL
OP_CALL_METHOD  = 56                    ; b argc
OP_CALL_METHOD_KW = 57                  ; b argc, w kwnames
OP_RETURN       = 58
OP_MAKE_FUNCTION = 59                   ; w code, b nargs, b nlocals, w name, b ndefaults, w params, b flags, b nkwonly
OP_MAKE_CLASS   = 60                    ; w name ref      base -> cls
OP_STORE_CLASSATTR = 61                 ; w sym           cls val -> cls
OP_UNPACK       = 62                    ; b n
OP_SETUP_EXCEPT = 63                    ; w handler
OP_POP_BLOCK    = 64
OP_EXC_MATCH    = 65                    ;                 exc cls -> bool
OP_RAISE        = 66                    ; b 0 reraise, 1 raise TOS, 2 raise TOS from TOS1
OP_POP_EXCEPT   = 67
OP_PRINT_EXPR   = 68
OP_FORMAT       = 69                    ; b 0 str, 1 repr; w format spec ref (0 = none)
OP_BUILD_STRING = 70                    ; w n
OP_BUILD_SLICE  = 71                    ; b 2 or 3
OP_DELETE_FAST  = 72                    ; b
OP_DELETE_GLOBAL = 73                   ; w sym
OP_DELETE_SUBSCR = 74
OP_DELETE_ATTR  = 75                    ; w sym
OP_LIST_APPEND  = 76                    ; b depth (stack slots below TOS)
OP_MAP_ADD      = 77                    ; b depth           key val ->
OP_ASSERT_FAIL  = 78                    ; b has message
OP_IMPORT       = 79                    ; w sym
OP_LOAD_SUPER   = 80                    ; w class sym  (self in local slot b)  b offset
OP_BUILD_SET    = 81                    ; w n
OP_SET_ADD      = 82                    ; b depth
OP_LIFT3        = 83                    ; a b c -> b c a (the third comes up)
OP_LOAD_DEREF   = 84                    ; b depth, b cell: a captured variable (env.asm)
OP_STORE_DEREF  = 85                    ; b depth, b cell
OP_ENTER_ENV    = 86                    ; b cells: the function's environment (prologue)
OP_SET_CLOSURE  = 87                    ; func -> func (it captures the frame's env)
OP_LOAD_CLASSNAME = 88                  ; w sym: in a class body: the class's, else global
OP_END_CLASS    = 89                    ; the end of a class body (MAKE_CLASS started it)
OP_PACK_ARGS    = 90                    ; b npos, w names: a * / ** call's list and dict
OP_EX_ARG       = 91                    ; b kind: one more argument into them (args.asm)
OP_CALL_EX      = 92                    ; b method: the call (names left under it)
OP_YIELD_VALUE  = 93                    ; value -> sent value (gen.asm)
OP_SEND         = 94                    ; w exit   it value -> it next | result (yield from)
OP_COUNT        = 95

; operand bytes per opcode, bit 7 = has a jump target (word at +1)
op_len:
        .byte 0, 0, 2, 1, 1, 2, 2, 2, 2, 0      ; 0-9
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0      ; 10-19
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0      ; 20-29
        .byte 0, 0, 0, 0, 0, 0, 0, 0, 0, 0      ; 30-39
        .byte 0, 0, 0, $82, $82, $82, $82, $82, 0, $82 ; 40-49
        .byte 2, 2, 2, 1, 3, 2, 1, 3, 0, 11     ; 50-59
        .byte 2, 2, 1, $82, 0, 0, 1, 0, 0, 3    ; 60-69
        .byte 2, 1, 1, 2, 0, 2, 1, 1, 1, 2      ; 70-79
        .byte 3, 2, 1, 0, 2, 2, 1, 0, 2, 0      ; 80-89
        .byte 3, 1, 1, 0, $82                   ; 90-94
