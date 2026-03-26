bits 32
global kernel_main

kernel_main:

    cli                         ; 🔥 interrupts uit (geen IDT nog)

; ----------------
; SEGMENTS RESET (BELANGRIJK)
; ----------------
    mov ax, 0x10                ; data segment selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

; ----------------
; STACK (VEILIG + ALIGNED)
; ----------------
    mov esp, 0x90000
    and esp, 0xFFFFFFF0

    cld                         ; string ops safety

; ----------------
; VGA TEXT MODE WRITE
; ----------------
    mov edi, 0xB8000            ; VGA buffer
    mov al, 'N'
    mov ah, 0x07                ; lichtgrijs op zwart
    mov [edi], ax

; ----------------
; DEBUG: meerdere chars (optioneel)
; ----------------
    mov word [edi+2], 0x0745    ; 'E'
    mov word [edi+4], 0x0758    ; 'X'
    mov word [edi+6], 0x074F    ; 'O'

; ----------------
; HALT LOOP (CPU vriendelijk)
; ----------------
.hang:
    hlt
    jmp .hang
