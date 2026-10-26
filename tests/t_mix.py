# the newer features together: closures, decorators, *args/**kwargs, properties,
# sets and hashed dicts, user iterators, exceptions through all of them
import functools


def memo(fn):
    cache = {}

    def inner(*args, **kw):
        key = (args, tuple(sorted(kw.items())))
        if key not in cache:
            cache[key] = fn(*args, **kw)
        return cache[key]
    return inner


@memo
def paths(r, c, *, wall=None):
    if r == 0 or c == 0:
        return 1
    if wall is not None and (r, c) in wall:
        return 0
    return paths(r - 1, c, wall=wall) + paths(r, c - 1, wall=wall)


print(paths(8, 8), paths(5, 5, wall=frozenset({(2, 2), (3, 1)})))


def counter_class(start):
    count = start

    class Counter:
        def __init__(self, *items, step=1, **extra):
            nonlocal count
            count += len(items)
            self.items = list(items)
            self.step = step
            self.extra = extra

        @property
        def total(self):
            return count + sum(self.items) * self.step

        @total.setter
        def total(self, v):
            nonlocal count
            count = v

        @classmethod
        def make(cls, *a, **k):
            return cls(*a, **k)

        @staticmethod
        def seen():
            return count
    return Counter


C = counter_class(100)
a = C(1, 2, 3, step=2, tag='x')
b = C.make(5, **{'step': 3})
print(a.total, b.total, C.seen(), a.extra, b.extra)
a.total = 7
print(a.total, b.total, C.seen())


def compose(*fns):
    def run(x):
        for f in reversed(fns):
            x = f(x)
        return x
    return run


inc = lambda x: x + 1
dbl = lambda x: x * 2
print(compose(inc, dbl)(5), compose(dbl, inc, str.upper)('ab') if False else compose()(9))


class Node:
    def __init__(self, name, *kids):
        self.name, self.kids = name, kids

    def __iter__(self):
        return Walk(self)

    def __hash__(self):
        return hash(self.name)

    def __eq__(self, other):
        return isinstance(other, Node) and self.name == other.name


class Walk:
    def __init__(self, root):
        self.stack = [root]

    def __iter__(self):
        return self

    def __next__(self):
        if not self.stack:
            raise StopIteration
        n = self.stack.pop()
        self.stack.extend(reversed(n.kids))
        return n.name


tree = Node('a', Node('b', Node('d')), Node('c', Node('e'), Node('f')))
print(list(tree), sorted(tree, key=lambda s: -ord(s)), '-'.join(tree))
print(len({Node('x'), Node('x'), Node('y')}), Node('d') in {Node(c) for c in 'abcd'})
groups = {}
for w in 'one two three four five six seven eight nine ten eleven twelve'.split():
    groups.setdefault(len(w), set()).add(w)
print(sorted((k, sorted(v)) for k, v in groups.items()))


def safe(default):
    def deco(fn):
        @functools.wraps(fn) if hasattr(functools, 'wraps') else (lambda f: f)
        def call(*a, **k):
            try:
                return fn(*a, **k)
            except (ZeroDivisionError, KeyError) as e:
                return default, type(e).__name__
        return call
    return deco


@safe(-1)
def div(a, b, *, table=None):
    if table is not None:
        return table[a] / b
    return a / b


print(div(6, 3), div(1, 0), div('k', 2, table={'k': 8}), div('z', 1, table={}))


class Temp:
    def __init__(self):
        self._c = 0

    @property
    def c(self):
        return self._c

    @c.setter
    def c(self, v):
        if v < -273:
            raise ValueError('too cold')
        self._c = v


t = Temp()
for v in (20, -300, 5):
    try:
        t.c = v
    except ValueError as e:
        print('ValueError', e)
print(t.c)


def gen_keys(n):
    out = {}
    for i in range(n):
        out[('k', i % 7, i)] = i
    return out


d = gen_keys(60)
for k in list(d):
    if k[2] % 3:
        del d[k]
print(len(d), d[('k', 6, 27)], ('k', 1, 1) in d, sum(d.values()))
s = set()
for i in range(40):
    s.add(i * 1.5)
s -= {3.0, 4.5}
print(len(s), 3.0 in s, 6.0 in s, 6 in s, max(s))
