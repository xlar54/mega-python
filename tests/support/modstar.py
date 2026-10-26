# modstar: a module for tests/t_import.py (from modstar import *) - only for that test
from modtest import *

__all__ = ['shown', '_kept', 'nine']
shown = square(3)                       # modtest's square, bound in this module
_kept = 'kept'
hidden = 'hidden'


def nine():
    return square(3)
