; ================================
; 16-bit REAL MODE
; ================================
bits 16

start:

    cli                     ; ❗ interrupts UIT (cruciaal!)

; ----------------
; A20 LINE ENABLE (FAST + VERIFY)
; ----------------
    in al, 0x92
    or al, 00000010b
    out 0x92, al

; (optioneel: check A20 hier voor robustness)

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

; FAR JUMP (pipeline flush)
    jmp 0x08:protected_mode

; ================================
; GDT
; ================================
gdt_start:

gdt_null:
    dq 0x0000000000000000

gdt_code:
    dq 0x00CF9A000000FFFF   ; base=0, limit=4GB, code

gdt_data:
    dq 0x00CF92000000FFFF   ; base=0, limit=4GB, data

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ================================
; 32-bit PROTECTED MODE
; ================================
bits 32

protected_mode:

; ----------------
; SET SEGMENTS
; ----------------
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

; ----------------
; STACK INIT (aligned)
; ----------------
    mov esp, 0x90000
    and esp, 0xFFFFFFF0     ; 16-byte alignment (future-proof)

; ----------------
; CLEAR DIRECTION FLAG
; ----------------
    cld

; ----------------
; CALL KERNEL
; ----------------
    call kernel_main

; ----------------
; FAILSAFE LOOP
; ----------------
.hang:
    hlt
    jmp .hang
