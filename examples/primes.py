# Sieve of Eratosthenes
LIMIT = 2000
sieve = [True] * (LIMIT + 1)
sieve[0] = sieve[1] = False
for n in range(2, LIMIT + 1):
    if n * n > LIMIT:
        break
    if sieve[n]:
        for m in range(n * n, LIMIT + 1, n):
            sieve[m] = False
primes = [n for n in range(LIMIT + 1) if sieve[n]]
print(len(primes), "primes below", LIMIT)
print("the last ten:", primes[-10:])
twins = [(p, p + 2) for p in primes if p + 2 <= LIMIT and sieve[p + 2]]
print(len(twins), "twin prime pairs, e.g.", twins[:5])
