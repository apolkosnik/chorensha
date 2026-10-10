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

rm -rf "$release" binaries/amiga/ChoRenSha-amiga.zip binaries/amiga/ChoRenSha-amiga.lha
mkdir -p "$drawer"

cp binaries/amiga/sz2 "$drawer/ChoRenSha"
cp sources/amiga/icons/ChoRenSha.info "$drawer/ChoRenSha.info"
cp sources/amiga/icons/drawer.info "$release/ChoRenSha.info"
cp README.md "$drawer/ReadMe.txt"
cp -r binaries/amiga/BGM_DAT binaries/amiga/ETC_DAT binaries/amiga/PCM_DAT binaries/amiga/XSP_DAT "$drawer/"

# The music (tools/music/build_music.sh): the streams, and the MP3 files for
# MHI.
[ -d binaries/amiga/MUSIC_DAT ] || { echo "binaries/amiga/MUSIC_DAT missing: run tools/music/build_music.sh" >&2; exit 1; }
mkdir "$drawer/MUSIC_DAT"
cp binaries/amiga/MUSIC_DAT/*.crm binaries/amiga/MUSIC_DAT/*.mp3 "$drawer/MUSIC_DAT/"

# A zip (UnZip on the Amiga keeps the file names).
(cd "$release" && 7z a -tzip -bd -bso0 ../ChoRenSha-amiga.zip ChoRenSha ChoRenSha.info)

# An LhA archive, the Amiga's usual format (Aminet), packed by LHa for UNIX
# (Lhasa, also installed as lha, cannot create archives): -lh5- with level 1
# headers, as the Amiga's LhA makes them. It is tested, and its contents must
# equal the release drawer. NO_LHA=1 skips it.
if [ "${NO_LHA:-0}" = 0 ]; then
	lha --version 2>&1 | grep -q "LHa for UNIX" ||
		{ echo "lha is not LHa for UNIX (Lhasa cannot create archives): install it (AUR lha) or set NO_LHA=1" >&2; exit 1; }
	rm -f binaries/amiga/ChoRenSha-amiga.lha
	(cd "$release" && lha ao51q ../ChoRenSha-amiga.lha ChoRenSha ChoRenSha.info)

	work=$(mktemp -d)
	lha tq binaries/amiga/ChoRenSha-amiga.lha
	(cd "$work" && lha xq "$OLDPWD/binaries/amiga/ChoRenSha-amiga.lha")
	diff -r "$release" "$work"
	rm -rf "$work"
	ls -l binaries/amiga/ChoRenSha-amiga.lha
fi

ls -l binaries/amiga/ChoRenSha-amiga.zip
find "$release" -maxdepth 2 | sort
