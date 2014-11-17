
	xdef initialize_graphics
	xdef release_graphics
	xdef compile_sprite
	xdef prepare_sprites
	xdef draw_sprites
	xdef update_background
	xdef flip_screen

	xdef display_screen_address
	xdef work_screen_address
	xdef display_window_address
	xdef text_bitmaps

SCREEN_BUFFER_SIZE=(16+512+256+16)*256*2*2
SCREEN_DISPLAY_OFFSET=16*2+16*256*2*2

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

initialize_graphics:
	; Allocate screen buffers (16 bytes boundary, ST-RAM only).

	move	#0,-(sp)
	move.l	#SCREEN_BUFFER_SIZE*2+16,-(sp)
	move	#68,-(sp)
	trap	#1
	addq.l	#8,sp

	move.l	d0,allocated_screen_address

	add.l	#15,d0
	and.l	#$fffffff0,d0

	cmp.l	#-1,machine_supervidel
	jeq		.no_supervidel

	add.l	#$a0000000,d0

.no_supervidel:
	move.l	d0,display_screen_address
	add.l	#SCREEN_BUFFER_SIZE,d0
	move.l	d0,work_screen_address

	; Load background graphics.

	clr		-(sp)
	pea		background_image_filename
	move	#61,-(sp)
	trap	#1
	addq.l	#8,sp

	move	d0,d7

	pea		background_image
	move.l	#256*2*512,-(sp)
	move	d7,-(sp)
	move	#63,-(sp)
	trap	#1
	lea		12(sp),sp

	move	d7,-(sp)
	move	#62,-(sp)
	trap	#1
	addq.l	#4,sp

	; Set background graphics.

	lea		background_image,a0
	move.l	display_screen_address,a1
	add.l	#SCREEN_DISPLAY_OFFSET,a1
	move.l	work_screen_address,a2
	add.l	#SCREEN_DISPLAY_OFFSET,a2

	move	#512-1,d7

.copy_loop1:
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,(a1)
	movem.l	d0-d6/a3-a6,(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4(a1)
	movem.l	d0-d6/a3-a6,11*4(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*2(a1)
	movem.l	d0-d6/a3-a6,11*4*2(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*3(a1)
	movem.l	d0-d6/a3-a6,11*4*3(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*4(a1)
	movem.l	d0-d6/a3-a6,11*4*4(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*5(a1)
	movem.l	d0-d6/a3-a6,11*4*5(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*6(a1)
	movem.l	d0-d6/a3-a6,11*4*6(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*7(a1)
	movem.l	d0-d6/a3-a6,11*4*7(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*8(a1)
	movem.l	d0-d6/a3-a6,11*4*8(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*9(a1)
	movem.l	d0-d6/a3-a6,11*4*9(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*10(a1)
	movem.l	d0-d6/a3-a6,11*4*10(a2)
	movem.l	(a0)+,d0-d6
	movem.l	d0-d6,11*4*11(a1)
	movem.l	d0-d6,11*4*11(a2)

	add.l	#256*2*2,a1
	add.l	#256*2*2,a2

	dbf		d7,.copy_loop1

	lea		background_image,a0

	move	#256-1,d7

.copy_loop2:
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,(a1)
	movem.l	d0-d6/a3-a6,(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4(a1)
	movem.l	d0-d6/a3-a6,11*4(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*2(a1)
	movem.l	d0-d6/a3-a6,11*4*2(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*3(a1)
	movem.l	d0-d6/a3-a6,11*4*3(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*4(a1)
	movem.l	d0-d6/a3-a6,11*4*4(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*5(a1)
	movem.l	d0-d6/a3-a6,11*4*5(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*6(a1)
	movem.l	d0-d6/a3-a6,11*4*6(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*7(a1)
	movem.l	d0-d6/a3-a6,11*4*7(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*8(a1)
	movem.l	d0-d6/a3-a6,11*4*8(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*9(a1)
	movem.l	d0-d6/a3-a6,11*4*9(a2)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*10(a1)
	movem.l	d0-d6/a3-a6,11*4*10(a2)
	movem.l	(a0)+,d0-d6
	movem.l	d0-d6,11*4*11(a1)
	movem.l	d0-d6,11*4*11(a2)

	add.l	#256*2*2,a1
	add.l	#256*2*2,a2

	dbf		d7,.copy_loop2

	rts

; ------------------------------------------------------------------------------

release_graphics:
	; Free allocated graphics buffer.

	move.l	allocated_screen_address,-(sp)
	move	#73,-(sp)
	trap	#1
	addq.l	#6,sp

	rts

; ------------------------------------------------------------------------------

compile_sprite:
	rts

; ------------------------------------------------------------------------------

prepare_sprites:
	rts

; ------------------------------------------------------------------------------

draw_sprites:
	rts

; ------------------------------------------------------------------------------

update_background:
	movem.l	d0-d1,-(sp)

	move	#512-1,d0
	move	BACKGROUND_SCROLL_COUNTER,d1
	and		#$1ff,d1
	sub		d1,d0
	move	d0,work_background_position

	movem.l	(sp)+,d0-d1

	rts

; ------------------------------------------------------------------------------

flip_screen:
	movem.l	d0-d1,-(sp)

	move.l	work_screen_address,d0
	move.l	display_screen_address,work_screen_address
	move.l	d0,display_screen_address

	move	work_background_position,d0
	move	display_background_position,work_background_position
	move	d0,display_background_position

	move.l	work_sprite_postitions_address,d0
	move.l	display_sprite_postitions_address,work_sprite_postitions_address
	move.l	d0,display_sprite_postitions_address

	move	display_background_position,d0
	move.l	display_screen_address,d1
	add.l	#SCREEN_DISPLAY_OFFSET,d1
	swap	d0
	clr		d0
	lsr.l	#6,d0
	add.l	d0,d1
	move.l	d1,display_window_address

	movem.l	(sp)+,d0-d1

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

background_image_filename:
	dc.b	'ETC_DAT\BACKGND.DAT',0

	even

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

display_sprite_postitions_address:
	dc.l	display_sprite_postitions

work_sprite_postitions_address:
	dc.l	work_sprite_postitions

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

allocated_screen_address:
	ds.l	1

display_screen_address:
	ds.l	1

work_screen_address:
	ds.l	1

display_window_address:
	ds.l	1

display_background_position:
	ds		1

work_background_position:
	ds		1

display_sprite_postitions:
	ds		512*2

work_sprite_postitions:
	ds		512*2

text_bitmaps:
	ds.l	32*2

background_image:
	ds.b	256*2*512

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------

