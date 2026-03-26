; turn the A20 line on (without it <1 MB RAM wouldn't work)
in al, 0x92
or al, 00000010b
out 0x92, al
; GDT global decriptor table
gdt_start:

gdt_null:
    dq 0x0000000000000000

gdt_code:
    dq 0x00CF9A000000FFFF   ; code segment

gdt_data:
    dq 0x00CF92000000FFFF   ; data segment

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start
; load GDT
lgdt [gdt_descriptor]
; turn on protected mode
mov eax, cr0
or eax, 1
mov cr0, eax
; far jump EXTREMELY IMPORTANT
jmp 08h:protected_mode
; start 32-bit mode
bits 32

protected_mode:

    mov ax, 10h
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax

    mov esp, 0x90000   ; stack

    call kernel_main
