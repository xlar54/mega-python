MEGA65 Python
=============

Version 0.8.0 (the `VERSION` file: the build puts it in the boot banner and in `sys`).

A Python 3 interpreter for the MEGA65, written entirely in 45GS02 assembly (64tass). It
boots to a `>>>` prompt, has a full-screen program editor, and loads and saves `.py`
files on the disk. Like CPython, it compiles each piece of source to bytecode in memory
and runs that on a bytecode VM.

It implements a large subset of Python 3 (see "Python support" below). The test
programs in `tests/` print exactly what CPython prints for them.

Python support
--------------

What works (each item as in CPython, apart from the notes in "Differences from
CPython" below):

* **Types**: `int` (any size up to about 500 digits), `float` (IEEE double), `bool`, `None`, `str`, `list`,
  `tuple`, `dict`, `set`, `frozenset`, `range`, slices, files, generators.
* **Statements**: `if`/`elif`/`else`, `while` and `for` (with `else`), `break`,
  `continue`, `pass`, `def`, `class`, `return`, `del`, `global`, `nonlocal`, `assert`,
  `import`, `from ... import` (also `*` and names in parentheses), `try`/`except`/`else`/`finally`, `raise` (also `raise
  ... from`), `with` (several managers), `yield`, `yield from`, annotated assignments
  (`x: int = 5`).
* **Expressions**: arithmetic, bitwise and comparison operators (chained: `a < b < c`),
  `and`/`or`/`not`, `in`, `is`, conditional expressions, `lambda`, `:=`, list / dict /
  set comprehensions, generator expressions (lazy), f-strings (format specs, `!r`, `!s`),
  `%` formatting, `str.format`, slicing with steps, assigning to and deleting slices of
  lists (`a[1:3] = x`, `del a[::2]`), unpacking with `*` and `**` in calls
  and displays (`[*a, *b]`, `{**d, 'k': 1}`) and starred targets (`first, *rest = x`).
* **Functions**: defaults, keyword arguments, `*args`, `**kwargs`, keyword-only
  parameters, closures and `nonlocal`, decorators, generators (`send`, `throw`, `close`).
* **Classes**: single and multiple inheritance (CPython's C3 method resolution order,
  `__mro__`, `__bases__`), `super()` (along the MRO), `staticmethod`, `classmethod`, `property`
  (with setters), the operator dunders (`__add__` ... `__radd__`, comparisons,
  `__eq__`/`__hash__`, also against other types), `__str__`/`__repr__`, `__len__`,
  `__bool__`, `__getitem__`/`__setitem__`/`__delitem__`, `__contains__`, `__iter__`/`__next__`, `__call__`,
  `__enter__`/`__exit__`, class attributes, `__class__`, `__name__`.
* **Exceptions**: the builtin hierarchy (`BaseException`, `Exception`, `ValueError`,
  `KeyError`, `StopIteration`, `GeneratorExit`, ...), your own exception classes,
  tracebacks with the chain of calls.
* **Builtins**: `abs all any ascii bin bool callable chr classmethod delattr dict dir
  divmod enumerate exit filter float format frozenset getattr globals hasattr hash hex id
  input int isinstance issubclass iter len list map max min next object oct open ord pow
  print property quit range repr reversed round set setattr slice sorted staticmethod str
  sum super tuple type vars zip` (`isinstance`/`issubclass` know `object` and that `bool`
  is an `int`), and for the MEGA65 `run edit new load save files cls peek poke mem help gc`.
* **Methods**: `str` (`upper lower split join strip lstrip rstrip find replace
  startswith endswith isdigit isalpha isalnum isspace isupper islower isascii isdecimal
  isnumeric count index rfind rindex format center ljust rjust zfill title capitalize
  swapcase casefold splitlines partition rpartition rsplit removeprefix removesuffix
  expandtabs`), `list` (`append pop insert
  remove index count extend reverse sort copy clear`), `dict` (`keys values items get
  pop setdefault update clear copy`), `set`/`frozenset` (all of them), files (`read
  readline readlines write close`). Methods also work taken from the type, as values:
  `str.upper`, `list.append`, `dict.get`.
* **Modules**: `math`, `os`, `sys`, `time`, `random`, `json`, `string`, `bisect`, `heapq`,
  `functools`, `copy`, `textwrap`, `statistics`, `itertools`, `collections` (`deque`,
  `Counter`, `defaultdict`, `namedtuple`, `OrderedDict`), your own modules from the disk, and the MEGA65 ones (see "Modules").

Not supported yet:

* `complex`, `bytes`/`bytearray` (`b'...'` is a `str`),
  `decimal`, `fractions`.
* Subclassing builtin types (`class D(dict)`), metaclasses, `cls.mro()`,
  `__slots__`, `__getattr__`/`__setattr__` hooks, `property` deleters.
* `match`, `async`/`await`, positional-only parameters (`/`), `yield` in a lambda,
  `del` of a variable a nested function uses.
* `eval`, `exec`, `locals`, `compile`.
* Attributes on functions (`f.cache = {}`), live `dict` views (`keys()` and friends
  return lists).
* `str.encode`, `str.translate`, `str.format_map`; `float` methods.
* Packages (`import a.b`), relative imports.
* The modules `re`, `datetime`, and most of the standard library. A `namedtuple` is a
  class of its own, not a `tuple` subclass (`isinstance(p, tuple)` is `False`).
* Traceback objects (`with`'s `__exit__` gets `None`), file names and source lines in
  tracebacks, `StopIteration(v).value` for one raised by your own code.

Build
-----

Run `build.bat`. It:

1. generates `src/gen/tables.asm` and `symnames.asm` (`tools/gen_tables.py`: symbols,
   builtin tables, the version) and `src/gen/fconst.asm` (`tools/gen_fconst.py`: float
   constants),
2. copies `examples/*.py` and `tests/*.py` to `target/py/` as disk files (`tools/mkpy.py`),
3. assembles `src/main.asm` with the bundled 64tass into `target/image.bin`,
4. splits the images into the program `target/mega-python.prg` and the file `mpy-ovl`
   (`tools/split.py`), writes the boot program `autoboot.c65` (`tools/mkboot.py`), and
5. writes `target/mega-python.d81` with c1541: `autoboot.c65` first, then the
   interpreter `mega-python`, `mpy-ovl` and every `.py` file.

Run
---

`run.bat` builds and starts Xemu with the disk. On a real MEGA65, mount the D81 and
reset: `AUTOBOOT.C65` is a one-line BASIC program, `10 RUN "MEGA-PYTHON"`, so the
interpreter starts by itself (or type `RUN "MEGA-PYTHON"`). It then loads `mpy-ovl` from
the same disk.

```
>>> 6 * 7
42
>>> load('mandel')
616 bytes loaded
>>> run()
```

Commands at the prompt (they are Python functions):

| Command | What it does |
|---|---|
| `edit()` | full-screen editor for the program |
| `run()` | run the program (with a fresh interpreter; its globals stay for inspection) |
| `new()` | clear the program and all variables |
| `load('name')` / `save('name')` | load / save `name.py` on drive 8 |
| `files()` | directory of the disk |
| `cls()`, `mem()`, `gc()`, `help()` | clear screen, free memory per area (see "Memory"), collect garbage, help |
| `peek(addr)`, `poke(addr, byte)` | 28-bit memory access; in bank 0 (0-65535) as the CPU sees it, so `$D000-$DFFF` are the I/O registers (`poke(0xD020, 2)` makes the border red) |

Floats are IEEE doubles, printed exactly as CPython prints them (`0.1 + 0.2` gives
`0.30000000000000004`). `import math` gives `sqrt floor ceil trunc fabs isnan isinf
isfinite exp log log10 log2 pow sin cos tan asin acos atan atan2 degrees radians hypot
copysign fmod` and `pi e tau inf nan`.

```
>>> import math
>>> math.sqrt(2), 7 / 2, f"{math.pi:.4f}", round(2.675, 2)
(1.4142135623730951, 3.5, '3.1416', 2.67)
```

Programs can read and write files on drive 8 with `open(name, mode)`, as in CPython
(no import): modes `'r'`, `'w'` and `'a'`, and `read([n])`, `readline()`,
`readlines()`, `write(s)`, `close()`, `for line in f` and `with`. Files are SEQ files
holding the text as it is (ASCII, `
` line ends); a CR or CR LF reads as `
`. Up
to 4 files can be open at once. `import os` gives `os.remove` (and `os.unlink`),
`os.rename(src, dst)`, `os.listdir()` and `os.path.exists(name)`.

Modules
-------

`import name` (also `import name as n` and `from name import x`) loads `name.py` from
the disk, or else `lib-name.py`, runs it once and gives a module with its own global
names, as in CPython. A second import gets the same module. `import math` and
`import os` are built in. The disk has no directories, so the build writes the modules
in `lib/` to it as `lib-<name>.py` (`lib/sprite.py` becomes `lib-sprite.py`, still
imported as `import sprite`); a module you `save()` yourself is just `name.py`.
(`tests/support/` holds modules that only the tests import, such as `modtest`.)

For hardware access, `peek` and `poke` reach the I/O registers, and
`os.sys(address, a=0, x=0, y=0, z=0)` calls machine code in bank 0, like BASIC's `SYS`,
and returns `(a, x, y, z, flags)`. The code runs with base page 0 (so `$02-$8F` are
free for it), interrupts off and the ROMs unmapped, and returns with `RTS`.
`$7E00-$7FFF` is kept free for it:

```
>>> import os
>>> for i, b in enumerate([0xE8, 0x8A, 0x60]):     # INX, TXA, RTS
...     poke(0x7E00 + i, b)
...
>>> os.sys(0x7E00, 0, 41)
(42, 42, 0, 0, 21)
```

These modules come with it, written in Python (the hardware ones with `peek`/`poke`):

* `lib/sound.py`: a `Sound` class for the SID chips (notes, waveforms, envelopes,
  tunes written as `'C4:8 E4:8 G4:16 R:4'`). The `tune` example plays "Ode to Joy".
* `lib/gfx.py`: 320x200 graphics in 256 colours (the full-colour character mode, the
  picture in bank 5). `gfx.mode()`, `text()`, `clear(c)`, `border(c)`,
  `background(c)`, `plot`, `point`, `line`, `hline`, `vline`, `rect`, `fill_rect`,
  `circle`, `fill_circle`, `palette(i, r, g, b)`, `rgb(r, g, b)` (a 6x6x6 colour
  cube), `grey(n)`, `wait_key()`, and the C64 colour names (`gfx.RED`, ...). Fills and
  clearing are DMA jobs, so they are fast; `plot` draws about 5000 pixels a second.
  The `gfxdemo` example draws a little scene.
* `lib/random.py`: Python's `random` module: `random()`, `seed()`, `randint`,
  `randrange`, `choice`, `choices` (with weights), `shuffle`, `sample`, `uniform`,
  `getrandbits`, `gauss`, `triangular`, `expovariate`, `getstate`/`setstate`. The
  generator is the "minimal standard" Lehmer generator, not CPython's Mersenne Twister,
  so a seed gives other numbers than on a PC; without a seed it starts from the
  MEGA65's hardware random number generator (`$D7EF`). The `dice` example uses it.
* `lib/sys.py`: Python's `sys` module: `version` (`'3.15.0 (MEGA65 Python 0.8.0, 45GS02
  assembly)'`), `version_info` (the Python language level, 3.15), `implementation`
  (`.name == 'mega65python'`, `.version`: this interpreter's version, 0.8.0),
  `hexversion`, `platform` (`'mega65'`), `maxsize`, `byteorder`, `argv`, `path`,
  `stdout`/`stderr` (`write()`), `stdin` (`readline()`) and `exit()`.
* `lib/time.py`: Python's `time` module on the real-time clock (`$FFD7110`):
  `time()`, `localtime()`/`gmtime()` (a `struct_time`), `mktime`, `strftime`,
  `asctime`, `ctime`, `sleep` (counted in video frames), `perf_counter`/`monotonic`
  (CIA 1's time-of-day clock, to a tenth of a second). The RTC keeps local time with no
  time zone, so `localtime()` and `gmtime()` are the same. The `clock` example uses it.
* `lib/sprite.py`: the 8 hardware sprites (24x21, over text or graphics) as a `Sprite`
  class: `Sprite(n, shape, color)`, `shape(rows)` (strings of `.` and `X`; in
  multicolour mode `1 2 3` for the three colours), `move(x, y)` in screen pixels,
  `show()`, `hide()`, `color(c)`, `expand(wide, tall)`, `behind(flag)`,
  `multicolor(flag)`; and `sprite.multicolors(c1, c2)`, `collisions()`, `hide_all()`,
  `wait_frame()`. It corrects X on real hardware, which shows sprites 16 pixels
  further left than Xemu. The `sprites` example bounces four balls over the text and
  flies a multicolour ship.
* `lib/gfx.py` also has `draw_text(x, y, text, c, bg=None)`: text in the 8x8 font on
  the graphics screen.
* `lib/keyboard.py`: keys without waiting for RETURN, for games and menus:
  `getkey()` (`''` if none), `waitkey()`, `getcode()`, `flush()`, the key names
  `keyboard.UP`/`DOWN`/`LEFT`/`RIGHT`/`HOME`/`CLR`/`DEL`/`INST`/`ESC`/`F1`-`F8`, and
  `shift()`, `ctrl()`, `mega()`, `alt()`.
* `lib/joystick.py`: `Joystick(port=2)` with `read()` (bits: 1 up, 2 down, 4 left,
  8 right, 16 fire), `up()`, `down()`, `left()`, `right()`, `fire()`, `direction()`
  (`(dx, dy)`). The `keys` example moves a star with either.
* `lib/curses.py`: a subset of Python's `curses` on the 80x25 text screen:
  `wrapper`, `initscr`/`endwin`, `newwin`, windows with `addstr`, `addch`, `move`,
  `getyx`, `getmaxyx`, `clear`, `clrtoeol`, `border`/`box`, `hline`/`vline`, `getch`
  (with `KEY_UP` and the like), `getkey`, `getstr`, `nodelay`; colour pairs
  (`init_pair`, `color_pair`) and the attributes `A_REVERSE`, `A_UNDERLINE`, `A_BLINK`,
  `A_BOLD` (the VIC-III's: colours 16-31). The screen has one background colour, so
  the last `init_pair` background wins. The `cursdemo` example has a menu.
* Pure-Python versions of standard modules, as in CPython (subsets where noted):
  * `json` (`dumps` with `indent`, `separators`, `sort_keys`; `loads`; `dump`/`load`
    on files; `JSONDecodeError`);
  * `string` (the constants, `capwords`);
  * `bisect`, `heapq`;
  * `functools` (`reduce`, `cmp_to_key`);
  * `copy` (`copy`, `deepcopy`);
  * `textwrap` (`wrap`, `fill`, `shorten`, `dedent`, `indent`);
  * `statistics` (`mean`, `fmean`, `geometric_mean`, `harmonic_mean`, `median` and
    `median_low`/`_high`, `mode`, `multimode`, `variance`, `pvariance`, `stdev`,
    `pstdev`);
  * `collections` (`deque`, `Counter`, `defaultdict`, `namedtuple`, `OrderedDict`);
  * `itertools` (all of it: `count`, `chain`, `islice`, `product`, `permutations`,
    `combinations`, `groupby`, `tee`, `batched`, ...).

  `statistics` and `collections` are `lib-stats.py` and `lib-colls.py` on the disk
  (`lib-statistics.py` would be too long a name); `import statistics` finds them.

```
import gfx
gfx.mode()
gfx.fill_circle(160, 100, 40, gfx.rgb(5, 3, 0))
gfx.line(0, 199, 319, 0, gfx.WHITE)
gfx.wait_key()
gfx.text()
```

`cls()` (and an error, so you see the traceback) also goes back to the text screen.
Printing in graphics mode writes to the hidden text screen. `load()`, `files()`,
`import` and `os.listdir()` load through bank 5, so they spoil the picture (and the
sprite shapes, which are at its end: `$5FA00`).

```
>>> with open('notes', 'w') as f:
...     f.write('hello' + chr(10))
...
6
>>> open('notes').read()
'hello
'
```

Example programs on the disk:

* `hello`, `primes`, `mandel` (fixed-point Mandelbrot), `bank` (classes and exceptions),
  `guess` (uses `input()`)
* `waves`: the `math` module (a sin/cos table and a damped sine wave drawn in text)
* `files`: a high-score table kept in a file (`open()`, `with`, appending, and
  `os.rename`/`remove`/`listdir`)
* `tune` (MEGA65 only): plays "Ode to Joy" with `lib/sound.py`
* `gfxdemo` (MEGA65 only): draws a scene (and text) with `lib/gfx.py`; press a key to end it
* `keys` (MEGA65 only): move a star with the cursor keys or a joystick in port 2
  (`keyboard`, `joystick`, `curses`)
* `cursdemo` (MEGA65 only): `curses` windows, colours, attributes and a menu
* `jsondemo`: a game save kept as JSON in a file (each run loads it, plays a level and
  saves it again), pretty-printed with `indent`
* `counter`: `Counter`, `defaultdict` and `deque` on a paragraph (letter and word
  counts with a text bar chart)
* `mixins`: multiple inheritance: animals built from ability mixins whose methods and
  `__init__`s chain through `super()`, a diamond where each class runs once, the
  method resolution order (`__mro__`), a mixin on an exception class, and an
  inconsistent order being refused
* `bignums`: big ints: 50!, Fibonacci(300), `2 ** 256` in decimal and hex, digits with
  commas, `divmod` and a modular power proving a Mersenne prime
* `recursion`: factorials, memoised Fibonacci (a closure), the Towers of Hanoi,
  permutations and the N queens puzzle (recursive generators with `yield from`), a
  flood fill, flattening nested lists, Ackermann's function and `RecursionError`
* `sprites` (MEGA65 only): bouncing ball sprites and a multicolour ship with `lib/sprite.py`
* `dice` (MEGA65 only): dice, cards, a lottery draw and weighted coins with `random`
* `clock` (MEGA65 only): the date in several formats, a stopwatch and a ticking clock
  with `time`
* `analog` (MEGA65 only): an analog clock with hour, minute and second hands, drawn with
  `gfx` and set by `time`; press a key to stop it

Controls
--------

At the `>>>` prompt:

* cursor left/right to edit the line, up/down for history (8 lines)
* HOME = start of line, CLR (shift+HOME) = clear the line, DEL = backspace
* a line ending in `:` (or with open brackets) continues with `...` until an empty line
* RUN/STOP or ESC cancels the line; RUN/STOP also interrupts a running program
  (`KeyboardInterrupt`)

In the editor (`edit()`):

* cursor keys move, HOME = start of line, CLR = top of the program, F1/F3 = page up/down
* RETURN keeps the indentation (and adds 4 after a `:`), TAB indents to the next 4
* DEL = backspace, INST (shift+DEL) = delete forward
* F5 = run the program, ESC or RUN/STOP = back to `>>>`

The keyboard is read through the MEGA65's ASCII typing queue, so `{ } [ ] _ | \ ~` work
as on the keys (` plus `:` `;` `.` `=` and so on; see the MEGA65 manual). The screen uses
ROM font A, which has the ASCII glyphs.

Tests
-----

`python tools\run_tests.py` boots Xemu headless and runs every `tests/*.py` file with
`load()` and `run()`. It compares the output with what desktop CPython prints for the
same file. It reads the output from a transcript the interpreter keeps in attic RAM.
Options: test names (also `examples/` names, like `mandel`), `-v` for full diffs,
`--show` to watch it run in an Xemu window, `--gc` to collect garbage before every
allocation (finds objects the interpreter forgot to keep alive; slow, minutes per test).

| Test | Covers |
|---|---|
| `t_basics` | int arithmetic (floor division and modulo signs, powers, shifts), comparisons, boolean operators |
| `t_strings` | string operations and methods, escapes, `repr`, f-strings with format specs, `%`, `str.format` |
| `t_lists` | list methods, slicing, comprehensions, `sorted` with key/reverse, slice assignment and `del` (plain and extended) |
| `t_dicts` | dicts, tuples, unpacking (also nested), dict comprehensions |
| `t_control` | if/elif/else, while/for with else, break/continue, conditional expressions, `:=` |
| `t_funcs` | defaults, keyword arguments, recursion, globals, lambdas, map/filter |
| `t_classes` | classes, inheritance, `super()`, dunder methods, bound methods |
| `t_except` | try/except/else/finally, custom exceptions, re-raise, assert |
| `t_builtins` | the builtin functions |
| `t_memory` | allocation-heavy code (many garbage collections) |
| `t_floats` | float literals and repr, arithmetic and mixing with ints, `//` `%` `**`, `float()`, `round()`, `%`/`format` specs, the `math` module |
| `t_import` | a module from the disk (`tests/support/modtest.py`): its functions, classes and globals, `import as`, `from import` (also in parentheses), `from import *` (a disk module's names, its `__all__`, `math`, into another module), one import only, `ImportError` |
| `t_random` | `random`: seeds repeat, ranges, shuffle, sample, weighted choices, errors (properties that hold for CPython's generator too) |
| `t_sys` | `sys`: the version values, `version_info` comparisons, `stdout.write`, `exit` |
| `t_time` | `time`: `gmtime`, `strftime`, `asctime` of fixed times, `struct_time`, the clock's plausibility |
| `t_sets` | set and frozenset literals, comprehensions, operators, subset comparisons, methods (also with several iterables), in-place operators, `unhashable` errors |
| `t_args` | `*args`, `**kwargs`, keyword-only parameters, `f(*a, **k)`, forwarding wrappers, argument errors |
| `t_decorators` | function, factory, stacked and class decorators; `staticmethod`, `classmethod`, `property` with setters, inherited |
| `t_closures` | nested functions and lambdas over enclosing variables, `nonlocal`, late binding, recursion through a closure, classes inside functions |
| `t_hash` | hashed dicts and sets: growth, deletes, keys equal across types, tuple/frozenset/instance keys (`__hash__`, `__eq__`), unhashable keys, order |
| `t_protocols` | user classes as iterators (`__iter__`/`__next__`, `StopIteration` ends the loop; `__iter__` returning a built-in iterator), `__contains__`, `__setitem__`, `__delitem__`, `__call__`, `__eq__` against other types (both sides) |
| `t_json` | `json`: `dumps` (indent, separators, sort_keys), `loads`, escapes, errors, `dump`/`load` with files |
| `t_libs` | `string`, `bisect`, `heapq`, `functools`, `copy` |
| `t_stats` | `statistics` |
| `t_colls` | `collections` (`deque`, `Counter`, `defaultdict`, `namedtuple`, `OrderedDict`, `del`) and `textwrap` |
| `t_itertools` | `itertools`, imported with `from itertools import *` |
| `t_mix` | features combined: closures with `*args`, decorated methods, sets of tuples from comprehensions, nested unpacking in loops |
| `t_excmix` | exceptions raised from inside closures, decorators, `*args` calls, comprehensions, class bodies and iterators, and what is left working afterwards |
| `t_gcmix` | the same features while the heap is nearly full (many collections) |
| `t_generators` | `yield`, `yield from` (also recursive), `send`, `close`, `try`/`finally` across a `yield`, exceptions leaving a generator, a running generator re-entered, generators in closures and methods, driven by `for`, `next`, `zip`, `sorted`, `sum`, `in`, `join`, and leaving a loop then going on; generator expressions (lazy, the first iterable taken at once, in functions, lambdas and class bodies, chained, infinite); `close()` running `finally`/`with` exits, `throw()`; `yield from` with `send()` and return values, `StopIteration.value`; lazy `map()`/`filter()` |
| `t_edges` | edge cases: deep recursion through a closure, many parameters and locals, changing a dict or set while iterating it (`RuntimeError`: "changed size", and CPython's "keys changed" when keys are deleted and added), imports inside functions, `RecursionError` and recovering from it, lazy `sum` of a big range |
| `t_blocks` | `finally` on `break`/`continue`/`return` (nested, mixed with `with`, `return` and `break` inside `finally`), `with` passing the exception to `__exit__` and swallowing it, several managers in one `with` |
| `t_unpack` | `*` and `**` in list / tuple / set / dict displays, starred assignment and `for` targets |
| `t_bigint` | ints beyond 32 bits: the operators (floored `//` and `%`, `**`, shifts, `&`, `\|`, `^`, `~` on negatives), comparisons, `int()` of strings and floats, literals, `float()`, hashing, `str`/`repr`, `%d`/`%x`/`format` with `,`, `hex`/`bin`/`oct`, `divmod`, `pow` with a modulus |
| `t_mi` | multiple inheritance: diamonds and the C3 order, `super()` chains through both sides, `__mro__`/`__bases__`, mixins on exceptions, an inconsistent order (`TypeError`), `super().__init__()` reaching `object` |
| `t_compscope` | comprehensions keep their loop variables to themselves: at the top level, in functions and class bodies, nested, with lambdas over them (late binding and `i=i` defaults), the first iterable taken from outside |
| `t_introsp` | `dir`, `vars`, `globals`, `delattr`, `slice` objects and their attributes, `ascii` |
| `t_strmeth` | the newer `str` methods (`rfind`, `partition`, `rsplit`, `expandtabs`, ...) and methods of builtin types as values |
| `t_errors` | error messages that name the type, `issubclass` (also of builtin types and `object`), `min`/`max` `default=`, `!r` with a format spec, `#` in format specs, annotated assignments |
| `t_files` | `open()` in each mode, `read`/`readline`/`readlines`/`write`, iteration, `with` (also with `return`, `break` and exceptions), a multi-block file, `FileNotFoundError`, the `os` functions |

Other tools: `tools\xemu_run.py` (boot, type, read the screen or transcript, screenshot),
`tools\trace.py` (single-step from a debug hold point), `tools\disasm.py` (bytecode),
`tools\bisect_run.py` (find the line that breaks a program).

Memory
------

Python objects (every int that does not fit in 15 bits, and every float, string, list,
tuple, dict, function, class and instance) live in a **64 KB object heap** in chip-RAM bank 4.
`mem()` runs a garbage collection and shows what is free in that heap and in the other
areas a program fills up:

```
>>> mem()
objects (heap, bank 4)  60350 of 65264 bytes free
bytecode (bank 1)       32761 of 32768 bytes free
names (symbol table)     1808 of  2048 names free
program source (attic)  65520 of 65520 bytes free
value stack (bank 0)     2047 of  2048 slots free
bank 5 (64 KB) is kept for graphics.
```

About 60 KB of the heap is free after start-up (the rest holds the builtins, exception classes and the
names of symbols). Small ints (-16384..16383), `None`, `True` and `False` take no heap
space. The heap is shared by everything a program creates, so it is the limit that
matters for big data. When a collection frees less than 1 KB, the program gets a
`MemoryError` instead of slowing to a crawl. The collector does not move objects, so
thousands of small live objects with gaps between them can also cause a `MemoryError`
for a big list or string while `mem()` still shows free space.

What objects cost, roughly (4-byte header included):

| Object | Bytes |
|---|---|
| int outside -16384..16383 | 8 |
| float | 12 |
| str | 6 + its length (rounded up to even) |
| list | 10, plus an item array of 4 + 2 per slot (it grows by doubling) |
| tuple | 6 + 2 per item |
| dict, set | 12, plus a pair array of 4 + 4 per slot; from 8 entries a hash index of 6 + 2 per slot (more than twice the entries) |
| instance | 8, plus a dict for its attributes |

Everything else is outside the heap (the bytecode, names, source and value stack lines of
`mem()` show the ones a program fills up):

| What | Where | Size |
|---|---|---|
| Program source (the editor buffer) | attic RAM | up to 64 KB |
| Compiled bytecode (program + REPL input that defines functions) | chip RAM bank 1 | 30 KB |
| Graphics mode's character pointers (`lib/gfx.py`) | chip RAM bank 1 `$1D800` | 2000 bytes |
| Global variables | chip RAM bank 1 | 2048 names |
| Symbol names, line table, REPL text and history, sort scratch | attic RAM | a few hundred KB of the 8 MB |
| The interpreter's code overlays and tails, and the output transcript | attic RAM | 48 KB + 1 MB |
| Float conversion workspace (bignums, digits) | chip RAM bank 1, bank 0 `$1F00` | 1 KB |
| Read buffers of open files | chip RAM bank 1 | 4 x 256 bytes |
| Value stack (locals, temporaries) | bank 0 | 2048 values: enough for 100-200 nested calls |
| Bank 5 | chip RAM | the graphics picture (`lib/gfx.py`); also the disk staging buffer |

Most of the 8 MB of attic RAM is unused. Python objects cannot live there because each
value is a 16-bit reference to one 64 KB bank, and attic RAM is slower for the CPU to
reach. A bigger heap is on the `TODO.md` list.

Architecture
------------

* **Interpreter**: single-pass compiler (`compiler.asm`, `lexer.asm`) to stack bytecode
  (`opcodes.asm`); a VM (`vm.asm`) with call frames, exception handlers and nested runs
  (native code calling back into Python for `key=`, `__str__`, `__eq__`, ...).
* **Values** are 16-bit refs: odd = small int (15-bit), 2/4/6 = None/False/True,
  otherwise an object in the 64 KB heap in bank 4. Bigger ints are boxed 32-bit, and
  beyond 32 bits big ints (a sign and up to 210 bytes; `bigint.asm`, tail N).
  Mark-and-sweep garbage collector with a free list (`heap.asm`).
* **Memory**: interrupts off, ROMs unmapped while Python runs; resident code at
  `$2001-$7FFF` and `$F000-$FEFF`; a 20 KB overlay window at `$8000` holds either the
  builtins or the compiler and editor, copied in from attic RAM by DMA. With the builtins
  in, the window's last 4 KB is one of four "tails" (float text conversion, the `math`
  module, files and `os`, or rarely used code and data such as `help()` and `load()`), swapped in
  by a 4 KB DMA when needed.
  The KERNAL is restored around each disk call, and its memory areas are left alone as
  the MEGA65 book's memory map asks. Bank 5 is kept free for graphics.
* **Floats**: IEEE doubles computed in software with 64-bit mantissas (and the hardware
  multiplier), correctly rounded; exact decimal conversion with bignums (shortest repr,
  like CPython). See `docs/INTERNALS.md`.
* Details: `docs/INTERNALS.md`.

Differences from CPython
------------------------

* **Integers** have any size up to 505 decimal digits (about 1680 bits); a bigger
  result raises `OverflowError`. Ints within 32 bits are as fast as before; beyond that
  the work is done digit by digit (byte by byte), so `2 ** 1000` takes a moment.
  Indexes, `range()` bounds, repeat counts and the like must fit in 32 bits
  (`OverflowError`). `/` of two big ints, and big ints mixed with floats, go through
  floats (CPython divides exactly). `hash()` of a big int is not CPython's. `round()` of
  an int ignores a negative `ndigits` (`round(1234, -2)` gives 1234).
* **Floats**: `float` has no methods (`is_integer()`, `hex()`, ...); no `complex` (a
  negative number to a fractional power raises `ValueError`). The `math` functions are
  computed here, not by a C library, so a result can differ from CPython's in the last
  digit (CPython's own results vary by platform the same way). Float literals and
  `float()` keep 30 significant digits. `hash()` of a non-integral float differs from
  CPython's. `math` is a class object: `print(math)` shows `<class 'math'>`.
* **Files**: text only (`'b'` in the mode is ignored and gives `str`), no `seek`/`tell`,
  file names of 1-16 characters on drive 8 (`os` refuses `* ? , : =` and quotes, which
  the drive would read as patterns or commands). `os` has only `remove`, `unlink`,
  `rename`, `listdir`, `path.exists` and `sys` (a MEGA65 addition); `listdir()` ignores its argument (one disk, no
  directories), and `os` and `os.path` print as classes. A file that is still open
  (one only partly read, without `with` or `close()`) cannot be removed: the drive
  reports no such file. A file
  read to its end gives its KERNAL channel back by itself; a file being written must be
  closed (or used with `with`) to be complete on disk. `open()`'s mode `'w'` replaces
  an existing file. `read()` returns at most 8 KB (the string builder's size).
* **`with`** works as in CPython (several managers too, `with a as x, b as y:`): when
  the block raises, `__exit__` gets the exception's class and the exception, and a true
  result swallows it. The traceback argument is `None` (there are no traceback
  objects). `break`, `continue` and `return` run the `finally` blocks and `__exit__`
  calls they leave.
* **Sets** (`{1, 2}`, `set()`, `frozenset()`, set comprehensions, `| & - ^`, `<=` and
  the other subset comparisons, and the set methods) keep their members in the order
  they were added, where CPython uses hash order: `print({3, 1, 2})` shows `{3, 1, 2}`
  (CPython: `{1, 2, 3}`).
* **Dicts and sets** with 8 or more entries are hashed (smaller ones are searched one
  by one, which is as fast for them). Keys follow CPython's rules: lists, dicts, sets
  and instances whose class defines `__eq__` but not `__hash__` are unhashable
  (`TypeError`); `1`, `1.0` and `True` are the same key. `hash()` gives CPython's
  values for ints and integral floats; for strings, tuples and frozensets it gives
  other numbers than CPython (whose string hashes change every run anyway).
* **Closures** (nested functions and lambdas using the variables of the functions
  around them, `nonlocal`) work as in CPython. A variable a nested function uses cannot
  be deleted (`del`); a function can have up to 48 locals and 4 `nonlocal` names.
* **Decorators** on functions, methods and classes work as in CPython, with
  `staticmethod`, `classmethod` and `property` (also `property(fget, fset)` and
  `@x.setter`). A property's setter is honoured; deleters are not supported. A class
  body sees the names it defined before (`b = a * 2`, `@x.setter`).
* **Parameters and calls**: `*args`, `**kwargs`, keyword-only parameters (after `*` or
  `*args`), and `f(*iterable, **dict)` in calls work as in CPython (at most 16
  arguments reach a builtin, 48 locals a function).
* **Generators**: a function with `yield` returns a generator, as in CPython: `for`
  loops, `next()`, builtins and other generators drive it, `send()` passes a value in,
  `return` ends it, `yield from` delegates, and `try`/`except`/`finally` blocks may
  span a `yield`. Generator expressions are lazy generators too (`sum(x for x in
  range(60000))` needs no list). `close()` raises `GeneratorExit` at the `yield`, so
  `finally` blocks and `with` exits run; `throw()` raises an exception there; `yield
  from` passes `send()` values on and gives the inner generator's return value, which
  `StopIteration.value` carries too; `throw()` and `close()` go on to the generator a
  `yield from` waits on, and a `StopIteration` leaving a generator becomes
  `RuntimeError` (PEP 479). Differences: `raise StopIteration(v)` in your own code
  gives no `.value` (only `.args`), and `yield` cannot be used in a lambda.
* **Modules**: a module's code and name are kept until `run()` or `new()`; a name a
  module does not define falls back to the main program's global of that name (CPython
  would raise `NameError`). Module names are up to 13 characters (`name.py`), or 9 for
  `lib-name.py` (longer library names have a short disk name: `statistics` and
  `collections`).
* `map()`, `filter()`, `zip()` and the other builtin iterators print as `<iterator>`
  and their type is `iterator` (CPython: `<map object at ...>`, `map`).
* A program's globals stay after `run()`, so a program that defines `load`, `save`,
  `run`, ... replaces those REPL commands until `new()`.
* `globals()` and `vars()` with no argument give a new dict of the main program's global
  names: changing it does not change the variables. `dir(obj)` lists what the object
  holds and its class's (and the bases') names and a builtin type's methods, not the
  dunder methods every object has in CPython.
* Tracebacks show each level as `  line N, in name` (no file name or source line), the
  innermost 12 levels at most.
* Memory: Python objects share a 64 KB heap (see "Memory" above).

Note: this is a 45GS02 target. `STZ` stores the Z register, not zero; use
`LDA #0 / STA`. See `.claude/CLAUDE.md` and `docs/` for MEGA65 notes.
