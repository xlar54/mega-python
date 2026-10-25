# sets and frozensets (set order differs from CPython's hash order, so most output
# goes through sorted() or uses one-member sets)
s = {3, 1, 2, 3, 1}
print(len(s), sorted(s), 2 in s, 5 in s, 5 not in s)
print(set(), frozenset(), {7}, frozenset([7]), set('aa'), len(set('hello')))
print(type(s).__name__, type(frozenset()).__name__, isinstance(s, set),
      isinstance(s, frozenset), isinstance({}, set), isinstance(s, dict))
print(bool(set()), bool({0}), not set())

a = {1, 2, 3, 4}
b = {3, 4, 5}
print(sorted(a | b), sorted(a & b), sorted(a - b), sorted(a ^ b), sorted(b - a))
print(sorted(a.union(b)), sorted(a.intersection([4, 9])), sorted(a.difference((1,))),
      sorted(a.symmetric_difference(range(3, 7))))
print({1, 2} <= {1, 2, 3}, {1, 2} < {1, 2}, {1, 2} <= {1, 2}, {1, 2, 3} > {1},
      {1} >= {1}, {1, 5} <= {1, 2})
print({1, 2}.issubset([1, 2, 3]), {1, 2, 3}.issuperset({2}), {1}.isdisjoint({2}),
      {1}.isdisjoint([1]))
print({1, 2} == {2, 1}, {1, 2} != {1, 3}, {1} == frozenset({1}), {1} == [1], set() == {})

s = set()
s.add(5)
s.add('x')
s.add(5)
s.add((1, 2))
print(len(s), 'x' in s, (1, 2) in s)
s.remove('x')
s.discard('nope')
s.discard(5)
print(s)
try:
    s.remove(99)
except KeyError as e:
    print('KeyError', e)
s.update([1, 2, 2])
print(sorted(s, key=str))
s.clear()
print(s, len(s))
t = {1, 2, 3}
x = t.pop()
print(len(t), x not in t)
try:
    set().pop()
except KeyError:
    print('empty pop')
t = {1, 2, 3, 4}
t.intersection_update({2, 3, 9})
print(sorted(t))
t.difference_update([3])
print(t)
t.symmetric_difference_update({2, 7})
print(t)

c = {1, 2}
d = c.copy()
d.add(3)
print(sorted(c), sorted(d))
fs = frozenset([1, 2])
print(sorted(fs | {3}), type(fs | {3}).__name__, type({3} | fs).__name__)
print(sorted({fs, frozenset([1, 2]), frozenset()}, key=len))

# comprehensions and iteration
sq = {n * n for n in range(-3, 4)}
print(sorted(sq), sorted({c for c in 'mississippi'}))
print(sum({1, 2, 3}), max({4, 9, 2}), sorted(list({5, 6})), len(tuple({1, 1})))
total = 0
for v in {10, 20}:
    total += v
print(total)
print({x for x in [1, 2] if x > 1}, {(i, j) for i in range(2) for j in range(1)} ==
      {(0, 0), (1, 0)})
for bad in ([1], {}, {2}):
    try:
        {bad}
    except TypeError as e:
        print('TypeError:', e)
try:
    {1} < [1]
except TypeError:
    print('compare TypeError')
try:
    {1} | [2]
except TypeError:
    print('operand TypeError')
print(repr({'a'}), str(frozenset({'b'})), [{1}, {2: 3}])
