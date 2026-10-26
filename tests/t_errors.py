# error messages name the type, as CPython's do
class Plain:
    pass


def gen():
    yield 1


tests = [lambda: len(5), lambda: len(Plain()), lambda: 5[0], lambda: (1, 2)[0:1][5],
         lambda: None[1:2], lambda: iter(3.5), lambda: [x for x in Plain()], lambda: next([1]),
         lambda: {**[1]}, lambda: [i for i in 7]]
for t in tests:
    try:
        t()
    except (TypeError, IndexError) as e:
        print(type(e).__name__, e)
t = (1, 2)
try:
    t[0] = 5
except TypeError as e:
    print(e)
s = 'ab'
try:
    del s[0]
except TypeError as e:
    print(e)
p = Plain()
try:
    p['k'] = 1
except TypeError as e:
    print(e)


def yf():
    yield from iter([1])


g = yf()
next(g)
