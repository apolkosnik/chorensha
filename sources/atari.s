LINE_F_OFFSET = 2																| 0 = 68000, 2 = 68030

	text

; ------------------------------------------------------------------------------

start:
	jsr		init

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

	move	d0,-(sp)
	pea		(a0)
	move	#61,-(sp)
	trap	#1
	addq	#8,sp

	jra		.exit

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

trap_f:
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
	cmp.b	#$ae,d0 ; _OS_CURON
	jne		.no_os_curon

	rte

.no_os_curon:
	cmp.b	#$af,d0 ; _OS_CUROFF
	jne		.no_os_curoff

	rte

.no_os_curoff:
	illegal

; ------------------------------------------------------------------------------

vbl:
	rte

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


