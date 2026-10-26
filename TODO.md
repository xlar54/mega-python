TODO
====

Language
--------

* Floats: `float` methods (`is_integer`, `hex`, `as_integer_ratio`), `math` functions
  still missing (`factorial`, `gcd`, `isclose`, `modf`, `frexp`, `ldexp`, hyperbolics),
  CPython's `hash()` for non-integral floats, faster `sin`/`cos`/`exp`/`log` (they sum
  ~15 series terms of 64-bit multiplies).
* Big ints: no 505-digit cap (16-bit lengths), exact `/` and float comparisons,
  CPython's `hash()`, faster `*` and `//` (16-bit limbs, Karatsuba), `range()` and
  indexes beyond 32 bits, `int.bit_length()` and the other int methods, `round()` with
  a negative `ndigits` (for all ints), `math.gcd`/`isqrt`/`comb`/`factorial`.
* Sets: CPython's hash order.
* Comprehensions in a scope of their own (now their loop variables leak into the code
  around them; at the top level they replace a global of that name). Generator
  expressions already have one: compiling list / dict / set comprehensions the same way
  costs a generator per comprehension, so a cheaper scheme (hidden local slots) is better.
* Live `dict` views (`keys()`, `values()`, `items()` are list snapshots); iterator
  types and reprs per kind (`map`, `filter`, `zip`, `list_iterator`: now `iterator`).
* `.value` of a `StopIteration` raised by Python code; traceback objects (`with`'s `__exit__` gets `None`), file names and source lines in
  tracebacks.
* `cls.mro()`, subclassing builtin types, `__getattr__`/`__setattr__` hooks,
  `match`, `eval`/`exec`, `locals()`, `bytes`; `globals()` of a module's code (it gives
  the main program's), a live `globals()` dict.
* Closures: `del` of a captured variable; the free variable's name in the
  "cannot access free variable" NameError.
* Positional-only parameters
  (`/`); `property` deleters, `functools.wraps`; the names in argument errors
  ("f() got an unexpected keyword argument 'x'").
* Files: `seek`/`tell`, binary mode (`bytes`), more of `os` (`getcwd`, `stat`,
  `path.getsize`), other drives, closing a forgotten file when it is collected (it
  keeps its drive channel, and the drive will not remove it).
* Modules (`lib/*.py`, using `peek`/`poke`/`os.sys`): 16-colour
  and bigger sprites (VIC-IV),
  faster `plot`/`line` (machine code through `os.sys`), double buffering; `gc`; more of
  `sys` (`modules`, `getrecursionlimit`, `getsizeof`);
  setting the RTC from `time`; `random` with CPython's Mersenne Twister (it needs
  unsigned 32-bit arithmetic: bigger ints).
* `os.sys()` for code outside bank 0 (it would need a MAP of the target). (`math` is a class object; a real
  module type would print as `<module 'math'>`.)
* Libraries: `re`, `datetime`. `namedtuple` classes could subclass `tuple` once builtin
  types can be subclassed.
* Dicts: keep each key's hash next to it, so growing and deleting do not hash the
  keys again; deletes are O(n) (the pairs move down and the index is rebuilt).
* `str` methods still missing: `encode`, `translate`, `format_map`; `#` with `0` padding (`{255:#06x}`) puts the zeros first.
* Iterate lazily where a list is built first today: `min`/`max`, `x in it` for
  non-sequences (`x in range(10**6)` should be arithmetic, as CPython), `str.join`,
  `set()`/`tuple()` of an iterator. Big ranges give `MemoryError` there (`sum` is lazy).

Environment
-----------

* `del` of a shadowed builtin name does not bring the builtin back (globals and builtins
  share one table).
* Editor: search, cut/paste of lines, syntax colours, line wrap marker.
* `save()` writes via the KERNAL: test on real hardware (Xemu is lenient about KERNAL
  disk calls).
* Choose the drive (now 8) and support SD-card files via HYPPO.

Memory
------

* Code space (see the sizes `build.bat` prints): part 1 has about 580 bytes free, overlay R
  about 290, part 2 about 120, tail B about 150, tail X about 190, tail H about 300, tail T
  about 360, tail P about 430, tail N about 650, tail M about 2.8 KB (one more tail fits
  in mpy-ovl's 64 KB before the boot loader must change);
  move cold code out before it fills up again (as sets went to tail T, fbig.asm to tail A,
  tracebacks / keyword binding / class creation to tails H and X); new code should go in a
  tail or overlay C; each tail has room left, and more tails can be
  added (`docs/INTERNALS.md`, "Tails"). More code should go into tails (only code that never
  runs Python code; see `docs/INTERNALS.md`) or overlay C (compile time).

* Objects carry a 4-byte header; strings could drop their separate length word.
* The heap is one 64 KB bank (16-bit refs). A second heap bank would need wider refs or
  an indirection table.
* The value stack is 2048 refs: deep recursion raises RecursionError at about 100-200
  levels depending on the locals.
