
; Input: joystick (port 2) and CD32 pad through lowlevel.library, keyboard
; through an input.device handler, and scripted input for automated tests.
;
; The game reads the joystick with IOCS _JOYGET (X68000 bits, active low:
; 0 up, 1 down, 2 left, 3 right, 5 trigger A, 6 trigger B) and the keyboard
; with _BITSNS (X68000 key matrix, 16 groups of 8 scancodes). Both answer with
; the current state, as the X68000 hardware does: the game also polls them in
; loops that complete no frame (the name entry after a game over waits there
; for the buttons to be released). The keyboard is kept up to date by the
; input.device handler, the joystick is read on every frame timer tick
; (input_tick); only scripted input advances with the game's frames. Keys also drive
; the joystick bits, as in the Falcon port:
;
;   cursor keys          joystick directions
;   CTRL, Z              trigger A          (fire 1 / red button)
;   SHIFT (either), X    trigger B          (fire 2 / blue button)
;   ESC, 1, TAB, SHIFT, CTRL, RETURN, SPACE, cursor keys   X68000 key matrix
;   P                    X68000 ESC (the game's pause, as ESC)
;   M                    mouse control on / off
;
; Auto fire: the game fires a volley when trigger A goes down (from one
; frame to the next), so holding it fires once. In a stage, a held trigger
; A is released and pressed again every AUTOFIRE_FRAMES game frames (about
; 14 presses per second), whatever holds it (joystick, keys, mouse, script);
; menus see it held as it is.
;
; Mouse control (M), relative: in a stage the mouse's movement (raw counts,
; one pixel each) moves an invisible target, which starts at the ship and
; stays within the ship's area; each frame the joystick directions point
; from the ship to the target, outside a dead zone of MOUSE_DEAD_ZONE
; pixels, so the ship follows the mouse at its normal speed and stops when
; the mouse stops. The left mouse button is trigger A, the right one trigger
; B. Outside a stage (menus) only the buttons count. "mouse on" /
; "mouse off" is shown for MOUSE_MESSAGE_TICKS where the game shows "pause"
; (DRAW_TEXT, from the frame end: mouse_frame_hook).

	xdef initialize_input
	xdef release_input
	xdef update_input
	xdef mouse_frame_hook
	xdef mouse_mode
	xdef amiga_stage_frame
	xdef input_tick
	xdef joystick_now

	xdef iocs_joystick_data
	xdef keyboard_matrix

	xref exec_base
	xref dos_base
	xref frame_count
	xref total_vbl_count
	xref WORD_00098864
	xref DRAW_TEXT

; exec.library

_LVOOpenLibrary=-552
_LVOCloseLibrary=-414
_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOOpenDevice=-444
_LVOCloseDevice=-450
_LVODoIO=-456
_LVOCreateMsgPort=-666
_LVODeleteMsgPort=-672
_LVOCreateIORequest=-654
_LVODeleteIORequest=-660

MEMF_ANY=0

NT_INTERRUPT=2
ln_Type=8
ln_Pri=9
ln_Name=10
is_Data=14
is_Code=18
IS_SIZE=22

; input.device

IND_ADDHANDLER=9
IND_REMHANDLER=10
io_Command=28
io_Data=40
IOSTD_SIZE=48

INPUT_HANDLER_PRIORITY=51 ; Before Intuition (50).

ie_NextEvent=0
ie_Class=4
ie_Code=6
ie_X=10
ie_Y=12
IECLASS_RAWKEY=1
IECODE_UP_PREFIX=$80

; lowlevel.library

_LVOReadJoyPort=-30

JOYSTICK_PORT=1 ; Game port 2.
JP_TYPE_MASK=$f0000000
JP_TYPE_NOTAVAIL=$00000000
JP_TYPE_GAMECTLR=$10000000
JP_TYPE_JOYSTK=$30000000
JPB_BUTTON_BLUE=23
JPB_BUTTON_RED=22
JPB_JOY_UP=3
JPB_JOY_DOWN=2
JPB_JOY_LEFT=1
JPB_JOY_RIGHT=0

; dos.library

_LVOOpen=-30
_LVOClose=-36
_LVORead=-42
_LVOSeek=-66

MODE_OLDFILE=1005
OFFSET_BEGINNING=-1
OFFSET_END=1

; X68000 joystick bits

X68_UP=0
X68_DOWN=1
X68_LEFT=2
X68_RIGHT=3
X68_TRIGGER_A=5
X68_TRIGGER_B=6

NO_KEY=$ff
KEY_STATE_SIZE=16+128/8+128+8 ; keyboard_matrix ... joystick_bit_counts
NO_BIT=$ff

; Input script (tests): 'CRSI', number of records, then 8-byte records:
; time (long), kind (byte), value (byte), padding. Kind 0: joystick state
; from that game frame on (X68000 bits, active low). Kind 1: a raw key event
; (Amiga raw key code, bit 7 = release) at that frame, written into
; input.device so it takes the same path as a real key. Kind 2: joystick
; state from that frame timer tick on (total_vbl_count), for input while
; the game completes no frames. Kind 3: a raw key event at that frame timer
; tick (processed directly, not through input.device: input_tick runs in
; an interrupt). Records are sorted by time.

SCRIPT_HEADER_SIZE=8
SCRIPT_RECORD_SIZE=8
SCRIPT_JOYSTICK=0
SCRIPT_KEY=1
SCRIPT_TICK_JOYSTICK=2
SCRIPT_TICK_KEY=3
SCRIPT_MOUSE=4 ; Value: x, then y in the padding byte (signed movement, pixels).
SCRIPT_MOUSE_BUTTON=5 ; Value: IECODE_LBUTTON / IECODE_RBUTTON, bit 7 = release.

; Mouse

IECLASS_RAWMOUSE=2
IECODE_LBUTTON=$68
IECODE_RBUTTON=$69
RAW_KEY_M=$37
MOUSE_DEAD_ZONE=2 ; Pixels.
SHIP_LEFT=$400 ; The ship's area (the game's limits, 1/64 pixel).
SHIP_RIGHT=$4000
SHIP_TOP=$400
SHIP_BOTTOM=$3F00
AUTOFIRE_SHIFT=1
AUTOFIRE_FRAMES=1<<AUTOFIRE_SHIFT ; Pressed for 2 frames, released for 2.
MOUSE_MESSAGE_TICKS=110 ; 2 s.
MOUSE_MESSAGE_X=11 ; Text cells: "mouse off" centred where "pause" is.
MOUSE_MESSAGE_Y=16

IND_WRITEEVENT=11
io_Length=36
IE_SIZE=22

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; a0 = input script file name, or 0. Returns d0 = 0, or -1 if the script
; could not be loaded. Missing lowlevel.library or input.device only lose
; that input source.

initialize_input:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	a0,a4

	move.b	#-1,joystick_state
	move.b	#-1,keyboard_joystick_state
	move.b	#-1,script_joystick_state
	move.l	#-1,iocs_joystick_data

	move.b	#-1,mouse_button_state
	move.b	#X68_LEFT,latest_horizontal
	move.b	#X68_UP,latest_vertical

	lea		keyboard_matrix,a0 ; And the key counts after it.
	moveq	#KEY_STATE_SIZE/4-1,d0

.clear_matrix:
	clr.l	(a0)+
	dbf		d0,.clear_matrix

	move.l	exec_base,a6

	; Joystick and CD32 pad.

	clr.l	lowlevel_base

	ifnd __NO_LOWLEVEL__

	lea		lowlevel_name,a1
	moveq	#40,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,lowlevel_base

	endif

	; ReadJoyPort acquires its resources on the first call, which must come
	; from a task; after that it may be called from interrupts (input_tick).

	sf		joystick_ready
	bsr		read_joystick
	move.l	exec_base,a6

	; Keyboard handler.

	ifd __NO_INPUT_HANDLER__

	bra		.no_keyboard

	endif

	jsr		_LVOCreateMsgPort(a6)
	move.l	d0,input_port
	beq		.no_keyboard

	move.l	d0,a0
	moveq	#IOSTD_SIZE,d0
	jsr		_LVOCreateIORequest(a6)
	move.l	d0,input_request
	beq		.no_keyboard

	lea		input_device_name,a0
	moveq	#0,d0
	move.l	input_request,a1
	moveq	#0,d1
	jsr		_LVOOpenDevice(a6)
	tst.l	d0
	bne		.no_keyboard

	st		input_device_open

	lea		input_handler_interrupt,a0
	move.b	#NT_INTERRUPT,ln_Type(a0)
	move.b	#INPUT_HANDLER_PRIORITY,ln_Pri(a0)
	move.l	#input_handler_name,ln_Name(a0)
	clr.l	is_Data(a0)
	move.l	#input_handler,is_Code(a0)

	move.l	input_request,a1
	move	#IND_ADDHANDLER,io_Command(a1)
	move.l	a0,io_Data(a1)
	jsr		_LVODoIO(a6)

	st		input_handler_added

.no_keyboard:
	; Input script.

	clr.l	script_data
	move.l	a4,d0
	beq		.done

	move.l	a4,a0
	jsr		load_input_script
	tst.l	d0
	bmi		.failed

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	moveq	#0,d0

	rts

.failed:
	movem.l	(sp)+,d2-d7/a2-a6

	moveq	#-1,d0

	rts

; ------------------------------------------------------------------------------

release_input:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	exec_base,a6

	tst.b	input_handler_added
	beq		.no_handler

	sf		input_handler_added

	move.l	input_request,a1
	move	#IND_REMHANDLER,io_Command(a1)
	move.l	#input_handler_interrupt,io_Data(a1)
	jsr		_LVODoIO(a6)

.no_handler:
	tst.b	input_device_open
	beq		.no_device

	sf		input_device_open

	move.l	input_request,a1
	jsr		_LVOCloseDevice(a6)

.no_device:
	move.l	input_request,d0
	beq		.no_request

	clr.l	input_request
	move.l	d0,a0
	jsr		_LVODeleteIORequest(a6)

.no_request:
	move.l	input_port,d0
	beq		.no_port

	clr.l	input_port
	move.l	d0,a0
	jsr		_LVODeleteMsgPort(a6)

.no_port:
	move.l	lowlevel_base,d0
	beq		.no_lowlevel

	clr.l	lowlevel_base
	move.l	d0,a1
	jsr		_LVOCloseLibrary(a6)

.no_lowlevel:
	move.l	script_data,d0
	beq		.no_script

	clr.l	script_data
	move.l	d0,a1
	move.l	script_size,d0
	jsr		_LVOFreeMem(a6)

.no_script:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
;
; Once per game frame (task context): read the joystick port and the input
; script, and combine all sources into the _JOYGET value.

; Reads the joystick or CD32 pad in port 2 into joystick_state (lowlevel.
; library). Task context the first time; then also from interrupts. If
; another caller is inside ReadJoyPort, the state is left as it was.
; Preserves all registers.

read_joystick:
	movem.l	d0-d2/a0-a1/a6,-(sp)

	move.l	lowlevel_base,d0
	beq		.done

	move.l	d0,a6
	moveq	#JOYSTICK_PORT,d0
	jsr		_LVOReadJoyPort(a6)

	move.l	d0,d1
	and.l	#JP_TYPE_MASK,d1
	cmp.l	#JP_TYPE_NOTAVAIL,d1
	beq		.done ; Busy, or the resources were not available.

	st		joystick_ready
	cmp.l	#JP_TYPE_JOYSTK,d1
	beq		.joystick

	cmp.l	#JP_TYPE_GAMECTLR,d1
	bne		.done

.joystick:
	moveq	#-1,d2

	btst	#JPB_JOY_UP,d0
	beq		.not_up
	bclr	#X68_UP,d2
.not_up:
	btst	#JPB_JOY_DOWN,d0
	beq		.not_down
	bclr	#X68_DOWN,d2
.not_down:
	btst	#JPB_JOY_LEFT,d0
	beq		.not_left
	bclr	#X68_LEFT,d2
.not_left:
	btst	#JPB_JOY_RIGHT,d0
	beq		.not_right
	bclr	#X68_RIGHT,d2
.not_right:
	btst	#JPB_BUTTON_RED,d0
	beq		.not_red
	bclr	#X68_TRIGGER_A,d2
.not_red:
	btst	#JPB_BUTTON_BLUE,d0
	beq		.not_blue
	bclr	#X68_TRIGGER_B,d2
.not_blue:
	move.b	d2,joystick_state

.done:
	movem.l	(sp)+,d0-d2/a0-a1/a6

	rts

; ------------------------------------------------------------------------------
;
; From the frame software interrupt: the joystick, and the script's tick
; records. Preserves all registers.

input_tick:
	tst.b	joystick_ready
	beq		.script ; Still read by update_input until ReadJoyPort works.

	bsr		read_joystick

.script:
	movem.l	d0/a0-a1,-(sp)

	move.l	script_next_tick_record,d0
	beq		.done

	move.l	d0,a0
	move.l	script_end,a1

.loop:
	cmp.l	a1,a0
	bcc		.end

	cmp.b	#SCRIPT_TICK_JOYSTICK,4(a0)
	bcs		.next ; A frame record.

	cmp.b	#SCRIPT_TICK_KEY,4(a0)
	bhi		.next

	move.l	(a0),d0
	cmp.l	total_vbl_count,d0
	bhi		.end

	cmp.b	#SCRIPT_TICK_KEY,4(a0)
	beq		.key

	move.b	5(a0),script_joystick_state

	bra		.next

.key:
	movem.l	d1-d4/a1-a2,-(sp)
	moveq	#0,d0
	move.b	5(a0),d0
	bsr		process_key
	movem.l	(sp)+,d1-d4/a1-a2

.next:
	addq.l	#SCRIPT_RECORD_SIZE,a0

	bra		.loop

.end:
	move.l	a0,script_next_tick_record

.done:
	movem.l	(sp)+,d0/a0-a1

	rts

; ------------------------------------------------------------------------------
;
; _JOYGET (trap handler): d0.l = the current joystick bits (X68000, active
; low): a bit is pressed if the joystick, the keyboard or the script presses
; it.
;
; The keyboard's cursor keys can hold opposite directions at once, which a
; joystick cannot: of left and right (and of up and down) only the one
; pressed last counts. The game reads left + right as START and up + down
; as SELECT of an X68000 pad (CONFIG: START SELECT): START pauses, START +
; SELECT leaves the game. (ESC is START from the keyboard.)

joystick_now:
	move.l	d1,-(sp)

	move.b	keyboard_joystick_state,d1
	moveq	#1<<X68_LEFT|1<<X68_RIGHT,d0
	and.b	d1,d0
	bne		.horizontal_done ; Not both pressed (active low).

	moveq	#X68_LEFT+X68_RIGHT,d0
	sub.b	latest_horizontal,d0 ; The other one.
	bset	d0,d1

.horizontal_done:
	moveq	#1<<X68_UP|1<<X68_DOWN,d0
	and.b	d1,d0
	bne		.vertical_done

	moveq	#X68_UP+X68_DOWN,d0
	sub.b	latest_vertical,d0
	bset	d0,d1

.vertical_done:
	tst.b	mouse_mode
	beq		.combine

	; Mouse control: the buttons; in a stage, the directions toward the
	; pointer.

	and.b	mouse_button_state,d1
	tst.b	amiga_stage_frame
	beq		.combine

	bsr		mouse_directions
	and.b	d0,d1

.combine:
	moveq	#-1,d0
	move.b	joystick_state,d0
	and.b	d1,d0
	and.b	script_joystick_state,d0
	move.b	d0,last_joystick_state ; For the auto fire at the frame end.

	; Auto fire: released in its off phase.

	tst.b	amiga_stage_frame
	beq		.done

	tst.b	autofire_released
	beq		.done

	bset	#X68_TRIGGER_A,d0

.done:
	move.l	(sp)+,d1

	rts

; Returns d0.b = joystick directions (active low) from the ship toward the
; mouse control's target (all released before the target is set). Preserves
; the other registers.

mouse_directions:
	movem.l	d1-d3,-(sp)

	moveq	#-1,d3 ; Directions.
	tst.b	mouse_target_set
	beq		.done

	move	mouse_target_x,d0
	sub		WORD_00098864,d0 ; Horizontal distance.
	cmp		#MOUSE_DEAD_ZONE<<6,d0
	ble		.not_right

	bclr	#X68_RIGHT,d3

.not_right:
	cmp		#-MOUSE_DEAD_ZONE<<6,d0
	bge		.not_left

	bclr	#X68_LEFT,d3

.not_left:
	move	mouse_target_y,d1
	sub		WORD_00098864+2,d1 ; Vertical distance.
	cmp		#MOUSE_DEAD_ZONE<<6,d1
	ble		.not_down

	bclr	#X68_DOWN,d3

.not_down:
	cmp		#-MOUSE_DEAD_ZONE<<6,d1
	bge		.done

	bclr	#X68_UP,d3

.done:
	move.l	d3,d0
	movem.l	(sp)+,d1-d3

	rts

; At the frame end: the mouse's movement since the last frame moves the
; target (in a stage, with mouse control on; it starts at the ship).
; Otherwise the movement is dropped and the target is set again next time.
; May change d0-d1.

move_mouse_target:
	; Take the movement (single instructions: the input handler adds to it).

	move.l	mouse_dx,d0
	sub.l	d0,mouse_dx
	move.l	mouse_dy,d1
	sub.l	d1,mouse_dy

	tst.b	mouse_mode
	beq		.reset

	tst.b	amiga_stage_frame
	beq		.reset

	tst.b	mouse_target_set
	bne		.move

	move	WORD_00098864,mouse_target_x
	move	WORD_00098864+2,mouse_target_y
	st		mouse_target_set

.move:
	; Pixels -> 1/64 pixel, clamped (also against huge movements).

	cmp.l	#$100,d0
	ble		.x_below
	move.l	#$100,d0
.x_below:
	cmp.l	#-$100,d0
	bge		.x_above
	move.l	#-$100,d0
.x_above:
	lsl.l	#6,d0
	add		mouse_target_x,d0
	cmp		#SHIP_LEFT,d0
	bge		.x_left_ok
	move	#SHIP_LEFT,d0
.x_left_ok:
	cmp		#SHIP_RIGHT,d0
	ble		.x_right_ok
	move	#SHIP_RIGHT,d0
.x_right_ok:
	move	d0,mouse_target_x

	cmp.l	#$100,d1
	ble		.y_below
	move.l	#$100,d1
.y_below:
	cmp.l	#-$100,d1
	bge		.y_above
	move.l	#-$100,d1
.y_above:
	lsl.l	#6,d1
	add		mouse_target_y,d1
	cmp		#SHIP_TOP,d1
	bge		.y_top_ok
	move	#SHIP_TOP,d1
.y_top_ok:
	cmp		#SHIP_BOTTOM,d1
	ble		.y_bottom_ok
	move	#SHIP_BOTTOM,d1
.y_bottom_ok:
	move	d1,mouse_target_y

	rts

.reset:
	sf		mouse_target_set

	rts

; ------------------------------------------------------------------------------
;
; At each frame end (amiga_wait_vbl, amiga_xsp_vsync: the game's task, its
; stack, user mode): shows "mouse on" / "mouse off" after M, as the game
; shows "pause" (DRAW_TEXT), and erases it MOUSE_MESSAGE_TICKS later.
; Preserves all registers.

mouse_frame_hook:
	movem.l	d0-d1/a0-a1,-(sp)

	tst.b	mouse_mode_changed
	beq		.no_change

	sf		mouse_mode_changed
	lea		mouse_on_text,a0
	tst.b	mouse_mode
	bne		.text_set

	lea		mouse_off_text,a0

.text_set:
	bsr		draw_mouse_message
	move.l	total_vbl_count,d0
	add.l	#MOUSE_MESSAGE_TICKS,d0
	move.l	d0,mouse_message_end
	st		mouse_message_shown

	bra		.done

.no_change:
	tst.b	mouse_message_shown
	beq		.done

	move.l	total_vbl_count,d0
	cmp.l	mouse_message_end,d0
	bcs		.done

	sf		mouse_message_shown
	lea		mouse_erase_text,a0
	bsr		draw_mouse_message

.done:
	; Auto fire: count the frames trigger A is held in a stage; every
	; AUTOFIRE_FRAMES the game sees it released, then pressed again.

	tst.b	amiga_stage_frame
	beq		.no_autofire

	btst	#X68_TRIGGER_A,last_joystick_state
	bne		.no_autofire ; Released.

	addq.l	#1,autofire_frames
	move.l	autofire_frames,d0
	btst	#AUTOFIRE_SHIFT,d0 ; Odd periods of AUTOFIRE_FRAMES: released.
	sne		autofire_released

	bra		.autofire_done

.no_autofire:
	clr.l	autofire_frames ; A new press counts at once.
	sf		autofire_released

.autofire_done:
	bsr		move_mouse_target
	sf		amiga_stage_frame ; Set again by the next stage frame.

	movem.l	(sp)+,d0-d1/a0-a1

	rts

; a0 = text: DRAW_TEXT(x, y, text) as the game calls it (C arguments).

draw_mouse_message:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	a0,-(sp)
	pea		MOUSE_MESSAGE_Y.w
	pea		MOUSE_MESSAGE_X.w
	jsr		DRAW_TEXT
	lea		12(sp),sp

	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
;
; Once per game frame: the joystick while ReadJoyPort cannot be used from
; the frame timer yet, and the script's frame records.

update_input:
	movem.l	d2-d7/a2-a6,-(sp)

	tst.b	joystick_ready
	bne		.no_joystick

	bsr		read_joystick

.no_joystick:
	; Script: apply every record whose frame has been reached.

	move.l	script_next_record,d0
	beq		.no_script

	move.l	d0,a0
	move.l	script_end,a1

.script_loop:
	cmp.l	a1,a0
	bcc		.script_done

	cmp.b	#SCRIPT_TICK_JOYSTICK,4(a0)
	bcs		.frame_record

	cmp.b	#SCRIPT_TICK_KEY,4(a0)
	bls		.next_record ; input_tick's.

.frame_record:

	move.l	(a0),d0
	cmp.l	frame_count,d0
	bhi		.script_done

	cmp.b	#SCRIPT_KEY,4(a0)
	beq		.script_key

	cmp.b	#SCRIPT_MOUSE,4(a0)
	beq		.script_mouse

	cmp.b	#SCRIPT_MOUSE_BUTTON,4(a0)
	beq		.script_mouse_button

	move.b	5(a0),script_joystick_state

	bra		.next_record

.script_key:
	movem.l	a0-a1,-(sp)
	moveq	#0,d0
	move.b	5(a0),d0
	moveq	#IECLASS_RAWKEY,d1
	jsr		write_input_event
	movem.l	(sp)+,a0-a1

	bra		.next_record

.script_mouse:
	move.b	5(a0),d0
	ext.w	d0
	ext.l	d0
	add.l	d0,mouse_dx
	move.b	6(a0),d0
	ext.w	d0
	ext.l	d0
	add.l	d0,mouse_dy

	bra		.next_record

.script_mouse_button:
	movem.l	a0-a1,-(sp)
	moveq	#0,d0
	move.b	5(a0),d0
	moveq	#IECLASS_RAWMOUSE,d1
	jsr		write_input_event
	movem.l	(sp)+,a0-a1

.next_record:
	addq.l	#SCRIPT_RECORD_SIZE,a0

	bra		.script_loop

.script_done:
	move.l	a0,script_next_record

.no_script:
	; All sources are active low: a bit is pressed if any source presses it.

	move.b	joystick_state,d0
	and.b	keyboard_joystick_state,d0
	and.b	script_joystick_state,d0
	move.b	d0,iocs_joystick_data+3

	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
;
; d0.b = Amiga raw key code (bit 7 = release): written into input.device.

write_input_event:
	tst.b	input_handler_added
	beq		.done

	move.b	d1,-(sp)

	lea		key_event,a0
	moveq	#IE_SIZE/2-1,d1

.clear:
	clr		(a0)+
	dbf		d1,.clear

	lea		key_event,a0
	move.b	(sp)+,ie_Class(a0)
	move	d0,ie_Code(a0)

	move.l	exec_base,a6
	move.l	input_request,a1
	move	#IND_WRITEEVENT,io_Command(a1)
	move.l	a0,io_Data(a1)
	move.l	#IE_SIZE,io_Length(a1)
	jsr		_LVODoIO(a6)

.done:
	rts

; ------------------------------------------------------------------------------
;
; input.device handler (input.device task): a0 = event list, a1 = is_Data.
; Updates the X68000 key matrix and the keyboard's joystick bits; the events
; are passed on unchanged. Returns d0 = event list.
;
; Several keys can drive one bit (Z and CTRL trigger A, X and both SHIFTs
; trigger B, both SHIFTs the X68000 SHIFT key): each bit counts the keys
; holding it and is released with the last one. The keys held are kept
; per raw key, so auto-repeated presses are not counted again.

input_handler:
	movem.l	d2-d4/a0/a2,-(sp)

.event_loop:
	cmp.b	#IECLASS_RAWMOUSE,ie_Class(a0)
	bne		.not_mouse

	move	ie_Code(a0),d0
	bsr		process_mouse_button

	; Movement (relative counts) for the mouse control's target.

	move	ie_X(a0),d0
	ext.l	d0
	add.l	d0,mouse_dx
	move	ie_Y(a0),d0
	ext.l	d0
	add.l	d0,mouse_dy

	bra		.next_event

.not_mouse:
	cmp.b	#IECLASS_RAWKEY,ie_Class(a0)
	bne		.next_event

	move	ie_Code(a0),d0
	cmp		#$100,d0
	bcc		.next_event ; Not a key code.

	bsr		process_key

.next_event:
	move.l	ie_NextEvent(a0),a0
	move.l	a0,d0
	bne		.event_loop

	movem.l	(sp)+,d2-d4/a0/a2
	move.l	a0,d0

	rts

; d0.w = mouse event code: the left and right buttons (bit 7: release) are
; triggers A and B while mouse control is on (mouse_button_state, active
; low). Other codes (movement) are ignored.

process_mouse_button:
	moveq	#$7f,d1
	and		d0,d1
	moveq	#X68_TRIGGER_A,d2
	cmp		#IECODE_LBUTTON,d1
	beq		.button

	moveq	#X68_TRIGGER_B,d2
	cmp		#IECODE_RBUTTON,d1
	bne		.done

.button:
	cmp		#$100,d0
	bcc		.done ; Not a button code.

	tst.b	d0
	bmi		.up

	bclr	d2,mouse_button_state

	rts

.up:
	bset	d2,mouse_button_state

.done:
	rts

; d0.w = raw key code (bit 7: release): updates the key matrix and the
; keyboard's joystick bits. From the input handler, and from input_tick for
; the script's tick key records. May change d0-d4, a1 and a2.

process_key:
	moveq	#$7f,d1
	and		d0,d1 ; Raw key.

	; Held keys: a press of a held key is a repeat, a release of a key not
	; held is ignored.

	move	d1,d2
	lsr		#3,d2
	lea		raw_keys_held,a2
	add		d2,a2
	moveq	#7,d2
	and		d1,d2
	moveq	#1,d4 ; Count change.
	tst.b	d0
	bmi		.key_up

	bset	d2,(a2)
	bne		.done

	bra		.apply

.key_up:
	bclr	d2,(a2)
	beq		.done

	moveq	#-1,d4

.apply:
	cmp.b	#RAW_KEY_M,d1
	bne		.not_m

	tst.l	d4
	bmi		.done ; Released.

	not.b	mouse_mode
	st		mouse_mode_changed
	sf		mouse_target_set ; Starts at the ship again.

	bra		.done

.not_m:
	lea		key_map,a1
	add		d1,d1
	add		d1,a1

	; X68000 scancode -> key matrix bit.

	moveq	#0,d1
	move.b	(a1),d1
	cmp.b	#NO_KEY,d1
	beq		.no_matrix_key

	lea		matrix_key_counts,a2
	add.b	d4,(a2,d1.w)
	sne		d3 ; Held by some key.
	move	d1,d2
	lsr		#3,d2
	lea		keyboard_matrix,a2
	add		d2,a2 ; Group byte.
	and		#7,d1
	tst.b	d3
	beq		.matrix_key_up

	bset	d1,(a2)

	bra		.no_matrix_key

.matrix_key_up:
	bclr	d1,(a2)

.no_matrix_key:
	; Joystick bit (active low).

	moveq	#0,d1
	move.b	1(a1),d1
	cmp.b	#NO_BIT,d1
	beq		.done

	lea		joystick_bit_counts,a2
	add.b	d4,(a2,d1.w)
	beq		.joystick_key_up

	bclr	d1,keyboard_joystick_state

	; The latest direction pressed on each axis (see joystick_now).

	tst.l	d4
	bmi		.done

	cmp.b	#X68_RIGHT,d1
	bhi		.done

	cmp.b	#X68_LEFT,d1
	bcs		.vertical

	move.b	d1,latest_horizontal

	bra		.done

.vertical:
	move.b	d1,latest_vertical

	bra		.done

.joystick_key_up:
	bset	d1,keyboard_joystick_state

.done:
	rts

; ------------------------------------------------------------------------------
;
; a0 = script file name (current directory). Returns d0 = 0 or -1.

load_input_script:
	move.l	dos_base,a6

	move.l	a0,d1
	move.l	#MODE_OLDFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,d4
	beq		.failed

	move.l	d4,d1
	moveq	#0,d2
	moveq	#OFFSET_END,d3
	jsr		_LVOSeek(a6)

	move.l	d4,d1
	moveq	#0,d2
	moveq	#OFFSET_BEGINNING,d3
	jsr		_LVOSeek(a6) ; Returns the old position: the file size.
	move.l	d0,d5
	cmp.l	#SCRIPT_HEADER_SIZE,d5
	blt		.close_failed

	move.l	d5,script_size
	move.l	d5,d0
	moveq	#MEMF_ANY,d1
	move.l	exec_base,a6
	jsr		_LVOAllocMem(a6)
	move.l	d0,script_data
	beq		.close_failed

	move.l	dos_base,a6
	move.l	d4,d1
	move.l	script_data,d2
	move.l	d5,d3
	jsr		_LVORead(a6)
	cmp.l	d5,d0
	bne		.close_failed

	move.l	d4,d1
	jsr		_LVOClose(a6)

	move.l	script_data,a0
	cmp.l	#'CRSI',(a0)
	bne		.failed

	move.l	4(a0),d0
	lsl.l	#3,d0 ; SCRIPT_RECORD_SIZE
	add.l	#SCRIPT_HEADER_SIZE,d0
	cmp.l	d5,d0
	bhi		.failed

	lea		SCRIPT_HEADER_SIZE(a0),a1
	move.l	a1,script_next_record
	move.l	a1,script_next_tick_record
	add.l	d0,a0
	move.l	a0,script_end

	moveq	#0,d0

	rts

.close_failed:
	move.l	dos_base,a6
	move.l	d4,d1
	jsr		_LVOClose(a6)

.failed:
	moveq	#-1,d0

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

lowlevel_name:
	dc.b	'lowlevel.library',0

input_device_name:
	dc.b	'input.device',0

input_handler_name:
	dc.b	'Cho Ren Sha 68k input',0

	even

; Per Amiga raw key ($00-$7f): X68000 scancode, X68000 joystick bit.

mouse_on_text:
	dc.b	'mouse on ',0
mouse_off_text:
	dc.b	'mouse off',0
mouse_erase_text:
	dc.b	'         ',0

	even

key_map:
	dc.b	NO_KEY,NO_BIT ; $00
	dc.b	$02,NO_BIT ; $01 1
	dc.b	NO_KEY,NO_BIT ; $02
	dc.b	NO_KEY,NO_BIT ; $03
	dc.b	NO_KEY,NO_BIT ; $04
	dc.b	NO_KEY,NO_BIT ; $05
	dc.b	NO_KEY,NO_BIT ; $06
	dc.b	NO_KEY,NO_BIT ; $07
	dc.b	NO_KEY,NO_BIT ; $08
	dc.b	NO_KEY,NO_BIT ; $09
	dc.b	NO_KEY,NO_BIT ; $0a
	dc.b	NO_KEY,NO_BIT ; $0b
	dc.b	NO_KEY,NO_BIT ; $0c
	dc.b	NO_KEY,NO_BIT ; $0d
	dc.b	NO_KEY,NO_BIT ; $0e
	dc.b	NO_KEY,NO_BIT ; $0f
	dc.b	NO_KEY,NO_BIT ; $10
	dc.b	NO_KEY,NO_BIT ; $11
	dc.b	NO_KEY,NO_BIT ; $12
	dc.b	NO_KEY,NO_BIT ; $13
	dc.b	NO_KEY,NO_BIT ; $14
	dc.b	NO_KEY,NO_BIT ; $15
	dc.b	NO_KEY,NO_BIT ; $16
	dc.b	NO_KEY,NO_BIT ; $17
	dc.b	NO_KEY,NO_BIT ; $18
	dc.b	$01,NO_BIT ; $19 P: the X68000's ESC, which the game reads as START (pause)
	dc.b	NO_KEY,NO_BIT ; $1a
	dc.b	NO_KEY,NO_BIT ; $1b
	dc.b	NO_KEY,NO_BIT ; $1c
	dc.b	NO_KEY,NO_BIT ; $1d
	dc.b	NO_KEY,NO_BIT ; $1e
	dc.b	NO_KEY,NO_BIT ; $1f
	dc.b	NO_KEY,NO_BIT ; $20
	dc.b	NO_KEY,NO_BIT ; $21
	dc.b	NO_KEY,NO_BIT ; $22
	dc.b	NO_KEY,NO_BIT ; $23
	dc.b	NO_KEY,NO_BIT ; $24
	dc.b	NO_KEY,NO_BIT ; $25
	dc.b	NO_KEY,NO_BIT ; $26
	dc.b	NO_KEY,NO_BIT ; $27
	dc.b	NO_KEY,NO_BIT ; $28
	dc.b	NO_KEY,NO_BIT ; $29
	dc.b	NO_KEY,NO_BIT ; $2a
	dc.b	NO_KEY,NO_BIT ; $2b
	dc.b	NO_KEY,NO_BIT ; $2c
	dc.b	NO_KEY,NO_BIT ; $2d
	dc.b	NO_KEY,NO_BIT ; $2e
	dc.b	NO_KEY,NO_BIT ; $2f
	dc.b	NO_KEY,NO_BIT ; $30
	dc.b	NO_KEY,X68_TRIGGER_A ; $31 Z
	dc.b	NO_KEY,X68_TRIGGER_B ; $32 X
	dc.b	NO_KEY,NO_BIT ; $33
	dc.b	NO_KEY,NO_BIT ; $34
	dc.b	NO_KEY,NO_BIT ; $35
	dc.b	NO_KEY,NO_BIT ; $36
	dc.b	NO_KEY,NO_BIT ; $37
	dc.b	NO_KEY,NO_BIT ; $38
	dc.b	NO_KEY,NO_BIT ; $39
	dc.b	NO_KEY,NO_BIT ; $3a
	dc.b	NO_KEY,NO_BIT ; $3b
	dc.b	NO_KEY,NO_BIT ; $3c
	dc.b	NO_KEY,NO_BIT ; $3d
	dc.b	NO_KEY,NO_BIT ; $3e
	dc.b	NO_KEY,NO_BIT ; $3f
	dc.b	$35,NO_BIT ; $40 SPACE
	dc.b	NO_KEY,NO_BIT ; $41
	dc.b	$10,NO_BIT ; $42 TAB
	dc.b	NO_KEY,NO_BIT ; $43
	dc.b	$1d,NO_BIT ; $44 RETURN
	dc.b	$01,NO_BIT ; $45 ESC
	dc.b	NO_KEY,NO_BIT ; $46
	dc.b	NO_KEY,NO_BIT ; $47
	dc.b	NO_KEY,NO_BIT ; $48
	dc.b	NO_KEY,NO_BIT ; $49
	dc.b	NO_KEY,NO_BIT ; $4a
	dc.b	NO_KEY,NO_BIT ; $4b
	dc.b	$3c,X68_UP ; $4c cursor up
	dc.b	$3e,X68_DOWN ; $4d cursor down
	dc.b	$3d,X68_RIGHT ; $4e cursor right
	dc.b	$3b,X68_LEFT ; $4f cursor left
	dc.b	NO_KEY,NO_BIT ; $50
	dc.b	NO_KEY,NO_BIT ; $51
	dc.b	NO_KEY,NO_BIT ; $52
	dc.b	NO_KEY,NO_BIT ; $53
	dc.b	NO_KEY,NO_BIT ; $54
	dc.b	NO_KEY,NO_BIT ; $55
	dc.b	NO_KEY,NO_BIT ; $56
	dc.b	NO_KEY,NO_BIT ; $57
	dc.b	NO_KEY,NO_BIT ; $58
	dc.b	NO_KEY,NO_BIT ; $59
	dc.b	NO_KEY,NO_BIT ; $5a
	dc.b	NO_KEY,NO_BIT ; $5b
	dc.b	NO_KEY,NO_BIT ; $5c
	dc.b	NO_KEY,NO_BIT ; $5d
	dc.b	NO_KEY,NO_BIT ; $5e
	dc.b	NO_KEY,NO_BIT ; $5f
	dc.b	$70,X68_TRIGGER_B ; $60 left SHIFT
	dc.b	$70,X68_TRIGGER_B ; $61 right SHIFT
	dc.b	NO_KEY,NO_BIT ; $62
	dc.b	$71,X68_TRIGGER_A ; $63 CTRL
	dc.b	NO_KEY,NO_BIT ; $64
	dc.b	NO_KEY,NO_BIT ; $65
	dc.b	NO_KEY,NO_BIT ; $66
	dc.b	NO_KEY,NO_BIT ; $67
	dc.b	NO_KEY,NO_BIT ; $68
	dc.b	NO_KEY,NO_BIT ; $69
	dc.b	NO_KEY,NO_BIT ; $6a
	dc.b	NO_KEY,NO_BIT ; $6b
	dc.b	NO_KEY,NO_BIT ; $6c
	dc.b	NO_KEY,NO_BIT ; $6d
	dc.b	NO_KEY,NO_BIT ; $6e
	dc.b	NO_KEY,NO_BIT ; $6f
	dc.b	NO_KEY,NO_BIT ; $70
	dc.b	NO_KEY,NO_BIT ; $71
	dc.b	NO_KEY,NO_BIT ; $72
	dc.b	NO_KEY,NO_BIT ; $73
	dc.b	NO_KEY,NO_BIT ; $74
	dc.b	NO_KEY,NO_BIT ; $75
	dc.b	NO_KEY,NO_BIT ; $76
	dc.b	NO_KEY,NO_BIT ; $77
	dc.b	NO_KEY,NO_BIT ; $78
	dc.b	NO_KEY,NO_BIT ; $79
	dc.b	NO_KEY,NO_BIT ; $7a
	dc.b	NO_KEY,NO_BIT ; $7b
	dc.b	NO_KEY,NO_BIT ; $7c
	dc.b	NO_KEY,NO_BIT ; $7d
	dc.b	NO_KEY,NO_BIT ; $7e
	dc.b	NO_KEY,NO_BIT ; $7f

iocs_joystick_data:
	dc.l	-1

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

lowlevel_base:
	ds.l	1
input_port:
	ds.l	1
input_request:
	ds.l	1
script_data:
	ds.l	1
script_size:
	ds.l	1
script_next_record:
	ds.l	1
script_next_tick_record:
	ds.l	1
script_end:
	ds.l	1

input_handler_interrupt:
	ds.b	IS_SIZE

	even

key_event:
	ds.b	IE_SIZE

keyboard_matrix:
	ds.b	16

raw_keys_held:
	ds.b	128/8 ; Bit per Amiga raw key.

matrix_key_counts:
	ds.b	128 ; Keys holding each X68000 scancode.

joystick_bit_counts:
	ds.b	8 ; Keys holding each joystick bit.

joystick_state:
	ds.b	1
keyboard_joystick_state:
	ds.b	1
script_joystick_state:
	ds.b	1
mouse_message_end:
	ds.l	1 ; Frame timer tick to erase the message at.
autofire_frames:
	ds.l	1 ; Stage frames trigger A has been held.
last_joystick_state:
	ds.b	1 ; joystick_now's last result before the auto fire.
autofire_released:
	ds.b	1 ; Auto fire's off phase: trigger A reads released.
mouse_dx:
	ds.l	1 ; Mouse movement since the last frame end (counts).
mouse_dy:
	ds.l	1
mouse_target_x:
	ds.w	1 ; Mouse control's target (the ship's units).
mouse_target_y:
	ds.w	1
mouse_mode:
	ds.b	1 ; Mouse control on (M).
mouse_mode_changed:
	ds.b	1
mouse_message_shown:
	ds.b	1
mouse_button_state:
	ds.b	1 ; Triggers from the mouse buttons (active low).
amiga_stage_frame:
	ds.b	1 ; The game has run its ship control this frame.
mouse_target_set:
	ds.b	1
joystick_ready:
	ds.b	1
latest_horizontal:
	ds.b	1 ; X68_LEFT or X68_RIGHT, pressed last on the keyboard.
latest_vertical:
	ds.b	1 ; X68_UP or X68_DOWN. ; ReadJoyPort has its resources (may be called from interrupts).
input_device_open:
	ds.b	1
input_handler_added:
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
