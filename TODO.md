TODO
====

Language
--------

* Floats: a software float type (`T_FLOAT` is reserved) with `/`, `float()`, `math`.
  The hardware multiplier/divider ($D770) can do the mantissa work.
* Arbitrary-precision ints (now 32-bit with OverflowError).
* Sets (`{1, 2}`, `set()`), `frozenset`.
* Generators and `yield` (a frame object that keeps its locals off the value stack).
  Then real lazy `map`/`filter`/`zip`/generator expressions and `dict` views.
* Closures / `nonlocal` (cells for captured locals).
* `*args`, `**kwargs`, keyword-only arguments, decorators, `with`.
* `import` of built-in modules: `mega65` (graphics on the reserved bank-5 framebuffer,
  sprites, sound), `time`, `random`, `math`, `sys`, `gc`.
* `StopIteration` from a user `__next__` should end a `for` loop (it propagates now).
* `break`/`continue` inside `try` with `finally` should run the finally block.
* Hash-based dicts (lookups are linear, fine for small dicts, slow for big ones).
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

* Objects carry a 4-byte header; strings could drop their separate length word.
* The heap is one 64 KB bank (16-bit refs). A second heap bank would need wider refs or
  an indirection table.
* The value stack is 2048 refs: deep recursion raises RecursionError at about 100-200
  levels depending on the locals.
