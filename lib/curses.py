# curses: full-screen text output and key input, as (a subset of) Python's curses
#
#   import curses
#   def main(stdscr):
#       stdscr.clear()
#       stdscr.addstr(2, 10, 'Hello', curses.A_REVERSE)
#       curses.init_pair(1, curses.COLOR_YELLOW, curses.COLOR_BLACK)
#       stdscr.addstr(4, 10, 'in colour', curses.color_pair(1))
#       stdscr.refresh()
#       stdscr.getch()
#   curses.wrapper(main)
#
# The screen is the 80x25 text screen: characters go straight to screen memory
# ($1E800) and colour memory ($FF80000), whose upper bits are the VIC-III attributes
# (blink, reverse, bold, underline). The background colour is one for the whole
# screen (init_pair's bg sets it). Keys come from the typing queue ($D610).

LINES = 25
COLS = 80
_SCREEN = 0x1E800
_COLOUR = 0xFF80000

COLOR_BLACK, COLOR_RED, COLOR_GREEN, COLOR_YELLOW = 0, 1, 2, 3
COLOR_BLUE, COLOR_MAGENTA, COLOR_CYAN, COLOR_WHITE = 4, 5, 6, 7
COLORS = 16
COLOR_PAIRS = 64
_C64 = [0, 2, 5, 7, 6, 4, 3, 1]         # curses colours 0-7 -> MEGA65 colours

A_NORMAL = 0
A_BLINK = 0x10
A_REVERSE = 0x20
A_STANDOUT = 0x20
A_BOLD = 0x40                           # (the VIC-III's bold: colours 16-31)
A_UNDERLINE = 0x80
A_ATTRIBUTES = 0xF0
A_COLOR = 0xFF00

KEY_DOWN, KEY_UP, KEY_LEFT, KEY_RIGHT, KEY_HOME = 258, 259, 260, 261, 262
KEY_BACKSPACE = 263
KEY_F0 = 264
KEY_DC, KEY_IC, KEY_ENTER, KEY_CLEAR = 330, 331, 343, 333
_KEYS = {0x11: KEY_DOWN, 0x91: KEY_UP, 0x9D: KEY_LEFT, 0x1D: KEY_RIGHT, 0x13: KEY_HOME,
         0x14: KEY_BACKSPACE, 0x94: KEY_IC, 0x93: KEY_CLEAR, 0x0D: 10,
         0xF1: KEY_F0 + 1, 0xF2: KEY_F0 + 2, 0xF3: KEY_F0 + 3, 0xF4: KEY_F0 + 4,
         0xF5: KEY_F0 + 5, 0xF6: KEY_F0 + 6, 0xF7: KEY_F0 + 7, 0xF8: KEY_F0 + 8}

_pairs = [1] * COLOR_PAIRS              # pair -> MEGA65 foreground colour (0: white)


def KEY_F(n):
    return KEY_F0 + n


class error(Exception):
    pass


def _code(ch):
    """An ASCII character -> its screen code (the interpreter's font)."""
    c = ord(ch) & 127
    if c < 32:
        return 32
    if c < 64:
        return c
    if c == 64:
        return 0
    if c < 91:
        return c
    if c < 96:
        return c - 64                   # [ \ ] ^ _
    if c == 96:
        return 0x40
    if c < 123:
        return c - 96                   # a-z
    if c < 127:
        return c - 32                   # { | } ~
    return 0x66


def color_pair(n):
    return n << 8


def pair_number(attr):
    return (attr & A_COLOR) >> 8


def init_pair(pair, fg, bg):
    """Colour pair n: fg and bg are COLOR_* (0-7) or MEGA65 colours (8-15). The MEGA65
    has one background colour for all the screen: the last bg given wins."""
    if not 1 <= pair < COLOR_PAIRS:
        raise ValueError('color pair out of range')
    _pairs[pair] = _C64[fg] if fg < 8 else fg
    if bg >= 0:
        poke(0xD021, _C64[bg] if bg < 8 else bg)


def start_color():
    pass


def has_colors():
    return True


def use_default_colors():
    pass


def curs_set(visibility):
    return 1


def noecho():
    pass


def echo():
    pass


def cbreak():
    pass


def nocbreak():
    pass


def beep():
    poke(0xD020, peek(0xD020) ^ 15)     # (a flash of the border: there is no bell)
    poke(0xD020, peek(0xD020) ^ 15)


flash = beep


class window:
    def __init__(self, nlines, ncols, begin_y, begin_x):
        self.h = nlines
        self.w = ncols
        self.y0 = begin_y
        self.x0 = begin_x
        self.cy = 0
        self.cx = 0
        self.attr = 0
        self.delay = True

    def _colour(self, attr):
        return _pairs[pair_number(attr)] | (attr & A_ATTRIBUTES)

    def _put(self, y, x, ch, attr):
        if 0 <= y < self.h and 0 <= x < self.w:
            offset = (self.y0 + y) * 80 + self.x0 + x
            poke(_SCREEN + offset, _code(ch))
            poke(_COLOUR + offset, self._colour(attr | self.attr))

    def addstr(self, y, x=None, s=None, attr=0):
        """addstr(y, x, s[, attr]) or addstr(s[, attr]) at the cursor."""
        if not isinstance(y, int):              # addstr(s[, attr])
            s, attr = y, (x if x is not None else 0)
            y, x = self.cy, self.cx
        for ch in str(s):
            if ch == '\n':
                y += 1
                x = 0
                continue
            self._put(y, x, ch, attr)
            x += 1
            if x >= self.w:
                x = 0
                y += 1
        self.cy = min(y, self.h - 1)
        self.cx = x

    def addch(self, y, x=None, ch=None, attr=0):
        """addch(y, x, ch[, attr]) or addch(ch[, attr]) at the cursor."""
        if ch is None:                          # addch(ch[, attr])
            ch, attr = y, (x if x is not None else 0)
            y, x = self.cy, self.cx
        if isinstance(ch, int):
            ch = chr(ch)
        self.addstr(y, x, ch[0], attr)

    def addnstr(self, y, x, s, n, attr=0):
        self.addstr(y, x, s[:n], attr)

    def move(self, y, x):
        self.cy = y
        self.cx = x

    def getyx(self):
        return self.cy, self.cx

    def getmaxyx(self):
        return self.h, self.w

    def getbegyx(self):
        return self.y0, self.x0

    def attron(self, attr):
        self.attr |= attr

    def attroff(self, attr):
        self.attr &= ~attr

    def attrset(self, attr):
        self.attr = attr

    def bkgd(self, ch, attr=0):
        self.erase()

    def erase(self):
        for y in range(self.h):
            self.addstr(y, 0, ' ' * self.w)
        self.move(0, 0)

    def clear(self):
        self.erase()

    def clrtoeol(self):
        self.addstr(self.cy, self.cx, ' ' * (self.w - self.cx))

    def clrtobot(self):
        y, x = self.cy, self.cx
        self.clrtoeol()
        for row in range(y + 1, self.h):
            self.addstr(row, 0, ' ' * self.w)
        self.move(y, x)

    def border(self, ls='|', rs='|', ts='-', bs='-', tl='+', tr='+', bl='+', br='+'):
        h, w = self.h, self.w
        self.addstr(0, 0, tl + ts * (w - 2) + tr)
        self.addstr(h - 1, 0, bl + bs * (w - 2))
        self._put(h - 1, w - 1, br, 0)
        for y in range(1, h - 1):
            self._put(y, 0, ls, 0)
            self._put(y, w - 1, rs, 0)

    def box(self, vertch='|', horch='-'):
        self.border(vertch, vertch, horch, horch)

    def hline(self, y, x, ch, n):
        self.addstr(y, x, ch * n)

    def vline(self, y, x, ch, n):
        for i in range(n):
            self._put(y + i, x, ch, 0)

    def inch(self, y, x):
        """The character code at y, x (the screen code)."""
        return peek(_SCREEN + (self.y0 + y) * 80 + self.x0 + x)

    def refresh(self):
        pass

    def noutrefresh(self):
        pass

    def keypad(self, flag):
        pass

    def nodelay(self, flag):
        """True: getch() does not wait (-1 if no key)."""
        self.delay = not flag

    def timeout(self, ms):
        self.delay = ms < 0

    def getch(self, y=None, x=None):
        """The next key: a character code, or KEY_UP and the like; -1 if nodelay and
        none is waiting."""
        while True:
            c = peek(0xD610)
            if c:
                poke(0xD610, 0)
                return _KEYS[c] if c in _KEYS else c
            if not self.delay:
                return -1

    def getkey(self, y=None, x=None):
        c = self.getch()
        if c == -1:
            raise error('no input')
        names = {KEY_UP: 'KEY_UP', KEY_DOWN: 'KEY_DOWN', KEY_LEFT: 'KEY_LEFT',
                 KEY_RIGHT: 'KEY_RIGHT', KEY_HOME: 'KEY_HOME',
                 KEY_BACKSPACE: 'KEY_BACKSPACE'}
        return names[c] if c in names else chr(c)

    def getstr(self, y=None, x=None, n=79):
        """A line typed on the screen (RETURN ends it)."""
        if y is not None:
            self.move(y, x)
        s = ''
        while True:
            c = self.getch()
            if c == 10:
                return s
            if c == KEY_BACKSPACE:
                if s:
                    s = s[:-1]
                    self.cx -= 1
                    self._put(self.cy, self.cx, ' ', 0)
            elif 32 <= c < 127 and len(s) < n:
                s += chr(c)
                self.addstr(chr(c))

    def subwin(self, nlines, ncols, begin_y, begin_x):
        return window(nlines, ncols, begin_y, begin_x)

    def derwin(self, nlines, ncols, begin_y, begin_x):
        """A window inside this one (begin_y, begin_x relative to it)."""
        return window(nlines, ncols, self.y0 + begin_y, self.x0 + begin_x)


def newwin(nlines, ncols, begin_y=0, begin_x=0):
    return window(nlines, ncols, begin_y, begin_x)


stdscr = None
_bg = None


def initscr():
    """The whole screen as a window (cleared)."""
    global stdscr, _bg
    if _bg is None:
        _bg = peek(0xD021)
    stdscr = window(LINES, COLS, 0, 0)
    stdscr.clear()
    return stdscr


def endwin():
    """Back to the interpreter's screen (cleared, its own background colour)."""
    global _bg
    if _bg is not None:
        poke(0xD021, _bg)
        _bg = None
    cls()


def wrapper(func):
    """Run func(stdscr) with the screen set up, and restore it afterwards (also when
    func raises)."""
    scr = initscr()
    try:
        return func(scr)
    finally:
        endwin()
