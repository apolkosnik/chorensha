# Cho Ren Sha 68k: Amiga port plan

## Target

**Minimum: a 68020 or better with an RTG card (Picasso96 or CyberGraphX), or an AGA Amiga (A1200 class) with 8 MB of fast RAM. Main target: 68030 at 50 MHz with an RTG card. AmigaOS 3.x.**

| Machine | Display | Status |
|---|---|---|
| 68030/50 + Zorro III RTG card (A3000/A4000 class) | RTG | Main target. Full speed expected (estimate, see budget). |
| 68020+ + Zorro II RTG card | RTG | Minimum. Card bandwidth may force rendering every second frame. |
| A1200 (68020/14) + 8 MB fast RAM | Native AGA | Minimum. Game logic at full rate; rendering rate to be measured (C2P on a 68020/14 is expensive). |
| 68040 / 68060 / PiStorm / Vampire | RTG or AGA | Full speed. |
| OCS/ECS, A1200 without 8 MB fast RAM, 68000 | - | Not supported. |

When both are available, RTG is used. The executable needs about 2.2 MB of free memory to load, plus a 1-2 MB process area (heap) at start-up; at start-up it reports the detected machine, the chosen display path, or the requirements if the machine falls short.

Memory note: an A1200 with 8 MB of fast RAM has only about 4.9 MB free after Workbench 3.2 has booted (measured in emulation), so the native AGA path needs a memory budget (see Architecture).

## Findings from the source

### Game core

- `sources/sz2.s` is a re-assemblable disassembly of the X68000 game: about 102k lines, about 75k of them instructions.
- It is plain 68000 code: no `movep`, bitfield, 32-bit mul/div, `movec`, `cas` or `move16`.
- Platform dependencies go through a small set of hooks already identified by the Falcon port:
  - `mem_map.s` defines the X68000 I/O regions as RAM shadow buffers (CRTC, video controller/palettes, MFP, system port, sprite registers, PCG, text planes). The game writes there harmlessly; the port layer reads back what it needs (e.g. palettes at `L_00E82000+$200`).
  - `emulator.s` emulates Human68k DOS and FLOAT calls (line-F, 83 call sites) and IOCS calls (`trap #15`, about 50 sites).
  - `XSP_OUT` is diverted to `prepare_sprite_infos`, which receives the game's own sprite list (up to 512 entries of x, y, pattern, attributes; 8 bytes each).
  - `DRAW_CHARACTER` and `CLEAR_TEXT_PLANE` are diverted for the text layer.
  - The port's VBL handler chains into the game's `VBL_INTERRUPT_HANDLER` with `move.l L_00000118,-(sp); rts`.

### Privileged instructions

The game runs in supervisor mode on the X68000 and the Falcon. Under AmigaOS (required for RTG) it runs as a user-mode task, so these must be handled:

| Where | Instructions | Plan |
|---|---|---|
| `XSP_ON` / `XSP_OFF` | `ori #$700,sr` / `andi #$f8ff,sr` (4) | Remove under `__AMIGA__`: they only guard shadow-register updates. |
| Raster sync before `skip_raster_sync1` | `move sr,-(sp)`, `ori`, `move (sp)+,sr` | Already skipped by the `__AMIGA__` branch; verify the `move sr` before it. |
| `CPU_INTEGER_BENCHMARK` | `ori` / `andi` on SR (2) | Not reached (`CALCULATE_CPU_POWER` returns early); remove to be safe. |
| Atari exit block | `move #$2700,sr` | Amiga needs its own exit path. |
| `VBL_INTERRUPT_HANDLER`, `RASTER_INTERRUPT_HANDLER` | `ori`/`andi` on SR, `rte` | Run in supervisor mode from an interrupt server (see below). |

### Build bug (fixed)

`ifd __ATARI__ || __AMIGA__` only tests the first symbol in vasm, so an `-D__AMIGA__` build took the X68000 branch in four blocks. `sz2.s` now defines `__PORT__` for either port, and those blocks use `ifd __PORT__`. The Atari TOS and the X68000 object are byte-identical before and after.

### Falcon shortcuts the Amiga port must not inherit

1. **Frozen background.** On the X68000 the background is two 512x512 256-colour GVRAM pages, scrolled independently by the vsync callback `L_0002A5D2`: page 0 at 4 px/frame, page 1 at 1 px/frame (parallax), with a horizontal variant when `WORD_0008DAFC` is set (rotated screen). The Falcon port skips the GVRAM build, loads a pre-flattened `BACKGND.DAT`, and pins the scroll at 0 (`clr d0 ; Fixme!` in `graphics.s`).
2. **No music.** `trap #4` (MCDRV, YM2151 FM driver) and `trap #2` (PCM8) are stubbed to `rte`. Sound effects play on one channel at 12.5 kHz.
3. **DSP-assisted sprite restore.** `dsprite.asm` computes restore runs on the DSP56001; the Amiga has no equivalent, and restore-only rendering is invalid once the background scrolls.
4. **`_BITSNS` returns 0** (no keyboard matrix).

### Data

- `binaries/amiga/` holds `BGM_DAT`, `ETC_DAT`, `XSP_DAT` identical to the Atari set.
- `PCM_DAT` is still raw X68000 ADPCM (`.pcm`); the Atari build uses converted `.sam` files.
- 1,885 sprite patterns, 16x16 at 4 bpp, about 241 KB.
- The GVRAM builder writes pages 0 and 1 only (2 x $80000), so the Amiga GVRAM shadow is 1 MB.

## Architecture (OS-friendly)

RTG drivers need the OS, so there is no hardware takeover. The native AGA path uses the same OS-friendly structure (an Intuition screen and the copper through graphics.library), so both outputs share one port layer and one chunky renderer.

| X68000 | Amiga |
|---|---|
| 512 sprites via XSP | Compiled sprites into an 8-bit chunky buffer in fast RAM; reuse the Falcon radix sort; full redraw each frame, no restore |
| 2 scrolling GVRAM pages | Per frame: copy the slow layer, overlay opaque spans of the fast layer. Layers built at init by the game's own routine writing into the GVRAM shadow, then converted to 8-bit chunky |
| Text VRAM | Compiled 8x8 characters, 8-bit |
| Palettes (graphics + sprite, 512 entries) | 256-entry RTG palette built from the entries actually used; reloaded when the shadow palette changes |
| VBL interrupt (55.46 Hz) | Timer interrupt (CIA via `timer.device`/`cia.resource`) at 55.46 Hz, so the game runs at its original speed independent of the RTG refresh. The server enters `VBL_INTERRUPT_HANDLER` through a fake format-0 exception frame so its `rte` returns to the server |
| Raster interrupts | Not used (raster sync already skipped) |
| IOCS `trap #15` | Same shim as the Atari; real `_BITSNS` and `_JOYGET`. The trap vector is task-local (`tc_TrapCode`) |
| Human68k DOS (line-F) | The original line-F opcodes reach the task trap handler, which returns into a user-mode routine that calls dos.library (`\` to `/` in paths). Changing the 2-byte opcodes into calls would push many short branches out of range. Non-FPU line-F opcodes are passed on by the 68040/68060 libraries (still to be tested with them installed) |
| `trap #2` PCM8 | Stub (game only calls function `$1FB`) |
| `_ADPCMOUT` | Paula channels allocated through `audio.device`, 8-bit samples converted offline at 15.6 kHz, 2 channels round-robin |
| `trap #4` MCDRV | Pre-rendered music streamed on the other 2 channels |
| Joystick / keyboard | `lowlevel.library` `ReadJoyPort` (joystick, CD32 pad); keyboard from `IDCMP_RAWKEY` on the game window |

### Display

Both outputs consume the same 8-bit chunky frame from fast RAM.

RTG:

- Open a 256x240 (or nearest available) 8-bit screen through Picasso96 or CyberGraphX; fall back to 320x240 centred.
- Upload the chunky buffer each frame (`WritePixelArray`/`p96WritePixelArray`, or direct after `LockBitMapTags`).
- Double-buffer with `ChangeScreenBuffer` where the driver supports it, otherwise accept tearing.

Native AGA:

- 256x256 PAL lowres screen, 8 bitplanes, 64-bit fetch mode; double-buffered with `ChangeScreenBuffer`.
- Chunky-to-planar conversion of the frame into the back buffer (about 61 KB of chip writes per frame). On a 68020/14 this is the most expensive step, so rendering runs below the logic rate there; dirty-row C2P (the slow background layer moves only 1 px per frame) is the first optimisation.
- Memory budget for 8 MB machines (about 4.8 MB free): executable about 2.2 MB, process area 1-2 MB (735 KB used), background layers 2 x 128 KB, chunky frame 64 KB; compiled sprites (about 1.5-3 MB on the Falcon at 16-bit) must be bounded, with a generic masked-sprite routine as the fallback when memory is short. Music is streamed per stage.

### Frame budget

One X68000 frame at 55.46 Hz is 18.0 ms. Game logic is measured (see Phase 1 results); the rendering figures are still estimates.

| Work | 68030/50 | 68020/14 |
|---|---|---|
| Game logic (measured, 95th percentile) | 1.1 ms | 3.7 ms |
| Upload 61,440 bytes (256x240x8), RTG | Zorro III: about 4-6 ms. Zorro II: about 15-20 ms | - |
| C2P of 61,440 bytes, AGA | - | chip-bus bound, the main cost on this machine |
| Slow-layer copy (61 KB fast to fast) | about 2.5 ms | about 8 ms |
| Fast-layer overlay | 57% opaque, 3.5 runs per line: span copy | same |
| Sprites and text | up to 268 sprites per frame | same |

Game logic always runs at 55.46 Hz; rendering skips frames when the budget is exceeded.

## Audio

- Sound effects (done, `sources/amiga/audio.s`): the game plays one effect at a time with IOCS `_ADPCMOUT` and keeps its priority, asking `_ADPCMSNS` whether one still plays. After `LOAD_PCM_SAMPLE_FILES` (hook `amiga_samples_loaded`) each of the 31 original ADPCM files is decoded once into chip RAM (462 KB of 8-bit PCM), and the game's sample table is pointed at the decoded data. Decoding follows MAME's okim6258 as the X68000 wires it: 10-bit output, signal -2 and step 0 at each start, low nibble first, played as signal >> 2. The samples are mastered for that range: the Falcon converter's 13-bit clamp makes them 4 times quieter. Paula plays them at the X68000 rate, 15625 Hz (period 227 on PAL, computed from the E clock), on channels 0 and 1 together (centred, as the X68000's mono ADPCM on both sides; the output bits of the mode select the sides), then loops a silent word. No audio interrupt: `_ADPCMOUT` waits a few raster lines for Paula to stop and to take the new start, and `_ADPCMSNS` uses the expected end in frame-timer ticks. The four channels are allocated through `audio.device` for the whole run; without them, or without enough chip RAM, the game runs silent.
- Music: MCDRV functions used are 1, 2, 3, 5, 20, 28, 46 with 13 `.MDC` tracks. Record each track from an X68000 emulator/MDC player with loop points, compress to 4-bit at about 14 kHz, stream from fast RAM. Music on 2 channels (L/R), effects on the other 2.

## Phases

| # | Phase | Done when | Status |
|---|---|---|---|
| 0 | Build and test setup: Amiga section in the build scripts, `__PORT__` fix, Amiga entry point with machine and display-path detection, FS-UAE test harness with an RTG system drive | Executable builds, starts, reports the machine and exits cleanly | Done |
| 1 | Measure: sprites per frame, game-logic CPU time on a 68020/14 and a 68030/50, palette entries used per layer, background-layer opacity, memory use | Numbers that confirm or correct the frame and memory budgets | Done for the attract demo (results below) |
| 2 | Port layer, no rendering: user-mode handling of privileged instructions, DOS/IOCS shim, timer interrupt at 55.46 Hz, `WAIT_VBL`, sincos, input, exit path | `DEMO.REP` replay runs to the same score, stage and RNG state as reference runs | Done against an Amiga-generated reference; the comparison with the X68000 original needs an X68000 emulator (see Open items) |
| 3 | RTG renderer: chunky core, palette mapping, upload, frame skipping | Playable on a 68030/50 with RTG in emulation | Core done (see below): correct picture, game at full speed, display about 38 fps on a 68030/50; 55 fps needs rendering under about 16 ms |
| 4 | Audio: sound effects, then the music pipeline | Music and effects in game | Sound effects done (see Audio); music not started |
| 5 | 68030 optimisation: compiled-sprite tuning, span-based overlay, Zorro II path | 68030/50 holds 55.46 Hz on Zorro III | |
| 6 | Packaging: icon, install script, optional WHDLoad | Installable release | |
| 7 | Native AGA output: screen, palette, C2P, frame pacing, memory budget for 8 MB machines | Playable on an A1200 with 8 MB fast RAM | Candidates: c2plib (Aminet dev/misc/c2plib.lha; check its licence) for the C2P routines, and graphics.library WriteChunkyPixels, which BlazeWCP (Aminet util/boot/BlazeWCP178.lha) speeds up on users' systems |

## Phase 1 results (attract demo, 6,000 frames)

Measured with `sz2 6000` in cycle-exact FS-UAE configs; summaries from `tests/amiga/measure_summary.py` and `tests/amiga/graphics_summary.py`. The sprite sequence was identical on every machine, so the replay is deterministic.

| | 68020/14 (A1200 + 8 MB) | 68030/50 | 68030/50 + RTG |
|---|---|---|---|
| Game logic per frame, median | 1.81 ms | 0.54 ms | 0.54 ms |
| Game logic per frame, 95th percentile | 3.69 ms | 1.10 ms | 1.10 ms |
| Frames over 18 ms (outside loading) | 0 | 0 | 0 |
| Sprites per frame: mean / 95% / max | 70.5 / 169 / 268 | same | same |
| Heap high-water mark | 735 KB | 735 KB | 735 KB |

- The game logic is much lighter than estimated: on the X68000 the hardware did the heavy lifting. Almost the whole frame is available for rendering even on a 68020/14.
- Colours (`graphics_summary.py`): GVRAM page 0 (fast layer) uses 18 colours and is 57% opaque in 3.5 runs per line on average; page 1 (slow layer) uses 10 colours and is fully opaque; the sprites drawn used 151 palette entries (86 colours); the text layer 13. All layers together: 99 distinct colours, so one 256-colour palette (RTG 8-bit or AGA) reproduces them exactly. Only 452 of the 1,886 sprite patterns appear in the demo, so later stages need checking.
- Memory: an 8 MB A1200 has about 4.8 MB of fast RAM free after Workbench 3.2; the executable takes about 2.2 MB, the process area 1-2 MB.
- Memory, current: the executable is 2.99 MB (264 KB code, 40 KB data, 2.7 MB uninitialised data in four hunks, the largest 1 MB: the X68000 GVRAM shadow). A 4 MB A1200 with Workbench 3.2 has 3.05 MB of fast RAM free (`rtg-020`), so it only just fits; the game heap (1 MB fallback), the sprite arena (256 KB fallback) and the decoded samples (462 KB) then go to chip RAM. At 3.21 MB, in one 2.9 MB hunk, the executable did not load there at all. Split into hunks, it loaded, but parts of the program spilled into chip RAM (slower), and the samples no longer fitted. Keep the executable's size in mind; `C:Avail` run through `run_fsuae.sh` shows the free memory of a config.

## Port layer status (Phase 2, headless)

The game core runs its attract demo on every supported config and exits cleanly, through the frame limit or through the game's own EXIT menu entry. The 6,000-frame demo reaches identical checkpoints (score, random table index, scroll counter, sprites; the score climbs to 137,041) on the 68020/14 A1200, the 68030/50, and RTG with 68020, 68030 and 68040; twelve consecutive 6,000-frame runs on the A1200 passed. Implemented in `sources/amiga/emulator.s`:

- Human68k DOS and FLOAT calls stay the original line-F opcodes. The task trap handler (`tc_TrapCode`) receives them, pushes the return address on the user stack and returns into `human68k_call` in user mode, which uses dos.library. `_OPEN`, `_CREATE`, `_READ`, `_WRITE`, `_SEEK`, `_CLOSE`, `_DELETE`, `_SETBLOCK` (against the real process area), `_NAMECK` (fills the name structure; the C library depends on it), `_GETPDB`, `_EXIT`/`_EXIT2`, `__LMUL`, `__LDIV`; console calls are no-ops. Unimplemented calls are reported by number.
- IOCS (`trap #15`): the Falcon set plus `_BGTEXTGT` from the sprite VRAM shadow (the background builder needs it) and `_BITSNS` from a keyboard matrix. `trap #2` (PCM8) and `trap #4` (MCDRV) return; the MCDRV probe reports no driver.
- Privileged instructions outside the interrupt handlers are removed or replaced (`move ccr`) under `__AMIGA__`; the 24-bit heap mask of the C start-up is widened.
- Stacks: the game's stacks are registered with exec via `StackSwap()` (exec checks the stack pointer against the bounds on task switches, and dos.library relies on them); every OS call from the game runs on a separate OS stack, also switched with `StackSwap()`.
- Frame timing: a CIA timer at the X68000's 55.46 Hz (the first free of CIA-B timer A/B, CIA-A timer A/B, through cia.resource; the vertical blank if none is free). The timer interrupt only `Cause()`s a software interrupt, which enters the game's VBL handler through a format 0 exception frame. The handler lowers the interrupt mask on purpose (for the X68000's raster interrupts), which is harmless at the software interrupt level but not in a level 6 CIA-B handler. `WAIT_VBL` and `XSP_VSYNC` sleep on the frame signal instead of polling.
- Input (`sources/amiga/input.s`): joystick in port 2 and CD32 pad through `lowlevel.library` `ReadJoyPort` (fire 1 / red = trigger A, fire 2 / blue = trigger B), read once per game frame; keyboard through an `input.device` handler (events are passed on): cursor keys = directions, CTRL / Z = trigger A, left SHIFT / X = trigger B, and ESC, 1, TAB, SHIFT, CTRL, RETURN, SPACE and the cursor keys also in the X68000 key matrix for `_BITSNS` (menu cancel, debug keys).
- Leaving through the game's menu (EXIT) returns to the shell; the summary reports the exit reason (game, frame limit or exception).
- `PRINTF` prints the game's messages (Shift-JIS) to standard output.
- Unexpected exceptions in the game (bus/address error, illegal instruction, ...) are reported with the code offset instead of a Software Failure requester.

## Renderer status (Phase 3)

`sources/amiga/graphics.s` composes each frame into an 8-bit chunky buffer; `sources/amiga/display.s` shows it on a Picasso96 or CyberGraphX screen (320 x 256, else 320 x 240). Picasso96 is used when both are present; `-D__FORCE_CYBERGRAPHX__` forces the CyberGraphX path for testing on a Picasso96 system (its emulation layer). Without RTG the game runs headless until the AGA output (Phase 7).

- GVRAM pages 0 and 1 are converted once into 8-bit layers (the game builds GVRAM only at start; a hook in sz2.s marks it). Page 1 is copied in the gaps between page 0's opaque runs, page 0's runs on top, so each pixel is written once; runs are copied through computed jumps into unrolled moves. A non-zero horizontal scroll (rotated screen) falls back to a per-pixel path.
- Palette: the graphics and sprite/text palettes (512 X68000 entries, 117 distinct colours) become one 256-colour palette. Every graphics index in use keeps its own slot, so the layers need no remapping; sprite and text entries share slots by colour. The game cycles about 14 entries every frame; those are updated incrementally and loaded with a partial LoadRGB32 (full rebuilds fell from 2,356 to 113 per 3,000 frames).
- Sprites: compiled per (pattern, flip) on first use into a 1 MB arena (256 KB if memory is short, generic routine when full): the eight most frequent colours in registers, one move per opaque pixel. Ordered like the Falcon port (32 priority buckets).
- Text: the four planes are read directly (the game's simultaneous-access clear of all four planes is emulated); a converted copy of the visible window is kept and only character rows written since the last frame are reconverted. Each line with text is converted straight into a bit per four-pixel group plus a mask and palette-mapped colours for each group with text, so drawing is one masked long write per group. Lines are converted again when their character row was written, the scroll changed, or the text colours' palette slots changed (10 times in the demo).
- Upload (Picasso96): the screen's bitmap is locked (`p96LockBitMap`) and the lines are copied directly; `p96WritePixelArray` is the fallback if the lock fails.
- Frame timing: game frames follow a fixed schedule at 55.46 Hz; when the game is late the picture is skipped, otherwise the finished frame is rendered at its tick. The 6,000-frame attract demo reaches the reference checkpoints on every config with rendering on.
- Screenshots: measurement runs read frames back from the screen every 500 frames (`screen_NNNNN.bin`, `tests/amiga/screenshot_png.py` converts them). Screenshot frames are rendered even when the game is late, so each screenshot shows exactly its frame and screenshots can be compared between builds (`tests/amiga/screenshot_compare.py`). Picasso96 uses p96ReadPixelArray; CyberGraphX's ReadPixelArray reads only RGB formats, so that path uses graphics.library ReadPixelArray8 with a one-line temporary bitmap; `-D__RENDER_PROFILE__` builds print the time per render stage.

Measured on the 68030/50 RTG config (cycle-exact, `profile_summary.py`), medians per rendered frame:

| | Phase 3 | Phase 5 so far |
|---|---|---|
| Palette | 0.60 ms | 0.60 ms |
| Graphics | 6.90 ms | 7.03 ms |
| Text | 2.49 ms (95%: 12.6) | 1.11 ms (95%: 5.1) |
| Sprites | 2.08 ms | 2.06 ms |
| Upload | 5.03 ms | 4.47 ms |
| Total | 17.09 ms | 15.43 ms |
| Frames rendered of 6,000 | 4,024 | 4,830 |

Gameplay frames have a fixed cost of about 13 ms (graphics, upload, text, palette) plus sprites (0.4 to 4 ms). The game keeps its speed throughout. The 68020/14 RTG config renders about 15 fps at full game speed. The `rtg-040` config emulates the CPU in "fastest possible" mode, not cycle-exact, so its timings say nothing about a real 68040.

## Testing

- `tests/amiga/run_fsuae.sh <config> <executable> [timeout] [arguments]` boots FS-UAE (Kickstart 3.2) without a window (SDL offscreen video; `SHOW_WINDOW=1` shows it) from a Workbench 3.2 + Picasso96 system drive, runs the executable from a second drive (`WORK:`, with the game data), and prints its output, or the shell's error if it cannot load. It only stops the FS-UAE process group it started. Configs: `a1200-4mb` (below minimum), `a1200-8mb`, `a1200-030`, `rtg-020`, `rtg-030`, `rtg-040`, and `rtg-040-libs` / `rtg-060-libs` on a system drive variant with the MMULib CPU libraries.
- System drive (`AMIGA_SYSTEM_DIR`, default `~/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg`): the DH0 system directories of the developer's Workbench 3.2 image, copied read-only, with Picasso96 3.6.3 and a `uaegfx` monitor. Differences from the source image: ZZ9000/Z3660 drivers and the MMULib CPU libraries are moved to `Storage/`, `S:startup-sequence` is a reduced test version (originals kept as `.orig`), and `WB1:` is assigned to `SYS:` for the preferences.
- WinUAE 6.1.0b9 (Unix AppImage) hangs inside the uaegfx monitor driver with this system, so RTG testing uses FS-UAE.
- The 68020 and 68030 configs are cycle-exact (68030 at 49.7 MHz), so measured timings are meaningful.
- `sz2 <frames>` exits after that many frames and writes `measure.bin` (per-frame CPU time, sprites) and `graphics.bin` (background pages, palettes, sprite patterns and palette usage). With `RESULT_DIR` set, the harness copies them out; `measure_summary.py [--timeline]` and `graphics_summary.py` summarise them.
- `tests/amiga/check_lvos.sh` checks every library vector offset against the vbcc inline headers.
- Input scripts: `sz2 <frames> <script>` feeds scripted joystick states and key events (key events go through `input.device`, the same path as real keys). `tests/amiga/make_input_script.py` builds them from text; `INPUT_SCRIPT=<file>` makes the harness copy one to `WORK:input.bin`. `tests/amiga/input/menu_exit.txt` (joystick) and `menu_exit_keyboard.txt` (keyboard) select EXIT in the main menu; both must end with "Exit: game" at frame 360.
- Checkpoints: measurement runs also write `checkpoints.bin` (every 60 frames: score, random table index, background scroll counter, sprites, player structure). `tests/amiga/checkpoints.py text` converts it; `checkpoints.py compare <reference> <files>` reports the first difference. `tests/amiga/reference/attract-6000.txt` is the reference for the 6,000-frame attract demo.
- Debug builds: assembling `emulator.s` with `-D__TRACE__` prints every Human68k call with its arguments and result; `-D__HEARTBEAT__` prints the task state, last trap, exec idle/dispatch counts and the last alert to the serial port every 50 VBL. `-D__FORCE_VERTB__` uses the vertical blank instead of a CIA timer; `input.s` with `-D__NO_LOWLEVEL__` or `-D__NO_INPUT_HANDLER__` drops the joystick or the keyboard source. `SERIAL_LOG=<file>` captures the serial port; `KEEP_WORK=1` keeps the work directory with the FS-UAE log.
- Sound effects: measurement runs write `samples.bin` (effects played, the rewritten sample table and the decoded samples). `tests/amiga/samples_check.py` decodes every sample of `SZ2_PCM.CNF` from the original files with the MAME model and compares length, mode, priority and data. `AUDIO_CAPTURE=<file.wav>` makes the harness record the emulated audio through OpenAL Soft's wave backend, at real speed, with drive sounds and the emulator's output filter and interpolation off. `tests/amiga/audio_check.py <wav> <samples.bin> [minimum events]` finds the sound events and identifies each by correlating its start with the decoded samples. In the 1,500-frame attract run, all 9 events match (correlation 0.93 to 0.98) and play equally on both sides. The 0.24 s events are bursts of the shot sound, which the demo retriggers every 4 frames.
- Profiling: `-D__RENDER_PROFILE__` builds print the average time per render stage, and write `profile.bin` with every rendered frame's stage times. `tests/amiga/profile_summary.py` prints medians, 95th percentiles and what the frames over budget spend their time on.
- Renderer regression: in normal runs the game's VBL handler (sprite buffer flips, palette effects) runs on the timer, so the picture at a given game frame depends on timing. Two runs of the same build give different background colours. Lockstep test builds (`-D__LOCKSTEP__`) run the VBLs from the game's frame waits and render every frame, so screenshots (every 100 frames) are the same in every run. `tests/amiga/render_compare.sh <commit>` builds the working tree and the commit's renderer (`graphics.s`, `display.s`) as lockstep builds and compares all screenshots pixel for pixel and the checkpoints (`screenshot_compare.py`). The text and upload changes above give the same 59 pictures as before. One run of the script hung once in the reference build (not reproduced since); watch for it.
- Hardware test kit (`tests/amiga/hardware`, packaged by `make_kit.sh` into `binaries/amiga/hardware_test.zip` after `./build.sh`): `sz2_profile` (the game with render profiling) and `vram_bench`, which times reads, writes and copies on the card's memory and in fast RAM, on an 8-bit Picasso96 screen. `RunTests` runs both from the game's directory and lists the files to send back. Evaluate the returned files with `profile_summary.py`, `checkpoints.py compare` (the attract reference), `samples_check.py` and `screenshot_png.py`. The kit was rehearsed in FS-UAE through `Execute RunTests` (`WORK_FILES` copies extra files into `WORK:`). Note that FS-UAE times the card's memory exactly like fast RAM, even on the Zorro II config (`vram_bench`: 19 MB/s copy on the 68030/50, 5.3 MB/s on the 68020/14). So emulation cannot judge drawing directly into the card's memory; that needs the kit's numbers from real cards.
- Reference runs from the original: no X68000 emulator is available on the development machine (MAME is only a source tree; X68000 BIOS ROMs are needed). Once one is, the same checkpoint values recorded there replace the Amiga-generated reference, and screenshots can be compared at fixed frames.

## Open items

- Reference runs from the X68000 original: needs MAME built with the X68000 driver (or another X68000 emulator) and the X68000 BIOS ROMs, then the checkpoint values recorded there.
- 68040/68060 CPU libraries (deferred): with MMULib's 68040.library the 6,000-frame demo runs (`rtg-040-libs`); the 68060 run (`rtg-060-libs`) did not finish within 10 minutes and has not been investigated.
- A1200 dead-end alert 8000 0006 (CHK exception) seen twice during development, both times while other FS-UAE instances ran different configs on the same system drive. Not reproduced since: 24 runs with four instances in parallel (8 each with the current code, with only the level 6 handler put back, and with the exact code that crashed) and 12 sequential 6,000-frame runs. Both suspected causes (the game's VBL handler running at CIA-B level 6, a 64-bit DIVU on a garbage register) are fixed anyway. Watch for it.

- Self-modifying code on 040/060: `CacheClearU()` after generating sprite code; check the game code for SMC.
- Rotated-screen mode: disable at first.
- Audio, on hold (only the sound effects are done):
  - Music needs the 13 MCDRV tracks rendered: either MAME with the X68000 BIOS ROMs, or our own YM2151 + MDC player.
  - Planned outputs: MHI for MP3 music on cards that decode it (`mhizz9000` / `mhiz3660`; needs gapless trimming or intro + loop files, and testing on real hardware, since FS-UAE has no ZZ9000/Z3660), with a Paula stream on channels 2 and 3 as the fallback.
  - Optional AHI output for effects and music when the AHI mode is a sound card (ZZ9000AX, Z3660AX). It frees the chip RAM the effects use, and can be tested with `filesave.audio`. Direct Paula stays the default, because AHI's Paula driver mixes in software.
