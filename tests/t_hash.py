# dicts and sets past 8 entries use a hash index: lookups, growth, deletes, keys that
# are equal across types, user classes with __hash__ / __eq__, unhashable keys
d = {}
for i in range(300):
    d[i * 7] = i
print(len(d), d[0], d[7 * 150], d[7 * 299], 21 in d, 22 in d, d.get(5, 'none'))
for i in range(0, 300, 2):
    del d[i * 7]
print(len(d), 14 in d, 7 in d, d[7 * 297], list(d)[:5], list(d.values())[-3:])
d[14] = 'back'
print(len(d), d[14], list(d)[-1])

# 1 == 1.0 == True, -1 == -1.0, 0 == False == 0.0
k = {1: 'one', -1: 'minus', 0: 'zero', 2.5: 'f', 'x' * 40: 'long'}
for i in range(10):
    k['key%d' % i] = i
print(k[1.0], k[True], k[-1.0], k[False], k[0.0], k[2.5], k['x' * 40], len(k))
k[1.0] = 'ONE'
k[True] = 'TRUE'
print(len(k), k[1], list(k)[0])

# strings that share long prefixes, tuples, frozensets, negative numbers
s = {'prefix-' * 6 + str(i) for i in range(50)}
print(len(s), 'prefix-' * 6 + '49' in s, 'prefix-' * 6 + '50' in s)
t = {(i, -i, 'a'): i for i in range(40)}
print(t[(5, -5, 'a')], (5, 5, 'a') in t, t.get((39, -39, 'a')))
f = {frozenset([i, i + 1]): i for i in range(20)}
print(f[frozenset([4, 3])], frozenset([3]) in f)
n = set(range(-50, 50))
print(len(n), -50 in n, -51 in n, -1 in n, 49 in n)


class P:
    def __init__(self, x, y):
        self.x, self.y = x, y

    def __eq__(self, other):
        return isinstance(other, P) and (self.x, self.y) == (other.x, other.y)

    def __hash__(self):
        return hash((self.x, self.y))


pts = {P(i, i * 2) for i in range(30)}
print(len(pts), P(3, 6) in pts, P(3, 7) in pts, len(pts | {P(0, 0), P(99, 1)}))


class E:                                # neither __eq__ nor __hash__: by identity
    def __init__(self, v):
        self.v = v


class Q:                                # __eq__ only: unhashable, as in CPython
    def __init__(self, x):
        self.x = x

    def __eq__(self, other):
        return isinstance(other, Q) and self.x == other.x


plain = [E(i) for i in range(20)]
seen = set(plain)
print(len(seen), plain[7] in seen, E(7) in seen)
small = {plain[0]: 0, plain[1]: 1}
small[E(0)] = 'new'
print(len(small), small[plain[1]], plain[0] in small)
for bad in ({1: 1}.get, set().add, hash):
    try:
        bad(Q(1))
    except TypeError as e:
        print('TypeError:', e)
print([plain[0]] == [plain[1]], (Q(1),) == (Q(1),), Q(1) in [Q(2), Q(1)])
print(hash(P(1, 2)) == hash(P(1, 2)), hash((1, 'a')) == hash((1, 'a')), hash(-1),
      hash(True), hash(frozenset([1])) == hash(frozenset([1])))

for bad in ([1], {}, {2}):
    try:
        x = {bad: 1}
    except TypeError as e:
        print('TypeError:', e)
try:
    print([1] in {1: 2})
except TypeError:
    print('lookup TypeError')

# order is kept through growth and deletes
o = {}
for w in 'the quick brown fox jumps over the lazy dog again and again'.split():
    o[w] = o.get(w, 0) + 1
del o['quick']
o['zebra'] = 0
print(list(o.items()))
big = dict.fromkeys(range(100), 0) if hasattr(dict, 'fromkeys') else {i: 0 for i in range(100)}
big.clear()
big[5] = 1
print(big, len(big))
