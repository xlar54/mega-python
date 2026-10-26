# dir(), vars(), globals(), delattr(), slice(), ascii() (tests/support/modtest.py)
import modtest


def pub(names):
    return [n for n in names if not n.startswith('__')]


def pick(names, wanted):
    return [n for n in names if n in wanted]


class Base:
    kind = 'base'

    def hello(self):
        return 'hi'


class Pt(Base):
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def norm(self):
        return self.x + self.y


p = Pt(1, 2)
print(pub(dir(p)))
print(pub(dir(Pt)))
print(vars(p))
print(sorted(pub(vars(Pt))))
print(pub(dir(modtest)))
print(sorted(pub(vars(modtest))))
print(pick(dir([]), ('append', 'pop', 'sort')))
print(pick(dir(str), ('upper', 'split')))
delattr(p, 'y')
print(vars(p), hasattr(p, 'y'))
try:
    delattr(p, 'nope')
except AttributeError:
    print('AttributeError')
setattr(p, 'z', 9)
vars(p)['w'] = 4
print(p.z, p.w)
g = globals()
print(g['p'] is p, 'Pt' in g, 'print' in g, 'len' in g)
total = 5
print(sorted(n for n in globals() if not n.startswith('__')))
print(sorted(n for n in dir() if not n.startswith('__')))
s = slice(2)
t = slice(1, 8, 3)
print(s, t, s.start, s.stop, s.step, t.start, t.step)
print([0, 1, 2, 3, 4, 5, 6, 7, 8][t], 'abcdef'[slice(1, None)], type(t) is slice)
print(isinstance(t, slice), ascii('hi'), ascii([1, 'x']))
try:
    vars(5)
except TypeError:
    print('TypeError')
