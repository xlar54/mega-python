"""Copy examples/*.py, tests/*.py and lib/*.py into target/py/ as MEGA65 PRG files.
The modules in lib/ become lib-<name>.py (the disk has no directories; import <name>
looks for <name>.py, then lib-<name>.py). tests/support/ holds modules the tests
import (plain <name>.py).

The interpreter loads a .py file with the KERNAL, which skips a 2-byte load address, so
each file gets one ($0000) in front of its plain ASCII text. Line ends become LF.
Names are lower-cased (c1541 turns lower-case ASCII into PETSCII the interpreter
expects) and must fit the 16-character CBM limit.
"""
import glob
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "target", "py")


# library modules whose lib-<name>.py would be over 16 characters: their short names
# (the same table is in src/file.asm, xm_alias)
ALIASES = {"statistics": "stats", "collections": "colls"}


def main():
    version = open(os.path.join(ROOT, "VERSION"), "rb").read().strip()
    os.makedirs(OUT, exist_ok=True)
    for old in glob.glob(os.path.join(OUT, "*.py")):
        os.remove(old)
    for d in ("examples", "tests", "tests/support", "lib"):
        for src in sorted(glob.glob(os.path.join(ROOT, d, "*.py"))):
            name = os.path.basename(src).lower()
            if d == "lib":
                base = name[:-3]
                name = "lib-" + ALIASES.get(base, base) + ".py"   # (import finds it)
            if len(name) > 16:
                raise SystemExit("%s: name longer than 16 characters" % src)
            text = open(src, "rb").read().replace(b"\r\n", b"\n")
            text = text.replace(b"@VERSION@", version)    # (lib/sys.py)
            if any(b > 126 for b in text):
                raise SystemExit("%s: only ASCII is supported" % src)
            with open(os.path.join(OUT, name), "wb") as f:
                f.write(b"\x00\x00" + text)


if __name__ == "__main__":
    main()
