# the sys module (lib/sys.py on the MEGA65): what holds for CPython's sys too
import sys

print(sys.version_info[0], sys.version_info.major, len(sys.version_info), sys.version_info[:1])
print(sys.version_info.releaselevel, sys.version_info >= (3, 8), sys.version_info >= (4,))
print(isinstance(sys.version, str), sys.version.startswith('3.'), sys.hexversion > 0x03080000)
print(sys.maxsize >= 2147483647, sys.byteorder in ('little', 'big'), isinstance(sys.platform, str))
print(isinstance(sys.implementation.name, str), len(sys.implementation.version))
print(isinstance(sys.argv, list), isinstance(sys.path, list))
n = sys.stdout.write('written' + chr(10))
print(n)
sys.stdout.flush()
for code in [None, 3, 'bye']:
    try:
        sys.exit(code)
    except SystemExit as e:
        print('SystemExit', e.args)
