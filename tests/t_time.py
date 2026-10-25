# the time module (lib/time.py on the MEGA65): conversions of fixed times, and checks
# of the clock that hold anywhere
import time

t = time.gmtime(0)
print(t)
print(t.tm_year, t.tm_mon, t.tm_mday, t.tm_wday, t.tm_yday, t[0], t[6], len(t))
for secs in [951782400, 1700000000, 1234567890, 86399]:
    t = time.gmtime(secs)
    print(time.strftime('%Y-%m-%d %H:%M:%S %a %A %b %B %j %y %I %p %w %%', t))
    print(time.asctime(t))
print(time.strftime('%x %X', time.gmtime(1700000000)))
print(time.gmtime(86400 * 365)[0], time.gmtime(86400 * (365 * 2 + 59))[1:3])

now = time.time()
print(isinstance(now, float), now > 1.7e9)
lt = time.localtime()
print(2024 <= lt.tm_year <= 2100, 1 <= lt[1] <= 12, 1 <= lt[2] <= 31, 0 <= lt[3] < 24)
print(len(time.strftime('%H:%M:%S')), len(time.ctime()))
start = time.perf_counter()
time.sleep(0.2)                 # (the test runner's Xemu runs faster than real time, so
elapsed = time.perf_counter() - start   # only the type and sign are checked here)
print(isinstance(elapsed, float), elapsed >= 0)
