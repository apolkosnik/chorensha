Cho Ren Sha 68k - Amiga port
============================

Cho Ren Sha 68k is a vertical shoot 'em up for the Sharp X68000, (c) 1995
by Famibe No Yosshin. This is a port of the original game code to the
Commodore Amiga: the X68000 program runs on the 68020+ with the X68000's
hardware emulated in software, and its picture is shown on a graphics
card (RTG) or on the AGA chipset.

Work in progress: sound effects and music are in.


Requirements
------------

  - AmigaOS 3.x, a 68020 or better.
  - Either a graphics card with Picasso96 or CyberGraphX (8-bit screen,
    320 x 256 or 320 x 240), or an AGA Amiga (A1200, A4000, CD32 with
    expansion) with at least 8 MB of fast RAM.
  - About 3 MB of free fast RAM and 0.6 MB of chip RAM for the sounds.
  - For the music, 100 MB of disk space (MUSIC_DAT: 66 MB of streams, and
    34 MB of MP3 files for MHI, which may be deleted without MHI) and a
    hard disk or other storage that reads 44 KB per second while the game
    runs.

Speed: the game itself runs at full speed (55 frames per second) on every
supported machine; how many of those frames are shown depends on the
machine. A 68030 at 50 MHz with a graphics card shows about 40 per second;
a stock A1200 (68020 at 14 MHz, AGA) about 5.

If a graphics card is present it is used; otherwise the AGA screen.


Installation and start
----------------------

Copy the ChoRenSha drawer anywhere (hard disk or RAM:) and double-click the
ChoRenSha icon, or start it from a Shell:

  CD ChoRenSha
  ChoRenSha

The program needs its data drawers (BGM_DAT, ETC_DAT, PCM_DAT, XSP_DAT)
next to it. MUSIC_DAT holds the music: without it (delete or rename it,
e.g. to run from a small disk), the game runs without music. Started from
Workbench, its messages appear in a small window, which stays open after
the game has ended until you close it.


Controls
--------

  Joystick in port 2 or a CD32 pad:
    directions             move
    fire (red) button      shot
    second (blue) button   second button

  Keyboard:
    cursor keys            move
    CTRL or Z              shot
    SHIFT or X             second button (either SHIFT)
    P or ESC               pause (press again to continue)
    M                      mouse control on / off

  Mouse control (M): in a stage the ship follows the mouse's movement
  (move the mouse 3 cm left, the ship goes about as far left) and stops
  when the mouse stops; the left mouse button shoots, the
  right one is the second button. The game shows "mouse on" or "mouse
  off" for two seconds.

  Auto fire: holding the shot button (fire, CTRL, Z or the left mouse
  button) keeps shooting; the original game shot once per press.
    ESC, 1, TAB, RETURN, SPACE work as the same keys on the X68000.

To quit, choose EXIT in the game's menu.


Notes
-----

  - The game keeps its X68000 timing: 55.46 frames per second, from a CIA
    timer. When a machine cannot show every frame, frames are left out,
    the game does not slow down.
  - Shell arguments (or the ARGUMENTS tool type of the icon) are for
    testing: "ChoRenSha 6000" plays the attract demo for 6000 frames and
    writes timing measurements to the current directory.
  - Music: the original songs (YM2151 FM, for the MCDRV driver) were
    played by MCDRV 0.69 (CUL, free software) and recorded, and are
    streamed from disk in 8-bit stereo at 22 kHz on Paula's channels 2
    and 3; the sound effects use channels 0 and 1.
  - Sound cards: with the argument AHI (Shell: "ChoRenSha AHI", or the
    tool type ARGUMENTS=AHI) the effects and the music play through AHI,
    in the audio mode chosen for the music unit in the AHI preferences;
    AHI=0x<mode id> picks a mode (the IDs are listed by AHI's
    preferences program). Without AHI, or if it cannot be opened, Paula
    plays them. The line "Sound: AHI, ..." at the start shows the mode.
  - MP3 decoder cards: with the argument MHI the music plays from the MP3
    files in MUSIC_DAT on an MHI decoder (LIBS:MHI/mhiz3660.library), or
    MHI=<driver> with another MHI driver (e.g. MHI=mhizz9000.library). If
    the driver cannot be opened or has no decoder, the game says so and
    plays the music as usual. Effects stay on Paula (or AHI with AHI).
  - Volume: MUSICVOL=<0-64> and SFXVOL=<0-64> (arguments or ARGUMENTS
    tool type, e.g. "ChoRenSha MUSICVOL=40") set the music's and the
    effects' volume; both default to 64 (full). The songs keep their
    original levels relative to each other.


Credits
-------

  Original game: (c) 1995 Famibe No Yosshin (X68000).
  Atari Falcon port and the disassembly this port builds on: Sascha
  Springer.
  Amiga port: Adam Polkosnik.
