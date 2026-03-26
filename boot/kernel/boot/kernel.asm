kernel_main:
    mov byte [0xB8000], 'N'
    mov byte [0xB8001], 0x07

hang:
    jmp hang

; if you see an 'N': kernel works!
