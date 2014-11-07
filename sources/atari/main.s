
	xdef start

	xdef machine_type
	xdef fast_ram_detected

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

	add.l	#$100000,d0 ; Reserve heap memory for the game.

	; Free unused memory.

	move.l	d0,-(sp)
	move.l	a0,-(sp)
	clr		-(sp)
	move	#74,-(sp)
	trap	#1
	lea		12(sp),sp

	; Activate super mode.

	pea		0
	move	#32,-(sp)
	trap	#1
	addq	#6,sp

	move.l	d0,old_ssp

	lea		my_stack,sp

	; Print info text.

	pea		welcome_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	jsr		initialize_machine

	pea		press_space_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	; Wait for user input.

	move	#1,-(sp)
	trap	#1
	addq.l	#2,sp

	; Initialize system and start emulator.

	jsr		init

	jsr		start_emulator

	jsr		restore

	; Free memory.

	move.l	allocated_screen_buffer,-(sp)
	move	#73,-(sp)
	trap	#1
	addq.l	#6,sp

	move.l	allocated_screen_buffer,d0
	jeq		.skip_free_display_buffer

	move.l	d0,-(sp)
	move	#73,-(sp)
	trap	#1
	addq.l	#6,sp

.skip_free_display_buffer:
	move.l	allocated_samples_buffer,d0
	jeq		.skip_free_samples_buffer

	move.l	d0,-(sp)
	move	#73,-(sp)
	trap	#1
	addq.l	#6,sp

.skip_free_samples_buffer:
	; Activate user mode.

	move.l	old_ssp,-(sp)
	move	#32,-(sp)
	trap	#1
	addq	#6,sp

	clr		-(sp)
	trap	#1

; ------------------------------------------------------------------------------

_p_cookies=$5a0

initialize_machine:
	move.l	_p_cookies,d0
	jeq		.exit

	move.l	d0,a6

	move.l	(a6)+,d0
	jeq		.skip_all

.cookies_loop:
	move.l	(a6)+,d1

	cmp.l	#'_MCH',d0
	jne		.skip_mch

	move.l	d1,machine_type

	jra		.next_cookie

.skip_mch:	
	cmp.l	#'_CPU',d0
	jne		.skip_cpu

	move.l	d1,machine_cpu

	jra		.next_cookie

.skip_cpu:
	cmp.l	#'_FPU',d0
	jne		.skip_fpu

	move.l	d1,machine_fpu

	jra		.next_cookie

.skip_fpu:
	cmp.l	#'_VDO',d0
	jne		.skip_video

	move.l	d1,machine_video

	jra		.next_cookie

.skip_video:
	cmp.l	#'_SND',d0
	jne		.skip_sound

	move.l	d1,machine_sound

	jra		.next_cookie

.skip_sound:
.next_cookie:
	move.l	(a6)+,d0
	jne		.cookies_loop

.skip_all:

	; Print detected machine.

	move.l	machine_type,d0
	cmp.l	#-1,d0
	jeq		.exit

	lea		machine_type_table,a0

.machine_type_loop:
	move.l	(a0)+,d1
	move.l	(a0)+,a6

	cmp.l	#-1,d1
	jeq		.exit

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
	jeq		.exit

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

	; Allocate screen buffers (Fast-RAM preferred).

	move	#3,-(sp)
	move.l	#(16+240+16)*256*2*2*2,-(sp)
	move	#68,-(sp)
	trap	#1
	addq.l	#8,sp

	move.l	d0,a0
	move.l	a0,a1
	add.l	#(16+240+16)*256*2*2*2,a1

.clear_loop:
	clr.l	(a0)+	
	clr.l	(a0)+	
	clr.l	(a0)+	
	clr.l	(a0)+	

	cmp.l	a1,a0
	jne		.clear_loop

	move.l	d0,allocated_screen_buffer
	move.l	d0,show_screen_address
	add.l	#(16+240+16)*256*2*2,d0
	move.l	d0,work_screen_address

	; Detect Fast-RAM by trying to allocate the display and sample buffers.

	move	#1,-(sp)
	move.l	#240*256*2,-(sp)
	move	#68,-(sp)
	trap	#1
	addq.l	#8,sp

	move.l	d0,allocated_display_buffer

	move	#1,-(sp)
	move.l	#512*1024,-(sp)
	move	#68,-(sp)
	trap	#1
	addq.l	#8,sp

	move.l	d0,allocated_samples_buffer
	jeq		.no_fast_ram

	pea		separator_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	pea		machine_fast_ram_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

.no_fast_ram:
.exit:
	pea		line_end_text
	move	#9,-(sp)
	trap	#1
	addq.l	#6,sp

	rts

; ------------------------------------------------------------------------------

init:
	move	#$2700,sr

	lea		$ffff9800.w,a0
	lea		old_palette,a1
	move	#256-1,d7

.copy_palette_loop:
	move.l	(a0)+,(a1)+

	dbra	d7,.copy_palette_loop

	clr.l	$ffff9800.w

	move	$ffff8900.w,old_8900
	move	$ffff8920.w,old_8920
	move.l	$ffff8930.w,old_8930
	move.l	$ffff8934.w,old_8934
	move.l	$ffff8938.w,old_8938
	move.b	$ffff893c.w,old_893c
	move.b	$ffff8941.w,old_8941

	move.b	#0,$ffff8900.w														| Interrupt selection.
	move.b	#0,$ffff8901.w														| DMA control.
	move.b	#0,$ffff8920.w														| DMA track selection.
	move.b	#1,$ffff8921.w														| Sample size and Frequency (8 bit + 12517 Hz).
	move	#1,$ffff8930.w														| Crossbar source.
	move	#1,$ffff8932.w														| Crossbar destination.
	move.b	#0,$ffff8934.w														| Frequency external clock (STE compatible).
	move.b	#0,$ffff8935.w														| Frequency internal clock (STE compatible).
	move.b	#0,$ffff8936.w														| Record track selection.

	move.b	$fffffa07.w,old_fa07
	move.b	$fffffa09.w,old_fa09
	move.b	$fffffa13.w,old_fa13
	move.b	$fffffa15.w,old_fa15

	move.l	$2c.w,old_line_f
	move.l	$88.w,old_trap_2
	move.l	$90.w,old_trap_4
	move.l	$bc.w,old_trap_f
	move.l	$70.w,old_vbl
	move.l	$118.w,old_keyboard

	move.b	$ffff8201.w,old_screen+1
	move.b	$ffff8203.w,old_screen+2
	move.b	$ffff820d.w,old_screen+3

	move.b	show_screen_address+1,$ffff8201.w
	move.b	show_screen_address+2,$ffff8203.w
	move.b	show_screen_address+3,$ffff820d.w

	move.l	$ffff820e.w,d0
	move.l	$ffff8264.w,d1
	movem.l	$ffff8282.w,d2-d5
	movem.l	$ffff82a2.w,d6-a0
	move.l	$ffff82c0.w,a1
	move	$ffff820a.w,a2
	movem.l	d0-a2,old_videl

	; 256 * 240, 256 colors.

	rem

	move.l	#$c7009e,$ffff8282.w
	move.l	#$1e0009,$ffff8286.w
	move.l	#$6100ab,$ffff828a.w
	move.l	#$20d0201,$ffff82a2.w
	move.l	#$170025,$ffff82a6.w
	move.l	#$2050207,$ffff82aa.w
	move	#$200,$ffff820a.w
	move	#$185,$ffff82c0.w
	clr		$ffff8266.w
	move	#$10,$ffff8266.w
	move	#$0,$ffff82c2.w
	move	#$80,$ffff8210.w

	erem

	; 256 * 240, TC.

	btst	#6,$ffff8006.w
	jeq		.set_vga_mode

	move.l	#$c7009e,$ffff8282.w
	move.l	#$1e001b,$ffff8286.w
	move.l	#$7300ab,$ffff828a.w
	move.l	#$20d0201,$ffff82a2.w
	move.l	#$170025,$ffff82a6.w
	move.l	#$2050207,$ffff82aa.w
	move	#$200,$ffff820a.w
	move	#$185,$ffff82c0.w
	clr		$ffff8266.w
	move	#$100,$ffff8266.w
	move	#$0,$ffff82c2.w
	move	#$100,$ffff8210.w

	jra		.skip_vga_mode

.set_vga_mode:
	move.l	#$c6008d,$ffff8282.w
	move.l	#$150004,$ffff8286.w
	move.l	#$6d0097,$ffff828a.w
	move.l	#$41903ff,$ffff82a2.w
	move.l	#$3f003d,$ffff82a6.w
	move.l	#$3fd0415,$ffff82aa.w
	move	#$200,$ffff820a.w
	move	#$186,$ffff82c0.w
	clr		$ffff8266.w
	move	#$100,$ffff8266.w
	move	#$5,$ffff82c2.w
	move	#$100,$ffff8210.w

.skip_vga_mode:
;	move	#(512-256)/2,$ffff820e.w
	move	#(256*2-256),$ffff820e.w

	clr.b	$fffffa07.w
	clr.b	$fffffa09.w
	clr.b	$fffffa13.w
	clr.b	$fffffa15.w

	move.l	#line_f_handler,$2c.w
	move.l	#trap_2_handler,$88.w
	move.l	#trap_4_handler,$90.w
	move.l	#trap_f_handler,$bc.w
	move.l	#vbl_handler,$70.w
	move.l	#ikbd_handler,$118.w

	bset	#6,$fffffa09.w
	bset	#6,$fffffa15.w

	bclr	#3,$fffffa17.w

	rts

; ------------------------------------------------------------------------------

restore:
	move	#$2700,sr

	clr		$ffff820e.w
	clr.b	$ffff8265.w

	lea		old_palette,a0
	lea		$ffff9800.w,a1

	move	#256-1,d7

.copy_palette_loop:
	move.l	(a0)+,(a1)+

	dbra	d7,.copy_palette_loop

	move	old_8900,$ffff8900.w
	move	old_8920,$ffff8920.w
	move.l	old_8930,$ffff8930.w
	move.l	old_8934,$ffff8934.w
	move.l	old_8938,$ffff8938.w
	move.b	old_893c,$ffff893c.w
	move.b	old_8941,$ffff8941.w

	move.b	old_fa07,$fffffa07.w
	move.b	old_fa09,$fffffa09.w
	move.b	old_fa13,$fffffa13.w
	move.b	old_fa15,$fffffa15.w

	move.l	old_line_f,$2c.w
	move.l	old_trap_2,$88.w
	move.l	old_trap_4,$90.w
	move.l	old_trap_f,$bc.w
	move.l	old_vbl,$70.w
	move.l	old_keyboard,$118.w

	move.b	old_screen+1,$ffff8201.w
	move.b	old_screen+2,$ffff8203.w
	move.b	old_screen+3,$ffff820d.w

	movem.l	old_videl,d0-a2
	move.l	d0,$ffff820e.w
	move.l	d1,$ffff8264.w
	movem.l	d2-d5,$ffff8282.w
	movem.l	d6-a0,$ffff82a2.w
	move.l	a1,$ffff82c0.w
	move	a2,$ffff820a.w

	move	#$2300,sr

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
	dc.b	'Atari Falcon030 port v20141105t by Sascha Springer.',10,13
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

	even

machine_type:
	dc.l	-1

machine_cpu:
	dc.l	-1

machine_fpu:
	dc.l	-1

machine_video:
	dc.l	-1

machine_sound:
	dc.l	-1

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

old_ssp:
	ds.l	1

old_screen:
	ds.l	1
old_palette:
	ds.l	256
old_videl:
	ds.l	11

old_line_f:
	ds.l	1
old_trap_2:
	ds.l	1
old_trap_4:
	ds.l	1
old_trap_f:
	ds.l	1
old_vbl:
	ds.l	1
old_keyboard:
	ds.l	1

old_8900:
	ds.w	1
old_8920:
	ds.w	1
old_8930:
	ds.l	1
old_8934:
	ds.l	1
old_8938:
	ds.l	1
old_893c:
	ds.b	1
old_8941:
	ds.b	1

old_fa07:
	ds.b	1
old_fa09:
	ds.b	1
old_fa13:
	ds.b	1
old_fa15:
	ds.b	1

	even

allocated_screen_buffer:
	ds.l	1

allocated_display_buffer:
	ds.l	1

allocated_samples_buffer:
	ds.l	1

	ds.l	1024
my_stack:

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------

