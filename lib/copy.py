# copy: shallow and deep copies, as Python's copy module
#
# Lists, dicts and tuples are copied; numbers, strings, None and functions are
# shared (they cannot change). An object of a class is copied by its __copy__ or
# __deepcopy__ method; without one, copy() raises TypeError here (CPython can make an
# empty instance, which MEGA65 Python cannot).


class Error(Exception):
    pass


error = Error


def copy(x):
    """A shallow copy: a new container holding the same items."""
    if isinstance(x, list):
        return x[:]
    if isinstance(x, dict):
        return dict(x)
    if hasattr(x, '__copy__'):
        return x.__copy__()
    if isinstance(x, (int, float, str, bool, tuple, range)) or x is None or callable(x):
        return x
    raise TypeError('cannot copy this object (give its class a __copy__ method)')


def deepcopy(x, memo=None):
    """A deep copy: the containers inside are copied too (shared items stay shared)."""
    if memo is None:
        memo = {}
    key = id(x)
    if key in memo:
        return memo[key]
    if isinstance(x, list):
        y = []
        memo[key] = y
        for item in x:
            y.append(deepcopy(item, memo))
    elif isinstance(x, dict):
        y = {}
        memo[key] = y
        for k in x:
            y[deepcopy(k, memo)] = deepcopy(x[k], memo)
    elif isinstance(x, tuple):
        y = tuple([deepcopy(item, memo) for item in x])
        memo[key] = y
    elif hasattr(x, '__deepcopy__'):
        y = x.__deepcopy__(memo)
        memo[key] = y
    else:
        y = copy(x)
    return y
