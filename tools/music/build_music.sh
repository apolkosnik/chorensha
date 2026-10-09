#!/bin/bash
#
# Renders the game's music (MCDRV .MDC songs in binaries/amiga/BGM_DAT) to
# files the Amiga port can play: binaries/amiga/MUSIC_DAT/NAME.crm (8-bit
# stereo stream for Paula, or AHI) and NAME_intro.mp3 / NAME_loop.mp3 (MHI).
#
# How: the original driver MCDRV.X (CUL, free software, v0.69) runs in a
# 68000 emulator (Musashi) with a minimal Human68k/X68000 environment
# (mcdrv_render.c), plays each song driven by the YM2151 timers and records
# the YM2151 register writes (and, in a second run, how long _FADEOUT takes);
# ymfm's YM2151 renders them (opm_render.cpp);
# make_amiga_music.py cuts intro and loop (first and second pass up to the
# song's loop command) and converts them.
#
# Downloads (into tools/music/deps, not in git): Musashi, ymfm, MCDRV 0.69.
# Needs gcc, g++, python3, ffmpeg (with soxr), lame, lha (Lhasa) and git.
#
# usage: tools/music/build_music.sh [rate (22050)]

set -euo pipefail

cd "$(dirname "$0")"
music=$PWD
rate=${1:-22050}
deps=$music/deps
work=$deps/work
out=$music/../../binaries/amiga/MUSIC_DAT
songs=$music/../../binaries/amiga/BGM_DAT

mkdir -p "$deps" "$work" "$out"

# Musashi (MIT licence), pinned.
if [ ! -d "$deps/Musashi" ]; then
	git clone -q https://github.com/kstenerud/Musashi.git "$deps/Musashi"
	git -C "$deps/Musashi" checkout -q 313ebf1bd9f4d0d93341eb5ce21fd8a119e9dbdd
fi

# ymfm (BSD licence).
if [ ! -d "$deps/ymfm" ]; then
	git clone -q https://github.com/aaronsgiles/ymfm.git "$deps/ymfm"
fi

# MCDRV 0.69 (free software, "copying and commercial use unrestricted").
if [ ! -f "$deps/mcdrv/MCDRV.X" ]; then
	mkdir -p "$deps/mcdrv"
	curl -s --max-time 60 -o "$deps/mcdrv/MCDRV069.Lzh" http://retropc.net/saya/x68000/lib/MCDRV069.Lzh
	(cd "$deps/mcdrv" && lha -xq MCDRV069.Lzh)
fi

# The emulator with the instruction hook and interrupt acknowledge on.
build=$deps/build
mkdir -p "$build"
cp "$deps"/Musashi/{m68kcpu.c,m68kdasm.c,m68k.h,m68kcpu.h,m68kfpu.c,m68kmmu.h,m68k_in.c,m68kmake.c} "$build/"
cp -r "$deps/Musashi/softfloat" "$build/"
sed -e 's/#define M68K_EMULATE_INT_ACK        M68K_OPT_OFF/#define M68K_EMULATE_INT_ACK        M68K_OPT_ON/' \
	-e 's/#define M68K_INSTRUCTION_HOOK       M68K_OPT_OFF/#define M68K_INSTRUCTION_HOOK       M68K_OPT_ON/' \
	"$deps/Musashi/m68kconf.h" > "$build/m68kconf.h"
grep -q "M68K_INSTRUCTION_HOOK       M68K_OPT_ON" "$build/m68kconf.h"
(cd "$build" && gcc -O2 -o m68kmake m68kmake.c && ./m68kmake . m68k_in.c > /dev/null)
gcc -O2 -I"$build" -o "$build/mcdrv_render" "$music/mcdrv_render.c" "$build"/m68kcpu.c \
	"$build"/m68kops.c "$build"/m68kdasm.c "$build"/softfloat/softfloat.c -lm
g++ -O2 -std=c++17 -I"$deps/ymfm/src" -o "$build/opm_render" "$music/opm_render.cpp" "$deps/ymfm/src/ymfm_opm.cpp"

# Every song: three loops (or its end), then the render.
for song in "$songs"/*.MDC; do
	name=$(basename "$song" .MDC)
	"$build/mcdrv_render" "$deps/mcdrv/MCDRV.X" "$song" 900 "$work/$name.log" 3 2> /dev/null
	# The fade length: _FADEOUT with speed 4 at 1 s.
	"$build/mcdrv_render" "$deps/mcdrv/MCDRV.X" "$song" 60 "$work/$name.fade.log" 0 1 4 2> /dev/null
	"$build/opm_render" "$work/$name.log" "$work/${name}_full.wav" 2> /dev/null
done

python3 "$music/make_amiga_music.py" "$work" "$out" "$rate"
du -sh "$out"
