#!/usr/bin/env python3
"""Turns rendered songs (mcdrv_render log + opm_render WAV) into Amiga files.

For each song NAME (NAME.log with the loop times, NAME_full.wav, 62500 Hz):

  NAME.crm      8-bit stream for Paula (and AHI 8-bit stereo):
                header (32 bytes, big-endian):
                  'CRSM', version.w (1), channels.w (2), rate.l (Hz),
                  intro_frames.l, loop_frames.l (0: no loop), block_frames.l,
                  peak.w (before normalising, for information), reserved
                then the intro, then the loop, each cut into blocks of
                block_frames (the last block of each part may be shorter):
                a block is its left samples followed by its right samples
                (signed 8-bit), so Paula's two channels play straight from it.
  NAME_intro.mp3, NAME_loop.mp3   for MHI (MP3 decoder cards).

The intro is the song's first pass up to its loop command, the loop its
second pass (which starts with the tails the loop will have on every repeat).
A song without loop gets its sound until 2 s after its last note.

usage: make_amiga_music.py music_dir output_dir [rate]
"""

import array
import os
import random
import re
import struct
import subprocess
import sys
import wave

SOURCE_RATE = 62500
BLOCK_FRAMES = 4096


def loop_times(log_path):
    text = open(log_path).read()
    loops = [int(t) / 4e6 for t in re.findall(r"^loop (\d+)", text, re.M)]
    writes = [l for l in text.splitlines() if l and l[0].isdigit()]
    last = int(writes[-1].split()[0]) / 4e6 if writes else 0
    return loops, last


def read_wav(path):
    w = wave.open(path)
    assert w.getframerate() == SOURCE_RATE and w.getnchannels() == 2 and w.getsampwidth() == 2
    data = array.array("h", w.readframes(w.getnframes()))

    if sys.byteorder == "big":
        data.byteswap()

    return data


def resample(samples, rate, work):
    """Stereo int16 at SOURCE_RATE -> int16 at rate (ffmpeg, high quality)."""
    raw_in = os.path.join(work, "in.raw")
    raw_out = os.path.join(work, "out.raw")
    samples.tofile(open(raw_in, "wb"))
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-f", "s16le", "-ar", str(SOURCE_RATE),
                    "-ac", "2", "-i", raw_in, "-af", "aresample=resampler=soxr:precision=28",
                    "-ar", str(rate), "-f", "s16le", raw_out], check=True)
    out = array.array("h")
    out.frombytes(open(raw_out, "rb").read())
    return out


def to_8bit(samples, gain):
    """int16 stereo -> signed 8-bit with gain and TPDF dither."""
    rng = random.Random(1)
    out = bytearray(len(samples))

    for i, s in enumerate(samples):
        v = s * gain / 256.0 + rng.random() - rng.random()
        v = int(round(v))
        out[i] = max(-128, min(127, v)) & 0xFF

    return out


def blocks(stereo8):
    """Interleaved stereo bytes -> blocks of left samples then right samples."""
    frames = len(stereo8) // 2
    out = bytearray()

    for start in range(0, frames, BLOCK_FRAMES):
        part = stereo8[2 * start:2 * min(frames, start + BLOCK_FRAMES)]
        out += part[0::2] + part[1::2]

    return out


def mp3(samples, rate, path, work):
    raw = os.path.join(work, "mp3.raw")
    samples.tofile(open(raw, "wb"))
    subprocess.run(["lame", "--quiet", "-r", "-s", str(rate / 1000), "--bitwidth", "16",
                    "--signed", "--little-endian", "-m", "j", "-b", "160", raw, path], check=True)


def main(music_dir, output_dir, rate):
    os.makedirs(output_dir, exist_ok=True)
    work = os.path.join(output_dir, ".work")
    os.makedirs(work, exist_ok=True)

    for log in sorted(f for f in os.listdir(music_dir) if f.endswith(".log")):
        name = log[:-4]
        loops, last = loop_times(os.path.join(music_dir, log))
        full = read_wav(os.path.join(music_dir, name + "_full.wav"))

        if len(loops) >= 2:
            intro_end = loops[0]
            loop_end = loops[1]
        else:
            intro_end = (loops[0] if loops else last) + 2.0
            loop_end = None

        a = int(round(intro_end * SOURCE_RATE))
        intro = full[:2 * a]
        loop = full[2 * a:2 * int(round(loop_end * SOURCE_RATE))] if loop_end else array.array("h")

        intro_r = resample(intro, rate, work)
        loop_r = resample(loop, rate, work) if len(loop) else array.array("h")

        peak = max(max(abs(s) for s in intro_r), max((abs(s) for s in loop_r), default=0))
        gain = 32000.0 / peak if peak else 1.0

        with open(os.path.join(output_dir, name + ".crm"), "wb") as out:
            out.write(b"CRSM" + struct.pack(">HHIIIIH", 1, 2, rate, len(intro_r) // 2, len(loop_r) // 2,
                                            BLOCK_FRAMES, min(peak, 65535)) + bytes(6))
            out.write(blocks(to_8bit(intro_r, gain)))
            out.write(blocks(to_8bit(loop_r, gain)))

        mp3_rate = 44100
        intro_m = resample(intro, mp3_rate, work)
        mp3(array.array("h", (max(-32768, min(32767, int(s * gain))) for s in intro_m)),
            mp3_rate, os.path.join(output_dir, name + "_intro.mp3"), work)

        if len(loop):
            loop_m = resample(loop, mp3_rate, work)
            mp3(array.array("h", (max(-32768, min(32767, int(s * gain))) for s in loop_m)),
                mp3_rate, os.path.join(output_dir, name + "_loop.mp3"), work)

        print(f"{name}: intro {len(intro_r) // 2 / rate:.2f} s, loop {len(loop_r) // 2 / rate:.2f} s, "
              f"gain {gain:.2f}, {os.path.getsize(os.path.join(output_dir, name + '.crm')) // 1024} KB")

    for f in os.listdir(work):
        os.remove(os.path.join(work, f))
    os.rmdir(work)


if len(sys.argv) < 3:
    raise SystemExit(__doc__)

main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 22050)
