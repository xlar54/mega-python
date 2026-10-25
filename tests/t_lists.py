# lists
a = [3, 1, 2]
a.append(5)
a.insert(0, 9)
print(a, len(a), a[0], a[-1], a[1:3])
a.extend([7, 7])
print(a.count(7), a.index(5), a.pop(), a.pop(0), a)
a.remove(1)
print(a)
a.reverse()
print(a)
a.sort()
print(a)
a.sort(reverse=True)
print(a)
b = a.copy()
b[0] = 100
print(a, b)
del b[1]
print(b)
print([1, 2] + [3], [0] * 4, [[1, 2], [3]], [] == [], [1, 2] < [1, 3])
print(3 in a, 42 in a, 42 not in a)
print(list(range(5)), list(range(2, 10, 3)), list(range(10, 0, -3)))
print([x * x for x in range(6)])
print([x for x in range(20) if x % 3 == 0])
print([(i, j) for i in range(3) for j in range(2)])
print([[r * 3 + c for c in range(3)] for r in range(2)])
print(sum([1, 2, 3, 4]), min([4, 2, 8]), max([4, 2, 8]), sorted([3, 1, 2]))
nums = [5, 3, 8, 1, 9, 2]
print(sorted(nums, reverse=True), sorted(nums, key=lambda v: -v))
pairs = [(1, "b"), (2, "a"), (0, "c")]
print(sorted(pairs), sorted(pairs, key=lambda p: p[1]))
m = [[0] * 3 for _ in range(3)]
m[1][1] = 5
print(m)
s = list("hello")
print(s, "".join(s))
c = [1, 2, 3]
c += [4]
d = c
d += [5]
print(c, d is c)
e = [10, 20, 30, 40, 50]
print(e[::2], e[::-1], e[-2:], e[:-2], e[1:-1])
e[0] = -1
print(e)
f = []
for i in range(50):
    f.append(i * 2)
print(len(f), f[49], sum(f))
f.clear()
print(f, len(f))
print(list(reversed([1, 2, 3])), list(enumerate("ab")), list(zip([1, 2], "xy")))
g = [4, 1, 3]
g.sort(key=lambda v: v % 3)
print(g)
print(any([0, 0, 1]), all([1, 1, 0]), any([]), all([]))
