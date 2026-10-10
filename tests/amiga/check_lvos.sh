#!/bin/bash
#
# Checks every _LVOxxx=-n definition in the Amiga sources against the jsr
# offsets in the vbcc inline headers. A wrong LVO calls a different library
# function (an earlier StackSwap=-750 called exec's removed ChildStatus).
# Libraries without vbcc headers (MHI drivers) are checked against the .fd
# files in tests/amiga/fd (offset = bias + 6 per public function).
#
# usage: check_lvos.sh [inline header directory]

inline_dir=${1:-/opt/amiga-cc/vbcc/targets/m68k-amigaos/include/inline}
status=0

cd "$(dirname "$0")/../.."

for definition in $(grep -hoE "^_LVO[A-Za-z0-9]+=-[0-9]+" sources/amiga/*.s tests/amiga/hardware/*.s tests/amiga/tools/*.s | sort -u); do
	name=${definition%%=*}
	value=${definition#*=}
	function=${name#_LVO}

	offset=$(grep -h -oE "__${function}\(__reg\(\"a6\"\)[^;]*jsr\\\\t-[0-9]+\(a6\)" "$inline_dir"/*_protos.h | grep -oE "jsr\\\\t-[0-9]+" | head -1 | grep -oE "[0-9]+")

	if [ -z "$offset" ]; then
		offset=$(awk -v f="$function" '
			/^##bias/ { bias = $2 }
			/^##(public|private)/ { next }
			/^##/ { next }
			/^\*/ { next }
			/\(/ { name = $0; sub(/\(.*/, "", name); if (name == f) { print bias; exit } bias += 6 }
		' tests/amiga/fd/*.fd 2>/dev/null)
	fi

	if [ -z "$offset" ]; then
		echo "$name: not found in $inline_dir"
		status=1
	elif [ "-$offset" != "$value" ]; then
		echo "$name: $value, should be -$offset"
		status=1
	fi
done

[ $status -eq 0 ] && echo "all LVOs match"

exit $status
