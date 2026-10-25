# time: the MEGA65's real-time clock, with the functions of Python's time module
#
#   import time
#   time.time()                      seconds since 1970-01-01 (a float)
#   time.localtime()                 a struct_time: .tm_year, .tm_hour, ... or t[0], t[3]
#   time.strftime('%H:%M:%S')        '08:15:42'
#   time.sleep(0.5)                  wait half a second
#   time.perf_counter()              for timing code (tenths of a second)
#
# The RTC ($FFD7110-$FFD7116, BCD) keeps the local time the MEGA65 was set to, with no
# time zone: localtime() and gmtime() both give it. sleep() counts video frames (50 or
# 60 a second); perf_counter() and monotonic() read CIA 1's time-of-day clock.

_RTC = 0xFFD7110
_TOD = 0xDC08
_FRAMES = 0xD7FA

timezone = 0
altzone = 0
daylight = 0
tzname = ('UTC', 'UTC')

_DAYNAMES = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
_MONTHNAMES = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
               'August', 'September', 'October', 'November', 'December']
_MONTHDAYS = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
_FIELDS = ['tm_year', 'tm_mon', 'tm_mday', 'tm_hour', 'tm_min', 'tm_sec', 'tm_wday',
           'tm_yday', 'tm_isdst']


class struct_time:
    """A date and time: tm_year, tm_mon (1-12), tm_mday, tm_hour, tm_min, tm_sec,
    tm_wday (0 = Monday), tm_yday (1-366), tm_isdst; also t[0] ... t[8]."""

    def __init__(self, values):
        v = list(values)
        self._v = v
        self.tm_year = v[0]
        self.tm_mon = v[1]
        self.tm_mday = v[2]
        self.tm_hour = v[3]
        self.tm_min = v[4]
        self.tm_sec = v[5]
        self.tm_wday = v[6]
        self.tm_yday = v[7]
        self.tm_isdst = v[8]

    def __getitem__(self, i):
        r = self._v[i]
        return tuple(r) if isinstance(r, list) else r      # (a slice gives a tuple)

    def __len__(self):
        return 9

    def __eq__(self, other):
        return list(self._v) == [other[i] for i in range(9)]

    def __repr__(self):
        parts = ['%s=%d' % (_FIELDS[i], self._v[i]) for i in range(9)]
        return 'time.struct_time(' + ', '.join(parts) + ')'


def _bcd(v):
    return (v >> 4) * 10 + (v & 15)


def _leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


def _days(y, m, d):
    """Days from 1970-01-01 to y-m-d."""
    n = 365 * (y - 1970) + (y - 1969) // 4 - (y - 1901) // 100 + (y - 1601) // 400
    for i in range(m - 1):
        n += _MONTHDAYS[i]
    if m > 2 and _leap(y):
        n += 1
    return n + d - 1


def _rtc():
    """The RTC -> [year, month, day, hour, minute, second] (read twice: no torn reads)."""
    a = None
    b = [peek(_RTC + i) for i in range(6)]
    while a != b:
        a = b
        b = [peek(_RTC + i) for i in range(6)]
    h = a[2]
    if h & 0x80:                                # 24-hour mode
        hour = _bcd(h & 0x3F)
    else:
        hour = _bcd(h & 0x1F) % 12 + (12 if h & 0x20 else 0)
    m = a[4] & 0x1F
    month = m if 10 <= m <= 12 else _bcd(m)     # (BCD; Xemu gives 10-12 in binary)
    return [2000 + _bcd(a[5]), month, _bcd(a[3] & 0x3F), hour, _bcd(a[1] & 0x7F),
            _bcd(a[0] & 0x7F)]


def time():
    """Seconds since 1970-01-01 00:00 (of the RTC's time)."""
    y, mo, d, h, mi, s = _rtc()
    return float(_days(y, mo, d) * 86400 + h * 3600 + mi * 60 + s)


def gmtime(secs=None):
    """Seconds since 1970 -> struct_time (now if no secs)."""
    if secs is None:
        secs = time()
    secs = int(secs)
    days = secs // 86400
    rest = secs % 86400
    wday = (days + 3) % 7                       # 1970-01-01 was a Thursday
    y = 1970
    while True:
        n = 366 if _leap(y) else 365
        if days < n:
            break
        days -= n
        y += 1
    yday = days + 1
    m = 0
    while True:
        n = _MONTHDAYS[m] + (1 if m == 1 and _leap(y) else 0)
        if days < n:
            break
        days -= n
        m += 1
    return struct_time([y, m + 1, days + 1, rest // 3600, rest % 3600 // 60, rest % 60,
                        wday, yday, 0])


localtime = gmtime


def mktime(t):
    """struct_time -> seconds since 1970 (a float)."""
    return float(_days(t[0], t[1], t[2]) * 86400 + t[3] * 3600 + t[4] * 60 + t[5])


def strftime(format, t=None):
    """Format a struct_time (now if none): %Y %y %m %d %H %I %M %S %p %a %A %b %B %j %w
    %c %x %X %%."""
    if t is None:
        t = localtime()
    out = ''
    i = 0
    while i < len(format):
        c = format[i]
        if c != '%' or i + 1 == len(format):
            out += c
            i += 1
            continue
        f = format[i + 1]
        i += 2
        if f == 'Y':
            out += str(t[0])
        elif f == 'y':
            out += '%02d' % (t[0] % 100)
        elif f == 'm':
            out += '%02d' % t[1]
        elif f == 'd':
            out += '%02d' % t[2]
        elif f == 'H':
            out += '%02d' % t[3]
        elif f == 'I':
            out += '%02d' % ((t[3] + 11) % 12 + 1)
        elif f == 'M':
            out += '%02d' % t[4]
        elif f == 'S':
            out += '%02d' % t[5]
        elif f == 'p':
            out += 'PM' if t[3] >= 12 else 'AM'
        elif f == 'a':
            out += _DAYNAMES[t[6]][:3]
        elif f == 'A':
            out += _DAYNAMES[t[6]]
        elif f == 'b':
            out += _MONTHNAMES[t[1] - 1][:3]
        elif f == 'B':
            out += _MONTHNAMES[t[1] - 1]
        elif f == 'j':
            out += '%03d' % t[7]
        elif f == 'w':
            out += str((t[6] + 1) % 7)
        elif f == 'c':
            out += asctime(t)
        elif f == 'x':
            out += strftime('%m/%d/%y', t)
        elif f == 'X':
            out += strftime('%H:%M:%S', t)
        elif f == '%':
            out += '%'
        else:
            out += '%' + f
    return out


def asctime(t=None):
    """'Sun Oct 25 08:15:42 2026'"""
    if t is None:
        t = localtime()
    return '%s %s %2d %02d:%02d:%02d %d' % (_DAYNAMES[t[6]][:3], _MONTHNAMES[t[1] - 1][:3],
                                            t[2], t[3], t[4], t[5], t[0])


def ctime(secs=None):
    return asctime(localtime(secs))


def perf_counter():
    """Seconds (to a tenth) for measuring time: CIA 1's time-of-day clock."""
    h = peek(_TOD + 3)                          # (reading the hours latches the others)
    m = _bcd(peek(_TOD + 2))
    s = _bcd(peek(_TOD + 1))
    tenths = peek(_TOD) & 15                    # (reading the tenths releases them)
    hour = _bcd(h & 0x1F) % 12 + (12 if h & 0x80 else 0)
    return hour * 3600 + m * 60 + s + tenths / 10


monotonic = perf_counter
process_time = perf_counter


def sleep(secs):
    """Wait secs seconds (counted in video frames)."""
    rate = 60 if peek(0xD06F) & 0x80 else 50
    frames = int(secs * rate + 0.5)
    while frames > 0:
        step = min(frames, 200)
        start = peek(_FRAMES)
        while (peek(_FRAMES) - start) & 255 < step:
            pass
        frames -= step
