# gfx: 320x200 graphics in 256 colours (the MEGA65's full-colour character mode)
#
#   import gfx
#   gfx.mode()                       # the graphics screen (cleared)
#   gfx.border(gfx.BLUE)
#   gfx.line(0, 0, 319, 199, gfx.YELLOW)
#   gfx.circle(160, 100, 50, gfx.rgb(5, 2, 0))
#   gfx.draw_text(10, 10, 'Hello', gfx.WHITE)
#   gfx.wait_key()
#   gfx.text()                       # back to the text screen (as cls() does)
#
# The picture is 64000 bytes in bank 5: 40 columns of 25 characters, each 8x8 bytes,
# one byte per pixel, column after column. Colours 0-15 are the C64's; mode() sets
# 16-231 to a 6x6x6 colour cube (rgb()) and 232-255 to greys (grey()).
# Clearing and filled shapes use the DMA controller: a job written at $7FE0.

WIDTH = 320
HEIGHT = 200
BITMAP = 0x50000                # the pixels (bank 5)
CHARS = 0x1D800                 # 40 x 25 character pointers (bank 1)
DMALIST = 0x7FE0                # the DMA job (bank 0: $7FE0-$7FFF)
COLRAM = 0xFF80000

BLACK, WHITE, RED, CYAN, PURPLE, GREEN, BLUE, YELLOW = 0, 1, 2, 3, 4, 5, 6, 7
ORANGE, BROWN, PINK, DARKGREY, GREY, LIGHTGREEN, LIGHTBLUE, LIGHTGREY = 8, 9, 10, 11, 12, 13, 14, 15


def border(c):
    poke(0xD020, c)


def background(c):
    poke(0xD021, c)


def _dma(command, count, src, dst, step=1):
    """Run one DMA job: command 0 = copy src -> dst, 3 = fill dst with the byte src."""
    job = [0x0B, 0x80, (src >> 20) & 255, 0x81, dst >> 20]
    if step != 1:
        job += [0x85, step]
    job += [0, command, count & 255, count >> 8, src & 255, (src >> 8) & 255,
            (src >> 16) & 15, dst & 255, (dst >> 8) & 255, (dst >> 16) & 15, 0, 0, 0]
    for i, b in enumerate(job):
        poke(DMALIST + i, b)
    poke(0xD702, 0)
    poke(0xD704, 0)
    poke(0xD701, DMALIST >> 8)
    poke(0xD705, DMALIST & 255)          # starts it


def palette(index, r, g, b):
    """Set a colour, r, g, b 0-255."""
    poke(0xD100 + index, (r & 15) * 16 + (r >> 4))
    poke(0xD200 + index, (g & 15) * 16 + (g >> 4))
    poke(0xD300 + index, (b & 15) * 16 + (b >> 4))


def rgb(r, g, b):
    """The colour of the 6x6x6 cube: r, g, b 0-5."""
    return 16 + 36 * r + 6 * g + b


def grey(level):
    """A grey, level 0-23."""
    return 232 + level


def _palette():
    i = 16
    for r in range(6):
        for g in range(6):
            for b in range(6):
                palette(i, r * 51, g * 51, b * 51)
                i += 1
    for level in range(24):
        palette(232 + level, level * 11, level * 11, level * 11)


def mode():
    """Switch to the 320x200 graphics screen and clear it."""
    poke(0xD02F, 0x47)                  # VIC-IV registers on
    poke(0xD02F, 0x53)
    sprites = [peek(0xD06C), peek(0xD06D), peek(0xD06E)]
    poke(0xD031, peek(0xD031) & 0x7F)   # 40 columns
    poke(0xD054, peek(0xD054) | 5)      # 16-bit characters, full colour
    poke(0xD058, 80)                    # bytes per row
    poke(0xD059, 0)
    poke(0xD05E, 40)                    # characters per row
    poke(0xD060, CHARS & 255)
    poke(0xD061, (CHARS >> 8) & 255)
    poke(0xD062, CHARS >> 16)
    poke(0xD063, 0)
    for i in range(3):                  # ($D031 reset the sprite pointers' address)
        poke(0xD06C + i, sprites[i])
    # each screen position shows its own character, numbered column by column
    first = BITMAP // 64
    if peek(CHARS) != first & 255 or peek(CHARS + 1998) != (first + 999) & 255:
        for col in range(40):
            v = first + col * 25
            a = CHARS + 2 * col
            for row in range(25):
                poke(a, v & 255)
                poke(a + 1, v >> 8)
                v += 1
                a += 80
    _dma(3, 2000, 0, COLRAM)
    _palette()
    clear()


def text():
    """Back to the text screen (cleared)."""
    cls()


def clear(c=0):
    _dma(3, 64000, c, BITMAP)


def plot(x, y, c):
    if 0 <= x < 320 and 0 <= y < 200:
        poke(BITMAP + (x >> 3) * 1600 + y * 8 + (x & 7), c)


def point(x, y):
    """The colour at x, y."""
    return peek(BITMAP + (x >> 3) * 1600 + y * 8 + (x & 7))


def fill_rect(x, y, w, h, c):
    """A filled rectangle (clipped to the screen)."""
    if x < 0:
        w += x
        x = 0
    if y < 0:
        h += y
        y = 0
    w = min(w, 320 - x)
    h = min(h, 200 - y)
    if w <= 0 or h <= 0:
        return
    end = x + w
    while x < end:
        col = BITMAP + (x >> 3) * 1600 + y * 8
        if x & 7 == 0 and x + 8 <= end:
            _dma(3, h * 8, c, col)          # a whole character column: one block
            x += 8
        else:
            _dma(3, h, c, col + (x & 7), 8)  # one pixel column (every 8th byte)
            x += 1


def hline(x0, x1, y, c):
    if x1 < x0:
        x0, x1 = x1, x0
    fill_rect(x0, y, x1 - x0 + 1, 1, c)


def vline(x, y0, y1, c):
    if y1 < y0:
        y0, y1 = y1, y0
    fill_rect(x, y0, 1, y1 - y0 + 1, c)


def rect(x, y, w, h, c):
    hline(x, x + w - 1, y, c)
    hline(x, x + w - 1, y + h - 1, c)
    vline(x, y, y + h - 1, c)
    vline(x + w - 1, y, y + h - 1, c)


def line(x0, y0, x1, y1, c):
    if y0 == y1:
        return hline(x0, x1, y0, c)
    if x0 == x1:
        return vline(x0, y0, y1, c)
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    sx = 1 if x0 < x1 else -1
    sy = 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        plot(x0, y0, c)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def circle(xc, yc, r, c):
    x = r
    y = 0
    err = 1 - r
    while x >= y:
        plot(xc + x, yc + y, c)
        plot(xc - x, yc + y, c)
        plot(xc + x, yc - y, c)
        plot(xc - x, yc - y, c)
        plot(xc + y, yc + x, c)
        plot(xc - y, yc + x, c)
        plot(xc + y, yc - x, c)
        plot(xc - y, yc - x, c)
        y += 1
        if err < 0:
            err += 2 * y + 1
        else:
            x -= 1
            err += 2 * (y - x) + 1


def fill_circle(xc, yc, r, c):
    x = r
    y = 0
    err = 1 - r
    while x >= y:
        hline(xc - x, xc + x, yc + y, c)
        hline(xc - x, xc + x, yc - y, c)
        hline(xc - y, xc + y, yc + x, c)
        hline(xc - y, xc + y, yc - x, c)
        y += 1
        if err < 0:
            err += 2 * y + 1
        else:
            x -= 1
            err += 2 * (y - x) + 1


FONT = 0x29800                  # the text screen's font (8 bytes per character)


def _code(ch):
    """An ASCII character -> its glyph number in FONT."""
    c = ord(ch) & 127
    if c < 32:
        return 32
    if c < 64 or 64 < c < 91:
        return c
    if c == 64:
        return 0
    if c < 96:
        return c - 64
    if c == 96:
        return 0x40
    if c < 123:
        return c - 96
    return c - 32 if c < 127 else 0x66


def draw_text(x, y, text, c, bg=None):
    """Text in the 8x8 font, its top-left corner at x, y (bg: a background colour,
    else the picture shows through). Returns the x after it."""
    for ch in text:
        glyph = FONT + _code(ch) * 8
        for row in range(8):
            bits = peek(glyph + row)
            for col in range(8):
                if bits & (128 >> col):
                    plot(x + col, y + row, c)
                elif bg is not None:
                    plot(x + col, y + row, bg)
        x += 8
    return x


def wait_key():
    """Wait for a key; -> its ASCII code."""
    while peek(0xD610):                 # (forget keys pressed before)
        poke(0xD610, 0)
    while not peek(0xD610):
        pass
    k = peek(0xD610)
    poke(0xD610, 0)
    return k
