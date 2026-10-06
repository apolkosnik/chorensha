#!/usr/bin/env python3
"""Compare the screenshots of two measurement runs of the Amiga build.

Screenshots (screen_NNNNN*.bin, see screenshot_png.py) are taken at exactly
their frame, so two builds that render the same picture give the same
colours pixel for pixel (palette slots may differ; the RGB values are
compared).

usage: screenshot_compare.py reference_directory directory
Exits with status 1 if a screenshot differs or is missing.
"""

import glob
import os
import struct
import sys


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
    references = sorted(glob.glob(os.path.join(reference_directory, "screen_*.bin")))

    if not references:
        raise SystemExit(f"{reference_directory}: no screenshots")

    for reference in references:
        name = os.path.basename(reference)
        path = os.path.join(directory, name)

        if not os.path.exists(path):
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
