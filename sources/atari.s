; iconv -c -f SHIFT-JIS -t UTF-8 programmers.man > programmers.man.txt

LINE_F_OFFSET = 2																| 0 = 68000, 2 = 68030

	text

; ------------------------------------------------------------------------------

start:
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


	pea		string
	move	#9,-(sp)
	trap	#1
	addq	#6,sp

	move	#1,-(sp)
	trap	#1
	addq	#2,sp

	clr		-(sp)
	trap	#1

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

	move.l	$ffff820e.w,d0
	move.l	$ffff8264.w,d1
	movem.l	$ffff8282.w,d2-d5
	movem.l	$ffff82a2.w,d6-a0
	move.l	$ffff82c0.w,a1
	move	$ffff820a.w,a2
	movem.l	d0-a2,old_videl

	clr.b	$fffffa07.w
	clr.b	$fffffa09.w
	clr.b	$fffffa13.w
	clr.b	$fffffa15.w

	move.l	#line_f,$2c.w
	move.l	#trap_2,$88.w
	move.l	#trap_4,$90.w
	move.l	#trap_f,$bc.w
	move.l	#vbl,$70.w
	move.l	#keyboard,$118.w

	bset	#6,$fffffa09.w
	bset	#6,$fffffa15.w

	bclr	#3,$fffffa17.w

	rts

; ------------------------------------------------------------------------------

line_f:
	movem.l	d1-d2/a0-a2,-(sp)

	move.l	22(sp),a0
	move	(a0),d0
	addq.l	#2,22(sp)

	cmp		#$fe00,d0 ; __LMUL
	jne		.not__lmul

	muls.l	d1,d0

	jra		.exit

.not__lmul:
	cmp		#$fe01,d0 ; __LDIV
	jne		.not__ldiv

	divs.l	d1,d0

	jra		.exit

.not__ldiv:
	cmp		#$fe0d,d0 ; __SRAND
	jne		.not__srand

	clr.l	d0

	jra		.exit

.not__srand:
	cmp		#$ff06,d0 ; _INPOUT
	jne		.not_inpout

	clr.l	d0

	jra		.exit

.not_inpout:
	cmp		#$ff20,d0 ; _SUPER
	jne		.not_super

	move.l	26+LINE_F_OFFSET+0(sp),a0

	clr.l	d0

	jra		.exit

.not_super:
	cmp		#$ff23,d0 ; _CONCTRL
	jne		.not_conctrl

	clr.l	d0

	jra		.exit

.not_conctrl:
	cmp		#$ff25,d0 ; _INTVCS
	jne		.not_intvcs

	move	26+LINE_F_OFFSET+0(sp),d0
	move	26+LINE_F_OFFSET+4(sp),a0

	clr.l	d0

	jra		.exit

.not_intvcs:
	cmp		#$ff36,d0 ; _DSKFRE
	jne		.not_dskfre

	move.l	#10000000,d0

	jra		.exit

.not_dskfre:
	cmp		#$ff37,d0 ; _NAMECK
	jne		.not_nameck

	clr.l	d0

	jra		.exit

.not_nameck:
	cmp		#$ff3d,d0 ; _OPEN
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
	cmp		#$ff3f,d0 ; _READ
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
	cmp		#$ff3e,d0 ; _CLOSE
	jne		.not_close

	move	26+LINE_F_OFFSET+0(sp),d0

	move	d0,-(sp)
	move	#62,-(sp)
	trap	#1
	addq	#4,sp

	jra		.exit

.not_close:
	cmp		#$ff40,d0 ; _WRITE
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
	cmp		#$ff42,d0 ; _SEEK
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
	cmp		#$ff44,d0 ; _IOCTRL
	jne		.not_ioctrl

	clr.l	d0

	jra		.exit

.not_ioctrl:
	cmp		#$ff4a,d0 ; _SETBLOCK
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

	move	#-1,d0

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

; ------------------------------------------------------------------------------

vbl:
	movem.l	d0-a6,-(sp)

	lea		screen_address,a0
	clr.b	(a0)
	move.b	$ffff8201.w,1(a0)
	move.b	$ffff8203.w,2(a0)
	move.b	$ffff820d.w,3(a0)

	move.l	(a0),a0

	lea		L_00EB0000,a1

	move	#128-1,d7

.sprite_loop:
	move	(a1)+,d0
	move	(a1)+,d1
	move	(a1)+,d2
	move	(a1)+,d3

	jeq		.skip_sprite

	cmp		#320-16,d0
	jge		.skip_sprite

	cmp		#200-16,d1
	jge		.skip_sprite

	move	d0,d2
	and		#$f,d2
	move.l	#%00000011110000000000000000000000,d3
	move.l	#%00111111111111000000000000000000,d4
	lsr.l	d2,d3
	lsr.l	d2,d4

	and		#$fff0,d0
	lsr		#1,d0
	lea		(a0,d0.w),a2
	mulu	#160,d1
	add.l	d1,a2

	clr		160*0(a2)
	clr		160*0+8(a2)

	clr		160*7(a2)
	clr		160*7+8(a2)

	move	d3,160*1+8(a2)
	move	d3,160*2+8(a2)
	move	d3,160*5+8(a2)
	move	d3,160*6+8(a2)

	swap	d3

	move	d3,160*1(a2)
	move	d3,160*2(a2)
	move	d3,160*5(a2)
	move	d3,160*6(a2)

	move	d4,160*3+8(a2)
	move	d4,160*4+8(a2)

	swap	d4

	move	d4,160*3(a2)
	move	d4,160*4(a2)

.skip_sprite:
	dbf		d7,.sprite_loop

	movem.l	(sp)+,d0-a6

	move.l	L_00000118,-(sp)

	rts

screen_address:
	dc.l	0

; ------------------------------------------------------------------------------

keyboard:
	rte

; ------------------------------------------------------------------------------

	data

string:
	dc.b	'hallo!',10,13,0

	even

sincos_tables_start:
	incbin	"sincos.dat"
sincos_tables_end:

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


