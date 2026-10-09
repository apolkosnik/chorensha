#!/usr/bin/env python3
"""Check captured audio of the Amiga build (run_fsuae.sh with AUDIO_CAPTURE).

Finds the sound events in the WAV file (stretches above a silence threshold)
and identifies each one: the start of the event, resampled from the X68000
rate (15625 Hz) to the WAV rate, is correlated with the start of every
decoded sample in samples.bin (the same run). An event matches a sample when
the normalised correlation is at least MATCH (allowing for Paula's and the
host's output filters).

usage: audio_check.py capture.wav samples.bin [minimum events]
Prints the events and exits with status 1 if fewer than the minimum number
of events (default 1) were found or any event matched no sample.
"""

import struct
import sys

X68000_RATE = 15625
THRESHOLD = 0.02  # Of full scale.
SILENCE_GAP = 0.05  # Seconds below the threshold that end an event.
WINDOW = 0.03  # Seconds compared at the start of an event.
MATCH = 0.9
LATE = 0.0002  # Seconds (10 samples at 48 kHz).


def read_wav(path):
    """PCM or float WAV, also WAVE_FORMAT_EXTENSIBLE (OpenAL Soft writes it)."""
    data = open(path, "rb").read()

    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise SystemExit(f"{path}: not a WAV file")

    position = 12
    fmt = frames = None

    while position + 8 <= len(data):
        kind, size = data[position:position + 4], struct.unpack("<I", data[position + 4:position + 8])[0]
        body = data[position + 8:position + 8 + size]

        if kind == b"fmt ":
            fmt = body
        elif kind == b"data":
            frames = body

        position += 8 + size + (size & 1)

    if fmt is None or frames is None:
        raise SystemExit(f"{path}: no fmt or data chunk")

    tag, channels, rate = struct.unpack("<HHI", fmt[:8])
    bits = struct.unpack("<H", fmt[14:16])[0]

    if tag == 0xfffe:
        tag = struct.unpack("<H", fmt[24:26])[0]

    if tag == 3 and bits == 32:
        values = struct.unpack(f"<{len(frames) // 4}f", frames[:len(frames) // 4 * 4])
    elif tag == 1 and bits == 16:
        values = [v / 32768.0 for v in struct.unpack(f"<{len(frames) // 2}h", frames[:len(frames) // 2 * 2])]
    elif tag == 1 and bits == 8:
        values = [(v - 128) / 128.0 for v in frames]
    else:
        raise SystemExit(f"{path}: format {tag} with {bits} bits not supported")

    left = list(values[0::channels])
    right = list(values[min(1, channels - 1)::channels])

    return rate, left, right


def read_samples(path):
    data = open(path, "rb").read()

    if data[:4] != b"CRSA":
        raise SystemExit(f"{path}: not a samples.bin file")

    _, base, size = struct.unpack(">III", data[4:16])
    table = data[16:16 + 256 * 16]
    memory = data[16 + 256 * 16:]
    samples = {}

    for number in range(256):
        _, length, address, _ = struct.unpack(">HIIH", table[number * 16:number * 16 + 12])

        if length and base <= address < base + size:
            offset = address - base
            raw = memory[offset:offset + length]
            samples.setdefault(offset, (number, [(b - 256 if b > 127 else b) / 128.0 for b in raw]))

    return list(samples.values())


def events(rate, signal):
    gap = int(SILENCE_GAP * rate)
    found = []
    start = None
    quiet = 0

    for index, value in enumerate(signal):
        if abs(value) >= THRESHOLD:
            if start is None:
                start = index

            quiet = 0
        elif start is not None:
            quiet += 1

            if quiet > gap:
                found.append((start, index - quiet))
                start = None

    if start is not None:
        found.append((start, len(signal) - 1))

    return found


def correlate(a, b):
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    ma, mb = sum(a) / n, sum(b) / n
    sab = sum((x - ma) * (y - mb) for x, y in zip(a, b))
    saa = sum((x - ma) ** 2 for x in a)
    sbb = sum((y - mb) ** 2 for y in b)

    return sab / (saa * sbb) ** 0.5 if saa and sbb else 0.0


def resample(sample, rate, count):
    # Paula holds each sample for one period: zero-order hold.
    return [sample[min(len(sample) - 1, int(i * X68000_RATE / rate))] for i in range(count)]


def best_match(rate, signal, start, samples):
    window = int(WINDOW * rate)
    best = (0.0, None, 0)

    # The threshold crossing can be a little after the sample's first byte
    # (up to 10 ms), or, through a mixer that interpolates (AHI), up to LATE
    # seconds before it (the interpolation rings ahead of the sound).

    for number, sample in samples:
        reference = resample(sample, rate, window + int(0.01 * rate))

        for late in range(0, int(LATE * rate) + 1):
            captured = signal[start + late:start + late + window]

            for shift in range(0, int(0.01 * rate) if late == 0 else 1):
                value = correlate(captured, reference[shift:shift + window])

                if value > best[0]:
                    best = (value, number, shift - late)

    return best


def main(wav_path, samples_path, minimum):
    rate, left, right = read_wav(wav_path)
    samples = read_samples(samples_path)
    mono = [(l + r) / 2 for l, r in zip(left, right)]
    found = events(rate, mono)
    unmatched = 0

    peak = max((abs(v) for v in mono), default=0.0)
    print(f"{wav_path}: {len(mono) / rate:.1f} s at {rate} Hz, peak {peak:.2f}, {len(found)} events")

    for start, end in found:
        value, number, _ = best_match(rate, mono, start, samples)
        balance = sum(abs(v) for v in left[start:end + 1]) / max(1e-9, sum(abs(v) for v in right[start:end + 1]))
        verdict = "ok" if value >= MATCH else "NO MATCH"

        if value < MATCH:
            unmatched += 1

        print(f"  {start / rate:8.3f} s  {(end - start) / rate:6.3f} s  sample ${number:02X}"
              f"  correlation {value:.3f}  left/right {balance:.2f}  {verdict}")

    if len(found) < minimum:
        print(f"{wav_path}: {len(found)} events, expected at least {minimum}")
        return 1

    return 1 if unmatched else 0


if len(sys.argv) < 3:
    raise SystemExit(__doc__)

sys.exit(main(sys.argv[1], sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 1))
