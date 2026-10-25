# integers, operators, comparisons, booleans
print(1 + 2, 7 - 10, 6 * 7)
print(17 // 5, 17 % 5, -17 // 5, -17 % 5, 17 // -5, 17 % -5, -17 // -5, -17 % -5)
print(2 ** 10, 3 ** 0, (-2) ** 3, 10 ** 9)
print(1 << 10, 1024 >> 3, -16 >> 2, 6 & 3, 6 | 3, 6 ^ 3, ~5)
print(-(5), +5, --5)
print(100000 * 1000, 2147483647, -2147483647 - 1)
print(0x1F, 0o17, 0b1010, 1_000_000)
x = 10
x += 5
x -= 3
x *= 2
x //= 5
x %= 3
print(x)
y = 2
y **= 5
y <<= 1
y |= 1
y &= 0xF0
print(y)
print(1 < 2, 2 < 1, 1 <= 1, 2 >= 3, 1 == 1, 1 != 1)
print(1 < 2 < 3, 1 < 3 < 2, 3 > 2 > 1, 1 < 2 > 0)
print(True and False, True or False, not True, not 0)
print(0 or 5, 3 and 4, 0 and 9, None or "x")
print(True + True, True * 10, False - 1)
print(True & False, True | False, True ^ True)
a = 5
print(a is a, a is not None, None is None)
print(abs(-7), abs(7), max(3, 9, 4), min(3, 9, 4))
n = 0
i = 0
while i < 1000:
    n += i
    i += 1
print(n)
big = 1
for k in range(1, 13):
    big *= k
print(big)
