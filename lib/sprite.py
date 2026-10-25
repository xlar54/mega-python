# sprite: the MEGA65's 8 hardware sprites (24x21 pixels, over text or graphics)
#
#   from sprite import Sprite
#   s = Sprite(0, ['....XXXX....', ...], color=7)   # a shape of up to 21 rows
#   s.move(100, 50)                                  # x, y on the 320x200 screen
#   s.show()
#
# Shapes: rows of '.' (or space) and any other character for a set pixel, up to 24
# wide. In multicolour mode (s.multicolor(True)) each character is a double-wide pixel:
# '.' clear, '1' shared colour 1, '2' the sprite's colour, '3' shared colour 2.
# The shapes live at the end of bank 5 ($5FA00, after the gfx picture); load(),
# files(), import and os.listdir() load through bank 5, so set shapes after those.

DATA = 0x5FA00                  # 8 shapes of 64 bytes
POINTERS = 0x5FC00              # 8 sprite pointers (16-bit: address / 64)
VIC = 0xD000
LEFT = 24                       # the sprite X of the screen's left edge
TOP = 50                        # the sprite Y of its top edge
FRAMES = 0xD7FA


def _fix():
    # real hardware shows sprites 16 pixels left of Xemu ($D60F bit 5: real hardware)
    return 16 if peek(0xD60F) & 0x20 else 0


def _where():
    poke(0xD02F, 0x47)                  # VIC-IV registers on
    poke(0xD02F, 0x53)
    poke(0xD06C, POINTERS & 255)        # where the pointers are, 16-bit pointers
    poke(0xD06D, (POINTERS >> 8) & 255)
    poke(0xD06E, 0x80 | (POINTERS >> 16))


def _setup():
    _where()
    for n in range(8):
        p = DATA // 64 + n
        poke(POINTERS + 2 * n, p & 255)
        poke(POINTERS + 2 * n + 1, p >> 8)


_setup()
X_FIX = _fix()


def _bit(reg, n, on):
    if on:
        poke(reg, peek(reg) | (1 << n))
    else:
        poke(reg, peek(reg) & (255 - (1 << n)))


class Sprite:
    def __init__(self, n, shape=None, color=1):
        self.n = n
        self.x = 0
        self.y = 0
        self.multi = False
        self.color(color)
        if shape:
            self.shape(shape)

    def shape(self, rows):
        """Set the picture: up to 21 strings (see the top of this file)."""
        base = DATA + 64 * self.n
        for r in range(21):
            row = rows[r] if r < len(rows) else ''
            bits = 0
            if self.multi:
                for i in range(12):
                    ch = row[i] if i < len(row) else '.'
                    v = ord(ch) - 48 if ch in '123' else 0
                    bits = bits * 4 + v
            else:
                for i in range(24):
                    on = i < len(row) and row[i] not in '. '
                    bits = bits * 2 + (1 if on else 0)
            poke(base + 3 * r, bits >> 16)
            poke(base + 3 * r + 1, (bits >> 8) & 255)
            poke(base + 3 * r + 2, bits & 255)
        poke(base + 63, 0)

    def color(self, c):
        poke(VIC + 0x27 + self.n, c)

    def move(self, x, y):
        """Put the sprite's top-left corner at x, y (screen pixels; it may go off
        the edges)."""
        self.x = x
        self.y = y
        hx = x + LEFT + X_FIX
        hy = y + TOP
        poke(VIC + 2 * self.n, hx & 255)
        _bit(VIC + 0x10, self.n, hx & 256)
        poke(VIC + 2 * self.n + 1, hy & 255)

    def show(self):
        _where()                            # (a video mode change resets it)
        _bit(VIC + 0x15, self.n, True)

    def hide(self):
        _bit(VIC + 0x15, self.n, False)

    def expand(self, wide, tall):
        """Double the width and / or the height."""
        _bit(VIC + 0x1D, self.n, wide)
        _bit(VIC + 0x17, self.n, tall)

    def behind(self, flag):
        """Behind the text or graphics (True) or in front (False)."""
        _bit(VIC + 0x1B, self.n, flag)

    def multicolor(self, flag):
        """Multicolour mode: call before shape() (it reads the rows differently)."""
        self.multi = flag
        _bit(VIC + 0x1C, self.n, flag)

    def hit(self):
        """True if this sprite touched another one since collisions() last ran."""
        return bool(_hits[0] & (1 << self.n))


_hits = [0, 0]


def multicolors(c1, c2):
    """The two colours that multicolour sprites share."""
    poke(VIC + 0x25, c1)
    poke(VIC + 0x26, c2)


def collisions():
    """-> (sprites that touched a sprite, sprites that touched text or graphics) as
    bit masks, since the last call (reading the registers clears them)."""
    _hits[0] = peek(VIC + 0x1E)
    _hits[1] = peek(VIC + 0x1F)
    return _hits[0], _hits[1]


def hide_all():
    poke(VIC + 0x15, 0)


def wait_frame(frames=1):
    """Wait for the next video frame(s): 50 a second; moves look smooth when they
    are made once per frame."""
    start = peek(FRAMES)
    while (peek(FRAMES) - start) & 255 < frames:
        pass
