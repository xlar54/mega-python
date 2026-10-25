# tune: plays "Ode to Joy" with the Sound class from lib/sound.py (MEGA65 only: it
# pokes the SID chip)
from sound import Sound, note_hz

ODE = '''E4:12 E4:12 F4:12 G4:12  G4:12 F4:12 E4:12 D4:12
         C4:12 C4:12 D4:12 E4:12  E4:18 D4:6 D4:24
         E4:12 E4:12 F4:12 G4:12  G4:12 F4:12 E4:12 D4:12
         C4:12 C4:12 D4:12 E4:12  D4:18 C4:6 C4:24'''

s = Sound()
s.waveform('pulse')
s.envelope(1, 8, 10, 4)

print('Ode to Joy - Beethoven')
print('A4 is %.1f Hz, middle C %.2f Hz' % (note_hz('A4'), note_hz('C4')))
lines = ODE.split('\n')
for n, line in enumerate(lines):
    print('phrase', n + 1, ':', ' '.join(item.split(':')[0] for item in line.split()))
    s.tune(line)

s.waveform('triangle')                  # a closing arpeggio, faster
for note in ['C4', 'E4', 'G4', 'C5', 'G4', 'E4', 'C4']:
    s.play(note, 6)
s.silence()
print('done')
