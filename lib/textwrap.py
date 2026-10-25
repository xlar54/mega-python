# textwrap: wrapping and filling text, as Python's textwrap module (handy on the
# 80-column screen)


def wrap(text, width=70, initial_indent='', subsequent_indent='', break_long_words=True):
    """The text's words in lines of at most width characters (a list of strings)."""
    words = text.split()
    lines = []
    cur = []                            # the words of the line being filled
    curlen = 0
    indent = initial_indent
    i = 0
    while i < len(words):
        word = words[i]
        room = width - len(indent)
        sep = 1 if cur else 0
        if curlen + sep + len(word) <= room:
            cur.append(word)
            curlen += sep + len(word)
            i += 1
            continue
        if len(word) > room:            # too long for any line
            if break_long_words:        # (as CPython: fill this line with its start)
                space = room - curlen - sep
                if space > 0:
                    cur.append(word[:space])
                    curlen += sep + space
                    words[i] = word[space:]
            elif not cur:
                cur.append(word)
                i += 1
        lines.append(indent + ' '.join(cur))
        cur = []
        curlen = 0
        indent = subsequent_indent
    if cur:
        lines.append(indent + ' '.join(cur))
    return lines


def fill(text, width=70, initial_indent='', subsequent_indent='', break_long_words=True):
    """wrap()'s lines joined with newlines."""
    return '\n'.join(wrap(text, width, initial_indent, subsequent_indent,
                          break_long_words))


def shorten(text, width, placeholder=' [...]'):
    """The words that fit in width, with the placeholder if some were left out."""
    words = text.split()
    if len(' '.join(words)) <= width:
        return ' '.join(words)
    out = ''
    for word in words:
        candidate = word if not out else out + ' ' + word
        if len(candidate) + len(placeholder) > width:
            break
        out = candidate
    return (out + placeholder) if out else placeholder.lstrip()


def dedent(text):
    """Remove the indentation that every non-blank line has in common."""
    lines = text.split('\n')
    margin = None
    for line in lines:
        if line.strip():
            indent = line[:len(line) - len(line.lstrip())]
            if margin is None:
                margin = indent
            else:
                while not indent.startswith(margin):
                    margin = margin[:-1]
    if not margin:
        return '\n'.join([line if line.strip() else '' for line in lines])
    return '\n'.join([line[len(margin):] if line.strip() else '' for line in lines])


def indent(text, prefix):
    """Put prefix in front of every non-blank line."""
    lines = text.split('\n')
    return '\n'.join([prefix + line if line.strip() else line for line in lines])
