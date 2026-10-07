#
# X68000
#
./tools/vasmm68k_mot.exe sources/sz2.s -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -o binaries/sz2_x68k.o
./tools/vasmm68k_mot.exe sources/x68000/mem_map.s -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -o binaries/mem_map.o
./tools/human68k-ld.exe -q -o binaries/sz2.o binaries/sz2_x68k.o binaries/mem_map.o
./tools/human68k-objcopy.exe -O xfile binaries/sz2.o binaries/sz2.x 
cp binaries/sz2.x binaries/x68000/CH68_101_B/SZ2.X 

#xxd binaries/sz2.x > binaries/sz2.hex
#diff binaries/sz2.hex binaries/x68000/sz2.hex > binaries/sz2.dif
#diff binaries/sz2.dif binaries/x68000/sz2.dif

#
# Atari
#
./tools/vasmm68k_mot.exe sources/sz2.s -quiet -no-opt -Faout -m68030 -D__ATARI__ -o binaries/sz2_atari.o
./tools/vasmm68k_mot.exe sources/atari/main.s -quiet -Faout -m68030 -o binaries/main.o
./tools/vasmm68k_mot.exe sources/atari/mem_map.s -quiet -Faout -m68030 -o binaries/mem_map.o
./tools/vasmm68k_mot.exe sources/atari/input.s -quiet -Faout -m68030 -o binaries/input.o
./tools/vasmm68k_mot.exe sources/atari/emulator.s -quiet -Faout -m68030 -o binaries/emulator.o
./tools/vasmm68k_mot.exe sources/atari/machine.s -quiet -Faout -m68030 -o binaries/machine.o
./tools/vasmm68k_mot.exe sources/atari/graphics.s -quiet -Faout -m68030 -o binaries/graphics.o
./tools/vasmm68k_mot.exe sources/atari/graphics.s -quiet -Faout -m68030 -D__HATARI__ -o binaries/graphics_hatari.o
./tools/vasmm68k_mot.exe sources/atari/audio.s -quiet -Faout -m68030 -o binaries/audio.o

./tools/vlink.exe binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/machine.o binaries/graphics.o binaries/audio.o -tos-flags 7 -bataritos -estart -o binaries/atari/sz2_dbg.tos
./tools/vlink.exe binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/machine.o binaries/graphics.o binaries/audio.o -s -tos-flags 7 -bataritos -estart -o binaries/atari/sz2.tos
./tools/vlink.exe binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/machine.o binaries/graphics_hatari.o binaries/audio.o -s -tos-flags 7 -bataritos -estart -o binaries/atari/sz2_hatari.tos

./tools/asm56000.exe -q -a -isources/atari -bbinaries/dsprite.cld -z -lbinaries/dsprite.lst sources/atari/dsprite.asm
./tools/cldlod.exe binaries/dsprite.cld > binaries/atari/dsprite.lod

#
# Amiga
#

# Target: 68030 with fast RAM and an RTG card. main.s is assembled for the
# 68000 so it reports missing requirements instead of crashing on a lesser
# CPU. The game core is plain 68000 code.

./tools/vasmm68k_mot.exe sources/amiga/main.s -quiet -Fhunk -m68000 -o binaries/amiga_main.o
./tools/vasmm68k_mot.exe sources/amiga/mem_map.s -quiet -Fhunk -m68030 -o binaries/amiga_mem_map.o
./tools/vasmm68k_mot.exe sources/amiga/emulator.s -quiet -Fhunk -m68030 -o binaries/amiga_emulator.o
./tools/vasmm68k_mot.exe sources/amiga/graphics.s -quiet -Fhunk -m68030 -o binaries/amiga_graphics.o
./tools/vasmm68k_mot.exe sources/amiga/input.s -quiet -Fhunk -m68030 -o binaries/amiga_input.o
./tools/vasmm68k_mot.exe sources/amiga/display.s -quiet -Fhunk -m68030 -o binaries/amiga_display.o
./tools/vasmm68k_mot.exe sources/amiga/audio.s -quiet -Fhunk -m68030 -o binaries/amiga_audio.o
./tools/vasmm68k_mot.exe sources/sz2.s -quiet -no-opt -Fhunk -m68030 -D__AMIGA__ -o binaries/sz2_amiga.o

./tools/vlink.exe binaries/amiga_main.o binaries/sz2_amiga.o binaries/amiga_mem_map.o binaries/amiga_emulator.o binaries/amiga_input.o binaries/amiga_display.o binaries/amiga_audio.o binaries/amiga_graphics.o -bamigahunk -o binaries/amiga/sz2_dbg
./tools/vlink.exe binaries/amiga_main.o binaries/sz2_amiga.o binaries/amiga_mem_map.o binaries/amiga_emulator.o binaries/amiga_input.o binaries/amiga_display.o binaries/amiga_audio.o binaries/amiga_graphics.o -bamigahunk -s -o binaries/amiga/sz2

# Hardware test kit (tests/amiga/hardware): the game with render profiling
# (writes profile.bin) and the screen memory benchmark.

./tools/vasmm68k_mot.exe sources/amiga/main.s -quiet -Fhunk -m68000 -D__RENDER_PROFILE__ -o binaries/amiga_main_profile.o
./tools/vasmm68k_mot.exe sources/amiga/emulator.s -quiet -Fhunk -m68030 -D__RENDER_PROFILE__ -o binaries/amiga_emulator_profile.o
./tools/vasmm68k_mot.exe sources/amiga/graphics.s -quiet -Fhunk -m68030 -D__RENDER_PROFILE__ -o binaries/amiga_graphics_profile.o
./tools/vasmm68k_mot.exe sources/amiga/display.s -quiet -Fhunk -m68030 -D__RENDER_PROFILE__ -o binaries/amiga_display_profile.o
./tools/vlink.exe binaries/amiga_main_profile.o binaries/sz2_amiga.o binaries/amiga_mem_map.o binaries/amiga_emulator_profile.o binaries/amiga_input.o binaries/amiga_display_profile.o binaries/amiga_audio.o binaries/amiga_graphics_profile.o -bamigahunk -s -o binaries/amiga/sz2_profile
./tools/vasmm68k_mot.exe tests/amiga/hardware/vram_bench.s -quiet -Fhunk -m68020 -o binaries/amiga_vram_bench.o
./tools/vlink.exe binaries/amiga_vram_bench.o -bamigahunk -s -o binaries/amiga/vram_bench
