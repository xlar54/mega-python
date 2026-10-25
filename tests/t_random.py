# the random module (lib/random.py on the MEGA65): properties that hold for any
# generator, so CPython prints the same
import random

random.seed(42)
a = [random.random() for i in range(20)]
random.seed(42)
print(a == [random.random() for i in range(20)], all([0 <= x < 1 for x in a]))
random.seed('hello')
b = [random.randint(1, 6) for i in range(10)]
random.seed('hello')
print(b == [random.randint(1, 6) for i in range(10)])
state = random.getstate()
c = random.random()
random.setstate(state)
print(random.random() == c)

rolls = [random.randint(1, 6) for i in range(300)]
print(min(rolls), max(rolls), len([f for f in range(1, 7) if f in rolls]))
evens = [random.randrange(10, 20, 2) for i in range(50)]
print(all([x in [10, 12, 14, 16, 18] for x in evens]))
print(all([0 <= random.randrange(5) < 5 for i in range(50)]))
print(all([2.5 <= random.uniform(2.5, 3.5) <= 3.5 for i in range(50)]))
print(random.choice('xyz') in 'xyz', random.choice([7]))
deck = list(range(52))
random.shuffle(deck)
print(sorted(deck) == list(range(52)), len(deck))
s = random.sample(range(100), 10)
print(len(s), len(sorted(s)) == 10, all([s.count(x) == 1 for x in s]))
print(random.choices(['heads', 'tails'], weights=[1, 0], k=3))
print(len(random.choices('abc', k=7)))
bits = random.getrandbits(8)
print(isinstance(bits, int), 0 <= bits < 256)
g = [random.gauss(10, 2) for i in range(200)]
print(8 < sum(g) / len(g) < 12)
for bad in [lambda: random.choice([]), lambda: random.randrange(5, 5),
            lambda: random.sample([1, 2], 3)]:
    try:
        bad()
    except (IndexError, ValueError) as e:
        print(type(e).__name__)
