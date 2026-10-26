# edge cases: deep closure recursion, many locals, mutation during iteration, imports in functions

def make_counter():
    n = 0
    def step(k):
        nonlocal n
        if k == 0:
            return n
        n += 1
        return step(k - 1)
    return step
print(make_counter()(60))

def many(a0, a1, a2, a3, a4, a5, a6, a7, a8, a9, *rest, k0=0, k1=1, **kw):
    b0 = a0 + a1; b1 = a2 + a3; b2 = a4 + a5; b3 = a6 + a7; b4 = a8 + a9
    c0 = b0 * 2; c1 = b1 * 2; c2 = b2 * 2; c3 = b3 * 2; c4 = b4 * 2
    d0 = [c0, c1]; d1 = (c2, c3); d2 = {c4}; d3 = len(rest); d4 = sorted(kw)
    return b0 + b1 + b2 + b3 + b4, c0 + c4, d0, d1, d2, d3, d4, k0, k1
print(many(*range(14), k1=5, z=1, y=2))

d = {i: i for i in range(10)}
try:
    for k in d:
        d[k + 100] = 0
except RuntimeError as e:
    print('RuntimeError', e)
s = {1, 2, 3}
try:
    for x in s:
        s.add(x + 10)
except RuntimeError as e:
    print('RuntimeError', e)
lst = [1, 2, 3]
for x in lst:
    if x < 3:
        lst.append(x + 10)
print(lst)
for k in list(d):
    if k >= 100:
        del d[k]
print(len(d))

def use_json():
    import json
    return json.dumps({'a': [1, 2]})
print(use_json(), use_json())

def outer():
    def mid():
        def inner():
            return x + y
        y = 2
        return inner
    x = 1
    return mid()()
print(outer())

fs = [lambda v, i=i: v * i for i in range(5)]
print([f(10) for f in fs])

def r(n):
    return 0 if n == 0 else 1 + r(n - 1)
print(r(100))

try:
    def deep(n):
        return deep(n + 1)
    deep(0)
except RecursionError:
    print('RecursionError')
print(r(50))

print(''.join(str(i % 10) for i in range(300))[-12:])
print(sum(range(50000)), max(range(-5, 5), key=abs))
print((1, (2, [3, {4: (5,)}]))[1][1][1][4])

# dict keys deleted and added during iteration (same size): CPython's 'keys changed'
def trial(name, d, f):
    seen = []
    try:
        for k in d:
            seen.append(k)
            f(d, k)
        print(name, seen, 'ok', d)
    except RuntimeError as e:
        print(name, seen, e)


def swap_cur(d, k):                     # delete the current key, add another
    del d[k]
    d[k + 10] = 0


def swap_later(d, k):                   # delete a key not reached yet
    if k == 1:
        del d[3]
        d[4] = 0


def swap_last(d, k):                    # at the last key: delete the first
    if k == 3:
        del d[1]
        d[4] = 0


def swap_earlier(d, k):                 # delete a key already seen
    if k == 2:
        del d[1]
        d[4] = 0


def readd(d, k):                        # delete and re-add the same key
    if k == 1:
        del d[1]
        d[1] = 'again'


def update(d, k):                       # only values change: fine
    d[k] = d[k] * 2


trial('cur', {1: 1, 2: 2}, swap_cur)
trial('later', {1: 1, 2: 2, 3: 3}, swap_later)
trial('last', {1: 1, 2: 2, 3: 3}, swap_last)
trial('earlier', {1: 1, 2: 2, 3: 3}, swap_earlier)
trial('readd', {1: 1, 2: 2, 3: 3}, readd)
trial('update', {1: 1, 2: 2, 3: 3}, update)
s = {1, 2, 3}                           # sets never raise "keys changed"
seen = []
for x in s:
    seen.append(x)
    if x == 1:
        s.discard(3)
        s.add(4)
print('set', seen, sorted(s))
trial('big', {i: i for i in range(12)}, swap_cur)


def swap_mid(d, k):                    # a hashed dict (8+ keys): pop an earlier key
    if k == 8:
        d.pop(k - 3)
        d[k + 50] = 0


trial('bigmid', {i: i for i in range(12)}, swap_mid)
