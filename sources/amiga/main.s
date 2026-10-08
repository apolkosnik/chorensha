
; Amiga entry point.
;
; Minimum: a 68020 or better with an RTG card, or an AGA Amiga with 8 MB of
; fast RAM. The main target is a 68030 at 50 MHz with an RTG card. This file
; is assembled with -m68000 so it reports missing requirements instead of
; crashing on a lesser CPU; the executable still needs about 2.3 MB of free
; memory to load at all (mostly the X68000 shadow buffers in mem_map.s).
;
; Usage: sz2 [frames [input script]]
;
; With a frame count the game exits after that many frames and the per-frame
; measurements are written to measure.bin in the current directory. An input
; script (see tests/amiga/make_input_script.py) feeds the joystick for tests.

	xdef start
	xdef start_of_code

	xdef exec_base
	xdef dos_base
	xdef machine_display
	xdef machine_cpu
	xdef machine_rtg

	xref start_emulator
	xref heap_used
	xref frame_count
	xref measured_frames
	xref frame_records
	xref free_frame_records
	xref checkpoints
	xref checkpoint_count
	xref eclock_frequency
	xref unimplemented_iocs
	xref exit_reason
	xref rendered_frames
	xref total_vbl_count
	xref frame_timer_text
	xref frame_timer_hz100

	ifd __RENDER_PROFILE__
	xref render_profile
	xref palette_rebuilds
	xref load_rgb_time
	xref text_lines_converted
	xref text_lines_drawn
	xref text_remaps
	xref c2p_time
	xref palette_entry_changes
	endif

; exec.library

_LVOForbid=-132
_LVOCacheControl=-648
_LVOAvailMem=-216
_LVOFindTask=-294
_LVOGetMsg=-372
_LVOReplyMsg=-378
_LVOWaitPort=-384
_LVOCloseLibrary=-414
_LVOOpenLibrary=-552

AttnFlags=296
AFB_68020=1
AFB_68030=2
AFB_68040=3
AFB_68881=4
AFB_68882=5
AFB_FPU40=6
AFB_68060=7

MEMF_CHIP=1<<1
MEMF_FAST=1<<2
MEMF_TOTAL=1<<19

; Fast RAM needed for the native AGA output. MEMF_TOTAL counts the memory
; list headers out, so an 8 MB board reports slightly less than 8192 kB.

AGA_MINIMUM_FAST_KB=8000

pr_MsgPort=92
pr_CLI=172

; dos.library

_LVOOpen=-30
_LVOClose=-36
_LVOWrite=-48
_LVOPutStr=-948
_LVOVPrintf=-954

MODE_NEWFILE=1006

; Picasso96API.library

_LVOp96GetRTGDataTagList=-180
P96RD_NumberOfBoards=$80040061

; cybergraphics.library

_LVOIsCyberModeID=-54

; graphics.library

_LVONextDisplayInfo=-732
INVALID_ID=-1

gb_ChipRevBits0=236
GFXB_HR_AGNUS=0

; Custom chips

DENISEID=$dff07c
DENISEID_ECS=$fc
DENISEID_LISA=$f8

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

start_of_code: ; Start of the code hunk, for reporting crash addresses.
start:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	a0,argument_string ; CLI arguments (ignored for Workbench starts).
	move.l	d0,argument_length

	move.l	$4.w,a6
	move.l	a6,exec_base

	; Workbench start: wait for and keep the startup message.

	sub.l	a1,a1
	jsr		_LVOFindTask(a6)
	move.l	d0,a2

	tst.l	pr_CLI(a2)
	bne		.from_cli

	lea		pr_MsgPort(a2),a0
	jsr		_LVOWaitPort(a6)
	lea		pr_MsgPort(a2),a0
	jsr		_LVOGetMsg(a6)
	move.l	d0,workbench_message

.from_cli:
	lea		dos_name,a1
	moveq	#36,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,dos_base
	beq		.exit

	lea		graphics_name,a1
	moveq	#36,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,graphics_base
	beq		.close_dos

	jsr		detect_machine
	jsr		select_display
	jsr		print_info_text

	tst.l	machine_display
	beq		.close_graphics

	jsr		parse_frame_limit

	ifd __NO_CPU_CACHES__

	; Test builds: instruction and data caches off for the run (the
	; X68000 original ran on a 68000 without caches).

	move.l	exec_base,a6
	moveq	#0,d0
	move.l	#$0101,d1 ; CACRF_EnableI | CACRF_EnableD
	jsr		_LVOCacheControl(a6)
	move.l	d0,saved_cache_bits

	endif

	move.l	frame_limit,d0
	move.l	input_script_name,a0
	jsr		start_emulator

	ifd __NO_CPU_CACHES__

	move.l	d0,-(sp)
	move.l	exec_base,a6
	move.l	saved_cache_bits,d0
	move.l	#$0101,d1
	jsr		_LVOCacheControl(a6)
	move.l	(sp)+,d0

	endif
	tst.l	d0
	bmi		.emulator_failed

	jsr		print_run_summary

	tst.l	frame_limit
	beq		.close_graphics

	jsr		write_measurements

	jsr		free_frame_records

	bra		.close_graphics

.emulator_failed:
	move.l	dos_base,a6
	move.l	#emulator_failed_text,d1
	jsr		_LVOPutStr(a6)

.close_graphics:

	move.l	exec_base,a6
	move.l	graphics_base,a1
	jsr		_LVOCloseLibrary(a6)

.close_dos:
	move.l	exec_base,a6
	move.l	dos_base,a1
	jsr		_LVOCloseLibrary(a6)

.exit:
	move.l	exec_base,a6

	move.l	workbench_message,d0
	beq		.no_workbench_message

	jsr		_LVOForbid(a6)
	move.l	workbench_message,a1
	jsr		_LVOReplyMsg(a6)

.no_workbench_message:
	movem.l	(sp)+,d2-d7/a2-a6

	moveq	#0,d0

	rts

; ------------------------------------------------------------------------------

detect_machine:
	move.l	exec_base,a6

	; CPU: 68000 + 10 * index of the highest AttnFlags CPU bit.

	move	AttnFlags(a6),d0

	moveq	#0,d1
	btst	#0,d0
	beq		.no_68010
	moveq	#10,d1
.no_68010:
	btst	#AFB_68020,d0
	beq		.no_68020
	moveq	#20,d1
.no_68020:
	btst	#AFB_68030,d0
	beq		.no_68030
	moveq	#30,d1
.no_68030:
	btst	#AFB_68040,d0
	beq		.no_68040
	moveq	#40,d1
.no_68040:
	btst	#AFB_68060,d0
	beq		.no_68060
	moveq	#60,d1
.no_68060:
	move.l	d1,machine_cpu

	; FPU: 0 = none, 1 = 68881, 2 = 68882, 3 = internal (68040/68060).

	moveq	#0,d1
	btst	#AFB_68881,d0
	beq		.no_68881
	moveq	#1,d1
.no_68881:
	btst	#AFB_68882,d0
	beq		.no_68882
	moveq	#2,d1
.no_68882:
	btst	#AFB_FPU40,d0
	beq		.no_fpu40
	moveq	#3,d1
.no_fpu40:
	move.l	d1,machine_fpu

	; Chipset: 0 = OCS, 1 = ECS, 2 = AGA.
	;
	; The AA bits in gb_ChipRevBits0 are only set once SetPatch has called
	; SetChipRev(), so AGA is detected from the Denise/Lisa ID register. An
	; OCS Denise has no ID register: reads return bus noise, so the value
	; must be stable over several reads to count.

	lea		DENISEID,a0
	move	(a0),d0
	and		#$ff,d0
	moveq	#32-1,d2

.denise_id_loop:
	move	(a0),d1
	and		#$ff,d1
	cmp		d0,d1
	bne		.ocs_denise

	dbf		d2,.denise_id_loop

	moveq	#2,d1
	cmp		#DENISEID_LISA,d0
	beq		.chipset_found

	moveq	#1,d1
	cmp		#DENISEID_ECS,d0
	beq		.chipset_found

.ocs_denise:
	moveq	#0,d1
	move.l	graphics_base,a0
	btst	#GFXB_HR_AGNUS,gb_ChipRevBits0(a0)
	beq		.chipset_found

	moveq	#1,d1

.chipset_found:
	move.l	d1,machine_chipset

	; RTG: 0 = none, 1 = Picasso96, 2 = CyberGraphX.
	;
	; Picasso96API.library opens without any board installed, so Picasso96
	; counts only when it reports at least one board. cybergraphics.library
	; may be Picasso96's compatibility layer, so CyberGraphX counts only when
	; the display database holds at least one CyberGraphX mode.

	clr.l	machine_rtg

	lea		picasso96_name,a1
	moveq	#2,d0
	jsr		_LVOOpenLibrary(a6)
	tst.l	d0
	beq		.no_picasso96

	move.l	d0,a6
	clr.l	rtg_board_count
	lea		rtg_board_count_tags,a0
	jsr		_LVOp96GetRTGDataTagList(a6)

	move.l	a6,a1
	move.l	exec_base,a6
	jsr		_LVOCloseLibrary(a6)

	tst.l	rtg_board_count
	beq		.no_picasso96

	move.l	#1,machine_rtg

	bra		.rtg_done

.no_picasso96:
	lea		cybergraphics_name,a1
	moveq	#40,d0
	jsr		_LVOOpenLibrary(a6)
	tst.l	d0
	beq		.rtg_done

	move.l	d0,a5
	move.l	graphics_base,a4
	moveq	#INVALID_ID,d3

.cybergraphics_mode_loop:
	move.l	d3,d0
	move.l	a4,a6
	jsr		_LVONextDisplayInfo(a6)
	move.l	d0,d3
	cmp.l	#INVALID_ID,d3
	beq		.cybergraphics_done

	move.l	a5,a6
	jsr		_LVOIsCyberModeID(a6)
	tst		d0
	beq		.cybergraphics_mode_loop

	move.l	#2,machine_rtg

.cybergraphics_done:
	move.l	a5,a1
	move.l	exec_base,a6
	jsr		_LVOCloseLibrary(a6)

.rtg_done:

	; Free memory in kB.

	moveq	#MEMF_CHIP,d1
	jsr		_LVOAvailMem(a6)
	moveq	#10,d1
	lsr.l	d1,d0
	move.l	d0,machine_chip_kb

	moveq	#MEMF_FAST,d1
	jsr		_LVOAvailMem(a6)
	moveq	#10,d1
	lsr.l	d1,d0
	move.l	d0,machine_fast_kb

	move.l	#MEMF_FAST|MEMF_TOTAL,d1
	jsr		_LVOAvailMem(a6)
	moveq	#10,d1
	lsr.l	d1,d0
	move.l	d0,machine_fast_total_kb

	rts

; ------------------------------------------------------------------------------

print_info_text:
	move.l	dos_base,a6

	move.l	#welcome_text,d1
	jsr		_LVOPutStr(a6)

	; Machine line.

	move.l	machine_chipset,d0
	lsl		#2,d0
	lea		chipset_text_table,a0
	move.l	(a0,d0.w),print_arguments+4

	move.l	machine_fpu,d0
	lsl		#2,d0
	lea		fpu_text_table,a0
	move.l	(a0,d0.w),print_arguments+8

	move.l	machine_rtg,d0
	lsl		#2,d0
	lea		rtg_text_table,a0
	move.l	(a0,d0.w),print_arguments+24

	move.l	machine_cpu,print_arguments
	move.l	machine_chip_kb,print_arguments+12
	move.l	machine_fast_total_kb,print_arguments+16
	move.l	machine_fast_kb,print_arguments+20

	move.l	#machine_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	; Display path.

	move.l	machine_display,d0
	lsl		#2,d0
	lea		display_text_table,a0
	move.l	(a0,d0.w),d1
	jsr		_LVOPutStr(a6)

	tst.l	machine_display
	bne		.supported

	move.l	#requirements_text,d1
	jsr		_LVOPutStr(a6)

	rts

.supported:
	rts

; ------------------------------------------------------------------------------
;
; The first number on the command line is the frame limit (0 if none).
; Only called on supported machines (68020 or better).

	machine	68020

parse_frame_limit:
	moveq	#0,d0

	tst.l	workbench_message
	bne		.done

	move.l	argument_string,a0
	move.l	argument_length,d1
	beq		.done

.skip_spaces:
	move.b	(a0),d2
	cmp.b	#' ',d2
	bne		.digits

	addq.l	#1,a0
	subq.l	#1,d1
	bne		.skip_spaces

	bra		.done

.digits:
	moveq	#0,d2
	move.b	(a0)+,d2
	sub.b	#'0',d2
	cmp.b	#9,d2
	bhi		.script_name

	mulu.l	#10,d0
	add.l	d2,d0

	subq.l	#1,d1
	bne		.digits

	bra		.done

.script_name:
	; After the number: optional input script name (up to a space or the
	; end of the line).

	subq.l	#1,a0

.skip_spaces2:
	move.b	(a0),d2
	cmp.b	#' ',d2
	bne		.name_start

	addq.l	#1,a0
	subq.l	#1,d1
	bne		.skip_spaces2

	bra		.done

.name_start:
	cmp.b	#10,d2
	beq		.done

	lea		input_script_name_buffer,a1
	move.l	a1,input_script_name
	moveq	#64-2,d3

.name_loop:
	move.b	(a0)+,d2
	cmp.b	#' ',d2
	bls		.name_end

	move.b	d2,(a1)+
	subq.l	#1,d1
	dbeq	d3,.name_loop

.name_end:
	clr.b	(a1)

.done:
	move.l	d0,frame_limit

	rts

	machine	68000

; ------------------------------------------------------------------------------

print_run_summary:
	move.l	dos_base,a6

	move.l	frame_count,print_arguments
	move.l	measured_frames,print_arguments+4
	move.l	eclock_frequency,print_arguments+8
	move.l	heap_used,print_arguments+12
	move.l	rendered_frames,print_arguments+16
	move.l	total_vbl_count,print_arguments+20

	move.l	#run_summary_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	move.l	exit_reason,d0
	lsl		#2,d0
	lea		exit_reason_table,a0
	move.l	(a0,d0.w),print_arguments
	move.l	frame_timer_text,print_arguments+4
	move.l	frame_timer_hz100,d0
	divu	#100,d0
	moveq	#0,d1
	move	d0,d1
	move.l	d1,print_arguments+8
	swap	d0
	move	d0,d1
	move.l	d1,print_arguments+12

	move.l	#exit_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	ifd __RENDER_PROFILE__

	; Average 1/100 ms per frame for each render stage (ticks * 100000 /
	; frequency / frames), and palette rebuilds. Supported machines only,
	; so 68020 code.

	machine	68020

	; Nothing to report if the game left before its first frame (missing
	; data files): the averages would divide by zero.

	tst.l	frame_count
	beq		.no_profile

	tst.l	eclock_frequency
	beq		.no_profile

	lea		render_profile,a2
	lea		print_arguments,a3
	moveq	#5-1,d3

.profile_loop:
	move.l	(a2)+,d0
	mulu.l	#100000,d1:d0
	divu.l	eclock_frequency,d1:d0
	move.l	frame_count,d1
	beq		.no_frames

	divul.l	d1,d1:d0

.no_frames:
	move.l	d0,(a3)+

	dbf		d3,.profile_loop

	move.l	palette_rebuilds,(a3)+
	move.l	load_rgb_time,d0
	mulu.l	#100000,d1:d0
	divu.l	eclock_frequency,d1:d0
	move.l	frame_count,d1
	divul.l	d1,d1:d0
	move.l	d0,(a3)+
	move.l	text_lines_converted,(a3)+
	move.l	text_lines_drawn,(a3)+
	move.l	text_remaps,(a3)+
	move.l	c2p_time,d0 ; Per rendered frame, 1/100 ms.
	mulu.l	#100000,d1:d0
	divu.l	eclock_frequency,d1:d0
	move.l	rendered_frames,d1
	beq		.no_c2p_frames

	divul.l	d1,d1:d0

.no_c2p_frames:
	move.l	d0,(a3)+

	move.l	#profile_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	; Palette entries that changed in more than 100 rebuilds.

	lea		palette_entry_changes,a2
	moveq	#0,d3

.entry_loop:
	moveq	#0,d0
	move	(a2,d3.l*2),d0
	cmp		#100,d0
	bls		.next_entry

	move.l	d3,print_arguments
	move.l	d0,print_arguments+4
	move.l	#entry_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

.next_entry:
	addq.l	#1,d3
	cmp.l	#512,d3
	bne		.entry_loop

.no_profile:
	machine	68000

	endif

	; IOCS calls the game made that are not implemented yet.

	lea		unimplemented_iocs,a2
	moveq	#0,d3

.iocs_loop:
	tst.b	(a2,d3.l)
	beq		.next_iocs

	move.l	d3,print_arguments
	move.l	#unimplemented_iocs_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

.next_iocs:
	addq.l	#1,d3
	cmp.l	#256,d3
	bne		.iocs_loop

	rts

; ------------------------------------------------------------------------------
;
; measure.bin: 'CRS2', E clock frequency, number of records, then per frame
; E clock ticks of the game (long), of rendering and display (long), sprites
; (word), vertical blanks passed while the game worked (word).

write_measurements:
	move.l	dos_base,a6

	move.l	#measure_file_name,d1
	move.l	#MODE_NEWFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,d4
	beq		.failed

	move.l	#'CRS2',measure_header
	move.l	eclock_frequency,measure_header+4
	move.l	measured_frames,measure_header+8

	move.l	d4,d1
	move.l	#measure_header,d2
	moveq	#12,d3
	jsr		_LVOWrite(a6)

	move.l	d4,d1
	move.l	frame_records,d2
	move.l	measured_frames,d3 ; * 12 (FRAME_RECORD_SIZE), 68000 code.
	lsl.l	#2,d3
	move.l	d3,d0
	add.l	d3,d3
	add.l	d0,d3
	jsr		_LVOWrite(a6)

	move.l	d4,d1
	jsr		_LVOClose(a6)

	; checkpoints.bin: 'CRSC', number of checkpoints, then the 32-byte
	; checkpoints (see CHECKPOINT_SIZE in emulator.s).

	move.l	#checkpoints_file_name,d1
	move.l	#MODE_NEWFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,d4
	beq		.failed

	move.l	#'CRSC',measure_header
	move.l	checkpoint_count,measure_header+4

	move.l	d4,d1
	move.l	#measure_header,d2
	moveq	#8,d3
	jsr		_LVOWrite(a6)

	move.l	d4,d1
	move.l	checkpoints,d2
	move.l	checkpoint_count,d3
	lsl.l	#5,d3
	jsr		_LVOWrite(a6)

	move.l	d4,d1
	jsr		_LVOClose(a6)

	rts

.failed:
	move.l	#measure_file_failed_text,d1
	jsr		_LVOPutStr(a6)

	rts

; ------------------------------------------------------------------------------
;
; Display path: 0 = unsupported, 1 = RTG, 2 = native AGA.
;
; Minimum: a 68020 or better with an RTG card, or an AGA Amiga (68020 or
; better) with 8 MB of fast RAM. RTG is preferred when both are available.

select_display:
	moveq	#0,d0

	cmp.l	#20,machine_cpu
	bcs		.done

	moveq	#1,d0
	tst.l	machine_rtg
	bne		.done

	moveq	#0,d0
	cmp.l	#2,machine_chipset
	bne		.done

	cmp.l	#AGA_MINIMUM_FAST_KB,machine_fast_total_kb
	bcs		.done

	moveq	#2,d0

.done:
	move.l	d0,machine_display

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

dos_name:
	dc.b	'dos.library',0

graphics_name:
	dc.b	'graphics.library',0

picasso96_name:
	dc.b	'Picasso96API.library',0

cybergraphics_name:
	dc.b	'cybergraphics.library',0

welcome_text:
	dc.b	'Cho Ren Sha 68k',10
	dc.b	'---------------',10
	dc.b	10
	dc.b	'Original X68000 version (c) 1995 by Famibe No Yosshin.',10
	dc.b	10
	dc.b	'Amiga port (work in progress).',10
	dc.b	10
	dc.b	0

machine_format:
	dc.b	'Detected machine: MC680%ld, %s, %s, %ld kB chip free, %ld kB fast (%ld kB free), %s.',10,0

no_rtg_text:
	dc.b	'no RTG',0
picasso96_text:
	dc.b	'Picasso96',0
cybergraphics_text:
	dc.b	'CyberGraphX',0

ocs_text:
	dc.b	'OCS',0
ecs_text:
	dc.b	'ECS',0
aga_text:
	dc.b	'AGA',0

no_fpu_text:
	dc.b	'no FPU',0
fpu_68881_text:
	dc.b	'MC68881 FPU',0
fpu_68882_text:
	dc.b	'MC68882 FPU',0
fpu_internal_text:
	dc.b	'internal FPU',0

display_none_text:
	dc.b	'Display: unsupported machine.',10,0
display_rtg_text:
	dc.b	'Display: RTG.',10,0
display_aga_text:
	dc.b	'Display: native AGA.',10,0

requirements_text:
	dc.b	'Requires a 68020 or better with an RTG card (Picasso96 or CyberGraphX),',10
	dc.b	'or an AGA Amiga with 8 MB of fast RAM.',10,0

emulator_failed_text:
	dc.b	'Could not set up the emulation (memory, signal or timer).',10,0

run_summary_format:
	dc.b	'Frames: %ld (measured: %ld), E clock: %ld Hz, heap used: %ld bytes, frames rendered: %ld, timer ticks: %ld.',10,0

	ifd __RENDER_PROFILE__
profile_format:
	dc.b	'Render (1/100 ms per frame): palette %ld, graphics %ld, text %ld, sprites %ld, upload %ld; palette rebuilds %ld, LoadRGB32 %ld; text lines converted %ld, drawn %ld, remapped all %ld times; c2p %ld (1/100 ms per rendered frame).',10,0
entry_format:
	dc.b	'  palette entry %ld changed %ld times',10,0
	endif

exit_format:
	dc.b	'Exit: %s. Frame timer: %s (%ld.%02ld Hz).',10,0

exit_unknown_text:
	dc.b	'unknown',0
exit_frame_limit_text:
	dc.b	'frame limit',0
exit_game_text:
	dc.b	'game',0
exit_exception_text:
	dc.b	'exception',0

	even

exit_reason_table:
	dc.l	exit_unknown_text,exit_frame_limit_text,exit_game_text,exit_exception_text

unimplemented_iocs_format:
	dc.b	'Unimplemented IOCS call $%02lx.',10,0

measure_file_name:
	dc.b	'measure.bin',0

checkpoints_file_name:
	dc.b	'checkpoints.bin',0

measure_file_failed_text:
	dc.b	'Could not write the measurement files.',10,0

	even

chipset_text_table:
	dc.l	ocs_text,ecs_text,aga_text

rtg_text_table:
	dc.l	no_rtg_text,picasso96_text,cybergraphics_text

display_text_table:
	dc.l	display_none_text,display_rtg_text,display_aga_text

rtg_board_count_tags:
	dc.l	P96RD_NumberOfBoards,rtg_board_count
	dc.l	0 ; TAG_DONE

fpu_text_table:
	dc.l	no_fpu_text,fpu_68881_text,fpu_68882_text,fpu_internal_text

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

	ifd __NO_CPU_CACHES__
saved_cache_bits:
	ds.l	1
	endif

exec_base:
	ds.l	1
dos_base:
	ds.l	1
graphics_base:
	ds.l	1
workbench_message:
	ds.l	1

machine_cpu:
	ds.l	1
machine_fpu:
	ds.l	1
machine_chipset:
	ds.l	1
machine_rtg:
	ds.l	1
argument_string:
	ds.l	1
argument_length:
	ds.l	1
frame_limit:
	ds.l	1
input_script_name:
	ds.l	1
input_script_name_buffer:
	ds.b	64
measure_header:
	ds.l	3
machine_display:
	ds.l	1
machine_fast_total_kb:
	ds.l	1
rtg_board_count:
	ds.l	1
machine_chip_kb:
	ds.l	1
machine_fast_kb:
	ds.l	1

print_arguments:
	ds.l	10

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
