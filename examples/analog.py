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
DOT = R - 22                    # the dots at 12, 3, 6, 9 (radius 2: 66-70 from the centre)
HOUR_LEN = 45                   # the hands stop short of the dots and ticks, so rubbing
MINUTE_LEN = 60                 # one out never nicks the face
SECOND_LEN = 64


def point(angle, length):
    """The end of a hand: angle in degrees clockwise from 12, length in pixels."""
    a = math.radians(angle)
    return CX + int(round(length * math.sin(a))), CY - int(round(length * math.cos(a)))


def hand(angle, length, width, color):
    x, y = point(angle, length)
    gfx.line(CX, CY, x, y, color)
    # a thicker hand: the same line moved up and down (a flat hand) or left and right
    # (a steep one), so the lines touch at every angle
    flat = abs(x - CX) >= abs(y - CY)
    for d in range(1, width):
        for side in (d, -d):
            ox, oy = (0, side) if flat else (side, 0)
            gfx.line(CX + ox, CY + oy, x + ox, y + oy, color)


def angles(t):
    """(hour, minute, second) hand angles: the hour and minute hands move once a minute."""
    h, m, s = t
    return (h % 12 + m / 60) * 30, m * 6, s * 6


def big_hands(a, color):
    hand(a[0], HOUR_LEN, 2, color)
    hand(a[1], MINUTE_LEN, 2, color)


def second_hand(a, color):
    hand(a[2], SECOND_LEN, 1, color)


def near(a, b):
    """Do two hands at these angles touch (other than at the centre)?"""
    d = abs(a - b) % 360
    return min(d, 360 - d) < 6


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
                x3, y3 = point(minute * 6, DOT)
                gfx.fill_circle(x3, y3, 2, RIM)
        else:
            x1, y1 = point(minute * 6, R - 4)
            x2, y2 = point(minute * 6, R - 8)
            gfx.line(x1, y1, x2, y2, TICK)


gfx.mode()
gfx.border(gfx.BLACK)
gfx.background(gfx.BLACK)
face()
shown = None                    # the angles of the hands on the screen
while not peek(0xD610):         # until a key is pressed
    t = time.localtime()
    now = angles((t.tm_hour, t.tm_min, t.tm_sec))
    if now == shown:
        continue
    if shown:
        second_hand(shown, FACE)            # rub out the second hand
    if not shown or now[1] != shown[1]:     # a new minute: move the other hands
        if shown:
            big_hands(shown, FACE)
        hand(now[0], HOUR_LEN, 2, HOUR)
        hand(now[1], MINUTE_LEN, 2, MINUTE)
    else:                                   # mend a hand the second hand had crossed
        if near(shown[2], now[0]):
            hand(now[0], HOUR_LEN, 2, HOUR)
        if near(shown[2], now[1]):
            hand(now[1], MINUTE_LEN, 2, MINUTE)
    second_hand(now, SECOND)
    gfx.fill_circle(CX, CY, 3, SECOND)
    shown = now
poke(0xD610, 0)
gfx.text()
print('analog clock: stopped at', time.strftime('%H:%M:%S'))
