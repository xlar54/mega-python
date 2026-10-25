"""Make the two disk files from the two build passes.

  target/image.bin  (pass 1, from $2001) -> target/mega-python.prg: resident part 1,
                    overlay R (in the window) and resident part 2 (at $D000)
  target/image2.bin (pass 2)             -> target/mpy-ovl: overlay C (compiler, lexer,
                    editor), loaded at boot to $50000 and kept in attic
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 0x2001


def main():
    main_part = open(os.path.join(ROOT, "target", "image.bin"), "rb").read()
    ovl = open(os.path.join(ROOT, "target", "image2.bin"), "rb").read()
    if BASE + len(main_part) > 0xF6FF:
        raise SystemExit("the main program is too big to load")
    with open(os.path.join(ROOT, "target", "mega-python.prg"), "wb") as f:
        f.write(bytes([BASE & 0xFF, BASE >> 8]) + main_part)
    with open(os.path.join(ROOT, "target", "mpy-ovl"), "wb") as f:
        f.write(b"\x00\x00" + ovl)
    print("mega-python.prg %d bytes, mpy-ovl %d bytes" % (len(main_part), len(ovl)))


if __name__ == "__main__":
    main()
