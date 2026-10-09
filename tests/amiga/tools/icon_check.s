; icon_check: loads icons through icon.library (GetDiskObject) and prints
; what Workbench will see: type, image size and depth, drawer data, stack
; size and tool types. A test for generated .info files.
;
; usage: icon_check <name> [<name> ...]   (names without .info)

; exec.library

_LVOOpenLibrary=-552
_LVOCloseLibrary=-414

; dos.library

_LVOReadArgs=-798
_LVOFreeArgs=-858
_LVOVPrintf=-954

; icon.library

_LVOGetDiskObject=-78
_LVOFreeDiskObject=-90

do_Gadget=4
gg_GadgetRender=18
do_Type=48
do_ToolTypes=54
do_DrawerData=66
do_StackSize=74
ig_Width=4
ig_Height=6
ig_Depth=8

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

start:
	movem.l	d2-d7/a2-a6,-(sp)

	moveq	#20,d7 ; Return code: failure until all icons loaded.

	move.l	4.w,a6
	lea		dos_name,a1
	moveq	#36,d0
	jsr		-552(a6)
	move.l	d0,dos_base
	beq		.exit

	lea		icon_name,a1
	moveq	#36,d0
	jsr		-552(a6)
	move.l	d0,icon_base
	beq		.close_dos

	move.l	dos_base,a6
	move.l	#template,d1
	move.l	#argument_array,d2
	moveq	#0,d3
	jsr		_LVOReadArgs(a6)
	move.l	d0,read_args
	beq		.close_icon

	moveq	#0,d7
	move.l	argument_array,a2 ; NULL-terminated name list.

.name_loop:
	move.l	(a2)+,d0
	beq		.free_args

	move.l	d0,a3
	move.l	icon_base,a6
	move.l	a3,a0
	jsr		_LVOGetDiskObject(a6)
	move.l	d0,a4
	tst.l	d0
	bne		.loaded

	move.l	a3,print_arguments
	lea		not_loaded_format,a0
	bsr		print
	moveq	#10,d7

	bra		.name_loop

.loaded:
	lea		print_arguments,a1
	move.l	a3,(a1)+
	moveq	#0,d0
	move.b	do_Type(a4),d0
	move.l	d0,(a1)+
	move.l	do_Gadget+gg_GadgetRender(a4),a0 ; Image.
	moveq	#0,d0
	move	ig_Width(a0),d0
	move.l	d0,(a1)+
	move	ig_Height(a0),d0
	move.l	d0,(a1)+
	move	ig_Depth(a0),d0
	move.l	d0,(a1)+
	moveq	#0,d0
	tst.l	do_DrawerData(a4)
	sne		d0
	neg.b	d0
	move.l	d0,(a1)+
	move.l	do_StackSize(a4),(a1)+
	lea		icon_format,a0
	bsr		print

	move.l	do_ToolTypes(a4),d0
	beq		.free_icon

	move.l	d0,a5

.tool_type_loop:
	move.l	(a5)+,d0
	beq		.free_icon

	move.l	d0,print_arguments
	lea		tool_type_format,a0
	bsr		print

	bra		.tool_type_loop

.free_icon:
	move.l	icon_base,a6
	move.l	a4,a0
	jsr		_LVOFreeDiskObject(a6)

	bra		.name_loop

.free_args:
	move.l	dos_base,a6
	move.l	read_args,d1
	jsr		_LVOFreeArgs(a6)

.close_icon:
	move.l	4.w,a6
	move.l	icon_base,a1
	jsr		_LVOCloseLibrary(a6)

.close_dos:
	move.l	4.w,a6
	move.l	dos_base,a1
	jsr		_LVOCloseLibrary(a6)

.exit:
	move.l	d7,d0
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; a0 = format, arguments in print_arguments.

print:
	movem.l	d1-d2/a6,-(sp)

	move.l	dos_base,a6
	move.l	a0,d1
	move.l	#print_arguments,d2
	jsr		_LVOVPrintf(a6)

	movem.l	(sp)+,d1-d2/a6

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

dos_name:
	dc.b	'dos.library',0
icon_name:
	dc.b	'icon.library',0
template:
	dc.b	'NAMES/M/A',0
icon_format:
	dc.b	'%s: type %ld, image %ld x %ld x %ld, drawer data %ld, stack %ld',10,0
tool_type_format:
	dc.b	'  tool type: %s',10,0
not_loaded_format:
	dc.b	'%s: GetDiskObject failed',10,0

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

	even

dos_base:
	ds.l	1
icon_base:
	ds.l	1
read_args:
	ds.l	1
argument_array:
	ds.l	1
print_arguments:
	ds.l	8

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
