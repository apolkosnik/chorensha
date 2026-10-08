; This is the main C2P algorythm

; History:
; v1: chunky to planar conversion, same code used in gfx3d.library
;     (ref: gfx3dlib_31_src package on Aminet)
; v2: improved swap of words in the first step (chunky 2 scrambled)
; v3: little optimization of register usage in chunky to scrambled, in order to
;     speed up the scramblednext to planar conversion
; v4: big optimization in mexg MACRO, not the mask identity the bits to swap
; v5: interleaving of instructions between writes do memory in chunky to scrambled
;     optimized register usage in scrambled to planar
; v6: same as v5, but with interleaved instructions in s2p loop for 060+
; v7: direct use of mask patterns instead of using a dedicate register (D6) for ANDs
; v8: explicit bitplane size in pixels by params
; v9: optimized parameters and avoid multiple stack push/pop





	MACHINE	68020





mexg	MACRO	src,dest,mask,tmp	; bits in mask are swapped
	move.\0	\1,\4
	eor.\0	\2,\4
	and.\0	\3,\4
	eor.\0	\4,\1
	eor.\0	\4,\2
	ENDM

pop   MACRO reg
	move.\0 (sp)+,\1
	ENDM

push  MACRO reg
	move.\0 \1,-(sp)
	ENDM





	section    code





; c2p_8x8_mexg
; Chunky 2 Planar conversion, 8 bit per pixel.
; a0 = chunky buffer
; a1 = raster address
; a2 = scrambled buffer
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
	public	_c2p_8x8_mexg
	cnop	0,4
_c2p_8x8_mexg:

	movem.l	d0-d7/a1-a6,-(sp)

library			equ	16	;20
;chunky			equ	32
raster			equ	32
scrambled		equ	36
num_pixels		equ	0
bpl_size		equ	4
bpl_row_size	equ	8
row_modulo		equ	12

	move.l	a2,a1

	bsr.w	_c2s_8_core

	move.l	scrambled(sp),a0
	move.l	raster(sp),a1
	move.l	num_pixels(sp),d0
	move.l	bpl_size(sp),d1
	move.l	bpl_row_size(sp),d2
	move.l	row_modulo(sp),d3

	lea		_s2p_8x8_mexg_core,a2
	bsr.w	_cs2p_8_core


	movem.l	(sp)+,d0-d7/a1-a6
	rts










; s2p_8x8_mexg
; Scrambled 2 Planar conversion, 8 bit per pixel.
; a0 = scrambled buffer
; a1 = raster address
; d0 = num pixels to convert
; d1 = bitplane size
; d2 = bitplane row size
; d3 = row modulo
	public	_s2p_8x8_mexg
	cnop	0,4
_s2p_8x8_mexg:

	push.l	a2

	lea		_s2p_8x8_mexg_core,a2
	bsr.w	_cs2p_8

	pop.l	a2
	rts










; s2p_8x8_mexg core procedure
; Scrambled 2 Planar conversion, 8 bit per pixel.
; a0 = scrambled buffer
; a1 = raster address
; d0 = num pixels to convert
; d1 = bitplane size
	public	_s2p_8x8_mexg_core
	cnop	0,4
_s2p_8x8_mexg_core:

	move.l	d1,a2			;bplsize in a2

	lea		(a1,d1.l*2),a3
	add.l	d1,a3			;bpl3 in a3

	lea		(a3,d1.l*2),a6	;bpl5 ptr in A6

	lsr.l	#5,d0			;32 pixels per loop
	; subq.l	#1,d0
	move.l	d0,d7

	; bra.s	.s2p_loop
	dbra.w	d7,.s2p_loop
	nop		; avoid compiler warning "short-branch to following instruction turned into a nop"

	cnop	0,64
.s2p_loop:

	move.w	d7,a4



	;------------------------------------
	; INIT: CHUNKY DATA (1 BYTE PER ROW)
	;------------------------------------

	movem.l	(a0)+,d0-d6/a5

		;---------------------
		;D0 = a7a6a5a4a3a2a1a0
		;D1 = b7b6b5b4b3b2b1b0
		;D2 = c7c6c5c4c3c2c1c0
		;D3 = d7d6d5d4d3d2d1d0
		;D4 = e7e6e5e4e3e2e1e0
		;D5 = f7f6f5f4f3f2f1f0
		;D6 = g7g6g5g4g3g2g1g0
		;A5 = h7h6h5h4h3h2h1h0
		;---------------------



	;--------------------------------------------
	; STEP 1: ROTATE LEFT, 7-N BITS PER N-TH ROW
	;--------------------------------------------

	rol.l	#1,d6
	rol.l	#2,d5
	rol.l	#3,d4

	;move.l	d6,a6		; superscalar interleaving, see below

	rol.l	#6,d1
	rol.l	#4,d3
	rol.l	#5,d2
	rol.l	#7,d0

		;---------------------
		;D0 = a0i7i6i5i4i3i2i1
		;D1 = b1b0j7j6j5j4j3j2
		;D2 = c2c1c0k7k6k5k4k3
		;D3 = d3d2d1d0l7l6l5l4
		;D4 = e4e3e2e1e0m7m6m5
		;D5 = f5f4f3f2f1f0n7n6
		;D6 = g6g5g4g3g2g1g0o7
		;A5 = h7h6h5h4h3h2h1h0
		;---------------------



	;--------------------------
	; STEP 2: SWAP SINGLE BITS
	;--------------------------

mask_bits	equ	$AAAAAAAA
	;move.l	#$AAAAAAAA,d6
		;D6 = 1 0 1 0 1 0 1 0

	mexg.l	d0,d1,#mask_bits,d7
		;MASK 1 0 1 0 1 0 1 0
		;D0 = b1i7j7i5j5i3j3i1
		;D1 = a0b0i6j6i4j4i2j2

	mexg.l	d2,d3,#mask_bits,d7
		;MASK 1 0 1 0 1 0 1 0
		;D2 = d3c1d1k7l7k5l5k3
		;D3 = c2d2c0d0k6l6k4l4

	;exg.l	d1,a6
		;D1 = g6g5g4g3g2g1g0o7
		;A6 = a0b0i6j6i4j4i2j2

	mexg.l	d4,d5,#mask_bits,d7
		;MASK 1 0 1 0 1 0 1 0
		;D4 = f5e3f3e1f1m7n7m5
		;D5 = e4f4e2f2e0f0m6n6

	exg.l	d2,a5
		;D2 = h7h6h5h4h3h2h1h0
		;A5 = d3c1d1k7l7k5l5k3

	mexg.l	d6,d2,#mask_bits,d7
		;MASK 1 0 1 0 1 0 1 0
		;D6 = h7g5h5g3h2g1h1o7
		;D2 = g6h6g4h4g2h2g0h0

		;---------------------
		;D0 = b1i7j7i5j5i3j3i1
		;D1 = a0b0i6j6i4j4i2j2
		;A5 = d3c1d1k7l7k5l5k3
		;D3 = c2d2c0d0k6l6k4l4
		;D4 = f5e3f3e1f1m7n7m5
		;D5 = e4f4e2f2e0f0m6n6
		;D6 = h7g5h5g3h2g1h1o7
		;D2 = g6h6g4h4g2h2g0h0
		;---------------------


	;---------------------------
	; STEP 3: SWAP COUPLED BITS
	;---------------------------

mask_couples_1	equ	$99999999
	;move.l	#$99999999,d6
		;D6 = 1 0 0 1 1 0 0 1

	mexg.l	d4,d6,#mask_couples_1,d7
		;MASK 1 0 0 1 1 0 0 1
		;D4 = h7e3f3g3h3m7n7o7
		;D6 = f5g5h5e1f1g1h1m5

	exg.l	d4,a5
		;A5 = h7e3f3g3h3m7n7o7
		;D4 = d3c1d1k7l7k5l5k3

	mexg.l	d0,d4,#mask_couples_1,d7
		;MASK 1 0 0 1 1 0 0 1
		;D0 = d3i7j7k7l7i3j3k3
		;D4 = b1c1d1i5j5k5l5i1

mask_couples_2	equ	$CCCCCCCC
	;ror.l	#1,d6	; #$CCCCCCCC
		;D6 = 1 1 0 0 1 1 0 0

	mexg.l	d5,d2,#mask_couples_2,d7
		;MASK 1 1 0 0 1 1 0 0
		;D5 = g6h6e2f2g2h2m6n6
		;D2 = e4f4g4h4e0f0g0h0

	;exg.l	a6,d1
		;A6 = f5g5h5e1f1g1h1m5
		;D1 = a0b0i6j6i4j4i2j2

	mexg.l	d3,d1,#mask_couples_2,d7
		;MASK 1 1 0 0 1 1 0 0
		;D3 = a0b0c0d0i4j4k4l4
		;D1 = c2d2i6j6k6l6i2j2

		;---------------------
		;D0 = d3i7j7k7l7i3j3k3
		;D1 = c2d2i6j6k6l6i2j2
		;D4 = b1c1d1i5j5k5l5i1
		;D3 = a0b0c0d0i4j4k4l4
		;A5 = h7e3f3g3h3m7n7o7
		;D5 = g6h6e2f2g2h2m6n6
		;D6 = f5g5h5e1f1g1h1m5
		;D2 = e4f4g4h4e0f0g0h0
		;---------------------



	;----------------------
	; STEP 4: SWAP NIBBLES
	;----------------------

mask_nibbles_1	equ	$F0F0F0F0
	;move.l	#$F0F0F0F0,d6
		;D6 = 1 1 1 1 0 0 0 0

	mexg.l	d2,d3,#mask_nibbles_1,d7
		;MASK 1 1 1 1 0 0 0 0
		;D2 = a0b0c0d0e0f0g0h0
		;D3 = e4f4g4h4i4j4k4l4

	move.l	d2,(a1)+			;write bpl0
		;D2 = free for use

	ror.l	#4,d3
		;D3 = a4b4c4d4e4f4g4h4

mask_nibbles_2	equ	$E1E1E1E1
	;rol.l	#1,d6	; #$E1E1E1E1
		;D6 = 1 1 1 0 0 0 0 1

	;move.l	a6,d2
		;D2 = f5g5h5e1f1g1h1m5
		;A6 = free to use

	; superscalar interleaving, see before
	move.l	d3,(a3,a2.l)		;write bpl4
	 	;D3 = free for use

	mexg.l	d4,d6,#mask_nibbles_2,d7
		;MASK 1 1 1 0 0 0 0 1
		;D4 = f5g5h5i5j5k5l5m5
		;D6 = b1c1d1e1f1g1h1i1

	ror.l	#1,d6
		;D6 = a1b1c1d1e1f1g1h1

	ror.l	#5,d4
		;D4 = a5b5c5d5e5f5g5h5

	; superscalar interleaving, see before
	move.l	d6,-4(a1,a2.l)		;write bpl1
		;D6 = free for use

mask_nibbles_3	equ	$C3C3C3C3
	;rol.l	#1,d6	; #$C3C3C3C3
		;D6 = 1 1 0 0 0 0 1 1

	mexg.l	d5,d1,#mask_nibbles_3,d7
		;MASK 1 1 0 0 0 0 1 1
		;D5 = c2d2e2f2g2h2i2j2
		;D1 = g6h6i6j6k6l6m6n6

	; superscalar interleaving, see before
	move.l	d4,(a6)+			;write bpl5
		;D4 = free for use

	ror.l	#2,d5
		;D5 = a2b2c2d2e2f2g2h2

	ror.l	#6,d1
		;D1 = a6b6c6d6e6f6g6h6

	; superscalar interleaving, see before
	move.l	d5,-4(a1,a2.l*2)	;write bpl2
		;D5 = free for use

mask_nibbles_4	equ	$87878787
	;rol.l	#1,d6	; #$87878787
		;D6 = 1 0 0 0 0 1 1 1

	move.l	a5,d2
		;D2 = h7e3f3g3h3m7n7o7

	; superscalar interleaving, see before
	move.l	d1,-4(a6,a2.l)		;write bpl6
		;D1 = free to use

	mexg.l	d0,d2,#mask_nibbles_4,d7
		;MASK 1 0 0 0 0 1 1 1
		;D0 = h7i7j7k7l7m7n7o7
		;D2 = d3e3f3g3h3i3j3k3

	ror.l	#3,d2
		;D2 = a3b3c3d3e3f3g3h3

	; superscalar interleaving, see before
	move.l	d2,(a3)+			;write bpl3
		;D2 = free for use

	ror.l	#7,d0
		;D0 = a7b7c7d7e7f7g7h7

	move.w	a4,d7
	move.l	d0,-4(a6,a2.l*2)	; write bpl7
	dbra	d7,.s2p_loop
.s2p_loop_end:

;	; DEBUG: trying to calculate the loop code size in bytes
;	lea		.s2p_loop,a0
;	lea		.s2p_loop_end,a1
;	move.l	a1,d0
;	sub.l	a0,d0	; 0xf0 = 240 bytes
;	nop

			;------;
			; exit ;
			;------;

.s2p_exit:

	rts





	end
