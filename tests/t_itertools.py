# itertools (lib/itertools.py on the MEGA65), imported with 'from itertools import *'
from itertools import *
import itertools

print(list(islice(count(5, 3), 4)))
print(list(islice(cycle('ab'), 5)))
print(list(repeat(7, 3)))
print(list(chain([1, 2], (3,), 'xy')))
print(list(chain.from_iterable([[1], [2, 3], []])))
print(list(accumulate([1, 2, 3, 4])))
print(list(accumulate([1, 2, 3, 4], lambda a, b: a * b, initial=10)))
print(list(compress('abcdef', [1, 0, 1, 0, 1, 1])))
print(list(dropwhile(lambda x: x < 3, [1, 2, 3, 1, 4])))
print(list(takewhile(lambda x: x < 3, [1, 2, 3, 1, 4])))
print(list(filterfalse(None, [0, 1, '', 'a'])))
print(list(starmap(pow, [(2, 3), (3, 2)])))
print(list(islice('abcdefg', 2, None, 2)))
print(list(islice(range(10), 1, 6)))
print(list(zip_longest('ab', [1, 2, 3], fillvalue='-')))
print(list(pairwise('abcd')))
print(list(product('ab', [0, 1])))
print(list(product([0, 1], repeat=2)))
print(list(permutations('abc', 2)))
print(len(list(permutations(range(4)))))
print(list(combinations('abcd', 2)))
print(list(combinations_with_replacement('ab', 2)))
for k, g in groupby('aaabbcaa'):
    print(k, list(g))
for k, g in groupby([1, 3, 2, 4, 5], key=lambda x: x % 2):
    print(k, list(g))
a, b = tee([1, 2, 3])
print(list(a), list(b))
print(next(itertools.count()))
print(list(permutations(range(3))))     # (batched is 3.12: not compared here)
