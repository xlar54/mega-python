# json: dumps / loads (lib/json.py on the MEGA65)
import json

data = {'name': 'Ada', 'age': 36, 'ratio': 0.5, 'ok': True, 'none': None,
        'tags': ['math', 'engines'], 'nested': {'a': [1, 2, {'b': False}]}, 'empty': []}
text = json.dumps(data)
print(text)
print(json.loads(text) == data)
print(json.dumps(data, sort_keys=True))
print(json.dumps([1, 'two', 3.25, None], indent=2))
print(json.dumps({'k': [1, 2], 'e': {}}, indent=4, sort_keys=True))
print(json.dumps('tab\tquote"back\slash\nend'))
print(json.dumps((1, 2)), json.dumps(1e20), json.dumps(-0.0), json.dumps({1: 'one', 2.5: 'x'}))
print(json.dumps([1, 2], separators=(',', ':')))
print(json.loads('  [1, -2.5e3, "a\\u0041\\n", true, false, null, {"x": {}}]  '))
print(json.loads('{"a": 1, "b": [ ], "c": "\\"q\\""}'))
for bad in ['[1, 2', '{"a" 1}', 'nope', '[1] x', '{a: 1}']:
    try:
        json.loads(bad)
    except ValueError:
        print('bad:', bad)
try:
    json.dumps({'x': object()})
except TypeError:
    print('TypeError')
with open('tjson', 'w') as f:
    json.dump({'scores': [10, 20]}, f)
with open('tjson') as f:
    print(json.load(f))
