#!/usr/bin/env python3
"""Summarise measure.bin files written by the Amiga build (sz2 <frames>).

measure.bin: 'CRSM', E clock frequency (Hz), number of records, then one
record per frame: E clock ticks the game used between two frame waits
(long), sprites in that frame (word), vertical blanks that passed while the
game worked on the frame (word). All big-endian.

usage: measure_summary.py [--timeline] measure.bin [...]
"""

import struct
import sys

X68000_FRAME_MS = 1000.0 / 55.46
PAL_FRAME_MS = 20.0


def percentile(values, fraction):
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))
    return ordered[index]


def summarise(path):
    data = open(path, "rb").read()
    magic, frequency, count = struct.unpack(">4sII", data[:12])

    if magic != b"CRSM":
        raise SystemExit(f"{path}: not a measure.bin file")

    records = [struct.unpack(">IHH", data[12 + 8 * i:20 + 8 * i]) for i in range(count)]
    times = [ticks * 1000.0 / frequency for ticks, _, _ in records]
    sprites = [count for _, count, _ in records]
    overruns = [vblanks for _, _, vblanks in records]

    print(f"{path}: {count} frames, E clock {frequency} Hz")
    print(f"  CPU time per frame (ms): mean {sum(times) / count:.2f}, "
          f"median {percentile(times, 0.5):.2f}, 95% {percentile(times, 0.95):.2f}, "
          f"max {max(times):.2f}")
    print(f"  sprites per frame: mean {sum(sprites) / count:.1f}, "
          f"95% {percentile(sprites, 0.95)}, max {max(sprites)}")
    print(f"  frames over {X68000_FRAME_MS:.2f} ms (X68000 55.46 Hz): "
          f"{sum(t > X68000_FRAME_MS for t in times)}; "
          f"over {PAL_FRAME_MS:.0f} ms (PAL): {sum(t > PAL_FRAME_MS for t in times)}")
    print(f"  frames where a vertical blank passed during the work: "
          f"{sum(v > 0 for v in overruns)}")

    busy = [t for t, s in zip(times, sprites) if s > 0]

    if busy:
        print(f"  frames with sprites: {len(busy)}, CPU time mean {sum(busy) / len(busy):.2f} ms, "
              f"95% {percentile(busy, 0.95):.2f} ms, max {max(busy):.2f} ms")


def timeline(path, block=50):
    data = open(path, "rb").read()
    _, frequency, count = struct.unpack(">4sII", data[:12])
    records = [struct.unpack(">IHH", data[12 + 8 * i:20 + 8 * i]) for i in range(count)]

    print(f"  timeline ({block}-frame blocks): first frame, max sprites, mean CPU ms")

    for start in range(0, count, block):
        part = records[start:start + block]
        times = [ticks * 1000.0 / frequency for ticks, _, _ in part]
        print(f"    {start:6d} {max(s for _, s, _ in part):4d} {sum(times) / len(times):8.2f}")


arguments = sys.argv[1:]
show_timeline = "--timeline" in arguments
arguments = [a for a in arguments if a != "--timeline"]

for name in arguments:
    summarise(name)

    if show_timeline:
        timeline(name)
