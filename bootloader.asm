; NexoOS Minimal Bootloader
; 512 bytes, moet exact op een floppy/ISO gezet worden

BITS 16          ; 16-bit real mode
ORG 0x7C00       ; BIOS laadt bootsector hier

start:
    ; Maak het scherm leeg
    mov ah, 0x0
    mov al, 0x3    ; text mode 80x25
    int 0x10

    ; Schrijf boodschap op het scherm
    mov si, msg
print_loop:
    lodsb          ; laad byte van SI naar AL
    cmp al, 0
    je done
    mov ah, 0x0E   ; teletype output
    int 0x10
    jmp print_loop

done:
    cli            ; disable interrupts
    hlt            ; stop CPU hier

msg db "Welkom bij NexoOS!", 0

; Vul tot 512 bytes
times 510-($-$$) db 0
dw 0xAA55        ; Bootsector signature
