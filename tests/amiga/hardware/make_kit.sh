#!/bin/bash
#
# Builds the hardware test kit: binaries/amiga/hardware_test/ and
# binaries/amiga/hardware_test.zip (sz2_profile, vram_bench, RunTests,
# ReadMe.txt; without game data). Run ./build.sh first.

set -euo pipefail

cd "$(dirname "$0")/../../.."

kit=binaries/amiga/hardware_test

for file in binaries/amiga/sz2_profile binaries/amiga/vram_bench; do
	[ -f "$file" ] || { echo "$file missing: run ./build.sh first" >&2; exit 1; }
done

rm -rf "$kit" "$kit.zip"
mkdir -p "$kit"
cp binaries/amiga/sz2_profile binaries/amiga/vram_bench "$kit/"
# AmigaDOS text: LF line ends as they are.
cp tests/amiga/hardware/RunTests tests/amiga/hardware/ReadMe.txt "$kit/"

# A zip (UnZip on the Amiga); the lha here (Lhasa) cannot create archives.
(cd binaries/amiga && 7z a -tzip -bd -bso0 hardware_test.zip hardware_test)

ls -l "$kit" "$kit.zip"
