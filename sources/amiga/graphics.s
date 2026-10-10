
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
;
; On the AGA screen the frame is drawn straight into the hidden screen
; buffer's bitplanes instead (see "Planar rendering" below), without the
; chunky buffer and its conversion; frames that path cannot draw (layers
; not built yet, a horizontal scroll) are composed in the chunky buffer as
; on RTG and converted by display.s.

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
	xdef planar_copy_to_screen
	xdef finish_pipelined_frame
	xdef poll_pipelined_frame

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
	xref planar_display_available
	xref begin_planar_frame
	xref pipelined_frame_target
	xref flip_pipelined_frame
	xref graphics_base
	xref machine_cpu

	ifd __RENDER_PROFILE__
	xref timer_base
	xdef render_profile
	xdef planar_sprites_made
	xdef planar_arena_resets
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
_LVOFindTask=-294
_LVOWait=-318
_LVOSignal=-324
_LVOAllocSignal=-330
_LVOFreeSignal=-336

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

	bsr		initialize_planar

	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

release_renderer:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	bsr		release_planar

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

	bsr		finish_pipelined_frame ; The picture before (pipelined).
	PROFILE	4

	tst.b	layers_dirty
	beq		.layers_ok

	bsr		build_layers

.layers_ok:
	bsr		update_palette
	PROFILE	0

	bsr		planar_frame_target
	move.l	d0,planar_destination
	bne		.planar

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

	; AGA: in planar form.

.planar:
	tst.b	planar_blitter
	beq		.planar_now

	bsr		prepare_pipelined_frame
	PROFILE	1

	bra		.done

.planar_now:
	ifnd __NO_GRAPHICS__
	bsr		planar_graphics
	endif
	PROFILE	1

	move	L_00E82000+VC_PRIORITY,d0
	move	d0,d1
	lsr		#8,d0
	lsr		#4,d0
	and		#3,d0 ; Sprites.
	lsr		#8,d1
	lsr		#2,d1
	and		#3,d1 ; Text.
	cmp		d1,d0
	bhi		.planar_text_in_front

	ifnd __NO_TEXT__
	bsr		planar_text
	endif
	PROFILE	2
	ifnd __NO_SPRITES__
	bsr		planar_sprites
	endif
	PROFILE	3

	bra		.done

.planar_text_in_front:
	ifnd __NO_SPRITES__
	bsr		planar_sprites
	endif
	PROFILE	3
	ifnd __NO_TEXT__
	bsr		planar_text
	endif
	PROFILE	2

	bra		.done

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

	tst.b	planar_enabled
	beq		.no_planar

	bsr		build_planar_layers

.no_planar:
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
	bsr		prepare_text

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

; Brings text_draw up to date: when the text colours' palette slots have
; changed every visible line is converted again, otherwise the lines whose
; character row was written.

prepare_text:
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
	bra		update_text_overlay

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

	lea		text_planar_stale,a3
	st		(a3,d7.w)
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

; sprite_order = the sprites' list indices in drawing order. Returns d7 =
; the number of sprites (Z set if none or no pattern data).

order_sprites:
	move	render_sprite_count,d7
	beq		.done

	move.l	SPRITE_DATA_ADDRESS,d0
	beq		.none

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

	; Within a bucket the order above is reversed already; the buckets
	; follow in ascending order.

	tst		d7

.done:
	rts

.none:
	moveq	#0,d7

	rts

; Draws the sprites into render_buffer.

render_sprites:
	bsr		order_sprites
	beq		.done

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

	tst.l	planar_arena
	beq		.no_planar

	bsr		reset_planar_sprites

.no_planar:

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

; ------------------------------------------------------------------------------
;
; Planar rendering (AGA): the frame is drawn into a planar frame in fast
; RAM with the layout of the screen's bitmaps (interleaved, 8 planes,
; 320-pixel rows, the picture 32 pixels from the left edge), which
; display.s has copied into the hidden screen buffer (planar_copy_to_screen)
; before it shows it; drawing in chip RAM directly is slower (the sprites'
; read-modify-writes). -D__PLANAR_DIRECT__ draws into the hidden screen
; buffer itself (display.s begin_planar_frame). Pixels get the same palette
; slots as in the chunky buffer, so the picture is the same.
;
; On a 68020 (or with -D__PLANAR_BLITTER__) frames are pipelined instead:
; at the frame the blitter composes the background into the next screen
; buffer (from copies of the planar layers in chip RAM), queued through
; QBlit, while the CPU prepares the text and the sprites and then goes on
; with the game; at a later frame end (or the next picture) the text and the
; sprites are drawn straight into that buffer, which is then shown
; (finish_pipelined_frame). The picture is one frame later; screenshots and
; the poll renders finish at once.
;
;   - Background: GVRAM pages 0 and 1 are converted once (build_layers) into
;     planar layers, per line eight 32-pixel groups of eight plane longs,
;     plus a mask of page 0's opaque pixels per group. Each group is copied
;     from page 0 (mask all set), from page 1 (mask clear) or merged.
;   - Text: lines converted into text_draw (prepare_text) are converted on
;     into planar groups (mask and eight plane longs); groups with text are
;     drawn with masked long writes.
;   - Sprites: per (pattern, flip, palette) a planar version (a mask word and
;     eight plane words per row) and a routine that draws it are made on
;     first use and kept in an arena, and made again when the palette's
;     slots change. Each row is shifted into place and written with masked
;     long writes: a plane that is clear (or set) at all the row's opaque
;     pixels is one AND (or OR) into the screen. Sprites cut by the
;     picture's edges are drawn from the planar version, clipped.

PLANAR_ROW_BYTES=40 ; One plane's row of the 320-pixel screen.
PLANAR_LINE=PLANAR_ROW_BYTES*8 ; Interleaved: all eight planes' rows.
PLANAR_PICTURE_X=4 ; Picture start in a plane row (bytes).

PLANAR_GROUPS=RENDER_WIDTH/32 ; 32-pixel groups per picture line.
PLANAR_LAYER_LINE=PLANAR_GROUPS*8*4
PLANAR_LAYER_SIZE=PLANAR_LAYER_LINE*LAYER_LINES
PLANAR_MASK_SIZE=PLANAR_GROUPS*4*LAYER_LINES
PLANAR_TEXT_GROUP=4+8*4 ; Mask, eight planes.
PLANAR_TEXT_LINE=4+PLANAR_GROUPS*PLANAR_TEXT_GROUP ; Group bits (byte), groups.
PLANAR_TEXT_SIZE=PLANAR_TEXT_LINE*RENDER_HEIGHT
PLANAR_FRAME_SIZE=PLANAR_LINE*RENDER_HEIGHT
PLANAR_MEMORY_SIZE=PLANAR_LAYER_SIZE*2+PLANAR_MASK_SIZE+PLANAR_TEXT_SIZE+PLANAR_FRAME_SIZE

; Blitter: the chip layers have the plane rows of a line one after the
; other (plane p at p * 32) and 768 lines (the first 256 again after the
; 512), so the 256 lines from any scroll position follow each other; the
; mask has 32 bytes per line. Per plane one blit of 16 words x 256 rows:
; D = A | (C & ~B), A = page 0, B = page 0's mask, C = page 1.

BLIT_LAYER_LINES=LAYER_LINES+RENDER_HEIGHT
BLIT_LAYER_SIZE=PLANAR_LAYER_LINE*BLIT_LAYER_LINES
BLIT_MASK_SIZE=PLANAR_GROUPS*4*BLIT_LAYER_LINES
BLIT_MEMORY_SIZE=BLIT_LAYER_SIZE*2+BLIT_MASK_SIZE
BLIT_SOURCE_MODULO=PLANAR_LAYER_LINE-PLANAR_GROUPS*4
BLIT_DESTINATION_MODULO=PLANAR_LINE-PLANAR_GROUPS*4
BLIT_CONTROL=$0ff20000 ; BLTCON0: A, B, C, D, minterm $f2; BLTCON1: 0.
BLIT_SIZE=(RENDER_HEIGHT<<6)|(PLANAR_GROUPS*2) ; (vasm: | binds tighter than *.)

MEMF_CHIP=1<<1
_LVOQBlit=-276
_LVOWaitBlit=-228

bn_function=4 ; struct bltnode
bn_stat=8
bn_cleanup=14
BLTNODE_SIZE=18

DMACONR=$002 ; Custom chip registers (offsets).
DMAB_BLTDONE=14 ; DMACONR: blitter busy.
BLTCON0=$040
BLTAFWM=$044
BLTCPT=$048
BLTBPT=$04c
BLTAPT=$050
BLTDPT=$054
BLTSIZE=$058
BLTCMOD=$060
BLTBMOD=$062
BLTAMOD=$064
BLTDMOD=$066

PLANAR_ARENA_SIZE=$100000
PLANAR_ARENA_MINIMUM=$40000

; Planar sprite: next (same pattern and flip), palette, its routine, the
; palette's slots it was made with, then 16 rows of a mask word and eight
; plane words. The routine follows it in the arena (or comes later, when it
; was made again).

PE_NEXT=0
PE_PALETTE=4
PE_CODE=6
PE_REMAP=10
PE_ROWS=26
PE_ROW=2+8*2
PLANAR_ENTRY_SIZE=PE_ROWS+16*PE_ROW

; Sprite routines: a2 = the screen long of row 0, d5 = shift; uses d0-d3.
; Per row with opaque pixels:
;   move.l #mask<<16,d0 / lsr.l d5,d0 / move.l d0,d1 / not.l d1
; then per plane, at offset row * PLANAR_LINE + plane * PLANAR_ROW_BYTES:
;   clear: and.l d1,offset(a2)
;   set:   or.l d0,offset(a2)
;   mixed: move.l #plane<<16,d2 / lsr.l d5,d2 / move.l offset(a2),d3 /
;          and.l d1,d3 / or.l d2,d3 / move.l d3,offset(a2)

OPCODE_MOVE_IMMEDIATE_D0=$203c
OPCODE_LSR_D0_MOVE_D0_D1=$eaa82200 ; lsr.l d5,d0 / move.l d0,d1
OPCODE_NOT_D1=$4681
OPCODE_AND_D1_TO_A2=$c3aa
OPCODE_OR_D0_TO_A2=$81aa
OPCODE_MOVE_IMMEDIATE_D2=$243c
OPCODE_LSR_D2=$eaaa
OPCODE_MOVE_A2_TO_D3=$262a
OPCODE_AND_D1_OR_D2=$c6818682 ; and.l d1,d3 / or.l d2,d3
OPCODE_MOVE_D3_TO_A2=$2543
PLANAR_CODE_MAXIMUM=16*(6+4+2+8*20)+2

; MERGE a, b, shift, mask, spare: swaps the mask bits of a with the bits of b
; shifted right by shift.

MERGE macro
	move.l	\2,\5
	lsr.l	#\3,\5
	eor.l	\1,\5
	and.l	#\4,\5
	eor.l	\5,\1
	lsl.l	#\3,\5
	eor.l	\5,\2
	endm

MERGE16 macro ; MERGE a, b, 16, $0000ffff with word moves (spare: low word).
	swap	\2
	move.w	\1,\3
	move.w	\2,\1
	move.w	\3,\2
	swap	\2
	endm

; C2P32: 32 chunky pixels in d0-d7 (four per long, the leftmost in the top
; byte) -> planes 0-7 in d7, d5, d3, d1, d6, d4, d2, d0 (the c2p of
; display.s). Uses a6.

C2P32 macro
	MERGE16	d0,d4,a6
	MERGE16	d1,d5,a6
	MERGE16	d2,d6,a6
	MERGE16	d3,d7,a6

	move.l	d7,a6
	MERGE	d0,d4,2,$33333333,d7
	MERGE	d1,d5,2,$33333333,d7
	MERGE	d2,d6,2,$33333333,d7
	move.l	a6,d7
	move.l	d0,a6
	MERGE	d3,d7,2,$33333333,d0
	move.l	a6,d0

	move.l	d7,a6
	MERGE	d0,d2,8,$00ff00ff,d7
	MERGE	d0,d2,1,$55555555,d7
	MERGE	d1,d3,8,$00ff00ff,d7
	MERGE	d1,d3,1,$55555555,d7
	MERGE	d4,d6,8,$00ff00ff,d7
	MERGE	d4,d6,1,$55555555,d7
	move.l	a6,d7
	move.l	d0,a6
	MERGE	d5,d7,8,$00ff00ff,d0
	MERGE	d5,d7,1,$55555555,d0
	move.l	a6,d0

	move.l	d7,a6
	MERGE	d0,d1,4,$0f0f0f0f,d7
	MERGE	d2,d3,4,$0f0f0f0f,d7
	MERGE	d4,d5,4,$0f0f0f0f,d7
	move.l	a6,d7
	move.l	d0,a6
	MERGE	d6,d7,4,$0f0f0f0f,d0
	move.l	a6,d0
	endm

; Stores the planes of C2P32 to (\1)+ in plane order.

STORE_PLANES macro
	move.l	d7,(\1)+
	move.l	d5,(\1)+
	move.l	d3,(\1)+
	move.l	d1,(\1)+
	move.l	d6,(\1)+
	move.l	d4,(\1)+
	move.l	d2,(\1)+
	move.l	d0,(\1)+
	endm

; Background group, one plane (\1): page 0 | (page 1 & ~mask) (page 0's
; transparent pixels are 0 in every plane); a0 = page 0, a1 = page 1, d2 =
; inverted mask, a3 = destination. Uses d0.

MERGE_PLANE macro
	move.l	(a1)+,d0
	and.l	d2,d0
	or.l	(a0)+,d0
	move.l	d0,PLANAR_ROW_BYTES*\1(a3)
	endm

; Text group, one plane (\1): a5 = group (planes from 4), d0 = inverted
; mask, a2 = destination. Uses d2.

MASKED_PLANE macro
	move.l	PLANAR_ROW_BYTES*\1(a2),d2
	and.l	d0,d2
	or.l	4+\1*4(a5),d2
	move.l	d2,PLANAR_ROW_BYTES*\1(a2)
	endm

; Sprite row, one plane (\1): the plane word at (a4)+ shifted right by d5
; from the long's top; d0 = mask (shifted, clipped; it also drops what the
; swap brings into the low word), d1 = inverted mask, a2 = destination.
; Uses d2-d3.

SPRITE_PLANE macro
	move	(a4)+,d2
	swap	d2
	lsr.l	d5,d2
	and.l	d0,d2
	move.l	PLANAR_ROW_BYTES*\1(a2),d3
	and.l	d1,d3
	or.l	d2,d3
	move.l	d3,PLANAR_ROW_BYTES*\1(a2)
	endm

; Allocates the planar layers and sprite arena when the AGA screen can take
; planar rendering (task context, after open_display). Without the memory
; frames go through the chunky buffer. The compiled chunky sprites' arena is
; given up for the planar one: the few chunky frames (see planar_frame_target)
; draw their sprites with the generic routine.

initialize_planar:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	jsr		planar_display_available
	tst.l	d0
	beq		.done

	move.l	exec_base,a6

	move.l	arena,d0
	beq		.no_arena

	clr.l	arena
	move.l	d0,a1
	move.l	arena_size,d0
	jsr		_LVOFreeMem(a6)

.no_arena:
	move.l	#PLANAR_MEMORY_SIZE,d0
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,planar_memory
	beq		.done

	move.l	d0,planar_layer0
	add.l	#PLANAR_LAYER_SIZE,d0
	move.l	d0,planar_layer1
	add.l	#PLANAR_LAYER_SIZE,d0
	move.l	d0,planar_mask
	add.l	#PLANAR_MASK_SIZE,d0
	move.l	d0,planar_text_lines
	add.l	#PLANAR_TEXT_SIZE,d0
	move.l	d0,planar_frame

	move.l	#PLANAR_ARENA_SIZE,d0
	move.l	d0,planar_arena_size
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,planar_arena
	bne		.arena

	move.l	#PLANAR_ARENA_MINIMUM,d0
	move.l	d0,planar_arena_size
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,planar_arena
	bne		.arena

	move.l	planar_memory,a1
	clr.l	planar_memory
	move.l	#PLANAR_MEMORY_SIZE,d0
	jsr		_LVOFreeMem(a6)

	bra		.done

.arena:
	add.l	planar_arena_size,d0
	move.l	d0,planar_arena_end
	bsr		reset_planar_sprites

	; Every text line is converted on the first planar frame.

	lea		text_planar_stale,a0
	move	#RENDER_HEIGHT/4-1,d0

.stale:
	move.l	#-1,(a0)+
	dbf		d0,.stale

	st		planar_enabled

	; Pipelined frames with the blitter on a 68020 (a 68030 composes in
	; fast RAM faster than the blitter).

	ifnd __PLANAR_DIRECT__
	ifnd __PLANAR_BLITTER__
	cmp.l	#30,machine_cpu
	bcc		.done
	endif

	; blit_background signals the task when the background is done.

	moveq	#-1,d0
	jsr		_LVOAllocSignal(a6)
	move.l	d0,blit_signal
	bmi		.done

	sub.l	a1,a1
	jsr		_LVOFindTask(a6)
	move.l	d0,blit_task

	move.l	#BLIT_MEMORY_SIZE,d0
	moveq	#MEMF_CHIP,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,blit_memory
	beq		.free_signal

	move.l	d0,blit_layer0
	add.l	#BLIT_LAYER_SIZE,d0
	move.l	d0,blit_layer1
	add.l	#BLIT_LAYER_SIZE,d0
	move.l	d0,blit_mask

	st		planar_blitter

	bra		.done

.free_signal:
	move.l	blit_signal,d0
	jsr		_LVOFreeSignal(a6)
	move.l	#-1,blit_signal
	endif

.done:
	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

release_planar:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	bsr		finish_pipelined_frame

	sf		planar_enabled
	sf		planar_blitter
	move.l	exec_base,a6

	move.l	blit_memory,d0
	beq		.no_blit_memory

	clr.l	blit_memory
	move.l	d0,a1
	move.l	#BLIT_MEMORY_SIZE,d0
	jsr		_LVOFreeMem(a6)

.no_blit_memory:
	move.l	blit_signal,d0
	bmi		.no_signal

	move.l	#-1,blit_signal
	jsr		_LVOFreeSignal(a6)

.no_signal:

	move.l	planar_arena,d0
	beq		.no_arena

	clr.l	planar_arena
	move.l	d0,a1
	move.l	planar_arena_size,d0
	jsr		_LVOFreeMem(a6)

.no_arena:
	move.l	planar_memory,d0
	beq		.done

	clr.l	planar_memory
	move.l	d0,a1
	move.l	#PLANAR_MEMORY_SIZE,d0
	jsr		_LVOFreeMem(a6)

.done:
	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

; Returns d0 = the picture's top left in plane 0 of the hidden screen buffer
; if this frame is drawn planar, else 0.

planar_frame_target:
	moveq	#0,d0
	tst.b	planar_enabled
	beq		.done

	tst.b	layers_ready
	beq		.done

	move	L_00E80000+CRTC_PAGE0_X,d1
	or		L_00E80000+CRTC_PAGE1_X,d1
	and		#511,d1
	bne		.done ; Horizontal scroll: the chunky per-pixel path.

	moveq	#1,d0 ; Pipelined: prepare_pipelined_frame takes the buffer.
	tst.b	planar_blitter
	bne		.done

	ifd __PLANAR_DIRECT__
	jsr		begin_planar_frame
	else
	move.l	planar_frame,d0
	addq.l	#PLANAR_PICTURE_X,d0
	st		planar_copy_pending
	endif

.done:
	tst.l	d0

	rts

; display.s present_frame (AGA): copies a frame drawn into planar_frame into
; the hidden screen buffer, if there is one (and makes present_frame show it
; as it is). Preserves all registers.

planar_copy_to_screen:
	tst.b	planar_copy_pending
	beq		.done

	sf		planar_copy_pending

	movem.l	d0-d7/a0-a6,-(sp)

	jsr		begin_planar_frame
	move.l	d0,a1
	move.l	planar_frame,a0
	addq.l	#PLANAR_PICTURE_X,a0
	lea		PLANAR_FRAME_SIZE(a0),a4

.line_loop:
	movem.l	(a0),d0-d6/a2
	movem.l	d0-d6/a2,(a1)
	movem.l	PLANAR_ROW_BYTES*1(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*1(a1)
	movem.l	PLANAR_ROW_BYTES*2(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*2(a1)
	movem.l	PLANAR_ROW_BYTES*3(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*3(a1)
	movem.l	PLANAR_ROW_BYTES*4(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*4(a1)
	movem.l	PLANAR_ROW_BYTES*5(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*5(a1)
	movem.l	PLANAR_ROW_BYTES*6(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*6(a1)
	movem.l	PLANAR_ROW_BYTES*7(a0),d0-d6/a2
	movem.l	d0-d6/a2,PLANAR_ROW_BYTES*7(a1)

	lea		PLANAR_LINE(a0),a0
	lea		PLANAR_LINE(a1),a1
	cmp.l	a4,a0
	bne		.line_loop

	movem.l	(sp)+,d0-d7/a0-a6

.done:
	rts

; build_layers: layer0 / layer1 into the planar layers, and page 0's mask.

build_planar_layers:
	movem.l	d0-d7/a0-a6,-(sp)

	lea		layer0,a0 ; layer1 follows.
	move.l	planar_layer0,a1 ; planar_layer1 follows.
	lea		layer0+LAYER_WIDTH*LAYER_LINES*2,a2

.convert:
	movem.l	(a0)+,d0-d7

	C2P32
	STORE_PLANES a1

	cmp.l	a2,a0
	bne		.convert

	; Page 0's mask: a pixel is opaque if its index is not 0, that is if any
	; of its plane bits is set (graphics indices are their own slots).

	move.l	planar_layer0,a0
	move.l	planar_mask,a1
	move	#LAYER_LINES*PLANAR_GROUPS-1,d1

.mask:
	move.l	(a0)+,d0
	or.l	(a0)+,d0
	or.l	(a0)+,d0
	or.l	(a0)+,d0
	or.l	(a0)+,d0
	or.l	(a0)+,d0
	or.l	(a0)+,d0
	or.l	(a0)+,d0
	move.l	d0,(a1)+

	dbf		d1,.mask

	tst.b	planar_blitter
	beq		.done

	bsr		copy_chip_layers

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

; The blitter's copies of the planar layers and the mask in chip RAM.

copy_chip_layers:
	movem.l	d0-d7/a0-a6,-(sp)

	move.l	planar_layer0,a0
	move.l	blit_layer0,a1
	bsr		.chip_layer
	move.l	planar_layer1,a0
	move.l	blit_layer1,a1
	bsr		.chip_layer

	move.l	planar_mask,a0
	move.l	blit_mask,a1
	move.l	a1,a2
	move	#LAYER_LINES*PLANAR_GROUPS-1,d2

.chip_mask:
	move.l	(a0)+,(a1)+
	dbf		d2,.chip_mask

	move	#RENDER_HEIGHT*PLANAR_GROUPS-1,d2

.chip_mask_again:
	move.l	(a2)+,(a1)+
	dbf		d2,.chip_mask_again

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; a0 = planar layer (groups of eight plane longs), a1 = chip layer (plane
; rows), then the first RENDER_HEIGHT lines again.

.chip_layer:
	move.l	a1,a2
	move	#LAYER_LINES-1,d2

.chip_line:
	move.l	a0,a3
	moveq	#8-1,d3

.chip_plane:
	move.l	(a3),(a1)+
	move.l	1*32(a3),(a1)+
	move.l	2*32(a3),(a1)+
	move.l	3*32(a3),(a1)+
	move.l	4*32(a3),(a1)+
	move.l	5*32(a3),(a1)+
	move.l	6*32(a3),(a1)+
	move.l	7*32(a3),(a1)+
	addq.l	#4,a3

	dbf		d3,.chip_plane

	lea		PLANAR_LAYER_LINE(a0),a0

	dbf		d2,.chip_line

	move	#RENDER_HEIGHT*PLANAR_LAYER_LINE/4-1,d2

.chip_again:
	move.l	(a2)+,(a1)+
	dbf		d2,.chip_again

	rts

; ------------------------------------------------------------------------------
;
; Pipelined frames (blitter). Starts the frame: queues the background's
; blits into the next screen buffer, then prepares the text and the sprites
; while they run. Task context.

prepare_pipelined_frame:
	jsr		pipelined_frame_target
	move.l	d0,planar_destination
	move.l	d0,blit_destination

	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE0_Y,d1
	and		#LAYER_LINES-1,d1
	move.l	d1,d2
	lsl.l	#8,d1 ; * PLANAR_LAYER_LINE
	add.l	blit_layer0,d1
	move.l	d1,blit_page0
	lsl.l	#5,d2 ; * PLANAR_GROUPS * 4
	add.l	blit_mask,d2
	move.l	d2,blit_page0_mask

	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE1_Y,d1
	and		#LAYER_LINES-1,d1
	lsl.l	#8,d1
	add.l	blit_layer1,d1
	move.l	d1,blit_page1

	clr		blit_plane
	sf		blit_done
	st		pipeline_pending

	ifnd __NO_GRAPHICS__
	move.l	graphics_base,a6
	lea		blit_node,a1
	jsr		_LVOQBlit(a6)
	else
	st		blit_done
	endif

	; R1: text in front of the sprites?

	move	L_00E82000+VC_PRIORITY,d0
	move	d0,d1
	lsr		#8,d0
	lsr		#4,d0
	and		#3,d0 ; Sprites.
	lsr		#8,d1
	lsr		#2,d1
	and		#3,d1 ; Text.
	cmp		d1,d0
	shi		pipeline_text_in_front

	ifnd __NO_TEXT__
	bsr		planar_convert_text
	endif
	ifnd __NO_SPRITES__
	bsr		planar_prepare_sprites
	endif

	rts

; QBlit routine (a0 = custom chips; interrupt or task context): one plane's
; blit per call; the call after the eighth blit marks the background done
; and signals the task. Uses d0-d1/a0-a1.

blit_background:
	; The blitter may still be busy (its busy bit is set a little after a
	; blit starts): the registers are only written once it is idle.

	tst.b	DMACONR(a0) ; (The first read of the busy bit can be stale.)

.busy:
	btst	#DMAB_BLTDONE-8,DMACONR(a0)
	bne		.busy

	move	blit_plane,d0
	cmp		#8,d0
	beq		.finished

	move.l	#BLIT_CONTROL,BLTCON0(a0)
	move.l	#-1,BLTAFWM(a0)
	move.l	blit_page1,BLTCPT(a0)
	move.l	blit_page0_mask,BLTBPT(a0)
	move.l	blit_page0,BLTAPT(a0)
	move.l	blit_destination,BLTDPT(a0)
	move	#BLIT_SOURCE_MODULO,BLTCMOD(a0)
	clr		BLTBMOD(a0)
	move	#BLIT_SOURCE_MODULO,BLTAMOD(a0)
	move	#BLIT_DESTINATION_MODULO,BLTDMOD(a0)
	move	#BLIT_SIZE,BLTSIZE(a0) ; Starts it.

	add.l	#PLANAR_GROUPS*4,blit_page0
	add.l	#PLANAR_GROUPS*4,blit_page1
	add.l	#PLANAR_ROW_BYTES,blit_destination
	addq	#1,blit_plane

	moveq	#1,d0 ; Call again.

	rts

.finished:
	st		blit_done

	move.l	a6,-(sp)
	move.l	exec_base,a6
	move.l	blit_task,a1
	move.l	blit_signal,d0
	moveq	#0,d1
	bset	d0,d1
	move.l	d1,d0
	jsr		_LVOSignal(a6)
	move.l	(sp)+,a6

	moveq	#0,d0

	rts

; Finishes the pipelined frame, if one is started: waits for its
; background, draws the text and the sprites into it and shows it. Task
; context. Preserves all registers.

finish_pipelined_frame:
	tst.b	pipeline_pending
	beq		.done

	movem.l	d0-d7/a0-a6,-(sp)

	; Wait() rather than a busy loop: the blitter queue may be waiting for
	; a task of lower priority to give the blitter up.

	move.l	exec_base,a6

.wait:
	tst.b	blit_done
	bne		.blitted

	move.l	blit_signal,d1
	moveq	#0,d0
	bset	d1,d0
	jsr		_LVOWait(a6)

	bra		.wait

.blitted:
	sf		pipeline_pending

	; The last blit has ended; the CPU reads what the blitter wrote (a
	; 68030's data cache).

	move.l	graphics_base,a6
	jsr		_LVOWaitBlit(a6)
	move.l	exec_base,a6
	jsr		_LVOCacheClearU(a6)

	tst.b	pipeline_text_in_front
	bne		.text_in_front

	ifnd __NO_TEXT__
	bsr		planar_draw_text
	endif
	ifnd __NO_SPRITES__
	bsr		planar_draw_sprites
	endif

	bra		.show

.text_in_front:
	ifnd __NO_SPRITES__
	bsr		planar_draw_sprites
	endif
	ifnd __NO_TEXT__
	bsr		planar_draw_text
	endif

.show:
	jsr		flip_pipelined_frame

	movem.l	(sp)+,d0-d7/a0-a6

.done:
	rts

; emulator.s, at every frame end: finishes the pipelined frame if its
; background is done. Preserves all registers.

poll_pipelined_frame:
	tst.b	pipeline_pending
	beq		.done

	tst.b	blit_done
	beq		.done

	bra		finish_pipelined_frame

.done:
	rts

; Background: page 0 over page 1, each with its vertical scroll.

planar_graphics:
	move.l	planar_destination,a3
	move.l	planar_layer0,a4
	move.l	planar_layer1,a5
	move.l	planar_mask,a6
	moveq	#0,d7 ; Line.

.line_loop:
	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE0_Y,d1
	add		d7,d1
	and		#LAYER_LINES-1,d1
	move.l	d1,d0
	lsl.l	#8,d1 ; * PLANAR_LAYER_LINE
	lea		(a4,d1.l),a0
	lsl.l	#5,d0 ; * PLANAR_GROUPS * 4
	lea		(a6,d0.l),a2

	moveq	#0,d1
	move	L_00E80000+CRTC_PAGE1_Y,d1
	add		d7,d1
	and		#LAYER_LINES-1,d1
	lsl.l	#8,d1
	lea		(a5,d1.l),a1

	moveq	#PLANAR_GROUPS-1,d6

.group_loop:
	move.l	(a2)+,d2 ; Page 0's opaque pixels.
	beq		.page1

	moveq	#-1,d0
	cmp.l	d0,d2
	bne		.merge

	move.l	(a0)+,(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES*2(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES*3(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES*4(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES*5(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES*6(a3)
	move.l	(a0)+,PLANAR_ROW_BYTES*7(a3)
	lea		8*4(a1),a1

	bra		.next_group

.page1:
	move.l	(a1)+,(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES*2(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES*3(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES*4(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES*5(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES*6(a3)
	move.l	(a1)+,PLANAR_ROW_BYTES*7(a3)
	lea		8*4(a0),a0

	bra		.next_group

	; Page 1 where page 0 is transparent.

.merge:
	not.l	d2

	MERGE_PLANE	0
	MERGE_PLANE	1
	MERGE_PLANE	2
	MERGE_PLANE	3
	MERGE_PLANE	4
	MERGE_PLANE	5
	MERGE_PLANE	6
	MERGE_PLANE	7

.next_group:
	addq.l	#4,a3

	dbf		d6,.group_loop

	lea		PLANAR_LINE-PLANAR_GROUPS*4(a3),a3

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; ------------------------------------------------------------------------------
;
; Text: converts the lines prepare_text has converted since the last planar
; frame, then draws the lines with text.

planar_text:
	bsr		planar_convert_text

	bra		planar_draw_text

; prepare_text, then the lines it converted into planar groups.

planar_convert_text:
	bsr		prepare_text

	lea		text_planar_stale,a0
	lea		text_line_used,a1
	moveq	#0,d7 ; Line.

.convert_loop:
	tst.b	(a0,d7.w)
	beq		.next_convert

	sf		(a0,d7.w)
	tst.b	(a1,d7.w)
	beq		.next_convert ; No text: not drawn.

	bsr		convert_planar_text_line

.next_convert:
	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.convert_loop

	rts

; Draws the lines with text.

planar_draw_text:
	lea		text_line_used,a1
	move.l	planar_destination,a3
	move.l	planar_text_lines,a4
	moveq	#0,d7

.line_loop:
	tst.b	(a1,d7.w)
	beq		.next_line

	ifd __RENDER_PROFILE__
	addq.l	#1,text_lines_drawn
	endif

	move.b	(a4),d6 ; Groups with text (bit 7 = group 0).
	lea		4(a4),a5
	move.l	a3,a2
	moveq	#PLANAR_GROUPS-1,d5

.group_loop:
	add.b	d6,d6
	bcc		.next_group

	move.l	(a5),d0 ; Mask.
	moveq	#-1,d1
	cmp.l	d1,d0
	bne		.masked

	move.l	4(a5),(a2)
	move.l	8(a5),PLANAR_ROW_BYTES(a2)
	move.l	12(a5),PLANAR_ROW_BYTES*2(a2)
	move.l	16(a5),PLANAR_ROW_BYTES*3(a2)
	move.l	20(a5),PLANAR_ROW_BYTES*4(a2)
	move.l	24(a5),PLANAR_ROW_BYTES*5(a2)
	move.l	28(a5),PLANAR_ROW_BYTES*6(a2)
	move.l	32(a5),PLANAR_ROW_BYTES*7(a2)

	bra		.next_group

.masked:
	not.l	d0

	MASKED_PLANE	0
	MASKED_PLANE	1
	MASKED_PLANE	2
	MASKED_PLANE	3
	MASKED_PLANE	4
	MASKED_PLANE	5
	MASKED_PLANE	6
	MASKED_PLANE	7

.next_group:
	lea		PLANAR_TEXT_GROUP(a5),a5
	addq.l	#4,a2

	dbf		d5,.group_loop

.next_line:
	lea		PLANAR_TEXT_LINE(a4),a4
	lea		PLANAR_LINE(a3),a3

	addq	#1,d7
	cmp		#RENDER_HEIGHT,d7
	bne		.line_loop

	rts

; d7 = line: its text_draw groups (mask and colours per four pixels) into
; planar groups. Preserves all registers.

convert_planar_text_line:
	movem.l	d0-d7/a0-a6,-(sp)

	move	d7,d0
	mulu	#TEXT_DRAW_LINE,d0
	lea		text_draw,a3
	add.l	d0,a3 ; Group bits.
	lea		TEXT_GROUP_BITS(a3),a5 ; Masks and colours of the groups with text.

	move	d7,d0
	mulu	#PLANAR_TEXT_LINE,d0
	move.l	planar_text_lines,a4
	add.l	d0,a4
	clr.b	(a4)

	moveq	#0,d6 ; 32-pixel group.

.group_loop:
	move.b	(a3,d6.w),d3 ; Its eight four-pixel groups (bit 7 first).
	beq		.next_group

	moveq	#7,d0
	sub		d6,d0
	bset	d0,(a4)

	move	d6,d0
	mulu	#PLANAR_TEXT_GROUP,d0
	lea		4(a4,d0.l),a2

	lea		planar_text_pixels,a1
	moveq	#0,d4 ; Mask.
	moveq	#8-1,d5

.four_loop:
	lsl.l	#4,d4
	add.b	d3,d3
	bcc		.empty

	move.l	(a5)+,d1 ; Mask bytes ($ff or 0).
	move.l	(a5)+,(a1)+ ; Colours.
	moveq	#4-1,d2

.mask_bit:
	rol.l	#8,d1
	tst.b	d1
	beq		.transparent

	bset	d2,d4

.transparent:
	dbf		d2,.mask_bit

	bra		.next_four

.empty:
	clr.l	(a1)+

.next_four:
	dbf		d5,.four_loop

	move.l	d4,(a2)+
	move	d6,planar_text_group

	movem.l	planar_text_pixels,d0-d7
	C2P32
	STORE_PLANES a2

	move	planar_text_group,d6

.next_group:
	addq	#1,d6
	cmp		#PLANAR_GROUPS,d6
	bne		.group_loop

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; Sprites, in the order of render_sprites.

planar_sprites:
	bsr		planar_prepare_sprites

	bra		planar_draw_sprites

; Fills planar_draw_list (planar sprite, x, y) in drawing order, making the
; planar sprites. If the arena is emptied on the way (full), the list is
; made again once, so that it holds no sprite made before.

planar_prepare_sprites:
	clr		planar_draw_count
	bsr		order_sprites
	beq		.done

	tst.b	sprite_cache_reset
	beq		.cache_ok

	bsr		reset_sprite_cache

.cache_ok:
	sf		planar_list_made_again

.list:
	clr		planar_draw_count
	move.l	planar_reset_serial,d4
	lea		sprite_order,a6
	lea		planar_draw_list,a5
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

	moveq	#0,d2
	move	(a0),d2 ; x
	cmp		#RENDER_STRIDE-16,d2
	bhi		.next_sprite

	moveq	#0,d3
	move	2(a0),d3 ; y
	cmp		#RENDER_LINES-16,d3
	bhi		.next_sprite

	; Variant: pattern * 4 + flip (attributes bit 14 = horizontal, bit 15
	; = vertical); palette: attributes bits 11-8.

	move	6(a0),d5
	lsl.l	#2,d0
	move	d5,d1
	rol		#2,d1
	and		#3,d1
	add		d1,d0
	move	d5,d1
	lsr		#8,d1
	and		#$f,d1

	bsr		planar_sprite

	cmp.l	planar_reset_serial,d4
	beq		.listed

	tst.b	planar_list_made_again
	bne		.listed

	st		planar_list_made_again

	bra		.list

.listed:
	move.l	a4,(a5)+
	move	d2,(a5)+
	move	d3,(a5)+
	addq	#1,planar_draw_count

.next_sprite:
	dbf		d6,.sprite_loop

.done:
	rts

; Draws planar_draw_list.

planar_draw_sprites:
	move	planar_draw_count,d6
	beq		.done

	subq	#1,d6
	lea		planar_draw_list,a6

.sprite_loop:
	move.l	(a6)+,a4
	move	(a6)+,d2
	move	(a6)+,d3
	bsr		draw_planar_sprite

	dbf		d6,.sprite_loop

.done:
	rts

; d0.l = variant, d1 = palette -> a4 = its planar sprite, made or brought up
; to date. Preserves all other registers.

planar_sprite:
	movem.l	d0-d2/a0-a1,-(sp)

	lea		planar_table,a0
	move.l	(a0,d0.l*4),d2

.find:
	beq		.new

	move.l	d2,a4
	cmp		PE_PALETTE(a4),d1
	beq		.found

	move.l	PE_NEXT(a4),d2

	bra		.find

.found:
	lea		sprite_remap,a1
	move	d1,d2
	lsl		#4,d2
	add		d2,a1
	move.l	(a1)+,d2
	cmp.l	PE_REMAP(a4),d2
	bne		.remade
	move.l	(a1)+,d2
	cmp.l	PE_REMAP+4(a4),d2
	bne		.remade
	move.l	(a1)+,d2
	cmp.l	PE_REMAP+8(a4),d2
	bne		.remade
	move.l	(a1),d2
	cmp.l	PE_REMAP+12(a4),d2
	beq		.done

	; The palette's slots changed: made again, with a new routine.

.remade:
	move.l	planar_arena_end,d2
	sub.l	planar_arena_next,d2
	cmp.l	#PLANAR_CODE_MAXIMUM,d2
	bcc		.build

	bsr		reset_planar_sprites ; Full: start again.

.new:
	move.l	planar_arena_end,d2
	sub.l	planar_arena_next,d2
	cmp.l	#PLANAR_ENTRY_SIZE+PLANAR_CODE_MAXIMUM,d2
	bcc		.room

	bsr		reset_planar_sprites ; Full: start again.

.room:
	move.l	planar_arena_next,a4
	lea		PLANAR_ENTRY_SIZE(a4),a1
	move.l	a1,planar_arena_next
	move.l	(a0,d0.l*4),PE_NEXT(a4)
	move.l	a4,(a0,d0.l*4)

.build:
	bsr		build_planar_sprite
	bsr		compile_planar_sprite

.done:
	movem.l	(sp)+,d0-d2/a0-a1

	rts

; a4 = planar sprite, d0.l = variant, d1 = palette: takes the palette's slots
; and converts the pattern. Preserves all registers.

build_planar_sprite:
	movem.l	d0-d7/a0-a3,-(sp)

	move	d1,PE_PALETTE(a4)
	lea		sprite_remap,a3
	lsl		#4,d1
	add		d1,a3 ; Slots of the palette's colours.
	move.l	(a3),PE_REMAP(a4)
	move.l	4(a3),PE_REMAP+4(a4)
	move.l	8(a3),PE_REMAP+8(a4)
	move.l	12(a3),PE_REMAP+12(a4)

	move.l	d0,d7 ; Variant.
	lsr.l	#2,d0
	lsl.l	#7,d0
	move.l	SPRITE_DATA_ADDRESS,a1
	add.l	d0,a1 ; Pattern data.

	lea		PE_ROWS(a4),a0
	moveq	#0,d3 ; Row.

.row_loop:
	clr.l	(a0)
	clr.l	4(a0)
	clr.l	8(a0)
	clr.l	12(a0)
	clr		16(a0)

	move	d3,d1
	btst	#1,d7
	beq		.row_ok

	moveq	#15,d1
	sub		d3,d1 ; Vertical flip.

.row_ok:
	lsl		#2,d1
	move.l	(a1,d1.w),d4 ; Left 8 pixels.
	move.l	64(a1,d1.w),d5 ; Right 8 pixels.
	moveq	#0,d2 ; Pixel.

.pixel_loop:
	cmp		#8,d2
	bne		.same_half

	move.l	d5,d4

.same_half:
	rol.l	#4,d4
	moveq	#$f,d0
	and		d4,d0
	beq		.next_pixel ; Transparent.

	move	d2,d1
	btst	#0,d7
	beq		.column_ok

	moveq	#15,d1
	sub		d2,d1 ; Horizontal flip.

.column_ok:
	bfset	(a0){d1:1} ; Mask.

	move.b	(a3,d0.w),d6 ; Slot.
	lea		2(a0),a2
	moveq	#8-1,d0

.plane_loop:
	lsr.b	#1,d6
	bcc		.next_plane

	bfset	(a2){d1:1}

.next_plane:
	addq.l	#2,a2

	dbf		d0,.plane_loop

.next_pixel:
	addq	#1,d2
	cmp		#16,d2
	bne		.pixel_loop

	lea		PE_ROW(a0),a0

	addq	#1,d3
	cmp		#16,d3
	bne		.row_loop

	movem.l	(sp)+,d0-d7/a0-a3

	rts

; a4 = planar sprite (rows made): generates its routine at the arena's
; free space (the caller has checked the room). Preserves all registers.

compile_planar_sprite:
	movem.l	d0-d7/a0-a1/a6,-(sp)

	move.l	planar_arena_next,a0
	move.l	a0,PE_CODE(a4)
	lea		PE_ROWS(a4),a1
	moveq	#0,d7 ; Row offset.
	moveq	#16-1,d6

.row_loop:
	move	(a1)+,d0 ; Mask.
	beq		.empty_row

	move	#OPCODE_MOVE_IMMEDIATE_D0,(a0)+
	move	d0,(a0)+
	clr		(a0)+
	move.l	#OPCODE_LSR_D0_MOVE_D0_D1,(a0)+
	move	#OPCODE_NOT_D1,(a0)+

	move	d7,d4 ; Offset.
	moveq	#8-1,d5

.plane_loop:
	move	(a1)+,d1
	beq		.clear

	cmp		d0,d1
	beq		.set

	move	#OPCODE_MOVE_IMMEDIATE_D2,(a0)+
	move	d1,(a0)+
	clr		(a0)+
	move	#OPCODE_LSR_D2,(a0)+
	move	#OPCODE_MOVE_A2_TO_D3,(a0)+
	move	d4,(a0)+
	move.l	#OPCODE_AND_D1_OR_D2,(a0)+
	move	#OPCODE_MOVE_D3_TO_A2,(a0)+
	move	d4,(a0)+

	bra		.next_plane

.clear:
	move	#OPCODE_AND_D1_TO_A2,(a0)+
	move	d4,(a0)+

	bra		.next_plane

.set:
	move	#OPCODE_OR_D0_TO_A2,(a0)+
	move	d4,(a0)+

.next_plane:
	add		#PLANAR_ROW_BYTES,d4

	dbf		d5,.plane_loop

	bra		.next_row

.empty_row:
	lea		8*2(a1),a1

.next_row:
	add		#PLANAR_LINE,d7

	dbf		d6,.row_loop

	move	#OPCODE_RTS,(a0)+
	move.l	a0,planar_arena_next

	ifd __RENDER_PROFILE__
	addq.l	#1,planar_sprites_made
	endif

	; The new code must not meet stale instruction cache lines.

	move.l	exec_base,a6
	jsr		_LVOCacheClearU(a6)

	movem.l	(sp)+,d0-d7/a0-a1/a6

	rts

; a4 = planar sprite, d2 = x, d3 = y (render buffer positions: the picture
; starts at GUARD). Draws it clipped to the picture: through its routine
; when it is whole inside. Preserves d6/a6.

draw_planar_sprite:
	movem.l	d0-d7/a0/a2/a4,-(sp)

	; Screen x = x - GUARD + 32: the long at word w = x / 16 holds the
	; sprite's 16 pixels from bit 31 - s, s = x & 15. The picture covers
	; words 2-17 of the row: at word 1 only the long's low half is in it, at
	; word 17 the high half.

	move	d2,d0
	add		#32-GUARD,d0
	moveq	#15,d5
	and		d0,d5 ; s
	lsr		#4,d0 ; w
	moveq	#-1,d6 ; Clip.
	cmp		#1,d0
	bne		.not_left

	move.l	#$0000ffff,d6

	bra		.clipped

.not_left:
	cmp		#17,d0
	bcs		.clipped
	bne		.done ; Right of the picture.

	move.l	#$ffff0000,d6

.clipped:
	; Rows within the picture.

	sub		#GUARD,d3 ; Picture line of row 0.
	moveq	#0,d1 ; First row.
	moveq	#16,d4 ; End row.
	tst		d3
	bpl		.top_ok

	move	d3,d1
	neg		d1

.top_ok:
	move	#RENDER_HEIGHT,d2
	sub		d3,d2
	cmp		d4,d2
	bge		.bottom_ok

	move	d2,d4

.bottom_ok:
	sub		d1,d4
	ble		.done

	move.l	planar_destination,a2
	subq.l	#PLANAR_PICTURE_X,a2 ; Row start.
	move	d3,d2
	add		d1,d2
	muls	#PLANAR_LINE,d2
	add.l	d2,a2
	add		d0,d0
	add		d0,a2

	cmp		#16,d4
	bne		.clip

	moveq	#-1,d2
	cmp.l	d2,d6
	bne		.clip

	move.l	PE_CODE(a4),a0 ; Whole inside.
	jsr		(a0)

	bra		.done

.clip:
	subq	#1,d4
	move	d4,d7 ; Rows - 1.

	lea		PE_ROWS(a4),a4
	mulu	#PE_ROW,d1
	add.l	d1,a4

.row_loop:
	move	(a4)+,d0
	swap	d0
	clr		d0
	lsr.l	d5,d0
	and.l	d6,d0 ; Mask.
	beq		.empty_row

	move.l	d0,d1
	not.l	d1

	SPRITE_PLANE	0
	SPRITE_PLANE	1
	SPRITE_PLANE	2
	SPRITE_PLANE	3
	SPRITE_PLANE	4
	SPRITE_PLANE	5
	SPRITE_PLANE	6
	SPRITE_PLANE	7

	bra		.next_row

.empty_row:
	lea		8*2(a4),a4

.next_row:
	lea		PLANAR_LINE(a2),a2

	dbf		d7,.row_loop

.done:
	movem.l	(sp)+,d0-d7/a0/a2/a4

	rts

; Empties the planar sprite arena (the patterns changed, or it is full).
; Preserves all registers.

reset_planar_sprites:
	movem.l	d0/a0,-(sp)

	addq.l	#1,planar_reset_serial

	ifd __RENDER_PROFILE__
	addq.l	#1,planar_arena_resets
	endif

	move.l	planar_arena,planar_arena_next

	lea		planar_table,a0
	move	#PCG_PATTERNS*4-1,d0

.clear:
	clr.l	(a0)+
	dbf		d0,.clear

	movem.l	(sp)+,d0/a0

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

blit_signal: ; Signal bit for the task (-1: none).
	dc.l	-1

blit_node: ; struct bltnode: next, function, stat, blitsize, beamsync, cleanup.
	dc.l	0
	dc.l	blit_background
	dc.b	0,0
	dc.w	0
	dc.w	0
	dc.l	0

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
planar_sprites_made:
	ds.l	1
planar_arena_resets: ; Including the first.
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

	cnop	0,4

; Planar rendering (AGA).

planar_destination: ; Picture's top left in plane 0 of the hidden buffer, or 0.
	ds.l	1
planar_memory: ; Layers, mask and text lines in one allocation.
	ds.l	1
planar_layer0:
	ds.l	1
planar_layer1:
	ds.l	1
planar_mask:
	ds.l	1
planar_text_lines:
	ds.l	1
planar_frame:
	ds.l	1
planar_arena:
	ds.l	1
planar_arena_size:
	ds.l	1
planar_arena_next:
	ds.l	1
planar_arena_end:
	ds.l	1

planar_table: ; Per variant (pattern * 4 + flip): its first planar sprite.
	ds.l	PCG_PATTERNS*4

planar_text_pixels: ; One 32-pixel group of text colours.
	ds.l	8

text_planar_stale: ; Per line: converted into text_draw since its planar group.
	ds.b	RENDER_HEIGHT

planar_text_group:
	ds.w	1

planar_enabled:
	ds.b	1
planar_copy_pending: ; A frame was drawn into planar_frame.
	ds.b	1
planar_blitter: ; Pipelined frames, the background by the blitter.
	ds.b	1
pipeline_pending: ; A pipelined frame waits to be finished.
	ds.b	1
pipeline_text_in_front:
	ds.b	1
blit_done: ; Set by blit_background after the last blit.
	ds.b	1
planar_list_made_again:
	ds.b	1

	even

planar_reset_serial: ; Counts reset_planar_sprites.
	ds.l	1
planar_draw_count:
	ds.w	1
planar_draw_list: ; Planar sprite, x, y.
	ds.l	MAXIMUM_SPRITES*2

blit_memory: ; Chip RAM: the layers and the mask for the blitter.
	ds.l	1
blit_layer0:
	ds.l	1
blit_layer1:
	ds.l	1
blit_mask:
	ds.l	1
blit_page0: ; The next blit's sources and destination.
	ds.l	1
blit_page0_mask:
	ds.l	1
blit_page1:
	ds.l	1
blit_destination:
	ds.l	1
blit_plane:
	ds.w	1
blit_task:
	ds.l	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
