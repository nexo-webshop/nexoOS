; Nexo OS Bootloader v1.1 (safe edition)

[org 0x7C00]

start:
    cli                     ; interrupts uit

    xor ax, ax
    mov ds, ax
    mov es, ax

    ; veilige stack setup
    mov ss, ax
    mov sp, 0x9000          ; ver weg van bootloader

    cld                     ; Direction Flag = forward

    sti                     ; interrupts weer aan

    mov si, message
    call print_string

hang:
    cli
    hlt
    jmp hang

; ========================
; Print functie (veilig)
; ========================
print_string:
.next:
    mov al, [si]            ; GEEN lodsb (controle)
    inc si
    test al, al
    jz .done

    mov ah, 0x0E
    int 0x10
    jmp .next

.done:
    ret

; ========================
; Data
; ========================
message db "Nexo OS secure boot...", 0

; ========================
; Boot sector padding
; ========================
times 510 - ($ - $$) db 0
dw 0xAA55
