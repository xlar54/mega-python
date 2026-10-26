# itertools: iterator building blocks, as in Python's itertools module (written in
# Python with generators; groupby's groups are iterators over lists)


def count(start=0, step=1):
    n = start
    while True:
        yield n
        n += step


def cycle(iterable):
    saved = []
    for x in iterable:
        yield x
        saved.append(x)
    while saved:
        for x in saved:
            yield x


def repeat(obj, times=None):
    if times is None:
        while True:
            yield obj
    else:
        for _ in range(times):
            yield obj


class chain:
    """The items of each iterable in turn; chain.from_iterable(its) takes them from one."""

    def __init__(self, *iterables):
        self._its = iter(iterables)
        self._cur = iter(())

    def __iter__(self):
        return self

    def __next__(self):
        while True:
            try:
                return next(self._cur)
            except StopIteration:
                self._cur = iter(next(self._its))

    @staticmethod
    def from_iterable(iterables):
        c = chain()
        c._its = iter(iterables)
        return c


def accumulate(iterable, func=None, initial=None):
    it = iter(iterable)
    total = initial
    if initial is None:
        try:
            total = next(it)
        except StopIteration:
            return
    yield total
    for x in it:
        total = total + x if func is None else func(total, x)
        yield total


def compress(data, selectors):
    for d, s in zip(data, selectors):
        if s:
            yield d


def dropwhile(predicate, iterable):
    it = iter(iterable)
    for x in it:
        if not predicate(x):
            yield x
            break
    for x in it:
        yield x


def takewhile(predicate, iterable):
    for x in iterable:
        if not predicate(x):
            break
        yield x


def filterfalse(predicate, iterable):
    if predicate is None:
        predicate = bool
    for x in iterable:
        if not predicate(x):
            yield x


def starmap(function, iterable):
    for args in iterable:
        yield function(*args)


def islice(iterable, *args):
    s = slice_args(args)
    start, stop, step = s
    it = iter(iterable)
    i = 0
    nxt = start
    while stop is None or i < stop:     # (no item past stop is taken)
        try:
            x = next(it)
        except StopIteration:
            return
        if i == nxt:
            yield x
            nxt += step
        i += 1


def slice_args(args):
    if len(args) == 1:
        start, stop, step = 0, args[0], 1
    elif len(args) == 2:
        start, stop, step = args[0], args[1], 1
    else:
        start, stop, step = args
    if start is None:
        start = 0
    if step is None:
        step = 1
    if start < 0 or (stop is not None and stop < 0) or step < 1:
        raise ValueError('Indices for islice() must be None or an integer: 0 <= x <= sys.maxsize.')
    return start, stop, step


def zip_longest(*iterables, fillvalue=None):
    its = [iter(it) for it in iterables]
    while True:
        row = []
        live = 0
        for it in its:
            try:
                row.append(next(it))
                live += 1
            except StopIteration:
                row.append(fillvalue)
        if not live:
            return
        yield tuple(row)


def pairwise(iterable):
    it = iter(iterable)
    try:
        a = next(it)
    except StopIteration:
        return
    for b in it:
        yield a, b
        a = b


def batched(iterable, n):
    if n < 1:
        raise ValueError('n must be at least one')
    batch = []
    for x in iterable:
        batch.append(x)
        if len(batch) == n:
            yield tuple(batch)
            batch = []
    if batch:
        yield tuple(batch)


def product(*iterables, repeat=1):
    pools = [tuple(p) for p in iterables] * repeat
    result = [()]
    for pool in pools:
        result = [x + (y,) for x in result for y in pool]
    for prod in result:
        yield prod


def permutations(iterable, r=None):
    pool = tuple(iterable)
    n = len(pool)
    r = n if r is None else r
    if r > n:
        return
    indices = list(range(n))
    cycles = list(range(n, n - r, -1))
    yield tuple(pool[i] for i in indices[:r])
    while n:
        for i in reversed(range(r)):
            cycles[i] -= 1
            if cycles[i] == 0:
                indices[i:] = indices[i + 1:] + indices[i:i + 1]
                cycles[i] = n - i
            else:
                j = cycles[i]
                indices[i], indices[-j] = indices[-j], indices[i]
                yield tuple(pool[i] for i in indices[:r])
                break
        else:
            return


def combinations(iterable, r):
    pool = tuple(iterable)
    n = len(pool)
    if r > n:
        return
    indices = list(range(r))
    yield tuple(pool[i] for i in indices)
    while True:
        for i in reversed(range(r)):
            if indices[i] != i + n - r:
                break
        else:
            return
        indices[i] += 1
        for j in range(i + 1, r):
            indices[j] = indices[j - 1] + 1
        yield tuple(pool[i] for i in indices)


def combinations_with_replacement(iterable, r):
    pool = tuple(iterable)
    n = len(pool)
    if not n and r:
        return
    indices = [0] * r
    yield tuple(pool[i] for i in indices)
    while True:
        for i in reversed(range(r)):
            if indices[i] != n - 1:
                break
        else:
            return
        indices[i:] = [indices[i] + 1] * (r - i)
        yield tuple(pool[i] for i in indices)


def groupby(iterable, key=None):
    """(key, group) for each run of items with the same key (a group is an iterator)."""
    if key is None:
        key = _same
    group = []
    gkey = None
    for x in iterable:
        k = key(x)
        if group and k != gkey:
            yield gkey, iter(group)
            group = []
        if not group:
            gkey = k
        group.append(x)
    if group:
        yield gkey, iter(group)


def _same(x):
    return x


def tee(iterable, n=2):
    """n iterators over the same items (the items are kept until all have passed them)."""
    it = iter(iterable)
    buf = []
    return tuple(_tee(it, buf) for _ in range(n))


def _tee(it, buf):
    i = 0
    while True:
        if i < len(buf):
            yield buf[i]
        else:
            try:
                x = next(it)
            except StopIteration:
                return
            buf.append(x)
            yield x
        i += 1
