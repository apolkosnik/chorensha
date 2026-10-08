#!/usr/bin/env python3
"""Compare the screenshots of two measurement runs of the Amiga build.

Screenshots (screen_NNNNN*.bin, see screenshot_png.py) are taken at exactly
their frame, so two builds that render the same picture give the same
colours pixel for pixel (palette slots may differ; the RGB values are
compared).

Screenshots are matched by frame number (screen_NNNNN), so runs on different
configs (file names screen_NNNNN-<config>.bin) can be compared, e.g. the
AGA output against RTG.

usage: screenshot_compare.py reference_directory directory
Exits with status 1 if a screenshot differs or is missing.
"""

import glob
import os
import re
import struct
import sys


def by_frame(directory):
    found = {}

    for path in glob.glob(os.path.join(directory, "screen_*.bin")):
        match = re.match(r"screen_(\d+)", os.path.basename(path))

        if match:
            found[int(match.group(1))] = path

    return found


def pixels(path):
    data = open(path, "rb").read()

    if data[:4] != b"CRSS":
        raise SystemExit(f"{path}: not a screenshot")

    width, lines = struct.unpack(">HH", data[4:8])
    palette = data[12:12 + 768]
    indices = data[12 + 768:12 + 768 + width * lines]

    return width, lines, [palette[i * 3:i * 3 + 3] for i in indices]


def main(reference_directory, directory):
    status = 0
    references = by_frame(reference_directory)
    candidates = by_frame(directory)

    if not references:
        raise SystemExit(f"{reference_directory}: no screenshots")

    for frame in sorted(references):
        reference = references[frame]
        name = f"screen_{frame:05d}"
        path = candidates.get(frame)

        if path is None:
            print(f"{name}: missing")
            status = 1
            continue

        width, lines, expected = pixels(reference)
        width2, lines2, actual = pixels(path)

        if (width, lines) != (width2, lines2):
            print(f"{name}: {width2} x {lines2}, reference {width} x {lines}")
            status = 1
            continue

        different = [i for i in range(len(expected)) if expected[i] != actual[i]]

        if different:
            first = different[0]
            print(f"{name}: {len(different)} pixels differ, first at x {first % width} y {first // width}")
            status = 1
        else:
            print(f"{name}: same")

    return status


if len(sys.argv) != 3:
    raise SystemExit(__doc__)

sys.exit(main(sys.argv[1], sys.argv[2]))
