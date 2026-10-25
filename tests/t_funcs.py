# functions
def add(a, b):
    return a + b


def greet(name, greeting="Hello", punct="!"):
    return greeting + ", " + name + punct


def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)


def fact(n):
    return 1 if n <= 1 else n * fact(n - 1)


def divmod2(a, b):
    return a // b, a % b


def no_return():
    x = 1


print(add(2, 3), add("a", "b"), add([1], [2]))
print(greet("Bob"), greet("Ann", "Hi"), greet("Cy", punct="?"), greet(punct=".", name="Di"))
print(fib(15), fact(10), divmod2(17, 5), no_return())
q, r = divmod2(20, 6)
print(q, r)

counter = 0


def bump():
    global counter
    counter += 1
    return counter


bump()
bump()
print(counter)


def apply(f, x):
    return f(x)


square = lambda x: x * x
print(apply(square, 7), apply(lambda s: s.upper(), "up"), (lambda: 42)())
print(list(map(square, [1, 2, 3])), list(filter(lambda v: v % 2, range(8))))
print(list(map(str, [1, 2])), list(filter(None, [0, 1, "", "a"])))


def local_scope():
    total = 0
    for i in range(5):
        total += i
    items = [total]
    return items


print(local_scope())


def defaults_list(x, acc=None):
    if acc is None:
        acc = []
    acc.append(x)
    return acc


print(defaults_list(1), defaults_list(2))


def outer():
    def inner(v):
        return v * 10
    return inner(4)


print(outer())


def many(a, b, c=3, d=4):
    return [a, b, c, d]


print(many(1, 2), many(1, 2, 5), many(1, 2, d=9), many(b=8, a=7))


def rec_sum(lst):
    if not lst:
        return 0
    return lst[0] + rec_sum(lst[1:])


print(rec_sum(list(range(20))))
print(add.__name__, callable(add), callable(5))


def ackermann(m, n):
    if m == 0:
        return n + 1
    if n == 0:
        return ackermann(m - 1, 1)
    return ackermann(m - 1, ackermann(m, n - 1))


print(ackermann(2, 3))
try:
    add(1)
except TypeError:
    print("TypeError for a missing argument")
