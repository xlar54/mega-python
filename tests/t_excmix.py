# exceptions raised inside the newer machinery, and everything working afterwards
def boom_deco(f):
    raise ValueError('deco')


try:
    @boom_deco
    def never():
        pass
except ValueError as e:
    print('deco:', e)


class Bad:
    @property
    def v(self):
        raise KeyError('getter')

    @v.setter
    def v(self, x):
        raise IndexError('setter')


b = Bad()
for act in (lambda: b.v, lambda: setattr(b, 'v', 1)):
    try:
        act()
    except (KeyError, IndexError) as e:
        print(type(e).__name__)


class H:
    def __init__(self, n, fail=False):
        self.n, self.fail = n, fail

    def __hash__(self):
        if self.fail:
            raise RuntimeError('hash')
        return self.n

    def __eq__(self, o):
        if getattr(o, 'fail', False) or self.fail:
            raise RuntimeError('eq')
        return self.n == o.n


d = {H(i): i for i in range(12)}
for probe in (H(3), H(3, True), H(99)):
    try:
        print(d.get(probe, 'missing'))
    except RuntimeError as e:
        print('RuntimeError', e)
s = {H(i) for i in range(10)}
try:
    s.add(H(1, True))
except RuntimeError as e:
    print('add:', e, len(s))
print(len(s), H(4) in s)


def key(v):
    if v == 3:
        raise ArithmeticError('key')
    return -v


data = [5, 3, 1, 4]
try:
    data.sort(key=key)
except ArithmeticError as e:
    print('sort:', e, sorted(data))
print(sorted(data, key=lambda v: -v))

for attempt in range(3):
    try:
        class K:
            a = 1
            if attempt == 1:
                raise LookupError('in body')
            b = a + 1
        print('class ok', K.a, K.b)
    except LookupError as e:
        print('class:', e)


class After:
    x = 10
    y = x * 2


print(After.y)
for attempt in range(10):                   # (each failed class body is forgotten)
    try:
        class Fails:
            z = 1
            raise KeyError(attempt)
    except KeyError:
        pass


class Last:
    z = 5
    w = z + 1


print(Last.w)


def f(a, *, k):
    return a, k


for call in (lambda: f(1), lambda: f(1, 2, k=3), lambda: f(k=1), lambda: f(1, k=2)):
    try:
        print(call())
    except TypeError:
        print('TypeError')


def outer():
    v = 1

    def inner():
        nonlocal v
        v += 1
        if v == 3:
            raise StopIteration('inner')
        return v
    out = []
    for _ in range(4):
        try:
            out.append(inner())
        except StopIteration as e:
            out.append(str(e))
    return out


print(outer())
print({k: v for k, v in zip('abc', range(3))}, 'done')
