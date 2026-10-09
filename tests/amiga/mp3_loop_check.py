#!/usr/bin/env python3
"""Check the MHI music files (tools/music/make_amiga_music.py) for gapless
looping, as an MHI decoder plays them: NAME_intro.mp3, then NAME_loop.mp3
again and again, as one stream of frames.

For every song with a loop, intro + loop x 3 is decoded (ffmpeg) and the
decoded audio around each place where the loop file starts again is
compared with the audio one loop period earlier, where the stream ran on
without a seam (the loop is a whole number of 1152-sample frames, so the
period is exact). Around a seamless restart the two match to within the
encoder's noise: the signal-to-difference ratio must be at least
MINIMUM_SNR dB in a window of WINDOW samples on both sides of the seam.

usage: mp3_loop_check.py music_dir
Exits with status 1 if any song fails.
"""

import os
import subprocess
import sys

import numpy as np

FRAME = 1152
WINDOW = 2048
MINIMUM_SNR = 20.0


def mp3_frame_count(data):
    bitrates = (0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320)
    rates = (44100, 48000, 32000)
    position = count = 0

    while position + 4 <= len(data):
        header = int.from_bytes(data[position:position + 4], "big")
        assert header >> 21 == 0x7ff, f"no frame header at {position}"
        position += 144 * bitrates[(header >> 12) & 15] * 1000 // rates[(header >> 10) & 3] + ((header >> 9) & 1)
        count += 1

    assert position == len(data)
    return count


def decode(data):
    result = subprocess.run(["ffmpeg", "-loglevel", "error", "-f", "mp3", "-i", "pipe:0", "-f", "s16le",
                             "-ac", "2", "-ar", "44100", "pipe:1"], input=data, capture_output=True, check=True)
    return np.frombuffer(result.stdout, "<i2").reshape(-1, 2).astype(np.float64)


def main(music_dir):
    failures = 0

    for name in sorted(f[:-10] for f in os.listdir(music_dir) if f.endswith("_intro.mp3")):
        loop_path = os.path.join(music_dir, name + "_loop.mp3")

        if not os.path.exists(loop_path):
            print(f"{name}: no loop")
            continue

        intro = open(os.path.join(music_dir, name + "_intro.mp3"), "rb").read()
        loop = open(loop_path, "rb").read()
        intro_frames = mp3_frame_count(intro)
        period = mp3_frame_count(loop) * FRAME
        audio = decode(intro + loop * 3)

        # The loop file's restarts, in decoded samples (the decoder's delay
        # shifts both compared windows alike).

        results = []

        for k in (1, 2):
            seam = intro_frames * FRAME + k * period
            here = audio[seam - WINDOW:seam + WINDOW]
            before = audio[seam - period - WINDOW:seam - period + WINDOW]
            difference = here - before
            snr = 10 * np.log10(np.sum(before ** 2) / max(np.sum(difference ** 2), 1e-9))
            results.append(snr)

        ok = all(snr >= MINIMUM_SNR for snr in results)

        if not ok:
            failures += 1

        print(f"{name}: period {period} samples ({period / 44100:.3f} s), seams: "
              + ", ".join(f"{snr:.1f} dB" for snr in results) + ("" if ok else "  FAIL"))

    return 1 if failures else 0


if len(sys.argv) != 2:
    raise SystemExit(__doc__)

sys.exit(main(sys.argv[1]))
