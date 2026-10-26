"""Make the two disk files from the two build passes.

  target/image.bin  (pass 1, from $2001) -> target/mega-python.prg: resident part 1,
                    overlay R (in the window) and resident part 2 (at $D000)
  target/image2.bin (pass 2)             -> target/mpy-ovl: overlay C (compiler, lexer,
                    editor) and the first 10 tails, and target/mpy-ov2: the tails after
                    them; each loaded at boot to $50000 (64 KB at most) and kept in attic
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 0x2001
FIRST = 0x5000 + 10 * 0x1000          # overlay C and tails B ... N (resident.asm: TAILS_1)


def main():
    main_part = open(os.path.join(ROOT, "target", "image.bin"), "rb").read()
    ovl = open(os.path.join(ROOT, "target", "image2.bin"), "rb").read()
    if BASE + len(main_part) > 0xF6FF:
        raise SystemExit("the main program is too big to load")
    with open(os.path.join(ROOT, "target", "mega-python.prg"), "wb") as f:
        f.write(bytes([BASE & 0xFF, BASE >> 8]) + main_part)
    with open(os.path.join(ROOT, "target", "mpy-ovl"), "wb") as f:
        f.write(b"\x00\x00" + ovl[:FIRST])
    with open(os.path.join(ROOT, "target", "mpy-ov2"), "wb") as f:
        f.write(b"\x00\x00" + ovl[FIRST:])
    print("mega-python.prg %d bytes, mpy-ovl %d bytes, mpy-ov2 %d bytes"
          % (len(main_part), min(len(ovl), FIRST), max(len(ovl) - FIRST, 0)))


if __name__ == "__main__":
    main()
