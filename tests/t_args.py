# *args, **kwargs, keyword-only parameters; f(*a, **k) calls
def f(a, b=2, *rest, c, d=4, **opts):
    return a, b, rest, c, d, sorted(opts.items())


print(f(1, c=3))
print(f(1, 5, 6, 7, c=8, e=9, d=0, z=1))
print(f(c=1, a=2))


def total(*nums):
    return sum(nums), len(nums), type(nums).__name__


print(total(), total(1), total(1, 2, 3))


def kw(**k):
    return sorted(k.items())


print(kw(), kw(x=1, y=2))


def only(*, key, default=None):
    return key, default


print(only(key='k'), only(default=1, key=2))

nums = [3, 1, 2]
opts = {'c': 'C', 'q': 'Q'}
print(f(*nums, **opts))
print(f(0, *[1, 2], 3, c=5, **{'w': 1}))
print(total(*range(5)), total(*[5, 6], *(7, 8)), kw(**{'a': 1}, b=2))
print(max(*nums), sorted(nums, **{'reverse': True}), '-'.join(list('abc')))
print('{} {x}'.format(*['pos'], **{'x': 'kw'}))


def wrap(fn):
    def wrapper(*args, **kwargs):
        return 'wrapped', fn(*args, **kwargs)
    return wrapper


@wrap
def add(a, b=10, *, scale=1):
    return (a + b) * scale


print(add(1), add(1, 2), add(1, b=3, scale=2))


class Box:
    def __init__(self, *items, **meta):
        self.items = items
        self.meta = meta

    def put(self, *more):
        self.items = self.items + more
        return len(self.items)


b = Box(1, 2, tag='t')
print(b.items, b.meta, b.put(*[3, 4]), b.put())

lam = lambda *a, **k: (a, sorted(k))
print(lam(1, 2, x=3))


def g(**k):
    return k


print(f(a=g(b=1)['b'], c=g(z=2)['z']))   # (nested calls with keywords)
for call in [lambda: f(), lambda: f(1), lambda: only(1, key=2), lambda: kw(1),
             lambda: f(1, a=2, c=3), lambda: total(**{1: 2}), lambda: kw(**[1]),
             lambda: kw(a=1, **{'a': 2})]:
    try:
        call()
        print('no error')
    except TypeError:
        print('TypeError')
