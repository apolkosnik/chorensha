
	xdef initialize_graphics
	xdef release_graphics
	xdef compile_sprite
	xdef prepare_sprites
	xdef draw_sprites

	xdef display_graphics_address
	xdef work_graphics_address
	xdef text_bitmaps

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

initialize_graphics:
	; Allocate graphics buffer (16 bytes boundary, ST-RAM only).

	move	#0,-(sp)
	move.l	#(16+512+16)*256*2*2*2+16,-(sp)
	move	#68,-(sp)
	trap	#1
	addq.l	#8,sp

	move.l	d0,allocated_graphics_buffer_address

	add.l	#15,d0
	and.l	#$fffffff0,d0

	cmp.l	#-1,machine_supervidel
	jeq		.no_supervidel

	add.l	#$a0000000,d0

.no_supervidel:
	move.l	d0,a0
	move.l	a0,a1
	add.l	#(16+512+16)*256*2*2*2,a1

.clear_loop:
	clr.l	(a0)+	
	clr.l	(a0)+	
	clr.l	(a0)+	
	clr.l	(a0)+	

	cmp.l	a1,a0
	jne		.clear_loop

	move.l	d0,display_graphics_address
	add.l	#(16+512+16)*256*2*2,d0
	move.l	d0,work_graphics_address

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

	; Test

	lea		background_image,a0
	move.l	display_graphics_address,a1

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
	add.l	#256*2*2,a1

	dbf		d7,.copy_loop

	rts

; ------------------------------------------------------------------------------

release_graphics:
	; Free allocated graphics buffer.

	move.l	allocated_graphics_buffer_address,-(sp)
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
	data
; ------------------------------------------------------------------------------

background_image_filename:
	dc.b	'ETC_DAT\BACKGND.DAT',0

	even

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

allocated_graphics_buffer_address:
	ds.l	1

display_graphics_address:
	ds.l	1

work_graphics_address:
	ds.l	1

text_bitmaps:
	ds.l	32*2

background_image:
	ds.b	256*2*512

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------

