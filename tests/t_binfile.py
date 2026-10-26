# binary files ('rb', 'wb'): bytes as they are (no CR translation), read back as bytes;
# writes of more than 255 bytes at once
data = bytes(range(256))
with open('bintest', 'wb') as f:
    print(f.write(data))
with open('bintest', 'rb') as f:
    back = f.read()
print(type(back), len(back), back == data, back[13], back[10], back[255])
with open('bintest', 'wb') as f:
    f.write(b'line1\nline2\r\nend')
with open('bintest', 'rb') as f:
    print(f.readline(), f.readline(), f.read())
with open('bintest', 'rb') as f:
    print([line for line in f])
with open('bintest', 'r') as f:
    print(repr(f.read()))
import os
pat = bytes(range(250, 256)) * 50
with open('bt', 'wb') as f:
    f.write(pat[:255])
    f.write(pat[255:])
with open('bt', 'rb') as f:
    back = f.read()
print('two writes, rb:', back == pat, [i for i in range(len(back)) if back[i] != pat[i]][:3])
with open('bt', 'wb') as f:
    f.write(pat)
txt = 'abcdefghij' * 30
with open('bt', 'w') as f:
    f.write(txt)
with open('bt', 'rb') as f:
    back = f.read()
print('text 300, rb:', back == txt.encode())
os.remove('bt')
os.remove('bintest')
