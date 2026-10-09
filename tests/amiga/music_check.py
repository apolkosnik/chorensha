#!/usr/bin/env python3
"""Check the music in captured audio of the Amiga build (run_fsuae.sh with
AUDIO_CAPTURE and MUSIC_DAT present).

The effects play centred (channels 0 and 1 together), the music in stereo
(channel 3 left, channel 2 right). So the capture's left minus right holds
only the music, and is compared with left minus right of the .crm streams
(intro, then the loop repeated), played at Paula's rate (PAL clock / the
period the player computes, as audio.s does):

1. Which song plays, and from when: the onset of every song's stream (the
   first ONSET seconds from its first sound) is correlated with the whole
   capture; the start is the earliest place that matches within REPEAT of
   the best (music repeats: S1's opening riff comes every 0.82 s, so only
   its onset, after silence, places it).
2. Whether it plays on: the capture is cut into windows (WINDOW seconds);
   each is matched against the stream at its expected place, following the
   previous window's lag (within SEARCH: repeating music must not make the
   check jump to another bar). Every window with music in it must match (normalised
   correlation at least MATCH, positive: left and right not swapped), and
   its lag may differ from the previous window's by at most JUMP: a lost or
   repeated block (186 ms at 22050 Hz) or an underrun's silence (23 ms)
   shows as a jump. (The capture drifts slowly against the stream: FS-UAE
   paces its real-time audio output itself; the drift is reported in ppm
   and must stay below MAXIMUM_DRIFT.) Windows where the stream's left minus
   right is quiet (below QUIET times the song's median) are skipped. Each window's level
   relative to the stream is reported (gain, against the first windows);
   once the capture is silent where the stream is not, the music has
   stopped and the check ends there.
3. With --fade SPEED: the music must fade out as MCDRV's _FADEOUT does:
   0.75 dB per step, 64 steps over SPEED x the song's fade unit (the .crm
   header), then stop. The fade's slope (from the windows between -3 and
   -30 dB) must be within FADE_TOLERANCE of that, and the music must stop
   within FADE_TOLERANCE of the fade length after the fade began (where the
   slope line crosses 0 dB).

usage: music_check.py capture.wav music_dir [--song NAME] [--fade SPEED]
Prints the result per window and exits with status 1 on any failure.
"""

import argparse
import os
import struct
import sys

import numpy as np

PAL_PAULA_CLOCK = 3546895
WINDOW = 0.5  # Seconds.
SEARCH = 0.03  # Seconds around the previous window's lag.
# Correlation of a window with the stream at the tracked lag. Music in the
# right place matches at 0.85 to 0.98; effects the game sends to one side
# only (the _ADPCMOUT output bits) do not cancel in left minus right and
# bring it down to about 0.6 while they play. A wrong or missing block
# matches at about 0.05.
MATCH = 0.5
FIND = 0.5  # Onsets: other songs score below 0.35.
REPEAT = 0.05
# Lag change allowed between consecutive windows: FS-UAE's real-time audio
# wobbles by up to about 3 ms; the smallest player fault, an underrun's
# silent block, is 23 ms.
JUMP = 0.01
MAXIMUM_DRIFT = 1000  # ppm.
QUIET = 0.3  # Of the median RMS of the stream's windows.
ONSET = 0.5  # Seconds.
SOUND = 0.02  # The first sound: left minus right above this.
# Capture below this part of the expected level: stopped (Paula's quietest
# volume, 1 of 64, is -36 dB).
SILENT = 0.001
FADE_TOLERANCE = 0.2


def read_wav(path):
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

    tag, channels, rate = struct.unpack("<HHI", fmt[:8])
    bits = struct.unpack("<H", fmt[14:16])[0]

    if tag == 0xfffe:
        tag = struct.unpack("<H", fmt[24:26])[0]

    if tag == 3 and bits == 32:
        values = np.frombuffer(frames[:len(frames) // 4 * 4], "<f4").astype(np.float64)
    elif tag == 1 and bits == 16:
        values = np.frombuffer(frames[:len(frames) // 2 * 2], "<i2") / 32768.0
    else:
        raise SystemExit(f"{path}: format {tag} with {bits} bits not supported")

    values = values[:len(values) // channels * channels].reshape(-1, channels)
    return rate, values[:, 0], values[:, min(1, channels - 1)]


def read_crm(path):
    """Returns rate, intro (left, right) and loop (left, right) as floats."""
    data = open(path, "rb").read()

    if data[:4] != b"CRSM":
        raise SystemExit(f"{path}: not a .crm file")

    _, channels, rate, intro, loop, block = struct.unpack(">HHIIII", data[4:24])
    fade_unit = struct.unpack(">H", data[26:28])[0] / 10000.0
    position = 32
    parts = []

    for frames in (intro, loop):
        left = np.empty(frames, np.int8)
        right = np.empty(frames, np.int8)
        done = 0

        while done < frames:
            n = min(block, frames - done)
            chunk = np.frombuffer(data[position:position + 2 * n], np.int8)
            left[done:done + n] = chunk[:n]
            right[done:done + n] = chunk[n:]
            position += 2 * n
            done += n

        parts.append(((left / 128.0), (right / 128.0)))

    return rate, parts[0], parts[1], fade_unit


def paula_rate(rate):
    period = (PAL_PAULA_CLOCK + rate // 2) // rate  # As audio.s rounds it.
    return PAL_PAULA_CLOCK / period


def stream_difference(intro, loop, seconds, rate):
    """Left minus right of the song as played for at least seconds."""
    difference = [intro[0] - intro[1]]
    total = len(intro[0])

    while len(loop[0]) and total < seconds * rate:
        difference.append(loop[0] - loop[1])
        total += len(loop[0])

    return np.concatenate(difference)


def resample(signal, from_rate, to_rate):
    """Paula's sample-and-hold output, sampled at to_rate."""
    times = np.arange(int(len(signal) * to_rate / from_rate)) * (from_rate / to_rate)
    return signal[np.minimum(times.astype(np.int64), len(signal) - 1)]


def correlate(capture, template):
    """Normalised correlation of template at every offset of capture."""
    n = len(capture) + len(template)
    size = 1 << (n - 1).bit_length()
    spectrum = np.fft.rfft(capture, size) * np.conj(np.fft.rfft(template, size))
    raw = np.fft.irfft(spectrum, size)[:len(capture) - len(template) + 1]
    energy = np.cumsum(np.concatenate(([0.0], capture * capture)))
    window_energy = energy[len(template):] - energy[:-len(template)]
    norm = np.sqrt(np.maximum(window_energy, 1e-12) * np.dot(template, template))
    return raw / norm


def main(capture_path, music_dir, only_song=None, fade_speed=None):
    rate, left, right = read_wav(capture_path)
    capture = left - right
    seconds = len(capture) / rate
    print(f"{capture_path}: {seconds:.1f} s at {rate} Hz")

    songs = {}

    for name in sorted(os.listdir(music_dir)):
        if name.endswith(".crm") and (only_song is None or name[:-4] == only_song):
            crm_rate, intro, loop, fade_unit = read_crm(os.path.join(music_dir, name))
            songs[name[:-4]] = (paula_rate(crm_rate), intro, loop, fade_unit)

    # 1. The song and its start.

    best = None

    for name, (played_rate, intro, loop, _) in songs.items():
        difference = stream_difference(intro, loop, 30, played_rate)
        sound = int(np.argmax(np.abs(difference) > SOUND))
        template = resample(difference[sound:sound + int(ONSET * played_rate)], played_rate, rate)

        if len(template) >= len(capture):
            continue

        scores = correlate(capture, template)
        found = int(np.argmax(scores))
        found = int(np.argmax(scores >= scores[found] - REPEAT))  # The earliest.
        offset = found - int(sound * rate / played_rate)
        print(f"  {name}: best correlation {scores[found]:.3f}, start at {offset / rate:.3f} s")

        if best is None or scores[found] > best[1]:
            best = (name, scores[found], offset)

    if best is None or best[1] < FIND or best[2] < 0:
        print("FAIL: no song found in the capture")
        return 1

    name, score, start = best
    played_rate, intro, loop, fade_unit = songs[name]
    print(f"{name} starts at {start / rate:.3f} s (correlation {score:.3f}), "
          f"played at {played_rate:.1f} Hz")

    # 2. Window by window.

    expected = resample(stream_difference(intro, loop, seconds, played_rate), played_rate, rate)
    window = int(WINDOW * rate)
    stream_levels = [np.sqrt(np.mean(expected[i:i + window] ** 2)) for i in range(0, len(expected) - window, window)]
    quiet_level = QUIET * float(np.median(stream_levels))
    previous_lag = None
    first = None
    search = int(SEARCH * rate)
    failures = 0
    checked = 0
    position = start
    reference_gain = None
    stopped = None
    levels = []

    while position + window <= len(capture):
        stream_position = position - start

        if stream_position + window + search > len(expected):
            print(f"  {position / rate:7.2f} s: past the end of the song")
            break

        reference = expected[stream_position:stream_position + window]
        quiet = np.sqrt(np.mean(reference * reference)) < quiet_level
        centre = stream_position + int(round((previous_lag or 0) * rate))
        low = max(0, centre - search)
        region = expected[low:centre + window + search]

        if quiet:
            position += window
            continue

        piece = capture[position:position + window]
        gain = np.sqrt(np.mean(piece * piece)) / np.sqrt(np.mean(reference * reference))

        if reference_gain is None:
            reference_gain = gain

        if gain < SILENT * reference_gain:
            stopped = position / rate
            print(f"  {position / rate:7.2f} s (song {stream_position / rate:7.2f} s): silent, the music has stopped")
            break

        scores = correlate(region, piece)
        lag = int(np.argmax(scores))
        lag_seconds = (low + lag - stream_position) / rate
        level = 20 * np.log10(gain / reference_gain)
        checked += 1
        levels.append(((position + window / 2) / rate, level))
        ok = scores[lag] >= MATCH

        if previous_lag is not None and abs(lag_seconds - previous_lag) > JUMP:
            ok = False

        if first is None:
            first = (position, lag_seconds)

        last = (position, lag_seconds)
        previous_lag = lag_seconds

        if not ok:
            # The window the music stopped in (the program ended): the next
            # one is silent, or the capture ends.
            following = capture[position + window:position + 2 * window]

            if len(following) < window or \
                    np.sqrt(np.mean(following * following)) < SILENT * reference_gain * \
                    np.sqrt(np.mean(expected[stream_position + window:stream_position + 2 * window] ** 2)):
                stopped = (position + window) / rate
                print(f"  {position / rate:7.2f} s (song {stream_position / rate:7.2f} s): "
                      f"the music stops in this window")
                break

            failures += 1

        print(f"  {position / rate:7.2f} s (song {stream_position / rate:7.2f} s): "
              f"correlation {scores[lag]:.3f}, lag {lag_seconds * 1000:+.2f} ms, "
              f"level {level:+6.1f} dB{'' if ok else '  FAIL'}")
        position += window

    if checked == 0:
        print("FAIL: no window with music to check")
        return 1

    print(f"{checked} windows checked, {failures} failed")

    if first is not None and last[0] > first[0]:
        drift = (last[1] - first[1]) / ((last[0] - first[0]) / rate) * 1e6
        print(f"drift of the capture against the stream: {drift:+.0f} ppm")

        if abs(drift) > MAXIMUM_DRIFT:
            print("FAIL: the music plays at the wrong rate")
            failures += 1

    if fade_speed is not None:
        failures += check_fade(levels, stopped, fade_speed * fade_unit)

    return 1 if failures else 0


def check_fade(levels, stopped, length):
    """The fade's slope and length against MCDRV's (length in seconds)."""
    expected_slope = -0.75 * 64 / length
    points = [(t, level) for t, level in levels if -30 <= level <= -3]

    if stopped is None or len(points) < 2:
        print(f"FAIL: no fade found (stopped: {stopped}, {len(points)} windows between -3 and -30 dB)")
        return 1

    times = np.array([t for t, _ in points])
    values = np.array([level for _, level in points])
    slope, intercept = np.polyfit(times, values, 1)
    began = -intercept / slope
    lasted = stopped - began
    print(f"fade: {slope:.2f} dB/s (MCDRV: {expected_slope:.2f}), began at {began:.2f} s, "
          f"stopped after {lasted:.2f} s (MCDRV: {length:.2f} s, to within the window)")

    if abs(slope / expected_slope - 1) > FADE_TOLERANCE or abs(lasted / length - 1) > FADE_TOLERANCE:
        print("FAIL: the fade differs from MCDRV's")
        return 1

    return 0


parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
parser.add_argument("capture")
parser.add_argument("music_dir")
parser.add_argument("--song")
parser.add_argument("--fade", type=int, metavar="SPEED")
arguments = parser.parse_args()
sys.exit(main(arguments.capture, arguments.music_dir, arguments.song, arguments.fade))
