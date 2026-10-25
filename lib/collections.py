# collections: deque, Counter and defaultdict, as in Python's collections module (on
# the disk as lib-colls.py: 'import collections' finds it). namedtuple and
# OrderedDict are not here yet (dicts keep their order anyway).


class _Iter:
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


class deque:
    """A list that is quick to add to and take from at both ends (maxlen: the oldest
    items fall off the other end)."""

    def __init__(self, iterable=(), maxlen=None):
        self.maxlen = maxlen
        self._items = []
        for x in iterable:
            self.append(x)

    def append(self, x):
        self._items.append(x)
        if self.maxlen is not None and len(self._items) > self.maxlen:
            self._items.pop(0)

    def appendleft(self, x):
        self._items.insert(0, x)
        if self.maxlen is not None and len(self._items) > self.maxlen:
            self._items.pop()

    def pop(self):
        if not self._items:
            raise IndexError('pop from an empty deque')
        return self._items.pop()

    def popleft(self):
        if not self._items:
            raise IndexError('pop from an empty deque')
        return self._items.pop(0)

    def extend(self, iterable):
        for x in iterable:
            self.append(x)

    def extendleft(self, iterable):
        for x in iterable:
            self.appendleft(x)

    def rotate(self, n=1):
        """Move the last n items to the front (n < 0: the first ones to the back)."""
        if self._items:
            n = n % len(self._items)
            self._items = self._items[len(self._items) - n:] + self._items[:len(self._items) - n]

    def clear(self):
        self._items = []

    def count(self, x):
        return self._items.count(x)

    def index(self, x):
        return self._items.index(x)

    def remove(self, x):
        self._items.remove(x)

    def reverse(self):
        self._items.reverse()

    def copy(self):
        return deque(self._items, self.maxlen)

    def __len__(self):
        return len(self._items)

    def __getitem__(self, i):
        return self._items[i]

    def __setitem__(self, i, x):
        self._items[i] = x

    def __contains__(self, x):
        return x in self._items

    def __iter__(self):
        return _Iter(self._items)

    def __eq__(self, other):
        return isinstance(other, deque) and self._items == other._items

    def __repr__(self):
        if self.maxlen is None:
            return 'deque(%r)' % self._items
        return 'deque(%r, maxlen=%d)' % (self._items, self.maxlen)


class Counter:
    """Counts of things: c[x] is how often x was seen (0 if never)."""

    def __init__(self, iterable=None):
        self._d = {}
        if iterable is not None:
            self.update(iterable)

    def update(self, iterable):
        if isinstance(iterable, (dict, Counter)):
            for k in iterable.keys():
                self[k] = self[k] + iterable[k]
        else:
            for x in iterable:
                self[x] = self[x] + 1

    def subtract(self, iterable):
        if isinstance(iterable, (dict, Counter)):
            for k in iterable.keys():
                self[k] = self[k] - iterable[k]
        else:
            for x in iterable:
                self[x] = self[x] - 1

    def most_common(self, n=None):
        """(item, count) pairs, the most common first (ties: first seen first)."""
        pairs = sorted(self._d.items(), key=lambda p: -p[1])
        return pairs if n is None else pairs[:n]

    def elements(self):
        out = []
        for k in self._d:
            out += [k] * max(self._d[k], 0)
        return out

    def total(self):
        return sum(self._d.values())

    def keys(self):
        return self._d.keys()

    def values(self):
        return self._d.values()

    def items(self):
        return self._d.items()

    def get(self, k, default=None):
        return self._d.get(k, default)

    def __getitem__(self, k):
        return self._d.get(k, 0)

    def __setitem__(self, k, v):
        self._d[k] = v

    def __contains__(self, k):
        return k in self._d

    def __len__(self):
        return len(self._d)

    def __iter__(self):
        return _Iter(list(self._d.keys()))

    def __eq__(self, other):
        return isinstance(other, Counter) and self._d == other._d

    def __repr__(self):
        if not self._d:
            return 'Counter()'
        parts = ['%r: %r' % (k, v) for k, v in self.most_common()]
        return 'Counter({' + ', '.join(parts) + '})'


class defaultdict:
    """A dict that makes a missing key's value with default_factory() (list, int, ...)."""

    def __init__(self, default_factory=None, items=None):
        self.default_factory = default_factory
        self._d = dict(items) if items is not None else {}

    def __getitem__(self, k):
        if k not in self._d:
            if self.default_factory is None:
                raise KeyError(k)
            self._d[k] = self.default_factory()
        return self._d[k]

    def __setitem__(self, k, v):
        self._d[k] = v

    def __contains__(self, k):
        return k in self._d

    def __len__(self):
        return len(self._d)

    def __iter__(self):
        return _Iter(list(self._d.keys()))

    def get(self, k, default=None):
        return self._d.get(k, default)

    def keys(self):
        return self._d.keys()

    def values(self):
        return self._d.values()

    def items(self):
        return self._d.items()

    def pop(self, k, default=None):
        return self._d.pop(k, default)

    def __repr__(self):
        return 'defaultdict(%r, %r)' % (self.default_factory, self._d)
