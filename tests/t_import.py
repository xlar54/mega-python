# import of a module from the disk (tests/support/modtest.py)
import modtest
print(modtest.NAME, modtest.square(7), modtest.counter(), modtest.counter())
print(modtest.count)
import modtest as m2
print(m2 is modtest, m2.count)          # imported once: the same module
from modtest import square, Point
print(square(3), Point(1, 2), Point(1, 2).moved(5), repr(modtest)[:16])
modtest.extra = 5
print(modtest.get_extra())
NAME = 'main'
print(NAME, modtest.NAME)               # the module's names are its own
modtest.count = 100
print(modtest.counter())
try:
    modtest.missing
except AttributeError:
    print('AttributeError')
try:
    import nosuchmod
except ImportError as e:
    print('ImportError', e)


def f():
    import modtest as m
    return m.square(5)


print(f())

from modtest import (counter,
                     NAME as N2,)
print(counter(), N2)
from modstar import *                   # its __all__: '_' names too, not the others
print(shown, _kept, nine())
try:
    hidden
except NameError:
    print('NameError')
from math import *
print(floor(2.5), sqrt(16), pi > 3)
