# re (lib/re.py on the MEGA65): search, match, fullmatch, findall, finditer, sub, split,
# groups (named too), classes, anchors, lazy and counted repeats, lookahead, flags, errors
import re

print(re.findall(r'\d+', 'a1b22c333'), re.findall(r'[a-z]+', 'Hi there, you'), re.findall('x', 'abc'))
m = re.search(r'(\w+)@(\w+)\.com', 'mail bob@example.com now')
print(m.group(), m.group(1), m.group(2), m.groups(), m.span(), m.start(2), m.end(1))
print(re.match(r'\d+', '123abc').group(), re.match(r'\d+', 'abc'), re.fullmatch(r'a.c', 'abc') is not None)
print(re.fullmatch(r'a.c', 'abcd'), re.sub(r'(\w+)@(\w+)', r'\2 at \1', 'x@y and p@q'))
print(re.sub(r'\s+', ' ', 'a   b \t c'), re.subn('o', '0', 'foo boo'), re.sub('a', lambda m: 'A', 'banana', 2))
print(re.split(r'[,;]\s*', 'a, b;c,  d'), re.split(r'(-)', '1-2-3'), re.split(r'x*', 'axbc'))
print(re.findall(r'(\w)(\d)', 'a1 b2 c3'), re.findall(r'(\d+)', 'x12y345'), re.findall(r'a*', 'baaa'))
print(re.search(r'^\w+$', 'one\ntwo', re.M).group(), re.findall(r'^\w', 'ab\ncd', re.MULTILINE))
print(re.search('HELLO', 'say hello', re.I).group(), re.findall(r'.', 'a\nb', re.S), re.findall('.', 'a\nb'))
print(re.findall(r'\bcat\b', 'cat concat cat.'), re.findall(r'colou?r', 'color colour'), re.findall(r'\d{2,3}', '1 12 1234'))
print(re.search(r'<.+?>', '<a><b>').group(), re.search(r'<.+>', '<a><b>').group(), re.findall(r'a{2}', 'aaaaa'))
print(re.findall(r'[^aeiou\s]+', 'hello world'), re.findall(r'[\d.]+', 'v1.2 and 3.45'), re.findall(r'[]a]', 'a]b'))
m = re.match(r'(?P<year>\d{4})-(?P<mon>\d\d)', '2024-05-17')
print(m.group('year'), m['mon'], m.groupdict(), m.lastindex)
print(re.findall(r'\w+(?=!)', 'hi! yo? hey!'), re.findall(r'\d(?!0)', '102030'), re.findall(r'(?:ab)+', 'ababx ab'))
p = re.compile(r'(cat|dog)s?')
print(p, p.findall('cats and dogs and a cat'), p.groups, [m.span() for m in p.finditer('dog cats')])
print(re.escape('a.b*c (d)'), re.match(r'\x41\t', 'A\t') is not None, re.findall(r'\S+', ' x  yz '))
print(re.search(r'(a)|(b)', 'b').groups(), re.search(r'(a)|(b)', 'b').groups('-'), re.match(r'a|ab', 'ab').group())
print(re.sub(r'(?P<w>\w+)', r'[\g<w>]', 'a bc'), re.sub(r'(\d)', r'<\g<1>>', 'a1b2'), re.findall(r'\w*', 'ab cd'))
print(bool(re.match('', 'x')), re.match(r'\Aab\Z', 'ab').span(), re.search(r'\d+$', 'abc 99').group())
print(repr(re.search('b', 'abc')), re.compile('x', re.I))
for bad in ['(', 'a**', '[a']:
    try:
        re.compile(bad)
    except re.error:
        print('error', bad)
