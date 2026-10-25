"""Run the Python test scripts (tests/*.py) on MEGA65 Python in headless Xemu.

Each test's expected output is what desktop CPython prints for the same file. One Xemu
session runs them all: for each test, load('name') then run(), then the output is read
back from the interpreter's output transcript in attic RAM and compared.

  python tools/run_tests.py            all tests
  python tools/run_tests.py t_lists    just the named ones
  -v                                   show the full output of failing tests
  --show                               run Xemu in a window (watch the tests run)

Exit status 0 when everything passed.
"""
import difflib
import glob
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import xemu_run as X  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def expected(path):
    r = subprocess.run([sys.executable, path], capture_output=True, text=True, timeout=60)
    return r.stdout


def log_end(m):
    p = m.peek(X.LABELS['log_fp'], 4)
    return p[0] | p[1] << 8 | p[2] << 16 | p[3] << 24


def log_read(m, start, end):
    if end <= start:
        return ''
    return bytes(m.peek(start, end - start)).decode('ascii', errors='replace')


def run_one(m, name, timeout):
    m.type("load('%s')\\n" % name)
    if not m.wait_prompt(30):
        return None, 'load timed out'
    start = log_end(m)
    m.type('run()\\n')
    time.sleep(0.5)
    if not m.wait_prompt(timeout):
        return log_read(m, start, log_end(m)), 'run timed out'
    out = log_read(m, start, log_end(m))
    # drop the echoed "run()" line and the final prompt
    if out.startswith('run()\n'):
        out = out[len('run()\n'):]
    if out.endswith('>>> '):
        out = out[:-4]
    return out, None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('-')]
    verbose = '-v' in sys.argv
    if '--show' in sys.argv:
        X.SHOW = True
    files = sorted(glob.glob(os.path.join(ROOT, 'tests', '*.py')))
    if args:
        # named tests may also be examples (those that do not read input)
        files += sorted(glob.glob(os.path.join(ROOT, 'examples', '*.py')))
        files = [f for f in files if os.path.splitext(os.path.basename(f))[0] in args]
    p = X.start()
    m = None
    passed = failed = 0
    try:
        time.sleep(1)
        m = X.Mon()
        if not m.wait_prompt(60):
            print('the interpreter did not reach the prompt')
            print('\n'.join(m.screen()))
            return 1
        for f in files:
            name = os.path.splitext(os.path.basename(f))[0]
            want = expected(f)
            got, err = run_one(m, name, 60)
            if err is None and got == want:
                passed += 1
                print('PASS', name)
                continue
            failed += 1
            print('FAIL', name, err or '')
            if got is not None:
                diff = difflib.unified_diff(want.splitlines(), got.splitlines(),
                                            'cpython', 'mega65', lineterm='', n=1)
                lines = list(diff)
                print('\n'.join(lines if verbose else lines[:40]))
            if err:
                print('\n'.join(m.screen()))
                # try to get back to a prompt for the next test
                m.type('\\s')
                m.wait_prompt(10)
    finally:
        if m:
            X.stop(p, m)
        elif p.poll() is None:
            p.kill()
    print('%d passed, %d failed' % (passed, failed))
    return 0 if failed == 0 else 1


if __name__ == '__main__':
    sys.exit(main())
