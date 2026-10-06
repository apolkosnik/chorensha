#!/bin/bash
#
# Boot a Workbench 3.2 + Picasso96 system in FS-UAE, run an executable from a
# second drive (WORK:) and print its output.
#
# usage: run_fsuae.sh <config> <executable> [timeout_seconds]
#
# configs:
#   a1200-4mb  A1200, AGA, 68020, 2 MB chip, 4 MB fast (below the minimum)
#   a1200-8mb  A1200, AGA, 68020, 2 MB chip, 8 MB fast (minimum, native)
#   a1200-030  A1200, AGA, 68030, 64 MB Zorro III fast, no RTG
#   rtg-020    A1200, AGA, 68020, 4 MB fast, Zorro II uaegfx (minimum, RTG)
#   rtg-030    A4000, AGA, 68030, 64 MB Zorro III fast, Zorro III uaegfx
#   rtg-040    A4000, AGA, 68040, 64 MB Zorro III fast, Zorro III uaegfx
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

kickstart_dir=${KICKSTART_DIR:-$HOME/Documents/FS-UAE/Kickstarts}
system_dir=${AMIGA_SYSTEM_DIR:-$HOME/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg}

a1200_kickstart="--kickstart_file=$kickstart_dir/A1200.47.115.rom"
a4000_kickstart="--kickstart_file=$kickstart_dir/A4kOS322.rom"

case $config in
	a1200-4mb)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=4096)
		;;
	a1200-8mb)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=8192)
		;;
	a1200-030)
		options=(--amiga_model=A1200 "$a1200_kickstart" --uae_cpu_model=68030
			--uae_cpu_24bit_addressing=false --zorro_iii_memory=65536)
		;;
	rtg-020)
		options=(--amiga_model=A1200 "$a1200_kickstart" --fast_memory=4096
			--graphics_card=uaegfx-z2)
		;;
	rtg-030)
		options=(--amiga_model=A4000 "$a4000_kickstart" --uae_cpu_model=68030
			--zorro_iii_memory=65536 --graphics_card=uaegfx)
		;;
	rtg-040)
		options=(--amiga_model=A4000/040 "$a4000_kickstart"
			--zorro_iii_memory=65536 --graphics_card=uaegfx)
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

# The marker is written after the program's output file is closed. FailAt 21
# keeps the script going when the program cannot be loaded; Why records the
# shell's error.

printf 'FailAt 21\nWORK:program >WORK:output.txt\nWhy >>WORK:output.txt\nEcho "done" >WORK:marker.txt\n' > "$drive/Run-Test"

# FS-UAE runs in its own session. setsid may fork, so $! is not reliably the
# emulator; the shell inside the new session records its own PID (which is
# also the process group ID) before exec'ing FS-UAE.

setsid bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$work_dir/fs-uae.pid" \
	fs-uae "${options[@]}" --hard_drive_0="$system_dir" --hard_drive_1="$drive" \
	--floppy_drive_0= --fullscreen=0 --automatic_input_grab=0 --warp_mode=1 \
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
	rm -rf "$work_dir"
else
	echo "no result after ${timeout}s (config $config), work dir kept: $work_dir" >&2
fi

exit $status
