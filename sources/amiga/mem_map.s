
; X68000 I/O regions the game core touches, as RAM shadow buffers. The game
; writes its hardware registers here harmlessly; the port layer reads back
; what it needs (palettes, scroll registers, text planes, GVRAM).
;
; Unlike the Atari port, GVRAM is kept: the Amiga port lets the game's own
; INITIALIZE_SPRITES_AND_GRAPHICS build both 256-colour background pages here
; (2 pages * $80000 = $100000), instead of using a pre-flattened image.

	xdef L_00C00000,L_00E00000,L_00E20000,L_00E80000,L_00E82000,L_00E88000
	xdef L_00E8E000,L_00EB0000,L_00EB8000

	xdef L_00000118,L_00000138

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

dummy_interrupt_handler:
	rte

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

	even

L_00000118:   ; MFP V-DISP vector (game VBL handler).
	dc.l	dummy_interrupt_handler

L_00000138:   ; MFP CRTC IRQ vector (game raster handler).
	dc.l	dummy_interrupt_handler

; ------------------------------------------------------------------------------
; The shadows are in sections of their own (separate hunks), so the loader
; does not need one contiguous block for all of them: machines with 4 MB of
; fast RAM have no single free block of 3 MB.
; ------------------------------------------------------------------------------

	section	gvram_shadow,bss

	align 4

L_00C00000:   ; GVRAM, pages 0 and 1 (512 * 512 * 2 bytes each).
	ds.b    $100000

	section	text_shadow,bss ; The four planes must stay together.

	align 4
L_00E00000:   ; TEXT PLANE 1
	ds.b    $20000
L_00E20000:   ; TEXT PLANE 2
	ds.b    $20000
L_00E40000:   ; TEXT PLANE 3
	ds.b    $20000
L_00E60000:   ; TEXT PLANE 4
	ds.b    $20000
L_00E80000:   ; CRTC
	ds.b    $2000
L_00E82000:   ; VIDEO CONTROLLER
	ds.b    $2000
L_00E88000:   ; MFP
	ds.b    $2000
L_00E8E000:   ; SYSTEM PORT
	ds.b    $2000
L_00EB0000:   ; SPRITE REGISTERS
	ds.b    $8000
L_00EB8000:   ; SPRITE VRAM
	ds.b    $8000

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
