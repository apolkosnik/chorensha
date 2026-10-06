
; Display output: an 8-bit RTG screen through Picasso96 or CyberGraphX.
;
; The rendered 256 x 256 picture is centred on a 320 x 256 screen (or the
; middle 240 lines on a 320 x 240 screen). Without a usable RTG board (native
; AGA output is a later phase) the game runs headless: the renderer still
; composes frames and screenshots come from its buffer. -D__FORCE_CYBERGRAPHX__
; uses the CyberGraphX calls on a Picasso96 system (its compatibility layer),
; to test that path.

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
_LVOInitRastPort=-198
_LVOReadPixelArray8=-780
_LVOAllocBitMap=-918
_LVOFreeBitMap=-924

RASTPORT_SIZE=100
rp_BitMap=4

; Picasso96API.library

_LVOp96BestModeIDTagList=-60
_LVOp96LockBitMap=-48
_LVOp96UnlockBitMap=-54
_LVOp96WritePixelArray=-102
_LVOp96ReadPixelArray=-108

P96BIDTAG_FormatsAllowed=$80000061
P96BIDTAG_NominalWidth=$80000063
P96BIDTAG_NominalHeight=$80000064
P96BIDTAG_Depth=$80000065
RGBFB_CLUT=1
RGBFF_CLUT=1<<RGBFB_CLUT
INVALID_ID=-1

; cybergraphics.library

_LVOBestCModeIDTagList=-60
_LVOWritePixelArray=-126

CYBRBIDTG_Depth=$80050000
CYBRBIDTG_NominalWidth=$80050001
CYBRBIDTG_NominalHeight=$80050002
RECTFMT_LUT8=3

BACKEND_PICASSO96=1
BACKEND_CYBERGRAPHX=2

; struct RenderInfo: Memory, BytesPerRow, pad, RGBFormat.

ri_Memory=0
ri_BytesPerRow=4
ri_RGBFormat=8
RENDER_INFO_SIZE=12

DISPLAY_RTG=1
RTG_PICASSO96=1
RTG_CYBERGRAPHX=2

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

	move.l	#BACKEND_PICASSO96,backend
	cmp.l	#RTG_PICASSO96,machine_rtg
	beq		.backend_chosen

	move.l	#BACKEND_CYBERGRAPHX,backend
	cmp.l	#RTG_CYBERGRAPHX,machine_rtg
	bne		.done

.backend_chosen:
	ifd __FORCE_CYBERGRAPHX__
	move.l	#BACKEND_CYBERGRAPHX,backend
	endif

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

	cmp.l	#BACKEND_CYBERGRAPHX,backend
	beq		.open_cybergraphics

	lea		picasso96_name,a1
	moveq	#2,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,picasso96_base
	beq		.failed

	bra		.library_open

.open_cybergraphics:
	lea		cybergraphics_name,a1
	moveq	#40,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,cybergraphics_base
	beq		.failed

.library_open:
	; Mode: 320 x 256 x 8, else 320 x 240.

	move.l	#PICTURE_HEIGHT,screen_height

.find_mode:
	cmp.l	#BACKEND_CYBERGRAPHX,backend
	beq		.find_cybergraphics_mode

	move.l	screen_height,mode_tags_height
	move.l	picasso96_base,a6
	lea		mode_tags,a0
	jsr		_LVOp96BestModeIDTagList(a6)

	bra		.mode_checked

.find_cybergraphics_mode:
	move.l	screen_height,cybergraphics_mode_tags_height
	move.l	cybergraphics_base,a6
	lea		cybergraphics_mode_tags,a0
	jsr		_LVOBestCModeIDTagList(a6)

.mode_checked:
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
	; Screenshots on CyberGraphX: its ReadPixelArray reads RGB formats only,
	; so graphics.library ReadPixelArray8 is used, which needs a temporary
	; RastPort with a one-line bitmap.

	cmp.l	#BACKEND_CYBERGRAPHX,backend
	bne		.no_temporary

	move.l	graphics_base,a6
	move.l	#PICTURE_WIDTH,d0
	moveq	#1,d1
	moveq	#8,d2
	moveq	#0,d3
	sub.l	a0,a0
	jsr		_LVOAllocBitMap(a6)
	move.l	d0,temporary_bitmap
	beq		.no_temporary

	lea		temporary_rastport,a1
	jsr		_LVOInitRastPort(a6)
	move.l	temporary_bitmap,temporary_rastport+rp_BitMap

.no_temporary:
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
	move.l	temporary_bitmap,d0
	beq		.no_temporary

	clr.l	temporary_bitmap
	move.l	d0,a0
	move.l	graphics_base,a6
	jsr		_LVOFreeBitMap(a6)

.no_temporary:
	move.l	exec_base,a6

	move.l	pointer_data,d0
	beq		.no_pointer

	clr.l	pointer_data
	move.l	d0,a1
	moveq	#POINTER_SIZE,d0
	jsr		_LVOFreeMem(a6)

.no_pointer:
	lea		intuition_base,a2
	moveq	#4-1,d2

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

	cmp.l	#BACKEND_CYBERGRAPHX,backend
	beq		.cybergraphics_upload

	; Picasso96: lock the screen's bitmap and copy the lines directly;
	; p96WritePixelArray when the bitmap cannot be locked.

	move.l	picasso96_base,a6
	move.l	window,a0
	move.l	wd_RPort(a0),a0
	move.l	rp_BitMap(a0),a5
	move.l	a5,a0
	lea		lock_info,a1
	moveq	#RENDER_INFO_SIZE,d0
	jsr		_LVOp96LockBitMap(a6)
	move.l	d0,d7
	beq		.write_pixel_array

	move.l	lock_info+ri_Memory,d0
	beq		.unlock

	move.l	d0,a1
	add.w	#(SCREEN_WIDTH-PICTURE_WIDTH)/2,a1
	move	lock_info+ri_BytesPerRow,d2
	ext.l	d2
	sub.l	#PICTURE_WIDTH,d2

	lea		render_buffer+GUARD,a0
	move.l	source_y,d0
	mulu	#RENDER_STRIDE,d0
	add.l	d0,a0

	move.l	screen_height,d1
	subq	#1,d1

.line_loop:
	rept	PICTURE_WIDTH/4
	move.l	(a0)+,(a1)+
	endr

	lea		RENDER_STRIDE-PICTURE_WIDTH(a0),a0
	add.l	d2,a1

	dbf		d1,.line_loop

.unlock:
	move.l	a5,a0
	move.l	d7,d0
	jsr		_LVOp96UnlockBitMap(a6)

	bra		.uploaded

.write_pixel_array:
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

	bra		.uploaded

.cybergraphics_upload:
	move.l	cybergraphics_base,a6
	lea		render_buffer,a0
	moveq	#GUARD,d0
	move.l	source_y,d1
	move.l	#RENDER_STRIDE,d2
	move.l	window,a1
	move.l	wd_RPort(a1),a1
	moveq	#(SCREEN_WIDTH-PICTURE_WIDTH)/2,d3
	moveq	#0,d4
	move.l	#PICTURE_WIDTH,d5
	move.l	screen_height,d6
	moveq	#RECTFMT_LUT8,d7
	jsr		_LVOWritePixelArray(a6)

.uploaded:
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

	cmp.l	#BACKEND_CYBERGRAPHX,backend
	bne		.picasso96_capture

	move.l	temporary_bitmap,d0
	beq		.from_buffer

	move.l	a0,a2 ; Destination.
	move.l	graphics_base,a6
	move.l	window,a0
	move.l	wd_RPort(a0),a0
	moveq	#(SCREEN_WIDTH-PICTURE_WIDTH)/2,d0
	moveq	#0,d1
	move.l	#(SCREEN_WIDTH-PICTURE_WIDTH)/2+PICTURE_WIDTH-1,d2
	move.l	screen_height,d3
	subq.l	#1,d3
	lea		temporary_rastport,a1
	jsr		_LVOReadPixelArray8(a6)

	move.l	screen_height,d0

	bra		.done

.picasso96_capture:
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
cybergraphics_name:
	dc.b	'cybergraphics.library',0

	even

mode_tags:
	dc.l	P96BIDTAG_NominalWidth,SCREEN_WIDTH
	dc.l	P96BIDTAG_NominalHeight
mode_tags_height:
	dc.l	PICTURE_HEIGHT
	dc.l	P96BIDTAG_Depth,8
	dc.l	P96BIDTAG_FormatsAllowed,RGBFF_CLUT
	dc.l	TAG_DONE

cybergraphics_mode_tags:
	dc.l	CYBRBIDTG_NominalWidth,SCREEN_WIDTH
	dc.l	CYBRBIDTG_NominalHeight
cybergraphics_mode_tags_height:
	dc.l	PICTURE_HEIGHT
	dc.l	CYBRBIDTG_Depth,8
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

intuition_base: ; The four library bases stay together (close_display).
	ds.l	1
graphics_base:
	ds.l	1
picasso96_base:
	ds.l	1
cybergraphics_base:
	ds.l	1

backend:
	ds.l	1
temporary_bitmap:
	ds.l	1
temporary_rastport:
	ds.b	RASTPORT_SIZE

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

lock_info: ; Filled by p96LockBitMap.
	ds.b	RENDER_INFO_SIZE

	even

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
