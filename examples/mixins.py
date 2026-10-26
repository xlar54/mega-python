# mixins: multiple inheritance - animals built from ability mixins, a diamond whose
# methods all run once through super() (the method resolution order), and an
# exception class with a mixin


class Animal:
    def __init__(self, name, **kw):
        self.name = name
        super().__init__(**kw)

    def abilities(self):
        return []

    def describe(self):
        kind = type(self).__name__
        return '%s the %s can %s' % (self.name, kind.lower(), ', '.join(self.abilities()))


class Walker:
    def __init__(self, legs=4, **kw):
        self.legs = legs
        super().__init__(**kw)

    def abilities(self):
        return ['walk on %d legs' % self.legs] + super().abilities()


class Swimmer:
    def abilities(self):
        return ['swim'] + super().abilities()


class Flyer:
    def __init__(self, wingspan=0, **kw):
        self.wingspan = wingspan
        super().__init__(**kw)

    def abilities(self):
        return ['fly (%d cm wings)' % self.wingspan] + super().abilities()


class Duck(Walker, Swimmer, Flyer, Animal):
    pass


class Dog(Walker, Swimmer, Animal):
    pass


class Bat(Flyer, Animal):
    pass


print('Animals made from mixins:')
zoo = [Duck(name='Donald', legs=2, wingspan=90), Dog(name='Rex'),
       Bat(name='Vlad', wingspan=30)]
for a in zoo:
    print(' ', a.describe())
print('  fliers:', [a.name for a in zoo if isinstance(a, Flyer)])
print('  Duck looks things up in:', ' > '.join(c.__name__ for c in Duck.__mro__))
print()


# a diamond: Base is reached through both Left and Right, but runs once
class Base:
    def steps(self, log):
        log.append('Base')
        return log


class Left(Base):
    def steps(self, log):
        log.append('Left')
        return super().steps(log)


class Right(Base):
    def steps(self, log):
        log.append('Right')
        return super().steps(log)


class Bottom(Left, Right):
    def steps(self, log):
        log.append('Bottom')
        return super().steps(log)


print('The diamond, each class once:', ' -> '.join(Bottom().steps([])))
print('Its bases:', [c.__name__ for c in Bottom.__bases__])
print()


# a mixin on an exception class: except ValueError still catches it
class Coded:
    code = 0

    def report(self):
        return 'error %d: %s' % (self.code, self.args[0])


class BadInput(ValueError, Coded):
    code = 42


for text in ['12', 'twelve']:
    try:
        if not text.isdigit():
            raise BadInput('not a number: ' + text)
        print('read', int(text))
    except ValueError as e:
        print(e.report() if isinstance(e, Coded) else e)
print()


# an order that cannot be made consistent is refused
class X:
    pass


class Y(X):
    pass


try:
    class Z(X, Y):
        pass
except TypeError:
    print('class Z(X, Y) is refused: X would have to come both before and after Y')
