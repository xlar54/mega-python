# dicts and tuples
d = {"a": 1, "b": 2}
d["c"] = 3
d["a"] = 10
print(d, len(d), d["b"], "c" in d, "z" in d)
print(d.get("a"), d.get("zz"), d.get("zz", 0))
print(list(d.keys()), list(d.values()), list(d.items()))
for k in d:
    print(k, d[k])
for k, v in d.items():
    print(k, "=", v)
del d["b"]
print(d)
print(d.pop("c"), d.pop("nope", -1), d)
d.setdefault("x", 7)
d.setdefault("a", 99)
print(d)
d.update({"y": 8, "a": 1})
print(d)
e = dict(one=1, two=2)
print(e, dict([("p", 1), ("q", 2)]))
sq = {n: n * n for n in range(5)}
print(sq)
counts = {}
for ch in "mississippi":
    counts[ch] = counts.get(ch, 0) + 1
print(counts)
nested = {"list": [1, 2], "dict": {"k": (1, 2)}}
print(nested["dict"]["k"][1], nested)
keyed = {(1, 2): "tuple", 3: "int"}
print(keyed[(1, 2)], keyed[3])
print({} == {}, {"a": 1} == {"a": 1}, {"a": 1} == {"a": 2})
try:
    print(d["missing"])
except KeyError as err:
    print("KeyError", err)
t = (1, 2, 3)
print(t, t[0], t[-1], t[1:], len(t), (1,), (), t + (4,), t * 2)
a, b, c = t
print(a, b, c)
a, b = b, a
print(a, b)
x, y = "xy"
print(x, y)
(p, q) = [5, 6]
print(p, q)
for i, (m, n) in enumerate([(1, 2), (3, 4)]):
    print(i, m, n)
print(t.index(2), t.count(3), 2 in t, tuple([1, 2]), tuple("ab"))
print((1, 2) < (1, 3), (1, 2) == (1, 2), max((3, 1), (2, 9)))
d2 = {}
d2[1] = "one"
d2[True] = "true"
print(d2)
