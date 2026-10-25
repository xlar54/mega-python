# collections (lib/collections.py on the MEGA65, lib-colls.py on the disk) and textwrap
from collections import deque, Counter, defaultdict
import textwrap

d = deque([1, 2, 3])
d.append(4)
d.appendleft(0)
print(d, len(d), d[0], d[-1], 2 in d)
print(d.pop(), d.popleft(), d)
d.rotate(1)
print(d)
d.rotate(-2)
print(d, list(d), [x * 10 for x in d])
last3 = deque(maxlen=3)
for i in range(6):
    last3.append(i)
print(last3, last3.maxlen)
d.extend([7, 8])
d.extendleft([-1, -2])
print(d, d.count(7))
try:
    deque().pop()
except IndexError:
    print('IndexError')

c = Counter('abracadabra')
print(c)
print(c['a'], c['z'], c.most_common(2), len(c), 'b' in c)
c.update('aaz')
c.subtract(['b'])
print(c.most_common(3), c.total(), sorted(c.elements())[:4])
words = Counter(['red', 'blue', 'red', 'green', 'blue', 'red'])
print(words.most_common(), sorted(words), Counter())

dd = defaultdict(list)
for word in ['apple', 'avocado', 'banana', 'blueberry', 'cherry']:
    dd[word[0]].append(word)
print(sorted(dd.keys()), dd['a'], dd['z'], len(dd), 'b' in dd)
counts = defaultdict(int)
for ch in 'hello':
    counts[ch] += 1
print(counts['l'], counts['q'], sorted(counts.items()))
print(defaultdict(int, {'x': 1}))

text = ('The MEGA65 is a complete 8-bit computer, fully compatible with the Commodore 64 '
        'and 65, with a 40 MHz CPU and a supercalifragilisticexpialidocious memory map.')
print(textwrap.wrap(text, 30))
print(textwrap.fill(text, 40, initial_indent='* ', subsequent_indent='  '))
print(textwrap.wrap('a verylongwordthatdoesnotfit here', 10))
print(textwrap.wrap('a verylongwordthatdoesnotfit here', 10, break_long_words=False))
print(textwrap.shorten('Hello there, my dear world!', 20), '|', textwrap.shorten('short', 20))
print(repr(textwrap.dedent('    one\n      two\n\n    three')))
print(repr(textwrap.indent('a\n\nb', '> ')))
