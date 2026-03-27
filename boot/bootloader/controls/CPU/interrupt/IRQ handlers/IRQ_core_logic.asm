irq_handler:

    ; ----------------
    ; TIMER (IRQ0)
    ; ----------------
    cmp dword [esp+32], 32
    jne .check_keyboard

    mov edi, 0xB8002
    mov ax, 0x072E          ; '.'
    mov [edi], ax
    jmp .done

.check_keyboard:

    cmp dword [esp+32], 33
    jne .done

    in al, 0x60

    mov edi, 0xB8004
    mov ah, 0x07
    mov [edi], ax

.done:

    ; ----------------
    ; EOI (SLAVE + MASTER)
    ; ----------------
    mov al, 0x20
    out 0x20, al
    out 0xA0, al

    ret
