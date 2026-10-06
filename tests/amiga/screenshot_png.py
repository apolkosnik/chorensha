#!/usr/bin/env python3
"""Convert screen_NNNNN.bin screenshots of the Amiga build to PNG.

screen_NNNNN.bin: 'CRSS', width (word), lines (word), colours (word),
padding (word), 256 x R, G, B (bytes), then width x lines palette indices.

usage: screenshot_png.py screen_00500.bin [...]   (writes screen_00500.png)
"""

import struct
import sys
import zlib


def png(path, width, height, rows):
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))

    raw = b"".join(b"\x00" + row for row in rows)

    with open(path, "wb") as output:
        output.write(b"\x89PNG\r\n\x1a\n")
        output.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)))
        output.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        output.write(chunk(b"IEND", b""))


def convert(path):
    data = open(path, "rb").read()

    if data[:4] != b"CRSS":
        raise SystemExit(f"{path}: not a screenshot")

    width, lines, colours = struct.unpack(">HHH", data[4:10])
    palette = data[12:12 + 768]
    pixels = data[12 + 768:12 + 768 + width * lines]

    rows = []

    for y in range(lines):
        row = bytearray()

        for index in pixels[y * width:(y + 1) * width]:
            row += palette[index * 3:index * 3 + 3]

        rows.append(bytes(row))

    target = path.rsplit(".", 1)[0] + ".png"
    png(target, width, lines, rows)
    print(f"{target}: {width} x {lines}, {colours} colours")


for name in sys.argv[1:]:
    convert(name)
