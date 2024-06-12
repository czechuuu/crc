; CRC - 3 projekt zaliczeniowy AKSO
; MIMUW 23/24L
;
; Program oblicza cykliczny kod nadmiarowy podanego pliku 
; przy podanym wielomianie (w ktorym najwyzszy stopien nie jest implikowany)
; Przepraszam, ze kod nie nalezy do najpiekniejszych ale mamy rownoczesnie
; ten projekt, projekt z PO, kolokwium z MD i nauke do egzaminu z MD 
;
; Bartosz Czechowski 
;

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
; |    65536 |        248 |        249 |          43 |
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
    align 16 ; can speed up access, i didnt measure any difference though
    big_buffer resb BIG_BUFFER_SIZE
    fd resq 1 ; file descriptor
    buffer resb BUFFER_SIZE ; used to flip a number due to the endian order
    print_buffer resb 66 ; used for printing out result
    poly_length resb 1 ; length of the result polynomial
    segment_offset resd 1 ; doubleword - 4 bytes
    bytes_in_buffer resb 1 ; when hits 0 well have the reslt
    ; Somewhat constant registers: 
    ; (that is storing only one thing)
    ; (can be treated as variables)
    ; r15:  poly - quadword
    ; r14w: data_counter resw - word
    ; r13w: data_len resw 1 ; word - 2 bytes
    ; r12b: small_buffer stores the last fetched byte (to avoid awkward index + 1 buffer accesses)
    ; r11:  big_buffer_ptr index of the next unread byte in buffer
    ; r10:  big_buffer_actual_size resq 1 ; how much data was loaded into buffer
    ; TODO make sure all are properly initialazied 0 at start
    

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
    mov rax, SYS_EXIT             ; sys_exit
    mov rdi, 1              ; exit code 1
    syscall                 ; call kernel


; reads following two bytes and saves them to data_len
read_data_len:
    call update_big_buffer ; we force update big buffer
    ; maybe change it in the future for better performance
    lea rax, [big_buffer]
    mov r13w, word [rax] ; r13w - data_len
    add r11, 2 ; r11 - big_buffer_ptr

    ; if the segment has 0 data we immediately seek the next one
    cmp r13w, 0 ; r13w - data_len
    je reading_offset

    xor eax, eax
    ; r14w - data_counter
    mov r14w, ax ; bytes read in curr segment - 0

    ret ; we return 0 because there are bytes in current segment

; fetches next byte to a small buffer
; if it was the last byte then rax is set to -1 = LAST_BYTE
; otherwise to 0
fetch_next_byte:
    call update_big_buffer_if_necessary
    lea rax, [big_buffer] ; rax := &big_buffer
    add rax, r11 ; rax := &big_buffer + big_buffer_ptr
    mov r12b, [rax] ; small_buffer := *(big_buffer+ptr)
    inc r11 ; big_buffer_ptr++

    inc r14w ; r14w - data_counter
    cmp r14w, r13w ; r13w - data_len
    je reading_offset ; if read all data in current segment proceed to the next
    xor eax, eax ; otherwise there is more data in the current segment
    ret ; so we return 0

reading_offset:
    call update_big_buffer_if_necessary
    lea rax, [big_buffer] ; rax := &big_buffer
    add rax, r11 ; rax := &big_buffer + big_buffer_ptr
    mov eax, [rax] ; ax := *(big_buffer+ptr)
    mov dword [segment_offset], eax
    add r11, 4 ; big_buffer_ptr

    movsxd rsi, dword [segment_offset]

    ; rdx will be total length of curr segment
    xor edx, edx ; rdx := 0
    mov dx, r13w ; rdx := data_len
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
    mov rax, r10 ; rax := amount of bytes weve loaded into big buffer
    sub rax, r11  ; but havent read
    ; rax := big_buffer_actual_size - big_buffer_ptr
    sub rsi, rax ; so we need to move that much more to the beggining of the file
    

    mov rax, SYS_LSEEK
    mov rdi, [fd]
    ; rsi set complicated so above
    mov rdx, LSEEK_CUR ; moving relative to current cursor 
    syscall

    cmp rax, 0
    jl _error ;  offset can be 0 so only negative is an error

    jmp read_data_len
    

; setups data for xoring
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
    mov byte [buffer + r8], r12b ; b[i] := small_buffer
    inc byte [bytes_in_buffer] ; new byte in buffer
    dec r8
    jmp .condition
.after_loop:
    jmp xoring_loop

; Registers:
; r9        - used to perform the calculations
; r8        - loop iterator [0, 7]
; rbx (bl)  - used to store the next byte not stored in r9
; rcx       - used to store rbx before shifting (why doesnt shld shift both?)
; rax       - stores whether there are any more bytes
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
    mov bl, r12b
    shl rbx, SHIFT_FROM_THE_YOUNGEST_TO_THE_OLDEST_EIGHT_BITS ; bytes from small buffer now are the oldest in rbx
    inc byte [bytes_in_buffer]
.inner_loop_setup:
    mov r8, 0
.inner_loop_condition:
    cmp r8, 8
    je .loop_unprocessed_bits_condition
.inner_loop_body:
    mov rcx, rbx ; copy rbx
    shl rbx, 1 ; and shift it
    shld r9, rcx, 1 ; we shift off the first bit and on the last
    ; now if the carry flag is set we popped a 1 from the left
    ; it corresponds to the implied highest degree of poly so we xor
    ; otherwise we skip iteration
    jc .can_proceed_with_xor
    jmp .inner_loop_lower_body
.can_proceed_with_xor:
    xor r9, r15 ; r15 = poly
.inner_loop_lower_body:
    inc r8
    jmp .inner_loop_condition
.after_loop:
    ret


; Registers:
; rax (al)  - checking current char
; rdx       - pointer to the polynomial string
; rcx       - loop iterator (and str_len)
parse_poly:
    xor r15, r15 ; poly = 0 by default
    mov rdx, [rsp + 32] ; polynomial string ptr
    mov al, [rdx]  ; str[0]
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
    or r15, rax ; r15 = poly
    jmp .check_done
.store_zero_bit:
    ; do nothing
.check_done:
    dec rcx
    js .done ; it was the last char
    jmp .process_char ; store prev char
.done: 
    ret


; Registers:
; rcx (cl)  - result polynomial length
; rsi       - pointer to result string
; rdi       - iterator for string char loop
; rbx       - used for processing current char
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
    mov rdx, rdi ; unusual order due to somewhat poor choice of registers...
    mov rdi, STDOUT                     
    lea rsi, [print_buffer]              
    syscall
    ret

; checks if there if enough data buffered 
; if not then request next batch by sys_read
update_big_buffer_if_necessary:
    mov rax, r11 ; r11 - big_buffer_ptr
    add rax, 3 ; we want to make sure that always there are at least 4 bytes to read
    cmp rax, r10 ; so big_buffer_actual_size+3 < size has to be true
    jae update_big_buffer_setting_cursor ; unsigned compare
    ret ; we have at least 4 more bytes buffered

; reads next batch, but shifting the cursor first
; so it begins with the unread bytes
update_big_buffer_setting_cursor:
    mov rsi, r10 ; = big_buffer_size
    sub rsi, r11 ; - big_buffer_ptr
    neg rsi

    mov rax, SYS_LSEEK
    mov rdi, [fd]
    ; rsi set above
    mov rdx, LSEEK_CUR
    syscall

; loads new data into buffer
update_big_buffer:
    mov rdx, BIG_BUFFER_SIZE
    cmp dx, r13w ; r13w - data_len
    jbe .reading_data
    xor edx, edx ; if data_len < buffer size
    mov dx, r13w ; well only fill with data_len + 4
    add rdx, 4 ; (make sure always at least 4 bytes read to not mess up offset reading)
    ; if this was called in read_data_len then we dont know the length of current segment yet
    ; but we can assume they are roughly the same size and if they arent
    ; it will quickly fix itself with the second request for data in the same segment
.reading_data:
    mov rax, SYS_READ
    mov rdi, [fd]
    mov rsi, big_buffer
    ; rdx amount set above
    syscall 

    cmp rax, 0
    jle _error

    ; syscall returns number of bytes read
    ; can be less than what we asked for
    mov r10, rax ; big_buffer_size = rax
    mov r11, 0 ; big_buffer_ptr = 0
    ret