"""Find the shortest prefix of a program whose run() kills or hangs the interpreter.
The source is poked straight into SRC (attic) instead of loading it from disk.

  python tools/bisect_run.py tests/t_builtins.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xemu_run as X  # noqa: E402

SRC = 0x8100000


def run_prefix(lines):
    text = ('\n'.join(lines) + '\n').encode() + b'\0'
    p = X.start()
    try:
        time.sleep(1)
        m = X.Mon()
        m.wait_prompt(30)
        m.poke(SRC, list(text))
        n = len(text) - 1
        m.poke(X.LABELS['src_len'], [n & 0xFF, n >> 8])
        m.type('run()\n')
        time.sleep(0.5)
        ok = m.wait_prompt(30)
        screen = [l for l in m.screen() if l.strip()]
        return ok, screen
    except Exception:
        return False, ['(Xemu died)']
    finally:
        p.kill()
        time.sleep(0.5)


def main():
    lines = open(sys.argv[1]).read().splitlines()
    lo, hi = 0, len(lines)            # prefix of hi lines fails (assumed), lo works
    ok, screen = run_prefix(lines)
    if ok:
        print('the whole file runs:')
        print('\n'.join(screen[-6:]))
        return
    while hi - lo > 1:
        mid = (lo + hi) // 2
        ok, _ = run_prefix(lines[:mid])
        print('%3d lines: %s' % (mid, 'ok' if ok else 'FAIL'))
        if ok:
            lo = mid
        else:
            hi = mid
    print('fails when line %d is added:\n%s' % (hi, lines[hi - 1]))
    print('\n'.join(run_prefix(lines[:hi])[1][-6:]))


if __name__ == '__main__':
    main()
