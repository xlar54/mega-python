# control flow
for n in range(1, 16):
    if n % 15 == 0:
        print("FizzBuzz")
    elif n % 3 == 0:
        print("Fizz")
    elif n % 5 == 0:
        print("Buzz")
    else:
        print(n)
i = 0
while True:
    i += 1
    if i == 3:
        continue
    if i > 6:
        break
    print("i", i)
for x in range(3):
    pass
else:
    print("for-else ran", x)
for x in range(3):
    if x == 1:
        break
else:
    print("not printed")
k = 0
while k < 3:
    k += 1
else:
    print("while-else", k)
found = None
for row in range(5):
    for col in range(5):
        if row * col == 6:
            found = (row, col)
            break
    if found:
        break
print("found", found)
print("yes" if 3 > 2 else "no", "yes" if 3 < 2 else "no")
v = 7
r = "small" if v < 5 else "medium" if v < 10 else "large"
print(r)
total = 0
for a in range(10):
    if a % 2:
        continue
    total += a
print(total)
if not []:
    print("empty is false")
if [0]:
    print("non-empty is true")
if "":
    print("no")
elif 0:
    print("no")
else:
    print("else branch")
count = 0
for _ in "abc":
    for _ in range(4):
        count += 1
print(count)
x = 10
while x:
    x -= 3
    if x < 0:
        break
print(x)
if (n := 5) > 3:
    print("walrus", n)
