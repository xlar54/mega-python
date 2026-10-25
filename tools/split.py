"""Cut the raw build image (target/image.bin, assembled from $2001) into the two disk files.

  target/mega-python   PRG at $2001: resident part 1 and overlay R (in the window)
  target/mpy-ovl       resident part 2 then overlay C (compiler, lexer, editor), loaded
                       at boot to $50000 and moved into place

The split point is $C000.
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 0x2001
SPLIT = 0xC000


def main():
    img = open(os.path.join(ROOT, "target", "image.bin"), "rb").read()
    cut = SPLIT - BASE
    main_part, ovl = img[:cut], img[cut:]
    if BASE + len(main_part) > 0xF6FF:
        raise SystemExit("the main program is too big to load")
    with open(os.path.join(ROOT, "target", "mega-python"), "wb") as f:
        f.write(bytes([BASE & 0xFF, BASE >> 8]) + main_part)
    with open(os.path.join(ROOT, "target", "mpy-ovl"), "wb") as f:
        f.write(b"\x00\x00" + ovl)
    print("mega-python %d bytes, mpy-ovl %d bytes" % (len(main_part), len(ovl)))


if __name__ == "__main__":
    main()
