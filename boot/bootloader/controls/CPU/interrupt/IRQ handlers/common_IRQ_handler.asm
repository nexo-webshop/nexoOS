irq_common:

    pusha

    mov ax, 0x10
    mov ds, ax
    mov es, ax

    call irq_handler

    popa

    iret
