isr_common:

    pusha                   ; alle registers opslaan

    mov ax, 0x10
    mov ds, ax
    mov es, ax

    ; hier kun je later C handlers callen
    call isr_handler

    popa
    add esp, 8              ; error code + interrupt number weg

    iret
