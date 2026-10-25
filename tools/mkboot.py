"""Write target/autoboot.c65: a one-line BASIC 65 boot program that runs the interpreter.

    10 RUN "MEGA-PYTHON"

The MEGA65 loads and runs AUTOBOOT.C65 when it boots with the disk mounted (and Xemu
-autoload runs the first file on the disk, which is this one). The name is written the
way c1541 stores lower-case ASCII names: as unshifted PETSCII ($41-$5A).
"""
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASIC_START = 0x2001
TOKEN_RUN = 0x8A
PROGRAM = "mega-python"


def petscii(name):
    # c1541 turns lower-case ASCII into unshifted PETSCII letters
    return bytes(ord(c) - 0x20 if 'a' <= c <= 'z' else ord(c) for c in name)


def main():
    body = bytes([10, 0, TOKEN_RUN]) + b'"' + petscii(PROGRAM) + b'"' + b'\0'
    nxt = BASIC_START + 2 + len(body)          # the address after this line
    line = bytes([nxt & 0xFF, nxt >> 8]) + body
    prg = bytes([BASIC_START & 0xFF, BASIC_START >> 8]) + line + b'\0\0'
    with open(os.path.join(ROOT, 'target', 'autoboot.c65'), 'wb') as f:
        f.write(prg)


if __name__ == '__main__':
    main()
