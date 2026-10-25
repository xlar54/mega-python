# modtest: a module for tests/t_import.py (import modtest) - only for that test
NAME = 'modtest'
count = 0


def square(n):
    return n * n


def counter():
    global count
    count += 1
    return count


class Point:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def __repr__(self):
        return 'Point(%d, %d)' % (self.x, self.y)

    def moved(self, dx):
        return Point(self.x + dx, self.y)


def get_extra():
    return extra


print('modtest loaded', len(NAME), square(4))     # builtins work inside a module
