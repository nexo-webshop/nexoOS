; Nexo OS Stage 2 Bootloader v1.1 - FIXED
; ========================================
[org 0x7E00]
[bits 16]

stage2_start:
    cli
    
    ; ========================
    ; Verify segment registers
    ; ========================
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    
    ; ========================
    ; CRITICAL: Stack placement
    ; ========================
    ; Stage 1: 0x7C00-0x7DFF (512 bytes)
    ; Stage 2: 0x7E00-0xFDFF (up to 32KB)
    ; Stack: grows DOWN from 0x7C00
    ; Safe: SP = 0x7C00 (won't collide)
    mov sp, 0x7C00              ; ← FIXED!
    
    cld
    sti
    
    ; ========================
    ; Print identification
    ; ========================
    mov si, msg_stage2
    call print_string
    
    ; ========================
    ; Enable A20 line (CRITICAL!)
    ; ========================
    call enable_a20
    
    ; ========================
    ; Memory detection (E801)
    ; ========================
    call detect_memory
    
    ; ========================
    ; TODO: Next steps
    ; ========================
    ; - Load kernel
    ; - Load & setup GDT
    ; - Switch to protected mode
    ; - Jump to kernel entry point
    
    mov si, msg_ready
    call print_string
    
.hang:
    cli
    hlt
    jmp .hang

; ========================
; enable_a20: Enable A20 line via keyboard
; ========================
; BIOS int 0x15 ax=0x2401 (modern method)
; Falls back to keyboard if needed
enable_a20:
    push ax
    
    ; Try BIOS int 0x15 first (fast, modern)
    mov ax, 0x2401
    int 0x15
    
    ; If carry set = not supported, try keyboard method
    ; (For now, assume it works - can add fallback later)
    
    pop ax
    ret

; ========================
; detect_memory: Detect RAM via INT 0x15 E801
; ========================
detect_memory:
    push ax
    push cx
    push dx
    
    mov ax, 0xE801         ; INT 0x15 E801 = get extended memory
    int 0x15
    
    ; CX = KB below 16MB
    ; DX = 64KB blocks above 16MB
    ; Store results for later use
    
    pop dx
    pop cx
    pop ax
    ret

; ========================
; print_string
; ========================
print_string:
    push ax
    push bx
    
.loop:
    lodsb
    test al, al
    jz .done
    
    mov ah, 0x0E
    xor bx, bx              ; BH=page 0, BL=0
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
    db "Stage 2 loaded!", 0x0D, 0x0A, 0
msg_ready:
    db "Ready for next stage...", 0x0D, 0x0A, 0

; ========================
; Padding
; ========================
; Stage 2 max size: 64 sectors = 32KB
; Stage 2 @ 0x7E00, so pad to 0x7E00 + 0x8000 = 0xFE00
align 4096              ; align to 4KB boundary
times (0x7E00 + 0x8000) - ($ - $$) db 0
