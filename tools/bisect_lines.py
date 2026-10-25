"""Feed a test file to the REPL one top-level statement at a time (in one Xemu
session) and report the statement after which the machine stops responding.

  python tools/bisect_lines.py tests/t_builtins.py
"""
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xemu_run as X  # noqa: E402


def statements(path):
    block = []
    for line in open(path):
        line = line.rstrip('\n')
        if not line.strip() or line.lstrip().startswith('#'):
            continue
        if line[0] not in ' \t' and block and not line.startswith(('else', 'elif', 'except', 'finally')):
            yield '\n'.join(block)
            block = []
        block.append(line)
    if block:
        yield '\n'.join(block)


def main():
    p = X.start()
    time.sleep(1)
    m = X.Mon()
    m.wait_prompt(30)
    for st in statements(sys.argv[1]):
        text = st + ('\n\n' if '\n' in st or st.rstrip().endswith(':') else '\n')
        try:
            m.type(text)
            ok = m.wait_prompt(20)
            screen = [l for l in m.screen() if l.strip()]
        except Exception as e:
            print('DIED after:\n' + st)
            return
        print('---', st.splitlines()[0][:70])
        print('\n'.join(screen[-3:]))
        if not ok:
            print('NO PROMPT after:\n' + st)
            break
    p.kill()


if __name__ == '__main__':
    main()
