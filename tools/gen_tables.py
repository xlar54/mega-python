"""Generate src/gen/tables.asm: the fixed symbol table and the builtin tables.

Symbols are interned at boot in this order, so their ids are assembly-time constants:
keywords first (the lexer turns symbol n < NKEYWORDS into keyword token TK_KW + n),
then special names, then the names of builtin functions and methods.

Each builtin is a native routine bi_<label> in src/builtins.asm. Kinds:
  f  global function            t  global type (callable, also what type() returns)
  T  type, not a global name    m  method of the named type     M  function of the math module
  O  function of the os module    P  function of os.path
  -  internal (no global binding)
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KEYWORDS = """False None True and as assert break class continue def del elif else except
finally for from global if import in is lambda nonlocal not or pass raise return try
while with yield""".split()

SPECIAL = """__init__ __str__ __repr__ args __name__ __class__ __eq__ __lt__ __le__ __gt__
__ge__ __ne__ __enter__ __exit__ __len__ __bool__ __getitem__ __setitem__ __iter__ __next__ __contains__
__call__ __add__ __sub__ __mul__ __truediv__ __floordiv__ __mod__ __pow__ __lshift__
__rshift__ __and__ __or__ __xor__ __iadd__ __radd__ __rsub__ __rmul__ __neg__ __pos__
__invert__ __hash__ self super __main__ __dict__ sep end key reverse file flush""".split()

# (python name, label, kind, owner type for methods)
BUILTINS = [
    ("print", "print", "f"), ("len", "len", "f"), ("range", "range", "t"),
    ("input", "input", "f"), ("int", "int", "t"), ("str", "str", "t"),
    ("repr", "repr", "f"), ("abs", "abs", "f"), ("min", "min", "f"), ("max", "max", "f"),
    ("sum", "sum", "f"), ("chr", "chr", "f"), ("ord", "ord", "f"),
    ("list", "list", "t"), ("tuple", "tuple", "t"), ("dict", "dict", "t"),
    ("bool", "bool", "t"), ("type", "type", "t"), ("isinstance", "isinstance", "f"),
    ("sorted", "sorted", "f"), ("enumerate", "enumerate", "f"), ("zip", "zip", "f"),
    ("hex", "hex", "f"), ("bin", "bin", "f"), ("oct", "oct", "f"),
    ("divmod", "divmod", "f"), ("pow", "pow", "f"), ("iter", "iter", "f"),
    ("next", "next", "f"), ("reversed", "reversed", "f"), ("any", "any", "f"),
    ("all", "all", "f"), ("hash", "hash", "f"), ("format", "format", "f"), ("id", "id", "f"),
    ("callable", "callable", "f"), ("getattr", "getattr", "f"),
    ("setattr", "setattr", "f"), ("hasattr", "hasattr", "f"), ("map", "map", "f"),
    ("filter", "filter", "f"), ("round", "round", "f"), ("object", "object", "t"),
    ("super", "super", "f"), ("exit", "exit", "f"), ("quit", "exit", "f"),
    ("float", "float", "t"), ("open", "open", "f"), ("TextIOWrapper", "filetype", "T"),
    ("NoneType", "nonetype", "T"), ("function", "functype", "T"),
    ("__init__", "exc_init", "-"),
    # MEGA65 / environment
    ("run", "run", "f"), ("edit", "edit", "f"), ("new", "new", "f"),
    ("load", "load", "f"), ("save", "save", "f"), ("files", "files", "f"),
    ("cls", "cls", "f"), ("peek", "peek", "f"), ("poke", "poke", "f"),
    ("mem", "mem", "f"), ("help", "help", "f"), ("gc", "gc", "f"),
    # the math module
    ("sqrt", "m_sqrt", "M"), ("floor", "m_floor", "M"), ("ceil", "m_ceil", "M"),
    ("trunc", "m_trunc", "M"), ("fabs", "m_fabs", "M"), ("isnan", "m_isnan", "M"),
    ("isinf", "m_isinf", "M"), ("isfinite", "m_isfinite", "M"), ("exp", "m_exp", "M"),
    ("log", "m_log", "M"), ("log10", "m_log10", "M"), ("log2", "m_log2", "M"),
    ("pow", "m_pow", "M"), ("sin", "m_sin", "M"), ("cos", "m_cos", "M"),
    ("tan", "m_tan", "M"), ("asin", "m_asin", "M"), ("acos", "m_acos", "M"),
    ("atan", "m_atan", "M"), ("atan2", "m_atan2", "M"), ("degrees", "m_degrees", "M"),
    ("radians", "m_radians", "M"), ("hypot", "m_hypot", "M"),
    ("copysign", "m_copysign", "M"), ("fmod", "m_fmod", "M"),
    # the os module, and os.path
    ("remove", "os_remove", "O"), ("unlink", "os_remove", "O"), ("rename", "os_rename", "O"),
    ("listdir", "os_listdir", "O"), ("exists", "os_exists", "P"),
    # file methods
    ("read", "file_read", "m", "file"), ("readline", "file_readline", "m", "file"),
    ("readlines", "file_readlines", "m", "file"), ("write", "file_write", "m", "file"),
    ("close", "file_close", "m", "file"), ("__enter__", "file_enter", "m", "file"),
    ("__exit__", "file_exit", "m", "file"),
    # list methods
    ("append", "list_append", "m", "list"), ("pop", "list_pop", "m", "list"),
    ("insert", "list_insert", "m", "list"), ("remove", "list_remove", "m", "list"),
    ("index", "list_index", "m", "list"), ("count", "list_count", "m", "list"),
    ("extend", "list_extend", "m", "list"), ("reverse", "list_reverse", "m", "list"),
    ("sort", "list_sort", "m", "list"), ("copy", "list_copy", "m", "list"),
    ("clear", "list_clear", "m", "list"),
    # tuple methods
    ("index", "list_index", "m", "tuple"), ("count", "list_count", "m", "tuple"),
    # str methods
    ("upper", "str_upper", "m", "str"), ("lower", "str_lower", "m", "str"),
    ("split", "str_split", "m", "str"), ("join", "str_join", "m", "str"),
    ("strip", "str_strip", "m", "str"), ("lstrip", "str_lstrip", "m", "str"),
    ("rstrip", "str_rstrip", "m", "str"), ("find", "str_find_m", "m", "str"),
    ("replace", "str_replace", "m", "str"), ("startswith", "str_startswith", "m", "str"),
    ("endswith", "str_endswith", "m", "str"), ("isdigit", "str_isdigit", "m", "str"),
    ("isalpha", "str_isalpha", "m", "str"), ("isalnum", "str_isalnum", "m", "str"),
    ("isspace", "str_isspace", "m", "str"), ("isupper", "str_isupper", "m", "str"),
    ("islower", "str_islower", "m", "str"), ("count", "str_count", "m", "str"),
    ("index", "str_index", "m", "str"), ("format", "str_format", "m", "str"),
    ("center", "str_center", "m", "str"), ("ljust", "str_ljust", "m", "str"),
    ("rjust", "str_rjust", "m", "str"), ("zfill", "str_zfill", "m", "str"),
    ("title", "str_title", "m", "str"), ("capitalize", "str_capitalize", "m", "str"),
    ("splitlines", "str_splitlines", "m", "str"),
    # dict methods
    ("keys", "dict_keys", "m", "dict"), ("values", "dict_values", "m", "dict"),
    ("items", "dict_items", "m", "dict"), ("get", "dict_get_m", "m", "dict"),
    ("pop", "dict_pop", "m", "dict"), ("setdefault", "dict_setdefault", "m", "dict"),
    ("update", "dict_update", "m", "dict"), ("clear", "dict_clear", "m", "dict"),
    ("copy", "dict_copy", "m", "dict"),
]

OWNERS = ["list", "tuple", "str", "dict", "file"]
# other names the interpreter needs as symbols (modules and their constants)
NAMES = "math pi e tau inf nan os path".split()


def ident(name):
    return name.strip("_").upper() or name


def main():
    syms = []
    for n in KEYWORDS + SPECIAL:
        if n not in syms:
            syms.append(n)
    for b in BUILTINS:
        if b[0] not in syms:
            syms.append(b[0])
    for n in NAMES:
        if n not in syms:
            syms.append(n)
    assert len(KEYWORDS) == 33
    out = [";" + "=" * 86,
           "; GENERATED by tools/gen_tables.py - do not edit",
           ";" + "=" * 86, ""]
    # symbol constants: special names get S_<NAME>, others S_<NAME> too (unique)
    used = {}
    for i, n in enumerate(syms):
        if i < len(KEYWORDS):
            continue
        base = n.strip("_").upper()
        if n.startswith("__"):
            label = "S_" + base
        else:
            label = "S_" + base
            if label in used.values() or base in ("INIT",):
                label = "S_N_" + base
        used[n] = label
        out.append("%-24s= %d" % (label, i))
    out.append("NFIXEDSYMS              = %d" % len(syms))
    out.append("")
    names = ["; GENERATED by tools/gen_tables.py - the fixed symbols' names (tail H)",
             "sym_init_names:"]
    for n in syms:
        names.append('        .text "%s", 0' % n)
    names.append("        .byte 0")
    # builtins
    labels = []
    for i, b in enumerate(BUILTINS):
        name, label, kind = b[0], b[1], b[2]
        owner = b[3] if len(b) > 3 else None
        cname = "B_" + (owner.upper() + "_" if owner else "") + ident(name)
        if kind in "MOP":
            cname = "B_%s_" % {"M": "MATH", "O": "OS", "P": "PATH"}[kind] + ident(name)
        if cname in labels:
            cname += "_%d" % i
        labels.append(cname)
        out.append("%-24s= %d" % (cname, i))
    out.append("NBUILTINS               = %d" % len(BUILTINS))
    out.append("BF_TYPE                 = 1")
    out.append("BF_GLOBAL               = 2")
    out.append("")
    # (byte tables: there are more than 128 builtins)
    for half, op in (("lo", "<"), ("hi", ">")):
        out.append("builtin_tab_%s:" % half)
        for b in BUILTINS:
            out.append("        .byte %sbi_%s" % (op, b[1]))
    for half, op in (("lo", "<"), ("hi", ">")):
        out.append("builtin_name_%s:" % half)
        for b in BUILTINS:
            out.append("        .byte %s%s" % (op, used[b[0]]))
    out.append("builtin_flags:")
    for b in BUILTINS:
        f = 0
        if b[2] == "t":
            f = 3
        elif b[2] == "T":
            f = 1
        elif b[2] == "f":
            f = 2
        out.append("        .byte %d" % f)
    out.append("")
    for owner in OWNERS:
        out.append("meth_%s:" % owner)
        for i, b in enumerate(BUILTINS):
            if len(b) > 3 and b[3] == owner:
                out.append("        .word %s, %d" % (used[b[0]], i))
        out.append("        .word $ffff")
    # the modules' function tables (in the tails that make the modules)
    mods = ["; GENERATED by tools/gen_tables.py - the math module's functions (tail B)",
            "math_funcs:"]
    for i, b in enumerate(BUILTINS):
        if b[2] == "M":
            mods.append("        .word %s, %d" % (used[b[0]], i))
    mods.append("        .word $ffff")
    osf = ["; GENERATED by tools/gen_tables.py - os / os.path functions (tail F):",
           "; symbol, builtin id, 0 = os / 1 = os.path", "os_funcs:"]
    for i, b in enumerate(BUILTINS):
        if b[2] in "OP":
            osf.append("        .word %s" % used[b[0]])
            osf.append("        .byte %d, %d" % (i, b[2] == "P"))
    osf.append("        .word $ffff")
    os.makedirs(os.path.join(ROOT, "src", "gen"), exist_ok=True)
    with open(os.path.join(ROOT, "src", "gen", "tables.asm"), "w") as f:
        f.write("\n".join(out) + "\n")
    with open(os.path.join(ROOT, "src", "gen", "symnames.asm"), "w") as f:
        f.write("\n".join(names) + "\n")
    with open(os.path.join(ROOT, "src", "gen", "mathfuncs.asm"), "w") as f:
        f.write("\n".join(mods) + "\n")
    with open(os.path.join(ROOT, "src", "gen", "osfuncs.asm"), "w") as f:
        f.write("\n".join(osf) + "\n")


if __name__ == "__main__":
    main()
