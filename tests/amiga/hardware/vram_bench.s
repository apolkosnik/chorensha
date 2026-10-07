; Picasso96 screen memory benchmark (hardware test kit).
;
; Opens an 8-bit Picasso96 screen (320 x 256, as the game does), locks its
; bitmap and times memory accesses with the E clock, under Forbid():
; long and byte writes, reads and read-modify-writes on the card's memory,
; the same in fast RAM, and copies from fast RAM to fast RAM and to the
; card (what the game's upload does). Each test covers 64 KB four times.
;
; The answer it gives: whether the game should keep composing frames in
; fast RAM and copy them to the card (now), or draw directly into the card's
; memory (sprites as byte writes, text as read-modify-writes).
;
; Output (to the console, redirect to a file to send back):
;   test name, KB/s, ns per access (a copy counts one long moved as one
;   access).
;
; usage: vram_bench
; Needs a 68020 or better and Picasso96.

	machine	68020

; exec.library

_LVOForbid=-132
_LVOPermit=-138
_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOCloseLibrary=-414
_LVOOpenDevice=-444
_LVOCloseDevice=-450
_LVOOpenLibrary=-552

AttnFlags=296
MEMF_ANY=0
MEMF_FAST=1<<2

; dos.library

_LVOVPrintf=-954

; intuition.library

_LVOCloseScreen=-66
_LVOOpenScreenTagList=-612

TAG_DONE=0
SA_Width=$80000023
SA_Height=$80000024
SA_Depth=$80000025
SA_Type=$8000002d
SA_DisplayID=$80000032
SA_ShowTitle=$80000036
SA_Quiet=$80000038
CUSTOMSCREEN=15
sc_RastPort=84
rp_BitMap=4

; Picasso96API.library

_LVOp96GetBitMapAttr=-42
_LVOp96LockBitMap=-48
_LVOp96UnlockBitMap=-54
_LVOp96BestModeIDTagList=-60

P96BIDTAG_FormatsAllowed=$80000061
P96BIDTAG_NominalWidth=$80000063
P96BIDTAG_NominalHeight=$80000064
P96BIDTAG_Depth=$80000065
RGBFF_CLUT=1<<1
INVALID_ID=-1
P96BMA_BYTESPERROW=4
P96BMA_ISONBOARD=9
ri_Memory=0
ri_BytesPerRow=4
RENDER_INFO_SIZE=12

; timer.device

UNIT_ECLOCK=2
io_Device=20
TIMEREQUEST_SIZE=40
_LVOReadEClock=-60

SCREEN_WIDTH=320
SCREEN_HEIGHT=256
BENCH_SIZE=65536
REPETITIONS=4

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

start:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	4.w,a6
	move.l	a6,exec_base

	lea		dos_name,a1
	moveq	#36,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,dos_base
	beq		.exit

	btst	#1,AttnFlags+1(a6) ; 68020 or better.
	bne		.cpu_ok

	lea		no_cpu_text,a0
	bsr		print_text
	bra		.close_dos

.cpu_ok:
	lea		intuition_name,a1
	moveq	#39,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,intuition_base
	beq		.close_dos

	lea		picasso96_name,a1
	moveq	#2,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,picasso96_base
	bne		.picasso96_ok

	lea		no_picasso96_text,a0
	bsr		print_text
	bra		.close_intuition

.picasso96_ok:
	lea		timer_name,a0
	moveq	#UNIT_ECLOCK,d0
	lea		timer_request,a1
	moveq	#0,d1
	jsr		_LVOOpenDevice(a6)
	tst.l	d0
	bne		.close_picasso96

	move.l	timer_request+io_Device,timer_base

	; Fast RAM buffers (any memory if there is no fast RAM).

	move.l	#BENCH_SIZE*2,d0
	moveq	#MEMF_FAST,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,fast_buffer
	bne		.buffer_ok

	move.l	#BENCH_SIZE*2,d0
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,fast_buffer
	beq		.close_timer

	lea		no_fast_text,a0
	bsr		print_text

.buffer_ok:
	; 8-bit screen.

	move.l	picasso96_base,a6
	lea		mode_tags,a0
	jsr		_LVOp96BestModeIDTagList(a6)
	cmp.l	#INVALID_ID,d0
	bne		.mode_ok

	lea		no_mode_text,a0
	bsr		print_text
	bra		.free_buffer

.mode_ok:
	move.l	d0,screen_tags_mode+4
	move.l	d0,print_arguments

	move.l	intuition_base,a6
	sub.l	a0,a0
	lea		screen_tags,a1
	jsr		_LVOOpenScreenTagList(a6)
	move.l	d0,screen
	bne		.screen_ok

	lea		no_screen_text,a0
	bsr		print_text
	bra		.free_buffer

.screen_ok:
	move.l	d0,a0
	move.l	sc_RastPort+rp_BitMap(a0),bitmap

	move.l	picasso96_base,a6
	move.l	bitmap,a0
	moveq	#P96BMA_ISONBOARD,d0
	jsr		_LVOp96GetBitMapAttr(a6)
	move.l	d0,print_arguments+4

	move.l	bitmap,a0
	lea		lock_info,a1
	moveq	#RENDER_INFO_SIZE,d0
	jsr		_LVOp96LockBitMap(a6)
	move.l	d0,lock
	beq		.no_lock

	move.l	lock_info+ri_Memory,d0
	beq		.no_memory

	move.l	d0,card_memory
	move.l	d0,print_arguments+12
	moveq	#0,d0
	move	lock_info+ri_BytesPerRow,d0
	move.l	d0,print_arguments+8
	mulu.l	#SCREEN_HEIGHT,d0
	cmp.l	#BENCH_SIZE,d0
	bcs		.no_memory

	; The tests, with multitasking off.

	move.l	exec_base,a6
	jsr		_LVOForbid(a6)

	lea		tests,a5
	lea		ticks,a4

.test_loop:
	move.l	(a5),d0
	beq		.tests_done

	bsr		read_eclock
	move.l	d0,start_ticks

	; a0 = source, a1 = destination (by test kind).

	move.l	8(a5),d0
	bsr		buffer_address
	move.l	d0,a0
	move.l	12(a5),d0
	bsr		buffer_address
	move.l	d0,a1
	move.l	(a5),a2
	jsr		(a2)

	bsr		read_eclock
	sub.l	start_ticks,d0
	move.l	d0,(a4)+

	lea		TEST_SIZE(a5),a5
	bra		.test_loop

.tests_done:
	move.l	exec_base,a6
	jsr		_LVOPermit(a6)

	move.l	picasso96_base,a6
	move.l	bitmap,a0
	move.l	lock,d0
	jsr		_LVOp96UnlockBitMap(a6)

	move.l	intuition_base,a6
	move.l	screen,a0
	jsr		_LVOCloseScreen(a6)

	bsr		print_results

	bra		.free_buffer

.no_memory:
	move.l	picasso96_base,a6
	move.l	bitmap,a0
	move.l	lock,d0
	jsr		_LVOp96UnlockBitMap(a6)

.no_lock:
	move.l	intuition_base,a6
	move.l	screen,a0
	jsr		_LVOCloseScreen(a6)

	lea		no_lock_text,a0
	bsr		print_text

.free_buffer:
	move.l	exec_base,a6
	move.l	fast_buffer,a1
	move.l	#BENCH_SIZE*2,d0
	jsr		_LVOFreeMem(a6)

.close_timer:
	move.l	exec_base,a6
	lea		timer_request,a1
	jsr		_LVOCloseDevice(a6)

.close_picasso96:
	move.l	exec_base,a6
	move.l	picasso96_base,a1
	jsr		_LVOCloseLibrary(a6)

.close_intuition:
	move.l	exec_base,a6
	move.l	intuition_base,a1
	jsr		_LVOCloseLibrary(a6)

.close_dos:
	move.l	exec_base,a6
	move.l	dos_base,a1
	jsr		_LVOCloseLibrary(a6)

.exit:
	movem.l	(sp)+,d2-d7/a2-a6

	moveq	#0,d0

	rts

; d0 = buffer kind (0 fast, 1 second fast buffer, 2 card) -> d0 = address.

buffer_address:
	cmp.l	#BUFFER_CARD,d0
	beq		.card

	mulu.l	#BENCH_SIZE,d0
	add.l	fast_buffer,d0

	rts

.card:
	move.l	card_memory,d0

	rts

; -> d0 = E clock, low longword. Preserves the other registers.

read_eclock:
	movem.l	d1/a0-a1/a6,-(sp)

	move.l	timer_base,a6
	lea		eclock_value,a0
	jsr		_LVOReadEClock(a6)
	move.l	d0,eclock_frequency
	move.l	eclock_value+4,d0

	movem.l	(sp)+,d1/a0-a1/a6

	rts

; ------------------------------------------------------------------------------
;
; Results: per test, KB/s = BENCH_SIZE * REPETITIONS / 1024 * E clock /
; ticks, and ns per access (in quarters) = ticks * (4e9 / E clock) /
; accesses. Each test takes well under a second, so the products fit in
; 32 bits (no 64-bit instructions: they trap on a 68060).

print_results:
	lea		header_format,a0
	bsr		print_format

	lea		tests,a5
	lea		ticks,a4

.loop:
	tst.l	(a5)
	beq		.done

	lea		print_arguments,a3
	move.l	4(a5),(a3)+ ; Name.

	move.l	(a4),d1
	bne		.ticks_ok

	moveq	#1,d1

.ticks_ok:
	move.l	#BENCH_SIZE*REPETITIONS/1024,d0
	mulu.l	eclock_frequency,d0
	divu.l	d1,d0
	move.l	d0,(a3)+ ; KB/s.

	move.l	#$ee6b2800,d0 ; 4e9.
	divu.l	eclock_frequency,d0 ; Quarter ns per tick.
	mulu.l	(a4),d0
	divu.l	16(a5),d0 ; Quarter ns per access.
	move.l	d0,d1
	lsr.l	#2,d1
	move.l	d1,(a3)+
	and.l	#3,d0
	mulu	#25,d0
	move.l	d0,(a3)+

	lea		result_format,a0
	bsr		print_format

	addq.l	#4,a4
	lea		TEST_SIZE(a5),a5
	bra		.loop

.done:
	move.l	eclock_frequency,print_arguments
	lea		footer_format,a0
	bra		print_format

; a0 = text without arguments.

print_text:
	movem.l	d1-d2/a0-a1/a6,-(sp)

	move.l	dos_base,a6
	move.l	a0,d1
	moveq	#0,d2
	jsr		_LVOVPrintf(a6)

	movem.l	(sp)+,d1-d2/a0-a1/a6

	rts

; a0 = format, arguments in print_arguments.

print_format:
	movem.l	d1-d2/a0-a1/a6,-(sp)

	move.l	dos_base,a6
	move.l	a0,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	movem.l	(sp)+,d1-d2/a0-a1/a6

	rts

; ------------------------------------------------------------------------------
;
; Test routines: a0 = source, a1 = destination, REPETITIONS passes over
; BENCH_SIZE bytes, 16 accesses per unrolled step.

copy_long:
	moveq	#REPETITIONS-1,d7

.pass:
	move.l	a0,a2
	move.l	a1,a3
	move	#BENCH_SIZE/64-1,d6

.step:
	rept	16
	move.l	(a2)+,(a3)+
	endr

	dbf		d6,.step

	dbf		d7,.pass

	rts

write_long:
	moveq	#REPETITIONS-1,d7
	moveq	#0,d0

.pass:
	move.l	a1,a3
	move	#BENCH_SIZE/64-1,d6

.step:
	rept	16
	move.l	d0,(a3)+
	endr

	dbf		d6,.step

	dbf		d7,.pass

	rts

write_byte:
	moveq	#REPETITIONS-1,d7
	moveq	#0,d0

.pass:
	move.l	a1,a3
	move	#BENCH_SIZE/16-1,d6

.step:
	rept	16
	move.b	d0,(a3)+
	endr

	dbf		d6,.step

	dbf		d7,.pass

	rts

read_long:
	moveq	#REPETITIONS-1,d7

.pass:
	move.l	a0,a2
	move	#BENCH_SIZE/64-1,d6

.step:
	rept	16
	move.l	(a2)+,d0
	endr

	dbf		d6,.step

	dbf		d7,.pass

	rts

read_byte:
	moveq	#REPETITIONS-1,d7

.pass:
	move.l	a0,a2
	move	#BENCH_SIZE/16-1,d6

.step:
	rept	16
	move.b	(a2)+,d0
	endr

	dbf		d6,.step

	dbf		d7,.pass

	rts

; Read-modify-write of longs, as the game's text drawing does.

modify_long:
	moveq	#REPETITIONS-1,d7
	move.l	#$ff00ff00,d1
	moveq	#0,d2

.pass:
	move.l	a1,a3
	move	#BENCH_SIZE/64-1,d6

.step:
	rept	16
	move.l	(a3),d0
	and.l	d1,d0
	or.l	d2,d0
	move.l	d0,(a3)+
	endr

	dbf		d6,.step

	dbf		d7,.pass

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

BUFFER_FAST=0
BUFFER_FAST2=1
BUFFER_CARD=2

LONG_ACCESSES=BENCH_SIZE/4*REPETITIONS
BYTE_ACCESSES=BENCH_SIZE*REPETITIONS

; Tests: routine, name, source, destination, accesses.

TEST_SIZE=20

tests:
	dc.l	copy_long,copy_fast_name,BUFFER_FAST,BUFFER_FAST2,LONG_ACCESSES
	dc.l	copy_long,copy_card_name,BUFFER_FAST,BUFFER_CARD,LONG_ACCESSES
	dc.l	write_long,card_write_long_name,BUFFER_FAST,BUFFER_CARD,LONG_ACCESSES
	dc.l	write_byte,card_write_byte_name,BUFFER_FAST,BUFFER_CARD,BYTE_ACCESSES
	dc.l	read_long,card_read_long_name,BUFFER_CARD,BUFFER_FAST,LONG_ACCESSES
	dc.l	read_byte,card_read_byte_name,BUFFER_CARD,BUFFER_FAST,BYTE_ACCESSES
	dc.l	modify_long,card_modify_name,BUFFER_FAST,BUFFER_CARD,LONG_ACCESSES
	dc.l	write_long,fast_write_long_name,BUFFER_FAST,BUFFER_FAST,LONG_ACCESSES
	dc.l	write_byte,fast_write_byte_name,BUFFER_FAST,BUFFER_FAST,BYTE_ACCESSES
	dc.l	read_long,fast_read_long_name,BUFFER_FAST,BUFFER_FAST,LONG_ACCESSES
	dc.l	read_byte,fast_read_byte_name,BUFFER_FAST,BUFFER_FAST,BYTE_ACCESSES
	dc.l	modify_long,fast_modify_name,BUFFER_FAST,BUFFER_FAST,LONG_ACCESSES
	dc.l	0

TEST_COUNT=12

mode_tags:
	dc.l	P96BIDTAG_NominalWidth,SCREEN_WIDTH
	dc.l	P96BIDTAG_NominalHeight,SCREEN_HEIGHT
	dc.l	P96BIDTAG_Depth,8
	dc.l	P96BIDTAG_FormatsAllowed,RGBFF_CLUT
	dc.l	TAG_DONE

screen_tags:
	dc.l	SA_Width,SCREEN_WIDTH
	dc.l	SA_Height,SCREEN_HEIGHT
	dc.l	SA_Depth,8
screen_tags_mode:
	dc.l	SA_DisplayID,0
	dc.l	SA_Quiet,-1
	dc.l	SA_ShowTitle,0
	dc.l	SA_Type,CUSTOMSCREEN
	dc.l	TAG_DONE

dos_name:
	dc.b	'dos.library',0
intuition_name:
	dc.b	'intuition.library',0
picasso96_name:
	dc.b	'Picasso96API.library',0
timer_name:
	dc.b	'timer.device',0

copy_fast_name:
	dc.b	'copy fast RAM -> fast RAM (long)',0
copy_card_name:
	dc.b	'copy fast RAM -> card (long)',0
card_write_long_name:
	dc.b	'card write (long)',0
card_write_byte_name:
	dc.b	'card write (byte)',0
card_read_long_name:
	dc.b	'card read (long)',0
card_read_byte_name:
	dc.b	'card read (byte)',0
card_modify_name:
	dc.b	'card read-modify-write (long)',0
fast_write_long_name:
	dc.b	'fast RAM write (long)',0
fast_write_byte_name:
	dc.b	'fast RAM write (byte)',0
fast_read_long_name:
	dc.b	'fast RAM read (long)',0
fast_read_byte_name:
	dc.b	'fast RAM read (byte)',0
fast_modify_name:
	dc.b	'fast RAM read-modify-write (long)',0

header_format:
	dc.b	'Cho Ren Sha 68k: Picasso96 screen memory benchmark',10
	dc.b	'Mode $%08lx, bitmap on board: %ld, bytes per row: %ld, memory at $%08lx',10,10
	dc.b	'Test                                     KB/s   ns per access',10,0
result_format:
	dc.b	'%-36s %8ld   %5ld.%02ld',10,0
footer_format:
	dc.b	10,'E clock: %ld Hz',10,0
no_cpu_text:
	dc.b	'vram_bench needs a 68020 or better.',10,0
no_picasso96_text:
	dc.b	'vram_bench needs Picasso96 (Picasso96API.library).',10,0
no_fast_text:
	dc.b	'No fast RAM: the fast RAM tests use other memory.',10,0
no_mode_text:
	dc.b	'No 8-bit Picasso96 screen mode found.',10,0
no_screen_text:
	dc.b	'Could not open the screen.',10,0
no_lock_text:
	dc.b	'Could not lock the screen bitmap (or it is too small).',10,0

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

exec_base:
	ds.l	1
dos_base:
	ds.l	1
intuition_base:
	ds.l	1
picasso96_base:
	ds.l	1
timer_base:
	ds.l	1
fast_buffer:
	ds.l	1
card_memory:
	ds.l	1
screen:
	ds.l	1
bitmap:
	ds.l	1
lock:
	ds.l	1
eclock_frequency:
	ds.l	1
start_ticks:
	ds.l	1
eclock_value:
	ds.l	2
print_arguments:
	ds.l	8
ticks:
	ds.l	TEST_COUNT
lock_info:
	ds.b	RENDER_INFO_SIZE
	even
timer_request:
	ds.b	TIMEREQUEST_SIZE

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
