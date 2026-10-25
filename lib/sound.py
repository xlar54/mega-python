# sound: play notes on the MEGA65's SID chips
#
#   from sound import Sound
#   s = Sound()                      # voice 1 of the first SID
#   s.play('C4', 10)                 # a note for 10 frames (1/50 s each)
#   s.tune('C4:8 E4:8 G4:16 R:4')    # notes (or R for a rest) with their lengths
#
# The SIDs are at $D400, $D420, $D440, $D460 (7 registers per voice, 3 voices each);
# peek/poke of bank-0 addresses reach them. Timing uses the VIC's frame counter.

SIDS = [0xD400, 0xD420, 0xD440, 0xD460]
FRAMES = 0xD7FA                 # counts video frames (50 per second on PAL)
CLOCK = 985248                  # the SID clock (PAL)

WAVES = {'triangle': 0x10, 'saw': 0x20, 'pulse': 0x40, 'noise': 0x80}
NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def wait(frames):
    """Wait a number of video frames."""
    start = peek(FRAMES)
    while (peek(FRAMES) - start) & 255 < frames:
        pass


def note_hz(note):
    """'A4' -> 440.0; also 'C#5', 'Eb3'. A number is a MIDI note (69 = A4)."""
    if isinstance(note, int):
        midi = note
    else:
        n = NAMES[note[0].upper()]
        rest = note[1:]
        if rest[0] == '#':
            n += 1
            rest = rest[1:]
        elif rest[0] == 'b':
            n -= 1
            rest = rest[1:]
        midi = 12 * (int(rest) + 1) + n
    return 440.0 * 2 ** ((midi - 69) / 12)


class Sound:
    def __init__(self, voice=1, sid=0):
        self.base = SIDS[sid]
        self.reg = self.base + 7 * (voice - 1)
        self.wave = WAVES['pulse']
        poke(self.base + 24, 15)            # full volume
        self.pulse(0x800)
        self.envelope(0, 9, 0, 0)

    def envelope(self, attack, decay, sustain, release):
        """The ADSR envelope, each 0-15."""
        poke(self.reg + 5, attack * 16 + decay)
        poke(self.reg + 6, sustain * 16 + release)

    def waveform(self, name):
        """'triangle', 'saw', 'pulse' or 'noise'."""
        self.wave = WAVES[name]

    def pulse(self, width):
        """The pulse wave's duty cycle, 0-4095 (2048 = square)."""
        poke(self.reg + 2, width & 255)
        poke(self.reg + 3, width >> 8)

    def freq(self, hz):
        value = int(hz * 16777216 / CLOCK)
        poke(self.reg, value & 255)
        poke(self.reg + 1, value >> 8)

    def on(self, note):
        self.freq(note_hz(note))
        poke(self.reg + 4, self.wave | 1)   # the gate starts the envelope

    def off(self):
        poke(self.reg + 4, self.wave)       # gate off: the release

    def play(self, note, frames):
        """Play a note for a number of frames (a short gap after it)."""
        self.on(note)
        wait(frames - 1)
        self.off()
        wait(1)

    def tune(self, text, speed=1):
        """Play 'C4:8 D4:8 R:4 ...': each note (R = rest) with its length in frames."""
        for item in text.split():
            note, frames = item.split(':')
            frames = int(frames) * speed
            if note == 'R':
                wait(frames)
            else:
                self.play(note, frames)

    def silence(self):
        for r in range(25):
            poke(self.base + r, 0)
