
; Human68k / X68000 emulation layer for the Amiga.
;
; The game core runs as a normal user-mode AmigaOS task:
;
; - Human68k DOS and FLOAT calls are line-F opcodes ($FFxx / $FExx). They
;   reach the task's trap handler (tc_TrapCode; the 68040/68060 libraries pass
;   non-FPU line-F opcodes on), which redirects the exception's return to
;   human68k_call in user mode, where they are served with dos.library on a
;   separate OS stack.
; - IOCS (trap #15), PCM8 (trap #2) and MCDRV (trap #4) arrive through the
;   same trap handler in supervisor mode.
; - A vertical blank interrupt server enters the game's VBL handler (which
;   ends with RTE) through a format 0 exception frame, counts frames and
;   signals the task.
; - WAIT_VBL and XSP_VSYNC sleep on that signal instead of busy-waiting, and
;   record per-frame measurements (CPU time spent between waits, sprites).

	xdef start_emulator
	xdef amiga_exit_game
	xdef amiga_wait_vbl
	xdef amiga_xsp_vsync
	xdef amiga_printf
	xdef free_frame_records

	xdef iocs_joystick_data
	xdef keyboard_matrix

	xref _start
	xref exec_base
	xref dos_base
	xref L_00000118
	xref L_00E82000
	xref L_00EB8000
	xref L_00C00000
	xref SPRITE_DATA_ADDRESS
	xref sprite_palette_usage
	xref VBL_VWAIT_COUNTER
	xref frame_sprite_count
	xref start_of_code
	xref NEW_STACK

	ifd __HEARTBEAT__

	xref end_of_code

	endif

; Debug output on the serial port: -D__TRACE__ (every Human68k, IOCS and
; trap call) and/or -D__HEARTBEAT__ (task state and PC every 50 VBL).

	ifd __TRACE__
__DEBUG_OUTPUT__ equ 1
	endif

	ifd __HEARTBEAT__
__DEBUG_OUTPUT__ equ 1
	endif

; exec.library

_LVOAddIntServer=-168
_LVORemIntServer=-174
_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOFindTask=-294
_LVOWait=-318
_LVOSignal=-324
_LVOAllocSignal=-330
_LVOFreeSignal=-336
_LVOOpenDevice=-444
_LVORawDoFmt=-522
_LVOStackSwap=-732
_LVOCloseDevice=-450

MEMF_ANY=0
MEMF_CLEAR=1<<16

tc_TrapCode=50

NT_INTERRUPT=2
ln_Type=8
ln_Pri=9
ln_Name=10
is_Data=14
is_Code=18
IS_SIZE=22

INTB_VERTB=5

io_Device=20
TIMEREQUEST_SIZE=40
UNIT_ECLOCK=2

; dos.library

_LVOOpen=-30
_LVOClose=-36
_LVORead=-42
_LVOWrite=-48
_LVOSeek=-66
_LVODeleteFile=-72
_LVOOutput=-60
_LVOFlush=-360
_LVOPutStr=-948
_LVOVPrintf=-954

MODE_OLDFILE=1005
MODE_NEWFILE=1006
OFFSET_BEGINNING=-1
OFFSET_CURRENT=0
OFFSET_END=1

; timer.device

_LVOReadEClock=-60

; Trap numbers passed to tc_TrapCode (exception vector numbers).

LINE_F=11
TRAP_2=32+2
TRAP_4=32+4
TRAP_15=32+15

; Human68k

HEAP_SIZE=$200000					; Process area: PSP, game stack, heap.
MINIMUM_HEAP_SIZE=$100000			; Fallback when memory is short.
FIRST_FILE_HANDLE=5					; 0-4 are the standard handles.
NUMBER_OF_FILE_HANDLES=16
HUMAN68K_ERROR_FILE_NOT_FOUND=-2
HUMAN68K_ERROR_TOO_MANY_FILES=-4
HUMAN68K_ERROR_BAD_HANDLE=-6
HUMAN68K_ERROR_IO=-1

OS_STACK_SIZE=16384
MAXIMUM_MEASURED_FRAMES=65536
FRAME_RECORD_SIZE=8

; Stacks. exec checks a task's stack pointer against its registered bounds
; when it switches tasks, and dos.library relies on the bounds too. The game
; sets up its own stacks: first NEW_STACK in its BSS, then one in the process
; area. So start_emulator switches (StackSwap) to bounds that cover both, and
; every OS call from the game's context runs on os_stack, switched to with
; StackSwap() as well. The result in d0 survives the switch back. Not
; reentrant: one switch at a time (the game core is single-threaded).

GAME_STARTUP_STACK_SIZE=$1000 ; Used below NEW_STACK before the game moves on.

OS_STACK_ENTER macro
	move.l	exec_base,a6
	lea		os_stack_swap,a0
	move.l	#os_stack,(a0)
	move.l	#os_stack+OS_STACK_SIZE,4(a0)
	move.l	#os_stack+OS_STACK_SIZE,8(a0)
	jsr		_LVOStackSwap(a6)
	st		os_stack_active
	endm

OS_STACK_LEAVE macro
	sf		os_stack_active
	move.l	d0,os_stack_result
	move.l	exec_base,a6
	lea		os_stack_swap,a0
	jsr		_LVOStackSwap(a6)
	move.l	os_stack_result,d0
	endm

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; d0.l = number of frames to run before exiting (0 = until the game exits).
; Returns d0.l = 0, or -1 if the emulation could not be set up.

start_emulator:
	movem.l	d1-d7/a0-a6,-(sp)

	move.l	d0,frame_limit
	clr.l	frame_count
	clr.l	measured_frames
	clr.l	last_wake_time
	clr.l	last_wake_time+4
	clr.w	vbl_wait_counter

	move.l	exec_base,a6

	sub.l	a1,a1
	jsr		_LVOFindTask(a6)
	move.l	d0,main_task

	moveq	#-1,d0
	jsr		_LVOAllocSignal(a6)
	cmp.b	#-1,d0
	beq		.fail

	move.l	d0,vbl_signal_number
	moveq	#0,d1
	bset	d0,d1
	move.l	d1,vbl_signal_mask

	; Process area (PSP, game stack and heap). Cleared, so the high-water
	; mark can be found at exit.

	move.l	#HEAP_SIZE,heap_size
	move.l	#HEAP_SIZE,d0
	move.l	#MEMF_ANY|MEMF_CLEAR,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,heap_address
	bne		.heap_allocated

	move.l	#MINIMUM_HEAP_SIZE,heap_size
	move.l	#MINIMUM_HEAP_SIZE,d0
	move.l	#MEMF_ANY|MEMF_CLEAR,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,heap_address
	beq		.free_signal

.heap_allocated:
	; Frame records, only when measuring (frame limit given).

	clr.l	frame_records
	move.l	frame_limit,d0
	beq		.no_measurement

	cmp.l	#MAXIMUM_MEASURED_FRAMES,d0
	bls		.record_count_ok

	move.l	#MAXIMUM_MEASURED_FRAMES,d0

.record_count_ok:
	move.l	d0,maximum_records
	lsl.l	#3,d0 ; FRAME_RECORD_SIZE
	move.l	d0,frame_records_size
	moveq	#MEMF_ANY,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,frame_records
	beq		.free_heap

.no_measurement:

	; E clock for frame timing.

	lea		timer_name,a0
	moveq	#UNIT_ECLOCK,d0
	lea		timer_request,a1
	moveq	#0,d1
	jsr		_LVOOpenDevice(a6)
	tst.l	d0
	bne		.free_heap

	move.l	timer_request+io_Device,timer_base

	; Trap handler (IOCS, PCM8, MCDRV).

	move.l	main_task,a0
	move.l	tc_TrapCode(a0),old_trap_code
	move.l	#trap_handler,tc_TrapCode(a0)

	; Vertical blank interrupt server.

	lea		vbl_interrupt,a1
	move.b	#NT_INTERRUPT,ln_Type(a1)
	clr.b	ln_Pri(a1)
	move.l	#vbl_interrupt_name,ln_Name(a1)
	clr.l	is_Data(a1)
	move.l	#vbl_server,is_Code(a1)
	moveq	#INTB_VERTB,d0
	jsr		_LVOAddIntServer(a6)

	; Register stack bounds that cover the game's stacks: from the lower of
	; (NEW_STACK - startup stack, process area) to the higher of (NEW_STACK,
	; end of process area). StackSwap keeps the current stack in
	; game_stack_swap for amiga_exit_game.

	move.l	#NEW_STACK-GAME_STARTUP_STACK_SIZE,d0
	move.l	heap_address,d1
	cmp.l	d1,d0
	bls		.lower_found

	move.l	d1,d0

.lower_found:
	move.l	#NEW_STACK,d2
	add.l	heap_size,d1
	cmp.l	d1,d2
	bcc		.upper_found

	move.l	d1,d2

.upper_found:
	lea		game_stack_swap,a0
	move.l	d0,(a0)
	move.l	d2,4(a0)
	move.l	#NEW_STACK,8(a0)
	jsr		_LVOStackSwap(a6)

	; Start the game the way Human68k starts a process: a0 = memory
	; management block, a1 = end of program + 1, a2 = command line,
	; a3 = environment, a4 = entry point. All point into the cleared process
	; area, which gives an empty command line and environment.

	move.l	heap_address,a0
	move.l	a0,a1
	move.l	a0,a2
	move.l	a0,a3
	lea		_start,a4

	jmp		(a4)

.free_heap:
	move.l	heap_address,a1
	move.l	heap_size,d0
	jsr		_LVOFreeMem(a6)

.free_signal:
	move.l	vbl_signal_number,d0
	jsr		_LVOFreeSignal(a6)

.fail:
	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#-1,d0

	rts

; ------------------------------------------------------------------------------
;
; Leaves the game from any point in its main context (exit menu entry,
; _EXIT/_EXIT2, frame limit) and returns from start_emulator.

amiga_exit_game:
	; Leaving from within an OS call (frame limit, _EXIT2): swap the task's
	; stack bounds back first.

	tst.b	os_stack_active
	beq		.bounds_restored

	sf		os_stack_active
	move.l	exec_base,a6
	lea		os_stack_swap,a0
	jsr		_LVOStackSwap(a6)

.bounds_restored:
	; Back to the stack start_emulator was called on.

	move.l	exec_base,a6
	lea		game_stack_swap,a0
	jsr		_LVOStackSwap(a6)

	move.l	exec_base,a6

	lea		vbl_interrupt,a1
	moveq	#INTB_VERTB,d0
	jsr		_LVORemIntServer(a6)

	move.l	main_task,a0
	move.l	old_trap_code,tc_TrapCode(a0)

	jsr		close_all_files

	tst.l	frame_records
	beq		.no_graphics_dump

	jsr		write_graphics_dump

.no_graphics_dump:
	; Heap high-water mark: the area was cleared at allocation.

	move.l	heap_address,a0
	move.l	a0,a1
	add.l	heap_size,a1

.high_water_loop:
	cmp.l	a0,a1
	beq		.high_water_found

	tst.l	-(a1)
	beq		.high_water_loop

	addq.l	#4,a1

.high_water_found:
	sub.l	a0,a1
	move.l	a1,heap_used

	move.l	exec_base,a6

	lea		timer_request,a1
	jsr		_LVOCloseDevice(a6)

	move.l	heap_address,a1
	move.l	heap_size,d0
	jsr		_LVOFreeMem(a6)

	move.l	vbl_signal_number,d0
	jsr		_LVOFreeSignal(a6)

	movem.l	(sp)+,d1-d7/a0-a6

	moveq	#0,d0

	rts

; graphics.bin (measurement runs): 'CRSG', then GVRAM pages 0-1 ($100000),
; the video controller palettes ($400: graphics palette, sprite/text
; palette), the per-pattern sprite palette usage (MAXIMUM_PATTERNS words) and
; the sprite patterns (PCG_PATTERNS * 128 bytes). The patterns live in the
; game heap, so this runs before the heap is freed.

PCG_PATTERNS=$75e

write_graphics_dump:
	move.l	dos_base,a6

	move.l	#graphics_file_name,d1
	move.l	#MODE_NEWFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,d4
	beq		.done

	lea		graphics_dump_parts,a2

.part_loop:
	move.l	(a2)+,d2
	beq		.close

	move.l	(a2)+,d3

	cmp.l	#-1,d2 ; Indirect: the pattern data pointer.
	bne		.write

	move.l	SPRITE_DATA_ADDRESS,d2

.write:
	move.l	d4,d1
	jsr		_LVOWrite(a6)

	bra		.part_loop

.close:
	move.l	d4,d1
	jsr		_LVOClose(a6)

.done:
	rts

; Called by main.s after it has written the measurements.

free_frame_records:
	move.l	frame_records,d0
	beq		.done

	move.l	d0,a1
	move.l	frame_records_size,d0
	move.l	exec_base,a6
	jsr		_LVOFreeMem(a6)

	clr.l	frame_records

.done:
	rts

; ------------------------------------------------------------------------------
;
; Vertical blank interrupt server (a1 = is_Data, supervisor mode).

vbl_server:
	addq.w	#1,vbl_wait_counter
	addq.l	#1,total_vbl_count

	ifd __HEARTBEAT__

	move.l	total_vbl_count,d0
	divu	#50,d0
	swap	d0
	tst		d0
	bne		.no_heartbeat

	move.l	main_task,a0
	moveq	#0,d0
	move.b	15(a0),d0 ; tc_State
	move.l	d0,trace_heartbeat_arguments
	move.l	22(a0),trace_heartbeat_arguments+4 ; tc_SigWait
	move.l	54(a0),trace_heartbeat_arguments+8 ; tc_SPReg
	move.l	26(a0),trace_heartbeat_arguments+12 ; tc_SigRecvd
	move.l	exec_base,a0
	move.l	276(a0),a0 ; ThisTask
	move.l	10(a0),trace_heartbeat_arguments+16 ; ln_Name
	moveq	#0,d0
	move.b	9(a0),d0 ; ln_Pri
	ext		d0
	ext.l	d0
	move.l	d0,trace_heartbeat_arguments+20
	move.l	traps_handled,trace_heartbeat_arguments+36
	move.l	frame_count,trace_heartbeat_arguments+40
	move.l	main_task,a0
	move.l	(a0),trace_heartbeat_arguments+44 ; ln_Succ
	move.l	4(a0),trace_heartbeat_arguments+48 ; ln_Pred
	move.l	exec_base,a0
	move.l	406(a0),trace_heartbeat_arguments+52 ; TaskReady.lh_Head
	moveq	#0,d0
	move.b	294(a0),d0 ; IDNestCnt
	move.l	d0,trace_heartbeat_arguments+56
	move.b	295(a0),d0 ; TDNestCnt
	move.l	d0,trace_heartbeat_arguments+60
	move.l	main_task,trace_heartbeat_arguments+64
	move.l	exec_base,a0
	move.l	280(a0),trace_heartbeat_arguments+68 ; IdleCount
	move.l	284(a0),trace_heartbeat_arguments+72 ; DispCount
	move.l	total_vbl_count,trace_heartbeat_arguments+76
	move.l	last_trap_number,trace_heartbeat_arguments+184
	move.l	last_trap_pc,d0
	sub.l	#start_of_code,d0
	move.l	d0,trace_heartbeat_arguments+188
	move.l	last_trap_d0,trace_heartbeat_arguments+192
	move.l	exec_base,a0
	move.l	514(a0),trace_heartbeat_arguments+176 ; LastAlert[0]
	move.l	518(a0),trace_heartbeat_arguments+180 ; LastAlert[1]
	; Return addresses on the task's saved stack (word-aligned scan of 512
	; bytes): values in our code or in the Kickstart ROM.

	move.l	main_task,a0
	move.l	54(a0),a0 ; tc_SPReg
	lea		trace_heartbeat_arguments+80,a1
	moveq	#24-1,d2
	move	#256-1,d0

.scan_stack:
	move.l	(a0),d1
	cmp.l	#$f80000,d1
	bcs		.not_rom

	cmp.l	#$1000000,d1
	bcs		.keep

.not_rom:
	cmp.l	#start_of_code,d1
	bcs		.next

	cmp.l	#end_of_code,d1
	bcc		.next

	sub.l	#start_of_code,d1
	or.l	#$80000000,d1 ; Marks a code offset.

.keep:
	move.l	d1,(a1)+
	subq	#1,d2
	bmi		.scan_done

.next:
	addq.l	#2,a0

	dbf		d0,.scan_stack

.fill:
	clr.l	(a1)+
	dbf		d2,.fill

.scan_done:

	; Interrupted user-mode PC: find the level 3 interrupt frame (format 0,
	; vector offset $6C) whose SR has the supervisor bit clear.

	clr.l	trace_heartbeat_arguments+24
	clr.l	trace_heartbeat_arguments+28
	clr.l	trace_heartbeat_arguments+32
	move.l	sp,a0
	moveq	#96-1,d1

.find_frame:
	addq.l	#2,a0
	cmp		#$006c,(a0)
	bne		.next_word

	move.l	-4(a0),d0
	sub.l	#start_of_code,d0
	move.l	d0,trace_heartbeat_arguments+24
	moveq	#0,d0
	move	-6(a0),d0
	move.l	d0,trace_heartbeat_arguments+28
	move.l	-4(a0),trace_heartbeat_arguments+32

	bra		.frame_done

.next_word:
	dbf		d1,.find_frame

.frame_done:

	movem.l	a2-a3,-(sp)
	lea		trace_heartbeat_text,a0
	lea		trace_heartbeat_arguments,a1
	lea		.heartbeat_char(pc),a2
	lea		trace_heartbeat_buffer,a3
	move.l	exec_base,a6
	jsr		_LVORawDoFmt(a6)
	movem.l	(sp)+,a2-a3

	lea		trace_heartbeat_buffer,a0
	jsr		serial_print

	bra		.no_heartbeat

.heartbeat_char:
	move.b	d0,(a3)+

	rts

.no_heartbeat:

	endif

	; The game's VBL handler ends with RTE: give it a format 0 frame
	; (format/vector word, return address, SR).

	move.w	#0,-(sp)
	pea		.return(pc)
	move.w	sr,-(sp)
	move.l	L_00000118,-(sp)
	rts

.return:
	move.l	exec_base,a6
	move.l	main_task,a1
	move.l	vbl_signal_mask,d0
	jsr		_LVOSignal(a6)

	moveq	#0,d0 ; Let the other vertical blank servers run.

	rts

; ------------------------------------------------------------------------------
;
; WAIT_VBL: d1.w = number of frames to wait minus one. Preserves all
; registers.

amiga_wait_vbl:
	movem.l	d0-d7/a0-a6,-(sp)

	move	d1,d7

	OS_STACK_ENTER

	jsr		frame_wait_begin

	clr		vbl_wait_counter

.wait_loop:
	cmp		vbl_wait_counter,d7
	blt		.done

	jsr		wait_for_vbl_signal

	bra		.wait_loop

.done:
	jsr		frame_wait_end

	OS_STACK_LEAVE

	movem.l	(sp)+,d0-d7/a0-a6

	rts

; ------------------------------------------------------------------------------
;
; XSP_VSYNC: waits until VBL_VWAIT_COUNTER (counted by the game's VBL
; handler) reaches d0.w, then returns the counter in d0.w and clears it.

amiga_xsp_vsync:
	movem.l	d1-d7/a0-a6,-(sp)

	move	d0,d7

	OS_STACK_ENTER

	jsr		frame_wait_begin

.wait_loop:
	cmp		VBL_VWAIT_COUNTER,d7
	bls		.done

	jsr		wait_for_vbl_signal

	bra		.wait_loop

.done:
	jsr		frame_wait_end

	OS_STACK_LEAVE

	movem.l	(sp)+,d1-d7/a0-a6

	move	VBL_VWAIT_COUNTER,d0
	clr		VBL_VWAIT_COUNTER

	rts

; ------------------------------------------------------------------------------

wait_for_vbl_signal:
	move.l	exec_base,a6
	move.l	vbl_signal_mask,d0
	jmp		_LVOWait(a6)

; ------------------------------------------------------------------------------
;
; Frame measurement: the E clock time from the end of one wait to the start of
; the next one is the CPU time the game needed for that frame.

frame_wait_begin:
	move.l	timer_base,a6
	lea		eclock_value,a0
	jsr		_LVOReadEClock(a6)
	move.l	d0,eclock_frequency

	tst.l	last_wake_time+4
	bne		.measure

	tst.l	last_wake_time
	beq		.no_previous_frame

.measure:
	tst.l	frame_records
	beq		.no_previous_frame

	move.l	measured_frames,d0
	cmp.l	maximum_records,d0
	bcc		.no_previous_frame

	; The E clock runs at about 709 kHz; a frame never takes 2^32 ticks, so
	; the low longword difference is the elapsed time.

	move.l	eclock_value+4,d1
	sub.l	last_wake_time+4,d1

	move.l	total_vbl_count,d2
	sub.l	vbl_count_at_wake,d2

	move.l	frame_records,a0
	lsl.l	#3,d0
	move.l	d1,(a0,d0.l)
	move	frame_sprite_count,4(a0,d0.l)
	move	d2,6(a0,d0.l)

	addq.l	#1,measured_frames

.no_previous_frame:
	clr		frame_sprite_count

	rts

frame_wait_end:
	move.l	total_vbl_count,vbl_count_at_wake

	move.l	timer_base,a6
	lea		last_wake_time,a0
	jsr		_LVOReadEClock(a6)

	addq.l	#1,frame_count

	move.l	frame_limit,d0
	beq		.no_limit

	cmp.l	frame_count,d0
	bhi		.no_limit

	jmp		amiga_exit_game

.no_limit:
	rts

; ------------------------------------------------------------------------------
;
; PRINTF(format, ...) from the game (C calling convention, 32-bit arguments).
; The format is converted for RawDoFmt (which takes 16-bit arguments unless
; told otherwise: %d -> %ld etc.) and the text goes to standard output. The
; game uses it for its error messages (Shift-JIS).

amiga_printf:
	movem.l	d0-d7/a0-a6,-(sp)

	move.l	15*4+4(sp),a0 ; Format.
	lea		15*4+8(sp),a4 ; Arguments.

	lea		printf_format_buffer,a1
	move	#256-3,d1

.convert:
	move.b	(a0)+,d0
	move.b	d0,(a1)+
	beq		.converted

	cmp.b	#'%',d0
	bne		.next

	; Copy flags and width, then make the conversion a long one.

.flags:
	move.b	(a0),d0
	cmp.b	#'-',d0
	beq		.copy_flag
	cmp.b	#'0',d0
	bcs		.conversion
	cmp.b	#'9',d0
	bhi		.conversion

.copy_flag:
	move.b	(a0)+,(a1)+
	subq	#1,d1
	bmi		.converted

	bra		.flags

.conversion:
	cmp.b	#'%',d0
	bne		.not_percent

	move.b	(a0)+,(a1)+ ; "%%"
	subq	#1,d1

	bra		.next

.not_percent:
	cmp.b	#'s',d0
	beq		.next
	cmp.b	#'l',d0
	beq		.next

	move.b	#'l',(a1)+
	subq	#1,d1

	cmp.b	#'u',d0 ; RawDoFmt has no %u.
	bne		.next

	move.b	#'d',(a0)

.next:
	dbf		d1,.convert

	clr.b	(a1)

.converted:
	lea		printf_format_buffer,a0
	move.l	a4,a1
	lea		.put_char(pc),a2
	lea		printf_text_buffer,a3
	move.l	exec_base,a6
	jsr		_LVORawDoFmt(a6)

	OS_STACK_ENTER

	move.l	dos_base,a6
	move.l	#printf_text_buffer,d1
	jsr		_LVOPutStr(a6)

	; Flush: the game may wait for a key after an error message.

	jsr		_LVOOutput(a6)
	move.l	d0,d1
	jsr		_LVOFlush(a6)

	OS_STACK_LEAVE

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.put_char:
	move.b	d0,(a3)+

	rts

; ------------------------------------------------------------------------------
;
; Task trap handler. On entry (supervisor mode): (sp).l = exception vector
; number, followed by the exception frame. Traps that are not the game's go
; to the previous handler with the stack unchanged.

trap_handler:
	addq.l	#1,traps_handled

	ifd __HEARTBEAT__

	move.l	(sp),last_trap_number
	move.l	4+2(sp),last_trap_pc
	move.l	d0,last_trap_d0

	endif

	ifd __TRACE__

	move.l	(sp),exception_number
	move.l	4+2(sp),exception_pc
	jsr		trace_exception

	endif

	cmp.l	#LINE_F,(sp)
	beq		line_f_call

	cmp.l	#TRAP_15,(sp)
	beq		iocs_call

	cmp.l	#TRAP_2,(sp)
	beq		pcm8_call

	cmp.l	#TRAP_4,(sp)
	beq		mcdrv_call

	cmp.l	#2,(sp)
	bcs		.not_ours

	cmp.l	#10,(sp) ; Bus error ... line A.
	bls		unexpected_exception

.not_ours:
	move.l	old_trap_code,-(sp)

	rts

; Bus/address error, illegal instruction, zero divide, CHK, TRAPV, privilege
; violation, trace or line A in the game's task: drop the exception frame
; (its size depends on the format), and return in user mode into
; report_exception, which prints the exception and leaves the game.

unexpected_exception:
	move.l	(sp)+,exception_number

	move.l	2(sp),exception_pc

	ifd __TRACE__

	jsr		trace_exception

	endif

	move	6(sp),d0
	lsr		#8,d0
	lsr		#4,d0
	lea		exception_frame_sizes,a0
	move.b	(a0,d0.w),d0
	ext		d0
	bne		.known_format

	moveq	#8,d0 ; Unknown format: assume the short frame.

.known_format:
	add		d0,sp

	move.w	#0,-(sp) ; Format 0.
	pea		report_exception
	move.w	#0,-(sp) ; User mode, interrupts enabled.

	rte

; Exception stack frame sizes by format (68010 - 68060).

exception_frame_sizes:
	dc.b	8,8,12,12,16,0,0,60,58,20,32,92,0,0,0,0

	even

report_exception:
	move.l	exception_number,print_arguments
	move.l	exception_pc,d0
	move.l	d0,print_arguments+4
	sub.l	#start_of_code,d0
	move.l	d0,print_arguments+8

	OS_STACK_ENTER

	move.l	dos_base,a6
	move.l	#exception_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	jmp		amiga_exit_game

; Human68k DOS / FLOAT call: the stacked PC points to the $FFxx / $FExx
; opcode. Keep the call number, push the address after the opcode as the
; return address onto the user stack, and return from the exception into
; human68k_call. The game core is single-threaded and makes no such calls
; from interrupts, so one pending call number is enough.

line_f_call:
	addq.l	#4,sp

	movem.l	a0-a1,-(sp) ; Frame: SR at 8(sp), PC at 10(sp).

	move.l	10(sp),a0
	move	(a0)+,pending_call_number

	move	usp,a1
	move.l	a0,-(a1)
	move	a1,usp

	move.l	#human68k_call,10(sp)

	movem.l	(sp)+,a0-a1

	rte

; PCM8 (the game only reads and sets the mode with function $1FB).

pcm8_call:
	addq.l	#4,sp

	rte

; MCDRV is reported as absent by the music driver probe in sz2.s, so the game
; does not call it.

mcdrv_call:
	addq.l	#4,sp

	rte

; ------------------------------------------------------------------------------
;
; IOCS call, d0.b = function number.

iocs_call:
	addq.l	#4,sp

	ifd __TRACE__

	jsr		trace_iocs_call

	endif

	cmp.b	#$04,d0 ; _BITSNS
	bne		.not_bitsns

	move.l	a0,-(sp)

	lea		keyboard_matrix,a0
	moveq	#$f,d0
	and		d1,d0
	move.b	(a0,d0.w),d0
	and.l	#$ff,d0

	move.l	(sp)+,a0

	rte

.not_bitsns:
	cmp.b	#$10,d0 ; _CRTMOD
	beq		.return_zero

	cmp.b	#$14,d0 ; _TPALET2
	bne		.not_tpalet2

	movem.l	d1-d2/a0,-(sp)

	lea		L_00E82000+$200,a0
	and		#$f,d1

	moveq	#0,d0

	tst.l	d2
	bmi		.tpalet2_get_color

	move	d2,(a0,d1.w*2)

	bra		.tpalet2_done

.tpalet2_get_color:
	move	(a0,d1.w*2),d0

.tpalet2_done:
	movem.l	(sp)+,d1-d2/a0

	rte

.not_tpalet2:
	cmp.b	#$20,d0 ; _B_PUTC
	beq		.return_zero

	cmp.b	#$22,d0 ; _B_COLOR
	beq		.return_zero

	cmp.b	#$23,d0 ; _B_LOCATE
	beq		.return_zero

	cmp.b	#$3b,d0 ; _JOYGET
	bne		.not_joyget

	move.l	iocs_joystick_data,d0

	rte

.not_joyget:
	cmp.b	#$60,d0 ; _ADPCMOUT (no audio yet)
	beq		.return_zero

	cmp.b	#$66,d0 ; _ADPCMSNS (nothing playing)
	beq		.return_zero

	cmp.b	#$67,d0 ; _ADPCMMOD
	beq		.return_zero

	cmp.b	#$7d,d0 ; _SKEY_MOD
	beq		.return_zero

	cmp.b	#$7f,d0 ; _ONTIME (fixed, as on the Falcon: replays stay deterministic)
	bne		.not_ontime

	move.l	#100*100,d0
	moveq	#0,d1

	rte

.not_ontime:
	cmp.b	#$81,d0 ; _B_SUPER: report "already in supervisor mode", so the
	bne		.not_b_super ; game never asks to switch back.

	moveq	#-1,d0

	rte

.not_b_super:
	cmp.b	#$87,d0 ; _B_WPOKE
	beq		.return_zero

	cmp.b	#$90,d0 ; _G_CLR_ON
	beq		.return_zero

	cmp.b	#$92,d0 ; Priority setting (undocumented).
	beq		.return_zero

	cmp.b	#$ae,d0 ; _OS_CURON
	beq		.return_zero

	cmp.b	#$af,d0 ; _OS_CUROFF
	beq		.return_zero

	cmp.b	#$b1,d0 ; _APAGE
	beq		.return_zero

	cmp.b	#$b2,d0 ; _VPAGE
	beq		.return_zero

	cmp.b	#$b3,d0 ; _HOME
	beq		.return_zero

	cmp.b	#$b4,d0 ; _WINDOW
	beq		.return_zero

	cmp.b	#$b5,d0 ; _WIPE
	beq		.return_zero

	cmp.b	#$c1,d0 ; _SP_ON
	beq		.return_zero

	cmp.b	#$c2,d0 ; _SP_OFF
	beq		.return_zero

	cmp.b	#$ca,d0 ; _BGCTRLST
	beq		.return_zero

	cmp.b	#$ce,d0 ; _BGTEXTGT
	bne		.not_bgtextgt

	; d1 = BG page, d2 = x (0-63), d3 = y (0-63): the word in the page's
	; map in the sprite VRAM shadow ($EBC000 / $EBE000).

	movem.l	d1-d3/a0,-(sp)

	lea		L_00EB8000+$4000,a0
	and		#1,d1
	mulu	#$2000,d1
	add.l	d1,a0
	and		#63,d3
	lsl		#6,d3
	and		#63,d2
	add		d2,d3
	moveq	#0,d0
	move	(a0,d3.w*2),d0

	movem.l	(sp)+,d1-d3/a0

	rte

.not_bgtextgt:

	cmp.b	#$cf,d0 ; _SPALET
	bne		.not_spalet

	movem.l	d1-d3/a0,-(sp)

	lea		L_00E82000+$200,a0
	lsl		#4,d2
	add		d1,d2

	moveq	#0,d0

	tst.l	d3
	bmi		.spalet_get_color

	move	d3,(a0,d2.w*2)

	bra		.spalet_done

.spalet_get_color:
	move	(a0,d2.w*2),d0

.spalet_done:
	movem.l	(sp)+,d1-d3/a0

	rte

.not_spalet:
	; Unimplemented: remember the function number, reported at exit.

	movem.l	d1/a0,-(sp)

	lea		unimplemented_iocs,a0
	moveq	#0,d1
	move.b	d0,d1
	st		(a0,d1.w)

	movem.l	(sp)+,d1/a0

.return_zero:
	moveq	#0,d0

	rte

; ------------------------------------------------------------------------------
;
; Human68k DOS / FLOAT call (user mode, entered from line_f_call).
;
; (sp) = return address, 4(sp) = the call's arguments, pending_call_number =
; call number. Returns d0; all other registers are preserved.

human68k_call:
	movem.l	d1-d7/a0-a6,-(sp)

	lea		14*4+4(sp),a5 ; Arguments.
	move	pending_call_number,d7

	move.l	sp,game_stack_pointer
	move.l	d0,call_input_d0 ; StackSwap() does not preserve d0.

	OS_STACK_ENTER

	move.l	call_input_d0,d0

	ifd __TRACE__

	jsr		trace_human68k_call

	endif

	lea		human68k_call_table,a0

.find_loop:
	move	(a0)+,d1
	beq		.unimplemented

	move.l	(a0)+,a1

	cmp		d1,d7
	bne		.find_loop

	jsr		(a1)

	bra		.done

.unimplemented:
	; Report it at once (this is user mode, so dos.library can be used) and
	; fail the call.

	moveq	#0,d0
	move	d7,d0
	move.l	d0,print_arguments
	move.l	dos_base,a6
	move.l	#unimplemented_call_format,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	moveq	#HUMAN68K_ERROR_IO,d0

.done:
	ifd __TRACE__

	jsr		trace_call_result

	endif

	OS_STACK_LEAVE

	movem.l	(sp)+,d1-d7/a0-a6

	rts

	ifd __DEBUG_OUTPUT__

; Trace build (-D__TRACE__): prints every Human68k call (with the file name
; for _OPEN, _CREATE and _DELETE) and flushes, so the log survives a hang.

trace_human68k_call:
	movem.l	d0-d7/a0-a6,-(sp)

	moveq	#0,d0
	move	d7,d0
	move.l	d0,print_arguments
	move.l	frame_count,print_arguments+4
	move.l	#trace_empty_text,print_arguments+8
	move.l	game_stack_pointer,d0
	add.l	#14*4+4,d0 ; The game's A7 at the call.
	move.l	d0,print_arguments+12
	move.l	heap_address,print_arguments+16
	move.l	(a5),print_arguments+20
	move.l	4(a5),print_arguments+24
	move.l	8(a5),print_arguments+28


	cmp		#$ff3c,d7
	beq		.with_name
	cmp		#$ff3d,d7
	beq		.with_name
	cmp		#$ff41,d7
	bne		.format

.with_name:
	move.l	(a5),print_arguments+8

.format:
	move.l	exec_base,a6
	lea		trace_call_format,a0
	lea		print_arguments,a1
	lea		.put_char(pc),a2
	lea		trace_buffer,a3
	jsr		_LVORawDoFmt(a6)

	lea		trace_buffer,a0
	moveq	#-1,d3

.length:
	addq.l	#1,d3
	tst.b	(a0)+
	bne		.length

	move.l	dos_base,a6
	jsr		_LVOOutput(a6)
	move.l	d0,d1
	move.l	#trace_buffer,d2
	jsr		_LVOWrite(a6)

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.put_char:
	move.b	d0,(a3)+

	rts

; a0 = zero-terminated text. Polls the serial port, so it works in any
; context (user, supervisor, interrupts disabled).

SERDATR=$dff018
SERDAT=$dff030
SERPER=$dff032

serial_print:
	move	#(3546895/115200)-1,SERPER

.loop:
	moveq	#0,d0
	move.b	(a0)+,d0
	beq		.done

	cmp.b	#10,d0
	bne		.wait

	move.b	#13,d0
	bsr		.put
	moveq	#10,d0

.wait:
	bsr		.put

	bra		.loop

.done:
	rts

.put:
	btst	#13-8,SERDATR ; TBE
	beq		.put

	or		#$100,d0 ; Stop bit.
	move	d0,SERDAT

	rts

; d0 = result of the Human68k call.

trace_call_result:
	movem.l	d0-d7/a0-a6,-(sp)

	move.l	d0,trace_iocs_arguments
	lea		trace_result_format,a0
	lea		trace_iocs_arguments,a1
	lea		.put_char(pc),a2
	lea		trace_buffer,a3
	move.l	exec_base,a6
	jsr		_LVORawDoFmt(a6)

	lea		trace_buffer,a0
	moveq	#-1,d3

.length:
	addq.l	#1,d3
	tst.b	(a0)+
	bne		.length

	move.l	dos_base,a6
	jsr		_LVOOutput(a6)
	move.l	d0,d1
	move.l	#trace_buffer,d2
	jsr		_LVOWrite(a6)

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.put_char:
	move.b	d0,(a3)+

	rts

; Exception number in exception_number, PC in exception_pc (supervisor mode).

trace_exception:
	movem.l	d0-d7/a0-a6,-(sp)

	move.l	exception_number,trace_iocs_arguments
	move.l	exception_pc,trace_iocs_arguments+4
	lea		trace_exception_format,a0

; a0 = format, arguments in trace_iocs_arguments; called with d0-d7/a0-a6
; pushed, pops them and returns.

trace_format_and_print:
	lea		trace_iocs_arguments,a1
	lea		.put_char(pc),a2
	lea		trace_buffer,a3
	move.l	exec_base,a6
	jsr		_LVORawDoFmt(a6)

	lea		trace_buffer,a0
	bsr		serial_print

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.put_char:
	move.b	d0,(a3)+

	rts

; IOCS trace (supervisor mode, from iocs_call). d0.b = function.

trace_iocs_call:
	movem.l	d0-d7/a0-a6,-(sp)

	moveq	#0,d1
	move.b	d0,d1
	move.l	d1,trace_iocs_arguments

	lea		trace_iocs_format,a0
	lea		trace_iocs_arguments,a1
	lea		.put_char(pc),a2
	lea		trace_buffer,a3
	move.l	exec_base,a6
	jsr		_LVORawDoFmt(a6)

	lea		trace_buffer,a0
	bsr		serial_print

	movem.l	(sp)+,d0-d7/a0-a6

	rts

.put_char:
	move.b	d0,(a3)+

	rts

	endif

; Each routine: a5 = arguments, d0 = the caller's d0 on entry, the caller's
; registers are saved at game_stack_pointer (d1 first). Result in d0.

human68k_lmul:
	move.l	game_stack_pointer,a0
	muls.l	(a0),d0

	rts

human68k_ldiv:
	move.l	game_stack_pointer,a0
	divs.l	(a0),d0

	rts

human68k_return_zero:
	moveq	#0,d0

	rts

human68k_exit:
	jmp		amiga_exit_game

human68k_print:
	move.l	(a5),d1
	move.l	dos_base,a6
	jsr		_LVOPutStr(a6)

	moveq	#0,d0

	rts

human68k_dskfre:
	move.l	#10000000,d0

	rts

human68k_getpdb:
	move.l	heap_address,d0
	add.l	#16,d0

	rts

; _NAMECK(name.l, buffer.l): splits a file name into the Human68k NAMECK
; structure: drive (2 bytes, "A:"), path (65, "\dir\"), name (19) and
; extension (5, ".ext"), each zero-terminated. Returns 0 (no wildcards).

NAMECK_DRIVE=0
NAMECK_PATH=2
NAMECK_NAME=67
NAMECK_EXTENSION=86
NAMECK_SIZE=91

human68k_nameck:
	move.l	4(a5),a1
	move.l	a1,a2
	moveq	#NAMECK_SIZE-1,d0

.clear:
	clr.b	(a2)+
	dbf		d0,.clear

	move.l	(a5),a0

	; Drive: "X:" prefix, or the current drive A:.

	move.b	#'A',NAMECK_DRIVE(a1)
	move.b	#':',NAMECK_DRIVE+1(a1)

	tst.b	(a0)
	beq		.split

	cmp.b	#':',1(a0)
	bne		.split

	move.b	(a0),NAMECK_DRIVE(a1)
	addq.l	#2,a0

.split:
	; a2 = start of the file name (after the last '\' or '/').

	move.l	a0,a2
	move.l	a0,a3

.find_name:
	move.b	(a3)+,d0
	beq		.name_found

	cmp.b	#'\',d0
	beq		.separator

	cmp.b	#'/',d0
	bne		.find_name

.separator:
	move.l	a3,a2

	bra		.find_name

.name_found:
	; Path: leading '\', the directory part, trailing '\'.

	lea		NAMECK_PATH(a1),a3
	move.b	#'\',(a3)+
	moveq	#64-2,d1

.copy_path:
	cmp.l	a2,a0
	bcc		.path_done

	move.b	(a0)+,d0
	cmp.b	#'/',d0
	bne		.store_path

	moveq	#'\',d0

.store_path:
	cmp.b	#'\',d0
	bne		.not_leading

	cmp.b	#'\',-1(a3) ; Do not double the leading separator.
	beq		.copy_path

.not_leading:
	move.b	d0,(a3)+

	dbf		d1,.copy_path

.path_done:
	cmp.b	#'\',-1(a3)
	beq		.copy_name

	move.b	#'\',(a3)+

.copy_name:
	lea		NAMECK_NAME(a1),a3
	moveq	#18-1,d1

.name_loop:
	move.b	(a0),d0
	beq		.done

	cmp.b	#'.',d0
	beq		.extension

	move.b	d0,(a3)+
	addq.l	#1,a0

	dbf		d1,.name_loop

.skip_name:
	move.b	(a0),d0
	beq		.done

	cmp.b	#'.',d0
	beq		.extension

	addq.l	#1,a0

	bra		.skip_name

.extension:
	lea		NAMECK_EXTENSION(a1),a3
	moveq	#4-1,d1

.extension_loop:
	move.b	(a0)+,d0
	beq		.done

	move.b	d0,(a3)+

	dbf		d1,.extension_loop

.done:
	moveq	#0,d0

	rts

; _SETBLOCK(block.l, size.l): resize the process memory block, which ends at
; the end of the process area. On failure returns $81000000 + the largest
; possible size.

human68k_setblock:
	move.l	heap_address,d1
	add.l	heap_size,d1
	sub.l	(a5),d1 ; Largest possible size.

	cmp.l	4(a5),d1
	bcs		.too_large

	moveq	#0,d0

	rts

.too_large:
	move.l	d1,d0
	or.l	#$81000000,d0

	rts

; _OPEN(name.l, mode.w). MODE_OLDFILE opens an existing file for reading and
; writing, which covers all Human68k open modes.

human68k_open:
	move.l	#MODE_OLDFILE,d6

	bra		open_file

; _CREATE(name.l, attributes.w)

human68k_create:
	move.l	#MODE_NEWFILE,d6

open_file:
	jsr		find_free_handle
	tst.l	d0
	bmi		.done

	move.l	d0,d5

	move.l	(a5),a0
	jsr		convert_path

	move.l	dos_base,a6
	move.l	#path_buffer,d1
	move.l	d6,d2
	jsr		_LVOOpen(a6)
	tst.l	d0
	beq		.not_found

	lea		file_handles,a0
	move.l	d5,d1
	lsl.l	#2,d1
	move.l	d0,(a0,d1.l)

	move.l	d5,d0
	add.l	#FIRST_FILE_HANDLE,d0

.done:
	rts

.not_found:
	moveq	#HUMAN68K_ERROR_FILE_NOT_FOUND,d0

	rts

; _CLOSE(handle.w)

human68k_close:
	move	(a5),d0
	jsr		get_file_handle
	beq		.bad_handle

	clr.l	(a0)

	move.l	d0,d1
	move.l	dos_base,a6
	jsr		_LVOClose(a6)

	moveq	#0,d0

	rts

.bad_handle:
	moveq	#HUMAN68K_ERROR_BAD_HANDLE,d0

	rts

; _READ(handle.w, buffer.l, length.l)

human68k_read:
	move.l	#_LVORead,d7

	bra		read_or_write

; _WRITE(handle.w, buffer.l, length.l)

human68k_write:
	move.l	#_LVOWrite,d7

read_or_write:
	move	(a5),d0
	jsr		get_file_handle
	beq		.bad_handle

	move.l	d0,d1
	move.l	2(a5),d2
	move.l	6(a5),d3
	and.l	#$7fffffff,d3 ; Human68k uses bit 31 as a flag (as on the Falcon).
	move.l	dos_base,a6
	jsr		(a6,d7.l)

	tst.l	d0
	bpl		.done

	moveq	#HUMAN68K_ERROR_IO,d0

.done:
	rts

.bad_handle:
	moveq	#HUMAN68K_ERROR_BAD_HANDLE,d0

	rts

; _SEEK(handle.w, offset.l, mode.w): mode 0 = start, 1 = current, 2 = end.
; Returns the new position (AmigaDOS Seek returns the old one).

human68k_seek:
	move	(a5),d0
	jsr		get_file_handle
	beq		.bad_handle

	move.l	d0,d4

	move	6(a5),d0
	lea		seek_mode_table,a0
	and		#3,d0
	move.l	(a0,d0.w*4),d3

	move.l	dos_base,a6
	move.l	d4,d1
	move.l	2(a5),d2
	jsr		_LVOSeek(a6)
	tst.l	d0
	bmi		.error

	move.l	d4,d1
	moveq	#0,d2
	moveq	#OFFSET_CURRENT,d3
	jsr		_LVOSeek(a6)

	rts

.error:
	moveq	#HUMAN68K_ERROR_IO,d0

	rts

.bad_handle:
	moveq	#HUMAN68K_ERROR_BAD_HANDLE,d0

	rts

; _DELETE(name.l)

human68k_delete:
	move.l	(a5),a0
	jsr		convert_path

	move.l	dos_base,a6
	move.l	#path_buffer,d1
	jsr		_LVODeleteFile(a6)
	tst.l	d0
	beq		.not_found

	moveq	#0,d0

	rts

.not_found:
	moveq	#HUMAN68K_ERROR_FILE_NOT_FOUND,d0

	rts

; ------------------------------------------------------------------------------
;
; Returns d0.l = free slot index, or a Human68k error.

find_free_handle:
	lea		file_handles,a0
	moveq	#0,d0

.loop:
	tst.l	(a0)+
	beq		.found

	addq.l	#1,d0
	cmp.l	#NUMBER_OF_FILE_HANDLES,d0
	bne		.loop

	moveq	#HUMAN68K_ERROR_TOO_MANY_FILES,d0

.found:
	rts

; d0.w = Human68k handle. Returns d0.l = AmigaDOS handle (Z set if none) and
; a0 = its slot.

get_file_handle:
	ext.l	d0
	sub.l	#FIRST_FILE_HANDLE,d0
	bmi		.none

	cmp.l	#NUMBER_OF_FILE_HANDLES,d0
	bcc		.none

	lea		file_handles,a0
	lsl.l	#2,d0
	add.l	d0,a0
	move.l	(a0),d0

	rts

.none:
	moveq	#0,d0

	rts

close_all_files:
	lea		file_handles,a2
	moveq	#NUMBER_OF_FILE_HANDLES-1,d2
	move.l	dos_base,a6

.loop:
	move.l	(a2),d1
	beq		.next

	clr.l	(a2)
	jsr		_LVOClose(a6)

.next:
	addq.l	#4,a2

	dbf		d2,.loop

	rts

; a0 = Human68k path. Copies it to path_buffer with '\' (also the Shift-JIS
; yen sign, the same byte) turned into '/'.

convert_path:
	lea		path_buffer,a1
	move	#256-2,d1

.loop:
	move.b	(a0)+,d0
	cmp.b	#'\',d0
	bne		.store

	moveq	#'/',d0

.store:
	move.b	d0,(a1)+
	dbeq	d1,.loop

	clr.b	(a1)

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

timer_name:
	dc.b	'timer.device',0

vbl_interrupt_name:
	dc.b	'Cho Ren Sha 68k VBL',0

	ifd __DEBUG_OUTPUT__

trace_call_format:
	dc.b	'Human68k call $%04lx (frame %ld) %s sp=$%08lx heap=$%08lx args %08lx %08lx %08lx',10,0

trace_iocs_format:
	dc.b	'IOCS $%02lx',10,0

trace_result_format:
	dc.b	'  -> $%08lx',10,0


trace_exception_format:
	dc.b	'trap %ld at $%08lx',10,0

trace_empty_text:
	dc.b	0

trace_heartbeat_text:
	dc.b	'(50 VBL) state %ld sigwait $%08lx sp $%08lx sigrecvd $%08lx running: %s (pri %ld) pc offset $%lx sr $%04lx pc $%08lx traps %ld frames %ld succ $%lx pred $%lx ready $%lx id %ld td %ld me $%lx idle %ld disp %ld vbl %ld',10
	dc.b	'  stack: %08lx %08lx %08lx %08lx %08lx %08lx %08lx %08lx',10
	dc.b	'  stack: %08lx %08lx %08lx %08lx %08lx %08lx %08lx %08lx',10
	dc.b	'  stack: %08lx %08lx %08lx %08lx %08lx %08lx %08lx %08lx',10
	dc.b	'  last alert: $%08lx $%08lx last trap %ld at code $%lx d0 $%lx',10,0

	endif

exception_format:
	dc.b	'Exception %ld at $%08lx (code offset $%lx).',10,0

graphics_file_name:
	dc.b	'graphics.bin',0

graphics_dump_magic:
	dc.b	'CRSG'

	even

graphics_dump_parts:
	dc.l	graphics_dump_magic,4
	dc.l	L_00C00000,$100000
	dc.l	L_00E82000,$400
	dc.l	sprite_palette_usage,2048*2
	dc.l	-1,PCG_PATTERNS*128
	dc.l	0

unimplemented_call_format:
	dc.b	'Unimplemented Human68k call $%04lx.',10,0

	even

seek_mode_table:
	dc.l	OFFSET_BEGINNING,OFFSET_CURRENT,OFFSET_END,OFFSET_END

human68k_call_table:
	dc.w	$fe00
	dc.l	human68k_lmul
	dc.w	$fe01
	dc.l	human68k_ldiv
	dc.w	$fe0d ; __SRAND
	dc.l	human68k_return_zero
	dc.w	$ff00 ; _EXIT
	dc.l	human68k_exit
	dc.w	$ff06 ; _INPOUT
	dc.l	human68k_return_zero
	dc.w	$ff09 ; _PRINT
	dc.l	human68k_print
	dc.w	$ff0d ; _FFLUSH
	dc.l	human68k_return_zero
	dc.w	$ff20 ; _SUPER
	dc.l	human68k_return_zero
	dc.w	$ff23 ; _CONCTRL
	dc.l	human68k_return_zero
	dc.w	$ff25 ; _INTVCS
	dc.l	human68k_return_zero
	dc.w	$ff21 ; _FNCKEY
	dc.l	human68k_return_zero
	dc.w	$ff36 ; _DSKFRE
	dc.l	human68k_dskfre
	dc.w	$ff37 ; _NAMECK
	dc.l	human68k_nameck
	dc.w	$ff3c ; _CREATE
	dc.l	human68k_create
	dc.w	$ff3d ; _OPEN
	dc.l	human68k_open
	dc.w	$ff3e ; _CLOSE
	dc.l	human68k_close
	dc.w	$ff3f ; _READ
	dc.l	human68k_read
	dc.w	$ff40 ; _WRITE
	dc.l	human68k_write
	dc.w	$ff41 ; _DELETE
	dc.l	human68k_delete
	dc.w	$ff42 ; _SEEK
	dc.l	human68k_seek
	dc.w	$ff44 ; _IOCTRL
	dc.l	human68k_return_zero
	dc.w	$ff4a ; _SETBLOCK
	dc.l	human68k_setblock
	dc.w	$ff4c ; _EXIT2
	dc.l	human68k_exit
	dc.w	$ff51 ; _GETPDB
	dc.l	human68k_getpdb
	dc.w	0

iocs_joystick_data:
	dc.l	-1 ; Nothing pressed (bits are active low).

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

	xdef heap_address
	xdef heap_used
	xdef frame_count
	xdef measured_frames
	xdef frame_records
	xdef eclock_frequency
	xdef unimplemented_iocs

main_task:
	ds.l	1
game_stack_swap:
	ds.l	3 ; struct StackSwapStruct
game_stack_pointer:
	ds.l	1
old_trap_code:
	ds.l	1
vbl_signal_number:
	ds.l	1
vbl_signal_mask:
	ds.l	1
heap_address:
	ds.l	1
heap_used:
	ds.l	1
timer_base:
	ds.l	1
frame_limit:
	ds.l	1
frame_count:
	ds.l	1
measured_frames:
	ds.l	1
eclock_frequency:
	ds.l	1
eclock_value:
	ds.l	2
last_wake_time:
	ds.l	2
print_arguments:
	ds.l	10
total_vbl_count:
	ds.l	1
vbl_count_at_wake:
	ds.l	1

vbl_wait_counter:
	ds.w	1
pending_call_number:
	ds.w	1

	even

call_input_d0:
	ds.l	1
traps_handled:
	ds.l	1
last_trap_number:
	ds.l	1
last_trap_pc:
	ds.l	1
last_trap_d0:
	ds.l	1
exception_number:
	ds.l	1
exception_pc:
	ds.l	1

	even

vbl_interrupt:
	ds.b	IS_SIZE

	even

timer_request:
	ds.b	TIMEREQUEST_SIZE

file_handles:
	ds.l	NUMBER_OF_FILE_HANDLES

keyboard_matrix:
	ds.b	16

unimplemented_iocs:
	ds.b	256

path_buffer:
	ds.b	256

printf_format_buffer:
	ds.b	256

printf_text_buffer:
	ds.b	1024

	ifd __DEBUG_OUTPUT__

trace_buffer:
	ds.b	512

	even

trace_iocs_arguments:
	ds.l	2
trace_heartbeat_arguments:
	ds.l	49
trace_heartbeat_buffer:
	ds.b	512

	endif

; Per measured frame: E clock ticks used (long), sprites (word), vertical
; blanks that passed while the game was working on the frame (word).

frame_records: ; Allocated when measuring.
	ds.l	1
frame_records_size:
	ds.l	1
maximum_records:
	ds.l	1
heap_size:
	ds.l	1

os_stack_swap:
	ds.l	3 ; struct StackSwapStruct
os_stack_result:
	ds.l	1
os_stack_active:
	ds.b	1

	even

os_stack:
	ds.b	OS_STACK_SIZE

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
