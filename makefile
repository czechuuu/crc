.PHONY: all clean

crc.o: crc.asm
	nasm -f elf64 -w+all -w+error -o $@ $^

crc: crc.o
	ld --fatal-warnings -o $@ $^

clean:
	rm crc.o crc