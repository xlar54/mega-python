# closures: nested functions that use the variables of the functions around them
def make_counter(start=0):
    count = start

    def inc(step=1):
        nonlocal count
        count += step
        return count
    return inc


c = make_counter()
d = make_counter(10)
print(c(), c(), c(5), d(), c())


def adder(n):                           # a captured parameter
    return lambda x: x + n


add3, add10 = adder(3), adder(10)
print(add3(1), add10(1), list(map(adder(100), [1, 2])))

curry = lambda a: lambda b: lambda c: a * 100 + b * 10 + c
print(curry(1)(2)(3))


def outer():                            # three levels; the middle one passes it on
    x = 'outer'

    def middle():
        def inner():
            return x + '!'
        return inner()
    r1 = middle()
    x = 'changed'
    return r1, middle()


print(outer())


def late():                             # closures see the variable, not a copy
    fs = []
    for i in range(3):
        fs.append(lambda: i)
    early = [lambda i=i: i for i in range(3)]
    return [f() for f in fs], [f() for f in early]


print(late())


def fib_memo():
    memo = {}

    def fib(n):                         # recursion through the closure
        if n < 2:
            return n
        if n not in memo:
            memo[n] = fib(n - 1) + fib(n - 2)
        return memo[n]
    return fib


print(fib_memo()(30))


def sort_by(field):
    return sorted([{'a': 2, 'b': 'y'}, {'a': 1, 'b': 'z'}], key=lambda r: r[field])


print(sort_by('a'), sort_by('b'))


def make_class(greeting):
    class Greeter:
        def __init__(self, name):
            self.name = name

        def hello(self):
            return greeting + ', ' + self.name
    return Greeter


print(make_class('Hi')('Ada').hello(), make_class('Hello')('Bob').hello())


def accumulate():
    total = 0
    items = []

    def add(v):
        nonlocal total
        total += v
        items.append(v)
        return total, len(items)
    return add


acc = accumulate()
acc(5)
print(acc(7), acc.__name__)


def swap_pair():
    a, b = 1, 2

    def swap():
        nonlocal a, b
        a, b = b, a
    swap()
    return a, b


print(swap_pair())


def unbound():
    def get():
        return value
    try:
        get()
    except NameError:
        print('NameError')
    value = 42
    return get()


print(unbound())
x = 'global x'


def uses_global():
    def f():
        return x                        # no enclosing x: the global
    return f()


print(uses_global())
