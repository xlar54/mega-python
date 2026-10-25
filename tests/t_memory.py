# allocation-heavy code: forces many garbage collections
a = []
for i in range(1000):
    a.append(str(i) * 3)
print(len(a), a[-1], a[123])
total = 0
for j in range(30):
    t = [str(i) + "x" for i in range(400)]
    total += len(t)
print(total)
d = {}
for i in range(500):
    d["k" + str(i)] = [i, i * i]
print(len(d), d["k499"], d["k7"])
for i in range(0, 500, 2):
    del d["k" + str(i)]
print(len(d), sorted(d)[:3])
s = ""
for i in range(200):
    s = s + str(i % 10)
print(len(s), s[-10:])


class Node:
    def __init__(self, v, nxt):
        self.v = v
        self.nxt = nxt


a = None
head = None
for i in range(500):
    head = Node(i, head)
n = 0
c = head
while c:
    n += c.v
    c = c.nxt
print(n)
a = None
t = None
d = None
big = [[i, str(i)] for i in range(600)]
print(len(big), big[-1])
