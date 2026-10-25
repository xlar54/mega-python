# ASCII Mandelbrot in fixed-point integer arithmetic (no floats needed)
SCALE = 1 << 12
CHARS = " .:-=+*#%@"
W, H = 72, 22
for row in range(H):
    y0 = (row - H // 2) * SCALE * 5 // (H * 2)
    line = ""
    for col in range(W):
        x0 = (col - W * 2 // 3) * SCALE * 3 // W
        x = y = 0
        n = 0
        while n < 18:
            x2 = x * x // SCALE
            y2 = y * y // SCALE
            if x2 + y2 > 4 * SCALE:
                break
            y = 2 * x * y // SCALE + y0
            x = x2 - y2 + x0
            n += 1
        line += CHARS[n % len(CHARS)] if n < 18 else " "
    print(line)
