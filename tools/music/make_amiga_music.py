#!/usr/bin/env python3
"""Turns rendered songs (mcdrv_render log + opm_render WAV) into Amiga files.

For each song NAME (NAME.log with the loop times, NAME_full.wav, 62500 Hz):

  NAME.crm      8-bit stream for Paula (and AHI 8-bit stereo):
                header (32 bytes, big-endian):
                  'CRSM', version.w (1), channels.w (2), rate.l (Hz),
                  intro_frames.l, loop_frames.l (0: no loop), block_frames.l,
                  peak.w (before normalising, for information),
                  fade_unit.w (MCDRV _FADEOUT length per unit of speed, in
                  1/10000 s: the fade lasts speed * fade_unit),
                  level.w (the song's original peak relative to the loudest
                  song's, 1-64: every file is normalised, the player plays
                  it at this volume to restore the songs' relative levels),
                  reserved
                then the intro, then the loop, each cut into blocks of
                block_frames (the last block of each part may be shorter):
                a block is its left samples followed by its right samples
                (signed 8-bit), so Paula's two channels play straight from it.
                All frame counts are even (Paula plays words).
  NAME_intro.mp3, NAME_loop.mp3   for MHI (MP3 decoder cards): 44100 Hz,
                160 kbit/s CBR, no LAME tag, no bit reservoir. Played as the
                intro file, then the loop file again and again, the frames
                join without a gap: the loop is resampled (by FFT, as the
                periodic signal it is) to a whole number of MP3 frames (1152
                samples), the intro is padded at its start to whole frames,
                and intro + loop x 3 is encoded as one stream; the intro file
                is its frames up to the end of the first loop pass, the loop
                file one loop period of frames from the second pass, which
                follows itself as it follows the first pass.

The intro is the song's first pass up to its loop command, the loop its
second pass (which starts with the tails the loop will have on every repeat).
A song without loop gets its sound until 2 s after its last note.

The fade length comes from NAME.fade.log: the song with _FADEOUT (speed
FADE_SPEED, short enough for SZ2_TMP to last; speeds 4 and 16 give the
same length per unit within 1 %) at 1 s; MCDRV's last register write ends the fade (it then sets
every operator to silence). MCDRV fades by one step of total level (0.75 dB)
every speed ticks of the song's timer, 64 steps in all.

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
FADE_AT = 1.0
FADE_SPEED = 4


def loop_times(log_path):
    text = open(log_path).read()
    loops = [int(t) / 4e6 for t in re.findall(r"^loop (\d+)", text, re.M)]
    writes = [l for l in text.splitlines() if l and l[0].isdigit()]
    last = int(writes[-1].split()[0]) / 4e6 if writes else 0
    return loops, last


def fade_unit(log_path):
    """Fade length per unit of speed, in 1/10000 s."""
    text = open(log_path).read()
    fade = int(re.search(r"^fade (\d+) (\d+)", text, re.M).group(1)) / 4e6
    assert abs(fade - FADE_AT) < 0.1
    assert not re.search(r"^end ", text, re.M), log_path + ": the song ended before the fade"
    last = max(int(l.split()[0]) for l in text.splitlines()
               if l and l[0].isdigit() and l.split()[1] not in ("10", "11", "14")) / 4e6	# Not the timer.
    return int(round((last - fade) / FADE_SPEED * 10000))


def even_parts(intro, loop):
    """Even frame counts: an odd intro takes the loop's first frame (the loop
    is rotated by one, so it still joins itself); an odd loop loses its last
    frame; an odd intro without loop gets a silent frame."""
    if len(intro) // 2 % 2:
        if len(loop):
            intro = intro + loop[:2]
            loop = loop[2:] + loop[:2]
        else:
            intro = intro + array.array("h", [0, 0])

    if len(loop) // 2 % 2:
        loop = loop[:-2]

    return intro, loop


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


MP3_FRAME = 1152


def mp3_frames(data):
    """Split MPEG-1 layer III data (no tags) into frames."""
    frames = []
    position = 0
    rates = (44100, 48000, 32000)
    bitrates = (0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)

    while position + 4 <= len(data):
        header = int.from_bytes(data[position:position + 4], "big")
        assert header >> 21 == 0x7ff and (header >> 19) & 3 == 3 and (header >> 17) & 3 == 1, hex(header)
        bitrate = bitrates[(header >> 12) & 15] * 1000
        rate = rates[(header >> 10) & 3]
        padding = (header >> 9) & 1
        length = 144 * bitrate // rate + padding
        frames.append(data[position:position + length])
        position += length

    assert position == len(data)
    return frames


def mp3_intro_loop(intro, loop, gain, intro_path, loop_path, work):
    """Gapless MP3 intro and loop files (see the module documentation).
    intro, loop: interleaved int16 stereo at 44100 Hz."""
    import numpy as np
    from scipy.signal import resample as fft_resample

    def frames_of(samples, multiple):
        return np.asarray(samples, dtype=np.float64).reshape(-1, 2) * gain

    intro_s = frames_of(intro, 1)
    pad = (-len(intro_s)) % MP3_FRAME
    intro_s = np.concatenate([np.zeros((pad, 2)), intro_s])
    parts = [intro_s]
    loop_frames = 0

    if len(loop):
        loop_s = frames_of(loop, 1)
        loop_frames = max(1, int(round(len(loop_s) / MP3_FRAME)))
        loop_s = fft_resample(loop_s, loop_frames * MP3_FRAME, axis=0)
        parts += [loop_s] * 3

    stream = np.clip(np.round(np.concatenate(parts)), -32768, 32767).astype("<i2")
    raw = os.path.join(work, "mp3.raw")
    encoded = os.path.join(work, "mp3.mp3")
    stream.tofile(raw)
    subprocess.run(["lame", "--quiet", "-r", "-s", "44.1", "--bitwidth", "16", "--signed", "--little-endian",
                    "-m", "j", "--cbr", "-b", "160", "-t", "--nores", raw, encoded], check=True)
    frames = mp3_frames(open(encoded, "rb").read())
    intro_end = len(intro_s) // MP3_FRAME + loop_frames

    with open(intro_path, "wb") as out:
        out.write(b"".join(frames[:intro_end if loop_frames else len(frames)]))

    if loop_frames:
        with open(loop_path, "wb") as out:
            out.write(b"".join(frames[intro_end:intro_end + loop_frames]))

    return pad, loop_frames


def song_parts(music_dir, name):
    """The song's intro and loop at SOURCE_RATE (interleaved int16)."""
    loops, last = loop_times(os.path.join(music_dir, name + ".log"))
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
    return intro, loop


def main(music_dir, output_dir, rate):
    os.makedirs(output_dir, exist_ok=True)
    work = os.path.join(output_dir, ".work")
    os.makedirs(work, exist_ok=True)
    names = [f[:-4] for f in sorted(os.listdir(music_dir)) if f.endswith(".log") and not f.endswith(".fade.log")]

    # The songs' original peaks, for their levels relative to the loudest.

    peaks = {}

    for name in names:
        intro, loop = song_parts(music_dir, name)
        peaks[name] = max(max(intro), -min(intro), max(loop, default=0), -min(loop, default=0))

    loudest = max(peaks.values())

    for name in names:
        intro, loop = song_parts(music_dir, name)
        level = max(1, int(round(64 * peaks[name] / loudest)))

        intro_r = resample(intro, rate, work)
        loop_r = resample(loop, rate, work) if len(loop) else array.array("h")
        intro_r, loop_r = even_parts(intro_r, loop_r)
        unit = fade_unit(os.path.join(music_dir, name + ".fade.log"))

        peak = max(max(abs(s) for s in intro_r), max((abs(s) for s in loop_r), default=0))
        gain = 32000.0 / peak if peak else 1.0

        with open(os.path.join(output_dir, name + ".crm"), "wb") as out:
            out.write(b"CRSM" + struct.pack(">HHIIIIHHH", 1, 2, rate, len(intro_r) // 2, len(loop_r) // 2,
                                            BLOCK_FRAMES, min(peak, 65535), unit, level) + bytes(2))
            out.write(blocks(to_8bit(intro_r, gain)))
            out.write(blocks(to_8bit(loop_r, gain)))

        mp3_rate = 44100
        intro_m = resample(intro, mp3_rate, work)
        loop_m = resample(loop, mp3_rate, work) if len(loop) else array.array("h")
        loop_path = os.path.join(output_dir, name + "_loop.mp3")

        if os.path.exists(loop_path):
            os.remove(loop_path)

        mp3_intro_loop(intro_m, loop_m, gain, os.path.join(output_dir, name + "_intro.mp3"), loop_path, work)

        print(f"{name}: intro {len(intro_r) // 2 / rate:.2f} s, loop {len(loop_r) // 2 / rate:.2f} s, "
              f"gain {gain:.2f}, level {level}, fade {unit / 10000:.3f} s per speed unit, {os.path.getsize(os.path.join(output_dir, name + '.crm')) // 1024} KB")

    for f in os.listdir(work):
        os.remove(os.path.join(work, f))
    os.rmdir(work)


if len(sys.argv) < 3:
    raise SystemExit(__doc__)

main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 22050)
