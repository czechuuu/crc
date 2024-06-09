%include "macro_print.asm"

SYS_OPEN equ 2
READ_ONLY equ 0
MODE equ 0

SYS_CLOSE equ 3
SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60
SYS_LSEEK equ 8
LSEEK_CUR equ 1

BUFFER_SIZE equ 8

section .data
    arg1_msg db 'File: ', 0
    arg2_msg db 'Polynomial: ', 0
    error_msg db 'Error', 10, 0
    newline db 10, 0

section .bss
    fd resq 1
    buffer resb BUFFER_SIZE
    buffer_pointer resb 1 ; byte
    data_counter resw 1 ; word - 2 bytes
    data_len resw 1 ; word - 2 bytes
    segment_offset resd 1 ; doubleword - 4 bytes
    

    

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
    call read_data_len 

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

get_next_buffer:
    ; Read from the file
    mov rax, SYS_READ                          ; sys_read
    mov rdi, [fd]                       ; file descriptor
    mov rsi, buffer                     ; buffer to read into
    mov rdx, BUFFER_SIZE                       ; maximum number of bytes to read
    syscall
    ret

; read_segment:
; 	mov word [data_len], word [buffer] 
; 	mov byte [buffer_pointer], 2
; 	mov gowno

; r8 - iterating over curr segment
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
    print "length: ", rax

    xor r8w, r8w ; only operating on lowest 16 bits
.processing_data_loop_condition:
    cmp r8w, word [data_len]
    je .reading_offset
.processing_data_loop_body:
    ; buffer := curent byte
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, buffer ; TODO push from the back 
    mov rdx, 1 ; process only one byte at once - endian order...
    syscall

    ; todo error doesnt stop???
    cmp rax, 0
    jl _error

    ; print buffer
    xor rax, rax
    mov al , byte [buffer]
    print "Read: ", rax

    ; i++ next iteration
    inc r8w
    jmp read_data_len.processing_data_loop_condition
.reading_offset:
    ; TODO optimize syscall args
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, segment_offset
    mov rdx, 4 ; offset is a 32bit U2 number
    syscall 

    cmp rax, 0
    jl _error

    movsxd rsi, dword [segment_offset]
    print "offset: ", rsi

    ; rdx := total length of curr segment
    xor edx, edx ; rdx := 0
    mov dx, word [data_len] ; rdx := data_len
    add rdx, 6 ; rdx += 2 (length) + 4 (offset)
    ;checking if it points to itself
    add rsi, rdx
    cmp rsi, 0
    jne .moving_to_next_segment
    ret ; if equal then we go back to print the result close the file etc.
.moving_to_next_segment:
    mov rax, SYS_LSEEK
    mov rdi, [fd]
    sub rsi, rdx ; rsi := offset
    mov rdx, LSEEK_CUR ; moving relative to current cursor 
    syscall

    print "error: ", rax
    cmp rax, 0
    jl _error

    jmp read_data_len
    

