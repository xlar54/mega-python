# string, bisect, heapq, functools, copy (lib/*.py on the MEGA65)
import string
import bisect
import heapq
import functools
import copy

print(string.ascii_letters, string.digits, string.hexdigits, string.octdigits)
print(string.punctuation, len(string.printable), repr(string.whitespace))
print(string.capwords('hello  big   world'), string.capwords('a-b-c', '-'))

a = [1, 2, 4, 4, 8]
print(bisect.bisect_left(a, 4), bisect.bisect_right(a, 4), bisect.bisect(a, 5), bisect.bisect_left(a, 0))
bisect.insort(a, 3)
bisect.insort_left(a, 4)
print(a, bisect.bisect_left(a, 4, 3), bisect.bisect_right(a, 4, 0, 3))
names = [('a', 1), ('b', 3), ('c', 5)]
print(bisect.bisect_left(names, 3, key=lambda p: p[1]))

h = []
for x in [5, 1, 8, 3, 9, 2]:
    heapq.heappush(h, x)
print(h[0], [heapq.heappop(h) for i in range(3)], len(h))
data = [9, 4, 7, 1, 8]
heapq.heapify(data)
print(data[0], heapq.heappushpop(data, 0), heapq.heapreplace(data, 6), sorted(data))
print(heapq.nlargest(2, [3, 1, 4, 1, 5]), heapq.nsmallest(3, [3, 1, 4, 1, 5]),
      heapq.nlargest(1, ['bb', 'a', 'ccc'], key=len))
tasks = []
heapq.heappush(tasks, (2, 'write'))
heapq.heappush(tasks, (1, 'plan'))
heapq.heappush(tasks, (3, 'test'))
print([heapq.heappop(tasks)[1] for i in range(3)])

print(functools.reduce(lambda x, y: x + y, [1, 2, 3, 4]), functools.reduce(lambda x, y: x * y, [2, 3], 10))
try:
    functools.reduce(lambda x, y: x, [])
except TypeError:
    print('TypeError')
def by_len(a, b):
    return len(a) - len(b)
print(sorted(['ccc', 'a', 'bb'], key=functools.cmp_to_key(by_len)))

x = [1, [2, 3], {'k': [4]}]
s = copy.copy(x)
d = copy.deepcopy(x)
x[1].append(9)
x[2]['k'].append(8)
print(s, d, s[1] is x[1], d[1] is x[1])
t = ([1], 2)
print(copy.deepcopy(t), copy.copy('str'), copy.copy(5), copy.deepcopy({'a': (1, [2])}))
st = {1, (2, 3)}
st2 = copy.copy(st)
st2.add(4)
fz = frozenset([5])
print(sorted(st, key=str), sorted(copy.deepcopy(st2), key=str), copy.copy(fz) is fz)
