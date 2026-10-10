# Cho Ren Sha 68k - Amiga port

Cho Ren Sha 68k is a vertical shoot 'em up for the Sharp X68000, (c) 1995
by Famibe No Yosshin. This is a port of the original game code to the
Commodore Amiga: the X68000 program runs on the 68020+ with the X68000's
hardware emulated in software, and its picture is shown on a graphics
card (RTG) or on the AGA chipset.

The whole game plays, with its sound effects and its music (on Paula, or
through AHI or an MHI MP3 decoder).


## Download

| Archive | Size | Format |
| --- | --- | --- |
| [ChoRenSha-amiga.lha](https://github.com/apolkosnik/chorensha/raw/amiga-port/binaries/amiga/ChoRenSha-amiga.lha) | 87 MB | LhA (`-lh5-`, level 1 headers), the Amiga's usual format |
| [ChoRenSha-amiga.zip](https://github.com/apolkosnik/chorensha/raw/amiga-port/binaries/amiga/ChoRenSha-amiga.zip) | 86 MB | Zip |

Both archives hold the same files, 108 MB unpacked: the `ChoRenSha`
drawer and its icon (`ChoRenSha.info`).

```
ChoRenSha.info           the drawer's icon
ChoRenSha/
  ChoRenSha              the program (344 KB)
  ChoRenSha.info         its icon
  ReadMe.txt             this text
  BGM_DAT/               the original MCDRV song data
  ETC_DAT/               demo replays, tables, high scores
  PCM_DAT/               the sound effects
  XSP_DAT/               the sprites
  MUSIC_DAT/             the music (108 MB):
    *.crm                  12 streams for Paula and AHI (65 MB)
    *.mp3                  23 MP3 files for MHI (43 MB)
```

Unpacking on the Amiga, from a Shell (the target drawer gets a
`ChoRenSha` drawer):

```
LhA x ChoRenSha-amiga.lha Work:Games/
UnZip ChoRenSha-amiga.zip -d Work:Games
```

On other systems, any LhA tool (LHa for UNIX, 7-Zip, xarchiver, Lhasa)
or zip tool unpacks them; copy the result to the Amiga's disk as it is.
The LhA archive is tested with the Amiga's LhA 2.15.

The program alone, for updating an installed copy, is
[binaries/amiga/sz2](https://github.com/apolkosnik/chorensha/raw/amiga-port/binaries/amiga/sz2)
(rename it to `ChoRenSha`). The archives are built from the sources by
`tools/make_amiga_release.sh` (after `./build.sh` and
`tools/music/build_music.sh`).


## Requirements

- AmigaOS 3.x, a 68020 or better.
- Either a graphics card with Picasso96 or CyberGraphX (8-bit screen,
  320 x 256 or 320 x 240), or an AGA Amiga (A1200, A4000, CD32 with
  expansion) with at least 8 MB of fast RAM.
- About 3 MB of free fast RAM and 0.6 MB of chip RAM for the sounds.
- For the music, 108 MB of disk space (`MUSIC_DAT`: 65 MB of streams for
  Paula and AHI, and 43 MB of MP3 files for MHI, which may be deleted if
  you do not use MHI), on a hard disk or other storage that reads 44 KB
  per second while the game runs.

Speed: the game itself always runs at full speed (55 frames per second);
how many of those frames are shown depends on the machine. A 68030 at
50 MHz shows about 30 to 40 per second with a graphics card and about 20
on AGA; a stock A1200 (68020 at 14 MHz, AGA) about 8. The `` ` ``
key shows the number (see Controls).


## Installation and start

Copy the `ChoRenSha` drawer anywhere (hard disk or RAM:) and double-click
the `ChoRenSha` icon, or start it from a Shell:

```
CD ChoRenSha
ChoRenSha
```

The program needs its data drawers (`BGM_DAT`, `ETC_DAT`, `PCM_DAT`,
`XSP_DAT`) next to it. `MUSIC_DAT` holds the music: without it (delete or
rename it, e.g. to run from a small disk), the game runs without music.
Started from Workbench, its messages appear in a small window, which stays
open after the game has ended until you close it.

To quit, choose EXIT in the game's menu.


## Controls

Joystick in port 2 or a CD32 pad:

| Input | Action |
| --- | --- |
| directions | move |
| fire (red) button | shot |
| second (blue) button | second button |

Keyboard:

| Key | Action |
| --- | --- |
| cursor keys | move |
| CTRL or Z | shot |
| SHIFT or X | second button (either SHIFT) |
| P or ESC | pause (press again to continue) |
| M | mouse control on / off |
| `` ` `` (left of 1) | frames-per-second counter on / off (top left) |
| 1, TAB, RETURN, SPACE | as the same keys on the X68000 |

Mouse (after M):

| Input | Action |
| --- | --- |
| movement | move |
| left button | shot |
| right button | second button |

**Mouse control:** in a stage the ship follows the mouse's movement (move
the mouse 3 cm left, the ship goes about as far left) and stops when the
mouse stops. The game shows "mouse on" or "mouse off" for two seconds.

**Auto fire:** holding the shot button keeps shooting (the original game
shot once per press).


## Options

Give options as Shell arguments (`ChoRenSha AGA MUSICVOL=40`) or in the
icon's ARGUMENTS tool type (`ARGUMENTS=AGA MUSICVOL=40`). Mode IDs are
hex; write them as `0x...` (in a Shell, `$` starts a variable).

| Option | Meaning |
| --- | --- |
| `AGA`, `RTG` | The display to use. Default: the graphics card if there is one, otherwise AGA. |
| `MODE=0x<id>` | The graphics card's screen mode (an 8-bit mode of at least 320 x 240; the ID as the ScreenMode preferences list it). Default: the best mode for 320 x 256. |
| `AHI`, `AHI=0x<id>` | Effects and music through AHI (sound cards), in the mode chosen for the music unit in the AHI preferences, or in the mode given. |
| `MHI`, `MHI=<driver>` | Music from the MP3 files on an MHI decoder: `LIBS:MHI/mhiz3660.library`, or the driver given (e.g. `MHI=mhizz9000.library`). Effects stay on Paula (or AHI). |
| `MUSICVOL=<0-64>` | The music's volume (default 64, full). |
| `SFXVOL=<0-64>` | The effects' volume (default 64, full). |

The start-up text shows the screen mode and the sound output in use. If
an option cannot be used (no AGA, no graphics card, an unsuitable mode, no
AHI, no MHI decoder), the start-up text says why and the default is used.

A number (`ChoRenSha 6000`) is for testing: the attract demo runs for
that many frames and the program writes timing measurements to its
drawer.


## Notes

- The game keeps its X68000 timing: 55.46 frames per second, from a CIA
  timer. When a machine cannot show every frame, frames are left out; the
  game does not slow down.
- Music: the original songs (YM2151 FM, for the MCDRV driver) were played
  by MCDRV 0.69 itself and recorded, then streamed from disk: in 8-bit
  stereo at 22 kHz on Paula's channels 2 and 3 (the sound effects use
  channels 0 and 1), or through AHI, or as MP3 on an MHI decoder. The
  songs keep their original levels relative to each other, and loop as on
  the X68000.
- The port's technical notes are in `docs/AMIGA_PORT.md`.


## Credits

- Original game: (c) 1995 Famibe No Yosshin (X68000).
- Atari Falcon port and the disassembly this port builds on: Sascha
  Springer.
- Amiga port: Adam Polkosnik.
- Music recorded with MCDRV 0.69 by CUL (free software), played by the
  Musashi 68000 emulator and rendered with ymfm's YM2151 (Aaron Giles).
