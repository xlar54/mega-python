# leaving blocks early: finally runs on break / continue / return, with blocks get the
# exception (and may swallow it), several managers in one with


log = []
for i in range(3):
    try:
        if i == 1:
            continue
        if i == 2:
            break
        log.append('body %d' % i)
    finally:
        log.append('finally %d' % i)
print(log)


def ret():
    try:
        return 'from try'
    finally:
        print('finally on return')


print(ret())


def nested():
    out = []
    for i in range(2):
        try:
            try:
                if i == 1:
                    break
                out.append(i)
            finally:
                out.append('inner')
        finally:
            out.append('outer')
    return out


print(nested())


def ret_in_loop():
    for i in range(3):
        try:
            if i == 1:
                return i
        finally:
            print('finally', i)


print(ret_in_loop())


class CM:
    def __init__(self, name, swallow=False):
        self.name = name
        self.swallow = swallow

    def __enter__(self):
        print('enter', self.name)
        return self.name

    def __exit__(self, typ, val, tb):
        print('exit', self.name, typ.__name__ if typ else None, val)
        return self.swallow


for i in range(2):
    with CM(i):
        try:
            if i == 0:
                continue
        finally:
            print('fin', i)
while True:
    try:
        break
    finally:
        print('while finally')


def stale():                            # the finally's handler is gone after the break
    for i in range(2):
        try:
            break
        finally:
            pass
    try:
        raise ValueError('later')
    except ValueError as e:
        return 'caught ' + str(e)


print(stale())


def order():
    out = []
    for i in range(1):
        try:
            with CM('w'):
                try:
                    break
                finally:
                    out.append('inner finally')
        finally:
            out.append('outer finally')
    return out


print(order())


def from_except():
    try:
        try:
            raise KeyError('k')
        except KeyError:
            return 'from except'
        finally:
            print('finally after except')
    finally:
        print('outer too')


print(from_except())


def break_in_finally():
    for i in range(3):
        try:
            pass
        finally:
            if i == 1:
                break
    return i


print(break_in_finally())


def override():
    try:
        return 1
    finally:
        return 2


print(override())


def raise_in_finally():
    for i in range(2):
        try:
            try:
                break
            finally:
                raise ValueError('from finally')
        except ValueError as e:
            print('caught', e)
    return 'done'


print(raise_in_finally())

with CM('a') as x, CM('b') as y:
    print('body', x, y)

with CM('quiet', True):
    raise ValueError('swallowed')
print('after quiet')

try:
    with CM('loud'):
        raise KeyError('k')
except KeyError as e:
    print('KeyError got out', e)


def f():
    with CM('f1') as p, CM('f2', True) as q, CM('f3') as r:
        print('in f', p, q, r)
        raise IndexError('i')
    return 'f returned'


print(f())


def g():
    for i in range(2):
        with CM('g%d' % i), CM('h%d' % i):
            if i == 0:
                continue
            return 'from g'


print(g())
