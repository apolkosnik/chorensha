#!/usr/bin/env python3
"""Convert and compare game state checkpoints of the Amiga build.

checkpoints.bin (written by sz2 <frames>): 'CRSC', number of checkpoints,
then 32-byte records every 60 frames: frame (long), score (long), random
table index (word), background scroll counter (word), sprites (word),
padding (word), player structure (14 bytes), padding (2 bytes).

The text form has one line per checkpoint:

    frame score random scroll sprites player-structure-hex

usage:
    checkpoints.py text checkpoints.bin                > run.txt
    checkpoints.py compare reference.txt checkpoints.bin [...]

compare exits with status 1 at the first difference and names the field.
"""

import struct
import sys

FIELDS = ("frame", "score", "random", "scroll", "sprites", "player")


def read_binary(path):
    data = open(path, "rb").read()

    if data[:4] != b"CRSC":
        raise SystemExit(f"{path}: not a checkpoints.bin file")

    count = struct.unpack(">I", data[4:8])[0]
    rows = []

    for index in range(count):
        record = data[8 + 32 * index:8 + 32 * (index + 1)]
        frame, score, random, scroll, sprites = struct.unpack(">IIHHH", record[:14])
        rows.append((frame, score, random, scroll, sprites, record[16:30].hex()))

    return rows


def read_text(path):
    rows = []

    for line in open(path):
        line = line.split("#")[0].split()

        if line:
            rows.append(tuple(int(v) for v in line[:5]) + (line[5],))

    return rows


def read(path):
    return read_binary(path) if open(path, "rb").read(4) == b"CRSC" else read_text(path)


def text(path):
    print("# frame score random scroll sprites player-structure")

    for row in read(path):
        print(" ".join(str(v) for v in row))


def compare(reference_path, paths):
    reference = read(reference_path)
    status = 0

    for path in paths:
        rows = read(path)
        difference = None

        for expected, actual in zip(reference, rows):
            for name, a, b in zip(FIELDS, expected, actual):
                if a != b:
                    difference = (expected[0], name, a, b)
                    break

            if difference:
                break

        if difference:
            frame, name, a, b = difference
            print(f"{path}: differs at frame {frame}: {name} {b} (reference {a})")
            status = 1
        elif len(rows) < len(reference):
            print(f"{path}: matches, but has {len(rows)} of {len(reference)} checkpoints")
            status = 1
        else:
            print(f"{path}: matches {len(reference)} checkpoints")

    return status


if sys.argv[1] == "text":
    text(sys.argv[2])
elif sys.argv[1] == "compare":
    sys.exit(compare(sys.argv[2], sys.argv[3:]))
else:
    raise SystemExit(__doc__)
