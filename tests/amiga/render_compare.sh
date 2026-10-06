#!/bin/bash
#
# Compare the renderer of the working tree with the renderer of a commit:
# both are built as lockstep test builds (-D__LOCKSTEP__: the game's VBLs
# follow its frames and every frame is rendered, so the pictures are the
# same in every run) and run the attract demo in FS-UAE; the screenshots
# (every 100 frames) must be the same pixel for pixel, and the checkpoints
# must match the attract reference.
#
# The commit contributes sources/amiga/graphics.s and display.s; everything
# else (port layer, game) comes from the working tree, so the two builds
# differ only in the renderer.
#
# usage: render_compare.sh <commit> [config (rtg-030)] [frames (6000)]
# Results stay in a temporary directory, which is printed.

set -euo pipefail

commit=$1
config=${2:-rtg-030}
frames=${3:-6000}

cd "$(dirname "$0")/../.."

work=$(mktemp -d)
vasm=./tools/vasmm68k_mot
vlink=./tools/vlink

build() { # build <directory> <graphics.s> <display.s>
	local out=$1
	mkdir -p "$out"
	$vasm sources/amiga/main.s -quiet -Fhunk -m68000 -o "$out/main.o"
	$vasm sources/amiga/mem_map.s -quiet -Fhunk -m68030 -o "$out/mem_map.o"
	$vasm sources/amiga/emulator.s -quiet -Fhunk -m68030 -D__LOCKSTEP__ -o "$out/emulator.o"
	$vasm sources/amiga/input.s -quiet -Fhunk -m68030 -o "$out/input.o"
	$vasm sources/amiga/audio.s -quiet -Fhunk -m68030 -o "$out/audio.o"
	$vasm "$3" -quiet -Fhunk -m68030 -o "$out/display.o"
	$vasm "$2" -quiet -Fhunk -m68030 -o "$out/graphics.o"
	$vasm sources/sz2.s -quiet -no-opt -Fhunk -m68030 -D__AMIGA__ -o "$out/sz2.o"
	$vlink "$out/main.o" "$out/sz2.o" "$out/mem_map.o" "$out/emulator.o" "$out/input.o" \
		"$out/display.o" "$out/audio.o" "$out/graphics.o" -bamigahunk -s -o "$out/sz2"
}

mkdir -p "$work/reference_sources"
git show "$commit:sources/amiga/graphics.s" > "$work/reference_sources/graphics.s"
git show "$commit:sources/amiga/display.s" > "$work/reference_sources/display.s"

build "$work/reference" "$work/reference_sources/graphics.s" "$work/reference_sources/display.s"
build "$work/current" sources/amiga/graphics.s sources/amiga/display.s

for build in reference current; do
	RESULT_DIR="$work/$build/results" tests/amiga/run_fsuae.sh "$config" "$work/$build/sz2" 1800 "$frames" \
		| grep -aE "^Frames|Exception|Exit"
done

echo "results in $work"

status=0
python3 tests/amiga/checkpoints.py compare tests/amiga/reference/attract-6000.txt \
	"$work"/reference/results/checkpoints-*.bin "$work"/current/results/checkpoints-*.bin || status=1
python3 tests/amiga/screenshot_compare.py "$work/reference/results" "$work/current/results" \
	| grep -v ": same$" || true
python3 tests/amiga/screenshot_compare.py "$work/reference/results" "$work/current/results" > /dev/null || status=1

if [ $status -eq 0 ]; then
	echo "renderer of the working tree and of $commit: same pictures ($(ls "$work"/current/results/screen_*.bin | wc -l) screenshots)"
fi

exit $status
