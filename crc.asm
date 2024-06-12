;%include "macro_print.asm"
; remove macro !!!!

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
NEWLINE equ 10

; i chose 4kB since thats the standard frame size and seems most logical
; but on the tests i conducted (somewhat poorly but nonetheless)
; it seems like it doesnt make a difference past 512 B
; but i don't have access to any truly massive tests
; and it doesn't hurt to assume that on them the difference would be noticeable
; (test times are all ao12)
; +----------+------------+------------+-------------+
; | Size (B) | Big 1 (ms) | Big 2 (ms) | Medium (ms) |
; +----------+------------+------------+-------------+
; |     4096 |        249 |        254 |          48 |
; |     2048 |        250 |        247 |          49 |
; |     1024 |        242 |        258 |          51 |
; |      512 |        253 |        256 |          48 |
; |      256 |        260 |        263 |          55 |
; |      128 |        279 |        281 |          52 |
; |       64 |        328 |        316 |          55 |
; |       32 |        406 |        397 |          66 |
; |       16 |        603 |        605 |          76 |
; |        8 |       1170 |       1168 |         143 |
; +----------+------------+------------+-------------+
BIG_BUFFER_SIZE equ 4096


section .bss
    align 16
    big_buffer resb 4096
    big_buffer_ptr resq 1
    big_buffer_actual_size resq 1
    fd resq 1
    buffer resb BUFFER_SIZE ; used to flip a number due to the endian order
    print_buffer resb 66
    poly_length resb 1
    ; Somewhat constant registers: 
    ; (that is storing only one thing)
    poly resq 1
    data_counter resw 1 ; word - 2 bytes
    data_len resw 1 ; word - 2 bytes
    small_buffer resb 1 ; can be eliminated
    segment_offset resd 1 ; doubleword - 4 bytes
    bytes_in_buffer resb 1 ; when hits 0 well have the reslt
    

section .text
    global _start


_start:
processing_parameters:
    mov rdi, [rsp]          ; argc (number of arguments)
    cmp rdi, 3              ; 2 args + 1 program name
    jne _not_closing_error              

    call parse_poly
opening_file:
    mov rax, SYS_OPEN
    mov rdi, [rsp + 16] ; file path
    mov rsi, READ_ONLY                        
    mov rdx, MODE ; ignored
    syscall

    cmp rax, 0
    jl _not_closing_error

    mov [fd], rax

processing_file:
    call filling_initial_buffer
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
    mov rax, SYS_CLOSE
    mov rdi, [fd]
    syscall
_not_closing_error:
    ; Handle error (print error message and exit with code 1)
    mov rax, SYS_EXIT             ; sys_exit
    mov rdi, 1              ; exit code 1
    syscall                 ; call kernel


; reads following two bytes and saves them to data_len
read_data_len:
    call update_big_buffer ; we force update big buffer
    ; maybe change it in the future for better performance
    lea rax, [big_buffer]
    add rax, [big_buffer_ptr] ; currently 0 but maybe we wont force reload in the future
    mov ax, word [rax]
    mov word [data_len], ax
    add qword [big_buffer_ptr], 2

    ; if the segment has 0 data we immedietaly seek the next one
    xor eax, eax
    mov ax, word [data_len]
    cmp ax, 0
    je reading_offset

    xor eax, eax
    mov word [data_counter], ax ; bytes read in curr segment - 0

    ret ; we return 0 because there are bytes in current segment

; fetches next byte to a small buffer
; if it was the last byte then rax is set to -1 = LAST_BYTE
; otherwise to 0
fetch_next_byte:
    call update_big_buffer_if_necessary
    lea rax, [big_buffer] ; rax := &big_buffer
    add rax, [big_buffer_ptr] ; rax := &big_buffer + ptr
    mov al, [rax] ; al := *(big_buffer+ptr)
    mov byte [small_buffer], al
    inc qword [big_buffer_ptr]

    mov ax, word [data_counter]
    inc ax
    mov word [data_counter], ax ; data read in current segment increases
    cmp ax, word [data_len]
    je reading_offset ; if read all data in current segment proceed to the next
    xor eax, eax ; otherwise there is more data in the current segment
    ret ; so we return 0

reading_offset:
    call update_big_buffer_if_necessary
    lea rax, [big_buffer] ; rax := &big_buffer
    add rax, [big_buffer_ptr] ; rax := &big_buffer + ptr
    mov eax, [rax] ; ax := *(big_buffer+ptr)
    mov dword [segment_offset], eax
    add qword [big_buffer_ptr], 4

    movsxd rsi, dword [segment_offset]

    ; rdx := total length of curr segment
    xor edx, edx ; rdx := 0
    mov dx, word [data_len] ; rdx := data_len
    add rdx, 6 ; rdx += 2 (length) + 4 (offset)
    ;checking if it points to itself
    add rsi, rdx
    cmp rsi, 0
    jne .moving_to_next_segment
    mov rax, LAST_BYTE ; no more data
    ret ; return LAST_BYTE
.moving_to_next_segment:
    ; we need to correct rsi to have the right offset
    sub rsi, rdx ; rsi := offset read (revert +6 change)
    mov rax, [big_buffer_actual_size] ; rax := amount of bytes weve read into big buffer
    sub rax, [big_buffer_ptr]  ; but havent read
    sub rsi, rax ; so we need to move that much more to the beggining of the file
    

    mov rax, SYS_LSEEK
    mov rdi, [fd]
    ; rsi set complicated so above
    mov rdx, LSEEK_CUR ; moving relative to current cursor 
    syscall

    cmp rax, 0
    jl _error ;  offset can be 0 so only negative is an error

    jmp read_data_len
    


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
    inc byte [bytes_in_buffer] ; new byte in buffer
    dec r8
    jmp .condition
.after_loop:
    jmp xoring_loop

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
    inc r8
    jmp .inner_loop_condition
.after_loop:
    ret


parse_poly:
    mov rdx, [rsp + 32] ; polynomial string ptr
    mov al, [rdx]              
    test al, al ; if first character null raise error
    jz _not_closing_error

    ; find the length of the string
    xor ecx, ecx
.find_length:
    mov al, [rdx + rcx]        
    test al, al                
    jz .process_string ; while not null
    inc rcx           ; i++
    jmp .find_length          
.process_string:
    mov byte [poly_length], cl
    cmp rcx, 64
    ja _not_closing_error ; polynomial too long
    dec rcx ; rcx now points to the last character of the string
.process_char:
    mov al, [rdx + rcx]        
    cmp al, '0'                
    je .store_zero_bit          

    cmp al, '1'
    je .store_one_bit

    jmp _not_closing_error ; wrong character
.store_one_bit:
    mov rax, 1
    shl rax, 63
    shr rax, cl ; turns on the rcx-th (cl-th since its <=64) bit
    or qword [poly], rax
    jmp .check_done
.store_zero_bit:
    ; do nothing
.check_done:
    dec rcx
    js .done ; it was the last char
    jmp .process_char ; store prev char
.done: 
    ret
    ; TODO: parse polynomial
    ; TODO: print result
    ; allowing empty segments by checking directly after reading lenght - seems ok


; assumes result in r9 
; will go through the input string and now to end from there
print_poly_result:
    xor ecx, ecx 
    mov cl, byte[poly_length] ; rcx = poly_length (number of bits to write)
    lea rsi, [print_buffer] ; rsi = address of buffer for printing result
    xor rdi, rdi ;  rdi = index in buffer

write_bits:
    mov rbx, r9
    shr rbx, 63                    ; rbx := oldest bit in r9
    add rbx, '0'                   ; convert bit to ASCII ('0' or '1')
    mov byte [rsi + rdi], bl       ; store char
    inc rdi                      

    ; Shift r9 left by 1 to process the next bit
    shl r9, 1 ; first bit stored so we pretend the polynomial is shorter
    dec rcx ; and repeat
    jnz write_bits

    mov byte [rsi + rdi], NEWLINE 
    inc rdi
    ; following byte 0 by default

    mov rax, SYS_WRITE                     
    mov rdx, rdi ; unusual order due to somwhat poor choice of registers...
    mov rdi, STDOUT                     
    lea rsi, [print_buffer]              
    syscall
    ret

update_big_buffer_if_necessary:
    mov rax, [big_buffer_ptr]
    add rax, 3 ; we want to make sure that always there are at least 4 bytes to read
    cmp rax, [big_buffer_actual_size] ; so ptr+3 < size has to be true
    jae update_big_buffer_setting_cursor ; unsigned compare
    ret ; we have at least 4 more bytes buffered
update_big_buffer_setting_cursor:
    mov rsi, [big_buffer_actual_size]
    sub rsi, [big_buffer_ptr]
    neg rsi

    mov rax, SYS_LSEEK
    mov rdi, [fd]
    ; rsi set above
    mov rdx, LSEEK_CUR
    syscall

update_big_buffer:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, big_buffer
    mov rdx, BIG_BUFFER_SIZE
    syscall 

    cmp rax, 0
    jle _error

    ; syscall returns number of bytes read
    ; can be less than what we asked for
    mov [big_buffer_actual_size], rax
    mov qword [big_buffer_ptr], 0
    ret

; TODO error check jle
; todo size of buffer
; remove macro !!!