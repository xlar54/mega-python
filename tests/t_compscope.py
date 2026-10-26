# comprehensions' loop variables stay inside them (hidden names): globals, locals, class
# bodies, nested comprehensions, lambdas over them, the first iterable outside
x = 'outer'
squares = [x * x for x in range(5)]
print(squares, x)
pairs = [(x, y) for x in range(3) for y in range(x)]
print(pairs, x)
d = {k: v for k, v in [('a', 1), ('b', 2)]}
s = {x % 3 for x in range(10)}
print(d, s, x)
try:
    k
except NameError:
    print('no k')
nested = [[x * y for y in range(3)] for x in range(3)]
print(nested, x)
x = [1, 2, 3]
x = [x * 2 for x in x]          # the first iterable is the outer x
print(x)
fs = [lambda: i for i in range(3)]
print([f() for f in fs])
gs = [lambda i=i: i for i in range(3)]
print([g() for g in gs])
hs = [lambda x: x + 1 for x in range(3)]
print([h(10) for h in hs])
print([sum(j * x for j in range(3)) for x in range(4)])
print([f(n=x) for x in range(2) for f in [lambda n: n * 10]])


def func():
    x = 'local'
    a = [x for x in 'abc']
    b = {x: len(x) for x in ['aa', 'b']}
    c = [lambda: x for x in range(2)]
    return a, b, x, [f() for f in c]


print(func())


class K:
    vals = [v * 2 for v in range(3)]
    n = len(vals)


print(K.vals, K.n, hasattr(K, 'v'))
y = 5
print([y for y in range(2)], y, [(y := z) for z in range(3)], y)
print(sorted(n for n in globals() if not n.startswith('__')))


def a():
    return [f() for f in [lambda i=i: i for i in range(3)]]


def b():
    for i in range(3):
        pass
    return [f() for f in [lambda i=i: i for i in range(3)]]


def c():
    return [f() for f in [lambda j=i: j for i in range(3)]]


def d():
    return [f(5) for f in [lambda i: i for i in range(3)]]


print(a(), b(), c(), d())


# the same name in nested comprehensions: each level keeps its own
print([(x, [x for x in range(2)], x) for x in 'ab'])
print({x: [x * 2 for x in range(x)] for x in range(3)})


def nested():
    return [[x, [x + 1 for x in range(2)], x] for x in (10, 20)]


print(nested())
