#!/usr/bin/env python3
"""Build an input script for the Amiga build (sz2 <frames> <script>).

Text input, one step per line:

    <frame> <controls>             joystick held from that frame on
    tick <tick> <controls>         joystick held from that frame timer tick
                                   on (55.46 per second, counted from the
                                   start; for input while the game completes
                                   no frames, as in its wait loops)
    <frame> key <name> press       a key event through input.device
    <frame> key <name> release
    tick <tick> key <name> press   a key event at a frame timer tick
    tick <tick> key <name> release
    <frame> mouse <x> <y>          the mouse pointer at (x, y) in the
                                   256 x 256 picture from that frame on
                                   (used in place of the real pointer)
    <frame> mouse left|right press|release
                                   a mouse button event through input.device

Controls: up, down, left, right, a (trigger A), b (trigger B), or - for
nothing; several can be combined with '+' (up+a). Key names: see KEYS
(Amiga raw keys). Lines starting with '#' are comments.

Output: 'CRSI', number of records, then 8-byte records: frame or tick
(long), kind (0 joystick, 1 key, 2 joystick at a tick, 3 key at a tick,
4 mouse position, 5 mouse button), value (joystick byte, active low X68000
bits; raw key code or mouse button code with bit 7 set for a release; the
mouse x), extra byte (the mouse y), padding. All big-endian.

usage: make_input_script.py input.txt input.bin
"""

import struct
import sys

BITS = {"up": 0, "down": 1, "left": 2, "right": 3, "a": 5, "b": 6}

KEYS = {"1": 0x01, "z": 0x31, "x": 0x32, "space": 0x40, "tab": 0x42, "return": 0x44,
        "esc": 0x45, "up": 0x4c, "down": 0x4d, "right": 0x4e, "left": 0x4f,
        "p": 0x19, "m": 0x37, "lshift": 0x60, "rshift": 0x61, "ctrl": 0x63}


def main(source, destination):
    records = []

    for number, line in enumerate(open(source), 1):
        line = line.split("#")[0].strip()

        if not line:
            continue

        words = line.split()
        kind = 0

        if words[0] == "tick":
            kind = 2
            words = words[1:]

        frame = int(words[0])

        if words[1] == "mouse":
            if words[2] in ("left", "right") and len(words) == 4 and words[3] in ("press", "release"):
                code = (0x68 if words[2] == "left" else 0x69) | (0x80 if words[3] == "release" else 0)
                records.append((frame, number, 5, code, 0))
            elif len(words) == 4:
                records.append((frame, number, 4, int(words[2]), int(words[3])))
            else:
                raise SystemExit(f"{source}:{number}: bad mouse event '{line}'")

            continue

        if words[1] == "key":
            name, action = words[2], words[3]

            if name not in KEYS or action not in ("press", "release"):
                raise SystemExit(f"{source}:{number}: bad key event '{line}'")

            records.append((frame, number, 3 if kind else 1, KEYS[name] | (0x80 if action == "release" else 0), 0))

            continue

        joystick = 0xff

        if words[1] != "-":
            for control in words[1].split("+"):
                if control not in BITS:
                    raise SystemExit(f"{source}:{number}: unknown control '{control}'")

                joystick &= ~(1 << BITS[control])

        records.append((frame, number, kind, joystick, 0))

    records.sort()

    with open(destination, "wb") as output:
        output.write(b"CRSI" + struct.pack(">I", len(records)))

        for frame, _, kind, value, extra in records:
            output.write(struct.pack(">IBBBx", frame, kind, value, extra))


main(*sys.argv[1:3])
