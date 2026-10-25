# cursdemo: the curses library - windows, borders, colours, attributes and a menu
# chosen with the cursor keys (RETURN picks, Q quits)
import curses

ITEMS = ['Load a game', 'Save the game', 'Options', 'High scores', 'Quit']


def menu(win, choice):
    for i in range(len(ITEMS)):
        attr = curses.A_REVERSE if i == choice else curses.color_pair(2)
        win.addstr(2 + i, 3, ' %-16s ' % ITEMS[i], attr)


def main(stdscr):
    curses.start_color()
    curses.init_pair(1, curses.COLOR_YELLOW, curses.COLOR_BLUE)
    curses.init_pair(2, curses.COLOR_WHITE, curses.COLOR_BLUE)
    curses.init_pair(3, curses.COLOR_GREEN, curses.COLOR_BLUE)
    curses.init_pair(4, curses.COLOR_RED, curses.COLOR_BLUE)
    stdscr.addstr(0, 0, ' MEGA65 Python curses demo '.center(80), curses.A_REVERSE)
    stdscr.addstr(2, 4, 'normal  ')
    stdscr.addstr('bold  ', curses.A_BOLD)
    stdscr.addstr('reverse', curses.A_REVERSE)
    stdscr.addstr('  underline', curses.A_UNDERLINE)
    stdscr.addstr('  blink', curses.A_BLINK | curses.color_pair(4))
    for c in range(8):
        curses.init_pair(10 + c, c, curses.COLOR_BLUE)
        stdscr.addstr(4, 4 + c * 9, 'colour %d' % c, curses.color_pair(10 + c))
    win = curses.newwin(9, 24, 7, 4)
    win.box()
    win.addstr(0, 2, ' Menu ', curses.color_pair(1))
    info = curses.newwin(9, 40, 7, 34)
    info.border()
    info.addstr(1, 2, 'cursor keys: choose', curses.color_pair(3))
    info.addstr(2, 2, 'RETURN: pick, Q: quit', curses.color_pair(3))
    h, w = stdscr.getmaxyx()
    stdscr.addstr(h - 1, 0, 'screen %d x %d' % (w, h))
    choice = 0
    while True:
        menu(win, choice)
        k = stdscr.getch()
        if k == curses.KEY_UP:
            choice = (choice - 1) % len(ITEMS)
        elif k == curses.KEY_DOWN:
            choice = (choice + 1) % len(ITEMS)
        elif k in (ord('q'), ord('Q')):
            return None
        elif k == 10:
            if ITEMS[choice] == 'Quit':
                return None
            info.addstr(5, 2, ' ' * 36)
            info.addstr(5, 2, 'You picked: ' + ITEMS[choice], curses.color_pair(1))
            curses.beep()


curses.wrapper(main)
print('cursdemo: done')
