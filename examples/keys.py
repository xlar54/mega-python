# keys: the keyboard and joystick libraries. Move the * with the cursor keys or a
# joystick in port 2; fire or SPACE drops a mark, Q quits.
import curses
import keyboard
import joystick

scr = curses.initscr()
curses.init_pair(1, curses.COLOR_YELLOW, curses.COLOR_BLACK)
curses.init_pair(2, curses.COLOR_CYAN, curses.COLOR_BLACK)
scr.border()
scr.addstr(0, 3, ' keys.py ', curses.A_REVERSE)
scr.addstr(23, 3, 'cursor keys / joystick 2: move   SPACE / fire: mark   Q: quit',
           curses.color_pair(2))
stick = joystick.Joystick(2)
x, y = 40, 12
marks = 0
keyboard.flush()
while True:
    scr.addch(y, x, '*', curses.color_pair(1))
    k = keyboard.getkey()
    dx, dy = stick.direction()
    if k == keyboard.UP:
        dy = -1
    elif k == keyboard.DOWN:
        dy = 1
    elif k == keyboard.LEFT:
        dx = -1
    elif k == keyboard.RIGHT:
        dx = 1
    elif k in ('q', 'Q'):
        break
    mark = k == ' ' or stick.fire()
    if k or dx or dy or mark:
        scr.addstr(1, 2, 'key: %-6s stick: %2d %2d  shift: %-5s  marks: %d   ' %
                   (repr(k), dx, dy, keyboard.shift(), marks))
    if dx or dy or mark:
        scr.addch(y, x, '.' if mark else ' ')
        marks += 1 if mark else 0
        x = min(max(x + dx, 1), 78)
        y = min(max(y + dy, 2), 22)
        if not k:                        # (a joystick: slow it down a little)
            for i in range(150):
                pass
curses.endwin()
print('keys: %d marks' % marks)
