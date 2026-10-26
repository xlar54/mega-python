# bignums: ints beyond 32 bits - factorials, Fibonacci numbers, powers of two, exact
# fractions of big numbers and modular powers (up to about 500 digits)


def factorial(n):
    r = 1
    for i in range(2, n + 1):
        r *= i
    return r


f = factorial(50)
print('50! =', f)
print('    it has', len(str(f)), 'digits, the sum of which is', sum(int(c) for c in str(f)))

a, b = 0, 1
for _ in range(300):
    a, b = b, a + b
print('fib(300) =', a)

p = 2 ** 256
print('2**256 =', p)
print('       = 0x%x' % p)
print('   with commas: {:,}'.format(2 ** 100))

n = 10 ** 40 + 7
q, r = divmod(n, 12345678901234567)
print('divmod(10**40 + 7, 12345678901234567) =', (q, r), q * 12345678901234567 + r == n)

# Fermat's little theorem: a ** (p - 1) % p == 1 for a prime p
m = 2 ** 127 - 1
print('2**127 - 1 is a Mersenne prime:', pow(3, m - 1, m) == 1)
print('negative numbers:', -(2 ** 70) // 7, -(2 ** 70) % 7, -(2 ** 70) >> 60)
