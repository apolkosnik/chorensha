
	xdef start

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

start:
	move.l	4(sp),a0
	move.l	#256,d0
	add.l	12(a0),d0
	add.l	20(a0),d0
	add.l	28(a0),d0

	lea		(a0,d0.l),a1
	move.l	a1,game_heap_address

	add.l	#$100000,d0 ; Reserve 1 MB heap memory for the game.

	; Free unused memory.

	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr		-(sp)
	move	#74,-(sp)
	trap	#1
	lea		12(sp),sp

	; Super mode.

	pea		0
	move	#32,-(sp)
	trap	#1
	addq	#6,sp

	move.l	d0,old_stack_address

	lea		my_stack,sp

	; Machine detection.

	jsr		detect_machine

	; Print info text.

	jsr		print_info_text

	; Wait for user input.

	move	#1,-(sp)
	trap	#1
	addq.l	#2,sp

	; Initialize system and start emulator.

	jsr		initialize_audio
	jsr		initialize_graphics
	jsr		initialize_machine

	jsr		start_emulator

	jsr		release_machine
	jsr		release_graphics
	jsr		release_audio

	; User mode.

	move.l	old_stack_address,-(sp)
	move	#32,-(sp)
	trap	#1
	addq	#6,sp

	clr		-(sp)
	trap	#1

; ------------------------------------------------------------------------------

print_info_text:
	; Print welcome text.

	pea		welcome_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	; Print detected machine type.

	move.l	machine_type,d0
	cmp.l	#-1,d0
	jeq		.no_detection_info

	lea		machine_type_table,a0

.machine_type_loop:
	move.l	(a0)+,d1
	move.l	(a0)+,a6

	cmp.l	#-1,d1
	jeq		.no_detection_info

	cmp.l	d0,d1
	jne		.machine_type_loop

	pea		detected_machine_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	move.l	a6,-(sp)
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	; Print detected CPU.

	move.l	machine_cpu,d0
	cmp.l	#-1,d0
	jeq		.no_detection_info

	divu	#10,d0
	add.b	d0,machine_cpu_text+5

	pea		separator_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	pea		machine_cpu_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	; Print detected SuperVidel.

	cmp.l	#-1,machine_supervidel
	jeq		.no_supervidel

	pea		separator_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	pea		machine_supervidel_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

.no_supervidel:
    ; Detect Fast-RAM.

    cmp		#-1,machine_has_fast_ram
	jne		.no_fast_ram

	pea		separator_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	pea		machine_fast_ram_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

.no_fast_ram:
	pea		line_end_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

.no_detection_info:
	pea		press_space_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

welcome_text:
	dc.b	'Cho Ren Sha 68k',10,13
	dc.b	'---------------',10,13
	dc.b	10,13
	dc.b	'Original X68000 version (c) 1995 by Famibe No Yosshin.',10,13
	dc.b	10,13
	dc.b	'Atari Falcon030 port v20141114t by Sascha Springer.',10,13
	dc.b	10,13
	dc.b	0

press_space_text:
	dc.b	10,13
	dc.b	'Press SPACE to start...',10,13
	dc.b	0

detected_machine_text:
	dc.b	'Detected machine: ',0

separator_text:
	dc.b	', ',0

line_end_text:
	dc.b	'.',10,13,0

machine_type_atari_st_text:
	dc.b	'Atari ST',0

machine_type_atari_ste_text:
	dc.b	'Atari STE',0

machine_type_atari_st_book_text:
	dc.b	'Atari ST Book',0

machine_type_atari_mega_ste_text:
	dc.b	'Atari Mega STE',0

machine_type_atari_tt_text:
	dc.b	'Atari TT',0

machine_type_atari_falcon030_text:
	dc.b	'Atari Falcon030',0

machine_type_medusa_text:
	dc.b	'Medusa T40',0

machine_type_milan_text:
	dc.b	'Milan',0

machine_type_aranym_text:
	dc.b	'ARAnyM',0

machine_cpu_text:
	dc.b	'MC68000 CPU',0

machine_fast_ram_text:
	dc.b	'Fast-RAM',0

machine_supervidel_text:
	dc.b	'SuperVidel',0

	even

machine_type_table:
	dc.l	$00000000,machine_type_atari_st_text
	dc.l	$00010000,machine_type_atari_ste_text
	dc.l	$00010010,machine_type_atari_mega_ste_text
	dc.l	$00020000,machine_type_atari_tt_text
	dc.l	$00030000,machine_type_atari_falcon030_text
	dc.l	$00040000,machine_type_milan_text
	dc.l	$00050000,machine_type_aranym_text
	dc.l	-1,0

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

old_stack_address:
	ds.l	1

	ds.l	1024
my_stack:

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------

