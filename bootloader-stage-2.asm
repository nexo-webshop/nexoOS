; Nexo OS Stage 2 Bootloader
; ===========================
; Loaded by stage 1 at 0x0000:0x7E00
; Can be up to 64 sectors (32KB)
;
; Next steps (suggested):
; - Enable A20 line
; - Load kernel
; - Switch to protected mode
; - Jump to kernel

[org 0x7E00]
[bits 16]

stage2_start:
    ; ========================
    ; Setup (keep minimal)
    ; ========================
    cli
    
    ; Segment registers should be 0 from stage 1
    ; but verify them
    xor ax, ax
    mov ss, ax
    mov sp, 0x9000             ; plenty of stack space
    mov ds, ax
    mov es, ax
    
    cld
    sti
    
    ; ========================
    ; Print identification
    ; ========================
    mov si, msg_stage2
    call print_string
    
    ; ========================
    ; TODO: Add your stage 2 logic here
    ; ========================
    ; - Load kernel from disk
    ; - Detect memory (INT 0x12, E801, etc.)
    ; - Build memory map
    ; - Enable A20 line
    ; - Load GDT
    ; - Switch to protected mode
    
    mov si, msg_todo
    call print_string
    
.hang:
    cli
    hlt
    jmp .hang

; ========================
; print_string: Print null-terminated string
; ========================
print_string:
    push ax
    push bx
    
.loop:
    lodsb
    test al, al
    jz .done
    
    mov ah, 0x0E
    mov bx, 0x0007
    int 0x10
    
    jmp .loop
    
.done:
    pop bx
    pop ax
    ret

; ========================
; Data
; ========================
msg_stage2:
    db "Stage 2 loaded successfully!", 0x0D, 0x0A, 0

msg_todo:
    db "TODO: Implement stage 2 logic", 0x0D, 0x0A, 0

; ========================
; Padding (fill rest of 32KB)
; ========================
times 0x8000 - ($ - $$) db 0  ; pad to 32KB total
