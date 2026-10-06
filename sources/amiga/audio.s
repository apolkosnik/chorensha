; Audio: the X68000's ADPCM sound effects on Paula.
;
; The game plays its effects with IOCS _ADPCMOUT, one at a time (it keeps the
; priority of the effect playing and asks _ADPCMSNS whether it still plays).
; The samples are the original MSM6258 ADPCM files (PCM_DAT), loaded by the
; game into its heap. Once they are loaded (amiga_samples_loaded, called
; after LOAD_PCM_SAMPLE_FILES) each file is decoded once into 8-bit PCM in
; chip RAM, and the game's sample table is pointed at the decoded data.
;
; Decoding follows the MSM6258 as wired in the X68000 (MAME okim6258 with
; 10-bit output): signal starts at -2 and step at 0 for every sample, low
; nibble first, the signal is clamped to 10 bits and played as signal >> 2.
;
; Playback: channels 0 (left) and 1 (right), allocated through audio.device
; for the whole run, so the effects sound centred like the X68000's mono
; ADPCM sent to both sides. Channels 2 and 3 are allocated as well and left
; silent for the music. Paula plays the decoded data at the X68000 rate
; (15625 Hz: period 227 on PAL machines), then loops a silent word.

	xdef initialize_audio
	xdef release_audio
	xdef decode_samples
	xdef audio_play
	xdef audio_stop
	xdef audio_status
	xdef write_samples_dump

	xref exec_base
	xref dos_base
	xref timer_base
	xref total_vbl_count
	xref frame_timer_hz100
	xref PCM_SAMPLE_INFO_TABLE

; exec.library

_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOOpenDevice=-444
_LVOCloseDevice=-450
_LVOCreateMsgPort=-666
_LVODeleteMsgPort=-672

MEMF_CHIP=1<<1
MEMF_CLEAR=1<<16

; dos.library

_LVOOpen=-30
_LVOClose=-36
_LVOWrite=-48

MODE_NEWFILE=1006

; timer.device

_LVOReadEClock=-60

; IOAudio

ln_Pri=9
mn_ReplyPort=14
ioa_AllocKey=32
ioa_Data=34
ioa_Length=38
IOAUDIO_SIZE=68

; Paula

DMACON=$dff096
VHPOSR=$dff006
AUD0LC=$dff0a0
AUD1LC=$dff0b0
AUD2LC=$dff0c0
AUD3LC=$dff0d0
ac_len=4
ac_per=6
ac_vol=8

DMAF_SETCLR=$8000
DMAF_MASTER=$0200
EFFECT_CHANNELS=%0011 ; 0 left, 1 right.
ALL_CHANNELS=%1111

MAXIMUM_VOLUME=64

; Game sample table: 256 entries of 16 bytes.

SAMPLE_ENTRIES=256
SAMPLE_ENTRY_SIZE=16
se_mode=0
se_length=2
se_address=6

; MSM6258 decoder.

DECODER_STEPS=49
SIGNAL_MAXIMUM=511
SIGNAL_MINIMUM=-512

; Lines to wait (on VHPOSR) for Paula to stop a channel's DMA before it is
; restarted, and to fetch the start of a new sample before the loop pointer
; is replaced: at least one sample period each (4 lines at 3.9 kHz).

DMA_STOP_LINES=5
DMA_START_LINES=5

; ------------------------------------------------------------------------------
	text
; ------------------------------------------------------------------------------

; Allocates the audio channels and the silent loop. Called from
; start_emulator (task context, OS stack). Without channels the game runs
; silently.

initialize_audio:
	movem.l	d2-d7/a2-a6,-(sp)

	clr.b	audio_available
	clr.b	samples_decoded
	clr.l	sample_memory

	bsr		build_decoder_table

	; Paula periods for the five X68000 rates: Paula clock (E clock * 5) *
	; divider / ADPCM clock.

	move.l	timer_base,a6
	lea		eclock_value,a0
	jsr		_LVOReadEClock(a6)
	mulu.l	#5,d0
	move.l	d0,d2

	lea		adpcm_rates,a0
	lea		adpcm_periods,a1
	moveq	#5-1,d3

.period_loop:
	move.l	d2,d0
	mulu.l	(a0)+,d0 ; Divider.
	move.l	(a0)+,d1 ; ADPCM clock.
	move.l	d1,d4
	lsr.l	#1,d4
	add.l	d4,d0
	divu.l	d1,d0
	move	d0,(a1)+

	dbf		d3,.period_loop

	; Silent loop (one word of chip RAM).

	move.l	exec_base,a6
	moveq	#4,d0
	move.l	#MEMF_CHIP|MEMF_CLEAR,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,silence
	beq		.done

	; All four channels through audio.device.

	jsr		_LVOCreateMsgPort(a6)
	move.l	d0,audio_port
	beq		.free_silence

	lea		audio_request,a1
	move.l	d0,mn_ReplyPort(a1)
	move.b	#127,ln_Pri(a1)
	move.l	#channel_combinations,ioa_Data(a1)
	move.l	#1,ioa_Length(a1)
	lea		audio_name,a0
	moveq	#0,d0
	moveq	#0,d1
	jsr		_LVOOpenDevice(a6)
	tst.l	d0
	bne		.delete_port

	move	#ALL_CHANNELS,DMACON
	moveq	#0,d0
	move	d0,AUD0LC+ac_vol
	move	d0,AUD1LC+ac_vol
	move	d0,AUD2LC+ac_vol
	move	d0,AUD3LC+ac_vol

	clr.l	effect_end_tick
	clr.l	effects_played
	st		audio_available

	bra		.done

.delete_port:
	move.l	audio_port,a0
	jsr		_LVODeleteMsgPort(a6)
	clr.l	audio_port

.free_silence:
	move.l	silence,a1
	moveq	#4,d0
	jsr		_LVOFreeMem(a6)
	clr.l	silence

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------

release_audio:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	exec_base,a6

	tst.b	audio_available
	beq		.no_channels

	clr.b	audio_available

	move	#ALL_CHANNELS,DMACON
	moveq	#0,d0
	move	d0,AUD0LC+ac_vol
	move	d0,AUD1LC+ac_vol
	move	d0,AUD2LC+ac_vol
	move	d0,AUD3LC+ac_vol

	lea		audio_request,a1
	jsr		_LVOCloseDevice(a6)

	move.l	audio_port,a0
	jsr		_LVODeleteMsgPort(a6)
	clr.l	audio_port

	move.l	silence,a1
	moveq	#4,d0
	jsr		_LVOFreeMem(a6)
	clr.l	silence

.no_channels:
	move.l	sample_memory,d0
	beq		.done

	move.l	d0,a1
	move.l	sample_memory_size,d0
	jsr		_LVOFreeMem(a6)
	clr.l	sample_memory

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
;
; Decodes the samples the game loaded into chip RAM and points the game's
; sample table at them (length in bytes of 8-bit PCM). Several entries can
; share one file: each file is decoded once. Called on the OS stack. If
; there are no channels or not enough chip RAM, the table is left alone and
; nothing is played.

decode_samples:
	movem.l	d2-d7/a2-a6,-(sp)

	tst.b	audio_available
	beq		.done

	; Keep the original addresses: entries are rewritten while later ones
	; are still compared against them.

	lea		PCM_SAMPLE_INFO_TABLE,a0
	lea		original_addresses,a1
	move	#SAMPLE_ENTRIES-1,d0

.copy_addresses:
	move.l	se_address(a0),d1
	tst.l	se_length(a0)
	bne		.address_valid

	moveq	#0,d1

.address_valid:
	move.l	d1,(a1)+
	lea		SAMPLE_ENTRY_SIZE(a0),a0

	dbf		d0,.copy_addresses

	; Chip RAM needed: two bytes per ADPCM byte for each distinct file.

	moveq	#0,d2
	moveq	#0,d3 ; Entry.
	lea		PCM_SAMPLE_INFO_TABLE,a2

.size_loop:
	bsr		find_first_entry
	cmp.l	d0,d3
	bne		.size_next ; Unused, or a file seen before.

	move.l	se_length(a2),d0
	add.l	d0,d0
	add.l	d0,d2

.size_next:
	lea		SAMPLE_ENTRY_SIZE(a2),a2
	addq.l	#1,d3
	cmp.l	#SAMPLE_ENTRIES,d3
	bne		.size_loop

	tst.l	d2
	beq		.done

	move.l	d2,sample_memory_size
	move.l	d2,d0
	moveq	#MEMF_CHIP,d1
	move.l	exec_base,a6
	jsr		_LVOAllocMem(a6)
	move.l	d0,sample_memory
	beq		.done

	; Decode, and rewrite the entries.

	move.l	d0,a3 ; Next free byte.
	moveq	#0,d3
	lea		PCM_SAMPLE_INFO_TABLE,a2

.decode_loop:
	bsr		find_first_entry
	tst.l	d0
	bmi		.decode_next

	cmp.l	d0,d3
	beq		.decode_file

	; Same file as entry d0, which is already rewritten.

	lea		PCM_SAMPLE_INFO_TABLE,a0
	lsl.l	#4,d0
	move.l	se_length(a0,d0.l),se_length(a2)
	move.l	se_address(a0,d0.l),se_address(a2)

	bra		.decode_next

.decode_file:
	move.l	se_address(a2),a0
	move.l	a3,a1
	move.l	se_length(a2),d0
	bsr		decode_adpcm

	move.l	se_length(a2),d0
	add.l	d0,d0
	move.l	d0,se_length(a2)
	move.l	a3,se_address(a2)
	add.l	d0,a3

.decode_next:
	lea		SAMPLE_ENTRY_SIZE(a2),a2
	addq.l	#1,d3
	cmp.l	#SAMPLE_ENTRIES,d3
	bne		.decode_loop

	st		samples_decoded

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; d3.l = entry. Returns d0.l = the first entry with the same original
; address, or -1 if the entry is unused.

find_first_entry:
	lea		original_addresses,a0
	move.l	(a0,d3.l*4),d1
	beq		.unused

	moveq	#0,d0

.loop:
	cmp.l	(a0)+,d1
	beq		.found

	addq.l	#1,d0
	bra		.loop

.found:
	rts

.unused:
	moveq	#-1,d0

	rts

; ------------------------------------------------------------------------------
;
; Decodes MSM6258 ADPCM to 8-bit PCM. a0 = ADPCM, a1 = destination, d0.l =
; ADPCM bytes (two samples each).
;
; decoder_table holds, for each step (64 bytes apart) and nibble, the signal
; difference (word) and the offset of the next step (word).

decode_adpcm:
	movem.l	d2-d7/a2,-(sp)

	lea		decoder_table,a2
	move.l	d0,d2
	beq		.done

	moveq	#-2,d3 ; Signal.
	moveq	#0,d4 ; Step offset.
	move	#SIGNAL_MAXIMUM,d0
	move	#SIGNAL_MINIMUM,d1

.loop:
	move.b	(a0)+,d5

	moveq	#$f,d6
	and		d5,d6
	lsl		#2,d6
	add		d4,d6
	add		(a2,d6.w),d3
	move	2(a2,d6.w),d4

	cmp		d0,d3
	ble		.not_above1

	move	d0,d3

.not_above1:
	cmp		d1,d3
	bge		.not_below1

	move	d1,d3

.not_below1:
	move	d3,d7
	asr		#2,d7
	move.b	d7,(a1)+

	lsr.b	#4,d5
	moveq	#0,d6
	move.b	d5,d6
	lsl		#2,d6
	add		d4,d6
	add		(a2,d6.w),d3
	move	2(a2,d6.w),d4

	cmp		d0,d3
	ble		.not_above2

	move	d0,d3

.not_above2:
	cmp		d1,d3
	bge		.not_below2

	move	d1,d3

.not_below2:
	move	d3,d7
	asr		#2,d7
	move.b	d7,(a1)+

	subq.l	#1,d2
	bne		.loop

.done:
	movem.l	(sp)+,d2-d7/a2

	rts

; Builds decoder_table from difference_table and step_shifts.

build_decoder_table:
	lea		difference_table,a0
	lea		decoder_table,a1
	moveq	#0,d0 ; Step.

.step_loop:
	moveq	#0,d1 ; Nibble.

.nibble_loop:
	move	(a0)+,(a1)+

	moveq	#7,d2
	and		d1,d2
	lea		step_shifts,a2
	move	d0,d3
	add		(a2,d2.w*2),d3
	bpl		.not_below

	moveq	#0,d3

.not_below:
	cmp		#DECODER_STEPS-1,d3
	ble		.not_above

	moveq	#DECODER_STEPS-1,d3

.not_above:
	lsl		#6,d3
	move	d3,(a1)+

	addq	#1,d1
	cmp		#16,d1
	bne		.nibble_loop

	addq	#1,d0
	cmp		#DECODER_STEPS,d0
	bne		.step_loop

	rts

; ------------------------------------------------------------------------------
;
; _ADPCMOUT: a1 = sample, d1 = mode (rate * 256 + output: 1 left, 2 right,
; 3 both), d2 = length in bytes. Supervisor mode (trap handler); no OS
; calls. Preserves all registers.

audio_play:
	movem.l	d0-d4/a0-a1,-(sp)

	tst.b	samples_decoded
	beq		.done

	moveq	#EFFECT_CHANNELS,d3
	and		d1,d3 ; Output bits = channel bits.
	beq		.done

	move.l	d2,d0
	lsr.l	#1,d0 ; Words.
	beq		.done

	cmp.l	#$ffff,d0
	bls		.length_ok

	move.l	#$ffff,d0

.length_ok:
	moveq	#0,d4
	move	d1,d4
	lsr		#8,d4
	cmp		#4,d4
	bls		.rate_ok

	moveq	#4,d4

.rate_ok:
	; Expected end of the effect, in frame timer ticks, for _ADPCMSNS.

	move.l	d2,d1
	mulu.l	frame_timer_hz100,d1
	lea		adpcm_rates_hz100,a0
	divu.l	(a0,d4.w*4),d1
	addq.l	#1,d1
	add.l	total_vbl_count,d1
	move.l	d1,effect_end_tick

	lea		adpcm_periods,a0
	move	(a0,d4.w*2),d4

	; Stop the effect channels and give Paula time to let go of them.

	move	#EFFECT_CHANNELS,DMACON
	moveq	#DMA_STOP_LINES,d2
	bsr		wait_lines

	move.l	a1,AUD0LC
	move	d0,AUD0LC+ac_len
	move	d4,AUD0LC+ac_per
	move.l	a1,AUD1LC
	move	d0,AUD1LC+ac_len
	move	d4,AUD1LC+ac_per

	moveq	#0,d2
	btst	#0,d3
	beq		.left_set

	moveq	#MAXIMUM_VOLUME,d2

.left_set:
	move	d2,AUD0LC+ac_vol
	moveq	#0,d2
	btst	#1,d3
	beq		.right_set

	moveq	#MAXIMUM_VOLUME,d2

.right_set:
	move	d2,AUD1LC+ac_vol

	move	#DMAF_SETCLR|DMAF_MASTER|EFFECT_CHANNELS,DMACON
	addq.l	#1,effects_played

	; Once Paula has taken the start of the sample, the next loop is the
	; silent word.

	moveq	#DMA_START_LINES,d2
	bsr		wait_lines

	move.l	silence,a0
	move.l	a0,AUD0LC
	move	#1,AUD0LC+ac_len
	move.l	a0,AUD1LC
	move	#1,AUD1LC+ac_len

.done:
	movem.l	(sp)+,d0-d4/a0-a1

	rts

; d2.w = number of raster lines to wait for (line changes on VHPOSR).

wait_lines:
	move.b	VHPOSR,d1

.line_loop:
	cmp.b	VHPOSR,d1
	beq		.line_loop

	move.b	VHPOSR,d1
	subq	#1,d2
	bne		.line_loop

	rts

; ------------------------------------------------------------------------------
;
; _ADPCMMOD 0: stops the effect. Preserves all registers.

audio_stop:
	tst.b	audio_available
	beq		.done

	move	#EFFECT_CHANNELS,DMACON
	clr.l	effect_end_tick

.done:
	rts

; ------------------------------------------------------------------------------
;
; _ADPCMSNS: returns d0.l = 2 while an effect plays, else 0.

audio_status:
	moveq	#0,d0
	tst.l	effect_end_tick
	beq		.done

	move.l	total_vbl_count,d0
	cmp.l	effect_end_tick,d0
	scs		d0
	and.l	#2,d0

.done:
	rts

; ------------------------------------------------------------------------------
;
; Measurement runs: samples.bin, for tests/amiga/samples_check.py. 'CRSA',
; effects played (long), chip RAM address (long) and size (long) of the
; decoded samples, the game's sample table (256 x 16 bytes, as rewritten),
; then the decoded samples. Without decoded samples the size is 0.

write_samples_dump:
	movem.l	d2-d4/a6,-(sp)

	move.l	dos_base,a6

	move.l	#samples_file_name,d1
	move.l	#MODE_NEWFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,d4
	beq		.done

	lea		samples_header,a0
	move.l	#'CRSA',(a0)
	move.l	effects_played,4(a0)
	move.l	sample_memory,8(a0)
	clr.l	12(a0)
	tst.b	samples_decoded
	beq		.header_done

	move.l	sample_memory_size,12(a0)

.header_done:
	move.l	d4,d1
	move.l	a0,d2
	moveq	#16,d3
	jsr		_LVOWrite(a6)

	move.l	d4,d1
	move.l	#PCM_SAMPLE_INFO_TABLE,d2
	move.l	#SAMPLE_ENTRIES*SAMPLE_ENTRY_SIZE,d3
	jsr		_LVOWrite(a6)

	move.l	samples_header+12,d3
	beq		.close

	move.l	d4,d1
	move.l	sample_memory,d2
	jsr		_LVOWrite(a6)

.close:
	move.l	d4,d1
	jsr		_LVOClose(a6)

.done:
	movem.l	(sp)+,d2-d4/a6

	rts

; ------------------------------------------------------------------------------
	data
; ------------------------------------------------------------------------------

samples_file_name:
	dc.b	'samples.bin',0

	even

audio_name:
	dc.b	'audio.device',0

channel_combinations:
	dc.b	ALL_CHANNELS

	even

; X68000 ADPCM rates (_ADPCMOUT mode bits 8-10): divider and ADPCM clock.

adpcm_rates:
	dc.l	1024,4000000 ; 3.9 kHz
	dc.l	768,4000000 ; 5.2 kHz
	dc.l	1024,8000000 ; 7.8 kHz
	dc.l	768,8000000 ; 10.4 kHz
	dc.l	512,8000000 ; 15.6 kHz

; The same rates * 100, for the effect's length in frame timer ticks:
; samples * (timer Hz * 100) / (rate * 100).

adpcm_rates_hz100:
	dc.l	4000000*100/1024
	dc.l	4000000*100/768
	dc.l	8000000*100/1024
	dc.l	8000000*100/768
	dc.l	8000000*100/512

step_shifts:
	dc.w	-1,-1,-1,-1,2,4,6,8

; Signal difference per step (16 * 1.1^step, as in MAME's okim6258) and
; nibble.

difference_table:
	dc.w	2,6,10,14,18,22,26,30,-2,-6,-10,-14,-18,-22,-26,-30
	dc.w	2,6,10,14,19,23,27,31,-2,-6,-10,-14,-19,-23,-27,-31
	dc.w	2,6,11,15,21,25,30,34,-2,-6,-11,-15,-21,-25,-30,-34
	dc.w	2,7,12,17,23,28,33,38,-2,-7,-12,-17,-23,-28,-33,-38
	dc.w	2,7,13,18,25,30,36,41,-2,-7,-13,-18,-25,-30,-36,-41
	dc.w	3,9,15,21,28,34,40,46,-3,-9,-15,-21,-28,-34,-40,-46
	dc.w	3,10,17,24,31,38,45,52,-3,-10,-17,-24,-31,-38,-45,-52
	dc.w	3,10,18,25,34,41,49,56,-3,-10,-18,-25,-34,-41,-49,-56
	dc.w	4,12,21,29,38,46,55,63,-4,-12,-21,-29,-38,-46,-55,-63
	dc.w	4,13,22,31,41,50,59,68,-4,-13,-22,-31,-41,-50,-59,-68
	dc.w	5,15,25,35,46,56,66,76,-5,-15,-25,-35,-46,-56,-66,-76
	dc.w	5,16,27,38,50,61,72,83,-5,-16,-27,-38,-50,-61,-72,-83
	dc.w	6,18,31,43,56,68,81,93,-6,-18,-31,-43,-56,-68,-81,-93
	dc.w	6,19,33,46,61,74,88,101,-6,-19,-33,-46,-61,-74,-88,-101
	dc.w	7,22,37,52,67,82,97,112,-7,-22,-37,-52,-67,-82,-97,-112
	dc.w	8,24,41,57,74,90,107,123,-8,-24,-41,-57,-74,-90,-107,-123
	dc.w	9,27,45,63,82,100,118,136,-9,-27,-45,-63,-82,-100,-118,-136
	dc.w	10,30,50,70,90,110,130,150,-10,-30,-50,-70,-90,-110,-130,-150
	dc.w	11,33,55,77,99,121,143,165,-11,-33,-55,-77,-99,-121,-143,-165
	dc.w	12,36,60,84,109,133,157,181,-12,-36,-60,-84,-109,-133,-157,-181
	dc.w	13,39,66,92,120,146,173,199,-13,-39,-66,-92,-120,-146,-173,-199
	dc.w	14,43,73,102,132,161,191,220,-14,-43,-73,-102,-132,-161,-191,-220
	dc.w	16,48,81,113,146,178,211,243,-16,-48,-81,-113,-146,-178,-211,-243
	dc.w	17,52,88,123,160,195,231,266,-17,-52,-88,-123,-160,-195,-231,-266
	dc.w	19,58,97,136,176,215,254,293,-19,-58,-97,-136,-176,-215,-254,-293
	dc.w	21,64,107,150,194,237,280,323,-21,-64,-107,-150,-194,-237,-280,-323
	dc.w	23,70,118,165,213,260,308,355,-23,-70,-118,-165,-213,-260,-308,-355
	dc.w	26,78,130,182,235,287,339,391,-26,-78,-130,-182,-235,-287,-339,-391
	dc.w	28,85,143,200,258,315,373,430,-28,-85,-143,-200,-258,-315,-373,-430
	dc.w	31,94,157,220,284,347,410,473,-31,-94,-157,-220,-284,-347,-410,-473
	dc.w	34,103,173,242,313,382,452,521,-34,-103,-173,-242,-313,-382,-452,-521
	dc.w	38,114,191,267,345,421,498,574,-38,-114,-191,-267,-345,-421,-498,-574
	dc.w	42,126,210,294,379,463,547,631,-42,-126,-210,-294,-379,-463,-547,-631
	dc.w	46,138,231,323,417,509,602,694,-46,-138,-231,-323,-417,-509,-602,-694
	dc.w	51,153,255,357,459,561,663,765,-51,-153,-255,-357,-459,-561,-663,-765
	dc.w	56,168,280,392,505,617,729,841,-56,-168,-280,-392,-505,-617,-729,-841
	dc.w	61,184,308,431,555,678,802,925,-61,-184,-308,-431,-555,-678,-802,-925
	dc.w	68,204,340,476,612,748,884,1020,-68,-204,-340,-476,-612,-748,-884,-1020
	dc.w	74,223,373,522,672,821,971,1120,-74,-223,-373,-522,-672,-821,-971,-1120
	dc.w	82,246,411,575,740,904,1069,1233,-82,-246,-411,-575,-740,-904,-1069,-1233
	dc.w	90,271,452,633,814,995,1176,1357,-90,-271,-452,-633,-814,-995,-1176,-1357
	dc.w	99,298,497,696,895,1094,1293,1492,-99,-298,-497,-696,-895,-1094,-1293,-1492
	dc.w	109,328,547,766,985,1204,1423,1642,-109,-328,-547,-766,-985,-1204,-1423,-1642
	dc.w	120,360,601,841,1083,1323,1564,1804,-120,-360,-601,-841,-1083,-1323,-1564,-1804
	dc.w	132,397,662,927,1192,1457,1722,1987,-132,-397,-662,-927,-1192,-1457,-1722,-1987
	dc.w	145,436,728,1019,1311,1602,1894,2185,-145,-436,-728,-1019,-1311,-1602,-1894,-2185
	dc.w	160,480,801,1121,1442,1762,2083,2403,-160,-480,-801,-1121,-1442,-1762,-2083,-2403
	dc.w	176,528,881,1233,1587,1939,2292,2644,-176,-528,-881,-1233,-1587,-1939,-2292,-2644
	dc.w	194,582,970,1358,1746,2134,2522,2910,-194,-582,-970,-1358,-1746,-2134,-2522,-2910

; ------------------------------------------------------------------------------
	bss
; ------------------------------------------------------------------------------

audio_request:
	ds.b	IOAUDIO_SIZE

audio_port:
	ds.l	1

silence:
	ds.l	1

sample_memory:
	ds.l	1

sample_memory_size:
	ds.l	1

effect_end_tick:
	ds.l	1

effects_played:
	ds.l	1

samples_header:
	ds.l	4

eclock_value:
	ds.l	2

original_addresses:
	ds.l	SAMPLE_ENTRIES

decoder_table:
	ds.l	DECODER_STEPS*16

adpcm_periods:
	ds.w	5

audio_available:
	ds.b	1

samples_decoded:
	ds.b	1

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
