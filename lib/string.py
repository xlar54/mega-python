# string: character sets and capwords(), as Python's string module

ascii_lowercase = 'abcdefghijklmnopqrstuvwxyz'
ascii_uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
ascii_letters = ascii_lowercase + ascii_uppercase
digits = '0123456789'
hexdigits = '0123456789abcdefABCDEF'
octdigits = '01234567'
punctuation = '!"#$%&' + "'" + '()*+,-./:;<=>?@[\\]^_`{|}~'
whitespace = ' \t\n\r' + chr(11) + chr(12)
printable = digits + ascii_letters + punctuation + whitespace


def capwords(s, sep=None):
    """Split s into words, capitalize each, and join them (with sep, else a space)."""
    words = [w.capitalize() for w in s.split(sep)]
    return (sep if sep is not None else ' ').join(words)
