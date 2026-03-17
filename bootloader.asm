; Nexo OS Bootloader v1
; Build: nasm -f bin boot.asm -o boot.bin

[org 0x7C00]

start:
    cli                 ; interrupts uit
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00      ; stack onder bootloader
    sti                 ; interrupts aan

    mov si, message
    call print_string

hang:
    jmp hang

; ========================
; Print functie (BIOS)
; ========================
print_string:
    mov ah, 0x0E        ; teletype output

.next:
    lodsb               ; AL = [SI]
    cmp al, 0
    je .done
    int 0x10
    jmp .next

.done:
    ret

; ========================
; Data
; ========================
message db "Nexo OS start...", 0

; ========================
; Padding + boot signature
; ========================
times 510 - ($ - $$) db 0
dw 0xAA55
