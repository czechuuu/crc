SYS_OPEN equ 2
READ_ONLY equ 0
MODE equ 0

SYS_CLOSE equ 3
SYS_READ equ 0
SYS_WRITE equ 1
SYS_EXIT equ 60

BUFFER_SIZE equ 1024

section .data
    arg1_msg db 'File: ', 0
    arg2_msg db 'Polynomial: ', 0
    error_msg db 'Error', 10, 0
    newline db 10, 0

section .bss
    fd resq 1
    buffer resb BUFFER_SIZE

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
    ; Read from the file
    mov rax, SYS_READ                          ; sys_read
    mov rdi, [fd]                       ; file descriptor
    mov rsi, buffer                     ; buffer to read into
    mov rdx, BUFFER_SIZE                       ; maximum number of bytes to read
    syscall

    ; Print the content of the file
    mov rsi, buffer                     ; pointer to input buffer
    call print_string                   ; print the file content

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
