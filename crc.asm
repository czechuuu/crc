%include "macro_print.asm"

LAST_BYTE equ -1
SYS_OPEN equ 2
READ_ONLY equ 0
STDOUT equ 1
MODE equ 0

SYS_CLOSE equ 3
SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60
SYS_LSEEK equ 8
LSEEK_CUR equ 1

BUFFER_SIZE equ 8
SHIFT_FROM_THE_YOUNGEST_TO_THE_OLDEST_EIGHT_BITS equ 56

section .data
    arg1_msg db 'File: ', 0
    arg2_msg db 'Polynomial: ', 0
    error_msg db 'Error', 10, 0
    newline db 10, 0

section .bss
    fd resq 1
    buffer resb BUFFER_SIZE
    small_buffer resb 1
    buffer_pointer resb 1 ; byte
    data_counter resw 1 ; word - 2 bytes
    data_len resw 1 ; word - 2 bytes
    segment_offset resd 1 ; doubleword - 4 bytes
    result_length resb 1 ; polylength-1
    bytes_in_buffer resb 1 ; when hits 0 well have the reslt
    poly resq 1
    poly_length resb 1
    print_buffer resb 66
    

    

section .text
    global _start

%macro PRINT_STRING 1
    ; Calculate the length of the string
    mov rsi, %1             ; string pointer
    xor rdx, rdx            ; reset length counter
%%len_calc:
    cmp byte [rsi + rdx], 0 ; check for null terminator
    je %%print               ; if null, we are done
    inc rdx                 ; increment length counter
    jmp %%len_calc           ; repeat
%%print:
    mov rax, 1              ; sys_write
    mov rdi, 1              ; file descriptor (stdout)
    mov rsi, %1             ; string pointer
    syscall                 ; call kernel
%endmacro

_start:
printing_parameters:
    ; Get command line arguments
    mov rdi, [rsp]          ; argc (number of arguments)
    cmp rdi, 3              ; We need exactly 2 arguments, so 3 in total with program name
    jne _error              ; If not, jump to error handler

    ; Print first argument message
    PRINT_STRING arg1_msg

    ; Print first argument
    mov rsi, [rsp + 16]     ; pointer to first argument (argv[1])
    call print_string       ; print the first argument

    ; Print newline
    PRINT_STRING newline

    ; Print second argument message
    PRINT_STRING arg2_msg

    ; Print second argument
    mov rsi, [rsp + 24]     ; pointer to second argument (argv[2])
    call print_string       ; print the second argument

    PRINT_STRING newline

    ;mov rdx, [rsp + 24]
    call parse_poly
    ;mov rax, [poly]
    ;print "poly parse: ", rax

    ; Print newline
    PRINT_STRING newline

opening_file:
    mov rax, SYS_OPEN                         ; sys_open
    mov rdi, [rsp + 16]             ; Pointer to file name
    mov rsi, READ_ONLY                        ; Flags: O_RDONLY (0)
    mov rdx, MODE                          ; Mode (ignored because we are not creating a file)
    syscall

    cmp rax, 0
    jl _error                      ; If rax < 0, jump to error handling

    ; Store the file descriptor
    mov [fd], rax

processing_file:

	; only ret here once its over
    ; call fetching_test
    ;mov qword [poly], 0b1
    ;shl qword [poly], 63
    ;mov qword [poly], 0b11
    ;shl qword [poly], 61 ; correctry came out as 4 = 0b0100
    ; mov qword [poly], 0b11010101
    ;shl qword [poly], 56 ; correctly passes with 57 = 0101 0111
    mov rax, [poly]
    print "poly: ", rax
    call filling_initial_buffer
    print "brat: ", r9
    call print_poly_result

closing_file:
    ; Close the file
    mov rax, SYS_CLOSE                          ; sys_close
    mov rdi, [fd]                       ; file descriptor
    syscall

    ; Exit the program
    mov rax, SYS_EXIT                         ; sys_exit
    xor rdi, rdi                        ; exit code 0
    syscall

_error:
    ; Handle error (print error message and exit with code 1)
    PRINT_STRING error_msg

    mov rax, SYS_EXIT             ; sys_exit
    mov rdi, 1              ; exit code 1
    syscall                 ; call kernel

; MESSES WITH ALL CALLER SAVED REGS
; Prints a string (null terminated) 
; rsi - pointer to the string
print_string:
    mov rdx, 0              ; Reset length counter
.count:
    cmp byte [rsi + rdx], 0 ; Compare current byte to NULL
    je .done                ; If NULL, we are done
    inc rdx                 ; Increment length counter
    jmp .count              ; Repeat
.done:
    mov rax, SYS_WRITE              ; sys_write
    mov rdi, 1              ; file descriptor (stdout)
    syscall                 ; call kernel
    ret                     ; Return from function


; reads following two bytes and saves them to data_len
read_data_len:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, data_len
    mov rdx, 2 ; length is a word - 2 bytes
    syscall
    ; TODO add checking for fails
    ; now in word [data_len] we have the number of bytes in curr segment

    cmp rax, 0
    jl _error

    xor rax, rax
    mov ax, word [data_len]
    cmp ax, 0
    je reading_offset
    ; print "length: ", rax

    xor eax, eax
    mov word [data_counter], ax ; bytes read in curr segment - 0

    cmp word [data_len], 0
    jne .end
    mov rax, LAST_BYTE ; if no bytes in current segment we want to return last byte

.end:
    ret ; we return 0 because there are bytes in current segment

; fetches next byte to a small buffer
; if it was the last byte then rax is set to -1 = LAST_BYTE
; otherwise to 0
; TODO change logic to allow zero length segments
; read data len should set LAST_BYTE if necessary
; and condition should be moved to the top
fetch_next_byte:
    ; small_buffer := curent byte
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, small_buffer ; TODO push from the back 
    mov rdx, 1 ; process only one byte at once - endian order...
    syscall

    cmp rax, 0
    jl _error

    ; print buffer
    xor rax, rax
    mov al , byte [small_buffer]
    ; print "Read: ", rax

    mov ax, word [data_counter]
    inc ax
    mov word [data_counter], ax
    cmp ax, word [data_len]
    je reading_offset
    xor eax, eax ; there is more data in the current segment
    ret ; so we return 0

reading_offset:
    ; TODO optimize syscall args
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, segment_offset
    mov rdx, 4 ; offset is a 32bit U2 number
    syscall 

    cmp rax, 0
    jl _error

    movsxd rsi, dword [segment_offset]
    ; print "offset: ", rsi

    ; rdx := total length of curr segment
    xor edx, edx ; rdx := 0
    mov dx, word [data_len] ; rdx := data_len
    add rdx, 6 ; rdx += 2 (length) + 4 (offset)
    ;checking if it points to itself
    add rsi, rdx
    cmp rsi, 0
    jne .moving_to_next_segment
    mov rax, LAST_BYTE
    ret ; return LAST_BYTE
.moving_to_next_segment:
    mov rax, SYS_LSEEK
    mov rdi, [fd]
    sub rsi, rdx ; rsi := offset
    mov rdx, LSEEK_CUR ; moving relative to current cursor 
    syscall

    cmp rax, 0
    jl _error

    jmp read_data_len
    

fetching_test:
    call read_data_len
.crawling_condition:
    cmp rax, LAST_BYTE
    je .after_file
.crawling_loop_body:
    call fetch_next_byte
    mov dl, byte [small_buffer]
    print "read: ", rdx
    jmp .crawling_condition
.after_file:
    ret

; RDX MODIFIED!!!!!!!!
filling_initial_buffer:
    call read_data_len ; zeros rax
    ; r8 <- [7, 0]
    ; iterating while has next byte and space in (big) buffer
    mov r8, 7
.condition:
    cmp r8, 0
    jl .after_loop
    cmp rax, LAST_BYTE
    je .after_loop
.loop_body:
    call fetch_next_byte ; rax has to be unchanged until the xor loop
    mov dl, byte [small_buffer] ; RDX!!
    mov byte [buffer + r8], dl
    inc byte [bytes_in_buffer] ; adding a byte
    dec r8
    jmp .condition
.after_loop:
    jmp xoring_loop

; rbx!!!
xoring_loop:
    mov r9, qword [buffer]
.loop_unprocessed_bits_condition:
    cmp byte [bytes_in_buffer], 0
    je .after_loop
.loop_outer_body:
    dec byte [bytes_in_buffer]
    xor ebx, ebx ; next byte 0 by default
    cmp rax, LAST_BYTE  ; make sure rax unchanged or move regs
    je .inner_loop_setup ; if no more data then we leave zero
    call fetch_next_byte
    mov bl, byte [small_buffer]
    shl rbx, SHIFT_FROM_THE_YOUNGEST_TO_THE_OLDEST_EIGHT_BITS ; bytes from small buffer now are the oldest in rbx
    inc byte [bytes_in_buffer]
.inner_loop_setup:
    mov r8, 0
.inner_loop_condition:
    cmp r8, 8
    je .loop_unprocessed_bits_condition
.inner_loop_body:
    mov rcx, rbx
    shl rbx, 1 ; ugly
    shld r9, rcx, 1 ; we shift off the first bit and on the last
    ; now if the carry flag is set we popped a 1 from the left
    ; it corresponds to the implied highest degree of poly so we xor
    ; otherwise we skip iteration
    jc .can_proceed_with_xor
    jmp .inner_loop_lower_body
.can_proceed_with_xor:
    xor r9, qword [poly]
.inner_loop_lower_body:
    ;print "content of r9: ", r9
    inc r8
    jmp .inner_loop_condition
.after_loop:
    print "result in hex: ", r9
    ret


parse_poly:
    mov rdx, [rsp + 32]               ; rcx = pointer to the string
    mov al, [rdx]              ; Load first character of the string into al
    test al, al                ; Check if it's the null terminator
    jz _error                  ; If it is, jump to _error

    ; Find the length of the string
    xor ecx, ecx
find_length:
    mov al, [rdx + rcx]        ; Load current character into al
    test al, al                ; Check if it's the null terminator
    jz process_string          ; If it is, start processing the string
    inc rcx                    ; Increment counter
    jmp find_length            ; Loop back to find length

process_string:
    mov [poly_length], cl
    dec rcx                    ; rdi now points to the last character of the string

process_char:
    mov al, [rdx + rcx]        ; Load the current character into al
    cmp al, '0'                ; Compare the character with '0'
    je store_zero_bit          ; If it's '0', store zero bit

    cmp al, '1'                ; Compare the character with '1'
    je store_one_bit           ; If it's '1', store one bit

    jmp _error                 ; If it's neither '0' nor '1', jump to _error


store_one_bit:
    ; Shift poly left by 1 bit and set the LSB
    mov rax, 1
    shl rax, 63
    shr rax, cl
    or qword [poly], rax
    jmp check_done

store_zero_bit:
    ; do nothign

check_done:
    dec rcx                    ; Move to the previous character
    js done                    ; If we've processed all characters, we're done
    jmp process_char           ; Loop back to process the next character

done: 
    ret
    ; TODO: parse polynomial
    ; TODO: print result
    ; allowing empty segments by checking directly after reading lenght - seems ok


; assumes result in r9 
; will go through the input string and now to end from there
print_poly_result:
    mov rcx, [poly_length]                   ; rcx = poly_length (number of bits to write)
    lea rsi, [buffer]              ; rsi = address of buffer
    xor rdi, rdi                   ; rdi = index in buffer

write_bits:
    ; Get the most significant bit of r9
    mov rbx, r9
    shr rbx, 63                    ; Shift right to get the most significant bit
    add rbx, '0'                   ; Convert bit to ASCII ('0' or '1')
    mov byte [rsi + rdi], bl            ; Store the character in the buffer
    inc rdi                        ; Move to the next buffer position

    ; Shift r9 left by 1 to process the next bit
    shl r9, 1

    ; Decrement the bit counter
    dec rcx
    jnz write_bits                 ; Repeat until all bits are processed

    mov byte [rsi + rdi], 10
    inc rdi
    mov byte [rsi + rdi], 0


    ; Write the buffer to stdout
    mov rax, SYS_WRITE                     ; syscall: write
    mov rdx, rdi                   ; number of bytes to write
    mov rdi, STDOUT                     ; file descriptor: stdout
    lea rsi, [buffer]              ; buffer to write
    syscall
    ret
