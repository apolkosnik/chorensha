#!/bin/bash
#
# Boot a Workbench 3.2 + Picasso96 system in FS-UAE, run an executable from a
# second drive (WORK:) and print its output.
#
# usage: run_fsuae.sh <config> <executable> [timeout_seconds] [arguments]
#
# The program runs with WORK: as its current directory, next to a copy of the
# game data (the *_DAT directories of GAME_DATA_DIR, default binaries/amiga).
# Files it writes there (measure.bin, graphics.bin, checkpoints.bin, samples.bin,
# profile.bin, screen_*.bin) are copied to RESULT_DIR if set.
# With SERIAL_LOG set, the Amiga serial port is written to that host file.
# With KEEP_WORK set, the work directory (including fs-uae.log) is kept.
# FSUAE_OPTIONS adds FS-UAE options (e.g. --uae_mmu_model=68030).
# FS-UAE runs without a window (SDL offscreen video); SHOW_WINDOW=1 shows it.
# With INPUT_SCRIPT set, that file is copied to WORK:input.bin (pass
# "input.bin" in the arguments to use it). Files listed in WORK_FILES are
# copied to WORK: as well; text files the program writes there are copied to
# RESULT_DIR.
# With WORKBENCH set, Workbench is loaded and the program is started from
# its icon (WORKBENCH_ICON) with WBRun; see below.
# With RUN_FROM_RAM set, the program and data are copied to RAM: and run from
# there (no UAE host-directory filesystem during the run).
# With AUDIO_CAPTURE set, the emulated audio is written to that WAV file
# (OpenAL Soft's wave backend) and the emulation runs at real speed, not in
# warp mode, so the sound is not skipped. Drive sounds, the emulated output
# filter and interpolation are off for the capture.
#
# configs:
#   a1200-4mb  A1200, AGA, 68020 14 MHz, 2 MB chip, 4 MB fast (below the minimum)
#   a1200-8mb  A1200, AGA, 68020 14 MHz, 2 MB chip, 8 MB fast (minimum, native)
#   a1200-8mb-nce  the same with FS-UAE's non-cycle-exact 68020 core (emulation checks)
#   a1200-030  A1200, AGA, 68030 50 MHz, 64 MB fast, no RTG
#   a1200-030-8mb  A1200, AGA, 68030 50 MHz, 8 MB fast below 16 MB (Zorro II), no RTG
#   a1200-030-14   the same with the 68030 at 14 MHz (CPU type versus speed tests)
#   rtg-020    A1200, AGA, 68020 14 MHz, 4 MB fast, Zorro II uaegfx (minimum, RTG)
#   rtg-030    A4000, AGA, 68030 50 MHz, 64 MB Zorro III fast, Zorro III uaegfx
#   rtg-040    A4000, AGA, 68040 (fastest possible), 64 MB fast, Zorro III uaegfx
#   rtg-040-libs, rtg-060-libs
#              A4000, AGA, 68040 / 68060 with MMU and FPU, Zorro III uaegfx,
#              on the system drive variant with the MMULib CPU libraries
#              (68040.library / 68060.library) installed (AMIGA_CPULIBS_DIR)
#
# The 68020 and 68030 configs are cycle-exact (FS-UAE's A1200 default; the
# 68030 runs at 14 x 3.546895 MHz = 49.7 MHz), so E clock timings measured
# in them are meaningful. Warp mode only speeds up the host side.
#
# The system drive (AMIGA_SYSTEM_DIR) is Workbench 3.2 with Picasso96 and the
# uaegfx monitor; its S:Startup-Sequence runs WORK:Run-Test once the display
# drivers are loaded. Only the FS-UAE process group started here is stopped.
#
# (WinUAE 6.1.0b9 for Unix hangs in the uaegfx monitor driver with this
# system, so RTG testing uses FS-UAE.)

set -u

config=$1
executable=$2
timeout=${3:-120}
arguments=${4:-}

game_data_dir=${GAME_DATA_DIR:-$(dirname "$0")/../../binaries/amiga}

kickstart_dir=${KICKSTART_DIR:-$HOME/Documents/FS-UAE/Kickstarts}
system_dir=${AMIGA_SYSTEM_DIR:-$HOME/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg}
cpulibs_system_dir=${AMIGA_CPULIBS_DIR:-$HOME/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg-cpulibs}

a1200_kickstart="--kickstart_file=$kickstart_dir/A1200.47.115.rom"
a4000_kickstart="--kickstart_file=$kickstart_dir/A4kOS322.rom"

case $config in
	a1200-4mb)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=4096)
		;;
	a1200-8mb)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=8192)
		;;
	a1200-8mb-nce)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=8192
			--uae_cpu_cycle_exact=false --uae_cpu_compatible=false)
		;;
	a1200-030-14)
		options=(--amiga_model=A1200 "$a1200_kickstart" --uae_cpu_model=68030
			--uae_cpu_cycle_exact=true --uae_cpu_multiplier=4
			--uae_cpu_24bit_addressing=false --fast_memory=8192)
		;;
	a1200-030-8mb)
		options=(--amiga_model=A1200 "$a1200_kickstart" --uae_cpu_model=68030
			--uae_cpu_cycle_exact=true --uae_cpu_multiplier=14
			--uae_cpu_24bit_addressing=false --fast_memory=8192)
		;;
	a1200-030)
		options=(--amiga_model=A1200 "$a1200_kickstart" --uae_cpu_model=68030
			--uae_cpu_cycle_exact=true --uae_cpu_multiplier=14
			--uae_cpu_24bit_addressing=false --zorro_iii_memory=65536)
		;;
	rtg-020)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=4096
			--graphics_card=uaegfx-z2)
		;;
	rtg-030)
		options=(--amiga_model=A4000 "$a4000_kickstart" --uae_cpu_model=68030
			--uae_cpu_speed=real --uae_cpu_compatible=true
			--uae_cpu_cycle_exact=true --uae_cpu_multiplier=14
			--zorro_iii_memory=65536 --graphics_card=uaegfx)
		;;
	rtg-040)
		options=(--amiga_model=A4000/040 "$a4000_kickstart"
			--zorro_iii_memory=65536 --graphics_card=uaegfx)
		;;
	rtg-040-libs|rtg-060-libs)
		cpu=68${config:4:3} # 68040 or 68060
		options=(--amiga_model=A4000/040 "$a4000_kickstart" --uae_cpu_model=$cpu
			--uae_fpu_model=$cpu --uae_mmu_model=$cpu --uae_cpu_compatible=true
			--zorro_iii_memory=65536 --graphics_card=uaegfx)
		system_dir=$cpulibs_system_dir
		;;
	*)
		echo "unknown config: $config" >&2
		exit 2
		;;
esac

if [ ! -f "$system_dir/S/startup-sequence" ]; then
	echo "system drive not found: $system_dir (set AMIGA_SYSTEM_DIR)" >&2
	exit 2
fi

work_dir=$(mktemp -d)

# FS-UAE names a directory drive's volume after the directory.

drive=$work_dir/WORK
mkdir -p "$drive"

cp "$executable" "$drive/program"
cp -r "$game_data_dir"/*_DAT "$drive/"

if [ -n "${INPUT_SCRIPT:-}" ]; then
	cp "$INPUT_SCRIPT" "$drive/input.bin"
fi

for file in ${WORK_FILES:-}; do
	cp "$file" "$drive/"
done

# The marker is written after the program's output file is closed. FailAt 21
# keeps the script going when the program cannot be loaded; Why records the
# shell's error.

if [ -n "${WORKBENCH:-}" ]; then
	# Started from Workbench like a double-click on its icon (WORKBENCH_ICON,
	# copied as program.info, should give ARGUMENTS=<frames>): the run ends
	# when the program has written its checkpoints. Its text goes to its own
	# console window, not to output.txt.
	cp "$WORKBENCH_ICON" "$drive/program.info"
	printf 'FailAt 21\nLoadWB\nWait 5\nCD WORK:\nWBRun WORK:program >WORK:wbrun.txt\nLab wait\nWait 2\nIf NOT EXISTS WORK:checkpoints.bin\n  Skip wait BACK\nEndIf\nWait 3\nEcho "started from Workbench" >WORK:output.txt\nEcho "done" >WORK:marker.txt\n' > "$drive/Run-Test"
elif [ -n "${RUN_FROM_RAM:-}" ]; then
	# Everything copied to RAM: first, so the run does not use UAE's
	# host-directory filesystem (WORK:); the files it writes are copied back.
	printf 'FailAt 21\nCopy WORK: RAM:game ALL QUIET\nCD RAM:game\nRAM:game/program %s >RAM:game/output.txt\nWhy >>RAM:game/output.txt\nCopy RAM:game/#?.(bin|txt) WORK: QUIET\nEcho "done" >WORK:marker.txt\n' "$arguments" > "$drive/Run-Test"
else
	printf 'FailAt 21\nCD WORK:\nWORK:program %s >WORK:output.txt\nWhy >>WORK:output.txt\nEcho "done" >WORK:marker.txt\n' "$arguments" > "$drive/Run-Test"
fi

# FS-UAE runs in its own session. setsid may fork, so $! is not reliably the
# emulator; the shell inside the new session records its own PID (which is
# also the process group ID) before exec'ing FS-UAE.

if [ -z "${SHOW_WINDOW:-}" ]; then
	export SDL_VIDEODRIVER=offscreen
fi

warp_mode=1

if [ -n "${AUDIO_CAPTURE:-}" ]; then
	printf '[general]\ndrivers = wave\n\n[wave]\nfile = %s\n' "$(realpath -m "$AUDIO_CAPTURE")" \
		> "$work_dir/alsoft.conf"
	export ALSOFT_CONF="$work_dir/alsoft.conf"
	export ALSOFT_DRIVERS=wave
	warp_mode=0
	# Paula's output as it is: no drive sounds, no output filter or
	# interpolation by the emulator.
	options+=(--floppy_drive_volume=0 --uae_sound_filter=off --uae_sound_interpol=none)
fi

setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$work_dir/fs-uae.pid" \
	fs-uae "${options[@]}" ${FSUAE_OPTIONS:-} ${SERIAL_LOG:+--serial_port="$SERIAL_LOG"} \
	--hard_drive_0="$system_dir" --hard_drive_1="$drive" \
	--floppy_drive_0= --fullscreen=0 --automatic_input_grab=0 --warp_mode=$warp_mode \
	--base_dir="$work_dir" > "$work_dir/fs-uae.log" 2>&1 &

for ((i = 0; i < 50; i++)); do
	[ -s "$work_dir/fs-uae.pid" ] && break
	sleep 0.1
done

fsuae_pid=$(cat "$work_dir/fs-uae.pid" 2>/dev/null)

if [ -z "$fsuae_pid" ]; then
	echo "FS-UAE did not start, see $work_dir/fs-uae.log" >&2
	exit 1
fi

status=1

for ((i = 0; i < timeout; i++)); do
	if [ -f "$drive/marker.txt" ]; then
		status=0
		break
	fi

	if ! kill -0 $fsuae_pid 2>/dev/null; then
		echo "FS-UAE exited early, see $work_dir/fs-uae.log" >&2
		break
	fi

	sleep 1
done

if kill -0 $fsuae_pid 2>/dev/null; then
	kill -- -$fsuae_pid

	for ((i = 0; i < 50; i++)); do
		kill -0 $fsuae_pid 2>/dev/null || break
		sleep 0.1
	done
fi

if [ $status -eq 0 ]; then
	cat "$drive/output.txt"

	if [ -n "${RESULT_DIR:-}" ]; then
		mkdir -p "$RESULT_DIR"

		for result in measure graphics checkpoints samples profile sums; do
			if [ -f "$drive/$result.bin" ]; then
				cp "$drive/$result.bin" "$RESULT_DIR/$result-$config.bin"
			fi
		done

		for screenshot in "$drive"/screen_*.bin; do
			[ -f "$screenshot" ] || continue
			name=$(basename "$screenshot" .bin)
			cp "$screenshot" "$RESULT_DIR/$name-$config.bin"
		done

		for text in "$drive"/*.txt; do # Text files the program wrote.
			name=$(basename "$text")
			case $name in output.txt|marker.txt) continue;; esac
			[ -f "$text" ] && cp "$text" "$RESULT_DIR/${name%.txt}-$config.txt"
		done
	fi

	if [ -n "${KEEP_WORK:-}" ]; then
		echo "work dir kept: $work_dir" >&2
	else
		rm -rf "$work_dir"
	fi
else
	echo "no result after ${timeout}s (config $config), work dir kept: $work_dir" >&2
fi

exit $status
