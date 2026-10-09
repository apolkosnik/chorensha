; Audio: the X68000's ADPCM sound effects and the MCDRV music on Paula.
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
; ADPCM sent to both sides. Channels 2 and 3 are allocated as well, for the
; music. Paula plays the decoded data at the X68000 rate (15625 Hz: period
; 227 on PAL machines), then loops a silent word.
;
; Music: the game plays its songs (BGM_DAT/*.MDC, YM2151) through MCDRV
; (trap #4). The songs are rendered from the original driver beforehand
; (tools/music/build_music.sh) into MUSIC_DAT/NAME.crm: 8-bit stereo, intro
; then loop, in blocks of 4096 frames, each block its left samples followed
; by its right samples. With MUSIC_DAT present, the MCDRV probe reports the
; driver, the game loads the songs named in SZ2_BGM.CNF as on the X68000
; (amiga_music_loaded keeps each song's file name), and the MCDRV calls
; play the matching stream:
; - A reader process streams the file into a ring of 8 blocks in chip RAM
;   (1.5 s at 22050 Hz), looping back to the loop start.
; - Paula plays the blocks on channels 3 (left) and 2 (right). Both run with
;   the same period and lengths, so they stay together; channel 2's audio
;   interrupt (at the start of each block) queues the next block and frees
;   the one that ended. Without a block ready, it queues silence.
; - The frame software interrupt passes the game's requests on to the
;   process (no OS calls in the trap handler) and runs _FADEOUT: MCDRV
;   lowers the level by 0.75 dB every speed ticks of the song, 64 steps
;   (the .crm header has the measured length per unit of speed), then the
;   song is silent and stops.
;
; AHI (argument "AHI" or "AHI=<mode id>"): instead of Paula, effects and
; music play through ahi.device's low-level API, for sound cards (and AHI's
; own Paula modes). Four mono channels as on Paula, hard left (even) and
; right (odd), so modes without panning (even channels left, odd right)
; play them the same: 0 and 1 the effects from the decoded samples (sound
; 1, any memory), 2 and 3 the music from the left and right halves of the
; ring's blocks (sound 0, a dynamic sample). The sound hook, called when a
; channel starts a sound, queues that channel's next half block (or the
; silence); a block is free once both sides have ended it, and the reader
; makes it ready for both sides at once, so they stay together. AHI calls
; are made from the frame software interrupt, the hook and the reader, never
; from the trap handler: effects and stops requested there start at the
; next frame tick. If AHI cannot be opened, Paula is used.
;
; MHI (argument "MHI" or "MHI=<driver>"): the music plays from MP3 files on
; an MHI decoder (LIBS:MHI/mhiz3660.library by default; effects stay on
; Paula or AHI): MUSIC_DAT/NAME_intro.mp3, then NAME_loop.mp3 again and
; again, which join without a gap (tools/music/make_amiga_music.py). The
; reader process allocates the decoder (MHI signals the allocating task),
; keeps MHI_BUFFERS buffers of MHI_BUFFER_SIZE bytes queued, and sets the
; volume (MHIP_VOLUME 0-100) for fades and MUSICVOL; MHI is only called by
; the process. Without the driver or a decoder, the music streams as above.

	xdef initialize_audio
	xdef release_audio
	xdef decode_samples
	xdef audio_play
	xdef audio_stop
	xdef audio_status
	xdef write_samples_dump
	xdef music_call
	xdef music_tick
	xdef amiga_music_loaded
	xdef amiga_mcdrv_probe
	xdef print_music_summary
	xdef audio_tick
	xdef audio_ahi_requested
	xdef audio_ahi_mode
	xdef audio_music_volume
	xdef audio_mhi_requested
	xdef audio_mhi_driver
	xdef audio_effect_volume

	xref exec_base
	xref dos_base
	xref timer_base
	xref total_vbl_count
	xref frame_timer_hz100
	xref PCM_SAMPLE_INFO_TABLE

; exec.library

_LVODisable=-120
_LVOEnable=-126
_LVOForbid=-132
_LVOSetIntVector=-162
_LVOAllocMem=-198
_LVOFreeMem=-210
_LVOFindTask=-294
_LVOWait=-318
_LVOSignal=-324
_LVOAllocSignal=-330
_LVOFreeSignal=-336
_LVOOpenDevice=-444
_LVOCloseDevice=-450
_LVOCreateMsgPort=-666
_LVODeleteMsgPort=-672

MEMF_PUBLIC=1<<0
MEMF_CHIP=1<<1
MEMF_CLEAR=1<<16

; Interrupt structure

ln_Type=8
ln_Name=10
is_Data=14
is_Code=18
IS_SIZE=22
NT_INTERRUPT=2

; dos.library

_LVOOpen=-30
_LVOClose=-36
_LVORead=-42
_LVOWrite=-48
_LVOSeek=-66
_LVOLock=-84
_LVOUnLock=-90
_LVOCreateNewProc=-498
_LVOVPrintf=-954

MODE_OLDFILE=1005
MODE_NEWFILE=1006
ACCESS_READ=-2
OFFSET_BEGINNING=-1

; ahi.device (low-level API)

_LVOAHI_AllocAudioA=-42
_LVOAHI_FreeAudio=-48
_LVOAHI_ControlAudioA=-60
_LVOAHI_SetVol=-66
_LVOAHI_SetFreq=-72
_LVOAHI_SetSound=-78
_LVOAHI_LoadSound=-90
_LVOAHI_UnloadSound=-96
_LVOAHI_GetAudioAttrsA=-108

AHI_TagBase=$80000000
AHIA_AudioID=AHI_TagBase+1
AHIA_MixFreq=AHI_TagBase+2
AHIA_Channels=AHI_TagBase+3
AHIA_Sounds=AHI_TagBase+4
AHIA_SoundFunc=AHI_TagBase+5
AHIC_Play=AHI_TagBase+80
AHIC_MixFreq_Query=AHI_TagBase+84
AHIDB_AudioID=AHI_TagBase+100
AHIDB_Name=AHI_TagBase+$8000+109
AHIDB_BufferLen=AHI_TagBase+122
AHI_DEFAULT_ID=0
AHI_DEFAULT_FREQ=0
AHI_INVALID_ID=-1
AHI_NOSOUND=$ffff
AHI_NO_UNIT=255
AHISF_IMM=1
AHISF_NODELAY=2 ; Do not wait for a zero crossing.
AHIST_M8S=0
AHIST_S8S=2
AHIST_SAMPLE=0
AHIST_DYNAMICSAMPLE=1
ahisi_Type=0
ahisi_Address=4
ahisi_Length=8
AHISampleInfo_SIZEOF=12
ahism_Channel=0
ahir_Version=48
AHIRequest_SIZEOF=80
io_Device=20
h_Entry=8
Hook_SIZEOF=20

AHI_EFFECT_LEFT=0 ; Channels: even left, odd right.
AHI_EFFECT_RIGHT=1
AHI_MUSIC_LEFT=2
AHI_MUSIC_RIGHT=3
AHI_CHANNELS=4
AHI_MUSIC_SOUND=0
AHI_EFFECT_SOUND=1
AHI_SOUNDS=2
AHI_FULL_VOLUME=$10000
AHI_PAN_LEFT=0
AHI_PAN_RIGHT=$10000
AHI_NAME_SIZE=64

; MHI driver library

_LVOMHIAllocDecoder=-30
_LVOMHIFreeDecoder=-36
_LVOMHIQueueBuffer=-42
_LVOMHIGetEmpty=-48
_LVOMHIGetStatus=-54
_LVOMHIPlay=-60
_LVOMHIStop=-66
_LVOMHIQuery=-78
_LVOMHISetParam=-84
_LVOOpenLibrary=-552
_LVOCloseLibrary=-414

MHIF_OUT_OF_DATA=2
MHIQ_DECODER_NAME=1000
MHIP_VOLUME=0
MHI_BUFFERS=8
MHI_BUFFER_SIZE=16384
MHI_DRIVER_NAME_SIZE=64 ; As main.s.
MHI_PATH_SIZE=64
MHI_MAXIMUM_VOLUME=100

NP_Entry=$800003eb
NP_StackSize=$800003f3
NP_Name=$800003f4
NP_Priority=$800003f5
TAG_DONE=0

; timer.device

_LVOReadEClock=-60

; IOAudio

ln_Pri=9
mn_ReplyPort=14
mn_Length=18
ioa_AllocKey=32
ioa_Data=34
ioa_Length=38
IOAUDIO_SIZE=68

; Paula

DMACON=$dff096
VHPOSR=$dff006
INTENA=$dff09a
INTREQ=$dff09c
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
MUSIC_CHANNELS=%1100 ; 2 right, 3 left.
ALL_CHANNELS=%1111

INTF_SETCLR=$8000
INTB_AUD2=9
INTF_AUD2=1<<INTB_AUD2

MAXIMUM_VOLUME=64
MINIMUM_PERIOD=124 ; Paula's fastest DMA rate.

; Music

MCDRV_VERSION=$69 ; Reported by the probe (MCDRV 0.69 rendered the songs).
MAXIMUM_SONGS=16
SONG_NAME_SIZE=40 ; "MUSIC_DAT/" + up to 24 characters + ".crm" + 0
SONG_BASE_NAME_SIZE=24
SONG_ENTRY_SIZE=4+SONG_NAME_SIZE ; MDC data address, stream file name.
BLOCK_FRAMES=4096
RING_SLOTS=8 ; A power of two.
SLOT_SHIFT=13 ; Slot bytes: left and right samples of one block.
SILENCE_BYTES=512 ; Played when no block is ready.
RING_BYTES=(RING_SLOTS<<SLOT_SHIFT)+SILENCE_BYTES
FADE_STEPS=64
READER_PRIORITY=1 ; Above the game: it mostly waits.
READER_STACK_SIZE=8192

; .crm header (big-endian)

crm_magic=0
crm_version=4
crm_channels=6
crm_rate=8
crm_intro_frames=12
crm_loop_frames=16
crm_block_frames=20
crm_peak=24
crm_fade_unit=26 ; 1/10000 s per unit of _FADEOUT speed.
crm_level=28 ; The song's original level relative to the loudest, 1-64 (0: 64).
CRM_HEADER_SIZE=32

; MCDRV functions the game uses

MCDRV_TRANSMDC=$01 ; a0 = song data, d1 = size.
MCDRV_PLAYMUSIC=$02
MCDRV_STOPMUSIC=$05
MCDRV_FADEOUT=$14 ; d1 = speed.

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
	move.l	d0,paula_clock

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

	; AHI if asked for; without it, or if it cannot be opened, Paula.

	tst.b	audio_ahi_requested
	beq		.paula

	bsr		open_ahi
	tst.b	using_ahi
	beq		.paula

	clr.l	effect_end_tick
	clr.l	effects_played
	st		audio_available

	bsr		initialize_music

	bra		.done

.paula:
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

	bsr		initialize_music

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

	bsr		release_music

	clr.b	audio_available

	tst.b	using_ahi
	beq		.paula

	bsr		close_ahi
	move.l	exec_base,a6

	bra		.no_channels

.paula:
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
	tst.b	using_ahi
	beq		.memory_type_set

	moveq	#MEMF_PUBLIC,d1 ; AHI: any memory.

.memory_type_set:
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

	tst.b	using_ahi
	beq		.decoded

	; AHI: all samples as one sound; effects play parts of it.

	lea		effect_sample_info,a0
	move.l	#AHIST_M8S,ahisi_Type(a0)
	move.l	sample_memory,ahisi_Address(a0)
	move.l	sample_memory_size,ahisi_Length(a0)
	moveq	#AHI_EFFECT_SOUND,d0
	moveq	#AHIST_SAMPLE,d1
	move.l	ahi_control,a2
	move.l	ahi_base,a6
	jsr		_LVOAHI_LoadSound(a6)
	tst.l	d0
	bne		.done

.decoded:
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

	tst.b	using_ahi
	bne		.ahi

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

	move.b	audio_effect_volume,d2

.left_set:
	move	d2,AUD0LC+ac_vol
	moveq	#0,d2
	btst	#1,d3
	beq		.right_set

	move.b	audio_effect_volume,d2

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

	bra		.done

.ahi:
	; AHI: the effect starts at the next frame tick (audio_tick). The
	; request is written with interrupts masked, so the tick never sees
	; half of it.

	move	sr,-(sp)
	or		#$0700,sr

	move.l	a1,d1
	sub.l	sample_memory,d1
	move.l	d1,effect_offset
	add.l	d0,d0 ; Bytes (samples).
	move.l	d0,effect_length
	lea		adpcm_rates_hz100,a0
	move.l	(a0,d4.w*4),d1
	divu.l	#100,d1
	move.l	d1,effect_rate

	move.l	d3,effect_sides ; Output bits: 1 left, 2 right.
	st		effect_pending

	move	(sp)+,sr
	addq.l	#1,effects_played

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

	clr.l	effect_end_tick
	tst.b	using_ahi
	bne		.ahi

	move	#EFFECT_CHANNELS,DMACON

	rts

.ahi:
	sf		effect_pending
	st		effect_stop_pending

.done:
	rts

; ------------------------------------------------------------------------------
;
; From the frame software interrupt: with AHI, starts or stops the effect
; the game asked for since the last tick; then the music's tick. Preserves
; all registers.

audio_tick:
	tst.b	using_ahi
	beq		music_tick

	movem.l	d0-d4/a0-a2/a6,-(sp)

	move.l	ahi_base,a6
	move.l	ahi_control,a2

	tst.b	effect_stop_pending
	beq		.no_stop

	sf		effect_stop_pending
	moveq	#AHI_EFFECT_LEFT,d0
	bsr		.channel_off
	moveq	#AHI_EFFECT_RIGHT,d0
	bsr		.channel_off

.no_stop:
	tst.b	effect_pending
	beq		.done

	sf		effect_pending
	moveq	#AHI_EFFECT_LEFT,d0
	moveq	#AHI_PAN_LEFT,d1
	bsr		.channel_effect
	moveq	#AHI_EFFECT_RIGHT,d0
	move.l	#AHI_PAN_RIGHT,d1
	bsr		.channel_effect

	bra		.done

; d0 = channel, d1 = its pan: the requested effect, at full volume if the
; output bits select this side, else silent; then off when it ends.

.channel_effect:
	movem.l	d0-d1,-(sp)
	move.l	effect_rate,d1
	moveq	#AHISF_IMM,d2
	jsr		_LVOAHI_SetFreq(a6)

	movem.l	(sp),d0/d2
	moveq	#0,d1
	moveq	#1,d3
	lsl.l	d0,d3
	and.l	effect_sides,d3 ; Channel 0 is bit 0 (left), channel 1 bit 1.
	beq		.volume_set

	move.b	audio_effect_volume,d1 ; 0-64 -> 0-$10000.
	moveq	#10,d3
	lsl.l	d3,d1

.volume_set:
	moveq	#AHISF_IMM,d3
	jsr		_LVOAHI_SetVol(a6)

	move.l	(sp),d0
	moveq	#AHI_EFFECT_SOUND,d1
	move.l	effect_offset,d2
	move.l	effect_length,d3
	moveq	#AHISF_IMM|AHISF_NODELAY,d4 ; At once, as the X68000's ADPCM.
	jsr		_LVOAHI_SetSound(a6)

	movem.l	(sp)+,d0-d1
	moveq	#0,d4 ; Queued: off when the effect ends.
	bra		.set_off

.channel_off:
	moveq	#AHISF_IMM,d4

.set_off:
	move.l	#AHI_NOSOUND,d1
	moveq	#0,d2
	moveq	#0,d3
	jmp		_LVOAHI_SetSound(a6)

.done:
	movem.l	(sp)+,d0-d4/a0-a2/a6

	bra		music_tick

; ------------------------------------------------------------------------------
;
; Opens ahi.device and allocates two channels in the mode asked for
; (audio_ahi_mode, 0: the preferences' mode), and starts playback. Prints
; the mode, or that Paula is used. Task context.

open_ahi:
	movem.l	d2-d7/a2-a6,-(sp)

	sf		using_ahi

	move.l	#ahi_step_device,ahi_failed_step
	move.l	exec_base,a6
	jsr		_LVOCreateMsgPort(a6)
	move.l	d0,ahi_port
	beq		.failed

	lea		ahi_request,a1
	move.l	d0,mn_ReplyPort(a1)
	move	#AHIRequest_SIZEOF,mn_Length(a1) ; ahi.device checks it.
	move	#4,ahir_Version(a1)
	lea		ahi_device_name,a0
	move.l	#AHI_NO_UNIT,d0
	moveq	#0,d1
	jsr		_LVOOpenDevice(a6)
	tst.b	d0
	bne		.delete_port

	move.l	ahi_request+io_Device,ahi_base

	lea		ahi_sound_hook,a0
	move.l	#ahi_sound_function,h_Entry(a0)

	move.l	#ahi_step_allocate,ahi_failed_step
	lea		ahi_allocation_tags,a1
	move.l	audio_ahi_mode,4(a1) ; AHIA_AudioID
	move.l	ahi_base,a6
	jsr		_LVOAHI_AllocAudioA(a6)
	move.l	d0,ahi_control
	beq		.close_device

	move.l	#ahi_step_play,ahi_failed_step
	move.l	d0,a2
	lea		ahi_play_tags,a1
	jsr		_LVOAHI_ControlAudioA(a6)
	tst.l	d0
	bne		.free_audio

	; The mode in use, for the message.

	lea		ahi_frequency_tags,a1
	jsr		_LVOAHI_ControlAudioA(a6)

	move.l	#AHI_INVALID_ID,d0
	lea		ahi_attribute_tags,a1
	jsr		_LVOAHI_GetAudioAttrsA(a6)

	st		using_ahi

	move.l	dos_base,a6
	move.l	#ahi_format,d1
	move.l	#ahi_print_arguments,d2
	jsr		_LVOVPrintf(a6)

	bra		.done

.free_audio:
	move.l	ahi_control,a2
	jsr		_LVOAHI_FreeAudio(a6)
	clr.l	ahi_control

.close_device:
	move.l	exec_base,a6
	lea		ahi_request,a1
	jsr		_LVOCloseDevice(a6)

.delete_port:
	move.l	exec_base,a6
	move.l	ahi_port,a0
	jsr		_LVODeleteMsgPort(a6)
	clr.l	ahi_port

.failed:
	move.l	dos_base,a6
	move.l	#no_ahi_format,d1
	move.l	#ahi_failed_step,d2
	jsr		_LVOVPrintf(a6)

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

close_ahi:
	movem.l	d2-d7/a2-a6,-(sp)

	move.l	ahi_base,a6
	move.l	ahi_control,a2
	lea		ahi_stop_tags,a1
	jsr		_LVOAHI_ControlAudioA(a6)

	move.l	ahi_control,a2
	jsr		_LVOAHI_FreeAudio(a6)
	clr.l	ahi_control

	move.l	exec_base,a6
	lea		ahi_request,a1
	jsr		_LVOCloseDevice(a6)

	move.l	ahi_port,a0
	jsr		_LVODeleteMsgPort(a6)
	clr.l	ahi_port

	sf		using_ahi

	movem.l	(sp)+,d2-d7/a2-a6

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
; Music. Sets up the ring, the channel 2 audio interrupt and the reader
; process when MUSIC_DAT exists. Called from initialize_audio once the
; channels are allocated (task context, OS stack). Without it, the MCDRV
; probe reports no driver and the game plays no music, as before.

initialize_music:
	movem.l	d2-d7/a2-a6,-(sp)

	clr.b	music_available
	move.l	#-1,music_transferred

	move.l	dos_base,a6
	move.l	#music_directory,d1
	moveq	#ACCESS_READ,d2
	jsr		_LVOLock(a6)
	move.l	d0,d1
	beq		.done

	jsr		_LVOUnLock(a6)

	; MHI: the driver library and the buffers (the process allocates the
	; decoder).

	clr.l	mhi_base
	clr.l	mhi_buffers
	tst.b	audio_mhi_requested
	beq		.no_mhi

	move.l	exec_base,a6
	lea		audio_mhi_driver,a1
	moveq	#0,d0
	jsr		_LVOOpenLibrary(a6)
	move.l	d0,mhi_base
	beq		.mhi_failed

	move.l	#MHI_BUFFERS*MHI_BUFFER_SIZE,d0
	moveq	#MEMF_PUBLIC,d1
	jsr		_LVOAllocMem(a6)
	move.l	d0,mhi_buffers
	bne		.no_mhi

	move.l	mhi_base,a1
	jsr		_LVOCloseLibrary(a6)
	clr.l	mhi_base

.mhi_failed:
	move.l	dos_base,a6
	move.l	#no_mhi_format,d1
	move.l	#mhi_print_arguments,d2
	move.l	#audio_mhi_driver,mhi_print_arguments
	jsr		_LVOVPrintf(a6)

.no_mhi:
	; The ring: chip RAM for Paula, any memory for AHI.

	move.l	#RING_BYTES,d0
	move.l	#MEMF_CHIP|MEMF_CLEAR,d1
	tst.b	using_ahi
	beq		.ring_memory_type_set

	move.l	#MEMF_PUBLIC|MEMF_CLEAR,d1

.ring_memory_type_set:
	move.l	d0,ring_size
	move.l	exec_base,a6
	jsr		_LVOAllocMem(a6)
	move.l	d0,ring_memory
	beq		.done

	add.l	#RING_SLOTS<<SLOT_SHIFT,d0
	move.l	d0,ring_silence

	bsr		reset_ring

	tst.b	using_ahi
	beq		.ring_ready

	; AHI: the ring is one dynamic 8-bit sound (mono: each channel plays
	; one half of a block).

	lea		music_sample_info,a0
	move.l	#AHIST_M8S,ahisi_Type(a0)
	move.l	ring_memory,ahisi_Address(a0)
	move.l	#RING_BYTES,ahisi_Length(a0)
	moveq	#AHI_MUSIC_SOUND,d0
	moveq	#AHIST_DYNAMICSAMPLE,d1
	move.l	ahi_control,a2
	move.l	ahi_base,a6
	jsr		_LVOAHI_LoadSound(a6)
	move.l	exec_base,a6
	tst.l	d0
	bne		.free_ring

.ring_ready:

	; Signal for the reader process's start and end.

	moveq	#-1,d0
	jsr		_LVOAllocSignal(a6)
	move.b	d0,handshake_signal
	bmi		.free_ring

	sub.l	a1,a1
	jsr		_LVOFindTask(a6)
	move.l	d0,music_parent

	; Channel 2 audio interrupt (exclusive: audio.device gave us the
	; channels). AHI calls the sound hook instead.

	tst.b	using_ahi
	bne		.interrupt_set

	move	#INTF_AUD2,INTENA
	move	#INTF_AUD2,INTREQ

	lea		music_interrupt,a1
	move.b	#NT_INTERRUPT,ln_Type(a1)
	move.l	#music_interrupt_name,ln_Name(a1)
	clr.l	is_Data(a1)
	move.l	#music_block_started,is_Code(a1)
	moveq	#INTB_AUD2,d0
	jsr		_LVOSetIntVector(a6)
	move.l	d0,old_audio_vector

.interrupt_set:
	; The reader process. It signals once it is set up (music_process is
	; then its task, or 0 if it could not start).

	clr.b	music_quit
	clr.l	music_process

	move.l	dos_base,a6
	move.l	#reader_tags,d1
	jsr		_LVOCreateNewProc(a6)
	tst.l	d0
	beq		.restore_vector

	move.l	exec_base,a6
	moveq	#0,d0
	move.b	handshake_signal,d1
	bset	d1,d0
	jsr		_LVOWait(a6)

	tst.l	music_process
	beq		.restore_vector

	st		music_available
	st		music_enabled

	tst.l	mhi_base
	beq		.done

	; The process allocated the decoder, or could not (then closed).

	tst.b	using_mhi
	beq		.mhi_no_decoder

	move.l	dos_base,a6
	move.l	#mhi_format,d1
	move.l	#mhi_print_arguments,d2
	jsr		_LVOVPrintf(a6)

	bra		.done

.mhi_no_decoder:
	move.l	dos_base,a6
	move.l	#mhi_print_arguments,d2
	move.l	#audio_mhi_driver,mhi_print_arguments
	move.l	#no_mhi_decoder_format,d1
	jsr		_LVOVPrintf(a6)
	bsr		free_mhi

	bra		.done

.restore_vector:
	move.l	exec_base,a6
	tst.b	using_ahi
	bne		.vector_restored

	moveq	#INTB_AUD2,d0
	move.l	old_audio_vector,a1
	jsr		_LVOSetIntVector(a6)

.vector_restored:
	moveq	#0,d0
	move.b	handshake_signal,d0
	jsr		_LVOFreeSignal(a6)

.free_ring:
	bsr		unload_music_sound
	move.l	exec_base,a6
	move.l	ring_memory,a1
	move.l	ring_size,d0
	jsr		_LVOFreeMem(a6)
	clr.l	ring_memory

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; ------------------------------------------------------------------------------
;
; Stops the music, ends the reader process and gives back the interrupt and
; the ring. Called from release_audio.

release_music:
	movem.l	d2-d7/a2-a6,-(sp)

	tst.b	music_available
	beq		.done

	sf		music_available ; music_tick and music_call do nothing now.
	bsr		stop_playback

	move.l	exec_base,a6
	st		music_quit
	move.l	music_process,a1
	move.l	music_wake_mask,d0
	jsr		_LVOSignal(a6)

	moveq	#0,d0
	move.b	handshake_signal,d1
	bset	d1,d0
	jsr		_LVOWait(a6)

	bsr		stop_playback

	tst.b	using_ahi
	bne		.vector_restored

	moveq	#INTB_AUD2,d0
	move.l	old_audio_vector,a1
	jsr		_LVOSetIntVector(a6)

.vector_restored:
	moveq	#0,d0
	move.b	handshake_signal,d0
	jsr		_LVOFreeSignal(a6)

	bsr		unload_music_sound
	move.l	exec_base,a6
	move.l	ring_memory,a1
	move.l	ring_size,d0
	jsr		_LVOFreeMem(a6)
	clr.l	ring_memory

	bsr		free_mhi

.done:
	movem.l	(sp)+,d2-d7/a2-a6

	rts

; The MHI driver and buffers (after the process has freed its decoder).

free_mhi:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	move.l	exec_base,a6
	move.l	mhi_buffers,d0
	beq		.no_buffers

	move.l	d0,a1
	move.l	#MHI_BUFFERS*MHI_BUFFER_SIZE,d0
	jsr		_LVOFreeMem(a6)
	clr.l	mhi_buffers

.no_buffers:
	move.l	mhi_base,d0
	beq		.done

	move.l	d0,a1
	jsr		_LVOCloseLibrary(a6)
	clr.l	mhi_base

.done:
	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

; AHI: the ring is no longer a sound (before it is freed).

unload_music_sound:
	tst.b	using_ahi
	beq		.done

	moveq	#AHI_MUSIC_SOUND,d0
	move.l	ahi_control,a2
	move.l	ahi_base,a6
	jsr		_LVOAHI_UnloadSound(a6)

.done:
	rts

; ------------------------------------------------------------------------------
;
; MCDRV probe (sz2.s): returns d0.l = the driver version if the music can
; play, else -1.

amiga_mcdrv_probe:
	moveq	#-1,d0
	tst.b	music_available
	beq		.done

	moveq	#MCDRV_VERSION,d0

.done:
	rts

; ------------------------------------------------------------------------------
;
; After the game loaded a song (INITIALIZE_SOUND, game context): a0 = the
; song data, a1 = its file name from SZ2_BGM.CNF ("BGM_DAT\SZ2_S1.mdc").
; Keeps the data address with the stream's name ("MUSIC_DAT/SZ2_S1.crm").
; Preserves all registers.

amiga_music_loaded:
	movem.l	d0-d1/a0-a3,-(sp)

	move.l	music_song_count,d0
	cmp.l	#MAXIMUM_SONGS,d0
	bcc		.done

	mulu	#SONG_ENTRY_SIZE,d0
	lea		music_songs,a2
	add.l	d0,a2
	move.l	a0,(a2)+

	; Base name: after the last '\', '/' or ':'.

	move.l	a1,a3

.scan:
	move.b	(a1)+,d0
	beq		.scanned

	cmp.b	#$5c,d0 ; '\'
	beq		.separator

	cmp.b	#'/',d0
	beq		.separator

	cmp.b	#':',d0
	bne		.scan

.separator:
	move.l	a1,a3

	bra		.scan

.scanned:
	lea		music_directory_prefix,a0

.prefix:
	move.b	(a0)+,(a2)+
	bne		.prefix

	subq.l	#1,a2

	moveq	#SONG_BASE_NAME_SIZE-1,d1

.base:
	move.b	(a3)+,d0
	cmp.b	#'.',d0
	beq		.extension

	cmp.b	#' ',d0
	bls		.extension ; End, or a line end or space.

	move.b	d0,(a2)+
	dbf		d1,.base

.extension:
	lea		stream_extension,a0

.extension_loop:
	move.b	(a0)+,(a2)+
	bne		.extension_loop

	addq.l	#1,music_song_count

.done:
	movem.l	(sp)+,d0-d1/a0-a3

	rts

; ------------------------------------------------------------------------------
;
; MCDRV call (trap #4, supervisor mode): d0.l = function, d1.l, a0. Returns
; d0.l = 0. No OS calls: requests for the reader process are passed on by
; music_tick. Preserves the other registers.

music_call:
	movem.l	d1-d2/a0-a1,-(sp)

	tst.b	music_available
	beq		.return

	cmp.l	#MCDRV_TRANSMDC,d0
	beq		.transfer

	cmp.l	#MCDRV_PLAYMUSIC,d0
	beq		.play

	cmp.l	#MCDRV_STOPMUSIC,d0
	beq		.stop

	cmp.l	#MCDRV_FADEOUT,d0
	beq		.fade

	bra		.return

.transfer:
	; The song to play next: the entry with this data.

	move.l	#-1,music_transferred
	lea		music_songs,a1
	moveq	#0,d2

.find:
	cmp.l	music_song_count,d2
	beq		.return

	cmp.l	(a1),a0
	beq		.found

	lea		SONG_ENTRY_SIZE(a1),a1
	addq.l	#1,d2

	bra		.find

.found:
	move.l	d2,music_transferred

	bra		.return

.play:
	bsr		stop_from_trap
	move.l	music_transferred,d2

	bra		.request

.stop:
	bsr		stop_from_trap
	moveq	#-1,d2

.request:
	move.l	d2,music_request_song
	addq.l	#1,music_request_serial
	st		music_wake_pending

	bra		.return

.fade:
	tst.b	music_playing
	beq		.return

	and.l	#$ffff,d1
	bne		.speed_set

	moveq	#1,d1

.speed_set:
	move.l	d1,fade_speed
	st		fade_requested

.return:
	moveq	#0,d0
	movem.l	(sp)+,d1-d2/a0-a1

	rts

; ------------------------------------------------------------------------------
;
; From the frame software interrupt: passes requests on to the reader
; process and runs the fade (in E clock time). Preserves all registers.

music_tick:
	tst.b	music_available
	beq		.return

	movem.l	d0-d2/a0-a1/a6,-(sp)

	; AHI: a stop from the trap handler (before the reader hears of it).

	tst.b	music_stop_pending
	beq		.no_stop

	sf		music_stop_pending
	bsr		stop_playback

.no_stop:
	tst.b	music_wake_pending
	beq		.no_wake

	sf		music_wake_pending
	bsr		wake_reader

.no_wake:
	tst.b	fade_requested
	beq		.no_new_fade

	; Fade length in E clock ticks: speed * unit * frequency / 10000.

	sf		fade_requested
	move.l	timer_base,a6
	lea		fade_eclock,a0
	jsr		_LVOReadEClock(a6)
	move.l	fade_eclock+4,fade_start

	move.l	fade_speed,d1
	mulu	song_fade_unit,d1
	mulu.l	d0,d2:d1
	divu.l	#10000,d2:d1
	tst.l	d1
	bne		.length_set

	moveq	#1,d1

.length_set:
	move.l	d1,fade_length
	st		fade_active

.no_new_fade:
	tst.b	fade_active
	beq		.done

	tst.b	music_playing
	beq		.done

	move.l	timer_base,a6
	lea		fade_eclock,a0
	jsr		_LVOReadEClock(a6)
	move.l	fade_eclock+4,d1
	sub.l	fade_start,d1
	cmp.l	fade_length,d1
	bcc		.faded

	moveq	#0,d2
	mulu.l	#FADE_STEPS,d2:d1
	divu.l	fade_length,d2:d1 ; Step.
	lea		fade_volumes,a0
	moveq	#0,d0
	move.b	(a0,d1.l),d0
	bsr		set_music_volume

	bra		.done

.faded:
	; Silent, as MCDRV leaves it: stop, and let the process close the file.

	bsr		stop_playback
	move.l	#-1,music_request_song
	addq.l	#1,music_request_serial
	bsr		wake_reader

.done:
	movem.l	(sp)+,d0-d2/a0-a1/a6

.return:
	rts

wake_reader:
	move.l	exec_base,a6
	move.l	music_process,a1
	move.l	music_wake_mask,d0
	jmp		_LVOSignal(a6)

; ------------------------------------------------------------------------------
;
; Stops the music channels and their interrupt. Any context. Preserves all
; registers.

stop_playback:
	sf		music_playing
	sf		fade_active
	sf		fade_requested

	tst.b	using_mhi
	bne		.mhi ; The reader process stops the decoder (a request follows).

	tst.b	using_ahi
	bne		.ahi

	move	#INTF_AUD2,INTENA
	move	#MUSIC_CHANNELS,DMACON
	move	#INTF_AUD2,INTREQ
	clr		AUD2LC+ac_vol
	clr		AUD3LC+ac_vol

	rts

.mhi:
	rts

.ahi:
	movem.l	d0-d4/a0-a2/a6,-(sp)

	move.l	ahi_control,a2
	move.l	ahi_base,a6
	moveq	#AHI_MUSIC_LEFT,d0
	move.l	#AHI_NOSOUND,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#AHISF_IMM,d4
	jsr		_LVOAHI_SetSound(a6)

	moveq	#AHI_MUSIC_RIGHT,d0
	move.l	#AHI_NOSOUND,d1
	moveq	#0,d2
	moveq	#0,d3
	moveq	#AHISF_IMM,d4
	jsr		_LVOAHI_SetSound(a6)

	movem.l	(sp)+,d0-d4/a0-a2/a6

	rts

; From the trap handler: Paula stops at once; AHI at the next frame tick
; (music_tick), and the sound hook does nothing meanwhile.

stop_from_trap:
	tst.b	using_mhi
	bne		stop_playback ; Flags only; the process stops the decoder.

	tst.b	using_ahi
	beq		stop_playback

	sf		music_playing
	sf		fade_active
	sf		fade_requested
	st		music_stop_pending

	rts

; d0.l = volume (0-64): the fade's. Scaled by the music volume (MUSICVOL)
; and the song's level. Preserves all registers.

set_music_volume:
	move.l	d1,-(sp)
	moveq	#0,d1
	move.b	audio_music_volume,d1
	mulu	song_level,d1
	mulu	d1,d0
	beq		.scaled

	; Rounded up: an audible fade step stays audible (at least 1).

	add.l	#MAXIMUM_VOLUME*MAXIMUM_VOLUME-1,d0
	divu	#MAXIMUM_VOLUME*MAXIMUM_VOLUME,d0
	and.l	#$ffff,d0

.scaled:
	move.l	(sp)+,d1

	tst.b	using_mhi
	beq		.not_mhi

	; MHI: 0-100, set by the reader process.

	movem.l	d0-d1,-(sp)
	mulu	#MHI_MAXIMUM_VOLUME,d0
	add.l	#MAXIMUM_VOLUME/2,d0
	divu	#MAXIMUM_VOLUME,d0
	and.l	#$ffff,d0
	move.l	d0,mhi_volume
	st		music_wake_pending
	movem.l	(sp)+,d0-d1

	rts

.not_mhi:
	tst.b	using_ahi
	bne		.ahi

	move	d0,AUD2LC+ac_vol
	move	d0,AUD3LC+ac_vol

	rts

.ahi:
	movem.l	d0-d4/a0-a2/a6,-(sp)

	move.l	d0,d4
	moveq	#10,d2
	lsl.l	d2,d4 ; 64 -> $10000
	move.l	ahi_control,a2
	move.l	ahi_base,a6
	moveq	#AHI_MUSIC_LEFT,d0
	move.l	d4,d1
	moveq	#AHI_PAN_LEFT,d2
	moveq	#AHISF_IMM,d3
	jsr		_LVOAHI_SetVol(a6)

	moveq	#AHI_MUSIC_RIGHT,d0
	move.l	d4,d1
	move.l	#AHI_PAN_RIGHT,d2
	moveq	#AHISF_IMM,d3
	jsr		_LVOAHI_SetVol(a6)

	movem.l	(sp)+,d0-d4/a0-a2/a6

	rts

; ------------------------------------------------------------------------------
;
; Channel 2 audio interrupt: Paula has started the queued block (and copied
; its address and length), so the block before has ended. Frees it, wakes
; the reader, and queues the next one. a6 = exec base. May change d0-d1 and
; a0-a1.

music_block_started:
	move	#INTF_AUD2,INTREQ

; A block (or the silence) has started: the one before has ended.

block_started:
	addq.l	#1,block_starts
	move.l	playing_slot,d0
	move.l	queued_slot,playing_slot
	tst.l	d0
	bmi		.queue ; Silence, or nothing, has ended.

	addq.l	#1,ring_free
	addq.l	#1,blocks_played
	move.l	exec_base,a6
	move.l	music_process,a1
	move.l	music_wake_mask,d0
	jsr		_LVOSignal(a6)

.queue:
	bra		queue_next_block

; Points channels 3 (left) and 2 (right) at the next ready block, or at the
; silence if there is none. Interrupt, or the process with interrupts
; disabled. May change d0-d1 and a0.

queue_next_block:
	tst.l	ring_ready
	beq		.silence

	subq.l	#1,ring_ready
	move.l	ring_read,d0
	move.l	d0,queued_slot
	lea		slot_frames,a0
	moveq	#0,d1
	move	(a0,d0.l*2),d1

	addq.l	#1,d0
	and.l	#RING_SLOTS-1,d0
	move.l	d0,ring_read

	move.l	queued_slot,d0
	lsl.l	#8,d0
	lsl.l	#SLOT_SHIFT-8,d0
	add.l	ring_memory,d0
	move.l	d0,AUD3LC
	add.l	d1,d0
	move.l	d0,AUD2LC
	lsr		#1,d1 ; Words.
	move	d1,AUD3LC+ac_len
	move	d1,AUD2LC+ac_len

	rts

.silence:
	move.l	#-1,queued_slot
	move.l	ring_silence,d0
	move.l	d0,AUD3LC
	move.l	d0,AUD2LC
	move	#SILENCE_BYTES/2,AUD3LC+ac_len
	move	#SILENCE_BYTES/2,AUD2LC+ac_len

	tst.b	stream_ended
	bne		.done

	addq.l	#1,music_underruns

.done:
	rts

; AHI sound hook (a0 = hook, a1 = AHISoundMessage, a2 = AHIAudioCtrl): a
; channel has started a sound. For a music channel, the half block it
; played before has ended: once both sides have ended a block, it is free
; (the reader is woken). Then that channel's next half block is queued.
; Returns d0 = 0; preserves d2-d7 and a2-a6.

ahi_sound_function:
	moveq	#0,d0
	move	ahism_Channel(a1),d0
	subq.l	#AHI_MUSIC_LEFT,d0
	bcs		.done ; An effect channel.

	cmp.l	#1,d0
	bhi		.done

	tst.b	music_playing
	beq		.done ; Stopped: the next tick turns the channels off.

	movem.l	d2-d4/a2/a6,-(sp)

	move.l	d0,d2 ; Side: 0 left, 1 right.
	addq.l	#1,block_starts
	lea		side_playing,a0
	lea		side_queued,a1
	move.l	(a0,d2.l*4),d1 ; Ended.
	move.l	(a1,d2.l*4),(a0,d2.l*4)
	tst.l	d1
	bmi		.queue ; Silence, or nothing.

	lea		slot_sides_ended,a0
	addq.b	#1,(a0,d1.l)
	cmp.b	#2,(a0,d1.l)
	bne		.queue

	clr.b	(a0,d1.l)
	addq.l	#1,ring_free
	addq.l	#1,blocks_played
	move.l	exec_base,a6
	move.l	music_process,a1
	move.l	music_wake_mask,d0
	jsr		_LVOSignal(a6)

.queue:
	bsr		queue_side

	movem.l	(sp)+,d2-d4/a2/a6

.done:
	moveq	#0,d0

	rts

; d2.l = side (0 left, 1 right): queues its next ready half block on its
; music channel, or the silence (after the current sound; at once with
; AHISF_IMM in ahi_queue_flags). May change d0-d1, d3-d4, a0-a2 and a6.

queue_side:
	lea		side_ready,a0
	tst.l	(a0,d2.l*4)
	beq		.silence

	subq.l	#1,(a0,d2.l*4)
	lea		side_read,a0
	move.l	(a0,d2.l*4),d1 ; Slot.
	lea		side_queued,a1
	move.l	d1,(a1,d2.l*4)
	addq.l	#1,(a0,d2.l*4)
	and.l	#RING_SLOTS-1,(a0,d2.l*4)

	lea		slot_frames,a0
	moveq	#0,d3
	move	(a0,d1.l*2),d3 ; Length.
	lsl.l	#8,d1
	lsl.l	#SLOT_SHIFT-8,d1
	tst.l	d2
	beq		.offset_set

	add.l	d3,d1 ; The right half.

.offset_set:
	move.l	d1,d4
	bra		.set

.silence:
	lea		side_queued,a1
	move.l	#-1,(a1,d2.l*4)

	tst.l	d2
	bne		.counted

	tst.b	stream_ended
	bne		.counted

	addq.l	#1,music_underruns ; Counted once, on the left.

.counted:
	move.l	#RING_SLOTS<<SLOT_SHIFT,d4
	move.l	#SILENCE_BYTES,d3

.set:
	move.l	d2,d0
	addq.l	#AHI_MUSIC_LEFT,d0
	moveq	#AHI_MUSIC_SOUND,d1
	move.l	d2,-(sp)
	move.l	d4,d2 ; Offset.
	move.l	ahi_queue_flags,d4
	move.l	ahi_control,a2
	move.l	ahi_base,a6
	jsr		_LVOAHI_SetSound(a6)
	move.l	(sp)+,d2

	rts

; Empty ring: all slots free. Only while the music interrupt is off.

reset_ring:
	clr.l	ring_write
	clr.l	ring_read
	clr.l	ring_ready
	move.l	#RING_SLOTS,ring_free
	move.l	#-1,playing_slot
	move.l	#-1,queued_slot
	sf		stream_ended

	lea		side_ready,a0
	clr.l	(a0)+
	clr.l	(a0)
	lea		side_read,a0
	clr.l	(a0)+
	clr.l	(a0)
	lea		side_playing,a0
	move.l	#-1,(a0)+
	move.l	#-1,(a0)
	lea		side_queued,a0
	move.l	#-1,(a0)+
	move.l	#-1,(a0)
	lea		slot_sides_ended,a0
	moveq	#RING_SLOTS-1,d0

.clear_ended:
	clr.b	(a0)+
	dbf		d0,.clear_ended

	rts

; ------------------------------------------------------------------------------
;
; Reader process. Handles the game's requests (stop, or play a song) and
; keeps the ring filled from the song's file.

reader_process:
	move.l	exec_base,a6
	moveq	#-1,d0
	jsr		_LVOAllocSignal(a6)
	move.b	d0,wake_signal
	bmi		.failed

	moveq	#0,d1
	bset	d0,d1
	move.l	d1,music_wake_mask

	sub.l	a1,a1
	jsr		_LVOFindTask(a6)
	move.l	d0,music_process

	move.l	music_wake_mask,reader_wait_mask
	sf		using_mhi
	tst.l	mhi_base
	beq		.decoder_done

	bsr		allocate_mhi_decoder

.decoder_done:
	bsr		signal_parent

.wait:
	move.l	exec_base,a6
	move.l	reader_wait_mask,d0
	jsr		_LVOWait(a6)

	tst.b	using_mhi
	bne		.mhi

	tst.b	music_quit
	bne		.quit

	move.l	music_request_serial,d0
	cmp.l	handled_serial,d0
	beq		.no_request

	move.l	d0,handled_serial
	bsr		stop_playback
	bsr		close_song
	bsr		reset_ring

	move.l	music_request_song,d0
	bmi		.no_request

	bsr		open_song

.no_request:
	bsr		fill_ring
	bsr		start_if_ready

	bra		.wait

.mhi:
	; MHI: requests, buffers, volume.

	tst.b	music_quit
	bne		.quit

	move.l	music_request_serial,d0
	cmp.l	handled_serial,d0
	beq		.mhi_service

	move.l	d0,handled_serial
	bsr		mhi_stop

	move.l	music_request_song,d0
	bmi		.mhi_service

	bsr		mhi_start

.mhi_service:
	bsr		mhi_refill
	bsr		mhi_apply_volume

	bra		.wait

.quit:
	tst.b	using_mhi
	beq		.no_decoder

	bsr		mhi_stop
	move.l	mhi_base,a6
	move.l	mhi_handle,a3
	jsr		_LVOMHIFreeDecoder(a6)
	sf		using_mhi

	move.l	exec_base,a6
	moveq	#0,d0
	move.b	mhi_signal,d0
	jsr		_LVOFreeSignal(a6)

.no_decoder:
	bsr		close_song

	move.l	exec_base,a6
	moveq	#0,d0
	move.b	wake_signal,d0
	jsr		_LVOFreeSignal(a6)

.failed:
	; Forbid: the process ends before the parent can go on (and unload
	; this code); the forbid ends with the process.

	move.l	exec_base,a6
	jsr		_LVOForbid(a6)
	bsr		signal_parent

	moveq	#0,d0

	rts

; MHI (reader process). Allocates the decoder for this process: using_mhi,
; and its signal joins reader_wait_mask. Without one, the driver is left
; for initialize_music to close.

allocate_mhi_decoder:
	move.l	exec_base,a6
	moveq	#-1,d0
	jsr		_LVOAllocSignal(a6)
	move.b	d0,mhi_signal
	bmi		.done

	moveq	#0,d1
	bset	d0,d1
	move.l	d1,mhi_mask

	move.l	mhi_base,a6
	move.l	music_process,a0
	move.l	d1,d0
	jsr		_LVOMHIAllocDecoder(a6)
	move.l	d0,mhi_handle
	beq		.no_decoder

	move.l	mhi_mask,d0
	or.l	d0,reader_wait_mask

	moveq	#0,d1
	move.l	#MHIQ_DECODER_NAME,d1
	jsr		_LVOMHIQuery(a6)
	move.l	d0,mhi_print_arguments

	; All buffers free.

	lea		mhi_free_buffers,a0
	move.l	mhi_buffers,d0
	moveq	#MHI_BUFFERS-1,d1

.buffer_loop:
	move.l	d0,(a0)+
	add.l	#MHI_BUFFER_SIZE,d0
	dbf		d1,.buffer_loop

	move.l	#MHI_BUFFERS,mhi_free_count
	st		using_mhi

	bra		.done

.no_decoder:
	move.l	exec_base,a6
	moveq	#0,d0
	move.b	mhi_signal,d0
	jsr		_LVOFreeSignal(a6)

.done:
	rts

; Stops the decoder, takes back all buffers, closes the files.

mhi_stop:
	movem.l	d2-d3/a2-a3/a6,-(sp)

	sf		music_playing
	move.l	mhi_base,a6
	move.l	mhi_handle,a3
	jsr		_LVOMHIStop(a6)
	bsr		mhi_take_back

	lea		mhi_files,a2
	moveq	#2-1,d2

.close_loop:
	move.l	(a2),d1
	beq		.next

	move.l	dos_base,a6
	jsr		_LVOClose(a6)
	clr.l	(a2)

.next:
	addq.l	#4,a2
	dbf		d2,.close_loop

	clr.l	mhi_current_file
	sf		stream_ended

	movem.l	(sp)+,d2-d3/a2-a3/a6

	rts

; Empty buffers back on the free list.

mhi_take_back:
	move.l	mhi_base,a6
	move.l	mhi_handle,a3

.loop:
	jsr		_LVOMHIGetEmpty(a6)
	tst.l	d0
	beq		.done

	move.l	mhi_free_count,d1
	lea		mhi_free_buffers,a0
	move.l	d0,(a0,d1.l*4)
	addq.l	#1,mhi_free_count

	bra		.loop

.done:
	rts

; d0.l = song entry: opens NAME_intro.mp3 and NAME_loop.mp3 (named after
; the song's stream, MUSIC_DAT/NAME.crm), queues the buffers and plays.

mhi_start:
	movem.l	d2-d4/a2-a3/a6,-(sp)

	move.l	d0,d4 ; Song entry.
	mulu	#SONG_ENTRY_SIZE,d0
	lea		music_songs+4,a2
	add.l	d0,a2

	lea		mhi_intro_suffix,a1
	lea		mhi_intro_path,a0
	bsr		mhi_path
	lea		mhi_loop_suffix,a1
	lea		mhi_loop_path,a0
	bsr		mhi_path

	move.l	dos_base,a6
	move.l	#mhi_intro_path,d1
	move.l	#MODE_OLDFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,mhi_files
	beq		.failed

	move.l	d0,mhi_current_file
	move.l	#mhi_loop_path,d1
	move.l	#MODE_OLDFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,mhi_files+4 ; 0: no loop.

	; The song's level and fade length from its stream's header (the MP3
	; files are normalised as the streams are).

	move.l	d4,d0
	bsr		open_song
	bsr		close_song

	moveq	#-1,d0
	move.l	d0,mhi_volume_set ; Set it in any case.
	moveq	#MAXIMUM_VOLUME,d0
	bsr		set_music_volume

	bsr		mhi_refill

	move.l	mhi_base,a6
	move.l	mhi_handle,a3
	jsr		_LVOMHIPlay(a6)
	st		music_playing
	addq.l	#1,songs_started

	bsr		mhi_apply_volume

	bra		.done

.failed:
	addq.l	#1,music_errors

.done:
	movem.l	(sp)+,d2-d4/a2-a3/a6

	rts

; a2 = the stream's name ("MUSIC_DAT/NAME.crm"), a0 = destination, a1 =
; suffix: the name up to ".crm", then the suffix.

mhi_path:
	moveq	#MHI_PATH_SIZE-12,d0
	move.l	a2,a3

.copy:
	move.b	(a3)+,d1
	beq		.suffix

	cmp.b	#'.',d1
	beq		.suffix

	move.b	d1,(a0)+
	dbf		d0,.copy

.suffix:
	move.b	(a1)+,(a0)+
	bne		.suffix

	rts

; Takes back the empty buffers, fills them (the intro, then the loop again
; and again) and queues them; restarts the decoder if it ran out of data.

mhi_refill:
	movem.l	d2-d4/a2-a3/a6,-(sp)

	bsr		mhi_take_back

.fill:
	tst.l	mhi_current_file
	beq		.check

	move.l	mhi_free_count,d0
	beq		.check

	subq.l	#1,d0
	lea		mhi_free_buffers,a0
	move.l	(a0,d0.l*4),a2 ; Buffer.
	move.l	a2,d2
	move.l	#MHI_BUFFER_SIZE,d3
	bsr		mhi_read
	tst.l	d0
	beq		.check ; No more data.

	subq.l	#1,mhi_free_count
	move.l	mhi_base,a6
	move.l	mhi_handle,a3
	move.l	a2,a0
	jsr		_LVOMHIQueueBuffer(a6)
	addq.l	#1,blocks_read

	bra		.fill

.check:
	tst.b	music_playing
	beq		.done

	move.l	mhi_base,a6
	move.l	mhi_handle,a3
	jsr		_LVOMHIGetStatus(a6)
	cmp.b	#MHIF_OUT_OF_DATA,d0
	bne		.done

	tst.l	mhi_current_file
	beq		.done ; The song has ended.

	addq.l	#1,music_underruns
	jsr		_LVOMHIPlay(a6)

.done:
	movem.l	(sp)+,d2-d4/a2-a3/a6

	rts

; d2 = buffer, d3 = size: reads the stream's next bytes, from the intro into
; the loop, which starts over at its end. Returns d0 = bytes read (0 at the
; end of a song without loop, or on an error).

mhi_read:
	movem.l	d2-d6/a6,-(sp)

	move.l	d2,d5 ; Next byte to fill.
	move.l	d3,d6 ; Bytes still to read.
	moveq	#0,d4 ; End-of-file reads in a row (a loop file without data).

.loop:
	tst.l	d6
	beq		.done

	move.l	mhi_current_file,d1
	beq		.done

	move.l	dos_base,a6
	move.l	d5,d2
	move.l	d6,d3
	jsr		_LVORead(a6)
	tst.l	d0
	bmi		.error

	beq		.end_of_file

	add.l	d0,d5
	sub.l	d0,d6
	moveq	#0,d4

	bra		.loop

.end_of_file:
	; On to the loop file, from its start (again).

	addq.l	#1,d4
	cmp.l	#2,d4
	bcc		.error

	move.l	mhi_files+4,d1
	beq		.no_loop

	move.l	d1,mhi_current_file
	moveq	#0,d2
	moveq	#OFFSET_BEGINNING,d3
	jsr		_LVOSeek(a6)
	tst.l	d0
	bmi		.error

	bra		.loop

.error:
	addq.l	#1,music_errors

.no_loop:
	clr.l	mhi_current_file

.done:
	move.l	d5,d0
	movem.l	(sp)+,d2-d6/a6
	sub.l	d2,d0 ; Bytes read.

	rts

; Sets the decoder's volume if it changed (fades, MUSICVOL).

mhi_apply_volume:
	move.l	mhi_volume,d1
	cmp.l	mhi_volume_set,d1
	beq		.done

	move.l	d1,mhi_volume_set
	movem.l	a3/a6,-(sp)
	move.l	mhi_base,a6
	move.l	mhi_handle,a3
	moveq	#MHIP_VOLUME,d0
	jsr		_LVOMHISetParam(a6)
	movem.l	(sp)+,a3/a6

.done:
	rts

signal_parent:
	move.l	exec_base,a6
	move.l	music_parent,a1
	moveq	#0,d0
	move.b	handshake_signal,d1
	bset	d1,d0
	jmp		_LVOSignal(a6)

; d0.l = song entry. Opens its stream and reads the header; on any problem
; the file stays closed (and the song silent).

open_song:
	movem.l	d2-d3/a6,-(sp)

	mulu	#SONG_ENTRY_SIZE,d0
	lea		music_songs+4,a0
	add.l	d0,a0

	move.l	dos_base,a6
	move.l	a0,d1
	move.l	#MODE_OLDFILE,d2
	jsr		_LVOOpen(a6)
	move.l	d0,song_file
	beq		.failed

	move.l	d0,d1
	move.l	#song_header,d2
	moveq	#CRM_HEADER_SIZE,d3
	jsr		_LVORead(a6)
	cmp.l	#CRM_HEADER_SIZE,d0
	bne		.bad

	lea		song_header,a0
	cmp.l	#'CRSM',crm_magic(a0)
	bne		.bad

	cmp		#2,crm_channels(a0)
	bne		.bad

	cmp.l	#BLOCK_FRAMES,crm_block_frames(a0)
	bne		.bad

	move.l	crm_intro_frames(a0),d0
	or.l	crm_loop_frames(a0),d0
	btst	#0,d0
	bne		.bad ; Paula plays words.

	; Period: Paula clock / rate, rounded.

	move.l	crm_rate(a0),d1
	beq		.bad

	move.l	d1,song_rate

	move.l	paula_clock,d0
	move.l	d1,d2
	lsr.l	#1,d2
	add.l	d2,d0
	divu.l	d1,d0
	cmp.l	#MINIMUM_PERIOD,d0
	bcs		.bad

	cmp.l	#$ffff,d0
	bhi		.bad

	move	d0,song_period

	move.l	crm_intro_frames(a0),d0
	move.l	d0,part_left
	add.l	d0,d0
	add.l	#CRM_HEADER_SIZE,d0
	move.l	d0,loop_offset
	move.l	crm_loop_frames(a0),loop_frames
	move	crm_fade_unit(a0),song_fade_unit
	move	crm_level(a0),d0
	beq		.full_level ; Older files.

	cmp		#MAXIMUM_VOLUME,d0
	bls		.level_set

.full_level:
	moveq	#MAXIMUM_VOLUME,d0

.level_set:
	move	d0,song_level
	sf		in_loop

	bra		.done

.bad:
	bsr		close_song

.failed:
	addq.l	#1,music_errors

.done:
	movem.l	(sp)+,d2-d3/a6

	rts

close_song:
	movem.l	d0-d1/a0-a1/a6,-(sp)

	move.l	song_file,d1
	beq		.done

	move.l	dos_base,a6
	jsr		_LVOClose(a6)
	clr.l	song_file

.done:
	movem.l	(sp)+,d0-d1/a0-a1/a6

	rts

; Reads blocks into the free slots, until the ring is full, the song ends,
; or a new request (or the end of the run) comes in.

fill_ring:
	movem.l	d2-d5/a6,-(sp)

.loop:
	tst.l	song_file
	beq		.done

	tst.l	ring_free
	beq		.done

	tst.b	music_quit
	bne		.done

	move.l	music_request_serial,d0
	cmp.l	handled_serial,d0
	bne		.done

	move.l	part_left,d0
	bne		.read

	; End of the intro or of the loop. The loop follows the intro in the
	; file; after the loop, back to its start.

	tst.l	loop_frames
	beq		.end_of_song

	tst.b	in_loop
	beq		.enter_loop

	move.l	dos_base,a6
	move.l	song_file,d1
	move.l	loop_offset,d2
	moveq	#OFFSET_BEGINNING,d3
	jsr		_LVOSeek(a6)
	tst.l	d0
	bmi		.error

.enter_loop:
	st		in_loop
	move.l	loop_frames,d0
	move.l	d0,part_left

.read:
	cmp.l	#BLOCK_FRAMES,d0
	bls		.size_set

	move.l	#BLOCK_FRAMES,d0

.size_set:
	move.l	d0,d4 ; Frames.
	move.l	ring_write,d5
	move.l	d5,d2
	moveq	#SLOT_SHIFT,d0
	lsl.l	d0,d2
	add.l	ring_memory,d2
	move.l	d4,d3
	add.l	d3,d3
	move.l	song_file,d1
	move.l	dos_base,a6
	jsr		_LVORead(a6)
	move.l	d4,d1
	add.l	d1,d1
	cmp.l	d1,d0
	bne		.error


	lea		slot_frames,a0
	move	d4,(a0,d5.l*2)
	addq.l	#1,d5
	and.l	#RING_SLOTS-1,d5
	move.l	d5,ring_write
	sub.l	d4,part_left
	addq.l	#1,blocks_read

	subq.l	#1,ring_free ; (Single instructions: the interrupt changes
	tst.b	using_ahi ; these too.)
	bne		.ready_for_both_sides

	addq.l	#1,ring_ready

	bra		.loop

.ready_for_both_sides:
	; AHI: both sides at once (a hook between them would split them).

	move.l	exec_base,a6
	jsr		_LVODisable(a6)
	addq.l	#1,side_ready
	addq.l	#1,side_ready+4
	jsr		_LVOEnable(a6)

	bra		.loop

.error:
	addq.l	#1,music_errors

.end_of_song:
	st		stream_ended
	bsr		close_song

.done:
	movem.l	(sp)+,d2-d5/a6

	rts

; Starts the channels once the ring is full (or holds the whole rest of a
; short song), unless a newer request came in meanwhile.

start_if_ready:
	movem.l	d2-d4/a2/a6,-(sp)

	tst.b	music_playing
	bne		.done

	tst.l	ring_ready
	bne		.something_ready

	tst.l	side_ready ; AHI.
	beq		.done

.something_ready:

	tst.l	ring_free
	beq		.start

	tst.b	stream_ended
	beq		.done

.start:
	move.l	exec_base,a6
	jsr		_LVODisable(a6)

	tst.b	music_quit
	bne		.enable

	move.l	music_request_serial,d0
	cmp.l	handled_serial,d0
	bne		.enable

	tst.b	using_ahi
	bne		.ahi

	move	song_period,d0
	move	d0,AUD2LC+ac_per
	move	d0,AUD3LC+ac_per
	moveq	#MAXIMUM_VOLUME,d0
	bsr		set_music_volume

	move.l	#-1,playing_slot
	bsr		queue_next_block

	; Paula takes the block and raises the interrupt, which queues the next.

	move	#INTF_AUD2,INTREQ
	move	#INTF_SETCLR|INTF_AUD2,INTENA
	move	#DMAF_SETCLR|DMAF_MASTER|MUSIC_CHANNELS,DMACON
	st		music_playing
	addq.l	#1,songs_started

	bra		.enable

.ahi:
	; The song's rate on both music channels, full volume, hard left and
	; right, and the first block at once on both: the hook queues each
	; side's next half when it starts.

	move.l	ahi_control,a2
	move.l	ahi_base,a6
	moveq	#AHI_MUSIC_LEFT,d0
	move.l	song_rate,d1
	moveq	#AHISF_IMM,d2
	jsr		_LVOAHI_SetFreq(a6)

	moveq	#AHI_MUSIC_RIGHT,d0
	move.l	song_rate,d1
	moveq	#AHISF_IMM,d2
	jsr		_LVOAHI_SetFreq(a6)

	moveq	#MAXIMUM_VOLUME,d0
	bsr		set_music_volume

	st		music_playing
	addq.l	#1,songs_started
	move.l	#AHISF_IMM,ahi_queue_flags
	moveq	#0,d2
	bsr		queue_side
	moveq	#1,d2
	bsr		queue_side
	clr.l	ahi_queue_flags

	move.l	exec_base,a6

.enable:
	jsr		_LVOEnable(a6)

.done:
	movem.l	(sp)+,d2-d4/a2/a6

	rts

; ------------------------------------------------------------------------------
;
; Run summary line (main.s, after the run): nothing without MUSIC_DAT.

print_music_summary:
	movem.l	d2/a6,-(sp)

	tst.b	music_enabled
	beq		.done

	lea		music_summary_arguments,a0
	move.l	music_song_count,(a0)+
	move.l	songs_started,(a0)+
	move.l	blocks_read,(a0)+
	move.l	blocks_played,(a0)+
	move.l	music_underruns,(a0)+
	move.l	music_errors,(a0)+
	move.l	block_starts,(a0)+

	move.l	dos_base,a6
	move.l	#music_summary_format,d1
	move.l	#music_summary_arguments,d2
	jsr		_LVOVPrintf(a6)

.done:
	movem.l	(sp)+,d2/a6

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

audio_music_volume:
	dc.b	MAXIMUM_VOLUME ; MUSICVOL (main.s).
audio_effect_volume:
	dc.b	MAXIMUM_VOLUME ; SFXVOL.

	even

samples_file_name:
	dc.b	'samples.bin',0

music_directory:
	dc.b	'MUSIC_DAT',0

music_directory_prefix:
	dc.b	'MUSIC_DAT/',0

stream_extension:
	dc.b	'.crm',0

reader_name:
	dc.b	'Cho Ren Sha music',0

music_interrupt_name:
	dc.b	'Cho Ren Sha music',0

music_summary_format:
	dc.b	'Music: %ld songs, %ld started, %ld blocks read, %ld played, %ld underruns, %ld errors, %ld block starts',10,0

	even

ahi_device_name:
	dc.b	'ahi.device',0

mhi_format:
	dc.b	'Music: MHI, %s.',10,0

no_mhi_format:
	dc.b	'The MHI driver %s could not be opened: the music plays without it.',10,0

no_mhi_decoder_format:
	dc.b	'The MHI driver %s has no free decoder: the music plays without it.',10,0

mhi_intro_suffix:
	dc.b	'_intro.mp3',0

mhi_loop_suffix:
	dc.b	'_loop.mp3',0

	even

audio_mhi_driver: ; main.s writes the name after "MHI/".
	dc.b	'MHI/mhiz3660.library',0
	ds.b	MHI_DRIVER_NAME_SIZE-21

	even

ahi_format:
	dc.b	'Sound: AHI, %s (mode $%lx), mixing at %ld Hz.',10,0

no_ahi_format:
	dc.b	'AHI could not be opened (%s): the sound plays on Paula.',10,0

ahi_step_device:
	dc.b	'ahi.device version 4',0

ahi_step_allocate:
	dc.b	'no such audio mode, or it is in use',0

ahi_step_play:
	dc.b	'playback did not start',0

	even

; AHI_AllocAudioA: two channels (effects, music), two sounds.

ahi_allocation_tags:
	dc.l	AHIA_AudioID,AHI_DEFAULT_ID ; Set from audio_ahi_mode.
	dc.l	AHIA_MixFreq,AHI_DEFAULT_FREQ
	dc.l	AHIA_Channels,AHI_CHANNELS
	dc.l	AHIA_Sounds,AHI_SOUNDS
	dc.l	AHIA_SoundFunc,ahi_sound_hook
	dc.l	TAG_DONE

ahi_play_tags:
	dc.l	AHIC_Play,1
	dc.l	TAG_DONE

ahi_stop_tags:
	dc.l	AHIC_Play,0
	dc.l	TAG_DONE

ahi_frequency_tags:
	dc.l	AHIC_MixFreq_Query,ahi_mix_frequency
	dc.l	TAG_DONE

ahi_attribute_tags:
	dc.l	AHIDB_AudioID,ahi_mode_id
	dc.l	AHIDB_BufferLen,AHI_NAME_SIZE
	dc.l	AHIDB_Name,ahi_mode_name
	dc.l	TAG_DONE

; VPrintf arguments for ahi_format.

ahi_print_arguments:
	dc.l	ahi_mode_name
ahi_mode_id:
	dc.l	0
ahi_mix_frequency:
	dc.l	0

reader_tags:
	dc.l	NP_Entry,reader_process
	dc.l	NP_Name,reader_name
	dc.l	NP_Priority,READER_PRIORITY
	dc.l	NP_StackSize,READER_STACK_SIZE
	dc.l	TAG_DONE

; Paula volume for each fade step (0.75 dB each).

fade_volumes:
	dc.b	64,59,54,49,45,42,38,35,32,29,27,25,23,21,19,18
	dc.b	16,15,14,12,11,10,10,9,8,7,7,6,6,5,5,4
	dc.b	4,4,3,3,3,3,2,2,2,2,2,2,1,1,1,1
	dc.b	1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0

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

paula_clock:
	ds.l	1

; AHI

audio_ahi_mode:
	ds.l	1 ; Mode ID from the arguments (0: the preferences' mode).

ahi_port:
	ds.l	1

ahi_request:
	ds.b	AHIRequest_SIZEOF

ahi_base:
	ds.l	1

ahi_control:
	ds.l	1

ahi_sound_hook:
	ds.b	Hook_SIZEOF

ahi_mode_name:
	ds.b	AHI_NAME_SIZE

effect_sample_info:
	ds.b	AHISampleInfo_SIZEOF

music_sample_info:
	ds.b	AHISampleInfo_SIZEOF

ahi_queue_flags:
	ds.l	1

effect_offset:
	ds.l	1 ; Requested effect, played by audio_tick.

effect_length:
	ds.l	1

effect_rate:
	ds.l	1

effect_sides:
	ds.l	1

ring_size:
	ds.l	1

ahi_failed_step:
	ds.l	1 ; VPrintf argument: what failed.

; MHI

mhi_base:
	ds.l	1
mhi_buffers:
	ds.l	1
mhi_handle:
	ds.l	1
mhi_mask:
	ds.l	1
reader_wait_mask:
	ds.l	1 ; The reader's signals: wake, and MHI's.
mhi_free_buffers:
	ds.l	MHI_BUFFERS
mhi_free_count:
	ds.l	1
mhi_files:
	ds.l	2 ; The intro's and the loop's file (0: none).
mhi_current_file:
	ds.l	1 ; The file read from (0: the song's data has ended).
mhi_volume:
	ds.l	1 ; Wanted (0-100).
mhi_volume_set:
	ds.l	1
mhi_print_arguments:
	ds.l	1
mhi_intro_path:
	ds.b	MHI_PATH_SIZE
mhi_loop_path:
	ds.b	MHI_PATH_SIZE

side_ready:
	ds.l	2 ; AHI, per side (left, right): blocks ready, not queued yet.

side_read:
	ds.l	2 ; Next slot to queue.

side_playing:
	ds.l	2 ; Slot playing (-1: silence or none).

side_queued:
	ds.l	2 ; Slot queued (-1: silence).

slot_sides_ended:
	ds.b	RING_SLOTS ; Sides that have ended each slot.

song_rate:
	ds.l	1

; Music

music_songs:
	ds.b	MAXIMUM_SONGS*SONG_ENTRY_SIZE

music_song_count:
	ds.l	1

music_transferred:
	ds.l	1 ; Song entry of the last _TRANSMDC, or -1.

music_request_song:
	ds.l	1 ; Song entry to play, or -1: stop.

music_request_serial:
	ds.l	1 ; Counts the requests.

handled_serial:
	ds.l	1 ; The last request the reader handled.

music_process:
	ds.l	1

music_parent:
	ds.l	1

music_wake_mask:
	ds.l	1

music_interrupt:
	ds.b	IS_SIZE

	even

old_audio_vector:
	ds.l	1

ring_memory:
	ds.l	1

ring_silence:
	ds.l	1

ring_write:
	ds.l	1 ; Next slot the reader fills.

ring_read:
	ds.l	1 ; Next slot the interrupt queues.

ring_ready:
	ds.l	1 ; Slots filled and not queued yet.

ring_free:
	ds.l	1

playing_slot:
	ds.l	1 ; Slot Paula plays (-1: silence or none).

queued_slot:
	ds.l	1 ; Slot Paula plays next (-1: silence).

slot_frames:
	ds.w	RING_SLOTS

song_file:
	ds.l	1

song_header:
	ds.b	CRM_HEADER_SIZE

part_left:
	ds.l	1 ; Frames left to read in the intro or the loop.

loop_frames:
	ds.l	1

loop_offset:
	ds.l	1

song_period:
	ds.w	1

song_fade_unit:
	ds.w	1

song_level:
	ds.w	1

fade_speed:
	ds.l	1

fade_start:
	ds.l	1 ; E clock (low long).

fade_length:
	ds.l	1 ; E clock ticks.

fade_eclock:
	ds.l	2

songs_started:
	ds.l	1

blocks_read:
	ds.l	1

blocks_played:
	ds.l	1

music_underruns:
	ds.l	1

music_errors:
	ds.l	1

music_summary_arguments:
	ds.l	7

block_starts:
	ds.l	1 ; Interrupts or hook calls for the music.

audio_available:
	ds.b	1

audio_ahi_requested:
	ds.b	1

using_ahi:
	ds.b	1

audio_mhi_requested:
	ds.b	1

using_mhi:
	ds.b	1 ; The reader process has an MHI decoder.

mhi_signal:
	ds.b	1

effect_pending:
	ds.b	1

effect_stop_pending:
	ds.b	1

music_stop_pending:
	ds.b	1

samples_decoded:
	ds.b	1

music_available:
	ds.b	1

music_enabled:
	ds.b	1 ; Music was set up in this run (for the summary).

music_playing:
	ds.b	1

music_wake_pending:
	ds.b	1

music_quit:
	ds.b	1

fade_requested:
	ds.b	1

fade_active:
	ds.b	1

stream_ended:
	ds.b	1

in_loop:
	ds.b	1

handshake_signal:
	ds.b	1

wake_signal:
	ds.b	1

; ------------------------------------------------------------------------------
	end
; ------------------------------------------------------------------------------
