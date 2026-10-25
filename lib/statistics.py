# statistics: averages and spread, as Python's statistics module (on the disk as
# lib-stats.py: 'import statistics' finds it)
#
# CPython computes with exact fractions; here ints are exact but floats are float
# arithmetic, so a float result can differ in its last digit.
import math


class StatisticsError(ValueError):
    pass


def _sum(data):
    total = 0
    for x in data:
        total += x
    return total


def _all_ints(data):
    for x in data:
        if not isinstance(x, int):
            return False
    return True


def _div(total, n, ints):
    if ints and total % n == 0:
        return total // n
    return total / n


def mean(data):
    """The arithmetic mean (an int when ints divide evenly, as in CPython)."""
    data = list(data)
    if not data:
        raise StatisticsError('mean requires at least one data point')
    return _div(_sum(data), len(data), _all_ints(data))


def fmean(data):
    data = list(data)
    if not data:
        raise StatisticsError('fmean requires at least one data point')
    return float(_sum(data)) / len(data)


def geometric_mean(data):
    data = list(data)
    if not data:
        raise StatisticsError('geometric_mean requires a non-empty dataset')
    return math.exp(fmean([math.log(x) for x in data]))


def harmonic_mean(data):
    data = list(data)
    if not data:
        raise StatisticsError('harmonic_mean requires at least one data point')
    if 0 in data:
        return 0
    return len(data) / _sum([1 / x for x in data])


def median(data):
    """The middle value (the mean of the two middle ones for an even count)."""
    data = sorted(data)
    n = len(data)
    if n == 0:
        raise StatisticsError('no median for empty data')
    if n % 2 == 1:
        return data[n // 2]
    return (data[n // 2 - 1] + data[n // 2]) / 2


def median_low(data):
    data = sorted(data)
    if not data:
        raise StatisticsError('no median for empty data')
    return data[(len(data) - 1) // 2]


def median_high(data):
    data = sorted(data)
    if not data:
        raise StatisticsError('no median for empty data')
    return data[len(data) // 2]


def _counts(data):
    counts = {}
    order = []
    for x in data:
        if x in counts:
            counts[x] += 1
        else:
            counts[x] = 1
            order.append(x)
    return counts, order


def mode(data):
    """The most common value (the first one met, if several are)."""
    counts, order = _counts(data)
    if not order:
        raise StatisticsError('no mode for empty data')
    best = order[0]
    for x in order:
        if counts[x] > counts[best]:
            best = x
    return best


def multimode(data):
    """All the most common values, in the order they first appear."""
    counts, order = _counts(data)
    if not order:
        return []
    top = max([counts[x] for x in order])
    return [x for x in order if counts[x] == top]


def _ss(data):
    """The sum of squared deviations, exact for ints: (n sum(x^2) - sum(x)^2) / n."""
    n = len(data)
    if _all_ints(data):
        total = _sum(data)
        return n * _sum([x * x for x in data]) - total * total, n, True
    m = _sum(data) / n
    return _sum([(x - m) * (x - m) for x in data]), 1, False


def pvariance(data, mu=None):
    data = list(data)
    if not data:
        raise StatisticsError('pvariance requires at least one data point')
    ss, scale, ints = _ss(data)
    return _div(ss, scale * len(data), ints)


def variance(data, xbar=None):
    data = list(data)
    if len(data) < 2:
        raise StatisticsError('variance requires at least two data points')
    ss, scale, ints = _ss(data)
    return _div(ss, scale * (len(data) - 1), ints)


def pstdev(data, mu=None):
    return math.sqrt(pvariance(data))


def stdev(data, xbar=None):
    return math.sqrt(variance(data))
