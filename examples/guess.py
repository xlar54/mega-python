# Guess the number (uses input(); the random numbers come from a tiny LCG)
seed = peek(0xD7FA)                     # the VIC frame counter


def rand(n):
    global seed
    seed = (seed * 1103 + 12345) % 32768
    return seed % n


secret = rand(100) + 1
tries = 0
print("I'm thinking of a number from 1 to 100.")
while True:
    text = input("Your guess? ")
    if not text.isdigit():
        print("Please type a number.")
        continue
    guess = int(text)
    tries += 1
    if guess < secret:
        print("Higher!")
    elif guess > secret:
        print("Lower!")
    else:
        print(f"Yes! {secret} in {tries} tries.")
        break
