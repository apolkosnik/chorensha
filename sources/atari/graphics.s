
	xdef prepare_sprites
	xdef draw_sprites
	xdef compile_sprite

	xdef text_bitmaps
	xdef show_screen_address
	xdef work_screen_address

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

convert_palettes:
	movem.l	d0-a6,-(sp)

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

	movem.l	(sp)+,d0-a6

	rts

	bss

converted_sprite_palettes:
	ds.w	16*16

	text

; ------------------------------------------------------------------------------

prepare_sprites:
	movem.l	d0-a6,-(sp)

    move    sr,-(sp)

    move    #$2700,sr

    ; Copy sprite infos.

    lea     SPRITE_DATA_TABLE,a0
    lea     sprite_data_table,a1
    move.l  CURRENT_SPRITE_DATA_ENTRY,d7
    sub.l   a0,d7
    lsr.l   #3,d7
    move.l  d7,sprite_data_count
    subq    #1,d7
    jmi     .skip_all

.copy_loop1:
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+

    dbf     d7,.copy_loop1

    ; Copy sprite graphics.

    lea     L_00EB8000,a0
    lea     sprite_graphics_buffer,a1

    move    #$8000/32-1,d7

.copy_loop2:
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+
    move.l  (a0)+,(a1)+

    dbf     d7,.copy_loop2

.skip_all:
    move    (sp)+,sr

	movem.l	(sp)+,d0-a6

	rts

    bss

sprite_data_count:
    ds.l    1

sprite_data_table:
    ds.b    512*8

sprite_graphics_buffer:
    ds.b    $8000

    text

; ------------------------------------------------------------------------------

draw_sprites:
	movem.l	d0-a6,-(sp)

	rem

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

	erem

	; rem

	; Draw background.

	lea		background_image,a0
	move.l	work_screen_address,a1
	add.l	#512*2*16+16*2,a1

	move	BACKGROUND_SCROLL_COUNTER,d0
	move.l	#512-1,d1
	and		#$1ff,d0
	sub		d0,d1	
	swap	d1
	lsr.l	#7,d1
	add.l	d1,a0

	move	#240-1,d7

.copy_loop:
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*2(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*3(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*4(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*5(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*6(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*7(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*8(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*9(a1)
	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,12*4*10(a1)

	add.l	#256*2*2,a1

	dbf		d7,.copy_loop

	; erem

	; Convert palettes.

	jsr		convert_palettes

	; Draw sprites.

	move.l	work_screen_address,a0
	lea		converted_sprite_palettes,a3 ; Sprite palette table.

    tst     machine_has_fast_ram
    jeq     .draw_live_sprites

    lea     sprite_data_table,a1
    lea     sprite_graphics_buffer,a2
    move.l  sprite_data_count,d7
    lea     8(a1,d7.l*8),a1
    subq.l  #1,d7
    jmi     draw_sprites_end

    jra     draw_sprites_loop

.draw_live_sprites:
	move.l	CURRENT_SPRITE_DATA_ENTRY,a1
	lea		L_00EB8000,a2 ; Sprite VRAM.
	addq.l	#8,a1
	move.l	a1,d7
	sub.l	#SPRITE_DATA_TABLE,d7
	lsr		#3,d7
	subq	#1,d7

draw_sprites_loop:
	sub		#16,a1

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
	jeq		draw_sprites_normal

	cmp		#$8000,d3
	jeq		draw_sprites_vertical_flipped

	cmp		#$4000,d3
	jeq		draw_sprites_horizontal_flipped

; --------------------------------------
; draw_sprites_vertical_and_horizontal_flipped:
; --------------------------------------
	add.l	#15*512*2,a4

	move	d2,d3
	lsr		#3,d2
	and		#$1e0,d2
	lea		(a3,d2.w),a5 ; Palette address.

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
	dbf		d7,draw_sprites_loop

	jra		draw_sprites_end

; --------------------------------------
draw_sprites_normal:
; --------------------------------------
	move	d2,d3
	lsr		#3,d2
	and		#$1e0,d2
	lea		(a3,d2.w),a5 ; Palette address.

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

	dbf		d7,draw_sprites_loop

	jra		draw_sprites_end

; --------------------------------------
draw_sprites_vertical_flipped:
; --------------------------------------
	add.l	#15*512*2,a4

	move	d2,d3
	lsr		#3,d2
	and		#$1e0,d2
	lea		(a3,d2.w),a5 ; Palette address.

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

	dbf		d7,draw_sprites_loop

	jra		draw_sprites_end

; --------------------------------------
draw_sprites_horizontal_flipped:
; --------------------------------------
	move	d2,d3
	lsr		#3,d2
	and		#$1e0,d2
	lea		(a3,d2.w),a5 ; Palette address.

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

	dbf		d7,draw_sprites_loop

draw_sprites_end:

	; Draw texts.
	
	lea		text_bitmaps,a0
	lea		L_00E00000,a1
	move.l	work_screen_address,a2
	add.l	#512*2*16+16*2,a2
	lea		converted_sprite_palettes,a3

	move	#32-1,d7

.text_lines_loop:
	move.l	(a0),d0
	jeq		.skip_text_line	

	move	#32-1,d6

.characters_loop:
	add.l	d0,d0
	jcc		.skip_character

	move	#8-1,d5

.lines_loop:
	move.l	a1,a4
	move.b	(a4),d1
	swap	d1

	add.l	#$20000,a4
	move.b	(a4),d1
	swap	d1

	add.l	#$20000,a4
	move.b	(a4),d2
	swap	d2

	add.l	#$20000,a4
	move.b	(a4),d2
	swap	d2

	move.l	a2,a4

	move	#8-1,d4

.pixels_loop:
	clr		d3

	swap	d2
	add.b	d2,d2
	addx	d3,d3
	swap	d2
	add.b	d2,d2
	addx	d3,d3
	swap	d1
	add.b	d1,d1
	addx	d3,d3
	swap	d1
	add.b	d1,d1
	addx	d3,d3
	jeq		.skip_pixel

	move	(a3,d3.w*2),(a4)

.skip_pixel:
	addq	#2,a4

	dbf		d4,.pixels_loop

	add.l	#128,a1
	add.l	#512*2,a2

	dbf		d5,.lines_loop

	sub.l	#128*8,a1
	sub.l	#512*2*8,a2

.skip_character:
	addq.l	#1,a1
	add.l	#8*2,a2

	dbf		d6,.characters_loop

	add.l	#128*8-32,a1
	add.l	#512*2*8-256*2,a2

	jra		.next_text_line

.skip_text_line:
	add.l	#128*8,a1
	add.l	#512*2*8,a2

.next_text_line:
	move.l	32*4(a0),(a0)+

	dbf		d7,.text_lines_loop	

	; Flip screen request.

    tst     machine_has_fast_ram
    jeq     .flip_screen

	move.l	work_screen_address,a0
	add.l	#512*2*16+16*2,a0
	move.l	allocated_display_buffer,a1

	move	#240-1,d7

.copy_loop:
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*2(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*3(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*4(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*5(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*6(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*7(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*8(a1)
	movem.l	(a0)+,d0-d6/a2-a6
	movem.l	d0-d6/a2-a6,12*4*9(a1)
	movem.l	(a0)+,d0-d6/a2
	movem.l	d0-d6/a2,12*4*10(a1)

	add.l	#256*2,a0
	add.l	#256*2,a1

	dbf		d7,.copy_loop

	movem.l	(sp)+,d0-a6

	rts

.flip_screen:
	move	sr,-(sp)

	move	#$2700,sr

	move.l	work_screen_address,d0
	move.l	show_screen_address,work_screen_address
	move.l	d0,show_screen_address

	move	(sp)+,sr

	movem.l	(sp)+,d0-a6

	rts

	data

background_image:
	incbin "surface.dat"
	incbin "surface.dat",256*2*240

	bss

text_bitmaps:
	ds.l	32*2

	text

; ------------------------------------------------------------------------------

compile_sprite:
	rts

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

show_screen_address:
	ds.l	1

work_screen_address:
	ds.l	1

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------

