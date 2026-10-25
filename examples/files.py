# files: a high-score table kept in a file - open(), write, read, append, with, and
# the os module (os.path.exists, os.rename, os.remove, os.listdir). (Not named load /
# save: a program's globals stay after run(), and those names are the REPL's commands.)
import os

NAME = 'scores.txt'
nl = chr(10)

def save_scores(scores):
    with open(NAME, 'w') as f:
        for name, points in scores:
            f.write('%s %d' % (name, points) + nl)

def load_scores():
    scores = []
    if not os.path.exists(NAME):
        return scores
    for line in open(NAME):
        name, points = line.split()
        scores.append((name, int(points)))
    return scores

def show(title):
    print(title)
    for rank, (name, points) in enumerate(sorted(load_scores(), key=lambda s: -s[1]), 1):
        print('%2d. %-8s %5d' % (rank, name, points))
    print()

if os.path.exists(NAME):
    os.remove(NAME)
print('a table on disk?', os.path.exists(NAME))

save_scores([('ada', 1200), ('grace', 950), ('linus', 400)])
show('after save():')

with open(NAME, 'a') as f:              # 'a' adds to the end of the file
    f.write('margaret 1500' + nl)
    f.write('ken 700' + nl)
show('after two appends:')

text = open(NAME).read()                # (read to the end: the file closes itself)
with open(NAME) as f:                   # (only part read: with closes it)
    first = f.readline()
print(len(text), 'characters,', len(text.splitlines()), 'lines; the first one is',
      repr(first))

os.rename(NAME, 'old.txt')
print('renamed:', os.path.exists(NAME), os.path.exists('old.txt'), 'old.txt' in os.listdir())
os.remove('old.txt')
print('removed:', os.path.exists('old.txt'))

try:
    open('old.txt')
except FileNotFoundError as e:
    print('FileNotFoundError:', e)
