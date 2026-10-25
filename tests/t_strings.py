# strings
s = "Hello"
t = 'World'
print(s + ", " + t + "!")
print(s * 3, len(s), s[0], s[-1], s[1:3], s[:2], s[2:], s[::-1], s[::2])
print("ell" in s, "xyz" in s, "lo" not in s)
print(s.upper(), s.lower(), "  pad  ".strip() + "|", "xxhixx".strip("x"))
print("  left".lstrip(), "right  ".rstrip() + "|")
print("a,b,,c".split(","), "one two  three".split(), "a b c".split(" ", 1))
print("-".join(["x", "y", "z"]), "".join(["a", "b"]))
print("banana".find("an"), "banana".find("x"), "banana".count("a"), "banana".index("n"))
print("banana".replace("a", "o"), "banana".replace("a", "", 2))
print("hello".startswith("he"), "hello".endswith("lo"), "hello".startswith(("x", "h")))
print("123".isdigit(), "12a".isdigit(), "abc".isalpha(), "   ".isspace())
print("ABC".isupper(), "abc".islower(), "Ab".isupper())
print("hello world".title(), "hello world".capitalize())
print("ab".center(6, "*"), "ab".ljust(4) + "|", "ab".rjust(4), "42".zfill(5), "-42".zfill(5))
print("line1\nline2\nline3".splitlines())
print("tab\there", "quote\"s", 'single\'s', "back\\slash")
print(repr("it's"), repr('say "hi"'), repr("a\nb"), repr("plain"))
print(str(42), str(-7), str(True), str(None), str([1, "a"]))
print(ord("A"), chr(97), chr(65) + chr(66))
name = "MEGA65"
n = 3
print(f"{name} has {n} sids, {n * 2} total")
print(f"{n:5}|{n:<5}|{n:^5}|{n:05}|{name:>8}|{name:.3}")
print(f"{255:x} {255:X} {255:b} {255:o} {1234567:,}")
print(f"{{braces}} {name!r} {'nested'}")
print("{} and {}".format("a", "b"), "{1}{0}".format("x", "y"), "{k}".format(k=5))
print("%d items, %s, %5d|%-5d|%05d, %x" % (3, "ok", 42, 42, 42, 255))
print("%r %%" % ("q",))
words = "the quick brown fox".split()
print(sorted(words), sorted(words, key=len), max(words, key=len) if False else max(words))
acc = ""
for ch in "abc":
    acc = ch + acc
print(acc)
print("a" < "b", "abc" < "abd", "Z" < "a", "abc" == "abc", "a" * 0 == "")
