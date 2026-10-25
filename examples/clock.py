# clock: the time module - today's date in several formats, a stopwatch, and a clock
# that ticks for five seconds
import time

now = time.localtime()
print('now:', time.asctime(now))
print('date:', time.strftime('%A, %d %B %Y', now))
print('time:', time.strftime('%H:%M:%S (%I:%M %p)', now))
print('day %d of the year, week day %d (0 = Monday)' % (now.tm_yday, now.tm_wday))
print('seconds since 1970:', int(time.time()))

days = (time.mktime((now.tm_year + 1, 1, 1, 0, 0, 0, 0, 1, 0)) - time.mktime(now)) // 86400
print('days to New Year:', int(days))

start = time.perf_counter()
total = 0
for i in range(2000):
    total += i % 7
print('2000 loop rounds took %.1f seconds' % (time.perf_counter() - start))

print('a clock, for five seconds:')
for i in range(5):
    print('  ', time.strftime('%H:%M:%S'))
    time.sleep(1)
print('done')
