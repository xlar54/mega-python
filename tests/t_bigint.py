# ints beyond 32 bits (tail N): arithmetic, comparisons, conversions, literals, formatting
a = 2 ** 40
print(a, -a, a + 1, a - 1, a * 3, type(a) is int)
print(2 ** 100, 3 ** 50, (-3) ** 31, (-2) ** 64)
b = 1
for i in range(1, 31):
    b *= i
print('30! =', b)
print(b // 2 ** 40, b % 1000007, -b // 7, -b % 7, b // -7, b % -7)
print(a == 2 ** 40, a == 2 ** 41, a < a + 1, -a < a, a > 5, 5 < a, a != 7)
print(2147483647 + 1, -2147483647 - 2, 65536 * 65536, -(-2147483647 - 1))
print(int('123456789012345678901234567890'), int('-99999999999999999999'))
print(int('ff' * 10, 16), int('0x' + '1' * 40, 0))
print(float(2 ** 64), float(-3 ** 40), 2 ** 70 / 2 ** 68, 2 ** 64 + 0.5)
print(int(1e20), int(-2.5e30), round(1.5e15))
print(1 << 100, (1 << 100) >> 99, -(2 ** 70) >> 3, 2 ** 70 >> 80, -(2 ** 70) >> 80)
print((2 ** 70) & (2 ** 70 - 1), (2 ** 70) | 1, (2 ** 70) ^ (2 ** 70), -(2 ** 40) & 0xffff, ~(2 ** 50))
print(hash(2 ** 80) == hash(2 ** 80), {2 ** 80: 'x'}[2 ** 80], 2 ** 80 in {2 ** 80})
print(abs(-(2 ** 50)), bool(2 ** 90), str(10 ** 30), repr(-10 ** 25))
print(sorted([2 ** 40, -2 ** 41, 5, 2 ** 33]), max(2 ** 50, 3), sum([2 ** 31, 2 ** 31]))
f = [0, 1]
for i in range(200):
    f.append(f[-1] + f[-2])
print(f[200])
print(len(str(2 ** 1000)), str(2 ** 1000)[:20])
x = 10 ** 50
x += 1
x -= 10 ** 50
print(x, 10 ** 50 // 10 ** 49, divmod(7, 2))
big = 123456789012345678901234567890
print(big, -big, big + 1, 0xffffffffffffffff, 0b1 << 0, 0o7777777777777777, 2147483648, -2147483648)
print(type(-2147483648), 4294967296 // 2, 1_000_000_000_000, big == 123456789012345678901234567890)
print(len(str(2 ** 1600)), 2 ** 1600 % 1000)
print('%d %s %r' % (2, big, -big), f'{big}', str(big).zfill(32))
import math
big = 123456789012345678901234567890
try:
    print('%d' % big)
except Exception as e:
    print(type(e).__name__)
try:
    print('%x' % big)
except Exception as e:
    print(type(e).__name__)
try:
    print(format(big, ','))
except Exception as e:
    print(type(e).__name__)
try:
    print(format(big, '>40'))
except Exception as e:
    print(type(e).__name__)
try:
    print(f'{big:d}')
except Exception as e:
    print(type(e).__name__)
try:
    print(hex(big))
except Exception as e:
    print(type(e).__name__)
try:
    print(bin(2**40))
except Exception as e:
    print(type(e).__name__)
try:
    print(oct(-big))
except Exception as e:
    print(type(e).__name__)
try:
    print(divmod(big, 7))
except Exception as e:
    print(type(e).__name__)
try:
    print(divmod(-big, 10**20))
except Exception as e:
    print(type(e).__name__)
try:
    print(pow(big, 3, 1000003))
except Exception as e:
    print(type(e).__name__)
try:
    print(pow(2, 100, 10**9+7))
except Exception as e:
    print(type(e).__name__)
try:
    print(round(big))
except Exception as e:
    print(type(e).__name__)
try:
    print(math.sqrt(2**80))
except Exception as e:
    print(type(e).__name__)
try:
    print(math.floor(1e25))
except Exception as e:
    print(type(e).__name__)
try:
    print(str(-2**31))
except Exception as e:
    print(type(e).__name__)
try:
    print(int(2**31))
except Exception as e:
    print(type(e).__name__)
try:
    print(abs(-2**31))
except Exception as e:
    print(type(e).__name__)
try:
    print(max(big, 2**100))
except Exception as e:
    print(type(e).__name__)
print((-2 ** 31) // -1, divmod(-2 ** 31, -1), -2 ** 31 % -1)
print({2 ** 40: 'a'}[2.0 ** 40], 2.0 ** 40 in {2 ** 40}, hash(2 ** 40) == hash(2.0 ** 40), {2 ** 70: 1}.get(2.0 ** 70))
