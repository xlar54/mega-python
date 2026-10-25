# files: open / write / read / readline / readlines / iteration / with / append / errors
nl = chr(10)
f = open('tfdata', 'w')
print(f.write('first line' + nl), f.write('second' + nl + 'third' + nl))
f.close()
f.close()                       # closing twice is fine
print(repr(open('tfdata').read()))

f = open('tfdata', 'r')
print(repr(f.readline()), repr(f.read(3)), repr(f.readline()))
print(repr(f.read()), repr(f.read()), repr(f.readline()))
f.close()

with open('tfdata', 'a') as g:
    g.write('fourth' + nl)
    g.write(str(42) + nl)
print(open('tfdata').readlines())

n = 0
for line in open('tfdata'):
    n += 1
    print(n, line.rstrip(), len(line))

# a table of numbers, written and read back
with open('tfnums', 'w') as f:
    for i in range(1, 11):
        f.write('%d %d %.3f' % (i, i * i, i ** 0.5) + nl)
total = 0
with open('tfnums') as f:
    for line in f:
        a, b, c = line.split()
        total += int(b) + float(c)
print(round(total, 3))

# with closes the file when the block raises, and the error goes on
try:
    with open('tfdata') as f:
        print(f.readline().strip())
        raise ValueError('inside')
except ValueError as e:
    print('caught', e)
try:
    f.read()
except ValueError as e:
    print(e)

# return and break inside with close the file too
def head(name):
    with open(name) as f:
        return f.readline().strip()
print(head('tfdata'), head('tfnums'))
for i in range(3):
    with open('tfdata') as f:
        if i == 1:
            break
print(i)

# a large file (several 255-byte transfers)
with open('tfbig', 'w') as f:
    for i in range(200):
        f.write('line %03d %s' % (i, 'x' * (i % 17)) + nl)
lines = open('tfbig').readlines()
print(len(lines), lines[0].strip(), lines[199].strip(), sum(len(s) for s in lines))

try:
    open('tfnothere')
except FileNotFoundError as e:
    print('FileNotFoundError', isinstance(e, OSError))
try:
    open('tfdata', 'q')
except ValueError:
    print('ValueError')

# the os module
import os
print(os.path.exists('tfdata'), os.path.exists('tfnope'), 'tfnums' in os.listdir())
os.rename('tfnums', 'tfnums2')
print(os.path.exists('tfnums'), os.path.exists('tfnums2'))
for name in ['tfdata', 'tfnums2', 'tfbig']:
    os.remove(name)
print(os.path.exists('tfdata'), 'tfbig' in os.listdir())
try:
    os.remove('tfdata')
except FileNotFoundError:
    print('FileNotFoundError')
try:
    os.rename('tfdata', 'tfx')
except OSError:
    print('OSError')
os.unlink                       # (the same function as os.remove)
