
; Amiga entry point.
;
; Minimum: a 68020 or better with an RTG card, or an AGA Amiga with 8 MB of
; fast RAM. The main target is a 68030 at 50 MHz with an RTG card. This file
; is assembled with -m68000 so it reports missing requirements instead of
; crashing on a lesser CPU; the executable still needs about 2.3 MB of free
; memory to load at all (mostly the X68000 shadow buffers in mem_map.s).
;
; The game core is linked in but not started yet: this build detects the
; machine, prints what it found and exits cleanly.

	xdef start

; exec.library

_LVOForbid=-132
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

_LVOPutStr=-948
_LVOVPrintf=-954

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

start:
	movem.l	d2-d7/a2-a6,-(sp)

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
	move.l	#not_started_text,d1
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

not_started_text:
	dc.b	'Game core linked; the emulation layer is not implemented yet.',10,0

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
	ds.l	7

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
