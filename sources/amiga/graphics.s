
; Amiga renderer: composes the X68000 screen into an 8-bit chunky buffer.
;
; Layers, back to front (X68000 default priorities; the game swaps text and
; sprites for its bomb flash through video controller register R1):
;
;   - GVRAM page 1 and page 0 (256-colour mode, each with its own scroll
;     registers; colour 0 is transparent),
;   - the text layer (4 bit planes, palette block 0) and the sprites (16x16,
;     4 bits per pixel, 16 palettes), in the order set by R1.
;
; Palette: the graphics palette and the sprite/text palette (2 x 256 X68000
; entries) are merged into one 256-entry palette of distinct colours whenever
; they change; remap tables translate the X68000 indices. All 512 entries of
; the game hold 117 distinct colours, so this is exact.
;
; The buffer layout (GUARD, RENDER_STRIDE) is repeated in display.s.
;
; The buffer has a 16-pixel guard band on every side, which is also the
; offset of the X68000 sprite coordinates: a sprite at (x, y) is drawn at
; buffer position (x, y).
;
; GVRAM is converted once into two 8-bit layers (the game builds it at start
; only; amiga_graphics_changed marks it). Every graphics index the layers use
; keeps its own hardware palette slot, so the layers are copied without
; remapping and palette fades need no rebuild; sprite and text colours share
; those slots when the colour matches and take free slots otherwise. Page 0
; is overlaid through per-line runs of opaque pixels.

	xdef prepare_sprite_infos
	xdef compile_sprite
	xdef compile_characters
	xdef render_frame
	xdef amiga_clear_text_planes
	xdef amiga_graphics_changed
	xdef amiga_text_row_written
	xdef initialize_renderer
	xdef release_renderer
	xdef compiled_sprite_count

	xdef render_buffer
	xdef hardware_palette
	xdef palette_load_table
	xdef palette_changed
	xdef palette_overflows

	xdef text_bitmaps
	xdef text_matrix
	xdef frame_sprite_count
	xdef sprite_palette_usage

	xref SPRITE_DATA_TABLE
	xref CURRENT_SPRITE_DATA_ENTRY
	xref SPRITE_DATA_ADDRESS
	xref L_00C00000
	xref L_00E00000
	xref L_00E80000
	xref L_00E82000
	xref exec_base

	ifd __RENDER_PROFILE__
	xref timer_base
	xdef render_profile
	xdef palette_rebuilds
	xdef text_lines_converted
	xdef text_lines_drawn
	xdef text_remaps
	xdef palette_entry_changes
	endif

MAXIMUM_PATTERNS=2048
PCG_PATTERNS=$75e
MAXIMUM_SPRITES=512

GUARD=16
RENDER_WIDTH=256
RENDER_HEIGHT=256
COLOUR_HASH_SIZE=1024 ; Colour -> slot table of full palette rebuilds.
TEXT_GROUP_BITS=8 ; text_draw line: a bit per group of four pixels,
TEXT_DRAW_LINE=TEXT_GROUP_BITS+RENDER_WIDTH/4*8 ; then (mask, colours) per group with text.
RENDER_STRIDE=GUARD+RENDER_WIDTH+GUARD
RENDER_LINES=GUARD+RENDER_HEIGHT+GUARD

GVRAM_PAGE_SIZE=$80000
GVRAM_LINE=1024
TEXT_PLANE_SIZE=$20000
TEXT_LINE=128

LAYER_WIDTH=256
LAYER_LINES=512
SPAN_BUFFER_SIZE=$10000

; COPY_RUN: copies d3.w bytes (1-256) from (a5)+ to (a1)+ through computed
; jumps into unrolled moves (unaligned longs are fine on 68020+). Uses d0.

COPY_RUN macro
	move	d3,d0
	lsr		#2,d0 ; Longs.
	neg		d0
	jmp		.longs_end\@(pc,d0.w*2)

	rept	LAYER_WIDTH/4
	move.l	(a5)+,(a1)+
	endr

.longs_end\@:
	moveq	#3,d0
	and		d3,d0
	neg		d0
	jmp		.bytes_end\@(pc,d0.w*2)

	move.b	(a5)+,(a1)+
	move.b	(a5)+,(a1)+
	move.b	(a5)+,(a1)+

.bytes_end\@:
	endm

; Compiled sprites: one routine per (pattern, flip), generated on first use
; into an arena. Entry: a6 = top left in the render buffer, a5 = remap block
; of the sprite's palette (16 bytes). Uses d0-d7. The pattern's eight most
; frequent colours are loaded into d0-d7, each opaque pixel is one
; "move.b dN,offset(a6)" or "move.b colour(a5),offset(a6)".

COMPILED_ARENA_SIZE=$100000
COMPILED_ARENA_MINIMUM=$40000
MAXIMUM_COMPILED_SIZE=8*4+256*6+2

OPCODE_LOAD_COLOUR=$102d ; move.b d16(a5),d0 (| register << 9)
OPCODE_STORE_REGISTER=$1d40 ; move.b d0,d16(a6) (| register)
OPCODE_STORE_MEMORY=$1d6d ; move.b d16(a5),d16(a6)
OPCODE_RTS=$4e75

_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOCacheClearU=-636

MEMF_ANY=0

; CRTC scroll registers (shadow): text X/Y, GR0 X/Y (page 0), GR2 X/Y (page 1).

CRTC_TEXT_X=$14
CRTC_TEXT_Y=$16
CRTC_PAGE0_X=$18
CRTC_PAGE0_Y=$1a
CRTC_PAGE1_X=$20
CRTC_PAGE1_Y=$22

; Video controller (shadow): palettes and R1 (layer priorities).

VC_GRAPHICS_PALETTE=$000
VC_SPRITE_PALETTE=$200
VC_PRIORITY=$500

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Called from XSP_OUT once the game has built its sprite list (8 bytes per
; sprite: x, y, pattern, attributes). Takes a copy for the renderer and
; returns d0 = 0 like the Falcon version.

prepare_sprite_infos:
	move.l	CURRENT_SPRITE_DATA_ENTRY,d0
	sub.l	#SPRITE_DATA_TABLE,d0
	lsr.l	#3,d0
	cmp		#MAXIMUM_SPRITES,d0
	bls		.count_ok

	move	#MAXIMUM_SPRITES,d0

.count_ok:
	move	d0,frame_sprite_count
	move	d0,render_sprite_count

	movem.l	d1-d3/a0-a2,-(sp)

	lea		SPRITE_DATA_TABLE,a0
	lea		sprite_list,a2
	lea		sprite_palette_usage,a1
	subq	#1,d0
	bmi		.copy_done

.copy_loop:
	move.l	(a0),(a2)+
	move.l	4(a0),(a2)+

	; Record which palettes each pattern is drawn with (colour analysis).

	move	4(a0),d1 ; Pattern.
	cmp		#MAXIMUM_PATTERNS,d1
	bcc		.next_sprite

	move	6(a0),d2 ; Attributes: bits 11-8 = palette.
	lsr		#8,d2
	and		#$f,d2
	move	(a1,d1.w*2),d3
	bset	d2,d3
	move	d3,(a1,d1.w*2)

.next_sprite:
	addq.l	#8,a0

	dbf		d0,.copy_loop

.copy_done:
	movem.l	(sp)+,d1-d3/a0-a2

	move.l	#SPRITE_DATA_TABLE,CURRENT_SPRITE_DATA_ENTRY

	moveq	#0,d0

	rts

; d0.l = address of a 16x16 sprite pattern (called while sprites load): the
; pattern data changes, so the compiled sprites are discarded.

compile_sprite:
	st		sprite_cache_reset

	rts

compile_characters:
	rts

; ------------------------------------------------------------------------------
;
; CLEAR_TEXT_PLANE on the Amiga: clears all four text planes (4 x 128 KB).
; Preserves all registers.

amiga_clear_text_planes:
	movem.l	d0-d7/a0-a6,-(sp)

	lea		L_00E00000+TEXT_PLANE_SIZE*4,a6
	moveq	#0,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#0,d4
	moveq	#0,d5
	moveq	#0,d6
	moveq	#0,d7
	move.l	d1,a0
	move.l	d1,a1
	move.l	d1,a2
	move.l	d1,a3
	move.l	d1,a4
	move.l	d1,a5
	move	#TEXT_PLANE_SIZE*4/(13*4*8)-1,d0

.clear:
	rept	8
	movem.l	d1-d7/a0-a5,-(a6) ; 13 longs.
	endr

	dbf		d0,.clear

	; Remainder (the plane size is not a multiple of 13 * 4 * 8).

	move	#(TEXT_PLANE_SIZE*4-(TEXT_PLANE_SIZE*4/(13*4*8))*(13*4*8))/4-1,d0

.remainder:
	move.l	d1,-(a6)
	dbf		d0,.remainder

	lea		text_dirty_rows,a0
	moveq	#-1,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; DRAW_CHARACTER on the Amiga: d0.w = text row (0-127, 8 pixel lines each)
; that has changed. Preserves all registers.

amiga_text_row_written:
	movem.l	d0-d1/a0,-(sp)

	and		#127,d0
	move	d0,d1
	lsr		#3,d1
	lea		text_dirty_rows,a0
	bset	d0,(a0,d1.w) ; Bit number modulo 8.

	movem.l	(sp)+,d0-d1/a0

	rts

; ------------------------------------------------------------------------------
;
; Called after the game has (re)built GVRAM: the layers are converted on the
; next frame. Preserves all registers.

amiga_graphics_changed:
	st		layers_dirty

	rts

; ------------------------------------------------------------------------------
;
; Allocates the compiled sprite arena (1 MB, else 256 KB, else none: sprites
; are then drawn by the generic routine). Task context.

initialize_renderer:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	move.l	exec_base,a6
	move.l	#COMPILED_ARENA_SIZE,d0
	move.l	d0,arena_size
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,arena
	bne		.allocated

	move.l	#COMPILED_ARENA_MINIMUM,d0
	move.l	d0,arena_size
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,arena

.allocated:
	st		sprite_cache_reset

	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

release_renderer:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	move.l	arena,d0
	beq		.done

	clr.l	arena
	move.l	d0,a1
	move.l	arena_size,d0
	move.l	exec_base,a6
	jsr		_LVOFreeMem(a6)

.done:
	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

; ------------------------------------------------------------------------------
;
; Renders the current X68000 screen into render_buffer (task context).

; Profiling build (-D__RENDER_PROFILE__): E clock ticks per stage are summed
; in render_profile (palette, graphics, text, sprites; emulator.s adds the
; display upload) and printed at exit by main.s.

PROFILE macro
	ifd __RENDER_PROFILE__
	move.l	#\1,profile_stage
	bsr		profile_mark
	endif
	endm

render_frame:
	movem.l	d0-d7/a0-a6,-(sp)

	PROFILE	-1

	tst.b	layers_dirty
	beq		.layers_ok

	bsr		build_layers

.layers_ok:
	bsr		update_palette
	PROFILE	0
	ifnd __NO_GRAPHICS__
	bsr		render_graphics
	endif
	PROFILE	1

	; R1 bits 13-12 = sprite priority, 11-10 = text priority (0 = front).

	move	L_00E82000+VC_PRIORITY,d0
	move	d0,d1
	lsr		#8,d0
	lsr		#4,d0
	and		#3,d0 ; Sprites.
	lsr		#8,d1
	lsr		#2,d1
	and		#3,d1 ; Text.
	cmp		d1,d0
	bhi		.text_in_front

	ifnd __NO_TEXT__
	bsr		render_text
	endif
	PROFILE	2
	ifnd __NO_SPRITES__
	bsr		render_sprites
	endif
	PROFILE	3

	bra		.done

.text_in_front:
	ifnd __NO_SPRITES__
	bsr		render_sprites
	endif
	PROFILE	3
	ifnd __NO_TEXT__
	bsr		render_text
	endif
	PROFILE	2

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; Converts GVRAM pages 0 and 1 into layer0 / layer1 (graphics palette
; indices), records the indices used, and builds the runs of page 0: per
; line a list of opaque runs and then a list of transparent runs, each of
; (start, length) words ended by start = -1, or no lists (span_lines entry 0)
; if the run buffer is full.

build_layers:
	sf		layers_dirty

	lea		used_graphics,a0
	moveq	#256/4-1,d0

.clear_used:
	clr.l	(a0)+
	dbf		d0,.clear_used

	lea		used_graphics,a3
	lea		L_00C00000,a0
	lea		layer0,a1
	moveq	#0,d0
	moveq	#2-1,d4 ; Pages.

.page_loop:
	move	#LAYER_LINES-1,d3

.line_loop:
	move	#LAYER_WIDTH-1,d2
	move.l	a0,a2

.pixel_loop:
	move.b	1(a2),d0
	addq.l	#2,a2
	move.b	d0,(a1)+
	st		(a3,d0.w)

	dbf		d2,.pixel_loop

	lea		GVRAM_LINE(a0),a0

	dbf		d3,.line_loop

	; Next page: GVRAM page 1 follows page 0 (512 lines of 1024 bytes).

	dbf		d4,.page_loop

	clr.b	used_graphics ; Index 0 is transparent.

	; Runs of page 0.

	lea		layer0,a0
	lea		span_lines,a1
	lea		span_buffer,a2
	lea		span_buffer+SPAN_BUFFER_SIZE-(LAYER_WIDTH+2)*4,a5 ; Room for a full line.
	move	#LAYER_LINES-1,d3

.span_line_loop:
	cmp.l	a5,a2
	bls		.room

	clr.l	(a1)+ ; Buffer full: this line is overlaid pixel by pixel.
	lea		LAYER_WIDTH(a0),a0

	bra		.next_span_line

.room:
	move.l	a2,(a1)+
	moveq	#0,d2 ; x

.find_start:
	cmp		#LAYER_WIDTH,d2
	beq		.line_done

	tst.b	(a0,d2.w)
	bne		.run_start

	addq	#1,d2

	bra		.find_start

.run_start:
	move	d2,d1 ; Start.

.find_end:
	addq	#1,d2
	cmp		#LAYER_WIDTH,d2
	beq		.run_end

	tst.b	(a0,d2.w)
	bne		.find_end

.run_end:
	move	d1,(a2)+
	move	d2,d0
	sub		d1,d0
	move	d0,(a2)+ ; Length.

	bra		.find_start

.line_done:
	move	#-1,(a2)+
	clr		(a2)+

	; Followed by the gaps (transparent runs), where page 1 shows.

	moveq	#0,d2

.find_gap:
	cmp		#LAYER_WIDTH,d2
	beq		.gaps_done

	tst.b	(a0,d2.w)
	beq		.gap_start

	addq	#1,d2

	bra		.find_gap

.gap_start:
	move	d2,d1

.find_gap_end:
	addq	#1,d2
	cmp		#LAYER_WIDTH,d2
	beq		.gap_end

	tst.b	(a0,d2.w)
	beq		.find_gap_end

.gap_end:
	move	d1,(a2)+
	move	d2,d0
	sub		d1,d0
	move	d0,(a2)+

	bra		.find_gap

.gaps_done:
	move	#-1,(a2)+
	clr		(a2)+
	lea		LAYER_WIDTH(a0),a0

.next_span_line:
	dbf		d3,.span_line_loop

	st		layers_ready
	st		palette_rebuild ; New set of used graphics indices.

	rts

; ------------------------------------------------------------------------------
;
; Builds hardware_palette (LoadRGB32 format) and the remap tables when the
; X68000 palettes change. Slot 0 is the backdrop (sprite/text palette entry
; 0; graphics index 0 is transparent, so empty layer pixels show it). Every
; graphics index in use keeps its own slot. Sprite and text entries share a
; slot with an identical colour (15 RGB bits; the intensity bit is ignored)
; or take a free slot, or the nearest colour if none is left.

update_palette:
	ifd __FULL_PALETTE__
	st		palette_rebuild ; Test builds: a full rebuild for every frame.
	endif

	lea		L_00E82000,a0
	lea		palette_copy,a1
	move	#512/2-1,d0

.compare:
	cmp.l	(a0)+,(a1)+
	dbne	d0,.compare

	bne		.changed

	tst.b	palette_rebuild
	beq		.done

	bra		.full

.changed:
	tst.b	palette_rebuild
	bne		.full

	bsr		update_palette_entries
	tst.l	d0
	beq		.done ; Updated incrementally.

.full:
	sf		palette_rebuild

	ifd __RENDER_PROFILE__

	; Which entries changed (histogram of entry numbers, for profiling).

	lea		L_00E82000,a0
	lea		palette_copy,a1
	lea		palette_entry_changes,a2
	move	#512-1,d0

.count_changes:
	move	(a0)+,d1
	cmp		(a1)+,d1
	beq		.same_entry

	move	#512-1,d1
	sub		d0,d1
	addq	#1,(a2,d1.w*2)

.same_entry:
	dbf		d0,.count_changes

	endif

	lea		L_00E82000,a0
	lea		palette_copy,a1
	move	#512/2-1,d0

.copy:
	move.l	(a0)+,(a1)+
	dbf		d0,.copy

	; Empty colour -> slot table.

	lea		colour_hash_keys,a0
	move	#COLOUR_HASH_SIZE/2-1,d0

.clear_hash:
	clr.l	(a0)+
	dbf		d0,.clear_hash

	lea		slot_taken,a0
	moveq	#256/4-1,d0

.clear_taken:
	clr.l	(a0)+
	dbf		d0,.clear_taken

	lea		colour_hash_keys,a2
	lea		colour_hash_slots,a3
	lea		slot_taken,a4
	moveq	#0,d0 ; The colour key indexes tables: keep the upper word clear.

	lea		slot_references,a0
	move	#256/2-1,d0

.clear_references:
	clr.l	(a0)+
	dbf		d0,.clear_references

	moveq	#0,d0

	; Slot 0: backdrop.

	move	palette_copy+512,d0
	lsr		#1,d0
	moveq	#0,d6
	bsr		.set_slot

	; Graphics indices in use: their own slots.

	lea		palette_copy,a0
	lea		used_graphics,a1
	moveq	#1,d6

.graphics_loop:
	tst.b	(a1,d6.w)
	beq		.next_graphics

	move	(a0,d6.w*2),d0
	lsr		#1,d0
	bsr		.set_slot

.next_graphics:
	addq	#1,d6
	cmp		#256,d6
	bne		.graphics_loop

	; Sprite and text entries.

	lea		palette_copy+512,a0
	lea		sprite_remap,a1
	clr.b	(a1)+ ; Entry 0: transparent.
	moveq	#1,d7 ; Entry.
	moveq	#1,d6 ; Next slot to try.

.sprite_loop:
	move	(a0,d7.w*2),d0
	lsr		#1,d0

	bsr		.hash_find
	tst		(a2,d2.w*2)
	beq		.find_free

	move.b	(a3,d2.w),d1
	move.b	d1,(a1)+
	and		#$ff,d1
	lea		slot_references,a5
	addq	#1,(a5,d1.w*2)

	bra		.next_sprite_entry

.find_free:
	cmp		#256,d6
	beq		.nearest

	tst.b	(a4,d6.w)
	beq		.free_found

	addq	#1,d6

	bra		.find_free

.free_found:
	bsr		.set_slot
	move.b	d6,(a1)+
	lea		slot_references,a5
	addq	#1,(a5,d6.w*2)
	addq	#1,d6

	bra		.next_sprite_entry

.nearest:
	addq.l	#1,palette_overflows
	bsr		.nearest_slot
	move.b	d1,(a1)+
	and		#$ff,d1
	lea		slot_references,a5
	addq	#1,(a5,d1.w*2)

.next_sprite_entry:
	addq	#1,d7
	cmp		#256,d7
	bne		.sprite_loop

	; Graphics remap: identity (used for the per-pixel fallback).

	lea		graphics_remap,a0
	moveq	#0,d0

.identity:
	move.b	d0,(a0)+
	addq.b	#1,d0
	bne		.identity

	move.l	#256<<16,hardware_palette ; 256 colours from slot 0.
	clr.l	hardware_palette+4+256*3*4
	move.l	#hardware_palette,palette_load_table

	st		palette_changed

	ifd __RENDER_PROFILE__
	addq.l	#1,palette_rebuilds
	endif

.done:
	rts

; d0 = colour key, d6 = slot: claims the slot, sets its colour and registers
; the colour (the first slot of a colour is the one found later).

.set_slot:
	st		(a4,d6.w)

	bsr		.hash_find
	tst		(a2,d2.w*2)
	bne		.registered

	move	d0,d1
	addq	#1,d1
	move	d1,(a2,d2.w*2)
	move.b	d6,(a3,d2.w)

.registered:
	lea		hardware_palette+4,a5
	move	d6,d1
	mulu	#12,d1
	add.l	d1,a5

	move	d0,d1
	lsr		#5,d1
	and		#$1f,d1 ; R
	bsr		.expand
	move.l	d2,(a5)+

	move	d0,d1
	lsr		#8,d1
	lsr		#2,d1
	and		#$1f,d1 ; G
	bsr		.expand
	move.l	d2,(a5)+

	move	d0,d1
	and		#$1f,d1 ; B
	bsr		.expand
	move.l	d2,(a5)

	rts

; d0 = colour key -> d2 = its entry in the colour hash (keys + 1 in
; colour_hash_keys, 0 = empty; slots in colour_hash_slots), or the empty
; entry where it belongs. Uses d1. Linear probing; the table has room for
; every colour of the 512 palette entries.

.hash_find:
	move	d0,d1
	addq	#1,d1
	move	d0,d2
	mulu	#40503,d2
	swap	d2
	and		#COLOUR_HASH_SIZE-1,d2

.probe:
	cmp		(a2,d2.w*2),d1
	beq		.hash_done

	tst		(a2,d2.w*2)
	beq		.hash_done

	addq	#1,d2
	and		#COLOUR_HASH_SIZE-1,d2

	bra		.probe

.hash_done:
	rts

; d1 = 5-bit component -> d2 = 8 bits replicated into 32 bits.

.expand:
	move	d1,d2
	lsl		#3,d2
	lsr		#2,d1
	or		d1,d2 ; 8 bits.
	move.b	d2,d1
	lsl		#8,d2
	move.b	d2,d1
	move	d2,d1
	swap	d2
	move	d1,d2

	rts

; d0 = colour key -> d1 = taken slot with the nearest colour.

.nearest_slot:
	movem.l	d0/d2-d7/a5,-(sp)

	move	d0,d2
	lsr		#5,d2
	and		#$1f,d2 ; R
	move	d0,d3
	lsr		#8,d3
	lsr		#2,d3
	and		#$1f,d3 ; G
	and		#$1f,d0 ; B

	lea		hardware_palette+4,a5
	move.l	#$7fffffff,d7 ; Best distance.
	moveq	#0,d1 ; Best slot.
	moveq	#0,d6 ; Slot.

.slot_loop:
	tst.b	(a4,d6.w)
	beq		.next_slot

	moveq	#0,d4
	move.b	(a5),d4
	lsr.b	#3,d4
	sub		d2,d4
	muls	d4,d4
	moveq	#0,d5
	move.b	4(a5),d5
	lsr.b	#3,d5
	sub		d3,d5
	muls	d5,d5
	add.l	d5,d4
	moveq	#0,d5
	move.b	8(a5),d5
	lsr.b	#3,d5
	sub		d0,d5
	muls	d5,d5
	add.l	d5,d4

	cmp.l	d7,d4
	bcc		.next_slot

	move.l	d4,d7
	move	d6,d1

.next_slot:
	lea		12(a5),a5
	addq	#1,d6
	cmp		#256,d6
	bne		.slot_loop

	movem.l	(sp)+,d0/d2-d7/a5

	rts

; ------------------------------------------------------------------------------
;
; Incremental palette update (the game cycles a few entries every frame):
; recolours the slots of the changed entries, moves a changed sprite/text
; entry that shares its slot to a free slot, and builds palette_update_table
; (LoadRGB32 ranges of one colour each). Returns d0 = 0 if done, -1 if a full
; rebuild is needed (a graphics slot shared with sprite entries changed, or
; no free slot is left).

update_palette_entries:
	movem.l	d1-d7/a0-a6,-(sp)

	lea		L_00E82000,a0
	lea		palette_copy,a1
	lea		palette_update_table,a6
	lea		slot_taken,a4
	lea		slot_references,a5
	lea		used_graphics,a3
	moveq	#0,d0

	; Graphics entries (identity slots).

	moveq	#0,d7

.graphics_loop:
	move	(a0,d7.w*2),d0
	cmp		(a1,d7.w*2),d0
	beq		.next_graphics

	tst		d7
	beq		.next_graphics ; Index 0: transparent.

	tst.b	(a3,d7.w)
	beq		.next_graphics ; Not shown.

	tst		(a5,d7.w*2)
	bne		.full ; Shared with sprite entries.

	lsr		#1,d0
	move	d7,d6
	bsr		.recolour

.next_graphics:
	addq	#1,d7
	cmp		#256,d7
	bne		.graphics_loop

	; Sprite/text entry 0: the backdrop in slot 0.

	move	512(a0),d0
	cmp		512(a1),d0
	beq		.sprite_entries

	tst		(a5)
	bne		.full ; Sprite entries share the backdrop's slot.

	lsr		#1,d0
	moveq	#0,d6
	bsr		.recolour

.sprite_entries:
	lea		sprite_remap,a2
	moveq	#1,d7

.sprite_loop:
	move	512(a0,d7.w*2),d0
	cmp		512(a1,d7.w*2),d0
	beq		.next_sprite

	lsr		#1,d0
	moveq	#0,d6
	move.b	(a2,d7.w),d6 ; Current slot.
	beq		.move_entry ; The backdrop's slot.

	tst.b	(a3,d6.w)
	bne		.move_entry ; A graphics slot: cannot be recoloured for it.

	cmp		#1,(a5,d6.w*2)
	bne		.move_entry ; Shared.

	bsr		.recolour

	bra		.next_sprite

.move_entry:
	subq	#1,(a5,d6.w*2)

	moveq	#1,d6

.find_free:
	tst.b	(a4,d6.w)
	beq		.free

	addq	#1,d6
	cmp		#256,d6
	bne		.find_free

	bra		.full

.free:
	st		(a4,d6.w)
	move	#1,(a5,d6.w*2)
	move.b	d6,(a2,d7.w)
	bsr		.recolour

.next_sprite:
	addq	#1,d7
	cmp		#256,d7
	bne		.sprite_loop

	clr.l	(a6) ; End of the LoadRGB32 table.
	move.l	#palette_update_table,palette_load_table
	st		palette_changed

	; Take over the new palette.

	lea		L_00E82000,a0
	lea		palette_copy,a1
	move	#512/2-1,d0

.copy:
	move.l	(a0)+,(a1)+
	dbf		d0,.copy

	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#0,d0

	rts

.full:
	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#-1,d0

	rts

; d0 = colour key, d6 = slot: sets the slot's colour in hardware_palette and
; appends a one-colour range to palette_update_table (a6).

.recolour:
	movem.l	d0-d2/a0,-(sp)

	lea		hardware_palette+4,a0
	move	d6,d1
	mulu	#12,d1
	add.l	d1,a0

	move.l	#1<<16,d1
	move	d6,d1
	move.l	d1,(a6)+ ; One colour at this slot.

	move	d0,d1
	lsr		#5,d1
	and		#$1f,d1 ; R
	bsr		expand_component
	move.l	d2,(a0)+
	move.l	d2,(a6)+

	move	d0,d1
	lsr		#8,d1
	lsr		#2,d1
	and		#$1f,d1 ; G
	bsr		expand_component
	move.l	d2,(a0)+
	move.l	d2,(a6)+

	move	d0,d1
	and		#$1f,d1 ; B
	bsr		expand_component
	move.l	d2,(a0)
	move.l	d2,(a6)+

	movem.l	(sp)+,d0-d2/a0

	rts

; d1 = 5-bit component -> d2 = 8 bits replicated into 32 bits.

expand_component:
	move	d1,d2
	lsl		#3,d2
	lsr		#2,d1
	or		d1,d2 ; 8 bits.
	move.b	d2,d1
	lsl		#8,d2
	move.b	d1,d2
	move	d2,d1
	swap	d2
	move	d1,d2

	rts

; ------------------------------------------------------------------------------
;
; GVRAM pages 0 and 1 (low byte of each word = graphics palette index).

render_graphics:
	tst.b	layers_ready
	beq		render_graphics_per_pixel

	move	L_00E80000+CRTC_PAGE0_X,d0
	or		L_00E80000+CRTC_PAGE1_X,d0
	and		#511,d0
	bne		render_graphics_per_pixel ; Horizontal scroll (rotated screen).

	lea		layer0,a0
	lea		layer1,a1
	lea		span_lines,a3
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a2

	moveq	#0,d7 ; Line.

.line_loop:
	; Page 1 line (index 0 shows the backdrop in slot 0).

	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE1_Y,d1
	add		d7,d1
	and		#LAYER_LINES-1,d1
	lsl.l	#8,d1 ; * LAYER_WIDTH
	add.l	a1,d1
	move.l	d1,page1_line

	; Page 0 line and its runs.

	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE0_Y,d1
	add		d7,d1
	and		#LAYER_LINES-1,d1
	move.l	(a3,d1.l*4),d0 ; Runs of this line.
	lsl.l	#8,d1
	lea		(a0,d1.l),a4 ; Layer line.

	tst.l	d0
	bne		.with_runs

	; No run lists (run buffer full): page 1, then page 0 pixel by pixel.

	move.l	page1_line,a1
	move.l	a2,a5

	rept	LAYER_WIDTH/4
	move.l	(a1)+,(a5)+
	endr

	bra		.pixel_line

.with_runs:
	move.l	d0,a6

	; Page 0's opaque runs, then page 1 in the gaps between them: every
	; pixel is written once.

.run_loop:
	move	(a6)+,d2 ; Start.
	bmi		.gaps

	move	(a6)+,d3 ; Length.
	lea		(a4,d2.w),a5
	lea		(a2,d2.w),a1

	COPY_RUN

	bra		.run_loop

.gaps:
	addq.l	#2,a6 ; Rest of the end marker.
	move.l	page1_line,a4

.gap_loop:
	move	(a6)+,d2 ; Start.
	bmi		.next_line

	move	(a6)+,d3 ; Length.
	lea		(a4,d2.w),a5
	lea		(a2,d2.w),a1

	COPY_RUN

	bra		.gap_loop

.pixel_line:
	; No run list (run buffer full): overlay the non-zero pixels.

	move.l	a2,a1
	move	#LAYER_WIDTH-1,d3

.pixel_loop:
	move.b	(a4)+,d0
	beq		.transparent

	move.b	d0,(a1)

.transparent:
	addq.l	#1,a1

	dbf		d3,.pixel_loop

.next_line:
	lea		layer1,a1
	lea		RENDER_STRIDE(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; Fallback: straight from GVRAM, pixel by pixel, with any scroll.

render_graphics_per_pixel:
	lea		L_00C00000,a0 ; Page 0.
	lea		GVRAM_PAGE_SIZE(a0),a1 ; Page 1.
	lea		graphics_remap,a3
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a2

	moveq	#0,d0
	move.b	sprite_remap,d4 ; Backdrop: sprite/text palette entry 0.

	move	L_00E80000+CRTC_PAGE0_X,d2
	and		#511,d2
	move	L_00E80000+CRTC_PAGE1_X,d3
	and		#511,d3

	moveq	#0,d7 ; Line.

.line_loop:
	move	L_00E80000+CRTC_PAGE0_Y,d1
	add		d7,d1
	and.l	#511,d1
	lsl.l	#8,d1
	lsl.l	#2,d1 ; * GVRAM_LINE
	lea		(a0,d1.l),a4

	move	L_00E80000+CRTC_PAGE1_Y,d1
	add		d7,d1
	and.l	#511,d1
	lsl.l	#8,d1
	lsl.l	#2,d1
	lea		(a1,d1.l),a5

	move	d2,d5 ; Page 0 x.
	move	d3,d6 ; Page 1 x.
	move	#RENDER_WIDTH-1,d1

.pixel_loop:
	move.b	1(a4,d5.w*2),d0
	bne		.opaque

	move.b	1(a5,d6.w*2),d0
	beq		.backdrop

.opaque:
	move.b	(a3,d0.w),(a2)+

	bra		.next_pixel

.backdrop:
	move.b	d4,(a2)+

.next_pixel:
	addq	#1,d5
	and		#511,d5
	addq	#1,d6
	and		#511,d6

	dbf		d1,.pixel_loop

	lea		RENDER_STRIDE-RENDER_WIDTH(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; ------------------------------------------------------------------------------
;
; Text layer: 4 bit planes of 1024 x 1024 pixels, palette block 0, colour 0
; transparent; the horizontal scroll is applied in whole bytes. The visible
; window is kept converted in text_draw: per line, its four-pixel groups
; with text, each as a mask and palette-mapped colours, so drawing is one
; masked long write per group. Lines are converted again only when their
; character row was written, the scroll changed or the text colours' palette
; slots changed, and only lines with text are drawn.

render_text:
	; The text colours' palette slots changed: every visible line is
	; converted again.

	lea		sprite_remap,a3
	lea		text_remap,a0
	move.l	(a3),d0
	cmp.l	(a0),d0
	bne		.remap_changed
	move.l	4(a3),d0
	cmp.l	4(a0),d0
	bne		.remap_changed
	move.l	8(a3),d0
	cmp.l	8(a0),d0
	bne		.remap_changed
	move.l	12(a3),d0
	cmp.l	12(a0),d0
	beq		.remap_same

.remap_changed:
	move.l	(a3),(a0)
	move.l	4(a3),4(a0)
	move.l	8(a3),8(a0)
	move.l	12(a3),12(a0)

	lea		text_dirty_rows,a0
	moveq	#-1,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)

	ifd __RENDER_PROFILE__
	addq.l	#1,text_remaps
	endif

.remap_same:
	bsr		update_text_overlay

	lea		text_line_used,a1
	lea		text_draw,a4
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a2
	moveq	#0,d7 ; Line.

.line_loop:
	tst.b	(a1,d7.w)
	beq		.next_line

	ifd __RENDER_PROFILE__
	addq.l	#1,text_lines_drawn
	endif

	; dst = (dst & ~mask) | colour for each group whose bit is set, in
	; group order: groups 0-31, then 32-63 (128 bytes to the right).

	lea		TEXT_GROUP_BITS(a4),a5
	move.l	a2,a6
	move.l	(a4),d4

.left_loop:
	bfffo	d4{0:32},d0
	beq		.left_done

	bfclr	d4{d0:1}
	move.l	(a5)+,d2
	move.l	(a5)+,d3
	not.l	d2
	beq		.left_full

	and.l	(a6,d0.l*4),d2
	or.l	d3,d2
	move.l	d2,(a6,d0.l*4)

	bra		.left_loop

.left_full:
	move.l	d3,(a6,d0.l*4)

	bra		.left_loop

.left_done:
	lea		RENDER_WIDTH/2(a2),a6
	move.l	4(a4),d4

.right_loop:
	bfffo	d4{0:32},d0
	beq		.next_line

	bfclr	d4{d0:1}
	move.l	(a5)+,d2
	move.l	(a5)+,d3
	not.l	d2
	beq		.right_full

	and.l	(a6,d0.l*4),d2
	or.l	d3,d2
	move.l	d2,(a6,d0.l*4)

	bra		.right_loop

.right_full:
	move.l	d3,(a6,d0.l*4)

	bra		.right_loop

.next_line:
	lea		TEXT_DRAW_LINE(a4),a4
	lea		RENDER_STRIDE(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; Converts the visible lines whose character row is dirty into text_draw:
; per line, a bit for each of the 64 groups of four pixels that has text,
; then for each of those groups (in order) its mask and palette-mapped
; colours (transparent pixels 0 in both).

update_text_overlay:
	; A scroll change makes the whole window stale.

	move	L_00E80000+CRTC_TEXT_X,d0
	swap	d0
	move	L_00E80000+CRTC_TEXT_Y,d0
	cmp.l	text_overlay_scroll,d0
	beq		.scroll_same

	move.l	d0,text_overlay_scroll

	lea		text_dirty_rows,a0
	moveq	#-1,d0
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)+
	move.l	d0,(a0)

.scroll_same:
	lea		L_00E00000,a0
	lea		text_draw,a2
	lea		text_dirty_rows,a6
	lea		sprite_remap,a3

	move	L_00E80000+CRTC_TEXT_X,d1
	lsr		#3,d1
	move	d1,a1 ; Byte column.

	moveq	#0,d7 ; Line.

.line_loop:
	moveq	#0,d1
	move	L_00E80000+CRTC_TEXT_Y,d1
	add		d7,d1
	and.l	#1023,d1

	move	d1,d0
	lsr		#3,d0 ; Character row.
	move	d0,d2
	lsr		#3,d2
	btst	d0,(a6,d2.w)
	beq		.next_line

	lsl.l	#7,d1 ; * TEXT_LINE
	lea		(a0,d1.l),a4

	clr.l	(a2)
	clr.l	4(a2)
	lea		TEXT_GROUP_BITS(a2),a5

	lea		text_line_used,a3
	sf		(a3,d7.w)
	lea		sprite_remap,a3

	ifd __RENDER_PROFILE__
	addq.l	#1,text_lines_converted
	endif

	moveq	#0,d6 ; Byte within the line.

.byte_loop:
	moveq	#0,d1
	move	a1,d1
	add		d6,d1
	and		#TEXT_LINE-1,d1

	move.b	(a4,d1.l),d3 ; Plane 0.
	move.b	TEXT_PLANE_SIZE(a4,d1.l),d4 ; Plane 1.
	move.b	TEXT_PLANE_SIZE*2(a4,d1.l),d5 ; Plane 2.
	move.b	TEXT_PLANE_SIZE*3(a4,d1.l),d1 ; Plane 3.

	move.b	d3,d0
	or.b	d4,d0
	or.b	d5,d0
	or.b	d1,d0
	beq		.next_byte

	lea		text_line_used,a3
	st		(a3,d7.w)
	lea		sprite_remap,a3

	; The byte's two groups (left four pixels first).

	bsr		.convert_group
	tst.l	(a5)
	beq		.left_empty

	move	d6,d0
	add		d0,d0
	bfset	(a2){d0:1}
	addq.l	#8,a5

.left_empty:
	bsr		.convert_group
	tst.l	(a5)
	beq		.next_byte

	move	d6,d0
	add		d0,d0
	addq	#1,d0
	bfset	(a2){d0:1}
	addq.l	#8,a5

.next_byte:
	addq	#1,d6
	cmp		#RENDER_WIDTH/8,d6
	bne		.byte_loop

.next_line:
	lea		TEXT_DRAW_LINE(a2),a2

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	; All rows are up to date (rows outside the window are reconverted when
	; the scroll brings them in).

	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)+
	clr.l	(a6)

	rts

; Four pixels from the top bits of the planes (d3 plane 0, d4 plane 1,
; d5 plane 2, d1 plane 3; shifted out): mask bytes at (a5), mapped colours
; at 4(a5). Colour = plane 3 << 3 | plane 2 << 2 | plane 1 << 1 | plane 0.

.convert_group:
	moveq	#4-1,d2

.pixel_loop:
	moveq	#0,d0
	add.b	d1,d1
	addx.b	d0,d0
	add.b	d5,d5
	addx.b	d0,d0
	add.b	d4,d4
	addx.b	d0,d0
	add.b	d3,d3
	addx.b	d0,d0
	tst.b	d0 ; (ADDX leaves Z from the ADD before it.)
	beq		.transparent

	st		(a5)+
	move.b	(a3,d0.w),3(a5)

	dbf		d2,.pixel_loop

	subq.l	#4,a5

	rts

.transparent:
	clr.b	(a5)+
	clr.b	3(a5)

	dbf		d2,.pixel_loop

	subq.l	#4,a5

	rts

; ------------------------------------------------------------------------------
;
; Sprites in priority order, as on the Falcon: 32 buckets by attribute bits
; 4-0 drawn from 0 to 31 (later is in front), the entries of a bucket in
; reverse list order.

render_sprites:
	move	render_sprite_count,d7
	beq		.done

	move.l	SPRITE_DATA_ADDRESS,d0
	beq		.done

	; Count per bucket.

	lea		bucket_counts,a0
	moveq	#32/2-1,d0

.clear_counts:
	clr.l	(a0)+
	dbf		d0,.clear_counts

	lea		sprite_list,a0
	lea		bucket_counts,a1
	move	d7,d0
	subq	#1,d0

.count_loop:
	moveq	#$1f,d1
	and		6(a0),d1
	addq	#1,(a1,d1.w*2)
	addq.l	#8,a0

	dbf		d0,.count_loop

	; Bucket end offsets: entries are stored backwards from each end, so a
	; bucket ends up in reverse list order.

	lea		bucket_counts,a1
	lea		bucket_ends,a2
	moveq	#0,d1
	moveq	#32-1,d0

.offset_loop:
	add		(a1)+,d1
	move	d1,(a2)+

	dbf		d0,.offset_loop

	lea		sprite_list,a0
	lea		bucket_ends,a2
	lea		sprite_order,a3
	moveq	#0,d2 ; Entry index.
	move	d7,d0
	subq	#1,d0

.order_loop:
	moveq	#$1f,d1
	and		6(a0),d1
	add		d1,d1
	move	(a2,d1.w),d3
	sub		#1,d3
	move	d3,(a2,d1.w)
	move	d2,(a3,d3.w*2)

	addq	#1,d2
	addq.l	#8,a0

	dbf		d0,.order_loop

	; Draw. Within a bucket the order above is reversed already; the
	; buckets follow in ascending order.

	tst.b	sprite_cache_reset
	beq		.cache_ok

	bsr		reset_sprite_cache

.cache_ok:
	lea		sprite_order,a6
	move	d7,d6
	subq	#1,d6

.sprite_loop:
	move	(a6)+,d0
	lea		sprite_list,a0
	lea		(a0,d0.w*8),a0

	moveq	#0,d0
	move	4(a0),d0 ; Pattern.
	cmp		#PCG_PATTERNS,d0
	bcc		.next_sprite

	move	d0,d4 ; Pattern index.
	move.l	SPRITE_DATA_ADDRESS,a1
	lsl.l	#7,d0
	add.l	d0,a1 ; Pattern data.

	move	6(a0),d5 ; Attributes.
	move	d5,d0
	lsr		#4,d0
	and		#$f0,d0
	lea		sprite_remap,a3
	add		d0,a3 ; Palette block.

	moveq	#0,d0
	move	(a0),d0 ; x
	cmp		#RENDER_STRIDE-16,d0
	bhi		.next_sprite

	moveq	#0,d1
	move	2(a0),d1 ; y
	cmp		#RENDER_LINES-16,d1
	bhi		.next_sprite

	mulu	#RENDER_STRIDE,d1
	lea		render_buffer,a2
	add.l	d1,a2
	add.l	d0,a2 ; Top left.

	; Compiled routine for (pattern, flip): attributes bit 14 = horizontal,
	; bit 15 = vertical flip.

	moveq	#0,d0
	move	d5,d0
	rol		#2,d0
	and		#3,d0
	lsl		#2,d4
	add		d4,d0 ; Variant: pattern * 4 + flip.
	lea		compiled_table,a4
	move.l	(a4,d0.l*4),d1
	bne		.call_compiled

	tst.l	arena
	beq		.generic

	bsr		compile_sprite_variant
	move.l	d0,d1
	beq		.generic

.call_compiled:
	movem.l	d6/a6,-(sp)
	move.l	d1,a0
	move.l	a2,a6
	move.l	a3,a5
	jsr		(a0)
	movem.l	(sp)+,d6/a6

	bra		.next_sprite

.generic:
	; Rows: d4 = source row step (4 bytes, or -4 for a vertical flip).

	moveq	#4,d4
	btst	#15,d5
	beq		.no_vertical_flip

	lea		15*4(a1),a1
	moveq	#-4,d4

.no_vertical_flip:
	moveq	#16-1,d3

.row_loop:
	move.l	(a1),d0 ; Left 8 pixels.
	move.l	64(a1),d1 ; Right 8 pixels.
	add		d4,a1

	btst	#14,d5
	bne		.flipped_row

	move.l	a2,a4
	bsr		.draw_8
	move.l	d1,d0
	bsr		.draw_8

	bra		.next_row

.flipped_row:
	lea		16(a2),a4
	bsr		.draw_8_flipped
	move.l	d1,d0
	bsr		.draw_8_flipped

.next_row:
	lea		RENDER_STRIDE(a2),a2

	dbf		d3,.row_loop

.next_sprite:
	dbf		d6,.sprite_loop

.done:
	rts

; d0 = 8 pixels (high nibble = left); a4 = destination, advanced by 8.

.draw_8:
	moveq	#8-1,d2

.draw_loop:
	rol.l	#4,d0
	moveq	#$f,d7
	and		d0,d7
	beq		.skip

	move.b	(a3,d7.w),(a4)

.skip:
	addq.l	#1,a4

	dbf		d2,.draw_loop

	rts

; Same, mirrored: a4 = one past the right end, moved left by 8.

.draw_8_flipped:
	moveq	#8-1,d2

.flipped_loop:
	rol.l	#4,d0
	moveq	#$f,d7
	and		d0,d7
	subq.l	#1,a4
	tst		d7
	beq		.flipped_skip

	move.b	(a3,d7.w),(a4)

.flipped_skip:
	dbf		d2,.flipped_loop

	rts

	ifd __RENDER_PROFILE__

; profile_stage = stage that has just ended (-1: start): adds the ticks since
; the previous mark to it.

profile_mark:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	move.l	timer_base,a6
	lea		profile_now,a0
	jsr		-60(a6) ; ReadEClock

	move.l	profile_stage,d0
	bmi		.start

	move.l	profile_now+4,d1
	sub.l	profile_last+4,d1
	lea		render_profile,a0
	add.l	d1,(a0,d0.l*4)

.start:
	move.l	profile_now+4,profile_last+4

	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

	endif

; ------------------------------------------------------------------------------

reset_sprite_cache:
	sf		sprite_cache_reset

	move.l	arena,arena_next
	move.l	arena,d0
	add.l	arena_size,d0
	move.l	d0,arena_end
	clr.l	compiled_sprite_count

	lea		compiled_table,a0
	move	#PCG_PATTERNS*4-1,d0

.clear:
	clr.l	(a0)+
	dbf		d0,.clear

	rts

; d0.l = variant (pattern * 4 + flip; bit 0 = horizontal, bit 1 = vertical
; flip), a1 = pattern data. Compiles the routine into the arena and enters it
; in compiled_table. Returns d0 = routine, or 0 if the arena is full.
; Preserves all other registers.

compile_sprite_variant:
	movem.l	d1-d7/a0-a6,-(sp)

	move.l	arena_end,d1
	sub.l	arena_next,d1
	cmp.l	#MAXIMUM_COMPILED_SIZE,d1
	bcs		.full

	move.l	d0,d7 ; Variant.

	; Decode into a 16 x 16 matrix of colour indices, flips applied.

	lea		decode_matrix,a2
	moveq	#0,d3 ; Row.

.decode_row:
	move	d3,d1
	btst	#1,d7
	beq		.row_ok

	moveq	#15,d1
	sub		d3,d1 ; Vertical flip.

.row_ok:
	lsl		#2,d1
	move.l	(a1,d1.w),d4 ; Left 8 pixels.
	move.l	64(a1,d1.w),d5 ; Right 8 pixels.

	moveq	#0,d2 ; x

.decode_pixel:
	cmp		#8,d2
	bne		.same_half

	move.l	d5,d4

.same_half:
	rol.l	#4,d4
	moveq	#$f,d0
	and		d4,d0

	move	d2,d1
	btst	#0,d7
	beq		.column_ok

	moveq	#15,d1
	sub		d2,d1 ; Horizontal flip.

.column_ok:
	move	d3,d6
	lsl		#4,d6
	add		d1,d6
	move.b	d0,(a2,d6.w)

	addq	#1,d2
	cmp		#16,d2
	bne		.decode_pixel

	addq	#1,d3
	cmp		#16,d3
	bne		.decode_row

	; Colour frequencies.

	lea		colour_counts,a3
	moveq	#16/2-1,d0

.clear_counts:
	clr.l	(a3)+
	dbf		d0,.clear_counts

	lea		colour_counts,a3
	move	#256-1,d1
	moveq	#0,d0

.count:
	move.b	(a2)+,d0
	addq	#1,(a3,d0.w*2)
	dbf		d1,.count

	; Registers d0-d7 for the eight most frequent colours (1-15).

	lea		colour_registers,a4
	moveq	#16/4-1,d0

.clear_registers:
	move.l	#-1,(a4)+
	dbf		d0,.clear_registers

	lea		colour_registers,a4
	moveq	#0,d5 ; Register.

.choose:
	moveq	#0,d3 ; Best count.
	moveq	#0,d4 ; Best colour.
	moveq	#1,d1

.candidate:
	tst.b	(a4,d1.w)
	bpl		.next_candidate ; Already has a register.

	move	(a3,d1.w*2),d2
	cmp		d3,d2
	bls		.next_candidate

	move	d2,d3
	move	d1,d4

.next_candidate:
	addq	#1,d1
	cmp		#16,d1
	bne		.candidate

	tst		d3
	beq		.chosen

	move.b	d5,(a4,d4.w)
	addq	#1,d5
	cmp		#8,d5
	bne		.choose

.chosen:
	; Emit: load the register colours, then one move per opaque pixel.

	move.l	arena_next,a0
	move.l	a0,a6 ; Routine.
	moveq	#1,d1

.prologue:
	moveq	#0,d0
	move.b	(a4,d1.w),d0
	bmi		.next_prologue

	lsl		#8,d0
	add		d0,d0 ; Register << 9.
	add		#OPCODE_LOAD_COLOUR,d0
	move	d0,(a0)+
	move	d1,(a0)+ ; Colour offset in the remap block.

.next_prologue:
	addq	#1,d1
	cmp		#16,d1
	bne		.prologue

	lea		decode_matrix,a2
	moveq	#0,d3 ; Row.

.emit_row:
	moveq	#0,d2 ; x

.emit_pixel:
	moveq	#0,d0
	move.b	(a2)+,d0
	beq		.next_emit

	move	d3,d1
	mulu	#RENDER_STRIDE,d1
	add		d2,d1 ; Offset.

	move.b	(a4,d0.w),d4
	bmi		.from_memory

	ext		d4
	add		#OPCODE_STORE_REGISTER,d4
	move	d4,(a0)+
	move	d1,(a0)+

	bra		.next_emit

.from_memory:
	move	#OPCODE_STORE_MEMORY,(a0)+
	move	d0,(a0)+
	move	d1,(a0)+

.next_emit:
	addq	#1,d2
	cmp		#16,d2
	bne		.emit_pixel

	addq	#1,d3
	cmp		#16,d3
	bne		.emit_row

	move	#OPCODE_RTS,(a0)+
	move.l	a0,arena_next

	lea		compiled_table,a1
	move.l	a6,(a1,d7.l*4)
	move.l	a6,d6 ; Routine (exec may change a0/a1/d0/d1).
	addq.l	#1,compiled_sprite_count

	; The new code must not meet stale instruction cache lines.

	move.l	exec_base,a6
	jsr		_LVOCacheClearU(a6)

	move.l	d6,d0

	movem.l	(sp)+,d1-d7/a0-a6

	rts

.full:
	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#0,d0

	rts

	xdef end_of_code

end_of_code: ; graphics.s is linked last: end of the code hunk.

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

layers_dirty: ; Build the layers on the first frame (GVRAM is empty until the
	dc.b	-1 ; game builds it, then amiga_graphics_changed marks it).

	even

text_dirty_rows: ; Bit per text character row (128); all dirty at start.
	dcb.b	16,$ff

text_overlay_scroll:
	dc.l	-1

	even

; ------------------------------------------------------------------------------
	section	renderer,bss ; A hunk of its own (see mem_map.s).
; ------------------------------------------------------------------------------

frame_sprite_count:
	ds.w	1
render_sprite_count:
	ds.w	1
palette_changed:
	ds.b	1
palette_rebuild:
	ds.b	1
layers_ready:
	ds.b	1

	even

palette_overflows:
	ds.l	1
compiled_sprite_count:
	ds.l	1

	ifd __RENDER_PROFILE__

render_profile: ; Palette, graphics, text, sprites, upload.
	ds.l	5
text_lines_converted:
	ds.l	1
text_lines_drawn:
	ds.l	1
text_remaps:
	ds.l	1
palette_entry_changes:
	ds.w	512
palette_rebuilds:
	ds.l	1
profile_stage:
	ds.l	1
profile_now:
	ds.l	2
profile_last:
	ds.l	2

	endif
arena:
	ds.l	1
arena_size:
	ds.l	1
arena_next:
	ds.l	1
arena_end:
	ds.l	1

compiled_table:
	ds.l	PCG_PATTERNS*4

decode_matrix:
	ds.b	256

colour_counts:
	ds.w	16

colour_registers:
	ds.b	16

sprite_cache_reset:
	ds.b	1

	even

; Per pattern: palettes it was drawn with (word, bit n = palette n).

sprite_palette_usage:
	ds.w	MAXIMUM_PATTERNS

sprite_list:
	ds.l	MAXIMUM_SPRITES*2

sprite_order:
	ds.w	MAXIMUM_SPRITES

bucket_counts:
	ds.w	32

bucket_ends:
	ds.w	32

palette_copy:
	ds.w	512

slot_references: ; Sprite/text entries per slot.
	ds.w	256

palette_load_table: ; Table for the next LoadRGB32.
	ds.l	1

palette_update_table: ; Up to 512 one-colour ranges and the terminator.
	ds.l	512*4+1

graphics_remap: ; Followed directly by sprite_remap (filled in one loop).
	ds.b	256
sprite_remap:
	ds.b	256

colour_hash_slots:
	ds.b	COLOUR_HASH_SIZE

used_graphics:
	ds.b	256

slot_taken:
	ds.b	256

layer0:
	ds.b	LAYER_WIDTH*LAYER_LINES
layer1: ; Must follow layer0 (build_layers fills both in one pass).
	ds.b	LAYER_WIDTH*LAYER_LINES

span_lines:
	ds.l	LAYER_LINES

span_buffer:
	ds.b	SPAN_BUFFER_SIZE

page1_line:
	ds.l	1

text_line_used:
	ds.b	RENDER_HEIGHT

text_remap: ; sprite_remap of the text colours (0-15) the lines were mapped with.
	ds.b	16

	cnop	0,4

text_draw: ; Per line: group bits, then (mask, mapped colours) per group with text.
	ds.b	TEXT_DRAW_LINE*RENDER_HEIGHT

	even

colour_hash_keys:
	ds.w	COLOUR_HASH_SIZE

; LoadRGB32 table: count.w, first.w, up to 256 RGB triplets, terminator.

hardware_palette:
	ds.l	1+256*3+1

render_buffer:
	ds.b	RENDER_STRIDE*RENDER_LINES

	even

text_bitmaps:
	ds.l	2*32 ; Text clear bitmap infos followed by text draw bitmap infos.

text_matrix:
	ds.b	32*32

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
