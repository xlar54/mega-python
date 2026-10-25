Boot environment & KERNAL/HYPPO I/O — the biggest one
	• KERNAL/HYPPO LOAD only works in the pristine BASIC65 boot environment. Run all your disk I/O at the very start of main_entry, BEFORE: sei, before lda #65; sta $00 (40 MHz), before any custom MAP. Once you've left that state, KERNAL LOAD is hostile to reproduce in-game.
	• Architect for "load once at boot, then never touch KERNAL again." Stage every PRG you'll ever need into Attic RAM via a boot_load_overlays-style routine; from then on it's pure DMA. Anything that needs in-game KERNAL I/O (commander save/load) needs a separate low-memory trampoline that reconstructs the boot environment — that's a project on its own.
	• Always call KERNAL_SETBNK (A=bank, X=0) before every SETLFS/SETNAM/LOAD/SAVE. Without it KERNAL writes go to whatever bank the previous SETBNK left configured. This bug ate days here.
	• The 2-byte PRG header is part of the load. KERNAL writes $xx $xx <body> to your target. If your target is $07FE, the body lands at $0800. Don't skip planning for those two bytes.
	• Don't let any PRG body land in the C65/MEGA65-reserved physical range $10000-$11FFF (bank 1 $0000-$1FFF). Load high into bank 1 and DMA-copy down, skipping the 2-byte header.
	• For in-game KERNAL I/O, the trampoline MUST execute below $2000 (so it isn't unmapped when you install the boot-style MAP). Keep it tiny.
	• Capture the real boot $01 and $D030 at entry — don't hardcode them. Whatever your in-game KERNAL trampoline restores must equal what worked at boot. Hardcoded constants are a latent landmine when cores/ROMs change.
	• Bound any retry loop on boot LOAD failures. Infinite retry trades a visible glitch for a silent hang. Three attempts then fall through to a clearly-displayed error.
MAP register — write this in a comment, day one
	• MAP instruction operand layout: A = MAPLO offset low byte; X = high nibble is block-enable mask for the four 8 KB blocks $0000/$2000/$4000/$6000, low nibble is MAPLO offset high; Y/Z are the same for MAPHI's $8000/$A000/$C000/$E000. Offset is in 256-byte pages. Forget this and every map routine becomes magic numbers.
	• Always end with eom (NOP+EOM pair). A bare MAP with no EOM leaves the CPU in a weird transitional state.
	• Don't sei/map in code that's mapped out by the new map — write your map-install routines to live in always-resident bank-0 RAM that survives the change.
DMA / Attic overlay architecture
	• Use Attic RAM (megabytes $80+) as your code library. Load overlays into Attic slots at boot, DMA them into a fixed CPU window when needed. ~4 KB DMA at 40 MHz is microseconds. This is the right pattern for any non-trivial MEGA65 game.
	• Document your F018B inline DMA list byte format at the top of your DMA helpers. The $80 src_mb / $81 dst_mb / $00 terminator / job_bytes ordering is not memorable. One worked example with field names saves hours.
	• DMA is MAP-state-independent. Once everything is in Attic, the rest of the game can do whatever it wants with the CPU MAP. This is what makes the overlay pattern liberating.
Speed / CIA / VIC quirks
	• The 40 MHz switch (lda #65; sta $00) can shift CIA port directions. After switching, re-pin $DC02 = $FF (PRA out) and $DC03 = $00 (PRB in) before scanning the keyboard. Otherwise the matrix returns the last row written.
	• 40 MHz is fine for KERNAL LOAD/SAVE (we proved this). Speed is rarely the disk-I/O culprit — environment is.
	• VIC raster $D012 is only the low 8 bits; bit 8 is in $D011. Fine for coarse frame delays, wrong for exact line waits.
Boot-sequence order — comment why each step is where it is
Working order (steal this):
cld
cli                          ; pristine IRQ state for boot LOADs
(capture $01/$D030)
(short raster settle: cold autoload races the drive)
jsr boot_load_overlays       ; KERNAL I/O happens here, nowhere else
sei
lda #65 / sta $00            ; 40 MHz native
jsr setup_runtime_map        ; custom MAP for the game
(re-pin CIA DDRs)            ; the 40 MHz switch may have nudged them
(screen mode + IRQ install)
Every reordering of this sequence I've seen broke something.
Build & toolchain
	• .cpu "45gs02" at the top of every .asm file or you don't get map/eom/bra/ldz/Q-reg ops.
	• Assert your address budget with .cerror * > $XXXX at the end of each section. Discovering an overlay grew past its window at runtime is miserable; at assemble time it's free.
	• Lay out memory in a single document (TODO.md works) and update it any time you move a region. $0800 stage, $1000-$13FF LOWFILE, $1400-$1FFF LOWGFX, $2000-$AFFF resident, $B000-$BFFF overlay window — that map IS your project.
Xemu vs real hardware — the discipline
	• Xemu lies about disk I/O. Code that does KERNAL LOAD from a custom MAP works in Xemu and hangs HYPPO on real hardware. Test disk I/O on real HW before declaring it done. Every time.
	• Xemu also lies more subtly about timing, IRQ races on cold autoload, and a few CIA edge cases. When something works in Xemu but breaks on metal, suspect environment (map/$01/$D030/IRQ state) before suspecting your code logic.
	• Keep the real-hardware monitor in your workflow. m, d <addr>, r (registers + MAP). On a wedge: capture PC, A/X/Y/Z, MAPHI/MAPLO, and a memory dump of the buffer that should have been written. That diagnostic kit found the SETBNK bug.
Things I wish were in this repo's README on day one
	• A page that lists every register-poking convention the project relies on (which addresses are "ours," which belong to KERNAL, which to HYPPO).
	• A "if you're about to call KERNAL from in-game, read this first" doc — that's where the trampoline rules go.
	• A "known-working baseline" tag in git you can always diff against when something breaks on real HW.
	• A short script that builds + uploads to a real MEGA65 via the freezer/SD path so the real-HW test loop is one command.


Overview
The MAP register is the C65 (and inherently *a* Mega65) way of making memory locations available for the CPU in 16-bit address space (0 - 65535).  It's called a register, but it's actually a procedure (you aren't writing data to a register in the classic sense).
There are two "modes" to perform the mapping - 4510 mode and 45GS02 mode:

4510 Mapping Mode
In 4510 mode (Commodore 65 mode), you can map anywhere up to 1MB ($0-$FFF00) into the standard 64kb space.  To do so, you write specific values to A, X, Y, and Z, then the MAP opcode, and then EOM (end of map):
LDA #$52
LDX #$24
LDY #$00
LDZ #$B3
MAP            ; immediately change memory map, freeze interrupts
EOM            ; release interrupt freeze
The specific values to be written will be explained further down, but the above is the procedure for changing the mapping.  Obviously changing memory mappings could crash the machine if interrupts were enabled, so MAP immediately freezes them during the remapping.  The I process flag is not affected, as the interrupt "freeze" is internal to the MAP operation.  The EOM is a separate instruction to "unfreeze" the interrupt state, so you can perform additional steps before the interrupt state is reverted.  EOM also does not change the I flag, so if interrupts were disabled by SEI, EOM will not re-enable them.  For this reason, I prefer the term "freeze" over disable/enable.

45GS02 Mapping Mode
In 45GS02 mode (Mega65 mode), you would call MAP twice, to provide for larger offsets (offsets explained below in Attic RAM).   This provides a full 16MB reach to be mapped into 8k blocks. 

So What About A,X,Y,Z?
You might think you can just say "hey CPU, make $2000-$3FFF point to $40000-$43FFF".   And yes, you can.  But the mechanism allows you to map multiple 8k blocks all in one MAP operation (so naturally it will be a little more confusing).   The A/X pair represent MAPLO and Y/Z pair represent MAPHI, as well as their offset bytes.


-	bit 7	bit 6	bit 5	bit 4	Example
MAPLO	$6000-$7FFF	$4000-$5FFF	$2000-$3FFF	$0000-$1FFF	
 x upper	0	0	1	0	= $2
MAPHI	$E000-$FFFF	$C000-$DFFF	$A000-$BFFF	$8000-$9FFF	
 z upper	1	0	1	1	= $B
Looking at the table above:

LDA #$52
LDX #$24   ;  the $2 is represented above, mapping only $2000-$3FFF
LDY #$00
LDZ #$B3   ; the $B indicated $E000-$FFFF, $A000-$BFFF, and $8000-$8FFF are mapped
But Mapped To Where?
Mapping is based on an offset, demonstrated below, in 256 byte blocks.
The remaining values for A/X are the offset for MAPLO:
LDA #$52
LDX #$24   ;  putting these values together make $452 x 256 = $45200
Therefore, after the mapping, if I write a value to $2000, it will actually be written to $45200.  $2001 -> $45201, etc.  
The same is true for Y/Z and MAPHI:
LDY #$00
LDZ #$B3   ; putting these values together make $300 x 256 = $30000
Note that $30000 becomes the offset for all three blocks selected for mapping in MAPHI.  Offsets are only unique between MAPLO and MAPHI.

Unmapped Banks
This MAP-ping operation is master of all, when it comes to memory layout...but it isn't the only mechanism.  To remain compatibility with the C64, other locations affect memory layout as well.
If a region is "unmapped," it falls through to the first 64K of addresses, as interpreted by the legacy banking mechanisms. This may be bank 0 RAM, C64 ROM, I/O registers, or cartridge lines, depending on $00/$01 and $D030.  
$01 and $D030 settings only apply to unmapped regions. In the KERNAL's desired state, they are only used for C000-CFFF and D000-DFFF.

Side note:  DLOAD'ing a PRG writes directly to the underlying bank 0 RAM starting at $2001, and can load a contiguous PRG up to $F6FF.


Unmapped Banks Are Not Zero-Offset Mapped Banks
It is possible to "map" an 8K region with an address offset of 0, such as:

LDA #$00
LDX #$40    ; $000 x 256 = $0000 offset

In this case, the physical 28-bit address is just the 16-bit address with upper bits set to 0. It always refers to RAM, ignoring the legacy banking mechanisms. It even ignores the CPU registers $00/$01 themselves, so you can access RAM at those addresses (something difficult, if not impossible to do on a standard C64).

The Default Mapping
At startup, the default map can be seen in the matrix monitor, although it is broken out by 4k blocks instead of 8:

0000-0FFF is unmapped, 1000-1FFF is also unmapped, resulting in bit 4 of MAPLO being off.
2000-2FFF is mapped and 3000-3FFF are mapped,  resulting in bit 5 of MAPLO being on.
4000-4FFF is mapped and 5000-5FFF are mapped,  resulting in bit 6 of MAPLO being on.
etc
Or:

-	bit 7	bit 6	bit 5	bit 4	Example
MAPLO	$6000-$7FFF	$4000-$5FFF	$2000-$3FFF	$0000-$1FFF	
 x upper	1	1	1	0	= $E
MAPHI	$E000-$FFFF	$C000-$DFFF	$A000-$BFFF	$8000-$9FFF	
 z upper	1	0	1	1	= $B
For the selected blocks, the offset for both MAPLO and MAPHI is obviously $30000, so the default mapping would be:

LDA #$00
LDX #$E3
LDY #$00
LDZ #$B3
MAP            ; immediately change memory map, freeze interrupts
EOM            ; release interrupt freeze
This configuration points the proper memory locations for access to the MEGA65 BASIC and KERNAL.
BUT....running the code above wont put things back as you'd expect. Remember, there are other lesser banking mechanisms in play as well.  
The actual boot state of the MEGA65's 16-bit address space is:
0000-1FFF : unmapped, bank 0 RAM
2000-BFFF : mapped to ROM in bank 3
C000-CFFF : unmapped, then ROMC (from bank 2) banked via $D030 register
D000-DFFF : unmapped, then MEGA65 I/O banked via $01 register
E000-FFFF : mapped to ROM in bank 3

Reading the MAP Register
If you actually want to read the MAP register, you must do so via a hypervisor trap (hyperlink later).

A Macro To Simplify Mapping
RetroCogs from Discord provided these assembler macros to help set up mapping:

.macro mapHi(source, target, blocks) {
    .var sourceMB = (source & $ff00000) >> 20
    .var sourceOffset = ((source & $00fff00) - target)
    .var sourceOffHi = sourceOffset >> 16
    .var sourceOffLo = (sourceOffset & $0ff00 ) >> 8
    .var bitHi = blocks << 4
    ldy #sourceOffLo
    ldz #[sourceOffHi + bitHi]
}
.macro mapLo(source, target, blocks) {
    .var sourceMB = (source & $ff00000) >> 20
    .var sourceOffset = ((source & $00fff00) - target)
    .var sourceOffHi = sourceOffset >> 16
    .var sourceOffLo = (sourceOffset & $0ff00 ) >> 8
    .var bitLo = blocks << 4
    lda #sourceOffLo
    ldx #[sourceOffHi + bitLo]
}
Example Usage:

    mapHi(sidMusicPal.addr + $2000, SID_RAM + $2000, $01)
    mapLo(sidMusicPal.addr, SID_RAM, $08)
    map
    eom
The last param is a 4 bit field of which 8k chunks to map.

MAP-ping Beyond 1MB
The mapping mechanism provided will allow you to map out to 1MB.  But to reach into "attic RAM", you need to go even further, with greater offsets.  To do this, you would issue MAP twice.  First for the upper offset bits, then for the lower.

Deathly/BAS provided an example: let us assume we're MAPing from $ff8 0000 to $000 4000, i.e. the bottom of attribute RAM, and I used the same destination.
This is, in fact, the easier part of the block.  For the lower 32KiB, you set the accumulator to the megabyte of the source bank, and for the upper, that's Y.  If you are doing a lower MB MAPing, you always set X to $0f, and the same for Z if you are MAPing to the upper 32KiB.
You then ignore the MB in your math, so, we are MAPing from $8 0000 in this case, so $8 0000 minus $4000 then divided by 256, we get $7c0.

So the code would look as such:

LDA #$FF
LDX #$0F
LDY #$FF
LDZ #$0F
MAP      ; note the lack of an EOM, you only need to do this at the very end of both MAPs, and even then, only if you have not done an SEI
LDA #$C0
LDX #$C7
LDY #$C0
LDZ #$17
MAP
EOM  

Practical Use and Considerations
1) Dan provides as an example to use MAPLO and $2000-$7FFF as a movable window for accessing upper memory, and keep MAPHI steady so dispatch code and interrupt handlers are always visible. In that design, you only have to worry about a single offset for a single memory range.  
2) Obviously don't allow your own code to be MAP-ped out.  Put it in a place that will not change, otherwise you'll send the CPU off to neverland.
3) Take special note that BASIC's MONITOR command will drop you into the ML monitor.  However, this monitor's view is the CPUs view of memory - that is, you will only see things as they appear to the CPU...with mappings in place.  If you want to see the actual 28-bit memory, use the matrix monitor.
4) It is also worth noting that there are other features to provide direct access to higher memory...which means you may never need to use MAP at all!  Consider using DMA to copy data instead, or direct 32 bit data access.

From <https://www.blogger.com/blog/post/edit/7937298055659029003/2180978579796601970> 




MAP has some complex restrictions. For example, MAPHI is used to install the KERNAL IRQ handlers, so you can’t touch MAPHI without accommodating that somehow (e.g. disabling interrupts during access). You can limit memory shenanigans to one region of MAPLO, but then you also need to keep the code that accesses upper memory out of that region in your default MAP, such as with specially located dispatch/access code.

From <https://discord.com/channels/719326990221574164/1177363904272277544> 

Another commenter wrote:

1. i am checking on the way memory mapping works. according to the docs, you use MAPLO and MAPHI to map 16bit sections to a bank offset however there are two default mappings that go against the logic of: MAPLO addresses share the same offset, MAPHI addresses share their offset. The default values i can see on MAPHI and MAPLO on a fresh boot are B300 and E300 this means that all 16bit addresses would be mapped to bank 3 except for the 0000-1FFF range and the C000-DFFF range. However C000-DFFF is actually mapped to 2.C000–2.CFFF despite the B300 value on MAPHI. And $D000–$DFFF is actually mapped to FFD.2000–FFD.2FFF despite MAPHI mapping it to bank 3. Is there any magic I am missing that makes these mappings possible? 


2. 
3. 

4. 
5. 

6. gardners — 1/31/2026 5:25 PM
The $Cxxx region has a special "ROM like" mapping, like the C64 KERNAL and BASIC ROMs. This is independent of MAP.
7. So in short, you're not imagining things.

From <https://discord.com/channels/719326990221574164/731186768170450955/1412785540423483393> 

Dan recommends:


I try to recommend a simplified model as the default for MEGA65 programs: 
• Ignore C64-style and C65-style banking. Leave 00/01 and D030 at defaults.
• Ignore MAP until you need it. Rely on launching ML from BASIC via SYS, and assume the SYS MAP.
• Use DMA and 32-bit indirect addressing to reach above bank 0 in most cases.
• If you think you need MAP (or just prefer it), design how your program uses MAP early in the process, and expect to stick to that design. Prefer MAPLO and leave 0000-1FFF alone.
• I don't consider the color RAM windows to be that complicated if you're not changing COLPTR, but I suspect that it's probably easiest to just write to FF8.0000 in common cases.
• If you need more than this and don't need the KERNAL, use the techniques in the Memory chapter to ditch the KERNAL entirely and install your own hardware interrupt handlers.
• If you need lots of memory and also need the KERNAL, spend a month reading the Compendium end to end and ask lots of questions in the Discord

From <https://discord.com/channels/719326990221574164/782757495180361778/1467299639811375127> 



dddaaannn — 2/14/2025 1:29 AM
The KERNAL is E000-FFFF and is MAP'd in from 3.E000-3.FFFF. The minimal KERNAL running mode should be that, make sure 0000-1FFF and C000-DFFF are unMAP'd, and leave $00/$01 and $D030 in their boot state. When a machine code program is launched from SYS, it switches to the SYS MAP of MAPH=8300 MAPL=E000, which meets these conditions. (I don't see a problem with MAPL=0000.) Whether you can call KERNAL serial/DOS routines with interrupts disabled, I don't know, and you're finding out. 
I'm only aware of the KERNAL IRQ handler triggered by the vertical raster interrupt, and a brief skim of the ROM code suggests there's nothing serial/DOS related in the IRQ handler itself. Earlier I conjectured that DOS code paths may still not be expecting to be called with interrupts disabled (CPU I flag set) and might cause problems when called from an IRQ handler, but that's what needs investigation.

From <https://discord.com/channels/719326990221574164/782757495180361778/1467299639811375127> 


MEGA65 Memory Mapping with MAP
The MEGA65 CPU still normally executes code through a 16-bit address space, from $0000 to $FFFF. That is classic 6502 territory: only 64KB visible at once.
But the MEGA65 has much more memory than that. The 45GS02 CPU solves this with the MAP register, which lets selected 8KB regions of the 16-bit CPU address space point somewhere else in the larger physical address space. The official model is: MAP translates a 16-bit address into a larger address by adding an offset. 
1. The basic idea
MAP does not say:

$2000 now equals physical $45200
It says:

actual address = CPU address + MAP offset
So if $2000-$3FFF has an offset of $45200, then:

$2000 -> $47200
$335F -> $4855F
$3FFF -> $491FF
That “offset, not destination address” detail is one of the big gotchas.
2. MAP works in 8KB blocks
The 64KB CPU address space is divided into eight 8KB chunks:

$0000-$1FFF
$2000-$3FFF
$4000-$5FFF
$6000-$7FFF
$8000-$9FFF
$A000-$BFFF
$C000-$DFFF
$E000-$FFFF
MAP has two halves:

MAPLO = $0000-$7FFF
MAPHI = $8000-$FFFF
Each half has:

one shared offset
four enable bits
That means every mapped block in the same half shares the same offset. You cannot give $2000-$3FFF one MAPLO offset and $4000-$5FFF a different MAPLO offset at the same time. 
3. The A, X, Y, and Z registers
To set MAP, load A, X, Y, and Z, then execute:

MAP
EOM
The register layout is:

MAPLO uses X:A
MAPHI uses Z:Y
For MAPLO:

X high nibble = block enable bits
X low nibble  = high nibble of offset
A             = low byte of offset
For MAPHI:

Z high nibble = block enable bits
Z low nibble  = high nibble of offset
Y             = low byte of offset
The offset is in $100-byte units, so the stored value $452 means an offset of $45200.
4. Block enable bits
For MAPLO, the enable bits are:

bit 7 -> $6000-$7FFF
bit 6 -> $4000-$5FFF
bit 5 -> $2000-$3FFF
bit 4 -> $0000-$1FFF
For MAPHI:

bit 7 -> $E000-$FFFF
bit 6 -> $C000-$DFFF
bit 5 -> $A000-$BFFF
bit 4 -> $8000-$9FFF
So this:

LDA #$52
LDX #$24
means:

MAPLO selection = $2
MAPLO offset    = $45200
Selection $2 is binary %0010, so only $2000-$3FFF is mapped.
This:

LDY #$00
LDZ #$B3
means:

MAPHI selection = $B = %1011
MAPHI offset    = $30000
So these MAPHI blocks are mapped:

$8000-$9FFF
$A000-$BFFF
$E000-$FFFF
while $C000-$DFFF is left unmapped.
Full example:

LDA #$52        ; MAPLO offset low byte
LDX #$24        ; MAPLO select=$2, offset high nibble=$4
LDY #$00        ; MAPHI offset low byte
LDZ #$B3        ; MAPHI select=$B, offset high nibble=$3
MAP
EOM
5. Unmapped does not mean “offset zero”
This is another important distinction.
An unmapped block falls through to the normal legacy memory system. That means $00/$01, $D030, ROM banking, I/O banking, and cartridge behaviour may still affect what appears there.
A mapped block with offset zero ignores those legacy banking rules and points directly at physical RAM.
For example:

LDA #$00
LDX #$10        ; select $0000-$1FFF, offset $00000
LDY #$00
LDZ #$00
MAP
EOM
This maps $0000-$1FFF directly to physical 0.0000-0.1FFF. In that state, $0000 and $0001 are RAM, not the C64-style CPU banking registers. The official guide calls out exactly this distinction: C64-style banking only applies to blocks that are not selected by MAP. 
6. The default MEGA65 map
At boot, the useful mental model is roughly:

$0000-$1FFF : unmapped, bank 0 RAM
$2000-$BFFF : mapped to ROM in bank 3
$C000-$CFFF : unmapped, then ROMC via $D030
$D000-$DFFF : unmapped, then I/O via $0001
$E000-$FFFF : mapped to KERNAL ROM in bank 3
This corresponds to the familiar-looking MAP values:

MAPLO = $E300
MAPHI = $B300
or in code:

LDA #$00
LDX #$E3
LDY #$00
LDZ #$B3
MAP
EOM
But running only that code is not the whole boot configuration, because $C000-$DFFF also depends on the older banking mechanisms. Your notes captured this well: MAP is the big hammer, but not the only switch in the room. 
7. MAP, KERNAL, and interrupts
The KERNAL expects important memory to be visible in the usual places, especially $E000-$FFFF, where the interrupt vectors and handlers live. If KERNAL interrupts are active, keep $E000-$FFFF mapped to 3.E000-3.FFFF. 
Practical rule:

If you still need the KERNAL, be very careful with MAPHI.
A good beginner-friendly strategy is:

Leave MAPHI alone.
Use MAPLO as your movable window.
Avoid mapping $0000-$1FFF unless you really know why.
That matches Dan’s simplified advice from your notes: ignore MAP until you need it, prefer DMA or 32-bit indirect addressing for many upper-memory jobs, and when you do use MAP, design your MAP strategy early. 
8. Accessing memory beyond 1MB
The original C65-style MAP mechanism can reach offsets up to $FFF00, which covers the 1MB C65 address space.
The MEGA65’s 45GS02 extends this. To reach the larger 28-bit address space, you set an extra high byte for MAPLO or MAPHI. This requires two MAP operations before the final EOM. 
The pattern is:

; First MAP: set high byte
LDA #high_byte_for_MAPLO
LDX #$0F
LDY #high_byte_for_MAPHI
LDZ #$0F
MAP

; Second MAP: set normal block selects and low offset bits
LDA #maplo_offset_low
LDX #maplo_select_and_offset_high
LDY #maphi_offset_low
LDZ #maphi_select_and_offset_high
MAP
EOM
Important warning: the high-byte setting takes effect immediately after the first MAP. Do not let the code currently executing disappear halfway through the sequence.
9. Reading MAP
You cannot read MAP back with a normal CPU instruction. To inspect it, use either:

Matrix Mode debugger
Hypervisor trap hyppo_get_mapping
The normal BASIC MONITOR shows the CPU’s mapped view of memory. Matrix Mode is better when you want to inspect the actual machine state, including MAPHI and MAPLO. 
10. When should you actually use MAP?
Use MAP when:

You need fast repeated access to a window of upper memory.
You want to bank code or data into a convenient 16-bit address range.
You are writing a system-level program with a planned memory layout.
Do not automatically use MAP for every high-memory access. For many tasks, the MEGA65 gives you easier tools:

DMA for copying or filling larger blocks.
45GS02 28-bit indirect addressing for direct single-byte/pointer access.
VIC-IV display address features for graphics memory.
The reference guide also recommends 32-bit/28-bit addressing or DMA in many cases, keeping MAP for banking code or rare cases where a mapped window is genuinely better. 
11. Safe beginner recipe
For most MEGA65 machine-code programs:

1. Start from BASIC with SYS.
2. Leave $00/$01 and $D030 alone.
3. Leave MAPHI alone unless you are taking over interrupts.
4. Use MAPLO as a window, commonly somewhere like $2000-$7FFF.
5. Keep your MAP-changing code outside the region being remapped.
6. Restore a KERNAL-compatible map before calling KERNAL routines.
7. Prefer DMA or 28-bit indirect access when they are simpler.
Very retro, very powerful, and very easy to shoot yourself in the foot — which is exactly why we love this beast.


KERNAL without BASIC uses $90-$FA. 

With BASIC enabled (e.g. a subroutine called from a BASIC program or the KERNAL IRQ vector), all of $00-$FA are reserved. $FB-$FF are available for program use.,

The rest of the memory map is in the Compendium; see the Memory chapter. BASIC needs almost all of the 384 KB with all of its features enabled, but if you don't need BASIC or need BASIC but are willing to live without the bitplane graphics subsystem, there's more available for program use. 

$1600-$1EFF is always available for program use.,

Finding the address of screen memory is covered in the May Digest.  And in the Memory chapter of the Compendium.



It's less a matter of what is banked than what is running. KERNAL code runs when you call it, or when the KERNAL's interrupt handlers are active. If you [replace the hardware interrupt handlers](https://dansanderson.com/mega65/racing-the-beam/) and don't need the KERNAL's features, you can use page zero for whatever you want (per the previous note that $0000 and $0001 are CPU I/O hardware registers when un-mapped). When KERNAL code is running, it expects to have full control of $90-$FB. When BASIC code is running, it expects to have full control of $02-$8F.

You can use the CPU B register (set with tab) to change what page the zero-page addressing modes are accessing. This is one way to preserve page zero for KERNAL/BASIC use, with the proviso that you must restore B to $00 before calling a KERNAL API from your own code. The KERNAL's interrupt handler is smart enough to preserve your custom B setting so you don't have to worry about interrupts in this case.

Page $01 ($0100-$01FF) is the default CPU stack location, and KERNAL and BASIC reserve a bunch of other pages. If you want to maintain the KERNAL and also want a base page of your own, $16 ($1600-$16FF) is a good choice. See the Memory chapter for more information.


DOS will map in $8000:


1. dos_map_default:            ; The DOS
    .word %0001000100000000 ; Map in DOS RAM (8K @ $010000), map out BASIC
    .word %1011000110000000 ; MAP in DOS & I/O ($8000 + $18000 = $20000)

From <https://discord.com/channels/719326990221574164/1177363904272277544> 




$10000-$11FFF: RESERVED - C65 KERNAL DOS variables (do not use!)
$1F800-$1FFFF: Shared with FF80000 for 2k color ram (can be pushed ahead by 2k)



1. Regarding colour memory, I always use the 32bit address ( $0FF80000 ), so is it possible to unbank ( $0000D800 ), so that I can use this area for other stuff ? 
2. dddaaannn — 4/20/2025 12:56 PM
You can push the start of color RAM forward and use the fixed addresses that the windows see as regular RAM. You’re giving up a small amount of color ram but as long as you don’t need all of it you can do this.
3. (The start of color ram can be moved in the ff80000 space. The windows don’t move and always see ff80000.)
4. Drex — 4/20/2025 1:54 PM
Ok, so I can’t un-bank the colour windows as such, but I can just offset the colour memory pointer, by 1000 \ 2000 bytes etc, and then I would be able to use $d800 \ $1f800 for other stuff ? 

5. dddaaannn — 4/20/2025 1:57 PM
yup!


From <https://discord.com/channels/719326990221574164/977076334297743360/1363588679699796052> 

try to replace $D800 with  $FF80000 in your code. That is indeed confusing since colour RAM on MEGA65 can be seen at three different addresses. C64-legacy $D800 if I/O is banked in, the first 1K of colour RAM can be accessed there. C65-legacy colour RAM at $1F800, the first 2K (!) can be seen there. And the real MEGA65 address is at $FF80000 where the full 32K of MEGA65 colour RAM can be seen

6. See the "Memory" chapter in the Compendium. The answer is "kind of:" you can push the start of color memory ahead by 2K such that 1F800 refers to memory that's not being used as color memory, at the expense of shortening the color memory range by 2K.
7. (You'll only miss the 2K of color memory when doing something extreme with graphics. 
)

From <https://discord.com/channels/719326990221574164/977076334297743360/1363588679699796052> 



8. // load the titlescreen attribute map to $ff80000 - we have to do this
    // again, because there's some bug that stomps on the attribute map data,
    // causing the very top of the "d" in "loading" to flip horizontally.
    //
    // for future use - $001f800 is an area of memory which cannot be used.  In
    // this case, I don't fully get what's happening as I'm not actually
    // touching that memory, but I think that maybe the IFFL loader might be
    // writing values there, as the bug triggers during a call to
    // floppy_iffl_fast_load.
    //
    // this can be fixed using COLPTR and setting the offset to $0800, but this
    // would also offset the attribute map at $ff8000, and since this 
    // workaround fixed the issue, I would rather not risk any potential
    // cascading errors that might be caused by offset $ff8000 since that is
    // a very core part of the game, and I have no idea what all could break
    // from moving that.
    //
    // in the future, though, it may be desirable to set COLPTR to $0800 and 
    // sacrifice that 2KiB of the real attribute map, since 32KiB is literally
    // more than we can possibly use for maps.  
9. That comment was not all written at once, and you can see the evolution of my understanding of it as you read it. heh

From <https://discord.com/channels/719326990221574164/977076334297743360/1202833560629944341> 

stz is NOT store zero like in the 65c02 processor. for the mega65 / 45gs02 processor, it stores the z register.
  • Consequence: never use STZ to mean "store 0". Use `lda #0` / `sta addr` (or `stz` only if you genuinely want the Z register's value). A whole codebase that assumed STZ=store-zero will mostly "work" only because Z happens to be 0 in many paths; it fails intermittently wherever Z is nonzero (e.g. a click edge that never clears, a tile counter that starts nonzero so a render loop skips rows). When something is subtly wrong and the source looks correct, grep for `stz`.

VIC sprites — coordinate origin and basics
  • Sprite position is in VIC sprite coordinates, NOT screen pixels. In H320 (40-column) mode the screen's top-left visible pixel is at sprite (X=24, Y=50) — the standard C64 values. To overlay a hardware sprite on NCM cell (col,row): sprite_x = 24 + col*8, sprite_y = 50 + row*8. (We lost a lot of time using X=40, which put every sprite 16px too far right; only 24 is correct. Y=50 was right.)
  • A 24px-wide hardware sprite can draw a 16px-wide shape by using only the left 2 of its 3 data bytes per row (third byte $00). No X-expand needed for 1:1 pixels (clear the per-sprite bit in $D01D / SPRITE_X_EXPAND).
  • MEGA65 16-bit sprite pointers: set bit 7 of $D06E (SPRPTRBNK) to enable; each pointer-table entry is a 16-bit value = data_address / 64 (data must be 64-byte aligned). Point the table base via $D06C/$D06D. Sprite-N X/Y low bytes are $D000+2N / $D001+2N; the 9th X bit is in $D010 (one bit per sprite), and MEGA65 adds further X/Y MSB bits in $D05F/$D077/$D078. When repositioning one sprite, read-modify-write those MSB registers so you preserve the other sprites' bits.
  • Sprite priority $D01B: bit clear = sprite in front of the foreground (chars), bit set = behind. Clear the bit for cursors/selectors that must sit on top.

Render order with overlapping chrome
  • If a scrolling playfield shares cells with static UI chrome (an intentional overlap), draw the playfield FIRST and the chrome ON TOP each frame, or the playfield erases the chrome. Equivalently, give the chrome and the map non-overlapping cell ranges so order doesn't matter.


