# MEGA65 project: standing instructions

This repo was started from `C:\Users\scott\repos\.template`. Read this file first; it answers what the
user would otherwise have to repeat. Deeper notes and recipes are in `docs/MEGA65_NOTES.md`.

## How the user wants MEGA65 projects done

- **Use this build template.** `build.bat` assembles with the bundled `64tass.exe` and writes a D81 with
  the bundled `c1541.exe`. `run.bat` builds and launches Xemu. Keep this structure.
- **Asset strategy: load everything into attic RAM at boot, then DMA it in as needed.**
  - Do all KERNAL disk I/O once, in the untouched BASIC65 state.
  - After that, take over the machine and never call the KERNAL again.
- **Don't build loading/option screens** (crack intros, publisher animations, drive-selection menus)
  unless asked. Skip straight to the game's own title or menu.
- **Keep `README.md` up to date** with what the project is, how to build and run it, controls,
  architecture and known differences. Keep a `TODO.md` for parity or remaining work when it's a port.
- **When porting a C64 game**, the original disks go in `resources/`. Using them is fine.
  - Extract from them at build time (a Python tool under `tools/`) instead of hand-copying data.
  - Ship the original's own graphics and sound wherever possible.
- **Test in Xemu yourself** (headless harness below) and look at the screenshots before reporting.
  Say plainly what was and wasn't tested.
- **Don't use the name of a commercial original if the user says otherwise.** For example, "Mega Dust"
  not "Metal Dust": logos and text in pictures were edited to match.

## Machine and tool locations

| What | Where |
|---|---|
| MEGA65 book (the "Compendium" PDF) | `C:\Users\scott\Downloads\mega65-book.pdf` (1437 pages) |
| Xemu MEGA65 emulator | `C:\Emulation\Mega65\xmega65.exe` |
| VICE 3.9 (GTK3) | `C:\Emulation\Commodore\vice\GTK3VICE-3.9-win64\bin\`, for example `x64sc.exe` (C64) and `xscpu64.exe` (C64 + SuperCPU) |
| VICE ROMs (SuperCPU, JiffyDOS) | `C:\Emulation\Commodore\roms\` (already configured in VICE) |
| Assembler / disk tool | `64tass.exe` (v1.60) and `c1541.exe` in the repo root |
| Python | `python` (3.11, Pillow and pypdf installed) |
| Shells | PowerShell 5.1 is primary (no `&&`). Git Bash is available for POSIX scripts. |

**Searching the book:** extract its text once to a scratch file:

```python
import pypdf
r = pypdf.PdfReader(r"C:\Users\scott\Downloads\mega65-book.pdf")
open("book.txt", "w", encoding="utf-8").write(
    "\n".join("=====PAGE %d\n" % i + (p.extract_text() or "") for i, p in enumerate(r.pages)))
```

Then grep it, for example for `MIXREGSEL`, `CH0CURADDR`, `hyppo_d81attach0` or `ETRIG`.

Useful sections:

| Topic | Location |
|---|---|
| Audio DMA | Appendix P, pp. P-18 to P-23 |
| Audio mixer | Appendix V, pp. V-23 to V-26 |
| Hypervisor (HYPPO) calls | Appendix N |
| Memory map | Chapter 14 |

## Reference repos (`C:\Users\scott\repos\`)

All are 64tass / 45GS02 unless noted. Lift code from them; don't reinvent it.

| Repo | Good for |
|---|---|
| `mega-dust` | Most complete reference. It has: <ul><li>a 4-D81 boot loader with HYPPO auto-mount, loading everything to attic</li><li>a 28-bit `dma_copy_far` that splits at megabyte boundaries</li><li>a double-buffered FCM column-major framebuffer, with fine scroll baked in (320 pixel-column DMAs)</li><li>a DMA sprite blitter with transparency and bounding boxes</li><li>audio-DMA streaming from attic through a ring buffer</li><li>mixer setup, SID sound effects, the HUD, and a menu built from picture patches</li><li>`tools/xemu_run.py`, plus the VICE recording bot in `tools/vice/`</li></ul> |
| `mega-kong` | DMA column blitter with dirty rectangles, raster IRQ without the KERNAL, joystick and keyboard input, audio-DMA samples (`docs/AUDIO_DMA.md` is a good register reference) |
| `little-mega-people` | FCM screen setup, CPU sprite blitter with masks, nibble-swapped palette, attic layout, sample playback |
| `mega-simcity` | Where this template came from. Separate loader PRG with a trampoline, overlays in attic, mouse driver, hardware sprites for pointers, Xemu-vs-hardware sprite-X correction (`$D60F` bit 5). Its `.claude/CLAUDE.md` has the original long gotcha list. |
| `m65-fcm` | Generic `set_screen_mode` (text/FCM/NCM, 40/80 columns), NCM coarse and fine scroll |
| `mega65-rrb-sample` | Minimal RRB (raster rewrite buffer) software sprites with GOTOX |
| `fcmlib` | BASIC65 / CBM prg Studio. Not useful for assembly. |
| `M65_Examples`, `Mega65Tutorials`, `megagfx`, `megapc`, `mega128`, ... | Various experiments; grep them when looking for a specific register use |

## Running the emulators

### Xemu (MEGA65)

- **Interactive:** `xmega65.exe -8 target\game.d81 -autoload`. Add
  `-hdosvirt -hdosdir <dir>` so the program's HYPPO `d81attach` / `loadfile` calls find files in
  `<dir>` (that's how mega-dust auto-mounts disks 2-4).
- **Headless test:** `python tools\xemu_run.py shot.png [actions]` boots the D81 with
  `-headless -sleepless -besure -uartmon :4510 -screenshot shot.png`, then runs these actions:

  | Action | Meaning |
  |---|---|
  | `wait:SECS` | Sleep |
  | `poke:ADDR=B,B` | Write bytes |
  | `peek:ADDR:N` | Print N bytes |
  | `regs` | Print CPU registers |
  | `realtime` | Run at 50 fps (first action only) |
  | `xemu:ARG` | Extra Xemu argument |

  ADDR can be a label from `target/*.lbl`, for example `poke:dbg_joy=10` to inject joystick fire.
  Xemu writes the screenshot on exit. Read it with the Read tool and check it.
- Give the program `dbg_*` bytes for the harness to poke: `dbg_joy` (OR'd into the joystick),
  `dbg_god`, `dbg_level` and so on.
- The uartmon `m` command reads 28-bit addresses: `m ffd3060` for VIC-IV registers, `m 8200000`
  for attic.
- **Measure the frame rate:** run with `realtime` and peek a per-frame counter twice, a few seconds
  apart.

### VICE (C64 / SuperCPU) for studying an original

- Start with a remote monitor, logging output so the bash tool doesn't capture it:

  ```
  x64sc.exe -remotemonitor -remotemonitoraddress ip4://127.0.0.1:6510 -8 disk.d64
  ```

  (use `xscpu64.exe -simmsize 16 -drive8type 1581` for SuperCPU D81 games). `-autostart` is
  unreliable with the SCPU ROM.
- **Typing:** the monitor command `keybuf load"*",8,1\nrun\n` types into the KERNAL buffer. It works
  for BASIC, but a game that scans the CIA matrix ignores it. Send real key presses to the VICE
  window with `tools\vice\hostkey.ps1 -Key " "` instead.
- **Joystick:** turn on keyset joystick through the monitor:

  ```
  resourceset "KeySetEnable" "1"
  resourceset "KeySet1Fire" "122"      (Z)
  resourceset "KeySet1North" "105"     (I)
  resourceset "KeySet1South" "107"     (K)
  resourceset "KeySet1West" "106"      (J)
  resourceset "KeySet1East" "108"      (L)
  resourceset "JoyDevice2" "2"
  ```

  Then send those keys. The numpad joystick and the binary monitor's `joyport set` didn't work.
- **Monitor commands:**

  | Command | Use |
  |---|---|
  | `bank ram` / `bank ram02` | Pick the C64 RAM or a SuperCPU bank |
  | `save "f" 0 0000 ffff` | Dump memory to a file |
  | `io d000` | VIC state: mode, screen, charset, sprites |
  | `screenshot "f.png" 2` | Save a screenshot |
  | `sw` | Cycle stopwatch |
  | `attach "disk2.d81" 8` | Swap disks |
  | `warp on` | Speed up loading |

- **Reconnect to the monitor for every command batch.** A long-lived connection, or a watchpoint,
  crashed VICE.
- `tools\vice\` has `vmon.py`, `snap.py` (screenshot), `mon.py "cmd ;; cmd"` and `hostkey.ps1`.
  `mega-dust\tools\vice\bot.py` shows a bot that plays a game and records its sprite tables.

## MEGA65 gotchas (each of these cost real time)

**CPU and assembler**

- `.cpu "45gs02"` at the top of every file.
- **`STZ` stores the Z register, not zero.** Use `LDA #0 / STA`.
- `inw`/`dew`/`asw` work on the base page only, not absolute addresses.
- 64tass `_local` labels are scoped between global labels. Referencing one across a global label
  gives "not defined symbol". Anonymous `+`/`-` labels resolve to the *next* one, which is easy to
  get wrong in branchy code; prefer named labels.
- 64tass supports `range()`, `.for x in list` and `sin()`. List comprehensions (`[f(x) for x in ...]`)
  aren't supported.

**Boot and KERNAL**

- KERNAL `LOAD` only works in the pristine BASIC65 state. Do it before `sei`, before the 40 MHz
  switch and before any MAP.
- Call `SETBNK` (A = data bank, X = 0) before every `SETLFS`/`SETNAM`/`LOAD`.
- Secondary address 0 loads to X/Y and skips the 2-byte header.
- During boot, use base page `$02`-`$8F` only; the KERNAL owns `$90`-`$FF`.
- `$1600`-`$1EFF` is always free.
- Never load into `$10000`-`$11FFF`.
- c1541 writes lowercase ASCII names as PETSCII *unshifted*. Put names in upper case in the
  asm `.text` (for example `"MDCOMMON"`). Write the game twice, as the first file and as `autoboot.c65`.

**Taking over the machine**

```
sei
lda #65 / sta $00                 ; 40 MHz
VIC-IV unlock: $47, $53 -> $D02F
lda #0 / tax / tay / taz / map / eom
lda #$35 / sta $01
lda #4 / sta $D030                ; RAM palette
txs
tab                               ; base page = $00
$DC02 = $FF, $DC03 = 0            ; re-pin the CIA data directions
```

Then install your own `$FFFE` IRQ.

**DMA (F018B, enhanced)**

- The list is `$0B` (F018B), `$80`/`$81` src/dst MB, options, `$00`, then cmd, count, src (3 bytes),
  dst (3 bytes), sub-command, modulo. Trigger by writing the list MSB to `$D701`, then the LSB to `$D705`.
- **The DMAgic wraps addresses inside a 1 MB megabyte.** A copy that crosses a MB boundary on either
  side silently wraps. Split copies at boundaries; mega-dust's `dma_copy_far` does this. This bug
  corrupted music data.
- Useful options:

  | Option | Effect |
  |---|---|
  | `$83 n` | Source step (whole bytes) |
  | `$85 n` | Destination step |
  | `$07` + `$86 v` | Transparency on, with transparent value v |

  A destination step of 8 writes one FCM pixel column; a destination step of 21 transposes rows
  into column-major sprites.

**Video (VIC-IV)**

- **Full Colour Mode framebuffer:** CHR16 + FCLRHI (`$D054` bits 0 and 2). Give each cell its own
  char (char number = address / 64) and lay the chars out column by column:
  offset = `(x>>3) * rows * 64 + y*8 + (x&7)`.
- Double-buffer by flipping `$D060`-`$D063` in an IRQ below the playfield.
- **Xemu ignores mid-frame `TEXTXPOS`/side-border changes**, so raster splits for scrolling don't
  work there. Bake fine scroll into the framebuffer instead.
- Turn hot registers off (`$D05D` bit 7) so `$D016`-style writes don't undo your layout.
- Palette bytes are nibble-swapped: `$D100`/`$D200`/`$D300` take `(v & 15) << 4 | v >> 4`.
- `TEXTXPOS` and the side border are in H640 units (2 per H320 pixel).
- `$D012` holds raster bits 0-7; bit 8 is `$D011` bit 7.
- Hardware sprite X differs between Xemu and real hardware by about 16 px. See mega-simcity's
  `$D60F` bit 5 check.
- `$D06B` is the 16-colour-sprite enable, not a charset register (some repos mislabel it).

**Audio**

- Audio DMA reads **chip RAM only**: 24-bit addresses, nothing from attic. The end address compares
  only 16 bits, so a sample is at most 64 KB.
- To stream long audio, loop a chip-RAM ring buffer and refill it from attic every frame, using
  `CHxCURADDR` (`$D72A`/`$D72B`) as the read position.
- `$D720` control: `$E2` = enable + loop + unsigned + 8 bit.
- FREQ = rate × 2^24 / 40.5 MHz. For example, 10947 Hz is 4535.
- **Route the mixer, or you hear nothing.**
  - Write `$80` to `$D711` (AUDEN), then set the digital-audio coefficients through
    `$D6F4` (select) / `$D6F5` (data), waiting at least 32 cycles between selects.
  - Register = `output*32 + source*2`. Digital audio L/R are sources 8 and 9. Outputs: 0/1
    speakers, 6/7 headphones.
  - Values that work: `$10,$11,$12,$13,$30,$31,$32,$33,$D0,$D1,$F2,$F3` <- `$FF,$BF,$FF,$3F,$FF,$3F,$FF,$BF,$FF,$BF,$FF,$BF`.
- The CPU must run at 40 MHz and execute memory-reading instructions in its wait loops, because
  audio DMA steals idle cycles.

**Attic RAM and HYPPO**

- Attic RAM is `$8000000`-`$87FFFFF` (8 MB). KERNAL loads land in a chip-RAM staging buffer
  (for example bank 5); DMA them up from there.
- Mount another D81 from the SD card: copy the name into a page-aligned buffer below `$7E00`
  (`$1E00` works), then call `HYPPO_SETNAME` (`$2E` -> `$D640`, `CLV`), then `$40` (d81attach0).
  Carry is set on success. Fall back to "insert disk N, press RETURN".
- To make the ROM area `$20000`-`$3FFFF` writable, call hypervisor trap `$70` (it toggles; test
  before and after).

**Hardware multiplier and divider**

- The multiplier is `$D770` (A) × `$D774` (B) = `$D778` (result, immediate).
- The divider gives `$D768`-`$D76F` as 32.32 fixed point. Wait while `$D70F` bit 7 is set.

## Workflow that worked

1. Study the original (VICE dumps, recordings, screenshots). Write the formats down in
   `docs/FORMATS.md`.
2. Write `tools/extract.py` so it reads `resources/` and emits `target/assets/*` plus `src/gen/*.asm`
   (manifest, tables).
3. Write the boot loader (loads to attic), the takeover, video, blitter, game loop and sound.
4. Build with `build.bat`. Test with `tools/xemu_run.py` screenshots and peeks; measure the frame rate.
5. Save non-obvious discoveries to memory and the README. Leave a `TODO.md`.
