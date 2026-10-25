# json: JSON text <-> Python values, as Python's json module
#
#   import json
#   text = json.dumps({'name': 'ada', 'scores': [3, 1.5, None]})
#   data = json.loads(text)
#   with open('save', 'w') as f: json.dump(data, f)
#   with open('save') as f: data = json.load(f)
#
# dicts <-> objects, lists and tuples -> arrays, str, int, float, True/False/None
# <-> true/false/null. Text is ASCII (other characters come out as \u escapes).


class JSONDecodeError(ValueError):
    pass


_ESC = {'"': '\\"', '\\': '\\\\', '\n': '\\n', '\r': '\\r', '\t': '\\t',
        chr(8): '\\b', chr(12): '\\f'}
_HEX = '0123456789abcdef'


def _str(s):
    out = '"'
    for ch in s:
        if ch in _ESC:
            out += _ESC[ch]
        elif ord(ch) < 32 or ord(ch) > 126:
            c = ord(ch)
            out += '\\u00' + _HEX[c >> 4] + _HEX[c & 15]
        else:
            out += ch
    return out + '"'


def _dump(obj, indent, level, item_sep, key_sep, sort_keys):
    if obj is None:
        return 'null'
    if obj is True:
        return 'true'
    if obj is False:
        return 'false'
    if isinstance(obj, str):
        return _str(obj)
    if isinstance(obj, int):
        return str(obj)
    if isinstance(obj, float):
        if obj != obj:
            return 'NaN'
        if obj == float('inf'):
            return 'Infinity'
        if obj == -float('inf'):
            return '-Infinity'
        return repr(obj)
    if indent is None:
        nl = ''
        inner = ''
        outer = ''
    else:
        nl = '\n'
        inner = ' ' * (indent * (level + 1))
        outer = ' ' * (indent * level)
    if isinstance(obj, (list, tuple)):
        if not obj:
            return '[]'
        parts = [inner + _dump(x, indent, level + 1, item_sep, key_sep, sort_keys)
                 for x in obj]
        return '[' + nl + (item_sep + nl).join(parts) + nl + outer + ']'
    if isinstance(obj, dict):
        if not obj:
            return '{}'
        keys = list(obj.keys())
        if sort_keys:
            keys = sorted(keys)
        parts = []
        for k in keys:
            if isinstance(k, str):
                ks = _str(k)
            elif k is None:
                ks = '"null"'
            elif k is True or k is False:
                ks = '"true"' if k else '"false"'
            elif isinstance(k, (int, float)):
                ks = '"' + _dump(k, None, 0, item_sep, key_sep, sort_keys) + '"'
            else:
                raise TypeError('keys must be str, int, float, bool or None')
            parts.append(inner + ks + key_sep +
                         _dump(obj[k], indent, level + 1, item_sep, key_sep, sort_keys))
        return '{' + nl + (item_sep + nl).join(parts) + nl + outer + '}'
    raise TypeError('Object of type %s is not JSON serializable' % type(obj).__name__)


def dumps(obj, indent=None, separators=None, sort_keys=False):
    """obj as JSON text."""
    if separators is not None:
        item_sep, key_sep = separators
    elif indent is None:
        item_sep, key_sep = ', ', ': '
    else:
        item_sep, key_sep = ',', ': '
    if isinstance(indent, str):
        indent = len(indent)
    return _dump(obj, indent, 0, item_sep, key_sep, sort_keys)


def dump(obj, fp, indent=None, separators=None, sort_keys=False):
    fp.write(dumps(obj, indent, separators, sort_keys))


class _Parser:
    def __init__(self, s):
        self.s = s
        self.i = 0

    def error(self, what):
        raise JSONDecodeError('%s: char %d' % (what, self.i))

    def ws(self):
        s = self.s
        while self.i < len(s) and s[self.i] in ' \t\n\r':
            self.i += 1

    def value(self):
        self.ws()
        s = self.s
        if self.i >= len(s):
            self.error('Expecting value')
        c = s[self.i]
        if c == '{':
            return self.obj()
        if c == '[':
            return self.arr()
        if c == '"':
            return self.string()
        for word, v in (('true', True), ('false', False), ('null', None),
                        ('NaN', float('nan')), ('Infinity', float('inf')),
                        ('-Infinity', -float('inf'))):
            if s[self.i:self.i + len(word)] == word:
                self.i += len(word)
                return v
        return self.number()

    def number(self):
        s = self.s
        start = self.i
        while self.i < len(s) and s[self.i] in '+-0123456789.eE':
            self.i += 1
        text = s[start:self.i]
        if not text:
            self.error('Expecting value')
        if '.' in text or 'e' in text or 'E' in text:
            return float(text)
        return int(text)

    def string(self):
        s = self.s
        self.i += 1
        out = ''
        while True:
            if self.i >= len(s):
                self.error('Unterminated string')
            c = s[self.i]
            self.i += 1
            if c == '"':
                return out
            if c != '\\':
                out += c
                continue
            e = s[self.i]
            self.i += 1
            if e == 'u':
                out += chr(int(s[self.i:self.i + 4], 16))
                self.i += 4
            else:
                out += {'"': '"', '\\': '\\', '/': '/', 'b': chr(8), 'f': chr(12),
                        'n': '\n', 'r': '\r', 't': '\t'}[e]

    def arr(self):
        self.i += 1
        out = []
        self.ws()
        if self.s[self.i] == ']':
            self.i += 1
            return out
        while True:
            out.append(self.value())
            self.ws()
            c = self.s[self.i] if self.i < len(self.s) else ''
            self.i += 1
            if c == ']':
                return out
            if c != ',':
                self.error("Expecting ',' delimiter")

    def obj(self):
        self.i += 1
        out = {}
        self.ws()
        if self.s[self.i] == '}':
            self.i += 1
            return out
        while True:
            self.ws()
            if self.i >= len(self.s) or self.s[self.i] != '"':
                self.error('Expecting property name enclosed in double quotes')
            k = self.string()
            self.ws()
            if self.i >= len(self.s) or self.s[self.i] != ':':
                self.error("Expecting ':' delimiter")
            self.i += 1
            out[k] = self.value()
            self.ws()
            c = self.s[self.i] if self.i < len(self.s) else ''
            self.i += 1
            if c == '}':
                return out
            if c != ',':
                self.error("Expecting ',' delimiter")


def loads(s):
    """JSON text -> the Python value."""
    p = _Parser(s)
    v = p.value()
    p.ws()
    if p.i != len(s):
        p.error('Extra data')
    return v


def load(fp):
    return loads(fp.read())
