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

Controls: up, down, left, right, a (trigger A), b (trigger B), or - for
nothing; several can be combined with '+' (up+a). Key names: see KEYS
(Amiga raw keys). Lines starting with '#' are comments.

Output: 'CRSI', number of records, then 8-byte records: frame or tick
(long), kind (0 joystick, 1 key, 2 joystick at a tick, 3 key at a tick),
value (joystick byte, active low X68000 bits, or raw key code with bit 7 set
for a release), padding. All big-endian.

usage: make_input_script.py input.txt input.bin
"""

import struct
import sys

BITS = {"up": 0, "down": 1, "left": 2, "right": 3, "a": 5, "b": 6}

KEYS = {"1": 0x01, "z": 0x31, "x": 0x32, "space": 0x40, "tab": 0x42, "return": 0x44,
        "esc": 0x45, "up": 0x4c, "down": 0x4d, "right": 0x4e, "left": 0x4f,
        "p": 0x19, "lshift": 0x60, "rshift": 0x61, "ctrl": 0x63}


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

        if words[1] == "key":
            name, action = words[2], words[3]

            if name not in KEYS or action not in ("press", "release"):
                raise SystemExit(f"{source}:{number}: bad key event '{line}'")

            records.append((frame, number, 3 if kind else 1, KEYS[name] | (0x80 if action == "release" else 0)))

            continue

        joystick = 0xff

        if words[1] != "-":
            for control in words[1].split("+"):
                if control not in BITS:
                    raise SystemExit(f"{source}:{number}: unknown control '{control}'")

                joystick &= ~(1 << BITS[control])

        records.append((frame, number, kind, joystick))

    records.sort()

    with open(destination, "wb") as output:
        output.write(b"CRSI" + struct.pack(">I", len(records)))

        for frame, _, kind, value in records:
            output.write(struct.pack(">IBB2x", frame, kind, value))


main(*sys.argv[1:3])
