
; Amiga renderer interface.
;
; Headless for now: it provides the hooks the game core calls on the ports
; (sprite list, sprite and character compilation, text layer bookkeeping)
; and counts the sprites of each frame for the measurements. The RTG and AGA
; outputs are added in later phases.

	xdef prepare_sprite_infos
	xdef compile_sprite
	xdef compile_characters

	xdef text_bitmaps
	xdef text_matrix
	xdef frame_sprite_count
	xdef sprite_palette_usage

MAXIMUM_PATTERNS=2048

	xref SPRITE_DATA_TABLE
	xref CURRENT_SPRITE_DATA_ENTRY

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Called from XSP_OUT once the game has built its sprite list (8 bytes per
; sprite: x, y, pattern, attributes). Returns d0 = 0 like the Falcon version.

prepare_sprite_infos:
	move.l	CURRENT_SPRITE_DATA_ENTRY,d0
	sub.l	#SPRITE_DATA_TABLE,d0
	lsr.l	#3,d0
	move	d0,frame_sprite_count

	; Record which palettes each pattern is drawn with (for the colour
	; analysis): attributes bits 11-8 = palette.

	movem.l	d1-d3/a0-a1,-(sp)

	lea		SPRITE_DATA_TABLE,a0
	lea		sprite_palette_usage,a1
	subq	#1,d0
	bmi		.usage_done

.usage_loop:
	move	4(a0),d1 ; Pattern.
	cmp		#MAXIMUM_PATTERNS,d1
	bcc		.next_sprite

	move	6(a0),d2 ; Attributes.
	lsr		#8,d2
	and		#$f,d2
	move	(a1,d1.w*2),d3
	bset	d2,d3
	move	d3,(a1,d1.w*2)

.next_sprite:
	addq.l	#8,a0

	dbf		d0,.usage_loop

.usage_done:
	movem.l	(sp)+,d1-d3/a0-a1

	move.l	#SPRITE_DATA_TABLE,CURRENT_SPRITE_DATA_ENTRY

	moveq	#0,d0

	rts

; d0.l = address of a 16x16 sprite pattern (called while sprites load).

compile_sprite:
	rts

compile_characters:
	rts

	xdef end_of_code

end_of_code: ; graphics.s is linked last: end of the code hunk.

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

frame_sprite_count:
	ds.w	1

	even

; Per pattern: palettes it was drawn with (word, bit n = palette n).

sprite_palette_usage:
	ds.w	MAXIMUM_PATTERNS

	even

text_bitmaps:
	ds.l	2*32 ; Text clear bitmap infos followed by text draw bitmap infos.

text_matrix:
	ds.b	32*32

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
