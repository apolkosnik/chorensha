
; Display output: an 8-bit RTG screen through Picasso96 or CyberGraphX, or a
; native AGA screen.
;
; The rendered 256 x 256 picture is centred on a 320 x 256 screen (or the
; middle 240 lines on a 320 x 240 RTG screen). Without a usable display the
; game runs headless: the renderer still composes frames and screenshots come
; from its buffer. -D__FORCE_CYBERGRAPHX__ uses the CyberGraphX calls on a
; Picasso96 system (its compatibility layer), -D__FORCE_AGA__ the AGA screen
; on a machine with an RTG board, to test those paths.
;
; AGA: a 320 x 256 x 8 PAL lores screen (interleaved bitplanes), triple
; buffered with ScreenBuffers: graphics.s draws each frame in planar form and
; copies it into the next bitmap (planar_copy_to_screen, through
; begin_planar_frame), or composes it in the chunky render buffer, which is
; then converted into the next bitmap (c2p), or has the blitter compose its
; background there while the game goes on and draws the rest later
; (pipelined_frame_target, flip_pipelined_frame); ChangeScreenBuffer() shows
; it at the next vertical blank. The bitmaps take turns, so the next one was
; left two flips ago: before each flip the safe message of the previous one
; (the bitmap shown before it may be drawn into) is awaited, and drawing
; never waits.

	xdef open_display
	xdef close_display
	xdef present_frame
	xdef capture_screen
	xdef display_active
	xdef update_fps_display
	xdef display_mode_request
	xdef graphics_base
	xdef planar_display_available
	xdef begin_planar_frame
	xdef pipelined_frame_target
	xdef flip_pipelined_frame

	xref fps_display
	xref rendered_frames
	xref total_vbl_count

	xref exec_base
	xref dos_base
	xref machine_display
	xref machine_rtg

	ifd __C2PLIB__
	xref machine_cpu
	xref _c2p_8x8_mexg
	xref _c2p_8x8_mexg_040
	endif
	xref render_buffer
	xref planar_copy_to_screen
	xref hardware_palette
	xref palette_load_table
	xref palette_changed

	ifd __RENDER_PROFILE__
	xref timer_base
	xdef load_rgb_time
	xdef c2p_time
	endif

; exec.library

_LVOOpenLibrary=-552
_LVOCloseLibrary=-414
_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOGetMsg=-372
_LVOWaitPort=-384
_LVOCreateMsgPort=-666
_LVODeleteMsgPort=-672

MEMF_CHIP=1<<1
MEMF_CLEAR=1<<16

; intuition.library

_LVOCloseScreen=-66
_LVOCloseWindow=-72
_LVOSetPointer=-270
_LVOOpenWindowTagList=-606
_LVOOpenScreenTagList=-612
_LVOAllocScreenBuffer=-768
_LVOFreeScreenBuffer=-774
_LVOChangeScreenBuffer=-780

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
SA_Interleaved=$80000042
CUSTOMSCREEN=15

PAL_MONITOR_ID=$00021000
LORES_KEY=$00000000

SB_SCREEN_BITMAP=1
sb_BitMap=0
sb_DBufInfo=4
dbi_SafeMessage=8
mn_ReplyPort=14

bm_BytesPerRow=0
bm_Depth=5
bm_Planes=8

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
_LVOWaitTOF=-270
_LVOInitRastPort=-198
_LVOText=-60
_LVOMove=-240
_LVORectFill=-306
_LVOSetAPen=-342
_LVOSetBPen=-348
_LVOSetDrMd=-354
_LVORawDoFmt=-522
_LVOFindDisplayInfo=-726
_LVOGetDisplayInfoData=-756
_LVOVPrintf=-954
DTAG_DISP=$80000000
DTAG_DIMS=$80001000
dis_NotAvailable=16 ; DisplayInfo (after its QueryHeader).
DISPLAY_INFO_SIZE=48
_LVOIsCyberModeID=-54
DTAG_NAME=$80003000
dim_MaxDepth=16 ; DimensionInfo (after its 16-byte QueryHeader).
dim_Nominal=26 ; struct Rectangle: MinX, MinY, MaxX, MaxY.
DIMENSION_INFO_SIZE=88
nif_Name=16 ; NameInfo.
NAME_INFO_SIZE=56
JAM2=1
_LVOReadPixelArray8=-780
_LVOAllocBitMap=-918
_LVOFreeBitMap=-924

RASTPORT_SIZE=100
rp_BitMap=4
rp_TxBaseline=62

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
BACKEND_AGA=3

; struct RenderInfo: Memory, BytesPerRow, pad, RGBFormat.

ri_Memory=0
ri_BytesPerRow=4
ri_RGBFormat=8
RENDER_INFO_SIZE=12

DISPLAY_RTG=1
DISPLAY_AGA=2
RTG_PICASSO96=1
RTG_CYBERGRAPHX=2

; Render buffer layout: must match graphics.s.

GUARD=16
PICTURE_WIDTH=256
PICTURE_HEIGHT=256
RENDER_STRIDE=GUARD+PICTURE_WIDTH+GUARD
SCREEN_WIDTH=320
POINTER_SIZE=16
AGA_DEPTH=8
SCREEN_BUFFERS=3
AGA_X_BYTES=(SCREEN_WIDTH-PICTURE_WIDTH)/2/8 ; Picture start in a plane row.

; Screenshots: from the picture's left edge; -D__CAPTURE_BORDER__ (test
; builds) from the screen's, to show the FPS counter in the left border.

	ifd __CAPTURE_BORDER__
CAPTURE_X=0
	else
CAPTURE_X=(SCREEN_WIDTH-PICTURE_WIDTH)/2
	endif

; FPS counter (` key): pictures shown per second, in the left border (the
; picture is centred on the screen), with the system font.

FPS_X=4
FPS_Y=1 ; Top of the text.
FPS_WIDTH=3*8 ; "nn" in the font's 8-pixel cells, and a space.
FPS_HEIGHT=8
FPS_TICKS=55 ; Recomputed about once a second.
FPS_TICK_HZ100=5546 ; The frame timer: 55.46 Hz.

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Opens the RTG screen if the machine has a Picasso96 board; otherwise the
; game runs headless. Returns nothing; display_active tells which.

open_display:
	movem.l	d2-d7/a2-a6,-(sp)

	clr.b	display_active

	ifd __FORCE_AGA__
	bra		.open_aga
	endif

	cmp.l	#DISPLAY_AGA,machine_display
	beq		.open_aga

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
	; Mode: the one asked for (MODE=<id>) if it suits, else the best for
	; 320 x 256 x 8, else 320 x 240.

	move.l	#PICTURE_HEIGHT,screen_height

	move.l	display_mode_request,d0
	beq		.find_mode

	bsr		check_mode
	tst.l	d0
	bmi		.find_mode ; Not usable: check_mode said why.

	move.l	d0,screen_height
	move.l	display_mode_request,d0

	bra		.mode_found

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
	bsr		print_mode

	move.l	intuition_base,a6
	sub.l	a0,a0
	lea		screen_tags,a1
	jsr		_LVOOpenScreenTagList(a6)
	move.l	d0,screen
	beq		.failed

.screen_open:
	move.l	screen_height,window_tags_height

	; Source rows: the middle screen_height lines of the picture.

	move.l	#PICTURE_HEIGHT,d0
	sub.l	screen_height,d0
	lsr.l	#1,d0
	add.l	#GUARD,d0
	move.l	d0,source_y

	move.l	intuition_base,a6
	move.l	screen,window_tags_screen
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

	cmp.l	#BACKEND_AGA,backend
	bne		.buffers_done

	bsr		open_screen_buffers
	tst.l	d0
	beq		.failed

.buffers_done:
	move.l	#hardware_palette,palette_load_table ; The whole palette first.
	st		palette_changed
	st		display_active

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

.failed:
	bsr		close_display

	bra		.done

	; Native AGA screen: PAL lores 320 x 256 x 8, else the default monitor.

.open_aga:
	move.l	#BACKEND_AGA,backend
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

	move.l	#PICTURE_HEIGHT,screen_height
	move.l	#PAL_MONITOR_ID|LORES_KEY,aga_screen_tags_mode

	move.l	intuition_base,a6
	sub.l	a0,a0
	lea		aga_screen_tags,a1
	jsr		_LVOOpenScreenTagList(a6)
	move.l	d0,screen
	bne		.screen_open

	move.l	#LORES_KEY,aga_screen_tags_mode
	sub.l	a0,a0
	lea		aga_screen_tags,a1
	jsr		_LVOOpenScreenTagList(a6)
	move.l	d0,screen
	beq		.failed

	bra		.screen_open

; ------------------------------------------------------------------------------
;
; AGA: the two ScreenBuffers (the screen's own bitmap and a second one), the
; port for their safe messages, and the plane layout for c2p. Returns d0 = 0
; on failure.

open_screen_buffers:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	exec_base,a6
	jsr		_LVOCreateMsgPort(a6)
	move.l	d0,safe_port
	beq		.failed

	move.l	intuition_base,a6
	move.l	screen,a0
	sub.l	a1,a1
	moveq	#SB_SCREEN_BITMAP,d0
	jsr		_LVOAllocScreenBuffer(a6)
	move.l	d0,screen_buffers
	beq		.failed

	move.l	screen,a0
	sub.l	a1,a1
	moveq	#0,d0
	jsr		_LVOAllocScreenBuffer(a6)
	move.l	d0,screen_buffers+4
	beq		.failed

	move.l	screen,a0
	sub.l	a1,a1
	moveq	#0,d0
	jsr		_LVOAllocScreenBuffer(a6)
	move.l	d0,screen_buffers+8
	beq		.failed

	; Safe messages to safe_port; all bitmaps must have 8 evenly spaced
	; planes (interleaved: one row of each plane after the other) with the
	; same layout.

	lea		screen_buffers,a2
	moveq	#SCREEN_BUFFERS-1,d4

.buffer_loop:
	move.l	(a2)+,a0
	move.l	sb_DBufInfo(a0),a1
	move.l	safe_port,dbi_SafeMessage+mn_ReplyPort(a1)

	move.l	sb_BitMap(a0),a1
	cmp.b	#AGA_DEPTH,bm_Depth(a1)
	bne		.failed

	moveq	#0,d0
	move	bm_BytesPerRow(a1),d0
	move.l	bm_Planes+4(a1),d1
	sub.l	bm_Planes(a1),d1 ; Plane spacing.

	cmp.l	#SCREEN_BUFFERS-1,d4
	bne		.compare_layout

	move.l	d0,plane_row_bytes
	move.l	d1,plane_spacing

.compare_layout:
	cmp.l	plane_row_bytes,d0
	bne		.failed

	cmp.l	plane_spacing,d1
	bne		.failed

	move.l	bm_Planes(a1),d2
	lea		bm_Planes+4(a1),a3
	moveq	#AGA_DEPTH-1-1,d3

.plane_loop:
	add.l	d1,d2
	cmp.l	(a3)+,d2
	bne		.failed

	dbf		d3,.plane_loop

	dbf		d4,.buffer_loop

	clr.l	shown_buffer ; Buffer 0 (the screen's bitmap) is shown.
	sf		safe_pending

	moveq	#1,d0

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

.failed:
	moveq	#0,d0

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
	bsr		close_screen_buffers

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

; AGA: show the screen's own bitmap again, then free the ScreenBuffers and
; the port.

close_screen_buffers:
	movem.l	d2-d7/a2-a6,-(sp)

	tst.l	screen_buffers
	beq		.free_port

	tst.l	shown_buffer
	beq		.free_others

	bsr		wait_until_safe

.show_first:
	move.l	intuition_base,a6
	move.l	screen,a0
	move.l	screen_buffers,a1
	jsr		_LVOChangeScreenBuffer(a6)
	tst.l	d0
	bne		.shown

	move.l	graphics_base,a6
	jsr		_LVOWaitTOF(a6)

	bra		.show_first

.shown:
	clr.l	shown_buffer
	st		safe_pending

.free_others:
	bsr		wait_until_safe

	lea		screen_buffers+SCREEN_BUFFERS*4,a2
	moveq	#SCREEN_BUFFERS-1,d2

.free_loop:
	move.l	-(a2),d0
	beq		.next_free

	clr.l	(a2)
	move.l	intuition_base,a6
	move.l	screen,a0
	move.l	d0,a1
	jsr		_LVOFreeScreenBuffer(a6)

.next_free:
	dbf		d2,.free_loop

.free_port:
	move.l	safe_port,d0
	beq		.done

	clr.l	safe_port
	move.l	exec_base,a6
	move.l	d0,a0
	jsr		_LVODeleteMsgPort(a6)

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; AGA: waits for the safe message of the last flip, if one is due.

wait_until_safe:
	tst.b	safe_pending
	beq		.done

	move.l	exec_base,a6

.loop:
	move.l	safe_port,a0
	jsr		_LVOGetMsg(a6)
	tst.l	d0
	bne		.received

	move.l	safe_port,a0
	jsr		_LVOWaitPort(a6)

	bra		.loop

.received:
	sf		safe_pending

.done:
	rts

; ------------------------------------------------------------------------------
;
; Shows the rendered frame (task context).

present_frame:
	tst.b	display_active
	beq		.done

	movem.l	d2-d7/a2-a6,-(sp)

	cmp.l	#BACKEND_AGA,backend
	beq		.aga

	bsr		load_palette

	ifd __NO_UPLOAD__
	movem.l	(sp)+,d2-d7/a2-a6
	rts
	endif

	cmp.l	#BACKEND_CYBERGRAPHX,backend
	beq		.cybergraphics_upload

	bra		.picasso96_upload

	; AGA: convert into the hidden bitmap (unless graphics.s has drawn the
	; frame into it), show it, then the palette (both take effect at the
	; next vertical blank).

.aga:
	tst.b	pipelined_frame
	beq		.not_pipelined

	sf		pipelined_frame ; Shown later (flip_pipelined_frame).

	bra		.uploaded

.not_pipelined:
	jsr		planar_copy_to_screen

	tst.b	planar_frame
	beq		.convert

	sf		planar_frame

	bra		.flip

.convert:
	bsr		next_screen_buffer
	move.l	sb_BitMap(a1),a1
	move.l	bm_Planes(a1),a1
	add.w	#AGA_X_BYTES,a1

	lea		render_buffer+GUARD,a0
	move.l	source_y,d0
	mulu	#RENDER_STRIDE,d0
	add.l	d0,a0

	move.l	plane_spacing,a2
	move.l	screen_height,d0
	move.l	plane_row_bytes,d1

	ifd __RENDER_PROFILE__
	movem.l	d0-d1/a0-a2,-(sp)
	move.l	timer_base,a6
	lea		profile_time,a0
	jsr		-60(a6) ; ReadEClock
	movem.l	(sp)+,d0-d1/a0-a2
	move.l	profile_time+4,c2p_start
	endif

	ifd __C2PLIB__
	bsr		c2p_c2plib
	else
	bsr		c2p
	endif

	ifd __RENDER_PROFILE__
	move.l	timer_base,a6
	lea		profile_time,a0
	jsr		-60(a6)
	move.l	profile_time+4,d0
	sub.l	c2p_start,d0
	add.l	d0,c2p_time
	endif

.flip:
	bsr		flip_screen_buffer

	bra		.uploaded


	; Picasso96: lock the screen's bitmap and copy the lines directly;
	; p96WritePixelArray when the bitmap cannot be locked.

.picasso96_upload:
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
; Planar rendering (graphics.s). Returns d0 = 1 if the AGA screen is open and
; its bitmaps have the layout graphics.s draws into (interleaved, 320-pixel
; rows of 8 planes, 256 lines), else 0.

planar_display_available:
	moveq	#0,d0
	tst.b	display_active
	beq		.done

	cmp.l	#BACKEND_AGA,backend
	bne		.done

	cmp.l	#SCREEN_WIDTH/8,plane_spacing
	bne		.done

	cmp.l	#SCREEN_WIDTH/8*AGA_DEPTH,plane_row_bytes
	bne		.done

	cmp.l	#PICTURE_HEIGHT,screen_height
	bne		.done

	moveq	#1,d0

.done:
	rts

; Waits until the hidden bitmap may be drawn into and returns d0 = the
; picture's top left in its plane 0; present_frame then shows it as it is.
; Preserves all other registers.

begin_planar_frame:
	movem.l	d1/a0-a1,-(sp)

	bsr		next_screen_buffer
	move.l	sb_BitMap(a1),a1
	move.l	bm_Planes(a1),d0
	addq.l	#AGA_X_BYTES,d0

	st		planar_frame

	movem.l	(sp)+,d1/a0-a1

	rts

; graphics.s, pipelined frames: returns d0 = the picture's top left in plane
; 0 of the next bitmap, which the blitter and graphics.s draw into while the
; game goes on; present_frame leaves it to flip_pipelined_frame. Preserves
; all other registers.

pipelined_frame_target:
	movem.l	d1/a0-a1,-(sp)

	bsr		next_screen_buffer
	move.l	sb_BitMap(a1),a1
	move.l	bm_Planes(a1),d0
	addq.l	#AGA_X_BYTES,d0

	st		pipelined_frame

	movem.l	(sp)+,d1/a0-a1

	rts

; graphics.s: shows the pipelined frame's bitmap and its palette (task
; context). Preserves all registers.

flip_pipelined_frame:
	movem.l	d0-d7/a0-a6,-(sp)

	bsr		flip_screen_buffer

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; Returns d0 = the picture's top left in plane 0 of the shown bitmap (test
; builds). Preserves all other registers.

; a1 = hidden_screen_buffer = the ScreenBuffer after the shown one, d1 =
; its number (also in hidden_buffer_number). Uses a0.

next_screen_buffer:
	move.l	shown_buffer,d1
	addq.l	#1,d1
	cmp.l	#SCREEN_BUFFERS,d1
	bne		.number_ok

	moveq	#0,d1

.number_ok:
	move.l	d1,hidden_buffer_number
	lea		screen_buffers,a0
	move.l	(a0,d1.l*4),a1
	move.l	a1,hidden_screen_buffer

	rts

; Shows hidden_screen_buffer once the previous flip has taken effect, then
; loads the palette (both at the next vertical blank). If the screen is busy
; the bitmap is not shown (drawn again next frame).

flip_screen_buffer:
	bsr		wait_until_safe

	move.l	intuition_base,a6
	move.l	screen,a0
	move.l	hidden_screen_buffer,a1
	jsr		_LVOChangeScreenBuffer(a6)
	tst.l	d0
	beq		.not_shown

	move.l	hidden_buffer_number,shown_buffer
	st		safe_pending

.not_shown:
	bra		load_palette

; ------------------------------------------------------------------------------
;
; Loads the palette changes into the screen (all colours or a range).

load_palette:
	tst.b	palette_changed
	beq		.done

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

	cmp.l	#BACKEND_AGA,backend
	beq		.aga_capture

	cmp.l	#BACKEND_CYBERGRAPHX,backend
	bne		.picasso96_capture

	move.l	temporary_bitmap,d0
	beq		.from_buffer

	move.l	a0,a2 ; Destination.
	move.l	graphics_base,a6
	move.l	window,a0
	move.l	wd_RPort(a0),a0
	moveq	#CAPTURE_X,d0
	moveq	#0,d1
	move.l	#CAPTURE_X+PICTURE_WIDTH-1,d2
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
	moveq	#CAPTURE_X,d2
	moveq	#0,d3
	move.l	#PICTURE_WIDTH,d4
	move.l	screen_height,d5
	jsr		_LVOp96ReadPixelArray(a6)

	move.l	screen_height,d0

	bra		.done

	; AGA: the shown bitmap's planes back to chunky pixels.

.aga_capture:
	move.l	shown_buffer,d0
	lea		screen_buffers,a1
	move.l	(a1,d0.l*4),a1
	move.l	sb_BitMap(a1),a1
	move.l	bm_Planes(a1),a3
	add.w	#CAPTURE_X/8,a3 ; Plane 0, first row.
	move.l	plane_spacing,a4
	move.l	screen_height,d7
	subq	#1,d7

.capture_row:
	move.l	a3,a1
	moveq	#PICTURE_WIDTH/8-1,d6

.capture_byte:
	move.l	a1,a5
	lea		capture_bytes,a6
	moveq	#AGA_DEPTH-1,d5

.gather:
	move.b	(a5),(a6)+
	add.l	a4,a5
	dbf		d5,.gather

	moveq	#8-1,d4

.capture_pixel:
	moveq	#0,d0
	lea		capture_bytes+AGA_DEPTH,a6
	moveq	#AGA_DEPTH-1,d5

.capture_bit:
	move.b	-(a6),d1 ; Plane 7 first.
	add.b	d1,d1
	move.b	d1,(a6) ; (MOVE leaves X alone.)
	addx.b	d0,d0
	dbf		d5,.capture_bit

	move.b	d0,(a0)+

	dbf		d4,.capture_pixel

	addq.l	#1,a1

	dbf		d6,.capture_byte

	add.l	plane_row_bytes,a3

	dbf		d7,.capture_row

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
;
; Chunky to planar, 8 planes: a0 = chunky pixels (rows RENDER_STRIDE apart,
; PICTURE_WIDTH wide), a1 = first byte in plane 0, a2 = distance between
; planes, d0 = rows, d1 = bytes per plane row.
;
; 32 pixels at a time: the eight longs (four pixels each) go through five
; merge stages, a transposition of the 32 x 8 bit matrix:
;   shift 16, then 2: register pairs (n, n + 4)
;   shift 8, then 1: pairs (n, n + 2)
;   shift 4: pairs (n, n + 1)
; after which planes 0-7 are in d7, d5, d3, d1, d6, d4, d2, d0 (checked
; against a model of the sequence on random data). A merge needs a spare
; data register: the one waiting for a later pair is parked in a6 (the
; 16-bit stage only exchanges words, through a6).

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

MERGE16 macro ; MERGE a, b, 16, $0000ffff with word moves: a = a.high:b.high,
	swap	\2 ; b = a.low:b.low. The spare can be an address register (only
	move.w	\1,\3 ; its low word is used).
	move.w	\2,\1
	move.w	\3,\2
	swap	\2
	endm

c2p:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	d0,c2p_rows
	move.l	d1,c2p_row_bytes
	move.l	a1,a3

.row:
	move.l	a3,a1
	lea		PICTURE_WIDTH(a0),a5

.block:
	movem.l	(a0)+,d0-d7

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

	move.l	a1,a4
	move.l	d7,(a4) ; Plane 0.
	add.l	a2,a4
	move.l	d5,(a4)
	add.l	a2,a4
	move.l	d3,(a4)
	add.l	a2,a4
	move.l	d1,(a4)
	add.l	a2,a4
	move.l	d6,(a4)
	add.l	a2,a4
	move.l	d4,(a4)
	add.l	a2,a4
	move.l	d2,(a4)
	add.l	a2,a4
	move.l	d0,(a4) ; Plane 7.

	addq.l	#4,a1
	cmp.l	a5,a0
	bne		.block

	lea		RENDER_STRIDE-PICTURE_WIDTH(a0),a0
	add.l	c2p_row_bytes,a3
	subq.l	#1,c2p_rows
	bne		.row

	movem.l	(sp)+,d2-d7/a2-a6

	rts

	ifd __C2PLIB__

; The same conversion through c2plib (Aminet dev/misc/c2plib.lha, MIT
; licence, sources in c2plib/), for comparison (-D__C2PLIB__). Its routines
; take contiguous chunky rows, so each picture row is converted on its own:
; 68020/68030 in two passes through a scrambled buffer, 68040/68060 in one.
; Same arguments as c2p.

c2p_c2plib:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	d0,d6 ; Rows.
	move.l	d1,d7 ; Bytes per plane row.
	move.l	a2,d5 ; Plane spacing.
	move.l	a0,a3
	move.l	a1,a4

.row:
	move.l	a3,a0
	move.l	a4,a1
	move.l	#PICTURE_WIDTH,d0
	move.l	d5,d1
	moveq	#PICTURE_WIDTH/8,d2
	moveq	#0,d3 ; One row, as a non-interleaved block.

	cmp.l	#40,machine_cpu
	bcc		.one_pass

	lea		c2plib_scrambled,a2
	jsr		_c2p_8x8_mexg

	bra		.next_row

.one_pass:
	jsr		_c2p_8x8_mexg_040

.next_row:
	lea		RENDER_STRIDE(a3),a3
	add.l	d7,a4

	subq.l	#1,d6
	bne		.row

	movem.l	(sp)+,d2-d7/a2-a6

	rts

	endif

; ------------------------------------------------------------------------------
;
; MODE=<id> (main.s): d0.l = the display ID. Returns d0.l = the screen
; height to use (256, or 240 for a mode with fewer lines), or -1 if the
; mode cannot be used (unknown, not 8 bits deep: the picture is uploaded as
; palette indices, or smaller than 320 x 240); then says why.

check_mode:
	movem.l	d2-d3/a2/a6,-(sp)

	move.l	d0,d3
	move.l	graphics_base,a6
	jsr		_LVOFindDisplayInfo(a6)
	move.l	#mode_unknown_text,d2
	tst.l	d0
	beq		.refused

	move.l	d0,a2 ; Handle.

	; A graphics card's mode (the picture is uploaded to the card), and
	; available.

	move.l	a2,a0
	lea		display_info,a1
	move.l	#DISPLAY_INFO_SIZE,d0
	move.l	#DTAG_DISP,d1
	move.l	d3,d2
	jsr		_LVOGetDisplayInfoData(a6)
	move.l	#mode_unknown_text,d2
	tst.l	d0
	beq		.refused

	lea		display_info,a0
	move.l	#mode_unavailable_text,d2
	tst		dis_NotAvailable(a0)
	bne		.refused

	; A graphics card's mode: cybergraphics.library (CyberGraphX, or
	; Picasso96's compatible one) knows it. (Picasso96 does not mark its
	; modes DIPF_IS_FOREIGN.) Without that library this is not checked.

	move.l	exec_base,a6
	lea		cybergraphics_name,a1
	moveq	#40,d0
	jsr		_LVOOpenLibrary(a6)
	tst.l	d0
	beq		.card_checked

	move.l	d0,a6
	move.l	d3,d0
	jsr		_LVOIsCyberModeID(a6)
	move.l	d0,-(sp)
	move.l	a6,a1
	move.l	exec_base,a6
	jsr		_LVOCloseLibrary(a6)
	move.l	(sp)+,d0
	move.l	graphics_base,a6
	move.l	#mode_native_text,d2
	tst		d0
	beq		.refused

.card_checked:
	move.l	graphics_base,a6

	move.l	a2,a0
	lea		dimension_info,a1
	move.l	#DIMENSION_INFO_SIZE,d0
	move.l	#DTAG_DIMS,d1
	move.l	d3,d2
	jsr		_LVOGetDisplayInfoData(a6)
	move.l	#mode_unknown_text,d2
	tst.l	d0
	beq		.refused

	lea		dimension_info,a2
	move.l	#mode_depth_text,d2
	cmp		#8,dim_MaxDepth(a2)
	bne		.refused

	move.l	#mode_size_text,d2
	move	dim_Nominal+4(a2),d0 ; MaxX - MinX + 1
	sub		dim_Nominal(a2),d0
	addq	#1,d0
	cmp		#SCREEN_WIDTH,d0
	bcs		.refused

	move	dim_Nominal+6(a2),d0
	sub		dim_Nominal+2(a2),d0
	addq	#1,d0
	cmp		#240,d0
	bcs		.refused

	move.l	#PICTURE_HEIGHT,d1
	cmp		#PICTURE_HEIGHT,d0
	bcc		.height_set

	move.l	#240,d1

.height_set:
	move.l	d1,d0

	bra		.done

.refused:
	move.l	d3,mode_print_arguments
	move.l	d2,mode_print_arguments+4
	move.l	dos_base,a6
	move.l	#mode_refused_format,d1
	move.l	#mode_print_arguments,d2
	jsr		_LVOVPrintf(a6)
	moveq	#-1,d0

.done:
	movem.l	(sp)+,d2-d3/a2/a6

	rts

; The RTG mode in use: "Screen mode: <name> ($id), 320 x <height>."
; screen_tags_mode = the display ID. Preserves all registers.

print_mode:
	movem.l	d0-d3/a0-a1/a6,-(sp)

	lea		name_info+nif_Name,a0
	move.b	#'?',(a0)+
	clr.b	(a0)

	move.l	graphics_base,a6
	move.l	screen_tags_mode,d0
	jsr		_LVOFindDisplayInfo(a6)
	tst.l	d0
	beq		.print

	move.l	d0,a0
	lea		name_info,a1
	move.l	#NAME_INFO_SIZE,d0
	move.l	#DTAG_NAME,d1
	move.l	screen_tags_mode,d2
	jsr		_LVOGetDisplayInfoData(a6)

.print:
	move.l	#name_info+nif_Name,mode_print_arguments
	move.l	screen_tags_mode,mode_print_arguments+4
	move.l	screen_height,mode_print_arguments+8
	move.l	dos_base,a6
	move.l	#mode_format,d1
	move.l	#mode_print_arguments,d2
	jsr		_LVOVPrintf(a6)

	movem.l	(sp)+,d0-d3/a0-a1/a6

	rts

; ------------------------------------------------------------------------------
;
; FPS counter: at each frame end (task context, OS stack). While it is on
; (fps_display, the ` key), the pictures shown per second are recomputed
; about once a second and drawn at the top of the left border; when it is
; turned off, the area is cleared. Only the picture is ever drawn over, so
; the text stays (on AGA it is drawn into both screen buffers). Preserves
; all registers.

update_fps_display:
	movem.l	d0-d7/a0-a6,-(sp)

	tst.b	display_active
	beq		.done

	move.b	fps_display,d0
	cmp.b	fps_shown,d0
	beq		.same_state

	move.b	d0,fps_shown
	tst.b	d0
	beq		.clear

	; Turned on: start counting, show "--" until the first second.

	move.l	total_vbl_count,fps_tick
	move.l	rendered_frames,fps_frames
	lea		fps_wait_text,a0
	bsr		draw_fps_text

	bra		.done

.clear:
	lea		fps_clear_text,a0
	bsr		draw_fps_text

	bra		.done

.same_state:
	tst.b	d0
	beq		.done

	move.l	total_vbl_count,d1
	sub.l	fps_tick,d1 ; Ticks.
	cmp.l	#FPS_TICKS,d1
	bcs		.done

	; Pictures * timer rate / ticks, rounded.

	move.l	rendered_frames,d0
	sub.l	fps_frames,d0
	mulu.l	#FPS_TICK_HZ100,d0
	move.l	d1,d2
	mulu.l	#100,d2
	move.l	d2,d3
	lsr.l	#1,d3
	add.l	d3,d0
	divu.l	d2,d0
	cmp.l	#99,d0
	bls		.value_set

	moveq	#99,d0

.value_set:
	move.l	d0,fps_arguments
	add.l	d1,fps_tick
	move.l	rendered_frames,fps_frames

	lea		fps_format,a0
	lea		fps_arguments,a1
	lea		.put_char(pc),a2
	lea		fps_text,a3
	move.l	exec_base,a6
	jsr		_LVORawDoFmt(a6)

	lea		fps_text,a0
	bsr		draw_fps_text

.done:
	movem.l	(sp)+,d0-d7/a0-a6

	rts

.put_char:
	move.b	d0,(a3)+

	rts

; a0 = text (3 characters): drawn at the counter's place, in the brightest
; palette colour on colour 0 (the border's), into the shown screen (RTG:
; through the window) or both screen buffers (AGA).

draw_fps_text:
	movem.l	d2-d4/a2-a3/a6,-(sp)

	move.l	a0,a3

	; The brightest colour: the largest R + G + B (LoadRGB32 table).

	lea		hardware_palette+4,a0
	moveq	#0,d2 ; Best sum.
	moveq	#1,d3 ; Its pen.
	moveq	#0,d4 ; Pen.

.palette_loop:
	moveq	#0,d0
	moveq	#0,d1
	move.b	(a0),d1
	add.l	d1,d0
	move.b	4(a0),d1
	add.l	d1,d0
	move.b	8(a0),d1
	add.l	d1,d0
	lea		12(a0),a0
	cmp.l	d2,d0
	bls		.not_brighter

	move.l	d0,d2
	move.l	d4,d3

.not_brighter:
	addq	#1,d4
	cmp		#256,d4
	bne		.palette_loop

	move.l	d3,fps_pen

	cmp.l	#BACKEND_AGA,backend
	beq		.aga

	move.l	window,a0
	move.l	wd_RPort(a0),a2
	bsr		.draw

	bra		.done

.aga:
	; Into all the buffers' bitmaps, through a RastPort of its own.

	moveq	#0,d4

.buffer_loop:
	move.l	graphics_base,a6
	lea		fps_rastport,a1
	jsr		_LVOInitRastPort(a6)
	lea		screen_buffers,a0
	move.l	(a0,d4.l*4),d0
	beq		.next_buffer

	move.l	d0,a0
	lea		fps_rastport,a2
	move.l	sb_BitMap(a0),rp_BitMap(a2)
	bsr		.draw

.next_buffer:
	addq.l	#1,d4
	cmp.l	#SCREEN_BUFFERS,d4
	bne		.buffer_loop

.done:
	movem.l	(sp)+,d2-d4/a2-a3/a6

	rts

; a2 = RastPort, a3 = text.

.draw:
	move.l	graphics_base,a6
	move.l	a2,a1
	moveq	#JAM2,d0
	jsr		_LVOSetDrMd(a6)
	move.l	a2,a1
	move.l	fps_pen,d0
	jsr		_LVOSetAPen(a6)
	move.l	a2,a1
	moveq	#0,d0
	jsr		_LVOSetBPen(a6)
	move.l	a2,a1
	moveq	#FPS_X,d0
	moveq	#0,d1
	move	rp_TxBaseline(a2),d1
	add		#FPS_Y,d1
	jsr		_LVOMove(a6)
	move.l	a2,a1
	move.l	a3,a0
	moveq	#3,d0
	jmp		_LVOText(a6)

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

aga_screen_tags:
	dc.l	SA_DisplayID
aga_screen_tags_mode:
	dc.l	PAL_MONITOR_ID|LORES_KEY
	dc.l	SA_Width,SCREEN_WIDTH
	dc.l	SA_Height,PICTURE_HEIGHT
	dc.l	SA_Depth,AGA_DEPTH
	dc.l	SA_Interleaved,-1
	dc.l	SA_Type,CUSTOMSCREEN
	dc.l	SA_Quiet,-1
	dc.l	SA_ShowTitle,0
	dc.l	SA_Draggable,0
	dc.l	SA_Exclusive,-1
	dc.l	TAG_DONE

mode_format:
	dc.b	'Screen mode: %s (mode $%08lx), 320 x %ld.',10,0
mode_refused_format:
	dc.b	'MODE=$%08lx cannot be used (%s): the best mode is used instead.',10,0
mode_unknown_text:
	dc.b	'no such mode',0
mode_unavailable_text:
	dc.b	'not available',0
mode_native_text:
	dc.b	'not a graphics card mode',0
mode_depth_text:
	dc.b	'not an 8-bit mode',0
mode_size_text:
	dc.b	'smaller than 320 x 240',0

fps_format:
	dc.b	'%2ld ',0
fps_wait_text:
	dc.b	'-- ',0
fps_clear_text:
	dc.b	'   ',0

	even

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

fps_rastport:
	ds.b	RASTPORT_SIZE

display_mode_request:
	ds.l	1 ; MODE=<id> (main.s), or 0.
mode_print_arguments:
	ds.l	3
display_info:
	ds.b	DISPLAY_INFO_SIZE
dimension_info:
	ds.b	DIMENSION_INFO_SIZE
name_info:
	ds.b	NAME_INFO_SIZE

fps_tick:
	ds.l	1 ; Frame timer tick at the last count.
fps_frames:
	ds.l	1 ; Pictures shown then.
fps_pen:
	ds.l	1
fps_arguments:
	ds.l	1
fps_text:
	ds.b	8
fps_shown:
	ds.b	1

	even

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

; AGA.

safe_port:
	ds.l	1
screen_buffers: ; The screen's own bitmap, then the others.
	ds.l	SCREEN_BUFFERS
shown_buffer: ; Its number.
	ds.l	1
hidden_screen_buffer: ; The next one to show.
	ds.l	1
hidden_buffer_number:
	ds.l	1
plane_row_bytes:
	ds.l	1
plane_spacing:
	ds.l	1
c2p_rows:
	ds.l	1
c2p_row_bytes:
	ds.l	1
capture_bytes:
	ds.b	AGA_DEPTH

	ifd __C2PLIB__
	cnop	0,4
c2plib_scrambled: ; One row.
	ds.b	PICTURE_WIDTH
	endif
planar_frame: ; graphics.s has drawn this frame into the hidden bitmap.
	ds.b	1
pipelined_frame: ; The frame is drawn and shown later (flip_pipelined_frame).
	ds.b	1
safe_pending:
	ds.b	1

display_active:
	ds.b	1

	even

	ifd __RENDER_PROFILE__
profile_time:
	ds.l	2
load_rgb_time:
	ds.l	1
c2p_time: ; E clock ticks in c2p, all frames.
	ds.l	1
c2p_start:
	ds.l	1
	endif

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
