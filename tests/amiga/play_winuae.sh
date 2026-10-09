#!/bin/bash
#
# Play the Amiga build interactively under WinUAE (Unix AppImage): a window
# with sound, keyboard and joystick, the game started from the boot shell
# with the game data and the music streams, no frame limit. WinUAE keeps
# running until its window is closed; the work directory is removed then.
#
# usage: play_winuae.sh [config] [arguments]
#   e.g. play_winuae.sh a1200-030
#        play_winuae.sh a1200-030 AHI=0x20007
#
# configs (AGA: WinUAE 6.1.0b9 for Unix hangs in the uaegfx RTG driver
# with this system):
#   a1200-030  A1200, AGA, 68030 as fast as the host allows, 64 MB fast
#              (default; for playing)
#   a1200-8mb  A1200, AGA, 68020 14 MHz cycle-exact, 8 MB fast (a stock
#              A1200 with the minimum memory: slow)
#
# Controls: the game's keyboard controls (cursor keys, CTRL or Z, SHIFT
# or X, P or ESC to pause, M for mouse control). JOYPORT=joy0 (or joy1, ...) puts a host joystick in port 2
# (default none: some keyboards register as joysticks too). MUSIC=0 leaves
# the music out. Prints the process group ID of the WinUAE it starts.

set -u

config=${1:-a1200-030}
arguments=${2:-}

cd "$(dirname "$0")/../.."

winuae=${WINUAE:-$HOME/Downloads/WinUAE-6.1.0b9-x86_64.AppImage}
kickstart_dir=${KICKSTART_DIR:-$HOME/Documents/FS-UAE/Kickstarts}
system_dir=${AMIGA_SYSTEM_DIR:-$HOME/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg}
game_data_dir=${GAME_DATA_DIR:-binaries/amiga}
executable=${EXECUTABLE:-binaries/amiga/sz2}

case $config in
	a1200-030)
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
	*)
		echo "unknown config: $config" >&2
		exit 2
		;;
esac

[ -f "$executable" ] || { echo "$executable missing: run ./build.sh" >&2; exit 1; }

work_dir=$(mktemp -d)
drive=$work_dir/work
mkdir -p "$drive"

cp "$executable" "$drive/ChoRenSha"

for data in "$game_data_dir"/*_DAT; do
	if [ "$(basename "$data")" != MUSIC_DAT ]; then
		cp -r "$data" "$drive/"
	fi
done

if [ "${MUSIC:-1}" != 0 ] && [ -d "$game_data_dir/MUSIC_DAT" ]; then
	mkdir "$drive/MUSIC_DAT"
	cp "$game_data_dir"/MUSIC_DAT/*.crm "$drive/MUSIC_DAT/"
fi

# The system drive's Startup-Sequence runs WORK:Run-Test.
printf 'CD WORK:\nWORK:ChoRenSha %s\nEcho "The game has ended; close the WinUAE window."\n' "$arguments" \
	> "$drive/Run-Test"

cat > "$work_dir/play.uae" <<EOF
use_gui=no
$settings
chipset=aga
nr_floppies=0
floppy0type=-1
sound_output=exact
sound_channels=stereo
sound_frequency=48000
sound_stereo_separation=10
joyport0=mouse
joyport1=${JOYPORT:-none}
filesystem2=ro,DH0:System:$system_dir,10
filesystem2=rw,DH1:WORK:$drive,-128
EOF

# setsid: WinUAE in its own process group, whose ID is recorded.
setsid bash -c 'echo $$ > "$1"; dir=$2; shift 2; "$@"; rm -rf "$dir"' _ "$work_dir/winuae.pid" \
	"$work_dir" "$winuae" -f "$work_dir/play.uae" -s use_gui=no > "$work_dir/winuae.log" 2>&1 &

for ((i = 0; i < 50; i++)); do
	[ -s "$work_dir/winuae.pid" ] && break
	sleep 0.1
done

echo "WinUAE started ($config${arguments:+, arguments: $arguments}), process group $(cat "$work_dir/winuae.pid")"
echo "work directory: $work_dir (removed when WinUAE exits)"
