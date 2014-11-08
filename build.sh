#
# X68000
#

#
# Atari
#
./vasmm68k_mot sources/sz2.s -quiet -no-opt -Faout -m68030 -D__ATARI__ -o binaries/sz2_atari.o
./vasmm68k_mot sources/atari/main.s -quiet -Faout -m68030 -o binaries/main.o
./vasmm68k_mot sources/atari/mem_map.s -quiet -Faout -m68030 -o binaries/mem_map.o
./vasmm68k_mot sources/atari/input.s -quiet -Faout -m68030 -o binaries/input.o
./vasmm68k_mot sources/atari/emulator.s -quiet -Faout -m68030 -o binaries/emulator.o
./vasmm68k_mot sources/atari/graphics.s -quiet -Faout -m68030 -o binaries/graphics.o
./vasmm68k_mot sources/atari/audio.s -quiet -Faout -m68030 -o binaries/audio.o

./vlink binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/graphics.o binaries/audio.o -tos-flags 7 -bataritos -estart -o binaries/atari/sz2_dbg.tos
./vlink binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/graphics.o binaries/audio.o -s -tos-flags 7 -bataritos -estart -o binaries/atari/sz2.tos

#
# Amiga
#

