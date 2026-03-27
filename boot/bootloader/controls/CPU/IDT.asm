bits 32

; ================================
; IDT STRUCTURE
; ================================
idt_start:

times 256 dq 0        ; 256 entries (8 bytes per entry)

idt_end:

idt_descriptor:
    dw idt_end - idt_start - 1
    dd idt_start

; ================================
; IDT SET ENTRY MACRO
; ================================
%macro IDT_SET 3
    mov eax, %1
    mov word [idt_start + %2*8 + 0], ax
    mov word [idt_start + %2*8 + 2], 0x08       ; code segment
    mov byte [idt_start + %2*8 + 4], 0
    mov byte [idt_start + %2*8 + 5], %3         ; flags
    shr eax, 16
    mov word [idt_start + %2*8 + 6], ax
%endmacro

; ================================
; INIT IDT
; ================================
idt_init:

    ; ----------------
    ; PIC REMAP (CRUCIAAL!)
    ; ----------------
    mov al, 0x11
    out 0x20, al
    out 0xA0, al

    mov al, 0x20        ; master offset (IRQ0 → INT 32)
    out 0x21, al
    mov al, 0x28        ; slave offset (IRQ8 → INT 40)
    out 0xA1, al

    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al

    mov al, 0x01
    out 0x21, al
    out 0xA1, al

    ; UNMASK IRQs
    mov al, 0x00
    out 0x21, al
    out 0xA1, al

    ; ----------------
    ; SET HANDLERS
    ; ----------------
    IDT_SET isr0, 0, 10001110b    ; divide by zero
    IDT_SET isr1, 1, 10001110b

    IDT_SET irq0, 32, 10001110b   ; timer
    IDT_SET irq1, 33, 10001110b   ; keyboard

    ; ----------------
    ; LOAD IDT
    ; ----------------
    lidt [idt_descriptor]

    sti                         ; 🔥 interrupts AAN

    ret

; ================================
; ISR (EXCEPTIONS)
; ================================
isr0:
    cli
    mov edi, 0xB8000
    mov ax, 0x0745             ; 'E'
    mov [edi], ax
.hang:
    hlt
    jmp .hang

isr1:
    iret

; ================================
; IRQ HANDLERS
; ================================

; TIMER (IRQ0)
irq0:
    pushad

    ; simpele debug output
    mov edi, 0xB8002
    mov ax, 0x072E             ; '.'
    mov [edi], ax

    ; EOI (end of interrupt)
    mov al, 0x20
    out 0x20, al

    popad
    iret

; KEYBOARD (IRQ1)
irq1:
    pushad

    in al, 0x60                ; lees scancode

    mov edi, 0xB8004
    mov ah, 0x07
    mov [edi], ax

    ; EOI
    mov al, 0x20
    out 0x20, al

    popad
    iret
