section .data
    filename db 'test.txt', 0         ; File name with null terminator
    open_error db 'Error opening file.', 10, 0   ; Error message with newline

section .bss
    fd resq 1                           ; Reserve space for one quadword to store the file descriptor
    buffer resb 1024                    ; Reserve space for a buffer to store file content

section .text
    global _start

_start:
    ; Open the file
    mov rax, 2                          ; sys_open
    mov rdi, filename                   ; Pointer to file name
    mov rsi, 0                          ; Flags: O_RDONLY (0)
    mov rdx, 0                          ; Mode (ignored because we are not creating a file)
    syscall
    ; Check if the file was opened successfully
    cmp rax, 0
    jl .open_error                      ; If rax < 0, jump to error handling

    ; Store the file descriptor
    mov [fd], rax

    ; Read from the file
    mov rax, 0                          ; sys_read
    mov rdi, [fd]                       ; file descriptor
    mov rsi, buffer                     ; buffer to read into
    mov rdx, 1024                       ; maximum number of bytes to read
    syscall

    ; Print the content of the file
    mov rsi, buffer                     ; pointer to input buffer
    call print_string                   ; print the file content

    ; Close the file
    mov rax, 3                          ; sys_close
    mov rdi, [fd]                       ; file descriptor
    syscall

    ; Exit the program
    mov rax, 60                         ; sys_exit
    xor rdi, rdi                        ; exit code 0
    syscall

.open_error:
    ; Print error message
    mov rsi, open_error                 ; pointer to error message
    call print_string                   ; print the error message

    ; Exit with error code 1
    mov rax, 60                         ; sys_exit
    mov rdi, 1                          ; exit code 1
    syscall

print_string:
    push rdx                            ; Save rdx
    mov rdx, 0                          ; Reset length counter
.count:
    cmp byte [rsi + rdx], 0            ; Compare current byte to NULL
    je .done                            ; If NULL, we are done
    inc rdx                             ; Increment length counter
    jmp .count                          ; Repeat
.done:
    mov rax, 1                          ; sys_write
    mov rdi, 1                          ; file descriptor (stdout)
    syscall                             ; call kernel
    pop rdx                             ; Restore rdx
    ret                                 ; Return from function
