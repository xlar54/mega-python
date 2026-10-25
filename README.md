MEGA65 Python
=============

A Python 3 interpreter for the MEGA65, written entirely in 45GS02 assembly (64tass). It
boots to a `>>>` prompt, has a full-screen program editor, and loads and saves `.py`
files on the disk. Like CPython, it compiles each piece of source to bytecode in memory
and runs that on a bytecode VM.

It implements a large subset of Python 3: ints, strings, lists, tuples, dicts, functions,
lambdas, classes with inheritance and `super()`, exceptions, comprehensions, f-strings and
most everyday builtins. The test programs in `tests/` print exactly what CPython prints
for them. See "Differences from CPython" below for what is missing.

Build
-----

Run `build.bat`. It:

1. generates `src/gen/tables.asm` (`tools/gen_tables.py`: symbols and builtin tables),
2. copies `examples/*.py` and `tests/*.py` to `target/py/` as disk files (`tools/mkpy.py`),
3. assembles `src/main.asm` with the bundled 64tass into `target/image.bin`,
4. splits the image into the program `mega-python` and the file `mpy-ovl`
   (`tools/split.py`), and
5. writes `target/mega-python.d81` with c1541 (`mega-python`, `autoboot.c65`, `mpy-ovl`,
   and every `.py` file).

Run
---

`run.bat` builds and starts Xemu with the disk. On a real MEGA65, mount the D81 and
reset: `AUTOBOOT.C65` starts the interpreter, which then loads `mpy-ovl` from the same
disk.

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
| `cls()`, `mem()`, `gc()`, `help()` | clear screen, free memory, collect garbage, help |
| `peek(addr)`, `poke(addr, byte)` | 28-bit memory access (`peek(0xD020)`, `poke(0xD020, 2)`) |

Example programs on the disk: `hello`, `primes`, `mandel` (fixed-point Mandelbrot),
`bank` (classes and exceptions) and `guess` (uses `input()`).

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
`--show` to watch it run in an Xemu window.

| Test | Covers |
|---|---|
| `t_basics` | int arithmetic (floor division and modulo signs, powers, shifts), comparisons, boolean operators |
| `t_strings` | string operations and methods, escapes, `repr`, f-strings with format specs, `%`, `str.format` |
| `t_lists` | list methods, slicing, comprehensions, `sorted` with key/reverse |
| `t_dicts` | dicts, tuples, unpacking (also nested), dict comprehensions |
| `t_control` | if/elif/else, while/for with else, break/continue, conditional expressions, `:=` |
| `t_funcs` | defaults, keyword arguments, recursion, globals, lambdas, map/filter |
| `t_classes` | classes, inheritance, `super()`, dunder methods, bound methods |
| `t_except` | try/except/else/finally, custom exceptions, re-raise, assert |
| `t_builtins` | the builtin functions |
| `t_memory` | allocation-heavy code (many garbage collections) |

Other tools: `tools\xemu_run.py` (boot, type, read the screen or transcript, screenshot),
`tools\trace.py` (single-step from a debug hold point), `tools\disasm.py` (bytecode),
`tools\bisect_run.py` (find the line that breaks a program).

Memory
------

Python objects (every int that does not fit in 15 bits, and every string, list, tuple,
dict, function, class and instance) live in a **64 KB object heap** in chip-RAM bank 4.
`mem()` runs a garbage collection and reports what is free in that heap; about
61-62 KB is free after start-up (the rest holds the builtins, exception classes and the
names of symbols). Small ints (-16384..16383), `None`, `True` and `False` take no heap
space. The heap is shared by everything a program creates, so it is the limit that
matters for big data. When a collection frees less than 1 KB, the program gets a
`MemoryError` instead of slowing to a crawl.

What objects cost, roughly (4-byte header included):

| Object | Bytes |
|---|---|
| int outside -16384..16383 | 8 |
| str | 6 + its length (rounded up to even) |
| list | 10, plus an item array of 4 + 2 per slot (it grows by doubling) |
| tuple | 6 + 2 per item |
| dict | 10, plus a pair array of 4 + 4 per slot |
| instance | 8, plus a dict for its attributes |

Everything else is outside the heap and does not count in `mem()`:

| What | Where | Size |
|---|---|---|
| Program source (the editor buffer) | attic RAM | up to 64 KB |
| Compiled bytecode (program + REPL input that defines functions) | chip RAM bank 1 | 36 KB |
| Global variables | chip RAM bank 1 | 2048 names |
| Symbol names, line table, REPL text and history, sort scratch | attic RAM | a few hundred KB of the 8 MB |
| The interpreter's two code overlays and the output transcript | attic RAM | 32 KB + 1 MB |
| Value stack (locals, temporaries) | bank 0 | 2048 values: enough for 100-200 nested calls |
| Bank 5 | chip RAM | 64 KB kept free for graphics; also the disk staging buffer |

Most of the 8 MB of attic RAM is unused. Python objects cannot live there because each
value is a 16-bit reference to one 64 KB bank, and attic RAM is slower for the CPU to
reach. A bigger heap is on the `TODO.md` list.

Architecture
------------

* **Interpreter**: single-pass compiler (`compiler.asm`, `lexer.asm`) to stack bytecode
  (`opcodes.asm`); a VM (`vm.asm`) with call frames, exception handlers and nested runs
  (native code calling back into Python for `key=`, `__str__`, `__eq__`, ...).
* **Values** are 16-bit refs: odd = small int (15-bit), 2/4/6 = None/False/True,
  otherwise an object in the 64 KB heap in bank 4. Bigger ints are boxed 32-bit.
  Mark-and-sweep garbage collector with a free list (`heap.asm`).
* **Memory**: interrupts off, ROMs unmapped while Python runs; resident code at
  `$2001-$7FFF` and `$E800-$FFF9`; a 16 KB overlay window at `$8000` holds either the
  builtins or the compiler and editor, copied in from attic RAM by DMA. The KERNAL is
  restored around each disk call. Bank 5 is kept free for graphics.
* Details: `docs/INTERNALS.md`.

Differences from CPython
------------------------

* **Integers are 32-bit**: results outside that range raise `OverflowError`.
* **No floats yet**: `/` raises an error; use `//`. `round()` takes ints only.
* Not supported yet: sets, generators/`yield`, `with`, closures over enclosing function
  variables (`nonlocal`), `*args`/`**kwargs`, decorators, multiple inheritance, `import`
  (there are no modules yet), the `bytes` type.
* `dict.keys()`, `values()` and `items()` return lists (snapshots, not live views).
  `map()`, `filter()` and generator expressions produce lists.
* `try`/`finally`: a `break`/`continue` out of the `try` body skips the `finally` block.
* Error messages and tracebacks are shorter: `Traceback: line N` and the exception.
* Memory: Python objects share a 64 KB heap (see "Memory" above).

Note: this is a 45GS02 target. `STZ` stores the Z register, not zero; use
`LDA #0 / STA`. See `.claude/CLAUDE.md` and `docs/` for MEGA65 notes.
