# statistics (lib/statistics.py on the MEGA65, lib-stats.py on the disk)
import statistics

print(statistics.mean([1, 2, 3, 4]), statistics.mean([1, 2, 3]), statistics.mean([2.5, 3.5]))
print(statistics.median([3, 1, 2]), statistics.median([4, 1, 3, 2]), statistics.median_low([1, 2, 3, 4]),
      statistics.median_high([1, 2, 3, 4]))
print(statistics.mode([1, 2, 2, 3, 3]), statistics.mode('abracadabra'), statistics.multimode('aabbc'))
print(statistics.variance([1, 2, 3, 4]), statistics.pvariance([1, 2, 3, 4]), statistics.variance([2, 4, 6]))
print(round(statistics.stdev([2, 4, 4, 4, 5, 5, 7, 9]), 10), statistics.pstdev([2, 4, 4, 4, 5, 5, 7, 9]))
print(statistics.fmean([1, 2, 3, 4]), round(statistics.geometric_mean([1, 4, 16]), 10),
      round(statistics.harmonic_mean([1, 2, 4]), 10))
for f in [statistics.mean, statistics.median, statistics.mode]:
    try:
        f([])
    except statistics.StatisticsError as e:
        print('StatisticsError', isinstance(e, ValueError))
try:
    statistics.variance([1])
except statistics.StatisticsError:
    print('StatisticsError')
