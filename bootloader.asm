; Nexo OS Bootloader v1.1 (safe edition) - FIXED
; ===============================================
; x86 Real Mode 16-bit bootloader
; Loads at 0x0000:0x7C00

[org 0x7C00]
[bits 16]

start:
    cli                     ; disable interrupts (FIRST!)
    
    ; ========================
    ; Register initialization
    ; ========================
    xor ax, ax              ; AX = 0
    mov ds, ax              ; DS = 0 (data segment)
    mov es, ax              ; ES = 0 (extra segment)
    
    ; ========================
    ; Stack setup (BEFORE sti!)
    ; ========================
    ; CRITICAL: Set up stack BEFORE enabling interrupts
    ; Otherwise interrupt handler has nowhere to push return address
    mov ss, ax              ; SS = 0 (stack segment)
    mov sp, 0x7C00          ; SP = 0x7C00 (grows downward, safe zone)
    
    ; ========================
    ; Flags & interrupt setup
    ; ========================
    cld                     ; clear Direction Flag (string ops go forward)
    sti                     ; enable interrupts (NOW it's safe!)
    
    ; ========================
    ; Print startup message
    ; ========================
    mov si, message         ; SI = offset of message string
    call print_string       ; print it
    
    ; ========================
    ; Idle loop (wait for system)
    ; ========================
hang:
    cli                     ; disable interrupts
    hlt                     ; halt CPU (low power)
    jmp hang                ; infinite loop (shouldn't reach, but safety)

; ========================
; print_string: Print null-terminated string
; ========================
; Input:  DS:SI -> string
; Output: none
; Uses:   AL, AH, SI
print_string:
    push ax                 ; save AX (good practice)
    
.next_char:
    lodsb                   ; load AL = [DS:SI], SI++  (atomic instruction)
    test al, al             ; check if AL == 0 (null terminator)
    jz .done                ; if zero, we're done
    
    mov ah, 0x0E            ; BIOS function: write character in TTY mode
    mov bx, 0x0007          ; BH = page 0, BL = color (white on black)
    int 0x10                ; BIOS video interrupt
    
    jmp .next_char          ; continue to next character
    
.done:
    pop ax                  ; restore AX
    ret                     ; return to caller

; ========================
; Data section
; ========================
message db "Nexo OS secure boot...", 0x0D, 0x0A, "Ready.", 0

; ========================
; Padding and boot signature
; ========================
; Bootloader must be exactly 512 bytes with signature at bytes 510-511
times 510 - ($ - $$) db 0  ; fill remaining space with zeros
dw 0xAA55                   ; x86 boot signature (little-endian: 0x55AA)
