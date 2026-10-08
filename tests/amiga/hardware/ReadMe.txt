Cho Ren Sha 68k, Amiga port: hardware test kit
==============================================

What it measures

  vram_bench    Opens an 8-bit Picasso96 screen (320 x 256) and times reads,
                writes and copies on the graphics card's memory and in fast
                RAM. This decides whether the game should keep composing
                frames in fast RAM and copying them to the card, or draw
                straight into the card's memory.

  sz2_profile   The game with render profiling. "sz2_profile 6000" runs the
                attract demo for 6000 frames (about 2 minutes), then exits
                and writes the time of each render stage for every frame
                (profile.bin), the game's CPU time per frame (measure.bin),
                game state checkpoints (checkpoints.bin, to check the port
                behaves the same as in emulation), the decoded sound
                effects (samples.bin) and screenshots every 500 frames
                (screen_NNNNN.bin).

Requirements

  68020 or better, AmigaOS 3.x, about 4 MB of free fast RAM, the game's data
  directories, and either a graphics card (Picasso96 or CyberGraphX) or an
  AGA chipset with 8 MB of fast RAM (sz2_profile then uses a native AGA
  screen; vram_bench needs Picasso96 and reports that it cannot run).

How to run

  1. Copy sz2_profile, vram_bench and RunTests into the game's directory
     (the directory with BGM_DAT, ETC_DAT, PCM_DAT and XSP_DAT).
  2. In a Shell:  CD <that directory>
                  Execute RunTests
  3. Send back the files RunTests lists at the end:
       hardware.txt vram_bench.txt profile_run.txt profile.bin measure.bin
       checkpoints.bin samples.bin screen_03000.bin

  RunTests overwrites those files if they exist. The game's screen is
  shown during the demo; it closes by itself after 6000 frames.

Please also note which accelerator and graphics card the machine has (and
the card's Zorro slot type, if it is in a Zorro slot).
