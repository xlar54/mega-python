# analog: an analog clock on the graphics screen, with hour, minute and second hands,
# set by the real-time clock (MEGA65 only: lib/gfx.py and lib/time.py). Press a key
# to stop it.
import gfx
import time
import math

CX, CY = 160, 100               # the centre
R = 90                          # the face's radius
FACE = gfx.rgb(0, 1, 2)
RIM = gfx.rgb(3, 4, 5)
TICK = gfx.grey(20)
HOUR = gfx.WHITE
MINUTE = gfx.rgb(5, 5, 2)
SECOND = gfx.RED


def point(angle, length):
    """The end of a hand: angle in degrees clockwise from 12, length in pixels."""
    a = math.radians(angle)
    return CX + int(round(length * math.sin(a))), CY - int(round(length * math.cos(a)))


def hand(angle, length, width, color):
    x, y = point(angle, length)
    gfx.line(CX, CY, x, y, color)
    if width > 1:               # a thicker hand: lines on either side
        for d in range(1, width):
            ox, oy = point(angle + 90, d)
            gfx.line(ox, oy, x + ox - CX, y + oy - CY, color)
            ox, oy = point(angle - 90, d)
            gfx.line(ox, oy, x + ox - CX, y + oy - CY, color)


def hands(t, hour_c, minute_c, second_c):
    h, m, s = t
    hand((h % 12 + m / 60) * 30, R * 0.5, 2, hour_c)
    hand((m + s / 60) * 6, R * 0.75, 2, minute_c)
    hand(s * 6, R * 0.8, 1, second_c)     # (short of the hour ticks)
    gfx.fill_circle(CX, CY, 3, SECOND)


def face():
    gfx.fill_circle(CX, CY, R, FACE)
    gfx.circle(CX, CY, R, RIM)
    gfx.circle(CX, CY, R + 1, RIM)
    gfx.circle(CX, CY, R + 2, RIM)
    for minute in range(60):
        if minute % 5 == 0:     # the hours: long ticks, and dots at 12, 3, 6, 9
            x1, y1 = point(minute * 6, R - 4)
            x2, y2 = point(minute * 6, R - 14)
            gfx.line(x1, y1, x2, y2, RIM)
            if minute % 15 == 0:
                gfx.fill_circle(x2 + (CX - x2) // 12, y2 + (CY - y2) // 12, 2, RIM)
        else:
            x1, y1 = point(minute * 6, R - 4)
            x2, y2 = point(minute * 6, R - 8)
            gfx.line(x1, y1, x2, y2, TICK)


gfx.mode()
gfx.border(gfx.BLACK)
gfx.background(gfx.BLACK)
face()
shown = None
while not peek(0xD610):         # until a key is pressed
    t = time.localtime()
    now = (t.tm_hour, t.tm_min, t.tm_sec)
    if now != shown:
        if shown:
            hands(shown, FACE, FACE, FACE)  # rub out the old hands
        hands(now, HOUR, MINUTE, SECOND)
        shown = now
poke(0xD610, 0)
gfx.text()
print('analog clock: stopped at', time.strftime('%H:%M:%S'))
