
; Input: joystick (port 2) and CD32 pad through lowlevel.library, keyboard
; through an input.device handler, and scripted input for automated tests.
;
; The game reads the joystick with IOCS _JOYGET (X68000 bits, active low:
; 0 up, 1 down, 2 left, 3 right, 5 trigger A, 6 trigger B) and the keyboard
; with _BITSNS (X68000 key matrix, 16 groups of 8 scancodes). Keys also drive
; the joystick bits, as in the Falcon port:
;
;   cursor keys          joystick directions
;   CTRL, Z              trigger A          (fire 1 / red button)
;   SHIFT (either), X    trigger B          (fire 2 / blue button)
;   ESC, 1, TAB, SHIFT, CTRL, RETURN, SPACE, cursor keys   X68000 key matrix

	xdef initialize_input
	xdef release_input
	xdef update_input

	xdef iocs_joystick_data
	xdef keyboard_matrix

	xref exec_base
	xref dos_base
	xref frame_count

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
IECLASS_RAWKEY=1
IECODE_UP_PREFIX=$80

; lowlevel.library

_LVOReadJoyPort=-30

JOYSTICK_PORT=1 ; Game port 2.
JP_TYPE_MASK=$f0000000
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
; frame (long), kind (byte), value (byte), padding. Kind 0: joystick state
; from that frame on (X68000 bits, active low). Kind 1: a raw key event
; (Amiga raw key code, bit 7 = release), written into input.device so it
; takes the same path as a real key.

SCRIPT_HEADER_SIZE=8
SCRIPT_RECORD_SIZE=8
SCRIPT_JOYSTICK=0
SCRIPT_KEY=1

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

update_input:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	lowlevel_base,d0
	beq		.no_joystick

	move.l	d0,a6
	moveq	#JOYSTICK_PORT,d0
	jsr		_LVOReadJoyPort(a6)

	move.l	d0,d1
	and.l	#JP_TYPE_MASK,d1
	cmp.l	#JP_TYPE_JOYSTK,d1
	beq		.joystick

	cmp.l	#JP_TYPE_GAMECTLR,d1
	bne		.no_joystick

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

.no_joystick:
	; Script: apply every record whose frame has been reached.

	move.l	script_next_record,d0
	beq		.no_script

	move.l	d0,a0
	move.l	script_end,a1

.script_loop:
	cmp.l	a1,a0
	bcc		.script_done

	move.l	(a0),d0
	cmp.l	frame_count,d0
	bhi		.script_done

	cmp.b	#SCRIPT_KEY,4(a0)
	beq		.script_key

	move.b	5(a0),script_joystick_state

	bra		.next_record

.script_key:
	movem.l	a0-a1,-(sp)
	moveq	#0,d0
	move.b	5(a0),d0
	jsr		write_key_event
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

write_key_event:
	tst.b	input_handler_added
	beq		.done

	lea		key_event,a0
	moveq	#IE_SIZE/2-1,d1

.clear:
	clr		(a0)+
	dbf		d1,.clear

	lea		key_event,a0
	move.b	#IECLASS_RAWKEY,ie_Class(a0)
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
	cmp.b	#IECLASS_RAWKEY,ie_Class(a0)
	bne		.next_event

	move	ie_Code(a0),d0
	cmp		#$100,d0
	bcc		.next_event ; Not a key code.

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
	bne		.next_event

	bra		.apply

.key_up:
	bclr	d2,(a2)
	beq		.next_event

	moveq	#-1,d4

.apply:
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
	beq		.next_event

	lea		joystick_bit_counts,a2
	add.b	d4,(a2,d1.w)
	beq		.joystick_key_up

	bclr	d1,keyboard_joystick_state

	bra		.next_event

.joystick_key_up:
	bset	d1,keyboard_joystick_state

.next_event:
	move.l	ie_NextEvent(a0),a0
	move.l	a0,d0
	bne		.event_loop

	movem.l	(sp)+,d2-d4/a0/a2
	move.l	a0,d0

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
	dc.b	NO_KEY,NO_BIT ; $19
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
input_device_open:
	ds.b	1
input_handler_added:
	ds.b	1

	even

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
