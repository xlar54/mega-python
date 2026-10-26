# unpacking with * and **: in list / tuple / set / dict displays, and starred targets
# (a, *b = ..., for a, *b in ...)
a = [1, 2]
b = (3, 4)
print([*a, *b], [0, *a, 9], [*'hi'], [*range(3), *a])
print((*a, 5), (*b,), (0, *a, *b, 7))
t = *a, *b
print(t, type(t).__name__)
print({*a, *b, 1}, {0, *a})
d = {'x': 1}
print({**d, 'y': 2}, {'z': 0, **d}, {**d, **{'x': 5, 'w': 6}}, {**d})


def gen():
    yield 'g'
    yield 'h'


print([*gen(), *(n * n for n in range(3))], {**dict(a=1), 'b': 2})
nested = [[*a, x] for x in b]
print(nested, len([*a, *a, *a]))
try:
    {**[1, 2]}
except TypeError:
    print('TypeError')

first, *rest = [1, 2, 3, 4]
print(first, rest)
*init, last = 'abc'
print(init, last)
p, *mid, q = range(6)
print(p, mid, q)
x, *y, z = 1, 2
print(x, y, z)
for head, *tail in [(1, 2, 3), 'xy', [9]]:
    print(head, tail)
try:
    m, *n, o = [1]
except ValueError:
    print('ValueError')


def f(*args):
    one, *others = args
    return one, others


print(f(5, 6, 7), f(8))
