# floats: literals, repr, arithmetic, mixing with ints, conversions, formatting, math
print(1.5, 0.1, 2.0, -3.25, 1e10, 1.5e-7, 123456789.125, .5, 7.)
print(0.1 + 0.2, 1 / 3, 2 / 3, 10 / 4, 1e16, 1e15, 0.0001, 0.00001)
print(1e300 * 1e10, -1e300 * 1e10, 5e-324, 2.2250738585072014e-308, 1.7976931348623157e308)
print(3 * 0.1, 0.1 * 3 == 0.3, 1.1 + 2.2, 100.0 - 99.9, 7.5 / 2.5)
print(7 // 2.0, -7 // 2.0, 7.5 % 2, -7.5 % 2, 7.5 % -2, divmod(7.5, 2), divmod(-1.0, 3))
print(2 ** 0.5, 2.0 ** 10, 10 ** -2, 2 ** -1, 1.5 ** 2, (-2.0) ** 3, 4 ** 0.5, 8 ** (1 / 3))
print(-0.0, 0.0 == -0.0, abs(-2.5), -(-1.5), +1.5)
print(1 == 1.0, 2.5 > 2, 3 < 2.5, 1.0 != 1, [1, 2.0] == [1.0, 2], {1: 'a'}[1.0])
print(int(3.9), int(-3.9), float(7), float('1.25'), float(' -2.5e3 '), float('inf'), float('-nan'))
print(round(2.5), round(3.5), round(-2.5), round(0.5), round(2.675, 2), round(1234.5678, -2), round(1.005, 2))
print(bool(0.0), bool(0.1), str(1.0), repr(0.3), float(), type(1.5), isinstance(2.0, float))
print(sum([0.1] * 10), min(3, 1.5, 2), max([1.0, 2.5, -1]), sorted([3.5, 1, 2.25]))
x = 1.0
for i in range(5):
    x = x * 1.5 + 0.25
print(x)
# formatting
print('%.2f %5.1f %e %g %g %g' % (3.14159, 2.25, 12345.678, 0.0001, 1e-5, 123456789.0))
print('%d %s %r %+.3f %10.4f|' % (3.99, 1.5, 0.1, 2.0, -1.0))
print(f'{3.14159:.3f} {2.5:8.2f}| {1234567.891:,.2f} {0.25:%} {0.5:.0%} {1e20:.3e} {12.0:g}')
print('{:.3} {:.3} {} {:<8.2f}| {:+.1f} {:E} {:G}'.format(1.0, 1234.5, 2.5, 1.5, 3.0, 1.5, 1e-10))
print(format(2.0, '.0f'), format(0.5, '.0f'), format(1.5, '.0f'), format(1e16, 'f'), format(255, '.2f'))
# math
import math
def r(xs):
    return [round(x, 12) for x in xs]   # (libm results differ in the last digit by platform)
print(math.pi, math.e, math.tau, math.inf, math.nan)
print(math.sqrt(2), math.sqrt(16), math.floor(-2.5), math.ceil(2.1), math.trunc(-3.7), math.fabs(-4))
print(r([math.exp(1), math.log(10)]), math.log(8, 2), math.log10(1000), math.log2(1024), math.log(1))
print(math.sin(0), math.cos(0), math.sin(math.pi / 2), math.cos(math.pi), r([math.tan(0.5)]))
print(r([math.atan(1), math.atan2(1, -1), math.asin(1), math.acos(0.5), math.atan(1e10), math.atan2(-2, -3)]))
print(math.degrees(math.pi), math.radians(180), math.hypot(3, 4), math.copysign(2, -1), math.fmod(7, 3))
print(math.isnan(math.nan), math.isinf(-math.inf), math.isfinite(1.0), math.pow(2, 8))
from math import sqrt, pi
print(sqrt(pi), r([math.sin(1), math.cos(1), math.exp(-1), math.log(2), math.sin(100), math.cos(-7.5)]))
try:
    math.sqrt(-1)
except ValueError as e:
    print('ValueError', e)
try:
    1 / 0.0
except ZeroDivisionError:
    print('ZeroDivisionError')
try:
    float('abc')
except ValueError as e:
    print(e)
