
; Background scroll in display time (option PARALLAX50).
;
; The game scrolls its two background layers by a counter that advances once
; per game frame (55.46 Hz): its VBL handler sets page 0 (the floor) to 4
; lines per count and page 1 (the far layer) to 1 line per count. Pictures
; are rendered right after a game frame's tick, but shown later: on AGA at a
; vertical blank (50 Hz), on RTG when uploaded. With the game's positions,
; a 50 Hz display shows the floor stepping 4, 4, 4, 4, 8 lines.
;
; With the option, each picture's background is drawn where the scroll will
; be when the picture is actually shown: the game's counter plus the time
; from its tick to the predicted display moment, in game frames. The
; constant part of that time (the average) is left out, so the background
; stays where the game puts it on average and only the steps between
; pictures change (at 50 Hz: 4, 4, 5, 4, 5 lines). The game, its timing and
; the sprites are unchanged.
;
; The display moment: the start of rendering plus the measured time from the
; start of rendering to the picture being shown (averaged); on AGA rounded up
; to the vertical blank (timed by a vertical blank server). Only pictures in
; a stage with the normal vertical scroll are moved: page 0 at 4 times page
; 1, no horizontal scroll, and the counter advanced by as many counts as
; frame timer ticks passed since the picture before (not in menus, pauses,
; or the rotated screen).

	xdef parallax_requested
	xdef start_parallax
	xdef stop_parallax
	xdef parallax_tick
	xdef picture_scroll
	xdef picture_page0_y
	xdef picture_page1_y
	xdef parallax_flipped
	xdef parallax_before_flip
	xdef parallax_uploaded
	xdef print_parallax_summary

	xref exec_base
	xref dos_base
	xref timer_base
	xref eclock_frequency
	xref frame_timer_type
	xref frame_timer_count
	xref display_active
	xref backend
	xref L_00E80000
	xref graphics_base

_LVOAddIntServer=-168
_LVORemIntServer=-174
_LVOVPrintf=-954
_LVOReadEClock=-60
_LVOWaitTOF=-270

NT_INTERRUPT=2
ln_Type=8
ln_Pri=9
ln_Name=10
is_Data=14
is_Code=18
IS_SIZE=22

INTB_VERTB=5
FRAME_TIMER_CIA=1
BACKEND_AGA=3

CRTC_PAGE0_X=$18
CRTC_PAGE0_Y=$1a
CRTC_PAGE1_X=$20
CRTC_PAGE1_Y=$22

; Vertical blank periods accepted (E clock ticks, about 709 kHz): 24 to
; 140 Hz.

MINIMUM_VBLANK_PERIOD=5000
MAXIMUM_VBLANK_PERIOD=30000

; At most this many frame timer ticks between two moved pictures.

MAXIMUM_PICTURE_TICKS=8

; A flip waits for at most this many vertical blanks.

MAXIMUM_FLIP_WAIT=3

; The vertical blank aimed at is the first one after the expected display
; moment plus a vertical blank >> MARGIN_SHIFT.

	ifnd MARGIN_SHIFT
MARGIN_SHIFT=2
	endif

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; After the frame timer has started (task context): turns the option on if it
; was requested and can be used, and says so.

start_parallax:
	tst.b	parallax_requested
	beq		.done

	movem.l	d2-d7/a2-a6,-(sp)

	ifd __LOCKSTEP__
	move.l	#parallax_lockstep_text,d1 ; Test builds: no real time.
	bra		.unavailable
	endif

	move.l	#parallax_no_display_text,d1
	tst.b	display_active
	beq		.unavailable

	move.l	#parallax_vertical_blank_text,d1
	cmp.l	#FRAME_TIMER_CIA,frame_timer_type
	bne		.unavailable

	cmp.l	#BACKEND_AGA,backend
	bne		.server_done

	lea		parallax_interrupt,a1
	move.b	#NT_INTERRUPT,ln_Type(a1)
	clr.b	ln_Pri(a1)
	move.l	#parallax_interrupt_name,ln_Name(a1)
	clr.l	is_Data(a1)
	move.l	#parallax_vertical_blank,is_Code(a1)
	move.l	exec_base,a6
	moveq	#INTB_VERTB,d0
	jsr		_LVOAddIntServer(a6)
	st		parallax_server

.server_done:
	st		parallax_active
	move.l	#parallax_on_text,d1

	bra		.print

.unavailable:
	move.l	d1,parallax_print_arguments
	move.l	#parallax_unused_format,d1

.print:
	move.l	#parallax_print_arguments,d2
	move.l	dos_base,a6
	jsr		_LVOVPrintf(a6)

	movem.l	(sp)+,d2-d7/a2-a6

.done:
	rts

; Before the display closes (task context).

stop_parallax:
	sf		parallax_active

	tst.b	parallax_server
	beq		.done

	movem.l	d0-d1/a0-a1/a6,-(sp)

	sf		parallax_server
	move.l	exec_base,a6
	lea		parallax_interrupt,a1
	moveq	#INTB_VERTB,d0
	jsr		_LVORemIntServer(a6)

	movem.l	(sp)+,d0-d1/a0-a1/a6

.done:
	rts

; Frame timer tick (hardware interrupt, before the game's VBL handler runs):
; its time. Uses d0-d1/a0-a1/a6.

parallax_tick:
	tst.b	parallax_active
	beq		.done

	move.l	timer_base,a6
	lea		parallax_tick_eclock,a0
	jsr		_LVOReadEClock(a6)
	move.l	parallax_tick_eclock+4,parallax_tick_time
	addq.l	#1,parallax_ticks

.done:
	rts

; Vertical blank server (AGA): the time of each vertical blank and the
; period between them (averaged).

parallax_vertical_blank:
	move.l	timer_base,a6
	lea		parallax_vblank_eclock,a0
	jsr		_LVOReadEClock(a6)

	move.l	parallax_vblank_eclock+4,d0
	move.l	d0,d1
	sub.l	parallax_vblank_time,d1
	move.l	d0,parallax_vblank_time

	cmp.l	#MINIMUM_VBLANK_PERIOD,d1
	bcs		.counted

	cmp.l	#MAXIMUM_VBLANK_PERIOD,d1
	bhi		.counted

	move.l	parallax_vblank_period,d0
	bne		.average

	move.l	d1,parallax_vblank_period

	bra		.counted

.average:
	sub.l	d0,d1
	asr.l	#3,d1
	add.l	d1,parallax_vblank_period

.counted:
	addq.l	#1,parallax_vblanks

	moveq	#0,d0 ; Let the other vertical blank servers run.

	rts

; At the start of each picture (task context, after the layers are built):
; picture_page0_y and picture_page1_y = the vertical scroll of the
; background layers to draw. Preserves all registers.

picture_scroll:
	move	L_00E80000+CRTC_PAGE0_Y,picture_page0_y
	move	L_00E80000+CRTC_PAGE1_Y,picture_page1_y

	tst.b	parallax_active
	bne		.active

	rts

.active:
	movem.l	d0-d7/a0-a1/a6,-(sp)

	clr.l	parallax_predicted
	sf		parallax_picture_moved

	move.l	timer_base,a6
	lea		parallax_task_eclock,a0
	jsr		_LVOReadEClock(a6)
	move.l	parallax_task_eclock+4,d7 ; Now.
	move.l	d7,parallax_picture_start

	; The scroll registers and their tick, together (a tick in between
	; reads them again).

.read_tick:
	move.l	parallax_ticks,d4
	move	L_00E80000+CRTC_PAGE0_X,d0
	or		L_00E80000+CRTC_PAGE1_X,d0
	move	L_00E80000+CRTC_PAGE0_Y,d2
	move	L_00E80000+CRTC_PAGE1_Y,d3
	move.l	parallax_tick_time,d6
	cmp.l	parallax_ticks,d4
	bne		.read_tick

	neg		d3
	ext.l	d3 ; Counter.

	move.l	d4,d5
	sub.l	parallax_last_ticks,d5 ; Ticks since the picture before.
	move.l	d4,parallax_last_ticks
	move	d3,d1
	sub		parallax_last_counter,d1 ; Counts since then.
	move	d3,parallax_last_counter

	and		#511,d0
	bne		.done ; Horizontal scroll (rotated screen).

	move	d3,d0
	asl		#2,d0
	neg		d0
	cmp		d0,d2
	bne		.done ; Not the game's normal scroll.

	tst.l	d5
	beq		.done

	cmp.l	#MAXIMUM_PICTURE_TICKS,d5
	bhi		.done

	ext.l	d1
	cmp.l	d5,d1
	bne		.done ; Not scrolling with the ticks.

	; The display moment: now plus the measured latency.

	move.l	parallax_latency,d0
	add.l	d7,d0

	tst.b	parallax_server
	beq		.timed

	; AGA: the first vertical blank at or after it plus a quarter vertical blank
	; (the flip waits for it when the picture is ready earlier).

.read_vblank:
	move.l	parallax_vblanks,d5
	move.l	parallax_vblank_time,d1
	move.l	parallax_vblank_period,d2
	cmp.l	parallax_vblanks,d5
	bne		.read_vblank

	tst.l	d2
	beq		.timed ; Not measured yet.

	move.l	d2,d4
	lsr.l	#MARGIN_SHIFT,d4
	add.l	d4,d0

	sub.l	d1,d0 ; From the last vertical blank.
	bpl		.after_vblank

	moveq	#0,d0 ; A vertical blank came after "now" was read.

.after_vblank:
	add.l	d2,d0
	subq.l	#1,d0
	divu.l	d2,d0 ; Vertical blanks after it, rounded up.
	bne		.vblanks_ok

	moveq	#1,d0

.vblanks_ok:
	add.l	d0,d5
	move.l	d5,parallax_predicted
	mulu.l	d2,d0
	add.l	d1,d0

.timed:
	; From the counter's tick to the display moment, against the average.

	sub.l	d6,d0

	tst.b	parallax_average_valid
	bne		.average

	move.l	d0,parallax_average
	st		parallax_average_valid

.average:
	move.l	d0,d1
	sub.l	parallax_average,d1
	move.l	d1,d2
	asr.l	#4,d2
	add.l	d2,parallax_average

	; At most 1.5 frames either way.

	move.l	frame_timer_count,d2
	move.l	d2,d0
	lsr.l	#1,d0
	add.l	d0,d2

	cmp.l	d2,d1
	ble		.not_above

	move.l	d2,d1

.not_above:
	neg.l	d2
	cmp.l	d2,d1
	bge		.not_below

	move.l	d2,d1

.not_below:
	; Position in 1/256 counts: counter * 256 + time * 256 / frame time.

	asl.l	#8,d1
	divs.l	frame_timer_count,d1
	asl.l	#8,d3
	move.l	d3,parallax_picture_counter
	add.l	d1,d3
	move.l	d3,parallax_picture_position
	st		parallax_picture_moved

	move.l	d3,d0
	add.l	#128,d0
	asr.l	#8,d0
	neg.l	d0
	move	d0,picture_page1_y

	asl.l	#2,d3
	add.l	#128,d3
	asr.l	#8,d3
	neg.l	d3
	move	d3,picture_page0_y

	addq.l	#1,parallax_pictures

.done:
	movem.l	(sp)+,d0-d7/a0-a1/a6

	rts

; AGA (task context): the picture started last is about to be handed to
; ChangeScreenBuffer, which shows it at the next vertical blank. Measures the
; latency (as if shown at the next one), then waits until the next vertical
; blank is the predicted one. Preserves all registers.

parallax_before_flip:
	tst.b	parallax_server
	bne		.active

	rts

.active:
	movem.l	d0-d2/a0-a1/a6,-(sp)

.read_vblank:
	move.l	parallax_vblanks,d0
	move.l	parallax_vblank_time,d1
	move.l	parallax_vblank_period,d2
	cmp.l	parallax_vblanks,d0
	bne		.read_vblank

	tst.l	d2
	beq		.done

	add.l	d2,d1 ; The next vertical blank, about.
	bsr		parallax_latency_sample

	move.l	parallax_predicted,d1
	beq		.done

	ifd __PARALLAX_NO_WAIT__
	bra		.done
	endif

.wait:
	move.l	d1,d0
	sub.l	parallax_vblanks,d0
	subq.l	#1,d0 ; Vertical blanks to wait.
	ble		.done

	cmp.l	#MAXIMUM_FLIP_WAIT,d0
	bhi		.done

	addq.l	#1,parallax_waits
	move.l	graphics_base,a6
	jsr		_LVOWaitTOF(a6)

	bra		.wait

.done:
	movem.l	(sp)+,d0-d2/a0-a1/a6

	rts

; AGA (task context): ChangeScreenBuffer has taken the picture started
; last; it is shown at the next vertical blank. Checks the prediction.
; Preserves all registers.

parallax_flipped:
	tst.b	parallax_server
	bne		.active

	rts

.active:
	movem.l	d0-d3,-(sp)

	move.l	parallax_predicted,d0
	beq		.steps

	clr.l	parallax_predicted
	addq.l	#1,parallax_predictions
	sub.l	parallax_vblanks,d0
	subq.l	#1,d0
	bne		.steps

	addq.l	#1,parallax_predictions_right

.steps:
	; Smoothness: between two moved pictures shown up to 8 vertical blanks
	; apart, how far the scroll moved against how far it moves in that
	; time, for the drawn position and for the game's own.

	move.l	parallax_vblanks,d0
	addq.l	#1,d0 ; Shown at this vertical blank.

	tst.b	parallax_picture_moved
	beq		.not_moved

	sf		parallax_picture_moved
	tst.b	parallax_last_moved
	beq		.remember

	move.l	d0,d1
	sub.l	parallax_last_shown,d1
	beq		.remember

	cmp.l	#8,d1
	bhi		.remember

	; Expected: vertical blanks * period * 256 / frame time.

	mulu.l	parallax_vblank_period,d1
	asl.l	#8,d1
	divu.l	frame_timer_count,d1

	move.l	parallax_picture_position,d2
	sub.l	parallax_last_position,d2
	sub.l	d1,d2
	bpl		.drawn_positive

	neg.l	d2

.drawn_positive:
	add.l	d2,parallax_drawn_error

	move.l	parallax_picture_counter,d2
	sub.l	parallax_last_counter_256,d2
	sub.l	d1,d2
	bpl		.game_positive

	neg.l	d2

.game_positive:
	add.l	d2,parallax_game_error
	addq.l	#1,parallax_steps

.remember:
	move.l	d0,parallax_last_shown
	move.l	parallax_picture_position,parallax_last_position
	move.l	parallax_picture_counter,parallax_last_counter_256
	st		parallax_last_moved

	bra		.done

.not_moved:
	sf		parallax_last_moved

.done:
	movem.l	(sp)+,d0-d3

	rts

; RTG (task context): the picture started last has been uploaded. Preserves
; all registers.

parallax_uploaded:
	tst.b	parallax_active
	beq		.done

	tst.b	parallax_server
	bne		.done

	movem.l	d0-d1/a0-a1/a6,-(sp)

	move.l	timer_base,a6
	lea		parallax_task_eclock,a0
	jsr		_LVOReadEClock(a6)
	move.l	parallax_task_eclock+4,d1
	bsr		parallax_latency_sample

	movem.l	(sp)+,d0-d1/a0-a1/a6

.done:
	rts

; d1 = the time the picture is shown: averages the time from the start of
; its rendering. Uses d1.

parallax_latency_sample:
	sub.l	parallax_picture_start,d1

	tst.b	parallax_latency_valid
	bne		.average

	move.l	d1,parallax_latency
	st		parallax_latency_valid

	rts

.average:
	sub.l	parallax_latency,d1
	asr.l	#3,d1
	add.l	d1,parallax_latency

	rts

; After the run (task context, measurement summary): how many pictures were
; moved, how often the vertical blank was predicted right, and the latency.

print_parallax_summary:
	tst.b	parallax_requested
	beq		.done

	movem.l	d2-d7/a2-a6,-(sp)

	move.l	parallax_pictures,parallax_print_arguments
	move.l	parallax_predictions_right,parallax_print_arguments+4
	move.l	parallax_predictions,parallax_print_arguments+8
	move.l	parallax_waits,parallax_print_arguments+20

	; Mean floor step error (page 0, 4 lines per count) in 1/100 lines.

	move.l	parallax_steps,d1
	beq		.steps_set

	move.l	parallax_drawn_error,d0
	mulu.l	#400,d0
	asr.l	#8,d0
	divu.l	d1,d0
	move.l	d0,parallax_print_arguments+28
	move.l	parallax_game_error,d0
	mulu.l	#400,d0
	asr.l	#8,d0
	divu.l	d1,d0
	move.l	d0,parallax_print_arguments+32

.steps_set:
	move.l	d1,parallax_print_arguments+24

	; Latency in 1/10 ms.

	move.l	eclock_frequency,d1
	divu.l	#10000,d1
	moveq	#0,d0
	tst.l	d1
	beq		.latency_set

	move.l	parallax_latency,d0
	divu.l	d1,d0

.latency_set:
	divu	#10,d0
	moveq	#0,d1
	move	d0,d1
	move.l	d1,parallax_print_arguments+12
	swap	d0
	move	d0,d1
	move.l	d1,parallax_print_arguments+16

	move.l	#parallax_summary_format,d1
	move.l	#parallax_print_arguments,d2
	move.l	dos_base,a6
	jsr		_LVOVPrintf(a6)

	movem.l	(sp)+,d2-d7/a2-a6

.done:
	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

parallax_interrupt_name:
	dc.b	'ChoRenSha parallax',0
parallax_on_text:
	dc.b	'Background: scrolled to each picture',39,'s display time (PARALLAX50).',10,0
parallax_unused_format:
	dc.b	'PARALLAX50: not used (%s).',10,0
parallax_no_display_text:
	dc.b	'no display',0
parallax_vertical_blank_text:
	dc.b	'the game is timed by the vertical blank',0
	ifd __LOCKSTEP__
parallax_lockstep_text:
	dc.b	'lockstep test build',0
	endif
parallax_summary_format:
	dc.b	'Parallax: %ld pictures moved, vertical blank predicted right %ld of %ld times, latency %ld.%ld ms, waited %ld vertical blanks; %ld steps, floor step error %ld/100 lines (game',39,'s position: %ld/100).',10,0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

	cnop	0,4

parallax_interrupt:
	ds.b	IS_SIZE
	cnop	0,4
parallax_tick_eclock:
	ds.l	2
parallax_vblank_eclock:
	ds.l	2
parallax_task_eclock:
	ds.l	2
parallax_print_arguments:
	ds.l	9
parallax_tick_time: ; E clock (low longword) of the last frame timer tick.
	ds.l	1
parallax_ticks:
	ds.l	1
parallax_vblank_time:
	ds.l	1
parallax_vblank_period:
	ds.l	1
parallax_vblanks:
	ds.l	1
parallax_picture_start:
	ds.l	1
parallax_latency:
	ds.l	1
parallax_average:
	ds.l	1
parallax_last_ticks:
	ds.l	1
parallax_predicted: ; The vertical blank expected to show the picture, or 0.
	ds.l	1
parallax_predictions:
	ds.l	1
parallax_predictions_right:
	ds.l	1
parallax_pictures:
	ds.l	1
parallax_waits:
	ds.l	1
parallax_picture_position: ; Drawn, in 1/256 counts.
	ds.l	1
parallax_picture_counter: ; The game's, in 1/256 counts.
	ds.l	1
parallax_last_position:
	ds.l	1
parallax_last_counter_256:
	ds.l	1
parallax_last_shown:
	ds.l	1
parallax_drawn_error:
	ds.l	1
parallax_game_error:
	ds.l	1
parallax_steps:
	ds.l	1
parallax_last_counter:
	ds.w	1
picture_page0_y:
	ds.w	1
picture_page1_y:
	ds.w	1
parallax_requested:
	ds.b	1
parallax_active:
	ds.b	1
parallax_server:
	ds.b	1
parallax_average_valid:
	ds.b	1
parallax_latency_valid:
	ds.b	1
parallax_picture_moved:
	ds.b	1
parallax_last_moved:
	ds.b	1
