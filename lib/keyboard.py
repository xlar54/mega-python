# keyboard: reading keys without waiting for RETURN (for games and menus)
#
#   import keyboard
#   k = keyboard.getkey()            # '' if no key is waiting (never waits)
#   k = keyboard.waitkey()           # waits for a key
#   if k == keyboard.UP: ...         # the cursor keys, F-keys, RETURN, ... (see below)
#   keyboard.shift()                 # is a shift key held?
#
# Keys come from the MEGA65's typing queue ($D610): each press once, as an ASCII
# character (letters, digits, punctuation) or one of the names below.

QUEUE = 0xD610
MODIFIERS = 0xD611

UP = 'UP'
DOWN = 'DOWN'
LEFT = 'LEFT'
RIGHT = 'RIGHT'
HOME = 'HOME'
CLR = 'CLR'
DEL = 'DEL'
INST = 'INST'
RETURN = '\n'
ESC = 'ESC'
TAB = '\t'
F1, F3, F5, F7 = 'F1', 'F3', 'F5', 'F7'
F2, F4, F6, F8 = 'F2', 'F4', 'F6', 'F8'

_NAMES = {0x91: UP, 0x11: DOWN, 0x9D: LEFT, 0x1D: RIGHT, 0x13: HOME, 0x93: CLR,
          0x14: DEL, 0x94: INST, 0x0D: RETURN, 0x1B: ESC, 0x09: TAB, 0x03: 'STOP',
          0xF1: F1, 0xF3: F3, 0xF5: F5, 0xF7: F7, 0xF2: F2, 0xF4: F4, 0xF6: F6,
          0xF8: F8}


def getcode():
    """The next key's code (0 if none), without waiting."""
    c = peek(QUEUE)
    if c:
        poke(QUEUE, 0)                  # (writing takes it off the queue)
    return c


def getkey():
    """The next key as a string ('' if none), without waiting."""
    c = getcode()
    if not c:
        return ''
    if c in _NAMES:
        return _NAMES[c]
    if 32 <= c < 127:
        return chr(c)
    return '?'


def waitkey():
    """Wait for a key and return it."""
    k = getkey()
    while not k:
        k = getkey()
    return k


def flush():
    """Forget the keys pressed so far."""
    while peek(QUEUE):
        poke(QUEUE, 0)


def shift():
    return bool(peek(MODIFIERS) & 3)


def ctrl():
    return bool(peek(MODIFIERS) & 4)


def mega():
    """The MEGA key (the Commodore key)."""
    return bool(peek(MODIFIERS) & 8)


def alt():
    return bool(peek(MODIFIERS) & 16)
