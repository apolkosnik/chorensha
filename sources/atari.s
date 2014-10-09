LINE_F_OFFSET = 2																| 0 = 68000, 2 = 68030

	text

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
	bne		.not_close

	move	26+LINE_F_OFFSET+0(sp),d0

	move	d0,-(sp)
	move	#62,-(sp)
	trap	#1
	addq	#4,sp

	bra		.exit

.not_close:
	cmp		#$ff4a,d0 ; _SETBLOCK
	bne		.not_setblock

	move.l	26+LINE_F_OFFSET+4(sp),d0

	cmp.l	#$ffffff,d0
	beq		.1

	clr.l	d0

	bra		.exit

.1:
	move.l	#$81200000,d0

	bra		.exit

.not_setblock:
	clr.l	d0

.exit:
	movem.l	(sp)+,d1-d2/a0-a2

	rte

; ------------------------------------------------------------------------------

trap_f:
	rte

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


