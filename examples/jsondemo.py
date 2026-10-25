# jsondemo: a game save kept as JSON in a file (json.dump / json.load). Each run
# loads the save if there is one, plays a "level" and saves it again.
import json
import os

SAVE = 'save.json'

if os.path.exists(SAVE):
    with open(SAVE) as f:
        game = json.load(f)
    print('loaded', SAVE)
else:
    game = {'player': 'Ada', 'level': 1, 'lives': 3,
            'inventory': ['torch'], 'scores': [], 'options': {'music': True, 'speed': 2}}
    print('a new game')

# play a level
level = game['level']
score = 100 * level + 25 * len(game['inventory'])
game['scores'].append(score)
game['scores'] = sorted(game['scores'], reverse=True)[:5]
game['inventory'].append(['key', 'map', 'rope', 'lamp', 'gem'][level % 5])
game['level'] = level + 1
print('level %d: %d points' % (level, score))

with open(SAVE, 'w') as f:
    json.dump(game, f)

print('the save file:')
print(json.dumps(game, indent=2, sort_keys=True))
print('compact:', len(json.dumps(game, separators=(',', ':'))), 'bytes')

# bad JSON raises ValueError (json.JSONDecodeError)
try:
    json.loads('{"level": 3,}')
except ValueError as e:
    print('bad JSON:', e)
