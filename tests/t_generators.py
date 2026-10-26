# generators: yield, yield from, send, close, and generators driving and driven by
# for loops, builtins and other generators


def count(n):
    i = 0
    while i < n:
        yield i
        i += 1


print(list(count(5)))
for x in count(3):
    print('x', x)
g = count(2)
print(next(g), next(g), next(g, 'end'))
print(sum(count(101)), type(g).__name__, repr(g)[:20])


def echo():
    got = yield 'ready'
    while True:
        got = yield got * 2


e = echo()
print(e.send(None), e.send(5), e.send('ab'))


def chain(*its):
    for it in its:
        yield from it
    return 'done'


print(list(chain([1, 2], 'ab', count(2))))


def fib():
    a, b = 0, 1
    while True:
        yield a
        a, b = b, a + b


f = fib()
print([next(f) for _ in range(10)])

def guarded(n):
    for i in range(n):
        try:
            if i == 2:
                raise ValueError('two')
            yield i
        except ValueError as e:
            yield 'caught ' + str(e)
        finally:
            yield 'fin %d' % i


print(list(guarded(4)))


def boom():
    yield 1
    raise KeyError('k')


b = boom()
print(next(b))
try:
    next(b)
except KeyError as e:
    print('KeyError', e)
print(next(b, 'exhausted'), list(b))


def selfish():
    yield next(me)


me = selfish()
try:
    next(me)
except ValueError as e:
    print('ValueError', e)
print(list(me))


def closable():
    yield 1
    yield 2


c = closable()
print(next(c))
c.close()
print(list(c), next(c, 'closed'))


class Tree:
    def __init__(self, v, kids=()):
        self.v = v
        self.kids = kids

    def walk(self):
        yield self.v
        for k in self.kids:
            yield from k.walk()


t = Tree(1, [Tree(2, [Tree(4), Tree(5)]), Tree(3, [Tree(6, [Tree(7)])])])
print(list(t.walk()))


def counter(start):
    def gen(step):
        n = start
        while n < start + 10:
            yield n
            n += step
    return gen


print(list(counter(5)(3)))
print(list(zip(counter(0)(1), 'abc')), list(enumerate(counter(1)(4))))
print(sorted(counter(0)(3), reverse=True), max(counter(2)(2)), 7 in counter(0)(1))
print('-'.join(str(i) for i in counter(0)(5)), dict(zip('xy', counter(0)(1))))

g = counter(0)(1)
for v in g:
    if v == 3:
        break
print('after break', next(g), list(g))


def deep(n):
    if n:
        yield from deep(n - 1)
    yield n


print(list(deep(30))[-3:], sum(deep(60)))


def ret():
    yield 1
    return 5


r = ret()
print(next(r))
try:
    next(r)
except StopIteration:
    print('StopIteration')
try:
    ret().send(3)
except TypeError as e:
    print('TypeError', e)

g1 = counter(0)(1)
print(g1 == g1, g1 == counter(0)(1), sorted(set(counter(0)(2))), set().union(counter(0)(5)))
try:
    len(g1)
except TypeError:
    print('TypeError')
try:
    g1 | {1}
except TypeError as e:
    print('TypeError', e)
try:
    g1[0]
except TypeError:
    print('TypeError')
