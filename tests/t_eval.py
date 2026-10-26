# eval() and exec() of source strings, in the main program's globals
x = 10
print(eval('1 + 2 * 3'), eval('x * 2'), eval('  [i * i for i in range(4)]'))
print(eval('"abc".upper()'), eval('2 ** 100'), eval('(lambda n: n + 1)(41)'))
exec('y = x + 5')
print(y)
exec('def twice(n):\n    return 2 * n\nz = twice(21)')
print(z, twice(4))
exec('for k in range(3):\n    print("loop", k)')
print(eval('x', ), eval('len("hello")'))
f = eval('lambda a, b: a * b')
print(f(6, 7))
total = 0
for i in range(200):
    total += eval('i * 2')
print(total)
try:
    eval('1 +')
except SyntaxError:
    print('SyntaxError')
try:
    eval('undefined_name')
except NameError:
    print('NameError')
try:
    exec('raise ValueError("inside")')
except ValueError as e:
    print('ValueError', e)
print(eval(repr([1, 'two', 3.0])), eval('eval("1 + 1")'))
print(exec('pass'), eval('x if x > 5 else 0'))
code = 'import math\nr = math.sqrt(16)'
exec(code)
print(r)
s = 'end'
for i in range(3000):                   # each eval's constants go with its code
    r = eval("'" + 'q' * 60 + "' + s")
print(len(r), r[-3:])
for i in range(300):
    r = eval("eval(\"'" + 'w' * 40 + "'\") + 'x'")
print(len(r))
