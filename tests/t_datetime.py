# datetime (lib/datetime.py on the MEGA65): date, time, datetime, timedelta; arithmetic,
# formats, ordinals, ISO calendar
import datetime
from datetime import date, time, timedelta

d = date(2024, 2, 28)
print(d, repr(d), d + timedelta(days=2), d - date(2023, 12, 25), d.weekday(), d.isoweekday())
print(d.toordinal(), date.fromordinal(738944), d.replace(day=1), d.strftime('%A %d %B %Y, day %j'))
print(tuple(date(2024, 12, 30).isocalendar()), tuple(date(2021, 1, 3).isocalendar()), d.ctime())
print(date(2000, 1, 1) < d, d == date(2024, 2, 28), d != d, sorted([d, date(1999, 9, 9)]))
print(date.fromisoformat('1987-06-05'), {d: 1}[date(2024, 2, 28)], date.max if hasattr(date, 'max') else '')
td = timedelta(days=1, hours=2, minutes=3, seconds=4, milliseconds=5)
print(td, repr(td), td.total_seconds(), -td, abs(-td), td * 2, td // 2, td / timedelta(hours=1))
print(timedelta(0), repr(timedelta(0)), timedelta(seconds=-1), timedelta(weeks=3) > td, bool(timedelta()))
print(timedelta(hours=36).days, timedelta(hours=36).seconds, timedelta(minutes=90) % timedelta(hours=1))
t = time(13, 5)
print(t, repr(t), time(1, 2, 3, 400), repr(time(0, 0)), t.strftime('%I:%M %p'), t < time(14))
dt = datetime.datetime(2024, 3, 10, 23, 59, 30)
print(dt, repr(dt), dt.isoformat(), dt + timedelta(seconds=45), dt - timedelta(days=10))
print(dt - datetime.datetime(2024, 1, 1), dt.date(), dt.time(), dt.weekday(), dt.strftime('%d/%m/%y %H:%M:%S'))
print(datetime.datetime.combine(d, t), datetime.datetime.fromisoformat('2001-02-03T04:05:06'))
print(dt.timestamp() > 0, datetime.datetime.max, timedelta.max, date.min, time.max)
print(isinstance(dt, date), dt == datetime.datetime(2024, 3, 10, 23, 59, 30), dt.replace(hour=1))
print(type(datetime.datetime.now()).__name__, type(date.today()).__name__, datetime.MINYEAR)
try:
    date(2023, 2, 29)
except ValueError as e:
    print('ValueError', e)
