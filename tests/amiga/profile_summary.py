#!/usr/bin/env python3
"""Summarise profile.bin files written by -D__RENDER_PROFILE__ builds.

profile.bin: 'CRSP', number of records, then one record per rendered frame:
frame number, then E clock ticks for palette, graphics, text, sprites and
upload (longs, big-endian). The E clock is taken as 709379 Hz (PAL) unless
--eclock is given.

For each stage: median, 95th percentile and maximum in ms; then the frames
over the budget (default 16 ms of rendering) and the mean of each stage in
them, which shows what makes frames late.

usage: profile_summary.py [--eclock HZ] [--budget MS] profile.bin [...]
"""

import struct
import sys

STAGES = ("palette", "graphics", "text", "sprites", "upload")


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, int(round(fraction * (len(ordered) - 1))))]


def summarise(path, eclock, budget):
    data = open(path, "rb").read()

    if data[:4] != b"CRSP":
        raise SystemExit(f"{path}: not a profile.bin file")

    count = struct.unpack(">I", data[4:8])[0]
    records = [struct.unpack(">I5I", data[8 + 24 * i:32 + 24 * i]) for i in range(count)]
    scale = 1000.0 / eclock
    stages = [[r[1 + s] * scale for r in records] for s in range(5)]
    totals = [sum(stage[i] for stage in stages) for i in range(count)]

    print(f"{path}: {count} rendered frames")

    for name, values in zip(STAGES + ("total",), stages + [totals]):
        print(f"  {name:8s} median {percentile(values, 0.5):6.2f}  95% {percentile(values, 0.95):6.2f}"
              f"  max {max(values):7.2f} ms")

    late = [i for i in range(count) if totals[i] > budget]
    print(f"  frames over {budget:.1f} ms: {len(late)}")

    if late:
        means = "  ".join(f"{name} {sum(stages[s][i] for i in late) / len(late):.2f}"
                          for s, name in enumerate(STAGES))
        print(f"  in those frames, mean ms: {means}")


arguments = sys.argv[1:]
eclock = 709379
budget = 16.0

while arguments and arguments[0].startswith("--"):
    option = arguments.pop(0)

    if option == "--eclock":
        eclock = int(arguments.pop(0))
    elif option == "--budget":
        budget = float(arguments.pop(0))
    else:
        raise SystemExit(__doc__)

if not arguments:
    raise SystemExit(__doc__)

for name in arguments:
    summarise(name, eclock, budget)
