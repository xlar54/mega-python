# the newer features with the heap nearly full: garbage collections land in the middle
# of index rebuilds, argument binding, CALL_EX, environments, set operations, sorting
ballast = [(i, i + 70000) for i in range(900)]     # ~ 25 KB of live objects, kept
# (built without garbage in between: the GC does not move objects, so live strings with
# freed ones between them would leave the free space in small pieces)


def make_adder(n):
    def add(*xs, scale=1, **extra):
        return (sum(xs) + n + len(extra)) * scale
    return add


class P:
    def __init__(self, x):
        self._x = x

    @property
    def x(self):
        return self._x

    def __hash__(self):
        return hash(self._x)

    def __eq__(self, o):
        return isinstance(o, P) and o._x == self._x


check = 0
for rnd in range(12):
    d = {}
    for i in range(40):                         # index growth and rebuilds
        d['k%d_%d' % (rnd, i)] = [i] * 3
    for i in range(0, 40, 3):
        del d['k%d_%d' % (rnd, i)]              # rebuilds on delete
    check += len(d) + sum(v[0] for v in d.values())
    adders = [make_adder(i) for i in range(10)]                     # environments
    check += sum(f(*range(i), scale=2, **{'a': i, 'b': 1}) for i, f in enumerate(adders))
    s = {P(i % 17) for i in range(60)}                              # __hash__ / __eq__
    t = {P(i) for i in range(10, 30)}
    check += len(s | t) + len(s & t) + len(s - t) + sum(p.x for p in s ^ t)
    words = sorted(('w%03d' % ((i * 37) % 101) for i in range(80)), key=lambda w: (w[-1], w))
    check += len(words) + ord(words[0][-1]) + ord(words[-1][-1])
    kw = {('n%d' % i): i for i in range(12)}
    check += make_adder(rnd)(**kw) + len(set(kw) - {'n1', 'n2'})
print(check, len(ballast), ballast[-1][1])
