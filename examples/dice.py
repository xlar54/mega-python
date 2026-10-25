# dice: the random module - dice rolls, a shuffled deck, a lottery draw and coin flips
import random

print('ten rolls of a die:', [random.randint(1, 6) for i in range(10)])

counts = [0] * 13
for i in range(600):
    counts[random.randint(1, 6) + random.randint(1, 6)] += 1
print('the sum of two dice, 600 times:')
for total in range(2, 13):
    print('%3d %s %d' % (total, '#' * (counts[total] // 4), counts[total]))

suits = ['spades', 'hearts', 'diamonds', 'clubs']
ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K']
deck = [r + ' of ' + s for s in suits for r in ranks]
random.shuffle(deck)
print('a hand of five:', ', '.join(deck[:5]))
print('lottery numbers:', sorted(random.sample(range(1, 50), 6)))
print('a coin, weighted 3:1:', ''.join(random.choices('HT', weights=[3, 1], k=20)))
print('a random colour:', random.choice(['red', 'green', 'blue', 'yellow']))
print('a float: %.4f, between 10 and 20: %.2f' % (random.random(), random.uniform(10, 20)))

random.seed(2026)
first = [random.randint(1, 100) for i in range(5)]
random.seed(2026)
print('seed(2026) twice gives the same numbers:', first, first == [random.randint(1, 100) for i in range(5)])
