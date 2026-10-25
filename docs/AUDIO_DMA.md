# MEGA65 Audio DMA reference

Taken from the MEGA65 book (`C:\Users\scott\Downloads\mega65-book.pdf`, Dec 2024 build).
Page numbers are the printed numbers in the book. The PDF page is given in brackets where known.

- Audio DMA text: Appendix P, pages **P-18 to P-20** [PDF ~1062-1064]
- DMA/Audio DMA register table: **P-21 to P-23** [PDF ~1063-1065]
- Audio mixer: Appendix V, pages **V-23 to V-26** [PDF ~1173-1176]
- Memory restrictions: **14-10** (memory map chapter) and **J-5**

Lines marked **[UNCONFIRMED]** are not stated in the book. They are inferences or community knowledge and need testing on real hardware or xemu.

---

## 1. Global control: $D711 and its neighbours (P-21, P-23)

| Addr | Bit(s) | Name | Meaning |
|------|--------|------|---------|
| $D711 | 7 | AUDEN | Enables Audio DMA. It also switches the mixer's "digital audio" inputs from $D6F8-$D6FB to the DMA channels. |
| $D711 | 6 | BLKD | Audio DMA blocked (read only, debug) |
| $D711 | 5 | AUDWRBLK | Audio DMA blocks writes (samples are still read) |
| $D711 | 4 | NOMIX | DMA audio bypasses the cross-bar mixer and plays at full volume. When set, SID, FM, mic and other sources are not heard. |
| $D711 | 3 | PWMPDM | PWM/PDM select for the 1-bit audio output on R2/R3 boards. It is listed in the V-26 table. The bit position is read from the table layout **[bit 3 UNCONFIRMED]**. |
| $D711 | 2-0 | AUDBLKTO | Audio DMA block timeout (read only, debug) |
| $D712 | 7..4 | DBGLFTSAT, DBGRGTSAT, DBGPANLFTSAT, DBGPANRGTSAT | Saturation flags (read only, debug) |
| $D712 | ~1 | CHANSWAP | Swaps the channels **[bit position UNCONFIRMED: the PDF table text extracts badly]** |
| $D712 | 0 | SATURATE | Enables saturation instead of wrap-around when channels are summed **[bit 0 likely]** |
| $D713 | 7..4 | IRQCH0FLG..IRQCH3FLG | Per-channel IRQ event flags |
| $D713 | 3..0 | IRQCH0ENA..IRQCH3ENA | Per-channel IRQ enables |
| $D714-$D717 | all | IRQCH0OFFS..IRQCH3OFFS | IRQ address offset (bits 15-8) for channels 0-3 |
| $D71C | all | CH0RVOL | Channel 0 volume on the **right** side |
| $D71D | all | CH1RVOL | Channel 1 volume on the **right** side |
| $D71E | all | CH2LVOL | Channel 2 volume on the **left** side |
| $D71F | all | CH3LVOL | Channel 3 volume on the **left** side |

The book (P-18) says: *"All other bits in $D711 should ordinarily be left clear, i.e., write $80 to $D711 to enable audio DMA."*

There is a contradiction about IRQs. P-20 says *"The audio DMA subsystem cannot presently generate interrupts"*, but the register table lists IRQ flag, enable and offset registers ($D713-$D717). Treat IRQs as **[UNCONFIRMED / maybe newer cores only]** and poll CHxSTP instead.

---

## 2. Per-channel registers (P-18 to P-22)

The four channels start at **$D720, $D730, $D740 and $D750**. Each block is 16 bytes. The offsets below are relative to the channel base, e.g. $D720 for channel 0.

| Off | Ch0 | Name | Meaning |
|-----|-----|------|---------|
| +0 | $D720 | control | See the bit table below |
| +1 | $D721 | BADDR LSB | Base (loop-restart) address, bits 0-7 |
| +2 | $D722 | BADDR MSB | Base address, bits 8-15 |
| +3 | $D723 | BADDR BNK | Base address, bits 16-23 |
| +4 | $D724 | FREQ0 | Frequency step, bits 0-7 |
| +5 | $D725 | FREQ1 | Frequency step, bits 8-15 |
| +6 | $D726 | FREQ2 | Frequency step, bits 16-23 |
| +7 | $D727 | TADDR LSB | Top (end) address, bits 0-7 |
| +8 | $D728 | TADDR MSB | Top (end) address, bits 8-15. **Only 16 bits are compared.** |
| +9 | $D729 | VOLUME | Volume on the channel's own side. $FF is full, $00 is mute. |
| +A | $D72A | CURADDR LSB | Current address, bits 0-7. P-18 calls this "the start address" you write. |
| +B | $D72B | CURADDR MSB | Current address, bits 8-15 |
| +C | $D72C | CURADDR BNK | Current address, bits 16-23 |
| +D | $D72D | TMGCNT0 | Timing counter (the 24-bit accumulator), bits 0-7 |
| +E | $D72E | TMGCNT1 | Timing counter, bits 8-15 |
| +F | $D72F | TMGCNT2 | Timing counter, bits 16-23 |

### Control byte (+0, $D720/$D730/$D740/$D750)

| Bit | Name | Meaning |
|-----|------|---------|
| 7 | CHxEN | Enables the channel. Set it to start playback; clear it to stop. |
| 6 | CHxLOOP | Loop. At the end, playback restarts from BADDR. |
| 5 | CHxSGN / CHxUSGN | Sample sign: **0 = signed, 1 = unsigned** (P-23). The register is labelled "SGN" in the table, but the description is "USGN 0=signed 1=unsigned". |
| 4 | CHxSINE | Plays a built-in 32-sample 16-bit sine wave instead of memory. The address registers still have to be set as if the table sat in the bottom 64 bytes of memory (P-19). |
| 3 | CHxSTP | Stop flag. The hardware sets it when the sample finishes (P-20). |
| 2 | - | Unused |
| 1-0 | CHxSBITS | Sample width: `11` = 16-bit, `10` = 8-bit, `01` = upper nybble, `00` = lower nybble |

Common control values:
- **$A2**: 8-bit signed, one-shot.
- **$E2**: 8-bit signed, looping.
- **$A3**: 16-bit signed, one-shot.
- Add $20 for unsigned data, e.g. **$82** for 8-bit unsigned one-shot.

### Addresses
- The start, base and current addresses are **24-bit** ($00.0000-$FF.FFFF), not 28-bit.
- P-18 says: write the start address into **$D72A-$D72C**, which is the current address. Write the end address into **$D727-$D728**. If the sample loops, put the loop-start address into **$D721-$D723** and set CHxLOOP.
- End detection compares **only the low 16 bits** of the current address with TADDR. Samples therefore cannot be longer than 64 KB (P-18).
- It is not documented whether TADDR is **inclusive or exclusive** **[UNCONFIRMED]**. To be safe, set TADDR to `(start+length) & $FFFF`. At worst this plays one extra sample.
- Because only the low 16 bits are compared, a sample shorter than 64 KB should be able to cross a 64 KB boundary **[inference, UNCONFIRMED]**.
- The current address is **not latched** when read back. Stop the channel (clear CHxEN) before you read it (P-19).
- For 16-bit samples the address should step by 2 per sample, little-endian **[UNCONFIRMED]**.
- Safest practice is to write the start address to both BADDR (+1..+3) and CURADDR (+A..+C) **[practice, not stated in book]**.

### Frequency / sample rate (P-19)
The channel has a 24-bit accumulator. On every CPU cycle (about 40.5 MHz) the 24-bit FREQ value is added to it. Each overflow fetches the next sample.

```
sample_rate_Hz = FREQ * 40.5 MHz / 2^24
FREQ           = round(sample_rate_Hz * 16777216 / 40500000)
               ~= sample_rate_Hz * 0.414252
```
The book states that $FFFFFF gives almost 40.5 MHz and that the minimum is 40.5 MHz / 2^24, about 2.4 Hz.

| Rate | FREQ (dec) | FREQ2 FREQ1 FREQ0 |
|------|-----------:|------------------|
| 4000 Hz | 1657 | $00 $06 $79 |
| 8000 Hz | 3314 | $00 $0C $F2 |
| 11025 Hz | 4567 | $00 $11 $D7 |
| 16000 Hz | 6628 | $00 $19 $E4 |
| 22050 Hz | 9134 | $00 $23 $AE |
| 44100 Hz | 18269 | $00 $47 $5D |

You can change frequency and volume while a sample is playing (P-19).

### Volume and panning (P-19)
- Channels 0 and 1 feed the **left** DMA output. Channels 2 and 3 feed the **right** DMA output (P-18).
- +9 (`$D729` etc.) sets the volume on the channel's own side.
- $D71C-$D71F set the volume on the **opposite** side, which allows panning.
- To play channel 0 at full volume on both sides, write `$D729=$FF` and `$D71C=$FF`.
- When channels are summed, enabling SATURATE ($D712) gives clipping instead of wrap-around.

---

## 3. Where sample data may live (P-18, 14-10, J-5)

- Samples must be in **chip RAM**: 384 KB at **$000.0000-$005.FFFF** (14-10). The address registers are 24-bit, but only chip RAM is valid.
- **Attic RAM / HyperRAM ($800.0000+) cannot be used for audio DMA** (14-10 and J-5). DMA the samples into chip RAM first.
- Avoid areas used by the KERNAL, BASIC or DOS, or take over the whole machine (14-11, 14-12).
- The data format is **not limited to signed 8-bit**. Signed or unsigned is chosen per channel (bit 5), and the width can be 4, 8 or 16 bit (bits 1-0). Raw unsigned 8-bit WAV data can be played as-is with bit 5 set.

---

## 4. Mixer routing (V-23 to V-26, P-18)

- **$D6F4 MIXREGSEL** selects a coefficient byte (0-255). **$D6F5 MIXREGDATA** reads or writes it. The book calls $D6F5 a "read port", but the mixer section describes modifying coefficients through it.
- There are 128 coefficients of 16 bits each, stored LSB first.
- Register number = `output*32 + source*2` for the LSB; the MSB is the next register.
- Mixer inputs **$8 and $9 ("Digital audio Left/Right")** carry the DMA audio when AUDEN=1, and the $D6F8-$D6FB registers when AUDEN=0 (P-18).
- **Source $F's coefficient is the master volume for each output** (V-24).
- Outputs:
  - 0 = left primary speaker (HDMI/digital on R2/R3)
  - 1 = right primary speaker
  - 6 = headphone left
  - 7 = headphone right
  - 2-5 are MEGAphone only
- Wait at least **32 cycles** before selecting a different coefficient, or the write may be lost (V-23/V-24).

The coefficient registers for digital audio:

| Purpose | Output | Coefficient regs (LSB/MSB) |
|---|---|---|
| Digi L to left speaker | 0 | $10/$11 |
| Digi R to right speaker | 1 | $32/$33 |
| Master volume, left speaker | 0 | $1E/$1F |
| Master volume, right speaker | 1 | $3E/$3F |
| Digi L to headphone L | 6 | $D0/$D1 |
| Digi R to headphone R | 7 | $F2/$F3 |
| Master volume, headphone L/R | 6/7 | $DE/$DF, $FE/$FF |

To also hear digi L on the right side, use $30/$31; for digi R on the left, use $12/$13.

**Default state after boot is not documented [UNCONFIRMED].**
- The book (4-6) says only that the Freezer's audio mixer has defaults that "pan the four SID chips slightly to the left and right".
- It says nothing about the digital inputs.
- To guarantee the DMA is audible, either:
  - write $90 to $D711 (AUDEN+NOMIX). This bypasses the mixer, and all other sound is muted. Or:
  - write the digital-input and master coefficients above, e.g. $FF/$FF, yourself.

---

## 5. Example code and gotchas

The book has **no complete audio DMA example program**. The only code fragment is the idle loop below (P-18). The routine after it is assembled from the register descriptions.

```asm
; ---- play a one-shot 8-bit signed sample on channel 0, both sides ----
; SAMPLE = 24-bit chip-RAM address, SAMPLE_LEN < 65536
        lda #$00
        sta $d720          ; stop channel 0 first (also makes CURADDR safe to write)

        lda #<SAMPLE       ; base/loop address
        sta $d721
        lda #>SAMPLE
        sta $d722
        lda #^SAMPLE       ; bits 16-23
        sta $d723

        lda #<SAMPLE       ; current ("start") address
        sta $d72a
        lda #>SAMPLE
        sta $d72b
        lda #^SAMPLE
        sta $d72c

        lda #<(SAMPLE+SAMPLE_LEN)   ; end, low 16 bits only
        sta $d727
        lda #>(SAMPLE+SAMPLE_LEN)
        sta $d728

        lda #$d7           ; 11025 Hz -> $0011D7
        sta $d724
        lda #$11
        sta $d725
        lda #$00
        sta $d726

        lda #$ff
        sta $d729          ; ch0 left volume
        sta $d71c          ; ch0 right volume

        lda #$80
        sta $d711          ; AUDEN (use $90 to bypass mixer)

        lda #$a2           ; EN | signed | 8-bit, no loop
        sta $d720          ; start -- write control LAST
; done when ($d720 & $08) != 0  (CH0STP)
```

**Gotchas**
1. **The CPU must run at full speed (about 40 MHz).** Audio DMA uses idle CPU cycles, i.e. the wait-state on every memory operand read. A tight loop with no memory read (e.g. `loop: JMP loop`) starves it. Put an `LDA abs` in such loops (P-18):
   ```asm
   loop: LDA $1234   ; gives audio DMA an idle cycle
         JMP loop
   ```
2. Audio DMA keeps running and steals cycles even during other DMA jobs. This is stated on P-4.
3. Rates above a few MHz are impossible. Even below that, uneven idle cycles can cause distortion. At rates under 16 kHz with 8-bit samples the effect is negligible (P-19).
4. Only 16 bits of the end address are compared, so samples are limited to 64 KB. Whether the end address is inclusive or exclusive is undocumented.
5. Current-address reads are not latched. Stop the channel before reading it.
6. Write the control byte (EN) last, after the addresses and frequency. This order is **[best practice, not stated in book]**.
7. Writing AUDEN takes over mixer inputs 8/9 from the $D6F8-$D6FB direct digi registers. You can't use both at once.
8. Clear the channel's EN bit before re-triggering. Whether the STP flag must be cleared by hand before EN is set again is **[UNCONFIRMED]**. Writing $00 then the control value should cover it.
