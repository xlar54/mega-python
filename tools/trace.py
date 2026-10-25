"""Single-step the interpreter in Xemu and print each instruction with its nearest label.

  python tools/trace.py hold STEPS "repl line" ["repl line" ...]

Every line but the last is typed and run first (| = newline inside a line). Then the
interpreter's DBG_HOLD points are armed (dbg_hold = $80), the last line is typed, and
once the CPU spins in a hold it is stopped (monitor 't1'), released and stepped STEPS
instructions ('t'). Xemu's own breakpoint command did not stop the CPU in testing, so
hold points (the DBG_HOLD macro in vm.asm) are used instead.
"""
import bisect
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xemu_run as X  # noqa: E402

L = X.LABELS
ADDRS = sorted((v, k) for k, v in L.items() if v < 0x10000 and not k.startswith('_'))
KEYS = [a for a, _ in ADDRS]


def near(pc):
    i = bisect.bisect_right(KEYS, pc) - 1
    if i < 0:
        return '?'
    a, k = ADDRS[i]
    return '%s+%x' % (k, pc - a)


def regs(text):
    for line in text.splitlines():
        if len(line) > 4 and all(c in '0123456789ABCDEF' for c in line[:4]):
            return line
    return ''


def main():
    steps = int(sys.argv[2])
    lines = sys.argv[3:]
    p = X.start()
    try:
        time.sleep(1)
        m = X.Mon()
        m.wait_prompt(30)
        for l in lines[:-1]:
            m.type(l.replace('|', '\n') + '\n')
            m.wait_prompt(15)
        m.poke(L['dbg_hold'], [0x80])
        m.type(lines[-1].replace('|', '\n') + '\n')
        held = False
        for _ in range(400):
            time.sleep(0.05)
            if m.peek(L['dbg_hold'], 1)[0] == 0x80:
                r = regs(m.cmd('r'))
                pc = int(r[:4], 16) if r else 0
                if near(pc).startswith('vm_except'):
                    held = True
                    break
        if not held:
            print('the hold point was not reached')
            return
        m.cmd('t1')
        m.poke(L['dbg_hold'], [0])
        for _ in range(steps):
            r = regs(m.cmd('t'))
            if not r:
                print('no response')
                break
            pc = int(r[:4], 16)
            print('%-28s %s' % (near(pc), r))
    finally:
        p.kill()


if __name__ == '__main__':
    main()
