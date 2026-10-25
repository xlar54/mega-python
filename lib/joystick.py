# joystick: the two joystick ports (CIA 1)
#
#   import joystick
#   j = joystick.Joystick(2)         # port 2 (the usual one for games), or 1
#   if j.fire(): ...
#   dx, dy = j.direction()           # each -1, 0 or 1 (dy -1 = up)
#   j.up(), j.down(), j.left(), j.right()
#
# The lines read 0 when pressed: port 2 is $DC00, port 1 is $DC01, with bit 0 up,
# 1 down, 2 left, 3 right, 4 fire.

PORTS = {1: 0xDC01, 2: 0xDC00}


class Joystick:
    def __init__(self, port=2):
        if port not in PORTS:
            raise ValueError('joystick port must be 1 or 2')
        self.port = port
        self.address = PORTS[port]

    def read(self):
        """The pressed lines as bits: 1 up, 2 down, 4 left, 8 right, 16 fire."""
        if self.port == 2:
            poke(0xDC00, 255)           # (the keyboard's column lines all high)
        return ~peek(self.address) & 31

    def up(self):
        return bool(self.read() & 1)

    def down(self):
        return bool(self.read() & 2)

    def left(self):
        return bool(self.read() & 4)

    def right(self):
        return bool(self.read() & 8)

    def fire(self):
        return bool(self.read() & 16)

    def direction(self):
        """(dx, dy): -1, 0 or 1 each; up is dy = -1, as on the screen."""
        bits = self.read()
        dx = (1 if bits & 8 else 0) - (1 if bits & 4 else 0)
        dy = (1 if bits & 2 else 0) - (1 if bits & 1 else 0)
        return dx, dy

    def __repr__(self):
        return 'Joystick(%d)' % self.port
