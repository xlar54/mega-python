# datetime: dates, times and the differences between them, as in Python's datetime
# module. They are naive (no time zones); now() and today() read the MEGA65's real-time
# clock through the time module.
#
#   from datetime import date, datetime, timedelta
#   d = date(2024, 2, 28) + timedelta(days=2)       date(2024, 3, 1)
#   datetime.now().strftime('%d %b %Y %H:%M')
import time as _time

MINYEAR = 1
MAXYEAR = 9999
_DIM = [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
_DBM = [0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334]
_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
_MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
           'September', 'October', 'November', 'December']
_US_DAY = 86400000000
_EPOCH = 719163                                 # the ordinal of 1970-01-01


def _leap(y):
    return y % 4 == 0 and (y % 100 != 0 or y % 400 == 0)


def _dim(y, m):
    return 29 if m == 2 and _leap(y) else _DIM[m]


def _ord(y, m, d):
    """Days since 0001-01-01 (which is day 1)."""
    y1 = y - 1
    n = y1 * 365 + y1 // 4 - y1 // 100 + y1 // 400 + _DBM[m] + d
    return n + 1 if m > 2 and _leap(y) else n


def _ymd(n):
    """Day number -> (year, month, day)."""
    n -= 1
    n400, n = divmod(n, 146097)
    n100, n = divmod(n, 36524)
    n4, n = divmod(n, 1461)
    n1, n = divmod(n, 365)
    y = n400 * 400 + n100 * 100 + n4 * 4 + n1 + 1
    if n1 == 4 or n100 == 4:
        return y - 1, 12, 31
    leap = n1 == 3 and (n4 != 24 or n100 == 3)
    m = (n + 50) >> 5
    before = _DBM[m] + (1 if m > 2 and leap else 0)
    if before > n:
        m -= 1
        before -= _DIM[m] + (1 if m == 2 and leap else 0)
    return y, m, n - before + 1


def _check_date(y, m, d):
    if not MINYEAR <= y <= MAXYEAR:
        raise ValueError('year %d is out of range' % y)
    if not 1 <= m <= 12:
        raise ValueError('month must be in 1..12')
    if not 1 <= d <= _dim(y, m):
        raise ValueError('day is out of range for month')


def _check_time(h, mi, s, us):
    if not 0 <= h <= 23:
        raise ValueError('hour must be in 0..23')
    if not 0 <= mi <= 59:
        raise ValueError('minute must be in 0..59')
    if not 0 <= s <= 59:
        raise ValueError('second must be in 0..59')
    if not 0 <= us <= 999999:
        raise ValueError('microsecond must be in 0..999999')


def _strftime(fmt, y, m, d, h, mi, s, us):
    wd = (_ord(y, m, d) + 6) % 7
    out = []
    i = 0
    while i < len(fmt):
        c = fmt[i]
        i += 1
        if c != '%' or i >= len(fmt):
            out.append(c)
            continue
        c = fmt[i]
        i += 1
        if c == 'Y':
            out.append('%04d' % y)
        elif c == 'm':
            out.append('%02d' % m)
        elif c == 'd':
            out.append('%02d' % d)
        elif c == 'H':
            out.append('%02d' % h)
        elif c == 'M':
            out.append('%02d' % mi)
        elif c == 'S':
            out.append('%02d' % s)
        elif c == 'f':
            out.append('%06d' % us)
        elif c == 'y':
            out.append('%02d' % (y % 100))
        elif c == 'I':
            out.append('%02d' % (h % 12 or 12))
        elif c == 'p':
            out.append('AM' if h < 12 else 'PM')
        elif c == 'b':
            out.append(_MONTHS[m - 1][:3])
        elif c == 'B':
            out.append(_MONTHS[m - 1])
        elif c == 'a':
            out.append(_DAYS[wd][:3])
        elif c == 'A':
            out.append(_DAYS[wd])
        elif c == 'w':
            out.append(str((wd + 1) % 7))
        elif c == 'j':
            out.append('%03d' % (_ord(y, m, d) - _ord(y, 1, 1) + 1))
        elif c == 'c':
            out.append(_strftime('%a %b %d %H:%M:%S %Y', y, m, d, h, mi, s, us))
        elif c == 'x':
            out.append(_strftime('%m/%d/%y', y, m, d, h, mi, s, us))
        elif c == 'X':
            out.append(_strftime('%H:%M:%S', y, m, d, h, mi, s, us))
        elif c == '%':
            out.append('%')
        else:
            out.append('%' + c)
    return ''.join(out)


class timedelta:
    """A duration: days, seconds (0-86399) and microseconds (0-999999)."""

    def __init__(self, days=0, seconds=0, microseconds=0, milliseconds=0, minutes=0,
                 hours=0, weeks=0):
        us = ((((weeks * 7 + days) * 24 + hours) * 60 + minutes) * 60 + seconds) * 1000000
        us = round(us + milliseconds * 1000 + microseconds)
        self._us = us
        self.days, r = divmod(us, _US_DAY)
        self.seconds, self.microseconds = divmod(r, 1000000)

    def total_seconds(self):
        return self._us / 1000000

    def __add__(self, other):
        if isinstance(other, timedelta):
            return timedelta(microseconds=self._us + other._us)
        if isinstance(other, date):
            return other + self
        raise TypeError('unsupported operand type(s) for +')

    __radd__ = __add__

    def __sub__(self, other):
        if isinstance(other, timedelta):
            return timedelta(microseconds=self._us - other._us)
        raise TypeError('unsupported operand type(s) for -')

    def __neg__(self):
        return timedelta(microseconds=-self._us)

    def __pos__(self):
        return self

    def __abs__(self):
        return -self if self._us < 0 else self

    def __mul__(self, n):
        return timedelta(microseconds=self._us * n)

    __rmul__ = __mul__

    def __floordiv__(self, other):
        if isinstance(other, timedelta):
            return self._us // other._us
        return timedelta(microseconds=self._us // other)

    def __truediv__(self, other):
        if isinstance(other, timedelta):
            return self._us / other._us
        return timedelta(microseconds=self._us / other)

    def __mod__(self, other):
        return timedelta(microseconds=self._us % other._us)

    def __eq__(self, other):
        return isinstance(other, timedelta) and self._us == other._us

    def __ne__(self, other):
        return not self == other

    def __lt__(self, other):
        return self._us < other._us

    def __le__(self, other):
        return self._us <= other._us

    def __gt__(self, other):
        return self._us > other._us

    def __ge__(self, other):
        return self._us >= other._us

    def __hash__(self):
        return hash(self._us)

    def __bool__(self):
        return self._us != 0

    def __repr__(self):
        parts = []
        if self.days:
            parts.append('days=%d' % self.days)
        if self.seconds:
            parts.append('seconds=%d' % self.seconds)
        if self.microseconds:
            parts.append('microseconds=%d' % self.microseconds)
        return 'datetime.timedelta(' + (', '.join(parts) or '0') + ')'

    def __str__(self):
        mi, s = divmod(self.seconds, 60)
        h, mi = divmod(mi, 60)
        t = '%d:%02d:%02d' % (h, mi, s)
        if self.microseconds:
            t += '.%06d' % self.microseconds
        if self.days:
            t = '%d day%s, ' % (self.days, '' if abs(self.days) == 1 else 's') + t
        return t


class date:
    """A day: year, month, day."""

    def __init__(self, year, month, day):
        _check_date(year, month, day)
        self.year = year
        self.month = month
        self.day = day

    @classmethod
    def today(cls):
        t = _time.localtime()
        return cls(t.tm_year, t.tm_mon, t.tm_mday)

    @classmethod
    def fromordinal(cls, n):
        y, m, d = _ymd(n)
        return cls(y, m, d)

    @classmethod
    def fromisoformat(cls, s):
        y, m, d = s.split('-')
        return cls(int(y), int(m), int(d))

    def toordinal(self):
        return _ord(self.year, self.month, self.day)

    def weekday(self):
        return (self.toordinal() + 6) % 7

    def isoweekday(self):
        return self.weekday() + 1

    def isocalendar(self):
        y = self.year
        week1 = _iso_week1(y)
        n = self.toordinal()
        if n < week1:
            y -= 1
            week1 = _iso_week1(y)
        elif n >= _iso_week1(y + 1):
            y += 1
            week1 = _iso_week1(y)
        week, day = divmod(n - week1, 7)
        return (y, week + 1, day + 1)

    def replace(self, year=None, month=None, day=None):
        return date(self.year if year is None else year, self.month if month is None else month,
                    self.day if day is None else day)

    def timetuple(self):
        return _time.struct_time([self.year, self.month, self.day, 0, 0, 0, self.weekday(),
                                  self.toordinal() - _ord(self.year, 1, 1) + 1, -1])

    def isoformat(self):
        return '%04d-%02d-%02d' % (self.year, self.month, self.day)

    __str__ = isoformat

    def ctime(self):
        return _strftime('%a %b %d 00:00:00 %Y', self.year, self.month, self.day, 0, 0, 0, 0)

    def strftime(self, fmt):
        return _strftime(fmt, self.year, self.month, self.day, 0, 0, 0, 0)

    def __format__(self, spec):
        return self.strftime(spec) if spec else str(self)

    def _key(self):
        return (self.year, self.month, self.day)

    def __add__(self, other):
        if not isinstance(other, timedelta):
            raise TypeError('unsupported operand type(s) for +')
        return date.fromordinal(self.toordinal() + other.days)

    __radd__ = __add__

    def __sub__(self, other):
        if isinstance(other, timedelta):
            return self + -other
        return timedelta(days=self.toordinal() - other.toordinal())

    def __eq__(self, other):
        return isinstance(other, date) and self._key() == other._key()

    def __ne__(self, other):
        return not self == other

    def __lt__(self, other):
        return self._key() < other._key()

    def __le__(self, other):
        return self._key() <= other._key()

    def __gt__(self, other):
        return self._key() > other._key()

    def __ge__(self, other):
        return self._key() >= other._key()

    def __hash__(self):
        return hash(self._key())

    def __repr__(self):
        return 'datetime.date(%d, %d, %d)' % (self.year, self.month, self.day)


def _iso_week1(y):
    """The day number of the Monday of ISO week 1 of year y."""
    first = _ord(y, 1, 1)
    monday = first - (first + 6) % 7
    return monday + 7 if (first + 6) % 7 > 3 else monday


class time:
    """A time of day: hour, minute, second, microsecond."""

    def __init__(self, hour=0, minute=0, second=0, microsecond=0):
        _check_time(hour, minute, second, microsecond)
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond

    def replace(self, hour=None, minute=None, second=None, microsecond=None):
        return time(self.hour if hour is None else hour,
                    self.minute if minute is None else minute,
                    self.second if second is None else second,
                    self.microsecond if microsecond is None else microsecond)

    def isoformat(self):
        t = '%02d:%02d:%02d' % (self.hour, self.minute, self.second)
        return t + '.%06d' % self.microsecond if self.microsecond else t

    __str__ = isoformat

    def strftime(self, fmt):
        return _strftime(fmt, 1900, 1, 1, self.hour, self.minute, self.second,
                         self.microsecond)

    def __format__(self, spec):
        return self.strftime(spec) if spec else str(self)

    def _key(self):
        return (self.hour, self.minute, self.second, self.microsecond)

    def __eq__(self, other):
        return isinstance(other, time) and self._key() == other._key()

    def __ne__(self, other):
        return not self == other

    def __lt__(self, other):
        return self._key() < other._key()

    def __le__(self, other):
        return self._key() <= other._key()

    def __gt__(self, other):
        return self._key() > other._key()

    def __ge__(self, other):
        return self._key() >= other._key()

    def __hash__(self):
        return hash(self._key())

    def __bool__(self):
        return True

    def __repr__(self):
        f = [self.hour, self.minute]
        if self.second or self.microsecond:
            f.append(self.second)
        if self.microsecond:
            f.append(self.microsecond)
        return 'datetime.time(' + ', '.join(str(x) for x in f) + ')'


class datetime(date):
    """A date and a time of day."""

    def __init__(self, year, month, day, hour=0, minute=0, second=0, microsecond=0):
        _check_date(year, month, day)
        _check_time(hour, minute, second, microsecond)
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.second = second
        self.microsecond = microsecond

    @classmethod
    def now(cls):
        t = _time.localtime()
        return cls(t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)

    @classmethod
    def today(cls):
        return cls.now()

    @classmethod
    def combine(cls, d, t):
        return cls(d.year, d.month, d.day, t.hour, t.minute, t.second, t.microsecond)

    @classmethod
    def fromtimestamp(cls, ts):
        return cls._from_us((_EPOCH * 86400 + ts) * 1000000)

    @classmethod
    def fromordinal(cls, n):
        y, m, d = _ymd(n)
        return cls(y, m, d)

    @classmethod
    def fromisoformat(cls, s):
        d = s[:10]
        t = s[11:]
        y, m, dd = d.split('-')
        h = mi = sec = us = 0
        if t:
            if '.' in t:
                t, f = t.split('.')
                us = int((f + '000000')[:6])
            parts = t.split(':')
            h = int(parts[0])
            mi = int(parts[1])
            if len(parts) > 2:
                sec = int(parts[2])
        return cls(int(y), int(m), int(dd), h, mi, sec, us)

    @classmethod
    def _from_us(cls, us):
        us = round(us)
        days, r = divmod(us, _US_DAY)
        y, m, d = _ymd(days)
        s, us = divmod(r, 1000000)
        mi, s = divmod(s, 60)
        h, mi = divmod(mi, 60)
        return cls(y, m, d, h, mi, s, us)

    def _total_us(self):
        return ((self.toordinal() * 86400 + self.hour * 3600 + self.minute * 60 + self.second)
                * 1000000 + self.microsecond)

    def date(self):
        return date(self.year, self.month, self.day)

    def time(self):
        return time(self.hour, self.minute, self.second, self.microsecond)

    def timestamp(self):
        return (self._total_us() - _EPOCH * _US_DAY) / 1000000

    def replace(self, year=None, month=None, day=None, hour=None, minute=None, second=None,
                microsecond=None):
        return datetime(self.year if year is None else year,
                        self.month if month is None else month,
                        self.day if day is None else day,
                        self.hour if hour is None else hour,
                        self.minute if minute is None else minute,
                        self.second if second is None else second,
                        self.microsecond if microsecond is None else microsecond)

    def timetuple(self):
        return _time.struct_time([self.year, self.month, self.day, self.hour, self.minute,
                                  self.second, self.weekday(),
                                  self.toordinal() - _ord(self.year, 1, 1) + 1, -1])

    def isoformat(self, sep='T'):
        return date.isoformat(self) + sep + self.time().isoformat()

    def __str__(self):
        return self.isoformat(' ')

    def ctime(self):
        return self.strftime('%a %b %d %H:%M:%S %Y')

    def strftime(self, fmt):
        return _strftime(fmt, self.year, self.month, self.day, self.hour, self.minute,
                         self.second, self.microsecond)

    def _key(self):
        return (self.year, self.month, self.day, self.hour, self.minute, self.second,
                self.microsecond)

    def __add__(self, other):
        if not isinstance(other, timedelta):
            raise TypeError('unsupported operand type(s) for +')
        return datetime._from_us(self._total_us() + other._us)

    __radd__ = __add__

    def __sub__(self, other):
        if isinstance(other, timedelta):
            return self + -other
        return timedelta(microseconds=self._total_us() - other._total_us())

    def __eq__(self, other):
        return isinstance(other, datetime) and self._key() == other._key()

    def __hash__(self):
        return hash(self._key())

    def __repr__(self):
        f = [self.year, self.month, self.day, self.hour, self.minute]
        if self.second or self.microsecond:
            f.append(self.second)
        if self.microsecond:
            f.append(self.microsecond)
        return 'datetime.datetime(' + ', '.join(str(x) for x in f) + ')'


date.min = date(1, 1, 1)
date.max = date(9999, 12, 31)
date.resolution = timedelta(days=1)
time.min = time(0, 0)
time.max = time(23, 59, 59, 999999)
datetime.min = datetime(1, 1, 1)
datetime.max = datetime(9999, 12, 31, 23, 59, 59, 999999)
timedelta.min = timedelta(-999999999)
timedelta.max = timedelta(days=999999999, hours=23, minutes=59, seconds=59, microseconds=999999)
timedelta.resolution = timedelta(microseconds=1)
