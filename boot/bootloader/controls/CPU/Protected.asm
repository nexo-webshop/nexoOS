bits 16
org 0x7C00

start:

    cli                     ; ❗ geen interrupts tijdens switch

; ----------------
; SEGMENTS RESET
; ----------------
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

; ----------------
; A20 LINE ENABLE
; ----------------
    in al, 0x92
    or al, 00000010b
    out 0x92, al

; ----------------
; LOAD GDT
; ----------------
    lgdt [gdt_descriptor]

; ----------------
; ENTER PROTECTED MODE
; ----------------
    mov eax, cr0
    or eax, 1              ; set PE bit
    mov cr0, eax

; FAR JUMP (flush pipeline)
    jmp 0x08:protected_mode

; ================================
; GDT
; ================================
gdt_start:

gdt_null:
    dq 0x0000000000000000

gdt_code:
    dq 0x00CF9A000000FFFF   ; code segment (4GB)

gdt_data:
    dq 0x00CF92000000FFFF   ; data segment (4GB)

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ================================
; 32-BIT MODE
; ================================
bits 32

protected_mode:

; ----------------
; SET SEGMENTS
; ----------------
    mov ax, 0x10            ; data selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

; ----------------
; STACK
; ----------------
    mov esp, 0x90000
    and esp, 0xFFFFFFF0

    cld

; ----------------
; TEST OUTPUT (VGA TEXT MODE)
; ----------------
    mov edi, 0xB8000
    mov eax, 0x07200750     ; 'P' + attrib
    mov [edi], ax

; ----------------
; CALL KERNEL
; ----------------
    call kernel_main

; ----------------
; FAILSAFE
; ----------------
.hang:
    hlt
    jmp .hang

; ================================
; KERNEL
; ================================
kernel_main:

    mov edi, 0xB8002
    mov ax, 0x074D          ; 'M'
    mov [edi], ax

    ret

; ================================
; BOOT SIGNATURE
; ================================
times 510 - ($ - $$) db 0
dw 0xAA55
