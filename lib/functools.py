# functools: reduce() and cmp_to_key(), from Python's functools module (partial,
# lru_cache and wraps need *args and decorators, which MEGA65 Python does not have yet)

_MISSING = []


def reduce(function, iterable, initial=_MISSING):
    """function(function(function(a, b), c), d) for the items a, b, c, d."""
    items = list(iterable)
    if initial is _MISSING:
        if not items:
            raise TypeError('reduce() of empty iterable with no initial value')
        value = items[0]
        items = items[1:]
    else:
        value = initial
    for item in items:
        value = function(value, item)
    return value


class _K:
    def __init__(self, obj, cmp):
        self.obj = obj
        self.cmp = cmp

    def __lt__(self, other):
        return self.cmp(self.obj, other.obj) < 0

    def __gt__(self, other):
        return self.cmp(self.obj, other.obj) > 0

    def __eq__(self, other):
        return self.cmp(self.obj, other.obj) == 0

    def __le__(self, other):
        return self.cmp(self.obj, other.obj) <= 0

    def __ge__(self, other):
        return self.cmp(self.obj, other.obj) >= 0


class _KeyMaker:
    def __init__(self, cmp):
        self.cmp = cmp

    def __call__(self, obj):
        return _K(obj, self.cmp)


def cmp_to_key(mycmp):
    """An old-style comparison function -> a key function (for sorted(key=...))."""
    return _KeyMaker(mycmp)
