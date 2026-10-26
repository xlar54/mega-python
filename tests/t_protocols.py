# user classes in for loops, 'in', item assignment and calls (__iter__/__next__,
# __contains__, __setitem__, __call__)
class It:
    def __init__(self, items):
        self.items = items
        self.i = 0

    def __iter__(self):
        return self

    def __next__(self):
        if self.i >= len(self.items):
            raise StopIteration
        self.i += 1
        return self.items[self.i - 1]


class D:
    def __iter__(self):
        return It([1, 2])

    def __contains__(self, x):
        return x == 2


class Bag:
    def __init__(self):
        self.d = {}

    def __setitem__(self, k, v):
        self.d[k] = v * 10

    def __getitem__(self, k):
        return self.d[k]


class Twice:
    def __call__(self, x):
        return x * 2


for x in It([5, 6]):
    print(x)
print(list(It([7, 8])), sorted(D()), sum(D()), max(It([3, 9, 4])))
print(2 in D(), 3 in D(), 3 not in D())
for a in It([1, 2]):
    for b in It(['x', 'y']):
        print(a, b, end=' ')
print()
try:
    for x in It([1]):
        raise ValueError('inside')
except ValueError as e:
    print('caught', e)


class Bad:
    def __iter__(self):
        return self

    def __next__(self):
        raise KeyError('k')


try:
    for x in Bad():
        pass
except KeyError:
    print('KeyError passes through')
b = Bag()
b['a'] = 4
b['b'] = 5
print(b['a'], b['b'], b.d)
t = Twice()
print(t(21), sorted([3, 1, 2], key=t), list(map(t, [1, 2])))
print(next(It([42])))


class Halves:                           # (str.join runs this while it works)
    def __init__(self, n):
        self.n = n

    def __iter__(self):
        return self

    def __next__(self):
        if self.n == 0:
            raise StopIteration
        self.n -= 1
        return str(self.n * 0.5).upper()


print('-'.join(Halves(4)), ', '.join(It(['a', 'b'])).title())


class Gen:                              # runs Python code and builtins on each item
    def __init__(self, items):
        self.items = items
        self.i = 0

    def __iter__(self):
        return self

    def __next__(self):
        if self.i >= len(self.items):
            raise StopIteration
        self.i += 1
        x = self.items[self.i - 1]
        str(len(str(x)) * 1.5).upper().split('.')
        return x


a = [9]
a.extend(Gen([1, 2]))
print(a, sorted(Gen([3, 1, 2]), key=lambda v: -v, reverse=True))
print(sum(Gen([1, 2, 3]), 10), min(Gen([4, 2, 8]), key=lambda v: -v),
      max(Gen([4, 2, 8]), default=0))
print(list(enumerate(Gen(['a', 'b']), 5)), tuple(Gen([1, 2])), dict(Gen([(1, 2)])))
print(list(zip(Gen([1, 2]), Gen('ab'))), list(map(abs, Gen([-1, -2]))),
      list(filter(None, Gen([0, 1, 2]))), any(Gen([0, 1])), all(Gen([1, 0])))
print(' '.join(Gen(['x', 'y'])), [v * 2 for v in Gen([1, 2])], 2 in Gen([1, 2]))
d = {}
d.update(Gen([('k', 1)]))
print(d, list(Gen('hi')))


# builtins whose callbacks call other builtins (with other arguments) keep their own
class Loud:
    def __init__(self, v):
        self.v = v

    def __str__(self):
        return '<%s>' % '|'.join([str(max(self.v, 1, 2)), format(self.v, '>3'), 'x' * 2])

    def __lt__(self, other):
        return sorted([self.v, other.v], reverse=True, key=abs)[0] == other.v


def k(v):
    return min([v, 9, 8], key=lambda w: -w) + len(str(v).zfill(4))


print(sorted([3, 1, 2], key=k, reverse=True), sorted(Gen([5, 4]), key=k, reverse=True))
print(Loud(7), Loud(0), sep=' / ', end=' .\n')
print('{} {:>4} {a}'.format(Loud(1), 'r', a=Loud(2)), min(Loud(3), Loud(1)).v)
print(max(Gen([1, 5, 3]), key=lambda v: str(v).center(5, '*')),
      list(map(lambda v: sum([v, 1], 10), Gen([1, 2]))))
# key functions that bring in other code (str methods, float text) in mid-sort, and
# one that imports a module (a compile) while sorted() runs
print(sorted([3, 1, 2], key=lambda v: len(str(v).zfill(4)), reverse=True),
      sorted([0.5, 0.25, 2.0], key=lambda v: repr(v * 3).rjust(6)))


def by_module(v):
    import modtest
    return -v


print(sorted([1, 3, 2], key=by_module), '%s|%5.1f' % (Loud(4), 2.25))


class Box:
    def __init__(self):
        self.d = {1: 'a', 2: 'b'}

    def __delitem__(self, k):
        print('del', k)
        del self.d[k]


bx = Box()
del bx[1]
print(bx.d)
try:
    del (1, 2)[0]
except TypeError as e:
    print(e)


class Eq:
    def __eq__(self, o):
        print('eq', o)
        return True


q = Eq()
print(q == (1, 2), q == 5, (1, 2) == q, 5 == q, q != 'x', [q] == [(3,)], q in [1, 2])
