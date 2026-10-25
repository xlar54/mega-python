# decorators: functions that wrap functions and classes; staticmethod, classmethod,
# property
calls = []


def log(f):
    def wrapper(x):
        calls.append(f.__name__)
        return f(x)
    return wrapper


@log
def double(x):
    return x * 2


print(double(21), double(5), calls)


def repeat(n):                          # a decorator factory
    def deco(f):
        def run(x):
            return [f(x) for _ in range(n)]
        return run
    return deco


@repeat(3)
def hi(name):
    return 'hi ' + name


print(hi('ada'))


def tag(t):
    return lambda f: lambda x: '<%s>%s</%s>' % (t, f(x), t)


@tag('b')
@tag('i')
def text(s):
    return s.upper()


print(text('bold italic'))

registry = {}


def register(cls):
    registry[cls.__name__] = cls
    return cls


@register
class Point:
    count = 0

    def __init__(self, x, y):
        self._x = x
        self.y = y
        Point.count += 1

    @staticmethod
    def origin_text():
        return 'origin'

    @classmethod
    def make(cls, v):
        return cls(v, v)

    @property
    def x(self):
        return self._x

    @x.setter
    def x(self, v):
        self._x = max(0, v)

    @property
    def norm1(self):
        return abs(self._x) + abs(self.y)


class Point3(Point):
    @classmethod
    def kind(cls):
        return cls.__name__


p = Point.make(3)
print(sorted(registry), p.x, p.norm1, Point.origin_text(), p.origin_text())
p.x = -5
print(p.x, p._x, p.norm1)
p.x = 7
q = Point3.make(2)
print(p.x, type(q).__name__, q.kind(), Point3.kind(), q.norm1, Point.count)
try:
    p.norm1 = 4
except AttributeError:
    print('AttributeError')


class Temp:
    def __init__(self):
        self.c = 0

    def get_f(self):
        return self.c * 9 / 5 + 32

    def set_f(self, f):
        self.c = (f - 32) * 5 / 9

    f = property(get_f, set_f)


t = Temp()
t.f = 212
print(t.c, t.f)
