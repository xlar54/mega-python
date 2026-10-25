"""Headless Xemu test driver.

Boots the project's D81 (target/mega-python.d81, or $MEGA65_D81), runs a script of
monitor actions over the UART-monitor TCP socket, then exits Xemu gracefully so it
writes a screenshot. Labels come from target/mega-python.lbl (or $MEGA65_LBL).

  python tools/xemu_run.py SHOT.png [actions...]

Actions (run in order). ADDR is hex, or a label from the label file with an optional
+hex offset (e.g. dbg_klen, p0+1). 28-bit addresses work (ffd3060 = VIC-IV,
8000000 = attic):
  wait:SECS            sleep (Xemu runs "sleepless", i.e. faster than real time)
  poke:ADDR=B[,B...]   write bytes (hex) with the monitor 's' command
  peek:ADDR[:N]        print N (default 16) bytes from ADDR
  regs                 print CPU registers
  type:TEXT            type TEXT through the interpreter's injection buffer, waiting
                       until it is consumed. Escapes: \\n RETURN, \\e ESC, \\s RUN/STOP,
                       \\5 F5, \\t TAB, \\b DEL, \\u/\\d/\\l/\\r cursor keys, \\\\ backslash
  waitfor:TEXT[:SECS]  wait until TEXT appears on the screen (default 30 s)
  prompt[:SECS]        wait until the screen's last non-empty line is ">>> " (idle)
  screen               print the 80x25 screen as text
  log                  print the output transcript (everything printed since boot)
  realtime             (first action only) run at real speed
  xemu:ARG             extra Xemu command-line argument (before other actions)
The screenshot is written when Xemu exits at the end.
"""
import glob
import os
import socket
import subprocess
import sys
import time

XEMU = r"C:\Emulation\Mega65\xmega65.exe"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
D81 = os.environ.get('MEGA65_D81') or os.path.join(ROOT, 'target', 'mega-python.d81')
LBL = os.environ.get('MEGA65_LBL') or os.path.join(ROOT, 'target', 'mega-python.lbl')
PORT = int(os.environ.get('MEGA65_PORT', '4510'))
SCREEN = 0x1E800
LOG = 0x8000000

KEYS = {'n': 0x0D, 'e': 0x1B, 's': 0x03, '5': 0xF5, 't': 0x09, 'b': 0x14,
        'u': 0x91, 'd': 0x11, 'l': 0x9D, 'r': 0x1D, '\\': ord('\\')}


def labels():
    out = {}
    if os.path.exists(LBL):
        for line in open(LBL):
            if '=' in line:
                k, v = line.split('=', 1)
                v = v.strip()
                if v.startswith('$'):
                    out.setdefault(k.strip(), int(v[1:], 16))
    return out


LABELS = labels()


def addr(s):
    """hex address, or a label name with optional +hex offset"""
    base, _, off = s.partition('+')
    a = LABELS[base] if base in LABELS else int(base, 16)
    return a + (int(off, 16) if off else 0)


def scr_to_ascii(c):
    c &= 0x7F
    if c == 0:
        return '@'
    if 1 <= c <= 26:
        return chr(c + 96)
    if 27 <= c <= 31:
        return '[\\]^_'[c - 27]
    if c == 0x40:
        return '`'
    if 0x5B <= c <= 0x5E:
        return '{|}~'[c - 0x5B]
    if 32 <= c <= 90:
        return chr(c)
    return '?'


class Mon:
    def __init__(self):
        for _ in range(100):
            try:
                self.s = socket.create_connection(('127.0.0.1', PORT), timeout=5)
                return
            except OSError:
                time.sleep(0.2)
        raise RuntimeError('cannot connect to uartmon')

    def cmd(self, c, timeout=5.0):
        """send a command, read until the monitor's '.' prompt line"""
        self.s.sendall((c + '\n').encode())
        out = b''
        end = time.time() + timeout
        self.s.settimeout(0.2)
        while time.time() < end:
            try:
                d = self.s.recv(65536)
                if not d:
                    break
                out += d
                if out.endswith(b'\n.\r\n') or out.endswith(b'\r\n.\r\n') or out.rstrip().endswith(b'\n.'):
                    break
            except socket.timeout:
                pass
        return out.decode(errors='replace')

    def peek(self, a0, n=16):
        data = []
        while len(data) < n:
            out = self.cmd('M %x' % (a0 + len(data)))
            got = False
            for line in out.splitlines():
                if line.startswith(':'):
                    hexs = line.split(':')[2].strip()
                    data += [int(hexs[i:i + 2], 16) for i in range(0, len(hexs), 2)]
                    got = True
            if not got:
                break
        return data[:n]

    def poke(self, a, vals):
        for i in range(0, len(vals), 16):
            chunk = vals[i:i + 16]
            self.cmd('s %x %s' % (a + i, ' '.join('%02x' % v for v in chunk)))

    def screen(self):
        d = self.peek(SCREEN, 80 * 25)
        return [''.join(scr_to_ascii(c) for c in d[r * 80:(r + 1) * 80]).rstrip()
                for r in range(25)]

    def log(self):
        ptr = self.peek(LABELS['log_fp'], 4)
        end = ptr[0] | ptr[1] << 8 | ptr[2] << 16 | ptr[3] << 24
        n = end - LOG
        if n <= 0:
            return ''
        return bytes(self.peek(LOG, n)).decode('ascii', errors='replace')

    def type(self, text):
        keys = []
        i = 0
        while i < len(text):
            c = text[i]
            if c == '\\' and i + 1 < len(text):
                keys.append(KEYS[text[i + 1]])
                i += 2
            else:
                keys.append(0x0D if c == chr(10) else ord(c))
                i += 1
        kpos, klen, kbuf = LABELS['dbg_kpos'], LABELS['dbg_klen'], LABELS['dbg_keys']
        for i in range(0, len(keys), 200):
            chunk = keys[i:i + 200]
            # wait for the previous batch to be consumed
            for _ in range(600):
                p, l = self.peek(kpos, 1)[0], self.peek(klen, 1)[0]
                if p >= l:
                    break
                time.sleep(0.05)
            self.poke(klen, [0])
            self.poke(kbuf, chunk)
            self.poke(kpos, [0])
            self.poke(klen, [len(chunk)])

    def waitfor(self, text, secs=30.0):
        end = time.time() + secs
        while time.time() < end:
            if any(text in line for line in self.screen()):
                return True
            time.sleep(0.3)
        return False

    def wait_prompt(self, secs=60.0):
        end = time.time() + secs
        while time.time() < end:
            lines = [l for l in self.screen() if l.strip()]
            p, l = self.peek(LABELS['dbg_kpos'], 1)[0], self.peek(LABELS['dbg_klen'], 1)[0]
            if lines and lines[-1] == '>>>' and p >= l:
                return True
            time.sleep(0.3)
        return False


SHOW = os.environ.get('MEGA65_SHOW') == '1'


def start(extra=(), speed=('-sleepless',), shot=None):
    """start Xemu; with $MEGA65_SHOW=1 (or --show) in a window you can watch"""
    head = [] if SHOW else ['-headless']
    args = [XEMU] + head + list(speed) + ['-besure', '-uartmon', ':%d' % PORT]
    if shot:
        args += ['-screenshot', shot]
    args += ['-8', D81, '-autoload'] + list(extra)
    return subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def stop(p, m):
    try:
        m.cmd('~exit', 2.0)
        p.wait(timeout=15)
    finally:
        if p.poll() is None:
            p.kill()


def main():
    shot = os.path.abspath(sys.argv[1])
    actions = sys.argv[2:]
    speed = ['-sleepless']
    extra = []
    while actions and (actions[0] == 'realtime' or actions[0].startswith('xemu:')):
        if actions[0] == 'realtime':
            speed = []
        else:
            extra.append(actions[0][5:])
        actions = actions[1:]
    if os.path.exists(shot):
        os.remove(shot)
    p = start(extra, speed, shot)
    m = None
    try:
        time.sleep(1.0)
        m = Mon()
        for a in actions:
            if a.startswith('wait:'):
                time.sleep(float(a[5:]))
            elif a.startswith('poke:'):
                where, vals = a[5:].split('=')
                m.poke(addr(where), [int(v, 16) for v in vals.split(',')])
            elif a.startswith('peek:'):
                parts = a[5:].split(':')
                where = addr(parts[0])
                n = int(parts[1]) if len(parts) > 1 else 16
                d = m.peek(where, n)
                for i in range(0, len(d), 16):
                    print('%-12s %07x: %s' % (parts[0], where + i, ' '.join('%02x' % b for b in d[i:i + 16])))
            elif a == 'regs':
                print(m.cmd('r'))
            elif a.startswith('type:'):
                m.type(a[5:])
            elif a.startswith('waitfor:'):
                text, _, secs = a[8:].partition(':')
                if not m.waitfor(text, float(secs or 30)):
                    print('waitfor: timed out waiting for %r' % text)
            elif a.startswith('prompt'):
                secs = a.partition(':')[2]
                if not m.wait_prompt(float(secs or 60)):
                    print('prompt: timed out')
            elif a == 'screen':
                print('\n'.join(m.screen()))
            elif a == 'log':
                print(m.log())
    finally:
        if m:
            stop(p, m)
        elif p.poll() is None:
            p.kill()
    print('screenshot:', shot if os.path.exists(shot) else 'MISSING')


if __name__ == '__main__':
    main()
