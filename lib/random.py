# random: pseudo-random numbers, with the functions of Python's random module
#
#   import random
#   random.randint(1, 6)             random.random()          random.choice('abc')
#   random.shuffle(cards)            random.sample(range(49), 6)
#   random.seed(42)                  (the same numbers again after the same seed)
#
# The generator is the "minimal standard" Lehmer generator (x = 16807 x mod 2^31-1,
# done without overflowing 32-bit ints), not CPython's Mersenne Twister: the same
# seed gives other numbers than on a PC. Without a seed it starts from the MEGA65's
# hardware random number generator ($D7EF), so each run differs.
import math

_M = 2147483647                 # 2^31 - 1
_x = 1


def _hw():
    return peek(0xD7EF)         # a hardware random byte (each read makes a new one)


def seed(a=None):
    """Start the sequence again: from a (an int or a string), or from the hardware."""
    global _x
    if a is None:
        v = ((_hw() & 127) << 24) | (_hw() << 16) | (_hw() << 8) | _hw()
    elif isinstance(a, int):
        v = abs(a)
    else:
        v = abs(hash(a))
    _x = v % (_M - 1) + 1


def getstate():
    return _x


def setstate(state):
    global _x
    _x = state


def _next():
    global _x
    hi = _x // 127773           # Schrage: 16807 x mod M without overflow
    lo = _x % 127773
    x = 16807 * lo - 2836 * hi
    if x <= 0:
        x += _M
    _x = x
    return x


def random():
    """A float in [0.0, 1.0)."""
    return (_next() - 1) / 2147483646


def getrandbits(k):
    """An int of k random bits (k up to 31)."""
    if k < 0 or k > 31:
        raise ValueError('number of bits must be between 0 and 31')
    v = 0
    for i in range(k):
        v = v * 2 + (_next() >> 15) % 2
    return v


def _below(n):
    return int(random() * n)


def randrange(start, stop=None, step=1):
    """A random int from range(start, stop, step)."""
    if stop is None:
        start, stop = 0, start
    if step > 0:
        n = (stop - start + step - 1) // step
    elif step < 0:
        n = (stop - start + step + 1) // step
    else:
        raise ValueError('zero step for randrange()')
    if n <= 0:
        raise ValueError('empty range for randrange()')
    return start + step * _below(n)


def randint(a, b):
    """A random int with a <= N <= b."""
    return randrange(a, b + 1)


def choice(seq):
    if not seq:
        raise IndexError('Cannot choose from an empty sequence')
    return seq[_below(len(seq))]


def choices(population, weights=None, k=1):
    """k picks, with replacement (weights: relative chances)."""
    if weights is None:
        return [population[_below(len(population))] for i in range(k)]
    total = 0
    cumulative = []
    for w in weights:
        total += w
        cumulative.append(total)
    out = []
    for i in range(k):
        r = random() * total
        j = 0
        while j < len(cumulative) - 1 and r >= cumulative[j]:
            j += 1
        out.append(population[j])
    return out


def shuffle(x):
    """Shuffle the list x in place."""
    for i in range(len(x) - 1, 0, -1):
        j = _below(i + 1)
        x[i], x[j] = x[j], x[i]


def sample(population, k):
    """k different items from population (a list of them)."""
    pool = list(population)
    n = len(pool)
    if k < 0 or k > n:
        raise ValueError('Sample larger than population or is negative')
    for i in range(k):
        j = i + _below(n - i)
        pool[i], pool[j] = pool[j], pool[i]
    return pool[:k]


def uniform(a, b):
    """A float between a and b."""
    return a + (b - a) * random()


def triangular(low=0.0, high=1.0, mode=None):
    u = random()
    c = 0.5 if mode is None else (mode - low) / (high - low)
    if u > c:
        u = 1.0 - u
        c = 1.0 - c
        low, high = high, low
    return low + (high - low) * math.sqrt(u * c)


def gauss(mu=0.0, sigma=1.0):
    """A normally distributed float (Box-Muller)."""
    u = 1.0 - random()
    return mu + sigma * math.sqrt(-2.0 * math.log(u)) * math.cos(2.0 * math.pi * random())


normalvariate = gauss


def expovariate(lambd=1.0):
    return -math.log(1.0 - random()) / lambd


seed()
