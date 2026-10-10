#!/bin/bash
#
# Run an executable under WinUAE (Unix AppImage) instead of FS-UAE, for
# checking emulation-specific results against a second emulator. Same drive
# layout as run_fsuae.sh: the Workbench 3.2 system drive boots and runs
# WORK:Run-Test, which runs the program from WORK: with the game data.
#
# usage: run_winuae.sh <config> <executable> [timeout_seconds] [arguments]
#
# configs:
#   a1200-8mb   A1200, AGA, 68020 14 MHz cycle-exact, 8 MB fast
#   a1200-030   A1200, AGA, 68030 cycle-exact (x4 multiplier), 8 MB fast
#   a1200-030-fast  A1200, AGA, 68030 as fast as the host allows, 64 MB
#               Zorro III fast (the play_winuae.sh a1200-030 machine)
#
# SOUND_OUTPUT=exact emulates Paula (to SDL's dummy audio driver); by
# default sound is off and Paula's DMA and interrupts do not run.
#
# INPUT_SCRIPT: copied to WORK:input.bin (pass "input.bin" in the arguments),
# as in run_fsuae.sh.
#
# RESULT_DIR: files the program wrote (measure, graphics, checkpoints, samples,
# profile, sums, screen_*) are copied there, named <name>-winuae-<config>.
# Video and audio use the SDL dummy drivers (SHOW_WINDOW=1 for a window).
# Only the process group started here is stopped.

set -u

config=$1
executable=$2
timeout=${3:-300}
arguments=${4:-}

cd "$(dirname "$0")/../.."

winuae=${WINUAE:-$HOME/Downloads/WinUAE-6.1.0b9-x86_64.AppImage}
kickstart_dir=${KICKSTART_DIR:-$HOME/Documents/FS-UAE/Kickstarts}
system_dir=${AMIGA_SYSTEM_DIR:-$HOME/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg}
game_data_dir=${GAME_DATA_DIR:-binaries/amiga}

case $config in
	a1200-8mb)
		settings="kickstart_rom_file=$kickstart_dir/A1200.47.115.rom
chipset_compatible=A1200
cpu_model=68020
cpu_24bit_addressing=true
cpu_compatible=true
cpu_cycle_exact=true
cpu_memory_cycle_exact=true
blitter_cycle_exact=true
cpu_speed=real
chipmem_size=4
fastmem_size=8"
		;;
	a1200-030)
		settings="kickstart_rom_file=$kickstart_dir/A1200.47.115.rom
chipset_compatible=A1200
cpu_model=68030
cpu_24bit_addressing=false
cpu_compatible=true
cpu_cycle_exact=true
cpu_memory_cycle_exact=true
blitter_cycle_exact=true
cpu_speed=real
cpu_multiplier=4
chipmem_size=4
fastmem_size=8"
		;;
	a1200-030-fast)
		settings="kickstart_rom_file=$kickstart_dir/A1200.47.115.rom
chipset_compatible=A1200
cpu_model=68030
cpu_24bit_addressing=false
cpu_compatible=false
cpu_cycle_exact=false
cpu_speed=max
chipmem_size=4
z3mem_size=64"
		;;
	*)
		echo "unknown config: $config" >&2
		exit 2
		;;
esac

work_dir=$(mktemp -d)
drive=$work_dir/work
mkdir -p "$drive"

cp "$executable" "$drive/program"
for data in "$game_data_dir"/*_DAT; do
	if [ "$(basename "$data")" != MUSIC_DAT ]; then
		cp -r "$data" "$drive/"
	fi
done

# The rendered music streams, as in run_fsuae.sh (MUSIC=0 leaves them out).
if [ "${MUSIC:-1}" != 0 ] && [ -d "$game_data_dir/MUSIC_DAT" ]; then
	mkdir "$drive/MUSIC_DAT"
	cp "$game_data_dir"/MUSIC_DAT/*.crm "$drive/MUSIC_DAT/"

	if [ "${MUSIC_MP3:-0}" != 0 ]; then
		cp "$game_data_dir"/MUSIC_DAT/*.mp3 "$drive/MUSIC_DAT/"
	fi
fi

if [ -n "${INPUT_SCRIPT:-}" ]; then
	cp "$INPUT_SCRIPT" "$drive/input.bin"
fi

# AFTER_WAIT: seconds the system runs on after the program has ended before
# the run counts as done (something the program left behind may crash it).
printf 'FailAt 21\nCD WORK:\nWORK:program %s >WORK:output.txt\nWhy >>WORK:output.txt\nWait %s\nEcho "done" >WORK:marker.txt\n' "$arguments" "${AFTER_WAIT:-0}" > "$drive/Run-Test"

cat > "$work_dir/test.uae" <<EOF
use_gui=no
$settings
chipset=aga
nr_floppies=0
floppy0type=-1
sound_output=${SOUND_OUTPUT:-none}
filesystem2=ro,DH0:System:$system_dir,10
filesystem2=rw,DH1:WORK:$drive,-128
EOF

if [ -z "${SHOW_WINDOW:-}" ]; then
	export SDL_VIDEO_DRIVER=dummy
fi

export SDL_AUDIO_DRIVER=dummy

# setsid: WinUAE runs in its own process group; the shell inside records its
# PID (the group ID) before exec'ing it.

setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$work_dir/winuae.pid" \
	"$winuae" -f "$work_dir/test.uae" -s use_gui=no > "$work_dir/winuae.log" 2>&1 &

for ((i = 0; i < 50; i++)); do
	[ -s "$work_dir/winuae.pid" ] && break
	sleep 0.1
done

winuae_pid=$(cat "$work_dir/winuae.pid" 2>/dev/null)
status=1

for ((i = 0; i < timeout; i++)); do
	if [ -f "$drive/marker.txt" ]; then
		status=0
		break
	fi

	if ! kill -0 "$winuae_pid" 2>/dev/null; then
		echo "WinUAE exited early, see $work_dir/winuae.log" >&2
		break
	fi

	sleep 1
done

if kill -0 "$winuae_pid" 2>/dev/null; then
	kill -- -"$winuae_pid"
	sleep 1
fi

if [ $status -eq 0 ]; then
	cat "$drive/output.txt"

	if [ -n "${RESULT_DIR:-}" ]; then
		mkdir -p "$RESULT_DIR"

		for file in "$drive"/*.bin; do
			[ -f "$file" ] || continue
			name=$(basename "$file" .bin)
			cp "$file" "$RESULT_DIR/$name-winuae-$config.bin"
		done
	fi

	rm -rf "$work_dir"
else
	echo "no result after ${timeout}s (config $config), work dir kept: $work_dir" >&2
fi

exit $status
