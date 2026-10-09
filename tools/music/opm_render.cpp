// opm_render: plays a YM2151 register log (from mcdrv_render) through ymfm's
// YM2151 at 4 MHz (the X68000's OPM clock) and writes a 16-bit stereo WAV at
// the chip's native rate (62500 Hz).
//
// usage: opm_render input.log output.wav [start_seconds end_seconds]

#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <vector>
#include "ymfm_opm.h"

struct write_event { double time; uint8_t reg, value; };

static void put16(FILE *f, uint16_t v) { fputc(v & 0xff, f); fputc(v >> 8, f); }
static void put32(FILE *f, uint32_t v) { put16(f, v & 0xffff); put16(f, v >> 16); }

int main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: opm_render input.log output.wav [start_seconds end_seconds]\n");
		return 2;
	}

	const double clock = 4000000.0;
	std::vector<write_event> events;
	double last = 0;
	FILE *in = fopen(argv[1], "r");
	if (!in) { perror(argv[1]); return 1; }
	char line[256];

	while (fgets(line, sizeof line, in)) {
		double t; unsigned reg, value;
		if (sscanf(line, "%lf %x %x", &t, &reg, &value) == 3) {
			events.push_back({t, (uint8_t)reg, (uint8_t)value});
			last = t;
		}
	}
	fclose(in);

	double start = argc > 4 ? atof(argv[3]) * clock : 0;
	double end = argc > 4 ? atof(argv[4]) * clock : last + clock;

	ymfm::ymfm_interface interface;
	ymfm::ym2151 chip(interface);
	chip.reset();

	uint32_t rate = chip.sample_rate((uint32_t)clock);	// clock / 64
	double clocks_per_sample = clock / rate;
	FILE *out = fopen(argv[2], "wb");
	if (!out) { perror(argv[2]); return 1; }

	fwrite("RIFF\0\0\0\0WAVEfmt ", 1, 16, out);
	put32(out, 16); put16(out, 1); put16(out, 2); put32(out, rate); put32(out, rate * 4);
	put16(out, 4); put16(out, 16);
	fwrite("data\0\0\0\0", 1, 8, out);

	size_t next = 0;
	uint32_t frames = 0;
	int32_t peak = 0;

	for (double t = 0; t < end; t += clocks_per_sample) {
		while (next < events.size() && events[next].time <= t) {
			chip.write_address(events[next].reg);
			chip.write_data(events[next].value);
			next++;
		}

		ymfm::ym2151::output_data output;
		chip.generate(&output, 1);

		if (t >= start) {
			for (int c = 0; c < 2; c++) {
				int32_t s = output.data[c] / 2;	// 8 channels can exceed 16 bits
				if (s > 32767) s = 32767;
				if (s < -32768) s = -32768;
				if (abs(s) > peak) peak = abs(s);
				put16(out, (uint16_t)s);
			}
			frames++;
		}
	}

	fseek(out, 4, SEEK_SET); put32(out, 36 + frames * 4);
	fseek(out, 40, SEEK_SET); put32(out, frames * 4);
	fclose(out);
	fprintf(stderr, "%s: %u frames at %u Hz (%.1f s), peak %d\n", argv[2], frames, rate, frames / (double)rate, peak);
	return 0;
}
