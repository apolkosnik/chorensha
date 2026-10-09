#!/bin/bash
#
# Packages the Amiga port for users: binaries/amiga/release/ with the
# ChoRenSha drawer (and its icon) holding the program, its tool icon, the
# ReadMe and the game data, and binaries/amiga/ChoRenSha-amiga.zip of it.
# Run ./build.sh first.

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

# A zip (UnZip on the Amiga keeps the file names); the lha here (Lhasa)
# cannot create archives.
(cd "$release" && 7z a -tzip -bd -bso0 ../ChoRenSha-amiga.zip ChoRenSha ChoRenSha.info)

ls -l binaries/amiga/ChoRenSha-amiga.zip
find "$release" -maxdepth 2 | sort
