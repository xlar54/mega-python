"""Disassemble MEGA65 Python bytecode (for debugging): opcodes from src/opcodes.asm."""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_ops():
    names, lens = {}, []
    src = open(os.path.join(ROOT, 'src', 'opcodes.asm')).read()
    for m in re.finditer(r'^OP_(\w+)\s*=\s*(\d+)', src, re.M):
        names[int(m.group(2))] = m.group(1)
    body = src[src.index('op_len:'):]
    for m in re.finditer(r'\.byte ([^;\n]+)', body):
        for v in m.group(1).split(','):
            v = v.strip()
            lens.append(int(v[1:], 16) if v.startswith('$') else int(v))
    return names, lens


def disasm(code, base):
    names, lens = load_ops()
    i = 0
    out = []
    while i < len(code):
        op = code[i]
        n = lens[op] & 0x7f if op < len(lens) else 0
        args = code[i + 1:i + 1 + n]
        if n in (2,) or (n > 2 and op != 59):
            a = ' '.join('%02x' % b for b in args)
        else:
            a = ' '.join('%02x' % b for b in args)
        txt = names.get(op, '?%02x' % op)
        if n == 2:
            a = '$%04x' % (args[0] | args[1] << 8) if len(args) == 2 else a
        out.append('%04x  %-18s %s' % (base + i, txt, a))
        if op == 0 and i > 0:
            pass
        i += 1 + n
    return out
