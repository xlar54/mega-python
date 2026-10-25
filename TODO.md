TODO
====

Language
--------

* Floats: `float` methods (`is_integer`, `hex`, `as_integer_ratio`), `math` functions
  still missing (`factorial`, `gcd`, `isclose`, `modf`, `frexp`, `ldexp`, hyperbolics),
  CPython's `hash()` for non-integral floats, faster `sin`/`cos`/`exp`/`log` (they sum
  ~15 series terms of 64-bit multiplies).
* Arbitrary-precision ints (now 32-bit with OverflowError).
* Sets: methods with several other iterables (`a.union(b, c)`), `|=` and friends
  changing the set in place, CPython's hash order.
* Generators and `yield` (a frame object that keeps its locals off the value stack).
  Then real lazy `map`/`filter`/`zip`/generator expressions and `dict` views.
* Closures: `del` of a captured variable; the free variable's name in the
  "cannot access free variable" NameError.
* Unpacking in displays (`[*a, *b]`, `{**d, 'k': 1}`), positional-only parameters
  (`/`); `property` deleters, `functools.wraps`; the names in argument errors
  ("f() got an unexpected keyword argument 'x'").
* `with`: pass the exception to `__exit__` and let a true result swallow it; several
  managers in one `with`.
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
* Libraries: `collections.namedtuple`/`OrderedDict`, `itertools`, `re`, `datetime`
  (some need generators first).
* `break`/`continue` inside `try` with `finally` should run the finally block.
* Dicts: keep each key's hash next to it, so growing and deleting do not hash the
  keys again; deletes are O(n) (the pairs move down and the index is rebuilt).
* `str` methods still missing: `partition`, `rsplit`, `swapcase`, `expandtabs`, ...
* Tracebacks with the call chain (the frames hold the return ips).

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

* Code space (see the sizes `build.bat` prints): part 1 has about 1.9 KB free, overlay R
  about 2 KB, part 2 about 190 bytes; each tail has room left, and more tails can be
  added (`docs/INTERNALS.md`, "Tails"). More code should go into tails (only code that never
  runs Python code; see `docs/INTERNALS.md`) or overlay C (compile time).

* Objects carry a 4-byte header; strings could drop their separate length word.
* The heap is one 64 KB bank (16-bit refs). A second heap bank would need wider refs or
  an indirection table.
* The value stack is 2048 refs: deep recursion raises RecursionError at about 100-200
  levels depending on the locals.
