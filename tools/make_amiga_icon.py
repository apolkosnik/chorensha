#!/usr/bin/env python3
"""Make the Workbench tool icon (.info) for the Amiga port.

The picture is the red title logo of the game, taken from a title-screen
screenshot of the Amiga build (screen_NNNNN.bin, see tests/amiga/
screenshot_png.py), scaled down and drawn in the four standard Workbench
colours (0 grey, 1 black, 2 white, 3 blue): the logo in white with a black
shadow on grey. The icon is a classic OS 2.x/3.x tool icon (DiskObject,
two-bitplane Image, optional tool types), which every Workbench shows.

usage: make_amiga_icon.py screenshot.bin output.info [TOOLTYPE=value ...]
"""

import struct
import sys

WIDTH = 72  # Icon image size (the logo is fitted into it).
HEIGHT = 38
NO_ICON_POSITION = 0x80000000
STACK_SIZE = 16384


def read_screenshot(path):
    data = open(path, "rb").read()

    if data[:4] != b"CRSS":
        raise SystemExit(f"{path}: not a screenshot")

    width, lines = struct.unpack(">HH", data[4:8])
    palette = data[12:12 + 768]
    pixels = data[12 + 768:12 + 768 + width * lines]

    return width, lines, palette, pixels


def logo_mask(path):
    """Coverage of red logo pixels, cropped to the logo."""
    width, lines, palette, pixels = read_screenshot(path)

    def red(x, y):
        i = pixels[y * width + x]
        r, g, b = palette[i * 3:i * 3 + 3]
        return r > 150 and g < 90 and b < 90

    top = lines // 2
    points = [(x, y) for y in range(top) for x in range(width) if red(x, y)]

    if not points:
        raise SystemExit(f"{path}: no red title logo found")

    x0 = min(p[0] for p in points)
    x1 = max(p[0] for p in points) + 1
    y0 = min(p[1] for p in points)
    y1 = max(p[1] for p in points) + 1

    return [[red(x, y) for x in range(x0, x1)] for y in range(y0, y1)]


def scale(mask, width, height):
    """Area coverage into width x height (keeping the aspect ratio)."""
    source_height = len(mask)
    source_width = len(mask[0])
    factor = max(source_width / width, source_height / height)
    out_width = int(source_width / factor)
    out_height = int(source_height / factor)
    out = [[False] * out_width for _ in range(out_height)]

    for y in range(out_height):
        for x in range(out_width):
            sx0, sx1 = int(x * factor), max(int(x * factor) + 1, int((x + 1) * factor))
            sy0, sy1 = int(y * factor), max(int(y * factor) + 1, int((y + 1) * factor))
            cells = [mask[sy][sx] for sy in range(sy0, sy1) for sx in range(sx0, sx1)]
            out[y][x] = sum(cells) / len(cells) >= 0.3

    return out


def picture(mask):
    """Colour indices: logo white (2), its shadow black (1), grey (0)."""
    height = len(mask) + 2
    width = len(mask[0]) + 2
    image = [[0] * width for _ in range(height)]

    for y, row in enumerate(mask):
        for x, set_ in enumerate(row):
            if set_:
                image[y + 2][x + 2] = 1

    for y, row in enumerate(mask):
        for x, set_ in enumerate(row):
            if set_:
                image[y + 1][x + 1] = 2

    return image


def planes(image):
    height = len(image)
    width = len(image[0])
    row_bytes = (width + 15) // 16 * 2
    data = bytearray()

    for plane in range(2):
        for y in range(height):
            row = bytearray(row_bytes)

            for x in range(width):
                if image[y][x] >> plane & 1:
                    row[x // 8] |= 0x80 >> (x % 8)

            data += row

    return data


def disk_object(image, tool_types):
    height = len(image)
    width = len(image[0])

    gadget = struct.pack(">IhhhhHHHIIIIIHI",
                         0,           # NextGadget
                         0, 0,        # LeftEdge, TopEdge
                         width, height + 1,
                         4,           # Flags: GFLG_GADGIMAGE, complement highlight
                         3,           # Activation: RELVERIFY | GADGIMMEDIATE
                         1,           # GadgetType: BOOLGADGET
                         1,           # GadgetRender (an Image follows)
                         0, 0, 0, 0,  # SelectRender, GadgetText, MutualExclude, SpecialInfo
                         0,           # GadgetID
                         1)           # UserData: revision 1 (OS 2.x icon)
    header = struct.pack(">HH", 0xE310, 1) + gadget + struct.pack(
        ">BBIIIIIII",
        3, 0,                        # Type WBTOOL, pad
        0,                           # DefaultTool
        1 if tool_types else 0,      # ToolTypes (present)
        NO_ICON_POSITION, NO_ICON_POSITION,
        0, 0,                        # DrawerData, ToolWindow
        STACK_SIZE)

    image_header = struct.pack(">hhhhhIBBI", 0, 0, width, height, 2, 1, 3, 0, 0)
    data = header + image_header + planes(image)

    if tool_types:
        data += struct.pack(">I", (len(tool_types) + 1) * 4)

        for text in tool_types:
            encoded = text.encode("latin-1") + b"\0"
            data += struct.pack(">I", len(encoded)) + encoded

    assert len(header) == 78
    return bytes(data)


def main(screenshot, output, tool_types):
    image = picture(scale(logo_mask(screenshot), WIDTH - 2, HEIGHT - 2))
    open(output, "wb").write(disk_object(image, tool_types))
    print(f"{output}: {len(image[0])} x {len(image)} icon, {len(tool_types)} tool types")


if len(sys.argv) < 3:
    raise SystemExit(__doc__)

main(sys.argv[1], sys.argv[2], sys.argv[3:])
