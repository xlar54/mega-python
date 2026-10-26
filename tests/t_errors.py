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


# issubclass
class SA:
    pass


class SB(SA):
    pass


class SC:
    pass


print(issubclass(SB, SA), issubclass(SA, SB), issubclass(SB, SB), issubclass(SB, (SC, SA)), issubclass(SC, (SA, SB)))
print(issubclass(KeyError, LookupError), issubclass(GeneratorExit, Exception), issubclass(ValueError, BaseException))
try:
    issubclass(SB(), SA)
except TypeError as e:
    print('TypeError', e)


# min/max default=, !r with a format spec, '#' in format specs, annotated assignments
print(min([], default=0), max((), default=9), max([3, 5], default=0), min(4, 2, key=lambda v: -v))
print(f'{"x"!r:>5}|{255:#x}|{255:#X}|{8:#o}|{5:#b}|{-255:#x}')
y: int = 5
z: int


def ah():
    a: int = 3
    b: list
    return a


class Pt:
    x: int = 1
    y: float


print(y, ah(), Pt.x, 'z' in globals() if False else 'ok')
print('%#x %#o %x' % (255, 8, 255), '{:#x}'.format(255), '{:x}'.format(255), f'{255:x}')
