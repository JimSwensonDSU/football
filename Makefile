NAME=football

all: football

clean:
	rm -rf football football.o

football: football.asm
	nasm -f elf -F dwarf football.asm
	gcc -m32 -o football football.o
