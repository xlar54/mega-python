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
