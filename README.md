# CRC Calculation Program (x86-64 Assembly)

## Overview
This program calculates the cyclic redundancy check (CRC) of a specified file using a given polynomial. Written in x86-64 assembly, the program reads the file in segments for efficiency, applying bitwise operations to compute the CRC value based on a binary polynomial provided by the user.

## Usage
1. **Compile** the program with `make`.
2. **Run** the compiled program with two arguments:
   - The path to the file for CRC calculation.
   - The polynomial as a binary string (e.g., `"1101"` for the polynomial x³ + x² + 1).

### Example
```bash
./crc myfile.txt "1101"
