bits 16
org 0x1000

start:
    mov ah, 0x0E
    mov al, 'K'
    int 0x10

hang:
    jmp hang

; if you see an 'K': kernel works!
