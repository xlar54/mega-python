# bytes: literals, indexing and iteration as ints, slicing, +, *, ==, repr, bytes(), encode/
# decode, hex, str methods giving bytes, dict keys
b = b'Hello\n'
print(b, type(b), len(b), b[0], b[-2], b[1:3], list(b[:3]))
print(b == b'Hello\n', b == 'Hello\n', b != 'x', b'a' < b'b', isinstance(b, bytes), isinstance(b, str))
print(b + b'!', b'ab' * 3, b'' * 2, b'x' in b'xyz', bytes(), bytes(3), bytes([65, 66, 67]))
print('caf'.encode(), b'abc'.decode(), 'x'.encode('ascii'), bytes('hi', 'utf-8'), bytes(b'z'))
print(b.upper(), b.strip(), b'a,b,c'.split(b','), b'-'.join([b'x', b'y']), b.replace(b'l', b'L'))
print(b.startswith(b'He'), b.find(b'l'), b.count(b'l'), b'AbC'.lower(), b'a b'.partition(b' '))
print(b'\x00\x01\xff\t\'"', b"it's", b'\\', repr(b'\x7f'), str(b'q'), f'{b"f"}')
print(b'\xde\xad'.hex(), [x for x in b'hi'], sum(b'\x01\x02'), max(b'abc'), sorted(b'cab'))
print({b'k': 1}[b'k'], {b'k', 'k'} == {'k', b'k'}, len({b'k', 'k'}), hash(b'k') == hash(b'k'))
try:
    b'a' + 'b'
except TypeError as e:
    print('TypeError', e)
try:
    bytes([256])
except ValueError as e:
    print('ValueError', e)
try:
    bytes('x')
except TypeError as e:
    print('TypeError', e)
cat = b'ab' b'cd'
print(cat, type(cat), cat == b'abcd')
