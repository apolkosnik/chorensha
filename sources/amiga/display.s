
; Display output: an 8-bit RTG screen through Picasso96.
;
; The rendered 256 x 256 picture is centred on a 320 x 256 screen (or the
; middle 240 lines on a 320 x 240 screen). Without a usable RTG board (native
; AGA output is a later phase; CyberGraphX is not supported yet) the game
; runs headless: the renderer still composes frames and screenshots come from
; its buffer.

	xdef open_display
	xdef close_display
	xdef present_frame
	xdef capture_screen
	xdef display_active

	xref exec_base
	xref machine_display
	xref machine_rtg
	xref render_buffer
	xref hardware_palette
	xref palette_load_table
	xref palette_changed

	ifd __RENDER_PROFILE__
	xref timer_base
	xdef load_rgb_time
	endif

; exec.library

_LVOOpenLibrary=-552
_LVOCloseLibrary=-414
_LVOAllocMem=-198
_LVOFreeMem=-210

MEMF_CHIP=1<<1
MEMF_CLEAR=1<<16

; intuition.library

_LVOCloseScreen=-66
_LVOCloseWindow=-72
_LVOSetPointer=-270
_LVOOpenWindowTagList=-606
_LVOOpenScreenTagList=-612

TAG_DONE=0
SA_Width=$80000023
SA_Height=$80000024
SA_Depth=$80000025
SA_Type=$8000002d
SA_DisplayID=$80000032
SA_ShowTitle=$80000036
SA_Quiet=$80000038
SA_Draggable=$8000003e
SA_Exclusive=$8000003f
CUSTOMSCREEN=15

WA_Width=$80000066
WA_Height=$80000067
WA_CustomScreen=$80000070
WA_Backdrop=$80000085
WA_NoCareRefresh=$80000087
WA_Borderless=$80000088
WA_Activate=$80000089
WA_RMBTrap=$8000008a
WA_SimpleRefresh=$8000008c

sc_ViewPort=44
wd_RPort=50

; graphics.library

_LVOLoadRGB32=-882

; Picasso96API.library

_LVOp96BestModeIDTagList=-60
_LVOp96WritePixelArray=-102
_LVOp96ReadPixelArray=-108

P96BIDTAG_FormatsAllowed=$80000061
P96BIDTAG_NominalWidth=$80000063
P96BIDTAG_NominalHeight=$80000064
P96BIDTAG_Depth=$80000065
RGBFB_CLUT=1
RGBFF_CLUT=1<<RGBFB_CLUT
INVALID_ID=-1

; struct RenderInfo: Memory, BytesPerRow, pad, RGBFormat.

ri_Memory=0
ri_BytesPerRow=4
ri_RGBFormat=8
RENDER_INFO_SIZE=12

DISPLAY_RTG=1
RTG_PICASSO96=1

; Render buffer layout: must match graphics.s.

GUARD=16
PICTURE_WIDTH=256
PICTURE_HEIGHT=256
RENDER_STRIDE=GUARD+PICTURE_WIDTH+GUARD
SCREEN_WIDTH=320
POINTER_SIZE=16

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Opens the RTG screen if the machine has a Picasso96 board; otherwise the
; game runs headless. Returns nothing; display_active tells which.

open_display:
	movem.l	d2-d7/a2-a6,-(sp)

	clr.b	display_active

	cmp.l	#DISPLAY_RTG,machine_display
	bne		.done

	cmp.l	#RTG_PICASSO96,machine_rtg
	bne		.done

	move.l	exec_base,a6

	lea		intuition_name,a1
	moveq	#39,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,intuition_base
	beq		.failed

	lea		graphics_name,a1
	moveq	#39,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,graphics_base
	beq		.failed

	lea		picasso96_name,a1
	moveq	#2,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,picasso96_base
	beq		.failed

	; Mode: 320 x 256 x 8, else 320 x 240.

	move.l	#PICTURE_HEIGHT,screen_height

.find_mode:
	move.l	screen_height,mode_tags_height
	move.l	picasso96_base,a6
	lea		mode_tags,a0
	jsr		_LVOp96BestModeIDTagList(a6)
	cmp.l	#INVALID_ID,d0
	bne		.mode_found

	cmp.l	#240,screen_height
	beq		.failed

	move.l	#240,screen_height

	bra		.find_mode

.mode_found:
	move.l	d0,screen_tags_mode
	move.l	screen_height,screen_tags_height
	move.l	screen_height,window_tags_height

	; Source rows: the middle screen_height lines of the picture.

	move.l	#PICTURE_HEIGHT,d0
	sub.l	screen_height,d0
	lsr.l	#1,d0
	add.l	#GUARD,d0
	move.l	d0,source_y

	move.l	intuition_base,a6
	sub.l	a0,a0
	lea		screen_tags,a1
	jsr		_LVOOpenScreenTagList(a6)
	move.l	d0,screen
	beq		.failed

	move.l	d0,window_tags_screen
	sub.l	a0,a0
	lea		window_tags,a1
	jsr		_LVOOpenWindowTagList(a6)
	move.l	d0,window
	beq		.failed

	; Invisible mouse pointer (sprite data must be in chip RAM).

	move.l	exec_base,a6
	moveq	#POINTER_SIZE,d0
	move.l	#MEMF_CHIP|MEMF_CLEAR,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,pointer_data
	beq		.pointer_done

	move.l	intuition_base,a6
	move.l	window,a0
	move.l	d0,a1
	moveq	#1,d0
	moveq	#16,d1
	moveq	#0,d2
	moveq	#0,d3
	jsr		_LVOSetPointer(a6)

.pointer_done:
	lea		render_info,a0
	move.l	#render_buffer,ri_Memory(a0)
	move	#RENDER_STRIDE,ri_BytesPerRow(a0)
	move.l	#RGBFB_CLUT,ri_RGBFormat(a0)

	move.l	#hardware_palette,palette_load_table ; The whole palette first.
	st		palette_changed
	st		display_active

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

.failed:
	bsr		close_display

	bra		.done

; ------------------------------------------------------------------------------

close_display:
	movem.l	d2-d7/a2-a6,-(sp)

	clr.b	display_active

	move.l	intuition_base,a6

	move.l	window,d0
	beq		.no_window

	clr.l	window
	move.l	d0,a0
	jsr		_LVOCloseWindow(a6)

.no_window:
	move.l	screen,d0
	beq		.no_screen

	clr.l	screen
	move.l	d0,a0
	jsr		_LVOCloseScreen(a6)

.no_screen:
	move.l	exec_base,a6

	move.l	pointer_data,d0
	beq		.no_pointer

	clr.l	pointer_data
	move.l	d0,a1
	moveq	#POINTER_SIZE,d0
	jsr		_LVOFreeMem(a6)

.no_pointer:
	lea		intuition_base,a2
	moveq	#3-1,d2

.close_libraries:
	move.l	(a2),d0
	beq		.next_library

	clr.l	(a2)
	move.l	d0,a1
	jsr		_LVOCloseLibrary(a6)

.next_library:
	addq.l	#4,a2

	dbf		d2,.close_libraries

	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
;
; Shows the rendered frame (task context).

present_frame:
	tst.b	display_active
	beq		.done

	movem.l	d2-d7/a2-a6,-(sp)

	tst.b	palette_changed
	beq		.palette_done

	sf		palette_changed

	ifd __RENDER_PROFILE__
	move.l	timer_base,a6
	lea		profile_time,a0
	jsr		-60(a6) ; ReadEClock
	endif

	move.l	graphics_base,a6
	move.l	screen,a0
	lea		sc_ViewPort(a0),a0
	move.l	palette_load_table,a1 ; All colours, or just the changed ones.
	jsr		_LVOLoadRGB32(a6)

	ifd __RENDER_PROFILE__
	move.l	profile_time+4,-(sp)
	move.l	timer_base,a6
	lea		profile_time,a0
	jsr		-60(a6)
	move.l	profile_time+4,d0
	sub.l	(sp)+,d0
	add.l	d0,load_rgb_time
	endif

.palette_done:
	ifd __NO_UPLOAD__
	movem.l	(sp)+,d2-d7/a2-a6
	rts
	endif

	move.l	picasso96_base,a6
	lea		render_info,a0
	moveq	#GUARD,d0
	move.l	source_y,d1
	move.l	window,a1
	move.l	wd_RPort(a1),a1
	moveq	#(SCREEN_WIDTH-PICTURE_WIDTH)/2,d2
	moveq	#0,d3
	move.l	#PICTURE_WIDTH,d4
	move.l	screen_height,d5
	jsr		_LVOp96WritePixelArray(a6)

	movem.l	(sp)+,d2-d7/a2-a6

.done:
	rts

; ------------------------------------------------------------------------------
;
; a0 = buffer for PICTURE_WIDTH x PICTURE_HEIGHT pixels. Reads the picture
; back from the screen (or from the render buffer when headless). Returns
; d0 = number of lines.

capture_screen:
	movem.l	d2-d7/a2-a6,-(sp)

	tst.b	display_active
	beq		.from_buffer

	lea		capture_info,a1
	move.l	a0,ri_Memory(a1)
	move	#PICTURE_WIDTH,ri_BytesPerRow(a1)
	move.l	#RGBFB_CLUT,ri_RGBFormat(a1)

	move.l	picasso96_base,a6
	move.l	a1,a0
	moveq	#0,d0
	moveq	#0,d1
	move.l	window,a1
	move.l	wd_RPort(a1),a1
	moveq	#(SCREEN_WIDTH-PICTURE_WIDTH)/2,d2
	moveq	#0,d3
	move.l	#PICTURE_WIDTH,d4
	move.l	screen_height,d5
	jsr		_LVOp96ReadPixelArray(a6)

	move.l	screen_height,d0

	bra		.done

.from_buffer:
	lea		render_buffer+GUARD*RENDER_STRIDE+GUARD,a1
	move	#PICTURE_HEIGHT-1,d1

.line_loop:
	moveq	#PICTURE_WIDTH/4-1,d2

.copy:
	move.l	(a1)+,(a0)+
	dbf		d2,.copy

	lea		RENDER_STRIDE-PICTURE_WIDTH(a1),a1

	dbf		d1,.line_loop

	move.l	#PICTURE_HEIGHT,d0

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

intuition_name:
	dc.b	'intuition.library',0
graphics_name:
	dc.b	'graphics.library',0
picasso96_name:
	dc.b	'Picasso96API.library',0

	even

mode_tags:
	dc.l	P96BIDTAG_NominalWidth,SCREEN_WIDTH
	dc.l	P96BIDTAG_NominalHeight
mode_tags_height:
	dc.l	PICTURE_HEIGHT
	dc.l	P96BIDTAG_Depth,8
	dc.l	P96BIDTAG_FormatsAllowed,RGBFF_CLUT
	dc.l	TAG_DONE

screen_tags:
	dc.l	SA_DisplayID
screen_tags_mode:
	dc.l	0
	dc.l	SA_Width,SCREEN_WIDTH
	dc.l	SA_Height
screen_tags_height:
	dc.l	PICTURE_HEIGHT
	dc.l	SA_Depth,8
	dc.l	SA_Type,CUSTOMSCREEN
	dc.l	SA_Quiet,-1
	dc.l	SA_ShowTitle,0
	dc.l	SA_Draggable,0
	dc.l	SA_Exclusive,-1
	dc.l	TAG_DONE

window_tags:
	dc.l	WA_CustomScreen
window_tags_screen:
	dc.l	0
	dc.l	WA_Width,SCREEN_WIDTH
	dc.l	WA_Height
window_tags_height:
	dc.l	PICTURE_HEIGHT
	dc.l	WA_Backdrop,-1
	dc.l	WA_Borderless,-1
	dc.l	WA_Activate,-1
	dc.l	WA_RMBTrap,-1
	dc.l	WA_SimpleRefresh,-1
	dc.l	WA_NoCareRefresh,-1
	dc.l	TAG_DONE

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

intuition_base: ; The three library bases stay together (close_display).
	ds.l	1
graphics_base:
	ds.l	1
picasso96_base:
	ds.l	1

screen:
	ds.l	1
window:
	ds.l	1
pointer_data:
	ds.l	1
screen_height:
	ds.l	1
source_y:
	ds.l	1

render_info:
	ds.b	RENDER_INFO_SIZE
capture_info:
	ds.b	RENDER_INFO_SIZE

display_active:
	ds.b	1

	even

	ifd __RENDER_PROFILE__
profile_time:
	ds.l	2
load_rgb_time:
	ds.l	1
	endif

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
