# gfxdemo: draws with lib/gfx.py - colours, rectangles, lines, circles and a sine
# wave on the 320x200 256-colour screen. Press a key to go back to the text screen.
import gfx
import math

gfx.mode()
gfx.border(gfx.BLACK)

# a sky that fades from dark to light blue, and green ground
for i in range(10):
    gfx.fill_rect(0, i * 12, 320, 12, gfx.rgb(0, i // 3, 2 + i // 4))
gfx.fill_rect(0, 120, 320, 80, gfx.rgb(0, 2, 0))

# the sun, with rays
gfx.fill_circle(260, 40, 22, gfx.YELLOW)
for a in range(0, 360, 30):
    r = math.radians(a)
    gfx.line(260 + int(28 * math.cos(r)), 40 + int(28 * math.sin(r)),
             260 + int(38 * math.cos(r)), 40 + int(38 * math.sin(r)), gfx.YELLOW)

# a house
gfx.fill_rect(40, 80, 80, 60, gfx.rgb(4, 2, 1))
gfx.rect(40, 80, 80, 60, gfx.WHITE)
gfx.line(36, 80, 80, 50, gfx.RED)
gfx.line(80, 50, 124, 80, gfx.RED)
gfx.line(36, 80, 124, 80, gfx.RED)
gfx.fill_rect(70, 110, 20, 30, gfx.BROWN)
gfx.fill_rect(50, 92, 14, 14, gfx.LIGHTBLUE)
gfx.fill_rect(96, 92, 14, 14, gfx.LIGHTBLUE)

# rings of colour
for i in range(6):
    gfx.circle(200, 150, 8 + i * 5, gfx.rgb(5, i, 5 - i))

# a sine wave over the ground
for x in range(0, 320, 2):
    gfx.plot(x, 175 + int(15 * math.sin(x / 20)), gfx.WHITE)

# the colour cube along the bottom
for i in range(216):
    gfx.vline(52 + i, 192, 199, 16 + i)

gfx.wait_key()
gfx.text()
print('gfxdemo: done')
