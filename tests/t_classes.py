# classes
class Point:
    count = 0

    def __init__(self, x, y):
        self.x = x
        self.y = y
        Point.count += 1

    def __repr__(self):
        return "Point(" + str(self.x) + ", " + str(self.y) + ")"

    def __add__(self, other):
        return Point(self.x + other.x, self.y + other.y)

    def __eq__(self, other):
        return self.x == other.x and self.y == other.y

    def dist2(self):
        return self.x * self.x + self.y * self.y


p = Point(1, 2)
q = Point(3, 4)
print(p, q, p + q, p == Point(1, 2), p == q)
print(p.dist2(), Point.count, p.x, getattr(q, "y"))
p.x = 10
print(p, hasattr(p, "x"), hasattr(p, "z"))
setattr(p, "z", 5)
print(p.z)


class Animal:
    def __init__(self, name):
        self.name = name

    def speak(self):
        return self.name + " makes a sound"

    def __str__(self):
        return "Animal " + self.name


class Dog(Animal):
    def __init__(self, name, breed):
        super().__init__(name)
        self.breed = breed

    def speak(self):
        return self.name + " barks"


class Puppy(Dog):
    def speak(self):
        return super().speak() + " softly"


a = Animal("Generic")
d = Dog("Rex", "lab")
pup = Puppy("Bit", "pug")
print(a.speak(), d.speak(), pup.speak(), d.breed)
print(str(d), isinstance(d, Animal), isinstance(a, Dog), isinstance(pup, Dog))
print(type(d) == Dog, type(5) == int, type("s") == str, type([]) == list)


class Stack:
    def __init__(self):
        self.items = []

    def push(self, v):
        self.items.append(v)

    def pop(self):
        return self.items.pop()

    def __len__(self):
        return len(self.items)

    def __bool__(self):
        return len(self.items) > 0


s = Stack()
print(bool(s), len(s))
s.push(1)
s.push(2)
print(bool(s), len(s), s.pop(), len(s))


class Version:
    def __init__(self, major, minor):
        self.major = major
        self.minor = minor

    def __lt__(self, other):
        return (self.major, self.minor) < (other.major, other.minor)

    def __repr__(self):
        return "v" + str(self.major) + "." + str(self.minor)


vs = [Version(1, 2), Version(0, 9), Version(1, 0)]
print(sorted(vs), min(vs), max(vs))


class Counter:
    def __init__(self):
        self.n = 0

    def inc(self, by=1):
        self.n += by
        return self


c = Counter()
c.inc().inc(5).inc()
print(c.n)
m = c.inc
m()
print(c.n)


class Empty:
    pass


e = Empty()
e.anything = [1, 2]
print(e.anything)
try:
    print(e.missing)
except AttributeError:
    print("AttributeError")
