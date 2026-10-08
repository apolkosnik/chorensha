; chunky 2 planar generic functions up to 8 bits per pixel

	MACHINE	68020

pop   MACRO reg
	move.\0 (sp)+,\1
	ENDM

push  MACRO reg
	move.\0 \1,-(sp)
	ENDM





	section    code





; cs2p_8
; Chunky or Scrambled 2 Planar conversion, up to 8 bit per pixel.
; a0 = chunky/raster buffer
; a1 = raster address
; a2 = conversion routine to call
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row_modulo
	public	_cs2p_8
	cnop	0,4
_cs2p_8:

	movem.l	d0-d7/a0-a6,-(sp)

	bsr.s	_cs2p_8_core

	movem.l	(sp)+,d0-d7/a0-a6
	rts





; cs2p_8 - core routine
;
; Chunky or Scrambled 2 Planar conversion, up to 8 bit per pixel.
;
; This is the main conversion routine, enabled to convert both chunky
; or scrambled to planar output.
; IMPORTANT: Is mandatory that the called routine (register a2) use
; the same following a0-a1/d0-d1 register parameters.
;
; a0 = chunky/raster buffer
; a1 = raster address
; a2 = conversion routine to call
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
;
	public	_cs2p_8_core
	cnop	0,4
_cs2p_8_core:

	tst.l	d3						; check if not interleaved bitmap (d3 = 0)
	beq.s	.standard_routine		; if row modulo equals 0, then not interleaved bitmap is used

	move.l	d0,d7					; use num_pixels counter for remaining rows
	move.l	d2,d6					; use row size in pixels, not bytes
	asl.l	#3,d6					; row size in pixels, not in bytes
.interleaved_loop:
	sub.l	d6,d7					; check if remaining pixels to convert
	ble.s	.last_step				; if negative, do last conversion step
	movem.l	d0-d3/d6-d7/a1-a2,-(sp)	; save reg values to stack
	move.l	d6,d0					; convert only the pixels in a single row
	move.l	d2,d1					; use bpl row size as bpl size during conversion
	jsr		(a2)					; convert a single row
	movem.l	(sp)+,d0-d3/d6-d7/a1-a2	; restore reg values from stack
	add.l	d3,a1					; adjust raster ptr to next row
	bra.s	.interleaved_loop		; do again for next row
.last_step:
	add.l	d7,d6					; calc remaining pixels to convert
	beq.s	.done					; if none to convert then all done
	move.l	d6,d0					; convert only remaining pixels in a single row
	move.l	d2,d1					; use row size as bpl size during conversion
	jsr		(a2)					; convert a single row
	bra.s	.done					; no more pixels to convert

.standard_routine:					; non-interleaved standard conversion conversion
	jsr		(a2)					; convert entire rows

.done:
	rts










; c2s_8_core
;
; Chunky 2 Scrambled conversion, 8 bit (1 byte) per pixel - core routine.
;
; a0 = chunky buffer
; a1 = scrambled buffer
; d0 = num pixels to convert
;
; IMPORTANT: all registers values will be messed up, it must be saved
; to stack BEFORE call this routine.
;
	public	_c2s_8_core
	cnop	0,4
_c2s_8_core:

	move.l	#24,a2		; needed for scrambled write
	;move.l	#$FF00FF00,a3

	lsr.l	#5,d0
	dbra.w	d0,.c2s_loop
	nop

	cnop	0,64
.c2s_loop:
	move.w	d0,a6
	movem.l	(a0)+,d0-d7
		; D0 = 0, 1, 2, 3
		; D1 = 4, 5, 6, 7
		; D2 = 8, 9, 10, 11
		; D3 = 12, 13, 14, 15
		; D4 = 16, 17, 18, 19
		; D5 = 20, 21, 22, 23
		; D6 = 24, 25, 26, 27
		; D7 = 28, 29, 30, 31
	ror.l	#8,d2
	ror.l	#8,d3
	swap	d4
	swap	d5
	rol.l	#8,d6
	rol.l	#8,d7
		; D0 = 0, 1, 2, 3
		; D1 = 4, 5, 6, 7
		; D2 = 11, 8, 9, 10
		; D3 = 15, 12, 13, 14
		; D4 = 18, 19, 16, 17
		; D5 = 22, 23, 20, 21
		; D6 = 25, 26, 27, 24
		; D7 = 29, 30, 31, 28

	move.w	d0,a4
	move.w	d1,a5
	move.w	d4,d0	; D0 = 0, 1, 16, 17
	move.w	d5,d1	; D1 = 4, 5, 20, 21
	move.w	a4,d4	; D4 = 18, 19, 2, 3
	move.w	a5,d5	; D5 = 22, 23, 6, 7
	move.w	d2,a4
	move.w	d3,a5
	move.w	d6,d2	; D2 = 11, 8, 27, 24
	move.w	d7,d3	; D3 = 15, 12, 31, 28
	move.w	a4,d6	; D6 = 25, 26, 9, 10
	move.w	a5,d7	; D7 = 29, 30, 13, 14
		; D0 = 0, 1, 16, 17
		; D1 = 4, 5, 20, 21
		; D2 = 11, 8, 27, 24
		; D3 = 15, 12, 31, 28
		; D4 = 18, 19, 2, 3
		; D5 = 22, 23, 6, 7
		; D6 = 25, 26, 9, 10
		; D7 = 29, 30, 13, 14

mask_bytes	equ	$FF00FF00

	;exg.l	a3,d3	; D3 = #$FF00FF00 : A3 = 15, 12, 31, 28
	move.l	d7,a5	; A5 = 29, 30, 13, 14 : D7 = scratch

	move.l	d0,d7
	and.l	#mask_bytes,d0	; D0 = 0, _, 16, _
	eor.l	d0,d7	; D7 = _, 1, _, 17
	eor.l	d2,d0
	and.l	#mask_bytes,d2	; D2 = 11, _, 27, _
	eor.l	d2,d0	; D0 = 0, 8, 16, 24
	eor.l	d4,d2
	move.l	d0,(a1)+	; scrambled write offset #0
	and.l	#mask_bytes,d4	; D4 = 18, _, 2, _
	eor.l	d4,d2	; D2 = 11, 19, 27, 3
	eor.l	d6,d4
	ror.l	#8,d2	; D2 = 3, 11, 19, 23 - needed for scrambled write
	move.l	d2,8(a1)	; scrambled write offset #3
	and.l	#mask_bytes,d6	; D6 = 25, _, 9, _
	eor.l	d6,d4	; D4 = 18, 26, 2, 10
	swap	d4		; D4 = 2, 10, 18, 26 - needed for scrambled write

	move.l	d4,4(a1)	; scrambled write offset #2
	or.l	d7,d6	; D6 = 25, 1, 9, 17
	rol.l	#8,d6	; D6 = 1, 9, 17, 25

	;move.l	a3,d0	; D0 = 15, 12, 31, 28 - needed for scrambled write
	move.l	a5,d7	; D7 = 29, 30, 13, 14 : A5 = scratch
	move.l	d6,(a1)+	; scrambled write offset #1

	move.l	d1,d6
	and.l	#mask_bytes,d1	; D1 = 4, _, 20, _ - needed for scrambled write
	eor.l	d1,d6	; D6 = _, 5, _, 21
	eor.l	d3,d1	;                  - needed for scrambled write
	and.l	#mask_bytes,d3	; D3 = 15, _, 31, _ - needed for scrambled write
	eor.l	d3,d1	; D1 = 4, 12, 20, 28 - needed for scrambled write
	eor.l	d5,d3	;                  - needed for scrambled write
	move.l	d1,8(a1)	; scrambled write offset #4
	and.l	#mask_bytes,d5	; D5 = 22, _, 6, _ - needed for scrambled write
	eor.l	d5,d3	; D3 = 15, 23, 31, 7 - needed for scrambled write
	eor.l	d7,d5
	ror.l	#8,d3	; D3 = 7, 15, 23, 31 - needed for scrambled write
	and.l	#mask_bytes,d7	; D7 = 29, _, 13, _ - needed for scrambled 
	move.l	d3,20(a1)	; scrambled write offset #7
	eor.l	d7,d5	; D5 = 22, 30, 6, 14
	or.l	d6,d7	; D7 = 29, 5, 13, 21

	swap	d5		; D5 = 6, 14, 22, 30 - needed for scrambled write
	move.l	d5,16(a1)	; scrambled write offset #6
	rol.l	#8,d7	; D7 = 5, 13, 21, 29 - needed for scrambled write

	move.w	a6,d0		; interleaved instruction

	; restore mask in A3 for next loop
	;exg.l	a3,d3	; A3 = #$FF00FF00 : D2 = 11, 19, 27, 3 - needed for scrambled write
	move.l	d7,12(a1)	; scrambled write offset #5
		; D0 = 0, 8, 16, 24
		; D6 = 1, 9, 17, 25 - prev value
		; D4 = 2, 10, 18, 26
		; D2 = 3, 11, 19, 23
		; D1 = 4, 12, 20, 28
		; D7 = 5, 13, 21, 29
		; D5 = 6, 14, 22, 30
		; D3 = 7, 15, 23, 31 - prev value

	add.l	a2,a1		; interleaved instruction
	dbra.w	d0,.c2s_loop
.c2s_loop_end:

;	; DEBUG: try to calculate the loop code size in bytes
;	lea		.c2s_loop,a0
;	lea		.c2s_loop_end,a1
;	move.l	a1,d0
;	sub.l	a0,d0	; 0xb2 = 178 bytes
;	nop

			;------;
			; exit ;
			;------;

.c2s_exit:

	rts
  









; cs2p_8_delta
; Chunky or Scrambled 2 Planar delta conversion.
;
; IMPORTANT: Is mandatory that the called routine (register a2) use
; the same following a0-a3/d0-d3 register parameters.
;
; a0 = scrambled buffer
; a1 = raster address
; a3 = reference address
; a4 = conversion routine to call
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
	public	_cs2p_8_delta
	cnop	0,4
_cs2p_8_delta:

	movem.l	d0-d7/a0-a6,-(sp)

	bsr.s	_cs2p_8_delta_core

	movem.l	(sp)+,d0-d7/a0-a6
	rts





; cs2p_8_delta - core routine
; Chunky or Scrambled 2 Planar delta conversion
;
; This is the main delta conversion routine, enabled to convert both
; chunky or scrambled to planar output.
; IMPORTANT: Is mandatory that the called routine (register a2) use
; the same following a0-a3/d0-d3 register parameters.
;
; a0 = scrambled buffer
; a1 = raster address
; a3 = reference address
; a4 = conversion routine to call
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
	public	_cs2p_8_delta_core
	cnop	0,4
_cs2p_8_delta_core:

	move.l	d0,d7
	lsr.l	#5,d7			;32 pixels per loop

	moveq	#32,d0			;if required, convert only one chunk of pixels per time
 
 	dbra.w	d7,.delta_loop
	nop		; avoid compiler warning "short-branch to following instruction turned into a nop"

	cnop	0,4
.delta_loop:
	move.l	(a0),d4
	cmp.l	(a3),d4
	bne.s	.convert
	move.l	4(a0),d4
	cmp.l	4(a3),d4
	bne.s	.convert
	move.l	8(a0),d4
	cmp.l	8(a3),d4
	bne.s	.convert
	move.l	12(a0),d4
	cmp.l	12(a3),d4
	bne.s	.convert
	move.l	16(a0),d4
	cmp.l	16(a3),d4
	bne.s	.convert
	move.l	20(a0),d4
	cmp.l	20(a3),d4
	bne.s	.convert
	move.l	24(a0),d4
	cmp.l	24(a3),d4
	bne.s	.convert
	move.l	28(a0),d4
	cmp.l	28(a3),d4
	bne.s	.convert

	lea		32(a0),a0
	lea		4(a1),a1
	lea		32(a3),a3

	dbra	d7,.delta_loop
.delta_loop_end:
	rts

	cnop	0,4
.convert:
	movem.l	d0-d7/a0-a6,-(sp)
	jsr		(a4)
	movem.l	(sp)+,d0-d7/a0-a6

	lea		32(a0),a0
	lea		4(a1),a1
	lea		32(a3),a3

	dbra	d7,.delta_loop
.convert_end:
	rts










; cs2p_8_delta_writeback
; Chunky or Scrambled 2 Planar delta conversion with writeback to reference buffer.
;
; IMPORTANT: Is mandatory that the called routine (register a2) use
; the same following a0-a3/d0-d3 register parameters.
;
; a0 = scrambled buffer
; a1 = raster address
; a3 = reference address
; a4 = conversion routine to call
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
	public	_cs2p_8_delta_writeback
	cnop	0,4
_cs2p_8_delta_writeback:

	movem.l	d0-d7/a0-a6,-(sp)

	bsr.s	_cs2p_8_delta_writeback_core

	movem.l	(sp)+,d0-d7/a0-a6
	rts





; cs2p_8_delta_writeback - core routine
; Chunky or Scrambled 2 Planar delta conversion with writeback to reference buffer
;
; This is the main delta conversion routine, enabled to convert both
; chunky or scrambled to planar output.
; IMPORTANT: Is mandatory that the called routine (register a2) use
; the same following a0-a3/d0-d3 register parameters.
;
; a0 = scrambled buffer
; a1 = raster address
; a3 = reference address
; a4 = conversion routine to call
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
	public	_cs2p_8_delta_writeback_core
	cnop	0,4
_cs2p_8_delta_writeback_core:

	move.l	d0,d7
	lsr.l	#5,d7			;32 pixels per loop

	moveq	#32,d0			;if required, convert only one chunk of pixels per time
 
 	dbra.w	d7,.delta_loop
	nop		; avoid compiler warning "short-branch to following instruction turned into a nop"

	cnop	0,4
.delta_loop:
	move.l	(a0),d4
	cmp.l	(a3),d4
	bne.s	.convert_32
	move.l	4(a0),d4
	cmp.l	4(a3),d4
	bne.s	.convert_28
	move.l	8(a0),d4
	cmp.l	8(a3),d4
	bne.s	.convert_24
	move.l	12(a0),d4
	cmp.l	12(a3),d4
	bne.s	.convert_24
	move.l	16(a0),d4
	cmp.l	16(a3),d4
	bne.s	.convert_16
	move.l	20(a0),d4
	cmp.l	20(a3),d4
	bne.s	.convert_16
	move.l	24(a0),d4
	cmp.l	24(a3),d4
	bne.s	.convert_16
	move.l	28(a0),d4
	cmp.l	28(a3),d4
	bne.s	.convert_16

	lea		32(a0),a0
	lea		4(a1),a1
	lea		32(a3),a3

	dbra	d7,.delta_loop
.delta_loop_end:
	rts

	cnop	0,4
.convert_32:
	move.l	d4,(a3)				; copy chunky to reference buffer

.convert_28:
	move.l	4(a0),4(a3)			; copy chunky to reference buffer

.convert_24:
	movem.l	8(a0),d5-d6			; copy chunky to reference buffer
	movem.l	d5-d6,8(a3)

.convert_16:
	movem.l	16(a0),d5-d6/a5-a6	; copy chunky to reference buffer
	movem.l	d5-d6/a5-a6,16(a3)

.convert:
	movem.l	d0-d7/a0-a6,-(sp)
	jsr		(a4)
	movem.l	(sp)+,d0-d7/a0-a6

	lea		32(a0),a0
	lea		4(a1),a1
	lea		32(a3),a3

	dbra	d7,.delta_loop
.convert_end:
	rts





	end
