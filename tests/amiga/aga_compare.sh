#!/bin/bash
#
# Checks the native AGA output (c2p into bitplanes, double buffering, read
# back from the shown bitmap) against the RTG output: both are lockstep test
# builds of the working tree (-D__LOCKSTEP__: deterministic pictures) run on
# the same machine (default rtg-030, which has an AGA chipset as well), one
# showing the picture on the RTG screen, one on the AGA screen
# (-D__FORCE_AGA__). Every screenshot (every 100 frames) must be the same
# pixel for pixel, and both runs must match the attract checkpoints.
#
# With C2PLIB=1 the AGA build converts through c2plib (-D__C2PLIB__).
# AGA_GRAPHICS_FLAGS are passed to the AGA build's graphics.s (e.g.
# -D__PLANAR_BLITTER__ for the pipelined blitter frames of the 68020).
#
# usage: aga_compare.sh [config (rtg-030)] [frames (6000)]
# Results stay in a temporary directory, which is printed.

set -euo pipefail

config=${1:-rtg-030}
frames=${2:-6000}

cd "$(dirname "$0")/../.."

work=$(mktemp -d)
vasm=./tools/vasmm68k_mot
vlink=./tools/vlink

objects() { # objects <directory> <display flags> [graphics flags]
	local out=$1
	mkdir -p "$out"
	$vasm sources/amiga/main.s -quiet -Fhunk -m68000 -o "$out/main.o"
	$vasm sources/amiga/mem_map.s -quiet -Fhunk -m68030 -o "$out/mem_map.o"
	$vasm sources/amiga/emulator.s -quiet -Fhunk -m68030 -D__LOCKSTEP__ -o "$out/emulator.o"
	$vasm sources/amiga/input.s -quiet -Fhunk -m68030 -o "$out/input.o"
	$vasm sources/amiga/audio.s -quiet -Fhunk -m68030 -o "$out/audio.o"
	$vasm sources/amiga/graphics.s -quiet -Fhunk -m68030 ${3:-} -o "$out/graphics.o"
	$vasm sources/amiga/display.s -quiet -Fhunk -m68030 $2 -o "$out/display.o"
	$vasm sources/sz2.s -quiet -no-opt -Fhunk -m68030 -D__AMIGA__ -o "$out/sz2.o"
}

objects "$work/rtg" ""
$vlink "$work"/rtg/{main,sz2,mem_map,emulator,input,display,audio,graphics}.o -bamigahunk -s -o "$work/rtg/sz2"

aga_flags="-D__FORCE_AGA__"
extra=()

if [ -n "${C2PLIB:-}" ]; then
	aga_flags="$aga_flags -D__C2PLIB__"

	for f in c2p_8 c2p_8x8_mexg c2p_8x8_mexg_040; do
		$vasm sources/amiga/c2plib/$f.s -quiet -Fhunk -m68020 -o "$work/$f.o"
		extra+=("$work/$f.o")
	done
fi

objects "$work/aga" "$aga_flags" "${AGA_GRAPHICS_FLAGS:-}"
$vlink "$work"/aga/{main,sz2,mem_map,emulator,input,display,audio,graphics}.o "${extra[@]}" -bamigahunk -s -o "$work/aga/sz2"

for build in rtg aga; do
	RESULT_DIR="$work/$build/results" tests/amiga/run_fsuae.sh "$config" "$work/$build/sz2" 2400 "$frames" \
		| grep -aE "^Frames|Exception|Exit"
done

echo "results in $work"

status=0
python3 tests/amiga/checkpoints.py compare tests/amiga/reference/attract-6000.txt \
	"$work"/rtg/results/checkpoints-*.bin "$work"/aga/results/checkpoints-*.bin || status=1
python3 tests/amiga/screenshot_compare.py "$work/rtg/results" "$work/aga/results" \
	| grep -v ": same$" || true
python3 tests/amiga/screenshot_compare.py "$work/rtg/results" "$work/aga/results" > /dev/null || status=1

if [ $status -eq 0 ]; then
	echo "AGA and RTG output: same pictures ($(ls "$work"/aga/results/screen_*.bin | wc -l) screenshots)"
fi

exit $status
