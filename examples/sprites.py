# sprites: four balls bounce around the screen over the text, a multicolour ship flies
# across, and sprite collisions are counted (MEGA65 only: lib/sprite.py pokes the VIC)
import sprite
from sprite import Sprite

BALL = ['.......XXXXXX',
        '.....XXXXXXXXXX',
        '....XXXXXXXXXXXX',
        '...XXXXXXXXXXXXXX',
        '..XXXXXXXXXXXXXXXX',
        '..XXXXXXXXXXXXXXXX',
        '.XXXXXXXXXXXXXXXXXX',
        '.XXXXXXXXXXXXXXXXXX',
        '.XXXXXXXXXXXXXXXXXX',
        '.XXXXXXXXXXXXXXXXXX',
        '.XXXXXXXXXXXXXXXXXX',
        '..XXXXXXXXXXXXXXXX',
        '..XXXXXXXXXXXXXXXX',
        '...XXXXXXXXXXXXXX',
        '....XXXXXXXXXXXX',
        '.....XXXXXXXXXX',
        '.......XXXXXX']

SHIP = ['.....22.....',             # multicolour: 1, 2, 3 = three colours
        '....2222....',
        '....2332....',
        '...222222...',
        '..22222222..',
        '.1222222221.',
        '112222222211',
        '112211112211',
        '11.......11.',
        '1.........1.']

print('sprites: bouncing balls (about 8 seconds)')
for line in range(8):
    print('     the sprites move over the text: this is line', line + 1)

balls = []
moves = [(2, 1), (-1, 2), (1, -2), (-2, -1)]
colors = [2, 5, 7, 14]
for n in range(4):
    b = Sprite(n, BALL, colors[n])
    b.move(40 + n * 60, 30 + n * 30)
    b.dx, b.dy = moves[n]
    b.show()
    balls.append(b)

ship = Sprite(4)
ship.multicolor(True)
ship.shape(SHIP)
ship.color(12)
sprite.multicolors(1, 8)
ship.expand(True, True)
ship.move(-48, 160)
ship.show()

hits = 0
sprite.collisions()
for frame in range(400):
    for b in balls:
        x, y = b.x + b.dx, b.y + b.dy
        if x < 0 or x > 320 - 19:
            b.dx = -b.dx
        if y < 0 or y > 200 - 17:
            b.dy = -b.dy
        b.move(b.x + b.dx, b.y + b.dy)
    ship.move(ship.x + 1 if ship.x < 330 else -48, 160)
    touched, _ = sprite.collisions()
    if touched:
        hits += 1
    sprite.wait_frame()

sprite.hide_all()
print('frames with sprites touching:', hits > 0)
