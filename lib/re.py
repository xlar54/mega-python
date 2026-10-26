# re: regular expressions, as in Python's re module (written in Python: fine for short
# texts). A pattern is parsed into a tree and compiled to a small program that a
# backtracking machine runs; it remembers the (instruction, position) states that
# already failed, so a match takes at most (pattern size x text length) steps.
#
#   import re
#   re.findall(r'\d+', 'a1b22c333')            ['1', '22', '333']
#   re.sub(r'(\w+)@(\w+)', r'\2 at \1', s)
#
# Supported: . [] [^] ranges, \d \w \s \D \W \S \b \B \A \Z, ^ $, | (...) (?:...)
# (?P<name>...) (?=...) (?!...), * + ? {m,n} and their lazy forms, the flags I, M, S.
# Not: backreferences inside a pattern, lookbehind, VERBOSE.

I = IGNORECASE = 2
M = MULTILINE = 8
S = DOTALL = 16
A = ASCII = 256


class error(Exception):
    pass


# instructions: (op, a, b)
_CHAR, _ANY, _CLS, _SPLIT, _JMP, _SAVE, _MATCH = range(7)
_BOL, _EOL, _WORDB, _NWORDB, _BEGIN, _END, _LOOK = range(7, 14)

_DIGITS = '0123456789'
_SPACES = ' \t\n\r\f\v'


def _is_word(c):
    return c.isalnum() or c == '_'


def _in_class(items, c, icase):
    if icase:
        cs = (c, c.lower(), c.upper())
    else:
        cs = (c,)
    for k in items:
        kind = k[0]
        for ch in cs:
            if kind == 'c':
                if ch == k[1]:
                    return True
            elif kind == 'r':
                if k[1] <= ch <= k[2]:
                    return True
            elif kind == 'd':
                if (ch in _DIGITS) != k[1]:
                    return True
            elif kind == 'w':
                if _is_word(ch) != k[1]:
                    return True
            elif kind == 's':
                if (ch in _SPACES) != k[1]:
                    return True
    return False


class _Parser:
    def __init__(self, pattern):
        self.p = pattern
        self.i = 0
        self.ngroups = 0
        self.names = {}

    def peek(self):
        return self.p[self.i] if self.i < len(self.p) else ''

    def take(self):
        c = self.peek()
        self.i += 1
        return c

    def alt(self):
        items = [self.cat()]
        while self.peek() == '|':
            self.i += 1
            items.append(self.cat())
        return items[0] if len(items) == 1 else ('alt', items)

    def cat(self):
        items = []
        while self.i < len(self.p) and self.peek() not in '|)':
            items.append(self.rep())
        return ('cat', items)

    def rep(self):
        node = self.atom()
        while True:
            c = self.peek()
            if c == '*':
                lo, hi = 0, None
            elif c == '+':
                lo, hi = 1, None
            elif c == '?':
                lo, hi = 0, 1
            elif c == '{' and self._is_count():
                self.i += 1
                lo, hi = self._count()
                self.i -= 1
            else:
                return node
            self.i += 1
            greedy = True
            if self.peek() == '?':
                self.i += 1
                greedy = False
            node = ('rep', node, lo, hi, greedy)
            c = self.peek()
            if c and c in '*+?' or c == '{' and self._is_count():
                raise error('multiple repeat at position %d' % self.i)

    def _is_count(self):
        j = self.i + 1
        while j < len(self.p) and (self.p[j].isdigit() or self.p[j] == ','):
            j += 1
        return j < len(self.p) and self.p[j] == '}' and j > self.i + 1

    def _count(self):
        j = self.i + self.p[self.i:].index('}')
        text = self.p[self.i:j]
        self.i = j + 1
        if ',' in text:
            a, b = text.split(',')
            return int(a) if a else 0, int(b) if b else None
        n = int(text)
        return n, n

    def atom(self):
        c = self.take()
        if c == '(':
            return self.group()
        if c == '[':
            return self.cls()
        if c == '.':
            return ('any',)
        if c == '^':
            return ('bol',)
        if c == '$':
            return ('eol',)
        if c == '\\':
            return self.escape(False)
        if c in '*+?':
            raise error('nothing to repeat at position %d' % (self.i - 1))
        return ('lit', c)

    def group(self):
        if self.p[self.i:self.i + 2] == '?:':
            self.i += 2
            node = self.alt()
            self.close()
            return node
        if self.p[self.i:self.i + 2] == '?=' or self.p[self.i:self.i + 2] == '?!':
            neg = self.p[self.i + 1] == '!'
            self.i += 2
            node = self.alt()
            self.close()
            return ('look', node, neg)
        name = None
        if self.p[self.i:self.i + 3] == '?P<':
            j = self.i + self.p[self.i:].index('>')
            name = self.p[self.i + 3:j]
            self.i = j + 1
        elif self.peek() == '?':
            raise error('unsupported group at position %d' % self.i)
        self.ngroups += 1
        n = self.ngroups
        if name:
            self.names[name] = n
        node = self.alt()
        self.close()
        return ('group', n, node)

    def close(self):
        if self.take() != ')':
            raise error('missing ), unterminated subpattern')

    def cls(self):
        neg = False
        if self.peek() == '^':
            self.i += 1
            neg = True
        items = []
        first = True
        while True:
            if self.i >= len(self.p):
                raise error('unterminated character set')
            c = self.take()
            if c == ']' and not first:
                break
            first = False
            if c == '\\':
                e = self.escape(True)
                if e[0] == 'cls':
                    items += e[1]
                    continue
                c = e[1]
            if self.peek() == '-' and self.i + 1 < len(self.p) and self.p[self.i + 1] != ']':
                self.i += 1
                hi = self.take()
                if hi == '\\':
                    hi = self.escape(True)[1]
                items.append(('r', c, hi))
            else:
                items.append(('c', c))
        return ('cls', items, neg)

    def escape(self, in_class):
        c = self.take()
        if c == '':
            raise error('bad escape (end of pattern)')
        low = c.lower()
        if low in 'dws':
            return ('cls', [(low, c != low)], False)
        if not in_class:
            if c == 'b':
                return ('wordb',)
            if c == 'B':
                return ('nwordb',)
            if c == 'A':
                return ('begin',)
            if c == 'Z':
                return ('end',)
        if c == 'n':
            return ('lit', '\n')
        if c == 't':
            return ('lit', '\t')
        if c == 'r':
            return ('lit', '\r')
        if c == 'f':
            return ('lit', '\f')
        if c == 'v':
            return ('lit', '\v')
        if c == 'x':
            h = self.p[self.i:self.i + 2]
            self.i += 2
            return ('lit', chr(int(h, 16)))
        if c == '0':
            return ('lit', '\0')
        if c.isdigit():
            raise error('backreferences are not supported')
        return ('lit', c)


def _emit(node, prog):
    kind = node[0]
    if kind == 'lit':
        prog.append((_CHAR, node[1], 0))
    elif kind == 'any':
        prog.append((_ANY, 0, 0))
    elif kind == 'cls':
        prog.append((_CLS, node[1], node[2]))
    elif kind == 'bol':
        prog.append((_BOL, 0, 0))
    elif kind == 'eol':
        prog.append((_EOL, 0, 0))
    elif kind == 'wordb':
        prog.append((_WORDB, 0, 0))
    elif kind == 'nwordb':
        prog.append((_NWORDB, 0, 0))
    elif kind == 'begin':
        prog.append((_BEGIN, 0, 0))
    elif kind == 'end':
        prog.append((_END, 0, 0))
    elif kind == 'cat':
        for n in node[1]:
            _emit(n, prog)
    elif kind == 'group':
        prog.append((_SAVE, 2 * node[1], 0))
        _emit(node[2], prog)
        prog.append((_SAVE, 2 * node[1] + 1, 0))
    elif kind == 'look':
        sub = []
        _emit(node[1], sub)
        sub.append((_MATCH, 0, 0))
        prog.append((_LOOK, sub, node[2]))
    elif kind == 'alt':
        jumps = []
        items = node[1]
        for k in range(len(items) - 1):
            split = len(prog)
            prog.append(None)
            _emit(items[k], prog)
            jumps.append(len(prog))
            prog.append(None)
            prog[split] = (_SPLIT, split + 1, len(prog))
        _emit(items[-1], prog)
        for j in jumps:
            prog[j] = (_JMP, len(prog), 0)
    elif kind == 'rep':
        body, lo, hi, greedy = node[1], node[2], node[3], node[4]
        for _ in range(lo):
            _emit(body, prog)
        if hi is None:                          # a loop: L: split body, out
            top = len(prog)
            prog.append(None)
            _emit(body, prog)
            prog.append((_JMP, top, 0))
            out = len(prog)
            prog[top] = (_SPLIT, top + 1, out) if greedy else (_SPLIT, out, top + 1)
        else:
            splits = []
            for _ in range(hi - lo):
                splits.append(len(prog))
                prog.append(None)
                _emit(body, prog)
            out = len(prog)
            for sp in splits:
                prog[sp] = (_SPLIT, sp + 1, out) if greedy else (_SPLIT, out, sp + 1)


def _run(prog, s, start, end, flags, nslots, seen, anchored):
    """Run prog at start (or each position from it, unless anchored) -> slots or None."""
    icase = flags & IGNORECASE
    multi = flags & MULTILINE
    dotall = flags & DOTALL
    width = len(prog) + 1
    pos = start
    while pos <= end:
        slots = [-1] * nslots
        stack = [(0, pos, -1, 0)]
        while stack:
            pc, i, slot, old = stack.pop()
            if slot >= 0:                       # undo a SAVE
                slots[slot] = old
                continue
            while True:
                key = i * width + pc
                if key in seen:
                    break
                seen.add(key)
                op, a, b = prog[pc]
                if op == _CHAR:
                    if i < end and (s[i] == a or icase and s[i].lower() == a.lower()):
                        pc += 1
                        i += 1
                        continue
                    break
                if op == _ANY:
                    if i < end and (dotall or s[i] != '\n'):
                        pc += 1
                        i += 1
                        continue
                    break
                if op == _CLS:
                    if i < end and _in_class(a, s[i], icase) != b:
                        pc += 1
                        i += 1
                        continue
                    break
                if op == _SPLIT:
                    stack.append((b, i, -1, 0))
                    pc = a
                    continue
                if op == _JMP:
                    pc = a
                    continue
                if op == _SAVE:
                    stack.append((0, 0, a, slots[a]))
                    slots[a] = i
                    pc += 1
                    continue
                if op == _MATCH:
                    slots[0] = pos
                    slots[1] = i
                    return slots
                if op == _BOL:
                    if i == 0 or multi and s[i - 1] == '\n':
                        pc += 1
                        continue
                    break
                if op == _EOL:
                    if i == end or i == end - 1 and s[i] == '\n' or multi and s[i] == '\n':
                        pc += 1
                        continue
                    break
                if op == _BEGIN:
                    if i == 0:
                        pc += 1
                        continue
                    break
                if op == _END:
                    if i == end:
                        pc += 1
                        continue
                    break
                if op == _WORDB or op == _NWORDB:
                    w1 = i > 0 and _is_word(s[i - 1])
                    w2 = i < end and _is_word(s[i])
                    if (w1 != w2) == (op == _WORDB):
                        pc += 1
                        continue
                    break
                if op == _LOOK:
                    r = _run(a, s, i, end, flags, 2, set(), True)
                    if (r is None) == b:
                        pc += 1
                        continue
                    break
        if anchored:
            return None
        pos += 1
    return None


class Match:
    def __init__(self, pattern, string, slots, pos, endpos):
        self.re = pattern
        self.string = string
        self._slots = slots
        self.pos = pos
        self.endpos = endpos
        self.lastindex = None
        for n in range(1, pattern.groups + 1):
            if slots[2 * n] >= 0:
                if self.lastindex is None or slots[2 * n] >= slots[2 * self.lastindex]:
                    self.lastindex = n

    def _index(self, g):
        if isinstance(g, str):
            if g not in self.re.groupindex:
                raise IndexError('no such group')
            return self.re.groupindex[g]
        if not 0 <= g <= self.re.groups:
            raise IndexError('no such group')
        return g

    def group(self, *gs):
        if not gs:
            gs = (0,)
        r = []
        for g in gs:
            n = self._index(g)
            a = self._slots[2 * n]
            r.append(None if a < 0 else self.string[a:self._slots[2 * n + 1]])
        return r[0] if len(r) == 1 else tuple(r)

    def __getitem__(self, g):
        return self.group(g)

    def groups(self, default=None):
        return tuple(default if self._slots[2 * n] < 0 else self.group(n)
                     for n in range(1, self.re.groups + 1))

    def groupdict(self, default=None):
        d = {}
        for name in self.re.groupindex:
            v = self.group(name)
            d[name] = default if v is None else v
        return d

    def start(self, g=0):
        return self._slots[2 * self._index(g)]

    def end(self, g=0):
        return self._slots[2 * self._index(g) + 1]

    def span(self, g=0):
        return (self.start(g), self.end(g))

    def expand(self, template):
        return _expand(template, self)

    def __bool__(self):
        return True

    def __repr__(self):
        return '<re.Match object; span=%r, match=%r>' % (self.span(), self.group())


class Pattern:
    def __init__(self, pattern, flags):
        self.pattern = pattern
        self.flags = flags
        p = _Parser(pattern)
        tree = p.alt()
        if p.i < len(pattern):
            raise error('unbalanced parenthesis at position %d' % p.i)
        self.groups = p.ngroups
        self.groupindex = p.names
        self._prog = []
        _emit(tree, self._prog)
        self._prog.append((_MATCH, 0, 0))
        self._nslots = 2 * (p.ngroups + 1)

    def _do(self, string, pos, endpos, anchored, full):
        if endpos is None or endpos > len(string):
            endpos = len(string)
        prog = self._prog
        if full:
            prog = prog[:-1] + [(_END, 0, 0), (_MATCH, 0, 0)]
            if endpos < len(string):
                string = string[:endpos]
        slots = _run(prog, string, pos, endpos, self.flags, self._nslots, set(), anchored)
        return None if slots is None else Match(self, string, slots, pos, endpos)

    def match(self, string, pos=0, endpos=None):
        return self._do(string, pos, endpos, True, False)

    def fullmatch(self, string, pos=0, endpos=None):
        return self._do(string, pos, endpos, True, True)

    def search(self, string, pos=0, endpos=None):
        return self._do(string, pos, endpos, False, False)

    def finditer(self, string, pos=0, endpos=None):
        if endpos is None or endpos > len(string):
            endpos = len(string)
        while pos <= endpos:
            m = self._do(string, pos, endpos, False, False)
            if m is None:
                return
            yield m
            pos = m.end() if m.end() > m.start() else m.end() + 1

    def findall(self, string, pos=0, endpos=None):
        out = []
        for m in self.finditer(string, pos, endpos):
            if self.groups == 0:
                out.append(m.group())
            elif self.groups == 1:
                out.append(m.group(1) or '')
            else:
                out.append(m.groups(''))
        return out

    def subn(self, repl, string, count=0):
        out = []
        last = 0
        n = 0
        for m in self.finditer(string):
            if count and n >= count:
                break
            out.append(string[last:m.start()])
            out.append(repl(m) if callable(repl) else _expand(repl, m))
            last = m.end()
            n += 1
        out.append(string[last:])
        return ''.join(out), n

    def sub(self, repl, string, count=0):
        return self.subn(repl, string, count)[0]

    def split(self, string, maxsplit=0):
        out = []
        last = 0
        n = 0
        for m in self.finditer(string):
            if maxsplit and n >= maxsplit:
                break
            out.append(string[last:m.start()])
            out += list(m.groups())
            last = m.end()
            n += 1
        out.append(string[last:])
        return out

    def __eq__(self, other):
        return isinstance(other, Pattern) and self.pattern == other.pattern and \
            self.flags == other.flags

    def __hash__(self):
        return hash((self.pattern, self.flags))

    def __repr__(self):
        if self.flags:
            return 're.compile(%r, %s)' % (self.pattern, _flag_names(self.flags))
        return 're.compile(%r)' % self.pattern


def _flag_names(flags):
    names = []
    for bit, name in ((IGNORECASE, 're.IGNORECASE'), (MULTILINE, 're.MULTILINE'),
                      (DOTALL, 're.DOTALL'), (ASCII, 're.ASCII')):
        if flags & bit:
            names.append(name)
    return '|'.join(names)


def _expand(template, m):
    """The replacement text: \\1, \\g<1>, \\g<name> and the usual escapes."""
    out = []
    i = 0
    while i < len(template):
        c = template[i]
        i += 1
        if c != '\\' or i >= len(template):
            out.append(c)
            continue
        c = template[i]
        i += 1
        if c.isdigit():
            n = int(c)
            if i < len(template) and template[i].isdigit():
                n = n * 10 + int(template[i])
                i += 1
            out.append(m.group(n) or '')
        elif c == 'g' and i < len(template) and template[i] == '<':
            j = i + template[i:].index('>')
            name = template[i + 1:j]
            i = j + 1
            out.append(m.group(int(name) if name.isdigit() else name) or '')
        elif c == 'n':
            out.append('\n')
        elif c == 't':
            out.append('\t')
        elif c == '\\':
            out.append('\\')
        else:
            out.append('\\' + c)
    return ''.join(out)


_cache = {}


def compile(pattern, flags=0):
    if isinstance(pattern, Pattern):
        return pattern
    key = (pattern, flags)
    p = _cache.get(key)
    if p is None:
        if len(_cache) > 20:
            _cache.clear()
        p = Pattern(pattern, flags)
        _cache[key] = p
    return p


def match(pattern, string, flags=0):
    return compile(pattern, flags).match(string)


def fullmatch(pattern, string, flags=0):
    return compile(pattern, flags).fullmatch(string)


def search(pattern, string, flags=0):
    return compile(pattern, flags).search(string)


def findall(pattern, string, flags=0):
    return compile(pattern, flags).findall(string)


def finditer(pattern, string, flags=0):
    return compile(pattern, flags).finditer(string)


def sub(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags).sub(repl, string, count)


def subn(pattern, repl, string, count=0, flags=0):
    return compile(pattern, flags).subn(repl, string, count)


def split(pattern, string, maxsplit=0, flags=0):
    return compile(pattern, flags).split(string, maxsplit)


_SPECIAL = '()[]{}?*+-|^$\\.&~# \t\n\r\v\f'


def escape(pattern):
    out = []
    for c in pattern:
        if c in _SPECIAL:
            out.append('\\')
        out.append(c)
    return ''.join(out)


def purge():
    _cache.clear()
