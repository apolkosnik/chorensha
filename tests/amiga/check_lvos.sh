#!/bin/bash
#
# Checks every _LVOxxx=-n definition in the Amiga sources against the jsr
# offsets in the vbcc inline headers. A wrong LVO calls a different library
# function (an earlier StackSwap=-750 called exec's removed ChildStatus).
#
# usage: check_lvos.sh [inline header directory]

inline_dir=${1:-/opt/amiga-cc/vbcc/targets/m68k-amigaos/include/inline}
status=0

cd "$(dirname "$0")/../.."

for definition in $(grep -hoE "^_LVO[A-Za-z0-9]+=-[0-9]+" sources/amiga/*.s | sort -u); do
	name=${definition%%=*}
	value=${definition#*=}
	function=${name#_LVO}

	offset=$(grep -h -oE "__${function}\(__reg\(\"a6\"\)[^;]*jsr\\\\t-[0-9]+\(a6\)" "$inline_dir"/*_protos.h | grep -oE "jsr\\\\t-[0-9]+" | head -1 | grep -oE "[0-9]+")

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
