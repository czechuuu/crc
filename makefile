.PHONY: all clean

crc.o: crc.asm
	nasm -f elf64 -w+all -w+error -o $@ $^

crc: crc.o
	ld --fatal-warnings -o $@ $^

read_test.o: read_test.asm
	nasm -f elf64 -w+all -w+error -o $@ $^

read_test: read_test.o
	ld --fatal-warnings -o $@ $^

all: crc

clean:
	rm crc.o crc