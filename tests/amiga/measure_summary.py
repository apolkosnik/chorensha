#!/usr/bin/env python3
"""Summarise measure.bin files written by the Amiga build (sz2 <frames>).

measure.bin: 'CRS2' (or the older 'CRSM'), E clock frequency (Hz), number
of records, then one record per frame: E clock ticks the game used between
two frame waits (long), E clock ticks for rendering and display ('CRS2'
only, long), sprites in that frame (word), vertical blanks that passed while
the game worked on the frame (word). All big-endian.

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


def read_records(path):
    """-> (frequency, [(game ticks, render ticks, sprites, vblanks)])."""
    data = open(path, "rb").read()
    magic, frequency, count = struct.unpack(">4sII", data[:12])

    if magic == b"CRSM":
        records = [struct.unpack(">IHH", data[12 + 8 * i:20 + 8 * i]) for i in range(count)]
        return frequency, [(g, 0, s, v) for g, s, v in records]

    if magic == b"CRS2":
        return frequency, [struct.unpack(">IIHH", data[12 + 12 * i:24 + 12 * i]) for i in range(count)]

    raise SystemExit(f"{path}: not a measure.bin file")


def summarise(path):
    frequency, records = read_records(path)
    count = len(records)
    times = [ticks * 1000.0 / frequency for ticks, _, _, _ in records]
    render = [ticks * 1000.0 / frequency for _, ticks, _, _ in records]
    sprites = [count for _, _, count, _ in records]
    overruns = [vblanks for _, _, _, vblanks in records]

    print(f"{path}: {count} frames, E clock {frequency} Hz")
    print(f"  CPU time per frame (ms): mean {sum(times) / count:.2f}, "
          f"median {percentile(times, 0.5):.2f}, 95% {percentile(times, 0.95):.2f}, "
          f"max {max(times):.2f}")
    if any(render):
        total = [t + r for t, r in zip(times, render)]
        print(f"  rendering + display per frame (ms): mean {sum(render) / count:.2f}, "
              f"median {percentile(render, 0.5):.2f}, 95% {percentile(render, 0.95):.2f}, "
              f"max {max(render):.2f}")
        print(f"  game + rendering, 95%: {percentile(total, 0.95):.2f} ms; frames over "
              f"{X68000_FRAME_MS:.2f} ms: {sum(t > X68000_FRAME_MS for t in total)}")

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
    frequency, records = read_records(path)

    print(f"  timeline ({block}-frame blocks): first frame, max sprites, mean game ms, mean render ms")

    for start in range(0, len(records), block):
        part = records[start:start + block]
        times = [g * 1000.0 / frequency for g, _, _, _ in part]
        render = [r * 1000.0 / frequency for _, r, _, _ in part]
        print(f"    {start:6d} {max(s for _, _, s, _ in part):4d} {sum(times) / len(times):8.2f} "
              f"{sum(render) / len(render):8.2f}")


arguments = sys.argv[1:]
show_timeline = "--timeline" in arguments
arguments = [a for a in arguments if a != "--timeline"]

for name in arguments:
    summarise(name)

    if show_timeline:
        timeline(name)
