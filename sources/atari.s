; sudo chmod a+rw /dev/ttyUSB0
; ~/Work/MonoSerialDisk/MonoSerialDisk/bin/Release/MonoSerialDisk.exe --port=/dev/ttyUSB0 --disk-size=128 --verbosity=2 ~/Work/ChoRenSha/binaries/atari/
; iconv -c -f SHIFT-JIS -t UTF-8 programmers.man > programmers.man.txt
; sox -t vox -r 15600 out.pcm -t wav -c 2 -r 25033 out2.wav

LINE_F_OFFSET = 2																| 0 = 68000, 2 = 68030

	text

; ------------------------------------------------------------------------------

start:
	pea		welcome_text
	move	#9,-(sp)
	trap	#1
	addq	#6,sp

	move	#1,-(sp)
	trap	#1
	addq	#2,sp

	jsr		init

	move.l	#dummy_interrupt_handler,L_00000118
	move.l	#dummy_interrupt_handler,L_00000138

; a0	メモリ管理ポインタのアドレス "Address of a pointer to memory management"
; a1	プログラムの終わり+1 のアドレス "+1 Address of the end of the program"
; a2	コマンドラインのアドレス "Address of the command line"
; a3	環境のアドレス "Address of the environment"
; a4	プログラムの実行開始アドレス "Execution of the program start address"
; sr	ユーザーモード "User-mode"
; usp	親のスタック "Stack of the parent"
; ssp	システムのスタック "Stack of the system"

	lea		NEW_STACK,a0
	lea		NEW_STACK,a1
	lea		NEW_STACK,a2
	lea		NEW_STACK,a3
	lea		_start,a4

	jmp		_start

; ------------------------------------------------------------------------------

dummy_interrupt_handler:
	rte

; ------------------------------------------------------------------------------

init:
	pea		0
	move	#32,-(sp)
	trap	#1
	addq	#6,sp

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

	move.b	display_screen_address+1,$ffff8201.w
	move.b	display_screen_address+2,$ffff8203.w
	move.b	display_screen_address+3,$ffff820d.w

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
	move	#(512-256),$ffff820e.w

	clr.b	$fffffa07.w
	clr.b	$fffffa09.w
	clr.b	$fffffa13.w
	clr.b	$fffffa15.w

	move.l	#line_f,$2c.w
	move.l	#trap_2,$88.w
	move.l	#trap_4,$90.w
	move.l	#trap_f,$bc.w
;	move.l	#vbl_256,$70.w
	move.l	#vbl_tc,$70.w
	move.l	#keyboard,$118.w

	bset	#6,$fffffa09.w
	bset	#6,$fffffa15.w

	bclr	#3,$fffffa17.w

	rts

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

	clr		-(sp)
	trap	#1

; ------------------------------------------------------------------------------

line_f:
	movem.l	d1-d2/a0-a2,-(sp)

	move.l	22(sp),a0
	move	(a0),d1
	addq.l	#2,22(sp)

	cmp		#$fe00,d1 ; __LMUL
	jne		.not__lmul

	muls.l	(sp),d0

	jra		.exit

.not__lmul:
	cmp		#$fe01,d1 ; __LDIV
	jne		.not__ldiv

	divs.l	(sp),d0

	jra		.exit

.not__ldiv:
	cmp		#$fe0d,d1 ; __SRAND
	jne		.not__srand

	clr.l	d0

	jra		.exit

.not__srand:
	cmp		#$ff06,d1 ; _INPOUT
	jne		.not_inpout

	clr.l	d0

	jra		.exit

.not_inpout:
	cmp		#$ff20,d1 ; _SUPER
	jne		.not_super

	move.l	26+LINE_F_OFFSET+0(sp),a0

	clr.l	d0

	jra		.exit

.not_super:
	cmp		#$ff23,d1 ; _CONCTRL
	jne		.not_conctrl

	clr.l	d0

	jra		.exit

.not_conctrl:
	cmp		#$ff25,d1 ; _INTVCS
	jne		.not_intvcs

	move	26+LINE_F_OFFSET+0(sp),d0
	move	26+LINE_F_OFFSET+4(sp),a0

	clr.l	d0

	jra		.exit

.not_intvcs:
	cmp		#$ff36,d1 ; _DSKFRE
	jne		.not_dskfre

	move.l	#10000000,d0

	jra		.exit

.not_dskfre:
	cmp		#$ff37,d1 ; _NAMECK
	jne		.not_nameck

	clr.l	d0

	jra		.exit

.not_nameck:
	cmp		#$ff3d,d1 ; _OPEN
	jne		.not_open

	move.l	26+LINE_F_OFFSET+0(sp),a0
	move	26+LINE_F_OFFSET+4(sp),d0

	rem

	movem.l	d0/a0,-(sp)

	pea		(a0)
	move	#9,-(sp)
	trap	#1
	addq	#6,sp

	pea		.new_line
	move	#9,-(sp)
	trap	#1
	addq	#6,sp

	movem.l	(sp)+,d0/a0

	erem

	move	d0,-(sp)
	pea		(a0)
	move	#61,-(sp)
	trap	#1
	addq	#8,sp

	jra		.exit

.new_line:
	dc.b	10,13,0,0

.not_open:
	cmp		#$ff3f,d1 ; _READ
	jne		.not_read

	move	26+LINE_F_OFFSET+0(sp),d0
	move.l	26+LINE_F_OFFSET+2(sp),a0
	move.l	26+LINE_F_OFFSET+6(sp),d1
	and.l	#$7fffffff,d1

	pea		(a0)
	move.l	d1,-(sp)
	move	d0,-(sp)
	move	#63,-(sp)
	trap	#1
	lea		12(sp),sp

	jra		.exit

.not_read:
	cmp		#$ff3e,d1 ; _CLOSE
	jne		.not_close

	move	26+LINE_F_OFFSET+0(sp),d0

	move	d0,-(sp)
	move	#62,-(sp)
	trap	#1
	addq	#4,sp

	jra		.exit

.not_close:
	cmp		#$ff40,d1 ; _WRITE
	jne		.not_write

	illegal

	move	26+LINE_F_OFFSET+0(sp),d0
	move.l	26+LINE_F_OFFSET+2(sp),a0
	move.l	26+LINE_F_OFFSET+6(sp),d1

	cmp		#1,d0
	jne		.exit

	clr		d0
	move.b	(a0),d0

	move	d0,-(sp)
	move	#2,-(sp)
	trap	#1
	addq	#4,sp

	clr.l	d0

	jra		.exit	

.not_write:
	cmp		#$ff42,d1 ; _SEEK
	jne		.not_seek

	move	26+LINE_F_OFFSET+0(sp),d0
	move.l	26+LINE_F_OFFSET+2(sp),a0
	move	26+LINE_F_OFFSET+6(sp),d1

	move	d1,-(sp)
	move	d0,-(sp)
	move.l	a0,-(sp)
	move	#66,-(sp)
	trap	#1
	lea		10(sp),sp

	jra		.exit	

.not_seek:
	cmp		#$ff44,d1 ; _IOCTRL
	jne		.not_ioctrl

	clr.l	d0

	jra		.exit

.not_ioctrl:
	cmp		#$ff4a,d1 ; _SETBLOCK
	jne		.not_setblock

	move.l	26+LINE_F_OFFSET+4(sp),d0

	cmp.l	#$ffffff,d0
	jeq		.1

	clr.l	d0

	jra		.exit

.1:
	move.l	#$81200000,d0

	jra		.exit

.not_setblock:
	illegal

	clr.l	d0

.exit:
	movem.l	(sp)+,d1-d2/a0-a2

	rte

; ------------------------------------------------------------------------------

trap_2:
	add		#$0f0,$ffff8240.w

	rte

; ------------------------------------------------------------------------------

trap_4:
	add		#$00f,$ffff8240.w

	rte

; ------------------------------------------------------------------------------

trap_f:
	cmp.b	#$4,d0 ; _BITSNS
	jne		.no_bitsns

	clr.l	d0

	rte

.no_bitsns:
	cmp.b	#$10,d0 ; _CRTMOD
	jne		.no_crtmod

	clr.l	d0

	rte

.no_crtmod:
	cmp.b	#$14,d0 ; _TPALET2
	jne		.no_tpalet2

	clr.l	d0

	rte

.no_tpalet2:
	cmp.b	#$20,d0 ; _B_PUTC
	jne		.no_b_putc

	clr.l	d0

	rte

.no_b_putc:
	cmp.b	#$22,d0 ; _B_COLOR
	jne		.no_b_color

	clr.l	d0

	rte

.no_b_color:
	cmp.b	#$23,d0 ; _B_LOCATE
	jne		.no_b_locate

	clr.l	d0

	rte

.no_b_locate:
	cmp.b	#$3b,d0 ; _JOYGET
	jne		.no_joyget

	move.l	iocs_joystick_data,d0

	rte

.no_joyget:
	cmp.b	#$60,d0 ; _ADPCMOUT
	jne		.no_adpcmout

	movem.l	d0-d2/a0-a2,-(sp)

;	WavePlay #0,#12571,(a1),d2
;	movem.l	(sp)+,d0-d2/a0-a2
;	rte

;	move	#$200b,$ffff8932.w
;	clr.b	$ffff8936.w

	clr		$ffff8900.w

	move.b	#$81,$ffff8921.w ; Mono & 12571 Hz.

	move.l	a1,d0
	move.b	d0,$ffff8907.w
	lsr		#8,d0
	move.b	d0,$ffff8905.w
	swap	d0
	move.b	d0,$ffff8903.w

	move.l	a1,d0
	add.l	d2,d0
	move.b	d0,$ffff8913.w
	lsr		#8,d0
	move.b	d0,$ffff8911.w
	swap	d0
	move.b	d0,$ffff890f.w

	move	#1,$ffff8900.w

	movem.l	(sp)+,d0-d2/a0-a2

	clr.l	d0

	rte

.no_adpcmout:
	cmp.b	#$66,d0 ; _ADPCMSNS
	jne		.no_adpcmsns

	clr.l	d0

	btst	#0,$ffff8901.w
	jeq		.replay_not_running

	moveq.l	#2,d0
	
.replay_not_running:
	rte

.no_adpcmsns:
	cmp.b	#$67,d0 ; _ADPCMMOD
	jne		.no_adpcmmod

	clr.l	d0

	rte

.no_adpcmmod:
	cmp.b	#$7d,d0 ; _SKEY_MOD
	jne		.no_skey_mod

	rte

.no_skey_mod:
	cmp.b	#$7f,d0 ; _ONTIME
	jne		.no_ontime

	move.l	#100*100,d0
	clr.l	d1

	rte

.no_ontime:
	cmp.b	#$81,d0 ; _B_SUPER
	jne		.no_b_super

	move.l	#-1,d0

	rte

.no_b_super:
	cmp.b	#$87,d0 ; _B_WPOKE
	jne		.no_b_wpoke

	rte

.no_b_wpoke:
	cmp.b	#$90,d0 ; _G_CLR_ON
	jne		.no_g_clr_on

	rte

.no_g_clr_on:
	cmp.b	#$92,d0 ; (未公開)	プライオリティ設定
	jne		.no_prio_set

	rte

.no_prio_set:
	cmp.b	#$ae,d0 ; _OS_CURON
	jne		.no_os_curon

	rte

.no_os_curon:
	cmp.b	#$af,d0 ; _OS_CUROFF
	jne		.no_os_curoff

	rte

.no_os_curoff:
	cmp.b	#$b2,d0 ; _VPAGE
	jne		.no_vpage

	clr.l	d0

	rte

.no_vpage:
	cmp.b	#$b3,d0 ; _HOME
	jne		.no_home

	clr.l	d0

	rte

.no_home:
	cmp.b	#$c1,d0 ; _SP_ON
	jne		.no_sp_on

	rte

.no_sp_on:
	cmp.b	#$c2,d0 ; _SP_OFF
	jne		.no_sp_off

	rte

.no_sp_off:
	cmp.b	#$ca,d0 ; _BGCTRLST
	jne		.no_bgctrlst

	rte

.no_bgctrlst:
	cmp.b	#$ce,d0 ; _BGTEXTGT
	jne		.no_bgtextgt

	clr.l	d0

	rte

.no_bgtextgt:
	cmp.b	#$cf,d0 ; _SPALET
	jne		.no_spalet

	clr.l	d0

	rte

.no_spalet:
	illegal

iocs_joystick_data:
	dc.l	-1

; ------------------------------------------------------------------------------

convert_palettes:
	movem.l	d0-d7/a0-a6,-(sp)

	lea		L_00E82000+$200,a0
	lea		converted_sprite_palettes,a1

	move	#16*16-1,d7

.loop:
	move	(a0)+,d0

	bfextu	d0{16+5:5},d1
	bfextu	d0{16+0:5},d2
	bfextu	d0{16+10:5},d3

	clr		d0

	bfins	d1,d0{16+0:5}
	bfins	d2,d0{16+5:5}
	bfins	d3,d0{16+11:5}

	move	d0,(a1)+

	dbf		d7,.loop

	movem.l	(sp)+,d0-d7/a0-a6

	rts

	bss

converted_sprite_palettes:
	ds.w	16*16

	text

; ------------------------------------------------------------------------------

vbl_tc:
	move.b	display_screen_address+1,$ffff8201.w
	move.b	display_screen_address+2,$ffff8203.w
	move.b	display_screen_address+3,$ffff820d.w

	addq	#1,vbl_wait_counter

	move.l	L_00000118,-(sp)

	rts

; ------------------------------------------------------------------------------

draw_tc_sprites:
	movem.l	d0-a6,-(sp)

	; Clear screen.

	move.l	work_screen_address,a0
	add.l	#512*2*16+16*2,a0

	clr.l	d0
	move.l	d0,d1
	move.l	d0,d2
	move.l	d0,d3
	move.l	d0,d4
	move.l	d0,d5
	move.l	d0,d6
	move.l	d0,a1
	move.l	d0,a2
	move.l	d0,a3
	move.l	d0,a4
	move.l	d0,a5

	move	#240-1,d7

.clear_loop:
	movem.l	d0-d6/a1-a5,(a0)
	movem.l	d0-d6/a1-a5,12*4(a0)
	movem.l	d0-d6/a1-a5,12*4*2(a0)
	movem.l	d0-d6/a1-a5,12*4*3(a0)
	movem.l	d0-d6/a1-a5,12*4*4(a0)
	movem.l	d0-d6/a1-a5,12*4*5(a0)
	movem.l	d0-d6/a1-a5,12*4*6(a0)
	movem.l	d0-d6/a1-a5,12*4*7(a0)
	movem.l	d0-d6/a1-a5,12*4*8(a0)
	movem.l	d0-d6/a1-a5,12*4*9(a0)
	movem.l	d0-d6/a1,12*4*10(a0)

	add.l	#256*2*2,a0

	dbf		d7,.clear_loop

	; Convert palettes.

	jbsr	convert_palettes

	; Draw sprites.

	move.l	work_screen_address,a0
	lea		L_00EB0000,a1 ; Sprite infos table.
	lea		L_00EB8000,a2 ; Sprite data table.
;	lea		L_00E82000+$200,a3 ; Sprite palette table.
	lea		converted_sprite_palettes,a3 ; Sprite palette table.

	move	#128-1,d7

draw_tc_sprites_loop:
	move	(a1)+,d0 ; X position.
	move	(a1)+,d1 ; Y position.
	move	(a1)+,d2 ; VF, HF, palette index, pattern index.
	move	(a1)+,d3 ; Priority (0 = no display).

	jeq		.skip_sprite

	cmp		#16+256,d0
	jhs		.skip_sprite

	cmp		#16+240,d1
	jhs		.skip_sprite

	lea		(a0,d0.w*2),a4
	swap	d1
	clr		d1
	lsr.l	#6,d1
	add.l	d1,a4 ; Screen address.

	move	d2,d3

	and		#$e000,d3
	jeq		draw_tc_sprites_normal

	cmp		#$8000,d3
	jeq		draw_tc_sprites_vertical_flipped

	cmp		#$4000,d3
	jeq		draw_tc_sprites_horizontal_flipped

; --------------------------------------
; draw_tc_sprites_vertical_and_horizontal_flipped:
; --------------------------------------
	add.l	#15*512*2,a4

	move	d2,d3
	lsr		#3,d2
	and.l	#$1e0,d2
	lea		(a3,d2.l),a5 ; Palette address.

	and.l	#$ff,d3
	lsl.l	#2+3+2,d3
	lea		(a2,d3.l),a6 ; Sprite data.

	clr.l	d0
	move	#$f0,d2
	move	#$0f,d3

	move	#2-1,d6

.loop1:
	move	#8-1,d5

.loop2:
	move.b	(a6),d0
	jeq		.draw_sprite_pixel1l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0l

	lsr		#3,d0
	move	(a5,d0.w),30(a4)

.draw_sprite_pixel0l:
	and		d3,d1
	jeq		.draw_sprite_pixel1l

	move	(a5,d1.w*2),28(a4)

.draw_sprite_pixel1l:
	move.b	1(a6),d0
	jeq		.draw_sprite_pixel3l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2l

	lsr		#3,d0
	move	(a5,d0.w),26(a4)

.draw_sprite_pixel2l:
	and		d3,d1
	jeq		.draw_sprite_pixel3l

	move	(a5,d1.w*2),24(a4)

.draw_sprite_pixel3l:
	move.b	2(a6),d0
	jeq		.draw_sprite_pixel5l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4l

	lsr		#3,d0
	move	(a5,d0.w),22(a4)

.draw_sprite_pixel4l:
	and		d3,d1
	jeq		.draw_sprite_pixel5l

	move	(a5,d1.w*2),20(a4)

.draw_sprite_pixel5l:
	move.b	3(a6),d0
	jeq		.draw_sprite_pixel7l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6l

	lsr		#3,d0
	move	(a5,d0.w),18(a4)

.draw_sprite_pixel6l:
	and		d3,d1
	jeq		.draw_sprite_pixel7l

	move	(a5,d1.w*2),16(a4)

.draw_sprite_pixel7l:
	move.b	4*16(a6),d0
	jeq		.draw_sprite_pixel1r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0r

	lsr		#3,d0
	move	(a5,d0.w),14(a4)

.draw_sprite_pixel0r:
	and		d3,d1
	jeq		.draw_sprite_pixel1r

	move	(a5,d1.w*2),12(a4)

.draw_sprite_pixel1r:
	move.b	4*16+1(a6),d0
	jeq		.draw_sprite_pixel3r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2r

	lsr		#3,d0
	move	(a5,d0.w),10(a4)

.draw_sprite_pixel2r:
	and		d3,d1
	jeq		.draw_sprite_pixel3r

	move	(a5,d1.w*2),8(a4)

.draw_sprite_pixel3r:
	move.b	4*16+2(a6),d0
	jeq		.draw_sprite_pixel5r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4r

	lsr		#3,d0
	move	(a5,d0.w),6(a4)

.draw_sprite_pixel4r:
	and		d3,d1
	jeq		.draw_sprite_pixel5r

	move	(a5,d1.w*2),4(a4)

.draw_sprite_pixel5r:
	move.b	4*16+3(a6),d0
	jeq		.draw_sprite_pixel7r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6r

	lsr		#3,d0
	move	(a5,d0.w),2(a4)

.draw_sprite_pixel6r:
	and		d3,d1
	jeq		.draw_sprite_pixel7r

	move	(a5,d1.w*2),(a4)

.draw_sprite_pixel7r:
	addq.l	#4,a6
	lea		-512*2(a4),a4

	dbf		d5,.loop2

	dbf		d6,.loop1

.skip_sprite:
	dbf		d7,draw_tc_sprites_loop

	jra		draw_tc_sprites_end

; --------------------------------------
draw_tc_sprites_normal:
; --------------------------------------
	move	d2,d3
	lsr		#3,d2
	and.l	#$1e0,d2
	lea		(a3,d2.l),a5 ; Palette address.

	and.l	#$ff,d3
	lsl.l	#2+3+2,d3
	lea		(a2,d3.l),a6 ; Sprite data.

	clr.l	d0
	move	#$f0,d2
	move	#$0f,d3

	move	#2-1,d6

.loop1:
	move	#8-1,d5

.loop2:
	move.b	(a6),d0
	jeq		.draw_sprite_pixel1l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0l

	lsr		#3,d0
	move	(a5,d0.w),(a4)

.draw_sprite_pixel0l:
	and		d3,d1
	jeq		.draw_sprite_pixel1l

	move	(a5,d1.w*2),2(a4)

.draw_sprite_pixel1l:
	move.b	1(a6),d0
	jeq		.draw_sprite_pixel3l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2l

	lsr		#3,d0
	move	(a5,d0.w),4(a4)

.draw_sprite_pixel2l:
	and		d3,d1
	jeq		.draw_sprite_pixel3l

	move	(a5,d1.w*2),6(a4)

.draw_sprite_pixel3l:
	move.b	2(a6),d0
	jeq		.draw_sprite_pixel5l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4l

	lsr		#3,d0
	move	(a5,d0.w),8(a4)

.draw_sprite_pixel4l:
	and		d3,d1
	jeq		.draw_sprite_pixel5l

	move	(a5,d1.w*2),10(a4)

.draw_sprite_pixel5l:
	move.b	3(a6),d0
	jeq		.draw_sprite_pixel7l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6l

	lsr		#3,d0
	move	(a5,d0.w),12(a4)

.draw_sprite_pixel6l:
	and		d3,d1
	jeq		.draw_sprite_pixel7l

	move	(a5,d1.w*2),14(a4)

.draw_sprite_pixel7l:
	move.b	4*16(a6),d0
	jeq		.draw_sprite_pixel1r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0r

	lsr		#3,d0
	move	(a5,d0.w),16(a4)

.draw_sprite_pixel0r:
	and		d3,d1
	jeq		.draw_sprite_pixel1r

	move	(a5,d1.w*2),18(a4)

.draw_sprite_pixel1r:
	move.b	4*16+1(a6),d0
	jeq		.draw_sprite_pixel3r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2r

	lsr		#3,d0
	move	(a5,d0.w),20(a4)

.draw_sprite_pixel2r:
	and		d3,d1
	jeq		.draw_sprite_pixel3r

	move	(a5,d1.w*2),22(a4)

.draw_sprite_pixel3r:
	move.b	4*16+2(a6),d0
	jeq		.draw_sprite_pixel5r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4r

	lsr		#3,d0
	move	(a5,d0.w),24(a4)

.draw_sprite_pixel4r:
	and		d3,d1
	jeq		.draw_sprite_pixel5r

	move	(a5,d1.w*2),26(a4)

.draw_sprite_pixel5r:
	move.b	4*16+3(a6),d0
	jeq		.draw_sprite_pixel7r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6r

	lsr		#3,d0
	move	(a5,d0.w),28(a4)

.draw_sprite_pixel6r:
	and		d3,d1
	jeq		.draw_sprite_pixel7r

	move	(a5,d1.w*2),30(a4)

.draw_sprite_pixel7r:
	addq.l	#4,a6
	lea		512*2(a4),a4

	dbf		d5,.loop2

	dbf		d6,.loop1

	dbf		d7,draw_tc_sprites_loop

	jra		draw_tc_sprites_end

; --------------------------------------
draw_tc_sprites_vertical_flipped:
; --------------------------------------
	add.l	#15*512*2,a4

	move	d2,d3
	lsr		#3,d2
	and.l	#$1e0,d2
	lea		(a3,d2.l),a5 ; Palette address.

	and.l	#$ff,d3
	lsl.l	#2+3+2,d3
	lea		(a2,d3.l),a6 ; Sprite data.

	clr.l	d0
	move	#$f0,d2
	move	#$0f,d3

	move	#2-1,d6

.loop1:
	move	#8-1,d5

.loop2:
	move.b	(a6),d0
	jeq		.draw_sprite_pixel1l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0l

	lsr		#3,d0
	move	(a5,d0.w),(a4)

.draw_sprite_pixel0l:
	and		d3,d1
	jeq		.draw_sprite_pixel1l

	move	(a5,d1.w*2),2(a4)

.draw_sprite_pixel1l:
	move.b	1(a6),d0
	jeq		.draw_sprite_pixel3l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2l

	lsr		#3,d0
	move	(a5,d0.w),4(a4)

.draw_sprite_pixel2l:
	and		d3,d1
	jeq		.draw_sprite_pixel3l

	move	(a5,d1.w*2),6(a4)

.draw_sprite_pixel3l:
	move.b	2(a6),d0
	jeq		.draw_sprite_pixel5l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4l

	lsr		#3,d0
	move	(a5,d0.w),8(a4)

.draw_sprite_pixel4l:
	and		d3,d1
	jeq		.draw_sprite_pixel5l

	move	(a5,d1.w*2),10(a4)

.draw_sprite_pixel5l:
	move.b	3(a6),d0
	jeq		.draw_sprite_pixel7l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6l

	lsr		#3,d0
	move	(a5,d0.w),12(a4)

.draw_sprite_pixel6l:
	and		d3,d1
	jeq		.draw_sprite_pixel7l

	move	(a5,d1.w*2),14(a4)

.draw_sprite_pixel7l:
	move.b	4*16(a6),d0
	jeq		.draw_sprite_pixel1r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0r

	lsr		#3,d0
	move	(a5,d0.w),16(a4)

.draw_sprite_pixel0r:
	and		d3,d1
	jeq		.draw_sprite_pixel1r

	move	(a5,d1.w*2),18(a4)

.draw_sprite_pixel1r:
	move.b	4*16+1(a6),d0
	jeq		.draw_sprite_pixel3r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2r

	lsr		#3,d0
	move	(a5,d0.w),20(a4)

.draw_sprite_pixel2r:
	and		d3,d1
	jeq		.draw_sprite_pixel3r

	move	(a5,d1.w*2),22(a4)

.draw_sprite_pixel3r:
	move.b	4*16+2(a6),d0
	jeq		.draw_sprite_pixel5r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4r

	lsr		#3,d0
	move	(a5,d0.w),24(a4)

.draw_sprite_pixel4r:
	and		d3,d1
	jeq		.draw_sprite_pixel5r

	move	(a5,d1.w*2),26(a4)

.draw_sprite_pixel5r:
	move.b	4*16+3(a6),d0
	jeq		.draw_sprite_pixel7r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6r

	lsr		#3,d0
	move	(a5,d0.w),28(a4)

.draw_sprite_pixel6r:
	and		d3,d1
	jeq		.draw_sprite_pixel7r

	move	(a5,d1.w*2),30(a4)

.draw_sprite_pixel7r:
	addq.l	#4,a6
	lea		-512*2(a4),a4

	dbf		d5,.loop2

	dbf		d6,.loop1

	dbf		d7,draw_tc_sprites_loop

	jra		draw_tc_sprites_end

; --------------------------------------
draw_tc_sprites_horizontal_flipped:
; --------------------------------------
	move	d2,d3
	lsr		#3,d2
	and.l	#$1e0,d2
	lea		(a3,d2.l),a5 ; Palette address.

	and.l	#$ff,d3
	lsl.l	#2+3+2,d3
	lea		(a2,d3.l),a6 ; Sprite data.

	clr.l	d0
	move	#$f0,d2
	move	#$0f,d3

	move	#2-1,d6

.loop1:
	move	#8-1,d5

.loop2:
	move.b	(a6),d0
	jeq		.draw_sprite_pixel1l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0l

	lsr		#3,d0
	move	(a5,d0.w),30(a4)

.draw_sprite_pixel0l:
	and		d3,d1
	jeq		.draw_sprite_pixel1l

	move	(a5,d1.w*2),28(a4)

.draw_sprite_pixel1l:
	move.b	1(a6),d0
	jeq		.draw_sprite_pixel3l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2l

	lsr		#3,d0
	move	(a5,d0.w),26(a4)

.draw_sprite_pixel2l:
	and		d3,d1
	jeq		.draw_sprite_pixel3l

	move	(a5,d1.w*2),24(a4)

.draw_sprite_pixel3l:
	move.b	2(a6),d0
	jeq		.draw_sprite_pixel5l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4l

	lsr		#3,d0
	move	(a5,d0.w),22(a4)

.draw_sprite_pixel4l:
	and		d3,d1
	jeq		.draw_sprite_pixel5l

	move	(a5,d1.w*2),20(a4)

.draw_sprite_pixel5l:
	move.b	3(a6),d0
	jeq		.draw_sprite_pixel7l

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6l

	lsr		#3,d0
	move	(a5,d0.w),18(a4)

.draw_sprite_pixel6l:
	and		d3,d1
	jeq		.draw_sprite_pixel7l

	move	(a5,d1.w*2),16(a4)

.draw_sprite_pixel7l:
	move.b	4*16(a6),d0
	jeq		.draw_sprite_pixel1r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel0r

	lsr		#3,d0
	move	(a5,d0.w),14(a4)

.draw_sprite_pixel0r:
	and		d3,d1
	jeq		.draw_sprite_pixel1r

	move	(a5,d1.w*2),12(a4)

.draw_sprite_pixel1r:
	move.b	4*16+1(a6),d0
	jeq		.draw_sprite_pixel3r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel2r

	lsr		#3,d0
	move	(a5,d0.w),10(a4)

.draw_sprite_pixel2r:
	and		d3,d1
	jeq		.draw_sprite_pixel3r

	move	(a5,d1.w*2),8(a4)

.draw_sprite_pixel3r:
	move.b	4*16+2(a6),d0
	jeq		.draw_sprite_pixel5r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel4r

	lsr		#3,d0
	move	(a5,d0.w),6(a4)

.draw_sprite_pixel4r:
	and		d3,d1
	jeq		.draw_sprite_pixel5r

	move	(a5,d1.w*2),4(a4)

.draw_sprite_pixel5r:
	move.b	4*16+3(a6),d0
	jeq		.draw_sprite_pixel7r

	move	d0,d1
	and		d2,d0
	jeq		.draw_sprite_pixel6r

	lsr		#3,d0
	move	(a5,d0.w),2(a4)

.draw_sprite_pixel6r:
	and		d3,d1
	jeq		.draw_sprite_pixel7r

	move	(a5,d1.w*2),(a4)

.draw_sprite_pixel7r:
	addq.l	#4,a6
	lea		512*2(a4),a4

	dbf		d5,.loop2

	dbf		d6,.loop1

	dbf		d7,draw_tc_sprites_loop

draw_tc_sprites_end:
	move.l	work_screen_address,d0
	move.l	show_screen_address,work_screen_address
	move.l	d0,show_screen_address
	add.l	#512*2*16+16*2,d0
	move.l	d0,display_screen_address

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

vbl_256:
	movem.l	d0-a6,-(sp)

	move.l	work_screen_address,d0
	move.l	show_screen_address,work_screen_address
	move.l	d0,show_screen_address
	add.l	#512*16+16,d0
	move.l	d0,display_screen_address
	move.b	display_screen_address+1,$ffff8201.w
	move.b	display_screen_address+2,$ffff8203.w
	move.b	display_screen_address+3,$ffff820d.w

	; Draw sprites.

	move.l	work_screen_address,a0
	add.l	#512*16+16,a0

	moveq	#0,d0
	move	#240-1,d7

.clear_screen_loop:
	move	d0,16*00(a0)
	move	d0,16*01(a0)
	move	d0,16*02(a0)
	move	d0,16*03(a0)
	move	d0,16*04(a0)
	move	d0,16*05(a0)
	move	d0,16*06(a0)
	move	d0,16*07(a0)
	move	d0,16*08(a0)
	move	d0,16*09(a0)
	move	d0,16*10(a0)
	move	d0,16*11(a0)
	move	d0,16*12(a0)
	move	d0,16*13(a0)
	move	d0,16*14(a0)
	move	d0,16*15(a0)

	add.l	#512,a0

	dbf		d7,.clear_screen_loop

	move.l	work_screen_address,a0
	lea		L_00EB0000,a1

	move	#128-1,d7

.sprite_loop:
	move	(a1)+,d0
	clr.l	d1
	move	(a1)+,d1
	move	(a1)+,d2
	move	(a1)+,d3

	jeq		.skip_sprite

	cmp		#240+16,d1
	jge		.skip_sprite

	move	d0,d2
	and		#$f,d2
	move.l	#%01111111111111100000000000000000,d3
	move.l	#%01000000000000100000000000000000,d4
	lsr.l	d2,d3
	lsr.l	d2,d4

	and		#$fff0,d0
	lea		(a0,d0.w),a2
	lsl.l	#8,d1
	add.l	d1,d1
	add.l	d1,a2

;	clr		512*0(a2)
;	clr		512*0+16(a2)

;	clr		512*15(a2)
;	clr		512*15+16(a2)

	or		d3,512*1+16(a2)
	or		d3,512*14+16(a2)

	swap	d3

	or		d3,512*1(a2)
	or		d3,512*14(a2)

	or		d4,512*2+16(a2)
	or		d4,512*3+16(a2)
	or		d4,512*4+16(a2)
	or		d4,512*5+16(a2)
	or		d4,512*6+16(a2)
	or		d4,512*7+16(a2)
	or		d4,512*8+16(a2)
	or		d4,512*9+16(a2)
	or		d4,512*10+16(a2)
	or		d4,512*11+16(a2)
	or		d4,512*12+16(a2)
	or		d4,512*13+16(a2)

	swap	d4

	or		d4,512*2(a2)
	or		d4,512*3(a2)
	or		d4,512*4(a2)
	or		d4,512*5(a2)
	or		d4,512*6(a2)
	or		d4,512*7(a2)
	or		d4,512*8(a2)
	or		d4,512*9(a2)
	or		d4,512*10(a2)
	or		d4,512*11(a2)
	or		d4,512*12(a2)
	or		d4,512*13(a2)

.skip_sprite:
	dbf		d7,.sprite_loop

	movem.l	(sp)+,d0-a6

	addq	#1,vbl_wait_counter

	move.l	L_00000118,-(sp)

	rts

; ------------------------------------------------------------------------------

; IKBD/MIDI interrupt routine (works only for the IKBD standard mode configuration).

keyboard:
	btst	#0,$fffffc00.w
	jne		.process_ikbd_data

	rte

.process_ikbd_data:
	move.l	d0,-(sp)

	move.b	$fffffc02.w,d0

	move.l	.processing_routine,-(sp)

	rts

.process_key_code:
	cmp.b	#$f6,d0 ; Key?
	jhs		.check_joystick

	cmp.b	#$01+$80,d0 ; "ESC" released?
	jeq		restore

	; Joystick emulation.

	cmp.b	#$2a,d0 ; "Left SHIFT" pressed?
	jne		.skip_left_shift1

	bclr	#6,iocs_joystick_data+3 ; Joystick button #1 down.

	move.l	(sp)+,d0

	rte

.skip_left_shift1:
	cmp.b	#$2a+$80,d0 ; "Left SHIFT" released?
	jne		.skip_left_shift2

	bset	#6,iocs_joystick_data+3 ; Joystick button #1 up.

	move.l	(sp)+,d0

	rte

.skip_left_shift2:
	cmp.b	#$1d,d0 ; "CONTROL" pressed?
	jne		.skip_control1

	bclr	#5,iocs_joystick_data+3 ; Joystick button #2 down.

	move.l	(sp)+,d0

	rte

.skip_control1:
	cmp.b	#$1d+$80,d0 ; "CONTROL" released?
	jne		.skip_control2

	bset	#5,iocs_joystick_data+3 ; Joystick button #2 up.

	move.l	(sp)+,d0

	rte

.skip_control2:
	cmp.b	#$4b,d0 ; "Left arrow" pressed?
	jne		.skip_left_arrow1

	bclr	#2,iocs_joystick_data+3 ; Joystick left.
	bset	#3,iocs_joystick_data+3 ; Not joystick right.

	move.l	(sp)+,d0

	rte

.skip_left_arrow1:
	cmp.b	#$4b+$80,d0 ; "Left arrow" released?
	jne		.skip_left_arrow2

	bset	#2,iocs_joystick_data+3 ; Not joystick left.

	move.l	(sp)+,d0

	rte

.skip_left_arrow2:
	cmp.b	#$4d,d0 ; "Right arrow" pressed?
	jne		.skip_right_arrow1

	bclr	#3,iocs_joystick_data+3 ; Joystick right.
	bset	#2,iocs_joystick_data+3 ; Not joystick left.

	move.l	(sp)+,d0

	rte

.skip_right_arrow1:
	cmp.b	#$4d+$80,d0 ; "Right arrow" released?
	jne		.skip_right_arrow2

	bset	#3,iocs_joystick_data+3 ; Not joystick right.

	move.l	(sp)+,d0

	rte

.skip_right_arrow2:
	cmp.b	#$48,d0 ; "Up arrow" pressed?
	jne		.skip_up_arrow1

	bclr	#0,iocs_joystick_data+3 ; Joystick up.
	bset	#1,iocs_joystick_data+3 ; Not joystick down.

	move.l	(sp)+,d0

	rte

.skip_up_arrow1:
	cmp.b	#$48+$80,d0 ; "Up arrow" released?
	jne		.skip_up_arrow2

	bset	#0,iocs_joystick_data+3 ; Not joystick up.

	move.l	(sp)+,d0

	rte

.skip_up_arrow2:
	cmp.b	#$50,d0 ; "Down arrow" pressed?
	jne		.skip_down_arrow1

	bclr	#1,iocs_joystick_data+3 ; Joystick down.
	bset	#0,iocs_joystick_data+3 ; Not joystick up.

	move.l	(sp)+,d0

	rte

.skip_down_arrow1:
	cmp.b	#$50+$80,d0 ; "Down arrow" released?
	jne		.skip_down_arrow2

	bset	#1,iocs_joystick_data+3 ; Not joystick down.

	move.l	(sp)+,d0

	rte

.skip_down_arrow2:
	move.l	(sp)+,d0

	rte

.check_joystick:
	cmp.b	#$fe,d0 ; Joystick?
	jlo		.check_mouse

	; d0.b = %1111111n (n = joystick number).

	move.l	#.process_joystick_data,.processing_routine

	move.l	(sp)+,d0

	rte

.process_joystick_data:
	; d0.b = %t000dddd (t = trigger, d = directions).

	and.b	#$f,d0
	not.b	d0
	move.b	d0,iocs_joystick_data+3
	
	move.l	#.process_key_code,.processing_routine
	
	move.l	(sp)+,d0

	rte

.check_mouse:
	cmp.b	#$f8,d0 ; Mouse?
	jlo		.unsupported_code

	; d0.b = %111110lr (l = left button, r = right button).

	bset	#5,iocs_joystick_data+3 ; Joystick button #2 up.

	btst	#0,d0
	jeq		.not_button_down

	bclr	#5,iocs_joystick_data+3 ; Joystick button #2 down.

.not_button_down:
	move.l	#.process_mouse_delta_x,.processing_routine

	move.l	(sp)+,d0

	rte

.process_mouse_delta_x:
	; d0.b = x.

	move.l	#.process_mouse_delta_y,.processing_routine

	move.l	(sp)+,d0

	rte

.process_mouse_delta_y:
	; d0.b = y.

	move.l	#.process_key_code,.processing_routine

	move.l	(sp)+,d0

	rte

.unsupported_code:
	illegal

.processing_routine:
	dc.l	.process_key_code

; ------------------------------------------------------------------------------

	data

welcome_text:
	dc.b	'ChoRenSha 68k',10,13
	dc.b	'-------------',10,13
	dc.b	10,13

	dc.b	'Original X68000 v1.01 (c) 1995 by',10,13
	dc.b	'Famibe No Yosshin',10,13
	dc.b	10,13

	dc.b	'Atari Falcon 030 port v20141019 by',10,13
	dc.b	'Sascha Springer',10,13
	dc.b	10,13
	
	dc.b	'Press a key to start...',10,13,0

	even

vbl_wait_counter:
	dc		0

work_screen_address:
	dc.l	screen1

show_screen_address:
	dc.l	screen2

display_screen_address:
	dc.l	screen1

	bss

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

	align 4

screen1:
;	ds.b	256*2*(16+240+16)
	ds.b	256*2*2*(16+240+16)

screen2:
;	ds.b	256*2*(16+240+16)
	ds.b	256*2*2*(16+240+16)

