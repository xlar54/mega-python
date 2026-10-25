# sys: about the interpreter and its environment, as Python's sys module
#
#   import sys
#   sys.version                  '3.15.0 (MEGA65 Python 0.8.0, 45GS02 assembly)'
#   sys.version_info             the Python language version: (3, 15, 0, 'final', 0)
#   sys.implementation.version   this interpreter's version: (0, 8, 0, 'final', 0)
#   sys.platform                 'mega65'
#   sys.stdout.write('text')     sys.exit()
#
# The build replaces @VERSION@ below with the VERSION file (tools/mkpy.py), so the
# version is the one the boot banner shows.

_V = '@VERSION@'


class _VersionInfo:
    """Like sys.version_info: major, minor, micro, releaselevel, serial; also v[0] ..."""

    def __init__(self, name, major, minor, micro, releaselevel='final', serial=0):
        self._name = name
        self._v = [major, minor, micro, releaselevel, serial]
        self.major = major
        self.minor = minor
        self.micro = micro
        self.releaselevel = releaselevel
        self.serial = serial

    def __getitem__(self, i):
        r = self._v[i]
        return tuple(r) if isinstance(r, list) else r

    def __len__(self):
        return 5

    def __eq__(self, other):
        return list(self._v[:len(other)]) == list(other)

    def __lt__(self, other):
        return self._v[:len(other)] < list(other)

    def __ge__(self, other):
        return not self < other

    def __repr__(self):
        return '%s(major=%d, minor=%d, micro=%d, releaselevel=%r, serial=%d)' % (
            self._name, self.major, self.minor, self.micro, self.releaselevel, self.serial)


def _numbers(text):
    parts = (text.split('.') + ['0', '0'])[:3]
    return [int(p) for p in parts]


_n = _numbers(_V)
version_info = _VersionInfo('sys.version_info', 3, 15, 0)
version = '3.15.0 (MEGA65 Python ' + _V + ', 45GS02 assembly)'
hexversion = 0x030F00F0


class _Implementation:
    def __init__(self):
        self.name = 'mega65python'
        self.version = _VersionInfo('sys.version_info', _n[0], _n[1], _n[2])
        self.cache_tag = None

    def __repr__(self):
        return "namespace(name='mega65python', cache_tag=None, version=%r)" % self.version


implementation = _Implementation()
platform = 'mega65'
byteorder = 'little'
maxsize = 2147483647            # (ints are 32-bit)
argv = ['']
path = ['']                     # (modules: name.py, then lib-name.py, on drive 8)
copyright = 'MEGA65 Python: a Python 3 subset in 45GS02 assembly'


class _Out:
    """sys.stdout / sys.stderr: write() prints (to the screen)."""

    def __init__(self, name):
        self.name = name

    def write(self, s):
        print(s, end='')
        return len(s)

    def flush(self):
        pass


class _In:
    """sys.stdin: readline() reads a line from the keyboard."""

    def readline(self):
        return input() + chr(10)


stdout = _Out('<stdout>')
stderr = _Out('<stderr>')
stdin = _In()


def exit(status=None):
    """Stop the program (SystemExit), as sys.exit() does."""
    if status is None:
        raise SystemExit()
    raise SystemExit(status)
