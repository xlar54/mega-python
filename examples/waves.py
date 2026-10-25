# waves: the math module - a table of sines and cosines, then a sine wave in text
import math

print('angle   radians      sin      cos')
for deg in range(0, 361, 45):
    rad = math.radians(deg)
    print(f'{deg:5}  {rad:8.4f} {math.sin(rad):8.4f} {math.cos(rad):8.4f}')

print()
print('square roots:', [round(math.sqrt(n), 3) for n in range(1, 8)])
print('a 3-4-5 triangle: hypotenuse', math.hypot(3, 4),
      'angle', round(math.degrees(math.atan2(4, 3)), 2), 'degrees')
r = 2.5
print(f'a circle of radius {r}: area {math.pi * r ** 2:.3f}, circumference {2 * math.pi * r:.3f}')
print()

# one period of sin(x) * e^(-x/8) in 21 rows (it fits on the screen), around a centre column
width = 30
for i in range(21):
    x = i * math.tau / 20
    y = math.sin(x) * math.exp(-x / 8)
    col = int(round(y * width))
    if col < 0:
        line = ' ' * (width + col) + '*' + '-' * (-col - 1) + '|'
    elif col > 0:
        line = ' ' * width + '|' + '-' * (col - 1) + '*'
    else:
        line = ' ' * width + '*'
    print(f'{y:6.3f} {line}')
