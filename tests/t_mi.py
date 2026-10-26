# multiple inheritance: the C3 MRO, super() along it, __mro__ / __bases__, isinstance,
# exception classes with a mixin, an inconsistent MRO, super().__init__() reaching object
class A:
    def who(self):
        return 'A'

    def hello(self):
        return 'A.hello'


class B(A):
    def who(self):
        return 'B>' + super().who()


class C(A):
    def who(self):
        return 'C>' + super().who()

    def only_c(self):
        return 'only C'


class D(B, C):
    def who(self):
        return 'D>' + super().who()


d = D()
print(d.who(), d.hello(), d.only_c())
print([k.__name__ for k in D.__mro__])
print([k.__name__ for k in D.__bases__], [k.__name__ for k in B.__bases__], A.__bases__)
print(isinstance(d, C), isinstance(d, B), issubclass(D, C), issubclass(C, D), isinstance(d, A))


class Mixin:
    tag = 'mixed'

    def describe(self):
        return self.name() + ' ' + self.tag


class Base:
    def __init__(self, n):
        self.n = n

    def name(self):
        return 'base%d' % self.n


class Thing(Base, Mixin):
    pass


t = Thing(3)
print(t.describe(), Thing.tag, [k.__name__ for k in Thing.__mro__])


class E(D):
    pass


print(E().who(), [k.__name__ for k in E.__mro__])


class LoudError(ValueError, Mixin):
    def name(self):
        return 'loud'


try:
    raise LoudError('x')
except ValueError as e:
    print('caught', type(e).__name__, e.describe(), isinstance(e, Mixin))


class X:
    pass


class Y(X):
    pass


try:
    class Z(X, Y):
        pass
except TypeError as e:
    print('TypeError')


class P1:
    def __init__(self):
        print('P1 init')
        super().__init__()


class P2:
    def __init__(self):
        print('P2 init')
        super().__init__()


class Q(P1, P2):
    def __init__(self):
        print('Q init')
        super().__init__()


Q()
print(len(Q.__mro__), Q.__mro__[-1] is object)
print([n for n in dir(D) if not n.startswith('__')], [n for n in dir(t) if not n.startswith('__')])
