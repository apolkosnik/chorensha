
	xdef initialize_graphics
	xdef release_graphics
	xdef compile_sprite
	xdef sprite_engine
	xdef timer_b_handler

	xdef display_screen_address
	xdef work_screen_address
	xdef display_window_address
	xdef text_bitmaps

SCREEN_BUFFER_SIZE=(16+512+256+16)*256*2*2
SCREEN_DISPLAY_OFFSET=16*2+16*256*2*2
MAX_NUMBER_OF_SPRITES=1885
MAX_LINES_PER_SPRITE_DRAWING=170 ; 180

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

initialize_graphics:
	; Prepare to send all sprite masks to the DSP.

	btst	#1,$ffffa202.w
	jeq		*-6

	move.l	#MAX_NUMBER_OF_SPRITES,$ffffa204.w

	; Physbase.

	move	#2,-(sp)
	trap	#14
	addq.l	#2,sp

	move.l	d0,physbase

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

	add.l	#SCREEN_DISPLAY_OFFSET,d0
	move.l	d0,display_window_address

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

	; Load background graphics (wrapped part).
	
	clr		-(sp)
	pea		background_image_filename
	move	#61,-(sp)
	trap	#1
	addq.l	#8,sp

	move	d0,d7

	pea		background_image+256*2*512
	move.l	#256*2*256,-(sp)
	move	d7,-(sp)
	move	#63,-(sp)
	trap	#1
	lea		12(sp),sp

	move	d7,-(sp)
	move	#62,-(sp)
	trap	#1
	addq.l	#4,sp

	; Copy background graphics.

	lea		background_image,a0
	move.l	display_screen_address,a1
	add.l	#SCREEN_DISPLAY_OFFSET,a1
	move.l	work_screen_address,a2
	add.l	#SCREEN_DISPLAY_OFFSET,a2

	move	#512+256-1,d7

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

	move.l	display_screen_address,a0
	add.l	#SCREEN_DISPLAY_OFFSET,a0
	lea		background_image+SCREEN_DISPLAY_OFFSET,a1

	move	#512+256-1,d7

.copy_loop2:
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*2(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*3(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*4(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*5(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*6(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*7(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*8(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*9(a1)
	movem.l	(a0)+,d0-d6/a3-a6
	movem.l	d0-d6/a3-a6,11*4*10(a1)
	movem.l	(a0)+,d0-d6
	movem.l	d0-d6,11*4*11(a1)

	add.l	#256*2,a0
	add.l	#256*2*2,a1

	dbf		d7,.copy_loop2

	; Build color translation table.

	lea		color_translation_table,a0
	clr.l	d0

.color_translation_loop:
	bfextu	d0{16+5:5},d1
	bfextu	d0{16+0:5},d2
	bfextu	d0{16+10:5},d3

	clr		d4

	bfins	d1,d4{16+0:5}
	bfins	d2,d4{16+5:5}
	bfins	d3,d4{16+11:5}

	move	d4,(a0)+

	addq	#1,d0
	jne		.color_translation_loop

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

translate_palettes:
	movem.l	d0-a6,-(sp)

	lea		L_00E82000+$200,a0
	lea		color_translation_table,a1
	lea		translated_palettes,a2

	clr.l	d0

	move	#16*16/8-1,d7

.loop:
	rept 8

	move	(a0)+,d0
	move	(a1,d0.l*2),d1
	move	d1,(a2)+
	move	d1,(a2)+

	endr

	dbf		d7,.loop

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------
;
; a0.l = compiled sprites struct address.
;

; d0   #1
; d1   #2
; d2   #3
; d3   #4
; d4   #5
; d5   #6
; d6   #7
; d7   #8 
; a0   #9
; a1   #10
; a2   #11
; a3   #12
; a4   #13
; a5   palette_address / #14
; a6   screen_address
; sp   stack_pointer
; (sp) #15

convert_sprite_to_drawing_code:
	movem.l	d0-a6,-(sp)

	lea		sprite_matrix,a1
	move.l	free_compiled_objects_address,a2
	move.l	a2,(a0)
	lea		sprite_color_to_register_table,a0

	; Colors.

	lea		sprite_colors_count+2,a3 ; Start at index #1.
	clr		d0 ; Color index.
	clr		d1 ; Color register bitmap (for "movem.l", bit 0 = d0, ...).
	clr		d2 ; Gap offset.

	cmp		#15,sprite_color_count
	jne		.skip_color_fix1

	move	#$2f2d,(a2)+ ; "move.l x(a5),-(sp)".
	move	#15*4,(a2)+ ; "x".

.skip_color_fix1:
	move	#16-1-1,d7

.colors_loop:
	tst		(a3)+
	jeq		.process_gap

	tst		d2
	jeq		.count_colors

	cmp		#8,d2
	jle		.quick_add1

	move	#$4bed,(a2)+ ; "lea x(a5),a5".
	move	d2,(a2)+ ; "x".

	jra		.count_colors

.quick_add1:
	and		#$7,d2
	lsl		#8,d2
	add		d2,d2
	add		#$508d,d2 ; "addq.l #x,a5".
	move	d2,(a2)+

.count_colors:
	clr		d2

	move	2(a0,d0.w*2),d3
	cmp		#15,d3
	jeq		.skip_color_fix2

	bset	d3,d1

.skip_color_fix2:
	jra		.next_color

.process_gap:
	tst		d1
	jeq		.count_gaps

	move	#$4cdd,(a2)+ ; "movem.l (a5)+,rx-ry".
	move	d1,(a2)+ ; "rx-ry".

.count_gaps:
	clr		d1

	addq	#4,d2

.next_color:
	addq	#1,d0

	dbf		d7,.colors_loop

	tst		d1
	jeq		.no_final_colors

	move	#$4cdd,(a2)+ ; "movem.l (a5)+,rx-ry".
	move	d1,(a2)+ ; "rx-ry".

.no_final_colors:
	; Pixels.

	clr		d0 ; Gap offset.
	clr		d1

	move	#16-1,d7

.lines_loop2:
	move	#16-1,d6

.pixels_loop:
	move.b	(a1)+,d1
	jne		.process_pixel

	addq	#2,d0

	jra		.next_pixel

.process_pixel:
	tst		d0
	jeq		.draw_pixel

	cmp		#8,d0
	jle		.quick_add2

	move	#$4dee,(a2)+ ; "lea x(a6),a6".
	move	d0,(a2)+ ; "x".

	jra		.draw_pixel

.quick_add2:
	and		#$7,d0
	lsl		#8,d0
	add		d0,d0
	add		#$508e,d0 ; "addq.l #x,a6".
	move	d0,(a2)+

.draw_pixel:
	clr		d0

	move	(a0,d1.w*2),d2 ; "x".
	cmp		#15,d2
	jne		.skip_color_fix3

	move	#$3cd7,d2 ; "move.w (sp),(a6)+".
	cmp		-2(a2),d2 ; Is the last opcode also "move.w (sp),(a6)+"?
	jne		.set_draw_color_command

	move	#$2cd7,d2 ; "move.l (sp),(a6)+".
	subq.l	#2,a2

	jra		.set_draw_color_command

.skip_color_fix3:
	add		#$3cc0,d2 ; "move.w rx,(a6)+".

	cmp		-2(a2),d2 ; Is the last opcode also "move.w rx,(a6)+"?
	jne		.set_draw_color_command

	sub		#$1000,d2 ; Convert the current opcode to "move.l rx,(a6)+".
	subq.l	#2,a2

.set_draw_color_command:
	move	d2,(a2)+

.next_pixel:
	dbf		d6,.pixels_loop

	add		#(256*2-16)*2,d0

	dbf		d7,.lines_loop2

	cmp		#15,sprite_color_count
	jne		.skip_color_fix4

	move	#$588f,(a2)+ ; "addq.l #4,sp".

.skip_color_fix4:
	move	#$4e75,(a2)+ ; "rts".

	move.l	a2,free_compiled_objects_address

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------
;
; a0.l = compiled sprites struct address.

convert_sprite_to_restore_data:
	movem.l	d0-a6,-(sp)

	move.l	free_compiled_objects_address,a2
	move.l	a2,(a0)
	
	lea		sprite_matrix,a1
	
	clr		d0 ; Pixel offset.
	clr		d1 ; Jump offset.
	
	move	#16-1,d7

.lines_loop:
	move	#16-1,d6
	
.pixels_loop:
	tst.b	(a1)+
	jeq		.no_pixel
	
	tst		d1
	jne		.skip_pixel_offset
	
	move	d0,(a2)+
	clr		d0

.skip_pixel_offset:
	subq	#2,d1

	jra		.next_pixel
	
.no_pixel:
	tst		d1
	jeq		.skip_jump_offset
	
	move	d1,(a2)+
	clr		d1

.skip_jump_offset:
	addq	#2,d0

.next_pixel:
	dbf		d6,.pixels_loop
	
	tst		d1
	jeq		.skip_jump_offset2
	
	move	d1,(a2)+
	clr		d1

.skip_jump_offset2:
	add		#(512-16)*2,d0

	dbf		d7,.lines_loop

	move	#-1,(a2)+
	
	move.l	a2,free_compiled_objects_address
	
	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

build_and_send_sprite_mask_to_dsp:
	movem.l	d0-a6,-(sp)

	lea		sprite_matrix,a0
	lea		sprite_mask_bitmap,a1

	move	#16-1,d7

.loop:
	clr		d0

	move	#16-1,d6

.loop2:
	tst.b	(a0)+
	jeq		.no_pixel

	bset	d6,d0

.no_pixel:
	dbf		d6,.loop2

	move	d0,(a1)+

	dbf		d7,.loop

	; Send packed mask to DSP.

	lea		$ffffa204.w,a0
	lea		sprite_mask_bitmap,a1

	rept 5

	move.l	(a1)+,d0
	move	d0,d1
	lsr.l	#8,d0
	move.l	d0,(a0)
	swap	d1
	move	(a1)+,d1
	move.l	d1,(a0)

	endr

	move	(a1)+,d0
	lsl.l	#8,d0
	move.l	d0,(a0)

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------
;
; d0.l = original sprite data address.
;

compile_sprite:
	movem.l	d0-a6,-(sp)

	; Create sprite matrix and count colors.

	move.l	(sp),a0
	lea		sprite_matrix,a1
	lea		sprite_colors_count+16*2,a2
	clr.l	-(a2)
	clr.l	-(a2)
	clr.l	-(a2)
	clr.l	-(a2)
	clr.l	-(a2)
	clr.l	-(a2)
	clr.l	-(a2)
	clr.l	-(a2)

	move	#16-1,d7

.lines_loop1:
	move.l	(a0)+,d1
	bfextu	d1{0:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{4:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{8:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{12:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{16:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{20:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{24:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{28:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+

	move.l	16*4-4(a0),d1
	bfextu	d1{0:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{4:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{8:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{12:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{16:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{20:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{24:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+
	bfextu	d1{28:4},d2
	addq	#1,(a2,d2.w*2)
	move.b	d2,(a1)+

	dbf		d7,.lines_loop1

	; Send sprite mask to DSP.

	jsr		build_and_send_sprite_mask_to_dsp

	; Palette color counting.

	lea		sprite_colors_count+2,a0
	lea		sprite_color_to_register_table+2,a1
	clr		d0

	move	#16-1-1,d7

.count_loop:
	tst		(a0)+
	jeq		.color_not_used

	move	d0,(a1)
	addq	#1,d0

.color_not_used:
	addq.l	#2,a1

	dbf		d7,.count_loop

	move	d0,sprite_color_count

	; Create normal sprite.

	move.l	(sp),a0
	jsr		convert_sprite_to_drawing_code
	add.l	#16,a0
	jsr		convert_sprite_to_restore_data

	; Create horizontally flipped sprite.

	lea		sprite_matrix,a0

	move	#16-1,d7

.flip_loop1:
	lea		16(a0),a1

	rept 8

	move.b	(a0),d0
	move.b	-(a1),(a0)+
	move.b	d0,(a1)

	endr

	addq.l	#8,a0

	dbf		d7,.flip_loop1

	move.l	(sp),a0
	addq.l	#4,a0
	jsr		convert_sprite_to_drawing_code
	add.l	#16,a0
	jsr		convert_sprite_to_restore_data

	; Create horizontally and vertically flipped sprite.

	lea		sprite_matrix,a0
	lea		15*16(a0),a1

	move	#8-1,d7

.flip_loop2:
	rept 4

	move.l	(a0),d0
	move.l	(a1),(a0)+
	move.l	d0,(a1)+

	endr

	sub.l	#16*2,a1

	dbf		d7,.flip_loop2

	move.l	(sp),a0
	add.l	#12,a0
	jsr		convert_sprite_to_drawing_code
	add.l	#16,a0
	jsr		convert_sprite_to_restore_data

	; Create vertically flipped sprite.

	lea		sprite_matrix,a0

	move	#16-1,d7

.flip_loop3:
	lea		16(a0),a1

	rept 8

	move.b	(a0),d0
	move.b	-(a1),(a0)+
	move.b	d0,(a1)

	endr

	addq.l	#8,a0

	dbf		d7,.flip_loop3

	move.l	(sp),a0
	addq.l	#8,a0
	jsr		convert_sprite_to_drawing_code
	add.l	#16,a0
	jsr		convert_sprite_to_restore_data

	addq.l	#8,a0
	move	sprite_count,(a0)
	addq	#1,sprite_count

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

prepare_sprites:
	movem.l	d0-a6,-(sp)

	move.l	CURRENT_SPRITE_DATA_ENTRY,a0
	move.l	SPRITE_DATA_ADDRESS,a1

	move.l	work_screen_address,a2
	move	work_background_position,d0
	swap	d0
	clr		d0
	lsr.l	#6,d0
	add.l	d0,a2

	lea		translated_palettes,a3
	move.l	work_sprite_infos_address_new,a4
	move.l	a4,work_sprite_infos_address_next ; Fixme!
	lea		$ffffa204+2.w,a6

	move.l	a0,d7
	sub.l	#SPRITE_DATA_TABLE,d7
	jeq		.skip_all

	btst	#3,$ffffa202.w
	jeq		*-6

	bset	#3,$ffffa200.w

	lsr		#3,d7
	move.l	d7,$ffffa204.w ; Send number of sprite infos to be sent to the DSP.
	subq	#1,d7

.loop:
	subq.l	#8,a0
	movem	(a0),d0-d3

	move	d1,d5

	lea		(a2,d0.w*2),a5
	swap	d1
	clr		d1
	lsr.l	#6,d1
	add.l	d1,a5
	move.l	a5,(a4)+ ; Screen address.

	move	d3,d1
	lsr		#4,d1
	and		#$f0,d1
	lea		4(a3,d1.w*4),a5
	move.l	a5,(a4)+ ; Palette address.

	ext.l	d2
	lsl.l	#2+3+2,d2
	lea		(a1,d2.l),a5 ; Sprite data.

	move	d3,d1
	and		#$c000,d1
	or		32(a5),d1
	move	d1,(a6) ; Flip info + sprite ID -> DSP.
	move	d0,(a6) ; X position -> DSP.
	move	d5,(a6) ; Y position -> DSP.

	rol		#2,d3
	and		#$3,d3
	lea		(a5,d3.w*4),a5
	move.l	(a5),(a4)+ ; Sprite draw address.
	move.l	16(a5),(a4)+ ; Sprite restore address.

	dbf		d7,.loop

.skip_all:
	clr.l	(a4) ; End marker.

	move.l	#SPRITE_DATA_TABLE,CURRENT_SPRITE_DATA_ENTRY

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

restore_sprites:
	movem.l	d0-a6,-(sp)

	move.l	work_sprite_infos_address_old,a3
	lea		background_image,a4
	move.l	work_screen_address,d1
	
	jra		.start

.loop:
	addq.l	#8,a3
	move.l	(a3)+,a0
	
	move.l	d0,a2
	sub.l	d1,d0
	lea		(a4,d0.l),a1

	jra		.jump
	
.sprite_loop:
	add		d0,a1
	add		d0,a2
	
	move	(a0)+,d0
	jmp		.jump(pc,d0.w)

	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+
	move	(a1)+,(a2)+

.jump:
	move	(a0)+,d0
	jpl		.sprite_loop
	
.start:
	move.l	(a3)+,d0
	jne		.loop

	move.l	work_sprite_infos_address_old,a0	
	clr.l	(a0)
	
	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

restore_sprites_dsp:
	movem.l	d0-a6,-(sp)

	move.l	work_sprite_infos_address_new,a0	
	tst.l	(a0)
	jeq		.skip

	btst	#3,$ffffa202.w
	jne		*-6

	bclr	#3,$ffffa200.w
	
	lea		$ffffa204.w,a0
	lea		$ffffa204+2.w,a1
	lea		background_image+16*256*2*2,a2
	move.l	work_screen_address,a3
	add.l	#16*256*2*2,a3

	jra		.start

	rept 16+256+16

	move	(a2)+,(a3)+

	endr

.start:
	move.l	(a0),d0
	add.l	d0,a2
	add.l	d0,a3

	move	(a1),d1

	jmp		.start(pc,d1.w)

.skip:
	move.l	work_sprite_infos_address_new,a0	
	clr.l	(a0)
	
	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

draw_sprites:
	movem.l	d0-a6,-(sp)

;	clr.b	$fffffa1b.w
	move.b	#MAX_LINES_PER_SPRITE_DRAWING,$fffffa21.w
	move.b	#8,$fffffa1b.w

;	move.l	work_sprite_infos_address_new,a0
	move.l	work_sprite_infos_address_next,a0

	jra		.start

.loop:
	move.l	d0,a6
	move.l	(a0)+,a5
	move.l	(a0)+,a1

	pea		4(a0)

	jsr		(a1)

	move.l	(sp)+,a0

.start:
;	tst		delay_drawing_sprites
;	jne		.delay

	move.l	(a0)+,d0
	jne		.loop

	clr		still_drawing_sprites

;	move.l	work_sprite_infos_address_old,d0 ; Fixme!
;	move.l	work_sprite_infos_address_new,work_sprite_infos_address_old
;	move.l	d0,work_sprite_infos_address_new

	clr.b	$fffffa1b.w
	clr		delay_drawing_sprites

	movem.l	(sp)+,d0-a6

	rts

.delay:
	move.l	a0,work_sprite_infos_address_next
	move	#-1,still_drawing_sprites

	clr.b	$fffffa1b.w
	clr		delay_drawing_sprites

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

draw_sprites_dsp:
	movem.l	d0-a6,-(sp)

	move.l	work_sprite_infos_address_new,a0
	move.l	physbase,a1
	lea		8(a1),a1

	tst.l	(a0)
	jeq		.skip

	btst	#0,$ffffa202.w
	jeq		*-6

	lea		$ffffa204+2.w,a0
	move.l	#24,d0

	move	#200-1,d7

.lines_loop:
	rept (16+256+16)/8/3/2

	move	(a0),(a1)
	move	(a0),8(a1)
	move	(a0),16(a1)
	add.l	d0,a1

	endr

	lea		(320-(16+256+16))/2(a1),a1

	dbf		d7,.lines_loop

.skip:
	move.l	work_sprite_infos_address_old,d0
	move.l	work_sprite_infos_address_new,work_sprite_infos_address_old
	move.l	d0,work_sprite_infos_address_new

	movem.l	(sp)+,d0-a6

	rts

; ------------------------------------------------------------------------------

update_background:
	movem.l	d0-d1,-(sp)

	move	#512-1,d0
	move	BACKGROUND_SCROLL_COUNTER,d1
	and		#$1ff,d1
	sub		d1,d0
	clr		d0 ; Fixme!
	move	d0,work_background_position

	movem.l	(sp)+,d0-d1

	rts

; ------------------------------------------------------------------------------

flip_screen:
	movem.l	d0-d1,-(sp)

;	move.l	work_screen_address,d0 ; Fixme!
;	move.l	display_screen_address,work_screen_address
;	move.l	d0,display_screen_address

	move	work_background_position,d0
	move	display_background_position,work_background_position
	move	d0,display_background_position

;	move.l	work_sprite_infos_address_old,d0 ; Fixme!
;	move.l	display_sprite_infos_address_old,work_sprite_infos_address_old
;	move.l	d0,display_sprite_infos_address_old

;	move.l	work_sprite_infos_address_new,d0 ; Fixme!
;	move.l	display_sprite_infos_address_new,work_sprite_infos_address_new
;	move.l	d0,display_sprite_infos_address_new

	move	display_background_position,d0

	ifd __HATARI__

	move.l	work_screen_address,d1

	else

	move.l	display_screen_address,d1

	endif

	move.l	work_screen_address,d1 ; Fixme!

	add.l	#SCREEN_DISPLAY_OFFSET,d1
	swap	d0
	clr		d0
	lsr.l	#6,d0
	add.l	d0,d1
	move.l	d1,display_window_address

	movem.l	(sp)+,d0-d1

	rts

; ------------------------------------------------------------------------------

	rem

	jsr		prepare_sprites
	jsr		update_background
	jsr		translate_palettes
;	jsr		restore_sprites
	jsr		draw_sprites
;	jsr		draw_sprites_dsp ; Fixme!
	jsr		restore_sprites_dsp ; Fixme!
	jsr		flip_screen

	erem

sprite_engine:
	tst		still_drawing_sprites
	jne		.skip
	
;	clr.b	$fffffa1b.w
	move.b	#MAX_LINES_PER_SPRITE_DRAWING,$fffffa21.w
	move.b	#8,$fffffa1b.w

	jsr		prepare_sprites
	jsr		update_background
	jsr		translate_palettes
	
.skip:
	jsr		draw_sprites

	tst		still_drawing_sprites
	jne		.skip2
	
	jsr		restore_sprites_dsp
	jsr		flip_screen
	
.skip2:
	rts

; ------------------------------------------------------------------------------

reset_sprite_drawing_timer:
;	clr.b	$fffffa1b.w
;	move.b	#MAX_LINES_PER_SPRITE_DRAWING,$fffffa21.w
;	move.b	#8,$fffffa1b.w

	rts

; ------------------------------------------------------------------------------

timer_b_handler:
	move	#-1,delay_drawing_sprites

	clr.b	$fffffa1b.w

	rte

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

background_image_filename:
	dc.b	'ETC_DAT\BACKGND.DAT',0

	even

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

display_sprite_infos_address_new:
	dc.l	sprite_infos1

display_sprite_infos_address_old:
	dc.l	sprite_infos2

work_sprite_infos_address_new:
	dc.l	sprite_infos3

work_sprite_infos_address_old:
	dc.l	sprite_infos4

free_compiled_objects_address:
	dc.l	compiled_objects

work_sprite_infos_address_next:
	dc.l	sprite_infos3

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

physbase:
	ds.l	1

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

delay_drawing_sprites:
	ds		1

still_drawing_sprites:
	ds		1

sprite_infos1: ; screen_address, palette_address, sprite_draw_address, sprite_restore_address.
	ds.l	4*512

sprite_infos2: ; screen_address, palette_address, sprite_draw_address, sprite_restore_address.
	ds.l	4*512

sprite_infos3: ; screen_address, palette_address, sprite_draw_address, sprite_restore_address.
	ds.l	4*512

sprite_infos4: ; screen_address, palette_address, sprite_draw_address, sprite_restore_address.
	ds.l	4*512

text_bitmaps:
	ds.l	32*2

background_image:
	ds.b	SCREEN_BUFFER_SIZE

color_translation_table:
	ds		$10000

translated_palettes:
	ds.l	16*16

compiled_objects:
	ds.b	$300000

sprite_color_count:
	ds		1

sprite_colors_count:
	ds		16

sprite_color_to_register_table:
	ds		16

sprite_matrix:
	ds.b	16*16

sprite_mask_bitmap:
	ds		16

sprite_count:
	ds		1

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------

