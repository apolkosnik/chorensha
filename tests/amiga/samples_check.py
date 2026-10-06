#!/usr/bin/env python3
"""Check the Amiga build's decoded sound effects against the original files.

samples.bin (written by sz2 <frames>): 'CRSA', effects played (long), chip
RAM address (long) and size (long) of the decoded samples, the game's sample
table after decoding (256 entries of 16 bytes: mode word, length long,
address long, priority word, 4 unused bytes), then the decoded samples.

Each sample number in PCM_DAT/SZ2_PCM.CNF is decoded here from its ADPCM
file with the MSM6258 model of MAME's okim6258 as the X68000 uses it (10-bit
output; signal -2 and step 0 at the start, low nibble first), scaled to
8 bits (signal >> 2), and compared with the entry and data in the dump. The
mode and priority words must match the configuration file as well.

usage: samples_check.py samples.bin [game data directory]
       (default directory: binaries/amiga)
Exits with status 1 at the first difference.
"""

import math
import os
import re
import struct
import sys

NIBBLE_BITS = [(1, 0, 0, 0), (1, 0, 0, 1), (1, 0, 1, 0), (1, 0, 1, 1),
               (1, 1, 0, 0), (1, 1, 0, 1), (1, 1, 1, 0), (1, 1, 1, 1),
               (-1, 0, 0, 0), (-1, 0, 0, 1), (-1, 0, 1, 0), (-1, 0, 1, 1),
               (-1, 1, 0, 0), (-1, 1, 0, 1), (-1, 1, 1, 0), (-1, 1, 1, 1)]
STEP_SHIFTS = (-1, -1, -1, -1, 2, 4, 6, 8)


def difference_table():
    table = []

    for step in range(49):
        value = math.floor(16.0 * pow(11.0 / 10.0, step))

        for sign, b2, b1, b0 in NIBBLE_BITS:
            table.append(sign * (value * b2 + value // 2 * b1 + value // 4 * b0 + value // 8))

    return table


DIFFERENCES = difference_table()


def decode(adpcm):
    signal, step = -2, 0
    output = bytearray()

    for byte in adpcm:
        for nibble in (byte & 15, byte >> 4):
            signal = max(-512, min(511, signal + DIFFERENCES[step * 16 + nibble]))
            step = max(0, min(48, step + STEP_SHIFTS[nibble & 7]))
            output.append((signal >> 2) & 0xff)

    return bytes(output)


def read_configuration(directory):
    """Sample number -> (file, mode, priority), as the game parses it."""
    text = open(os.path.join(directory, "PCM_DAT", "SZ2_PCM.CNF"), "rb").read()
    entries = {}
    pattern = re.compile(rb"^\s*PCM_No\.\$([0-9A-Fa-f]+)\s*:\s*FILE=\s*(\S+)\s*,"
                         rb"\s*STAT=\$([0-9A-Fa-f]+)\s*,\s*PR=\$([0-9A-Fa-f]+)")

    for line in text.splitlines():
        match = pattern.match(line)

        if match:
            number = int(match.group(1), 16)
            name = match.group(2).split(b"\x81\x8f")[-1].split(b"\\")[-1].decode("ascii")
            entries[number] = (name, int(match.group(3), 16), int(match.group(4), 16))

    return entries


def find_file(directory, name):
    folder = os.path.join(directory, "PCM_DAT")

    for candidate in os.listdir(folder):
        if candidate.lower() == name.lower():
            return os.path.join(folder, candidate)

    raise SystemExit(f"{name}: not found in {folder}")


def main(path, directory):
    data = open(path, "rb").read()

    if data[:4] != b"CRSA":
        raise SystemExit(f"{path}: not a samples.bin file")

    played, base, size = struct.unpack(">III", data[4:16])
    table = data[16:16 + 256 * 16]
    memory = data[16 + 256 * 16:]

    if size == 0:
        print(f"{path}: no decoded samples (no audio channels or chip RAM)")
        return 1

    if len(memory) != size:
        print(f"{path}: {len(memory)} bytes of samples, header says {size}")
        return 1

    configuration = read_configuration(directory)
    decoded_files = {}
    used = 0

    for number, (name, mode, priority) in sorted(configuration.items()):
        entry_mode, length, address, entry_priority = struct.unpack(">HIIH", table[number * 16:number * 16 + 12])

        if (entry_mode, entry_priority) != (mode, priority):
            print(f"{path}: sample ${number:02X} ({name}): mode ${entry_mode:X} priority ${entry_priority:X},"
                  f" configuration says ${mode:X} ${priority:X}")
            return 1

        expected = decode(open(find_file(directory, name), "rb").read())
        offset = address - base

        if length != len(expected) or offset < 0 or offset + length > size:
            print(f"{path}: sample ${number:02X} ({name}): length {length} at offset {offset},"
                  f" expected length {len(expected)} within {size} bytes")
            return 1

        actual = memory[offset:offset + length]

        if actual != expected:
            index = next(i for i in range(length) if actual[i] != expected[i])
            print(f"{path}: sample ${number:02X} ({name}): differs at byte {index}:"
                  f" {actual[index]} (expected {expected[index]})")
            return 1

        if name.lower() not in decoded_files:
            decoded_files[name.lower()] = offset
            used += length
        elif decoded_files[name.lower()] != offset:
            print(f"{path}: sample ${number:02X} ({name}): decoded twice")
            return 1

    if used != size:
        print(f"{path}: {size} bytes of chip RAM for {used} bytes of samples")
        return 1

    print(f"{path}: {len(configuration)} samples ({len(decoded_files)} files, {size} bytes) match;"
          f" {played} effects played")

    return 0


if len(sys.argv) < 2:
    raise SystemExit(__doc__)

sys.exit(main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "binaries/amiga"))
