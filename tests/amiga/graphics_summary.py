#!/usr/bin/env python3
"""Analyse graphics.bin written by the Amiga build (sz2 <frames>).

graphics.bin: 'CRSG', GVRAM pages 0-1 (2 x 512 x 512 words, 256-colour mode:
the low byte of each word is the graphics palette index, 0 = transparent),
the video controller palettes ($400 bytes: 256 graphics palette words, then
256 sprite/text palette words, X68000 GGGGGRRRRRBBBBBI), the per-pattern
sprite palette usage (2048 words, bit n = drawn with palette n) and the
sprite patterns (16x16, 4 bits per pixel, 128 bytes each: four 8x8 blocks,
top-left, bottom-left, top-right, bottom-right).

It reports what the Amiga renderer needs to know: the palette entries each
layer really uses, how opaque the background pages are, and whether all
layers together fit into one 256-colour palette.

usage: graphics_summary.py graphics.bin
"""

import struct
import sys

GVRAM_PAGE_SIZE = 512 * 512 * 2
PATTERNS = 0x75e


def rgb(word):
    """X68000 palette word -> (r, g, b), 5 bits each (intensity bit ignored)."""
    return ((word >> 6) & 31, (word >> 11) & 31, (word >> 1) & 31)


def pattern_colours(data, index):
    """Colour indices (1-15) used by a 16x16 pattern."""
    colours = set()

    for byte in data[index * 128:(index + 1) * 128]:
        for nibble in (byte >> 4, byte & 15):
            if nibble:
                colours.add(nibble)

    return colours


def main(path):
    data = open(path, "rb").read()

    if data[:4] != b"CRSG":
        raise SystemExit(f"{path}: not a graphics.bin file")

    offset = 4
    gvram = data[offset:offset + 2 * GVRAM_PAGE_SIZE]
    offset += 2 * GVRAM_PAGE_SIZE
    palettes = struct.unpack(">512H", data[offset:offset + 0x400])
    offset += 0x400
    usage = struct.unpack(">2048H", data[offset:offset + 4096])
    offset += 4096
    patterns = data[offset:offset + PATTERNS * 128]

    graphics_palette = palettes[:256]
    sprite_palette = palettes[256:]

    all_colours = set()

    # Background pages: the builder fills 256 x 512 pixels of each page.

    for page in range(2):
        base = page * GVRAM_PAGE_SIZE
        indices = set()
        opaque = 0
        runs = []

        for y in range(512):
            line = gvram[base + y * 1024:base + y * 1024 + 512]
            values = [line[2 * x + 1] for x in range(256)]
            run_count = 0
            previous = 0

            for value in values:
                if value:
                    opaque += 1
                    indices.add(value)

                    if not previous:
                        run_count += 1

                previous = value

            runs.append(run_count)

        colours = {rgb(graphics_palette[i]) for i in indices}
        all_colours |= colours

        print(f"GVRAM page {page}: {len(indices)} palette indices, {len(colours)} colours, "
              f"{100.0 * opaque / (256 * 512):.1f}% opaque, "
              f"opaque runs per line: mean {sum(runs) / len(runs):.1f}, max {max(runs)}")

    # Sprites: (palette, colour) entries that were really drawn.

    entries = set()
    drawn_patterns = 0

    for index in range(PATTERNS):
        palettes_used = usage[index]

        if not palettes_used:
            continue

        drawn_patterns += 1
        colours_used = pattern_colours(patterns, index)

        for palette in range(16):
            if palettes_used & (1 << palette):
                entries |= {palette * 16 + c for c in colours_used}

    sprite_colours = {rgb(sprite_palette[e]) for e in entries}
    all_colours |= sprite_colours

    print(f"sprites: {drawn_patterns} of {PATTERNS} patterns drawn, "
          f"{len(entries)} sprite palette entries, {len(sprite_colours)} colours, "
          f"palettes used: {sorted({e // 16 for e in entries})}")

    # Text layer: sprite/text palette 0.

    text_colours = {rgb(sprite_palette[i]) for i in range(1, 16)}
    all_colours |= text_colours

    print(f"text palette: {len(text_colours)} colours")
    print(f"all layers together: {len(all_colours)} distinct colours "
          f"({'fits' if len(all_colours) <= 256 else 'does not fit'} in 256)")


main(sys.argv[1])
