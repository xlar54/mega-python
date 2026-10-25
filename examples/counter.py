# counter: the collections module - Counter, defaultdict and deque on a paragraph
from collections import Counter, defaultdict, deque

TEXT = ('the mega65 is a complete 8-bit computer that is fully compatible with the '
        'commodore 64 and the commodore 65 and it runs at 40 mhz with a lot of memory '
        'and a lot of colours and the sound of two sid chips')

words = TEXT.split()
letters = Counter(ch for ch in TEXT if ch.isalpha())

print('the 5 most common letters:')
top = letters.most_common(5)
for ch, n in top:
    print('  %s %3d %s' % (ch, n, '#' * (n * 40 // top[0][1])))

common = Counter(words)
print('the most common words:', common.most_common(4))
print("'the' %d times, 'python' %d times" % (common['the'], common['python']))

# words grouped by their first letter
by_letter = defaultdict(list)
for w in words:
    if w not in by_letter[w[0]]:
        by_letter[w[0]].append(w)
print('words starting with c:', sorted(by_letter['c']))
print('first letters:', ''.join(sorted(by_letter.keys())))

# the last 4 words, in a deque that drops the oldest
last = deque(maxlen=4)
for w in words:
    last.append(w)
print('the last 4 words:', list(last))
last.rotate(1)
print('rotated:', last)
