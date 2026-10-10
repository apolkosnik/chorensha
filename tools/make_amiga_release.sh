#!/bin/bash
#
# Packages the Amiga port for users: binaries/amiga/release/ with the
# ChoRenSha drawer (and its icon) holding the program, its tool icon, the
# ReadMe, the game data and the music streams, and
# binaries/amiga/ChoRenSha-amiga.zip and ChoRenSha-amiga.lha of it. Run
# ./build.sh and tools/music/build_music.sh first.

set -euo pipefail

cd "$(dirname "$0")/.."

release=binaries/amiga/release
drawer=$release/ChoRenSha

[ -f binaries/amiga/sz2 ] || { echo "binaries/amiga/sz2 missing: run ./build.sh first" >&2; exit 1; }

rm -rf "$release" binaries/amiga/ChoRenSha-amiga.zip
mkdir -p "$drawer"

cp binaries/amiga/sz2 "$drawer/ChoRenSha"
cp sources/amiga/icons/ChoRenSha.info "$drawer/ChoRenSha.info"
cp sources/amiga/icons/drawer.info "$release/ChoRenSha.info"
cp docs/amiga/ReadMe.txt "$drawer/ReadMe.txt"
cp -r binaries/amiga/BGM_DAT binaries/amiga/ETC_DAT binaries/amiga/PCM_DAT binaries/amiga/XSP_DAT "$drawer/"

# The music (tools/music/build_music.sh): the streams, and the MP3 files for
# MHI.
[ -d binaries/amiga/MUSIC_DAT ] || { echo "binaries/amiga/MUSIC_DAT missing: run tools/music/build_music.sh" >&2; exit 1; }
mkdir "$drawer/MUSIC_DAT"
cp binaries/amiga/MUSIC_DAT/*.crm binaries/amiga/MUSIC_DAT/*.mp3 "$drawer/MUSIC_DAT/"

# A zip (UnZip on the Amiga keeps the file names).
(cd "$release" && 7z a -tzip -bd -bso0 ../ChoRenSha-amiga.zip ChoRenSha ChoRenSha.info)

# An LhA archive, the Amiga's usual format (Aminet): the lha here (Lhasa)
# cannot create archives, so the system drive's LhA (C:LhA) packs it in
# FS-UAE (tests/amiga/run_fsuae.sh, on the fastest config). Lhasa then tests
# it, and its contents must equal the release drawer. NO_LHA=1 skips it.
if [ "${NO_LHA:-0}" = 0 ]; then
	system_dir=${AMIGA_SYSTEM_DIR:-$HOME/Documents/FS-UAE/Hard Drives/chorensha-wb32-rtg}
	work=$(mktemp -d)
	mkdir "$work/empty" "$work/out" "$work/check"
	rm -f binaries/amiga/ChoRenSha-amiga.lha

	# FS-UAE's host-directory filesystem sometimes stops answering (the
	# emulator hang in docs/AMIGA_PORT.md); packing takes about 6 minutes,
	# so after 20 the attempt is given up and made once more.
	for attempt in 1 2; do
		GAME_DATA_DIR="$work/empty" MUSIC=0 WORK_FILES="$drawer $release/ChoRenSha.info" \
			COPY_BACK=ChoRenSha-amiga.lha RESULT_DIR="$work/out" \
			tests/amiga/run_fsuae.sh rtg-040 "$system_dir/C/LhA" 1200 \
			"-r a ChoRenSha-amiga.lha ChoRenSha ChoRenSha.info" > "$work/lha.log" 2>&1 || true

		[ -f "$work/out/ChoRenSha-amiga.lha" ] && break
		echo "LhA attempt $attempt did not finish" >&2
	done

	if [ ! -f "$work/out/ChoRenSha-amiga.lha" ]; then
		cat "$work/lha.log" >&2
		echo "LhA archive not made (see above); work dir: $work" >&2
		exit 1
	fi

	lha -t "$work/out/ChoRenSha-amiga.lha" > "$work/test.log"
	(cd "$work/check" && lha -xq "$work/out/ChoRenSha-amiga.lha")
	diff -r "$release" "$work/check"
	mv "$work/out/ChoRenSha-amiga.lha" binaries/amiga/
	rm -rf "$work"
	ls -l binaries/amiga/ChoRenSha-amiga.lha
fi

ls -l binaries/amiga/ChoRenSha-amiga.zip
find "$release" -maxdepth 2 | sort
