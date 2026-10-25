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
