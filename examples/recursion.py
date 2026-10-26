# recursion: functions that call themselves - factorial, memoised Fibonacci, the
# Towers of Hanoi, permutations (a recursive generator), the N queens puzzle
# (backtracking), a flood fill, nested lists and Ackermann's function


def factorial(n):
    return 1 if n <= 1 else n * factorial(n - 1)


print('factorials:', [factorial(n) for n in range(1, 13)])


def make_fib():
    memo = {0: 0, 1: 1}                 # a closure keeps the answers

    def fib(n):
        if n not in memo:
            memo[n] = fib(n - 1) + fib(n - 2)
        return memo[n]
    return fib


fib = make_fib()
print('fib(40) =', fib(40), '  first ten:', [fib(n) for n in range(10)])


def hanoi(n, src, dst, via, moves):
    if n:
        hanoi(n - 1, src, via, dst, moves)
        moves.append(src + dst)
        hanoi(n - 1, via, dst, src, moves)
    return moves


moves = hanoi(3, 'A', 'C', 'B', [])
print('hanoi, 3 discs:', len(moves), 'moves:', ' '.join(moves))
print('hanoi, 10 discs:', len(hanoi(10, 'A', 'C', 'B', [])), 'moves')


def permutations(items):
    if len(items) <= 1:
        yield items
        return
    for i in range(len(items)):
        for rest in permutations(items[:i] + items[i + 1:]):
            yield items[i] + rest


print('permutations of abc:', list(permutations('abc')))
print('of mega:', sum(1 for _ in permutations('mega')), 'of them')


def queens(n, placed=()):
    """Every way to put n queens on an n x n board, none attacking another."""
    row = len(placed)
    if row == n:
        yield placed
        return
    for col in range(n):
        if all(col != c and abs(col - c) != row - r for r, c in enumerate(placed)):
            yield from queens(n, placed + (col,))


print('6 queens:', sum(1 for _ in queens(6)), 'solutions')
first = next(queens(8))
print('the first of 8 queens:')
for col in first:
    print('   ' + ' '.join('Q' if c == col else '.' for c in range(8)))

picture = ['..........',
           '.###..###.',
           '.#.#..#.#.',
           '.###..###.',
           '..........',
           '.########.',
           '..........']
grid = [list(line) for line in picture]


def fill(r, c, old, new):
    if 0 <= r < len(grid) and 0 <= c < len(grid[0]) and grid[r][c] == old:
        grid[r][c] = new
        fill(r + 1, c, old, new)
        fill(r - 1, c, old, new)
        fill(r, c + 1, old, new)
        fill(r, c - 1, old, new)


fill(0, 0, '.', '~')
print('flood fill from the corner (the holes stay dry):')
for row in grid:
    print('   ' + ''.join(row))


def flatten(x):
    if isinstance(x, list):
        for item in x:
            yield from flatten(item)
    else:
        yield x


def depth(x):
    return 1 + max(map(depth, x), default=0) if isinstance(x, list) else 0


nested = [1, [2, [3, [4, [5]]], 6], [[7]]]
print('flatten', nested, '->', list(flatten(nested)), ' depth', depth(nested))


def ackermann(m, n):
    if m == 0:
        return n + 1
    if n == 0:
        return ackermann(m - 1, 1)
    return ackermann(m - 1, ackermann(m, n - 1))


print('ackermann(2, 3) =', ackermann(2, 3), '  ackermann(3, 3) =', ackermann(3, 3))


def forever(n):
    return forever(n + 1)


try:
    forever(0)
except RecursionError:
    print('and recursion without an end stops with RecursionError')
