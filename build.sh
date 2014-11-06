#
# X68000
#
./vasmm68k_mot sources/sz2.s -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -o binaries/sz2_x68k.o
./vasmm68k_mot sources/x68000/mem_map.s -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -o binaries/mem_map.o
human68k-gcc -nostartfiles binaries/sz2_x68k.o binaries/mem_map.o -o binaries/sz2.o 
human68k-objcopy -O xfile binaries/sz2.o binaries/sz2.x 
cp binaries/sz2.x binaries/x68000/CH68_101_B/SZ2.X 

xxd binaries/sz2.x > binaries/sz2.hex
diff binaries/sz2.hex binaries/x68000/sz2.hex > binaries/sz2.dif
diff binaries/sz2.dif binaries/x68000/sz2.dif

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

./vlink binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/graphics.o binaries/audio.o -b ataritos -e start -o binaries/atari/sz2_dbg.tos
./vlink binaries/main.o binaries/sz2_atari.o binaries/mem_map.o binaries/input.o binaries/emulator.o binaries/graphics.o binaries/audio.o -s -b ataritos -e start -o binaries/atari/sz2.tos

#
# Amiga
#

