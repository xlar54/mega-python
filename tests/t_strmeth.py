# the newer str methods: swapcase casefold isascii isdecimal isnumeric rfind rindex
# partition rpartition removeprefix removesuffix expandtabs rsplit
s = 'Hello, World of Python'
print(s.swapcase(), s.casefold(), 'abc'.isascii(), ''.isascii(), '12'.isdecimal(), '1a'.isnumeric())
print(s.rfind('o'), s.rfind('o', 15), s.rfind('zz'), s.rindex('l'), 'aaa'.rfind(''), s.find('o'))
try:
    s.rindex('q')
except ValueError as e:
    print('ValueError', e)
print(s.partition(', '), s.partition('#'), s.rpartition('o'), s.rpartition('#'))
print('k=v=w'.partition('='), 'k=v=w'.rpartition('='))
print('unittest'.removeprefix('unit'), 'unittest'.removesuffix('test'), 'abc'.removeprefix('x'),
      'abc'.removesuffix(''), 'ab'.removeprefix('abc'))
print(repr('a\tbc\td\n\tx'.expandtabs()), repr('a\tb'.expandtabs(4)), repr('a\tb'.expandtabs(0)))
print('a b  c d'.rsplit(), 'a b  c d'.rsplit(None, 1), '  a b  c  '.rsplit(None, 2), ' x '.rsplit(None, 0))
print('a,b,,c'.rsplit(','), 'a,b,,c'.rsplit(',', 1), 'a,b,,c'.rsplit(',', 2), 'aaa'.rsplit('aa', 1))
print('one::two::three'.rsplit('::', 1), ''.rsplit(','), ''.rsplit(), 'abc'.rsplit('x', 1))
try:
    'a'.rsplit('', 1)
except ValueError as e:
    print('ValueError', e)

# methods taken from builtin types as values; their self is checked
print(list(map(str.upper, ['ab', 'cd'])), sorted(['b', 'A', 'c'], key=str.lower))
print(str.join('-', 'abc'), list.count([1, 2, 1], 1), dict.get({'a': 1}, 'a'), str.strip('  x '))
words = ['apple', 'Bob', 'cat']
print(list(filter(str.istitle if False else str.isupper, ['A', 'b'])), [str.title(w) for w in words])
f = str.replace
print(f('aXbX', 'X', '-'), callable(str.upper))
for bad in (lambda: str.upper(5), lambda: list.append('abc', 1), lambda: str.upper()):
    try:
        bad()
    except TypeError:
        print('TypeError')
s = set()
set.add(s, 3)
print(s, frozenset.union(frozenset({1}), {2}), 'abc'.upper(), [1].copy())
big = ('a,' * 300).rsplit(',', 400)
print(len(big), big[:3], big[-2:], 'a b c d'.rsplit(None, 2), 'x-y-z'.rsplit('-', 1))

# start / end positions (find, rfind, index, rindex, count, startswith, endswith)
s = 'abcabcabc'
print(s.find('c', 3), s.find('c', 3, 5), s.find('a', -3), s.rfind('a', 0, 5), s.index('b', 2), s.rindex('b', 0, -2))
print(s.count('a', 1), s.count('a', 1, 4), s.startswith('ca', 2), s.startswith('ab', 3, 4), s.endswith('ca', 0, 4))
print(s.find('z', 2), s.find('a', 100), s.find('', 4), s.count('', 2, 5), s.endswith('c', -1), s.find('b', None, 3))
print(b'xyzxyz'.find(b'z', 3), b'xyzxyz'.count(b'x', 1), b'xyz'.startswith(b'y', 1))
try:
    s.index('a', 7)
except ValueError:
    print('ValueError')
