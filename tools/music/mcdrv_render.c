/*
 * mcdrv_render: runs the X68000 music driver MCDRV.X (CUL, free software) in
 * a 68000 emulator (Musashi) with a minimal Human68k/X68000 environment,
 * plays an MDC song through it and records the YM2151 register writes with
 * their times, driven by the YM2151 timers as on the real machine.
 *
 * usage: mcdrv_render MCDRV.X song.MDC seconds output.log [loops]
 * (stops after the song has looped that many times)
 *
 * output.log: text, one line per YM2151 data write: "<time in 4 MHz YM2151
 * clocks> <register> <value>" (hex), plus "loop <time>" when the song's
 * end-of-data/loop command is reached for the first time.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "m68k.h"

#define MEM_SIZE 0x01000000
static uint8_t *mem;

/* Layout. */
#define LOAD_PSP 0x00010000u	/* memory block (16) + process data (240) */
#define LOAD_TEXT (LOAD_PSP + 0x100)
#define STACK_TOP 0x00BE0000u
#define MAGIC_STOP 0x00BF0000u	/* return address: execution ends here */
#define IDLE_LOOP 0x00BF0010u	/* bra.s * (the main program idles here) */
#define HEAP_START 0x00200000u

static uint32_t heap_next = HEAP_START;
static int stopped;
static int verbose = 1;

/* YM2151 state. */
static int opm_address;
static uint8_t opm_reg[256];
static int opm_flags;	/* bit 0 timer A overflow, bit 1 timer B */
static double timer_a_next, timer_b_next;	/* in YM2151 clocks (4 MHz) */
static double now;	/* current time, YM2151 clocks */
static FILE *log_file;
static int recording;
static long write_count;

/* MFP (just what MCDRV touches). */
static uint8_t mfp[0x40];

static uint32_t rd16(uint32_t a) { return (mem[a] << 8) | mem[a + 1]; }
static uint32_t rd32(uint32_t a) { return (rd16(a) << 16) | rd16(a + 2); }
static void wr16(uint32_t a, uint32_t v) { mem[a] = v >> 8; mem[a + 1] = v; }
static void wr32(uint32_t a, uint32_t v) { wr16(a, v >> 16); wr16(a + 2, v); }

static void unhandled(const char *what, uint32_t a, uint32_t v)
{
	if (verbose)
		fprintf(stderr, "%s %06X (%X) at PC %06X\n", what, a, v, m68k_get_reg(NULL, M68K_REG_PPC));
}

/* --- YM2151 --- */

static double timer_a_period(void)
{
	int na = (opm_reg[0x10] << 2) | (opm_reg[0x11] & 3);
	return 64.0 * (1024 - na);
}

static double timer_b_period(void)
{
	return 1024.0 * (256 - opm_reg[0x12]);
}

static void opm_write(int reg, int value)
{
	if (reg == 0x14) {
		/* Bits 0/1 load (start) timers A/B, 2/3 enable their IRQ, 4/5 reset
		   their flags. */
		if (value & 0x10) opm_flags &= ~1;
		if (value & 0x20) opm_flags &= ~2;
		if ((value & 1) && !(opm_reg[0x14] & 1)) timer_a_next = now + timer_a_period();
		if ((value & 2) && !(opm_reg[0x14] & 2)) timer_b_next = now + timer_b_period();
	}

	opm_reg[reg] = value;

	if (recording && log_file) {
		fprintf(log_file, "%.0f %02X %02X\n", now, reg, value);
		write_count++;
	}
}

/* --- memory map --- */

static int is_ram(uint32_t a) { return a < 0x00C00000; }

unsigned int m68k_read_memory_8(unsigned int a)
{
	a &= 0xFFFFFF;
	if (is_ram(a) || a >= 0xF00000) return mem[a];
	if (a == 0xE90003) return 0x00 | opm_flags;	/* never busy */
	if (a >= 0xE88000 && a < 0xE88040) return mfp[a - 0xE88000];
	if (a == 0xE9A001) return 0xFF;	/* PPI port A (joystick): idle */
	unhandled("read8", a, 0);
	return 0xFF;
}

unsigned int m68k_read_memory_16(unsigned int a)
{
	a &= 0xFFFFFF;
	if (is_ram(a) || a >= 0xF00000) return rd16(a);
	return (m68k_read_memory_8(a) << 8) | m68k_read_memory_8(a + 1);
}

unsigned int m68k_read_memory_32(unsigned int a)
{
	return (m68k_read_memory_16(a) << 16) | m68k_read_memory_16(a + 2);
}

void m68k_write_memory_8(unsigned int a, unsigned int v)
{
	a &= 0xFFFFFF;
	if (is_ram(a)) { mem[a] = v; return; }
	if (a == 0xE90001) { opm_address = v & 0xFF; return; }
	if (a == 0xE90003) { opm_write(opm_address, v & 0xFF); return; }
	if (a >= 0xE88000 && a < 0xE88040) { mfp[a - 0xE88000] = v; return; }
	unhandled("write8", a, v);
}

void m68k_write_memory_16(unsigned int a, unsigned int v)
{
	a &= 0xFFFFFF;
	if (is_ram(a)) { wr16(a, v); return; }
	m68k_write_memory_8(a, v >> 8);
	m68k_write_memory_8(a + 1, v & 0xFF);
}

void m68k_write_memory_32(unsigned int a, unsigned int v)
{
	m68k_write_memory_16(a, v >> 16);
	m68k_write_memory_16(a + 2, v & 0xFFFF);
}

unsigned int m68k_read_disassembler_8(unsigned int a) { return m68k_read_memory_8(a); }
unsigned int m68k_read_disassembler_16(unsigned int a) { return m68k_read_memory_16(a); }
unsigned int m68k_read_disassembler_32(unsigned int a) { return m68k_read_memory_32(a); }

/* --- Human68k / IOCS --- */

static uint32_t allocate(uint32_t size)
{
	uint32_t a = (heap_next + 15) & ~15u;
	heap_next = a + size + 16;
	memset(mem + a, 0, size);
	return a;
}

/* DOS call $FFxx: arguments on the stack (above the return address the
   line F handler would see; here the stack as at the instruction). */
static void dos_call(int number)
{
	uint32_t sp = m68k_get_reg(NULL, M68K_REG_A7);
	uint32_t d0 = 0;

	switch (number) {
	case 0x09: /* _PRINT */
		if (verbose) {
			uint32_t s = rd32(sp);
			fputs("PRINT: ", stderr);
			while (mem[s]) fputc(mem[s] >= 0x20 || mem[s] == '\n' ? mem[s] : '.', stderr), s++;
			fputc('\n', stderr);
		}
		break;
	case 0x20: /* _SUPER: already supervisor */
		d0 = 0;
		break;
	case 0x30: /* _VERNUM */
		d0 = 0x36380302;	/* Human68k 3.02 */
		break;
	case 0x31: /* _KEEPPR: stay resident */
		if (verbose) fprintf(stderr, "KEEPPR (%u bytes resident)\n", rd32(sp));
		stopped = 1;
		break;
	case 0x48: /* _MALLOC */
		d0 = allocate(rd32(sp) & 0xFFFFFF);
		break;
	case 0x49: /* _MFREE */
		d0 = 0;
		break;
	case 0x4A: /* _SETBLOCK */
		d0 = 0;
		break;
	case 0x4C: /* _EXIT2 */
	case 0x00: /* _EXIT */
		if (verbose) fprintf(stderr, "EXIT (%u)\n", number == 0x4C ? rd16(sp) : 0);
		stopped = 2;
		break;
	case 0x50: /* _SETPDB */
	case 0x51: /* _GETPDB */
	case 0x80: /* _GETPDB (new) */
		d0 = LOAD_PSP + 16;
		break;
	case 0xF7: /* _BUS_ERR: every probe (MIDI boards) faults: none fitted */
		d0 = 2;
		break;
	default:
		fprintf(stderr, "unhandled DOS call $FF%02X at %06X\n", number, m68k_get_reg(NULL, M68K_REG_PC));
		d0 = (uint32_t)-1;
		break;
	}

	m68k_set_reg(M68K_REG_D0, d0);
}

static void iocs_call(void)
{
	uint32_t d0 = m68k_get_reg(NULL, M68K_REG_D0) & 0xFF;
	uint32_t result = 0;

	switch (d0) {
	case 0x81: /* _B_SUPER */
		result = (uint32_t)-1;
		break;
	default:
		fprintf(stderr, "unhandled IOCS $%02X at %06X\n", d0, m68k_get_reg(NULL, M68K_REG_PC));
		break;
	}

	m68k_set_reg(M68K_REG_D0, result);
}

/* Called before every instruction: emulates DOS ($FFxx), IOCS (trap #15)
   and PCM8 (trap #2) calls in place. */
void instruction_hook(unsigned int pc)
{
	uint32_t op = rd16(pc);

	if (pc == MAGIC_STOP) {
		stopped = 1;
		m68k_end_timeslice();
		return;
	}

	if ((op & 0xFF00) == 0xFF00) {
		dos_call(op & 0xFF);
		m68k_set_reg(M68K_REG_PC, pc + 2);
		if (stopped) m68k_end_timeslice();
	} else if (op == 0x4E4F) {
		iocs_call();
		m68k_set_reg(M68K_REG_PC, pc + 2);
	} else if (op == 0x4E42) {
		m68k_set_reg(M68K_REG_D0, (uint32_t)-1);	/* no PCM8 */
		m68k_set_reg(M68K_REG_PC, pc + 2);
	}
}

static int interrupt_ack(int level)
{
	m68k_set_irq(0);
	return 0x43;	/* MFP GPIP3: YM2151 IRQ */
}

/* --- loading --- */

static uint32_t load_x(const char *path)
{
	FILE *f = fopen(path, "rb");
	if (!f) { perror(path); exit(1); }
	uint8_t header[64];
	fread(header, 1, 64, f);
	if (header[0] != 'H' || header[1] != 'U') { fprintf(stderr, "%s: not an X file\n", path); exit(1); }

	uint32_t exec = (header[8] << 24) | (header[9] << 16) | (header[10] << 8) | header[11];
	uint32_t text = (header[12] << 24) | (header[13] << 16) | (header[14] << 8) | header[15];
	uint32_t data = (header[16] << 24) | (header[17] << 16) | (header[18] << 8) | header[19];
	uint32_t bss = (header[20] << 24) | (header[21] << 16) | (header[22] << 8) | header[23];
	uint32_t reloc = (header[24] << 24) | (header[25] << 16) | (header[26] << 8) | header[27];

	fread(mem + LOAD_TEXT, 1, text + data, f);
	memset(mem + LOAD_TEXT + text + data, 0, bss);

	uint8_t *r = malloc(reloc);
	fread(r, 1, reloc, f);
	fclose(f);

	/* Relocation table: offsets (word; $0001 then long for large ones) to
	   longs that get the load address added. */
	uint32_t pos = 0, at = LOAD_TEXT;
	while (pos + 1 < reloc) {
		uint32_t d = (r[pos] << 8) | r[pos + 1];
		pos += 2;
		if (d == 1) {
			d = (r[pos] << 24) | (r[pos + 1] << 16) | (r[pos + 2] << 8) | r[pos + 3];
			pos += 4;
		}
		at += d & ~1u;
		if (d & 1) wr16(at, rd16(at) + LOAD_TEXT);
		else wr32(at, rd32(at) + LOAD_TEXT);
	}
	free(r);

	heap_next = (LOAD_TEXT + text + data + bss + 0xFFFF) & ~0xFFFFu;
	if (heap_next < HEAP_START) heap_next = HEAP_START;

	return LOAD_TEXT + exec;
}

static void run_until_stop(long max_cycles)
{
	stopped = 0;
	while (!stopped && max_cycles > 0) {
		max_cycles -= m68k_execute(10000);
	}
}

/* Calls MCDRV service d0 with d1/a0 and runs it to its return. */
static uint32_t mcdrv_call(int service, uint32_t d1, uint32_t a0)
{
	uint32_t vector = rd32(0x90);
	uint32_t sp = m68k_get_reg(NULL, M68K_REG_A7);

	/* Exception frame for trap #4 returning to MAGIC_STOP. */
	sp -= 4; wr32(sp, MAGIC_STOP);
	sp -= 2; wr16(sp, 0x2000);
	m68k_set_reg(M68K_REG_A7, sp);
	m68k_set_reg(M68K_REG_SR, 0x2000);
	m68k_set_reg(M68K_REG_D0, service);
	m68k_set_reg(M68K_REG_D1, d1);
	m68k_set_reg(M68K_REG_A0, a0);
	m68k_set_reg(M68K_REG_PC, vector);
	run_until_stop(50000000);

	return m68k_get_reg(NULL, M68K_REG_D0);
}

int main(int argc, char **argv)
{
	if (argc < 5) {
		fprintf(stderr, "usage: mcdrv_render MCDRV.X song.MDC seconds output.log [loops [fade_seconds fade_speed]]\n");
		return 2;
	}

	mem = calloc(1, MEM_SIZE);

	/* Idle loop and stop marker. */
	wr16(IDLE_LOOP, 0x60FE);	/* bra.s * */
	wr16(MAGIC_STOP, 0x4E71);

	uint32_t entry = load_x(argv[1]);

	/* Process: memory block, PSP with an empty command line. */
	uint32_t psp = LOAD_PSP + 16;
	uint32_t command_line = allocate(256);	/* length byte 0 */

	m68k_init();
	m68k_set_cpu_type(M68K_CPU_TYPE_68000);
	m68k_set_instr_hook_callback(instruction_hook);
	m68k_set_int_ack_callback(interrupt_ack);
	/* Unused vectors as the X68000 IPL sets them: vector number in the top
	   byte, a ROM address below (MCDRV checks trap #4 is free this way). */
	for (int v = 2; v < 256; v++)
		wr32(v * 4, ((uint32_t)v << 24) | 0xFF0000);

	wr32(0, STACK_TOP);
	wr32(4, entry);
	m68k_pulse_reset();

	m68k_set_reg(M68K_REG_SR, 0x2700);
	m68k_set_reg(M68K_REG_A7, STACK_TOP);
	m68k_set_reg(M68K_REG_USP, STACK_TOP - 0x10000);
	m68k_set_reg(M68K_REG_A0, LOAD_PSP);
	m68k_set_reg(M68K_REG_A1, heap_next);
	m68k_set_reg(M68K_REG_A2, command_line);
	m68k_set_reg(M68K_REG_A3, allocate(256));	/* empty environment */
	m68k_set_reg(M68K_REG_A4, entry);
	m68k_set_reg(M68K_REG_PC, entry);
	(void)psp;

	run_until_stop(100000000);

	if (stopped != 1) {
		fprintf(stderr, "MCDRV did not stay resident (%d)\n", stopped);
		return 1;
	}

	fprintf(stderr, "trap #4 vector %06X, YM2151 vector %06X\n", rd32(0x90), rd32(0x10C));
	verbose = 0;

	/* The song. */
	FILE *f = fopen(argv[2], "rb");
	if (!f) { perror(argv[2]); return 1; }
	fseek(f, 0, SEEK_END);
	long size = ftell(f);
	fseek(f, 0, SEEK_SET);
	uint32_t song = allocate(size);
	fread(mem + song, 1, size, f);
	fclose(f);

	log_file = fopen(argv[4], "w");
	if (!log_file) { perror(argv[4]); return 1; }

	int32_t r = mcdrv_call(0x01, size, song);	/* _TRANSMDC */
	fprintf(stderr, "_TRANSMDC: %08X\n", r);
	mcdrv_call(0x05, 0, 0);	/* _STOPMUSIC */
	recording = 1;
	r = mcdrv_call(0x02, 0, 0);	/* _PLAYMUSIC */
	fprintf(stderr, "_PLAYMUSIC: %08X, timer reg $14 = %02X, A %.0f B %.0f clocks\n",
	        r, opm_reg[0x14], timer_a_period(), timer_b_period());

	double end = atof(argv[3]) * 4000000.0;
	int stop_loops = argc > 5 ? atoi(argv[5]) : 0;	/* stop after this many loops */
	int last_loops = 0;
	long interrupts = 0;
	/* Optional _FADEOUT with the given speed at the given time (measures fades). */
	double fade_at = argc > 7 ? atof(argv[6]) * 4000000.0 : -1;
	int fade_speed = argc > 7 ? atoi(argv[7]) : 0;

	while (now < end) {
		/* Next timer event. */
		double next = end;
		if ((opm_reg[0x14] & 1) && timer_a_next < next) next = timer_a_next;
		if ((opm_reg[0x14] & 2) && timer_b_next < next) next = timer_b_next;
		now = next;
		if (now >= end) break;

		int irq = 0;
		if ((opm_reg[0x14] & 1) && now >= timer_a_next) {
			opm_flags |= 1;
			timer_a_next += timer_a_period();
			if (opm_reg[0x14] & 4) irq = 1;
		}
		if ((opm_reg[0x14] & 2) && now >= timer_b_next) {
			opm_flags |= 2;
			timer_b_next += timer_b_period();
			if (opm_reg[0x14] & 8) irq = 1;
		}

		/* The YM2151 IRQ reaches the CPU through the MFP (GPIP3, level 6)
		   when MCDRV has enabled it there. */
		if (irq && (mfp[0x09] & 8) && (mfp[0x15] & 8)) {
			m68k_set_reg(M68K_REG_PC, IDLE_LOOP);
			m68k_set_reg(M68K_REG_SR, 0x2000);
			m68k_set_reg(M68K_REG_A7, STACK_TOP - 0x100);
			m68k_set_irq(6);
			m68k_execute(200000);	/* the handler returns to the idle loop */
			interrupts++;

			if (fade_at >= 0 && now >= fade_at) {
				mcdrv_call(0x14, fade_speed, 0);	/* _FADEOUT */
				fprintf(log_file, "fade %.0f %d\n", now, fade_speed);
				fade_at = -1;
			}

			int loops = mcdrv_call(0x0D, 0, 0) & 0xFFFF;	/* _GETLOOPCOUNT (word) */
			if (loops != last_loops) {
				fprintf(log_file, "loop %.0f %d\n", now, loops);
				last_loops = loops;
				if (stop_loops && loops >= stop_loops) break;
			}
			if (!(mcdrv_call(0x0B, 0, 0) & 0xFFFF)) {	/* _GETPLAYFLG */
				fprintf(log_file, "end %.0f\n", now);
				break;
			}
		}
	}

	fprintf(stderr, "%ld interrupts, %ld YM2151 writes, %.1f s\n", interrupts, write_count, now / 4000000.0);
	fclose(log_file);
	return 0;
}
