#
# X68000
#
./vasmm68k_mot sources/sz2.s -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -o binaries/sz2_x68k.o
./vasmm68k_mot sources/x68000.s -quiet -Felf -nosym -no-opt -m68000 -rangewarnings -o binaries/x68000.o
human68k-gcc -nostartfiles binaries/sz2_x68k.o binaries/x68000.o -o binaries/sz2.o 
human68k-objcopy -O xfile binaries/sz2.o binaries/sz2.x 
cp binaries/sz2.x binaries/x68000/CH68_101_B/SZ2.X 
xxd binaries/sz2.x > binaries/sz2.hex
diff binaries/sz2.hex binaries/x68000/sz2.hex > binaries/sz2.dif
diff binaries/sz2.dif binaries/x68000/sz2.dif

#
# Atari
#
./vasmm68k_mot sources/sz2.s -quiet -nosym -no-opt -Faout -m68030 -D__ATARI__ -o binaries/sz2_atari.o
./vasmm68k_mot sources/atari.s -quiet -nosym -Faout -m68030 -o binaries/atari.o
./vlink binaries/atari.o binaries/sz2_atari.o -b ataritos -e start -o binaries/atari/sz2.tos

./vasmm68k_mot sources/atari.s -quiet -nosym -Faout -m68030 -D__HATARI__ -o binaries/atari.o
./vlink binaries/atari.o binaries/sz2_atari.o -b ataritos -e start -o binaries/atari/sz2_hata.tos

./vasmm68k_mot sources/sz2.s -quiet -no-opt -Faout -m68030 -D__ATARI__ -o binaries/sz2_atari.o
./vasmm68k_mot sources/atari.s -quiet -Faout -m68030 -o binaries/atari.o
./vlink binaries/atari.o binaries/sz2_atari.o -b ataritos -e start -o binaries/atari/sz2_dbg.tos

#
# Amiga
#

