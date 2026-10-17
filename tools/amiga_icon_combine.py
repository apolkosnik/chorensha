#!/usr/bin/env python3
"""Combine a classic Workbench icon with the colour images of another.

OS 3.5+ colour icons keep their images in an IFF "FORM ICON" chunk after the
classic icon (the DiskObject, its planar images and its strings); older
Workbenches show the classic images. This takes the classic part from one
icon, its type, stack and drawer window from the options, and the colour
images from another icon, unchanged:

    amiga_icon_combine.py --classic logo.info --colour art.info
        [--type tool|drawer] [--stack N] [--drawer-from drawer.info]
        [--tool-type TEXT ...] output.info

The result has no default tool, and only the tool types given (so the
editor's leftovers in the colour icon, such as FILETYPE=ICON, are not
kept). A drawer icon
takes its window (DrawerData, and the OS 2.x DrawerData2 view settings) from
--drawer-from, or from --classic if that is a drawer icon.

Used for the colour icons made for the port by Hexaae: the game's icon keeps
the logo icon of make_amiga_icon.py as its classic image (Hexaae's has an
8 x 8 placeholder there), the drawer icon Hexaae's own classic images.
"""

import argparse
import re
import struct

WBDRAWER = 2
WBTOOL = 3
HEADER_SIZE = 78  # do_Magic ... do_StackSize
DRAWER_DATA_SIZE = 56  # NewWindow, dd_CurrentX, dd_CurrentY
DRAWER_DATA2_SIZE = 6  # dd_Flags, dd_ViewModes
IMAGE_SIZE = 20


def parse(path):
    """The parts of an icon file: header, drawer data, images, drawer data 2,
    colour chunk."""

    data = open(path, "rb").read()
    magic, version = struct.unpack_from(">HH", data, 0)

    if magic != 0xE310:
        raise SystemExit(f"{path}: not an icon")

    render, select = struct.unpack_from(">II", data, 22)
    user_data = struct.unpack_from(">I", data, 44)[0]
    default_tool, tool_types = struct.unpack_from(">II", data, 50)
    drawer, tool_window = struct.unpack_from(">II", data, 66)
    position = HEADER_SIZE
    parts = {"header": data[:HEADER_SIZE], "drawer": None, "drawer2": None}

    if drawer:
        parts["drawer"] = data[position:position + DRAWER_DATA_SIZE]
        position += DRAWER_DATA_SIZE

    images_start = position

    for present in (render, select):
        if present:
            width, height, depth = struct.unpack_from(">hhh", data, position + 4)
            position += IMAGE_SIZE + (width + 15) // 16 * 2 * height * depth

    parts["images"] = data[images_start:position]

    def skip_string():
        nonlocal position
        length = struct.unpack_from(">I", data, position)[0]
        position += 4 + length

    if default_tool:
        skip_string()

    if tool_types:
        count = struct.unpack_from(">I", data, position)[0] // 4 - 1
        position += 4

        for _ in range(count):
            skip_string()

    if tool_window:
        skip_string()

    if drawer and user_data & 0xFF == 1:
        parts["drawer2"] = data[position:position + DRAWER_DATA2_SIZE]
        position += DRAWER_DATA2_SIZE

    parts["colour"] = None

    for match in re.finditer(b"FORM", data[position:]):
        start = position + match.start()

        if data[start + 8:start + 12] == b"ICON":
            length = struct.unpack_from(">I", data, start + 4)[0]
            parts["colour"] = data[start:start + 8 + length + (length & 1)]
            break

    return parts


def main():
    arguments = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    arguments.add_argument("--classic", required=True)
    arguments.add_argument("--colour", required=True)
    arguments.add_argument("--type", choices=("tool", "drawer"))
    arguments.add_argument("--stack", type=int)
    arguments.add_argument("--drawer-from")
    arguments.add_argument("--tool-type", action="append", default=[])
    arguments.add_argument("output")
    options = arguments.parse_args()

    classic = parse(options.classic)
    colour = parse(options.colour)

    if colour["colour"] is None:
        raise SystemExit(f"{options.colour}: no colour images (FORM ICON)")

    header = bytearray(classic["header"])
    icon_type = header[48]

    if options.type:
        icon_type = WBDRAWER if options.type == "drawer" else WBTOOL

    drawer = drawer2 = None

    if icon_type == WBDRAWER:
        source = parse(options.drawer_from) if options.drawer_from else classic

        if source["drawer"] is None:
            raise SystemExit("a drawer icon needs --drawer-from with a drawer icon")

        drawer = source["drawer"]
        drawer2 = source["drawer2"] or bytes(DRAWER_DATA2_SIZE)

    header[48] = icon_type
    struct.pack_into(">I", header, 44, 1)  # Gadget UserData: revision 1 (DrawerData2).
    struct.pack_into(">II", header, 50, 0, 1 if options.tool_type else 0)  # No default tool.
    struct.pack_into(">ii", header, 58, -0x80000000, -0x80000000)  # NO_ICON_POSITION.
    struct.pack_into(">II", header, 66, 1 if drawer else 0, 0)

    if options.stack is not None:
        struct.pack_into(">i", header, 74, options.stack)
    elif icon_type == WBDRAWER:
        struct.pack_into(">i", header, 74, 0)

    with open(options.output, "wb") as output:
        output.write(header)

        if drawer:
            output.write(drawer)

        output.write(classic["images"])

        if options.tool_type:
            output.write(struct.pack(">I", 4 * (len(options.tool_type) + 1)))

            for text in options.tool_type:
                encoded = text.encode("latin-1") + b"\0"
                output.write(struct.pack(">I", len(encoded)) + encoded)

        if drawer:
            output.write(drawer2)

        output.write(colour["colour"])


main()
