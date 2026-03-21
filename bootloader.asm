; Nexo OS Bootloader v1.2 (ultra-safe) - IMPROVED
; ===============================================
[org 0x7C00]
[bits 16]

start:
    cli                     ; EERSTE: disable interrupts
    
    ; ========================
    ; Register initialization
    ; ========================
    xor ax, ax
    mov ds, ax              ; DS = 0
    mov es, ax              ; ES = 0
    mov ss, ax              ; SS = 0
    
    ; ========================
    ; Stack setup CRITICAL!
    ; ========================
    ; SAFE: groeit van 0x7BFE naar beneden
    ; BIOS data zone begint pas rond 0x400
    mov sp, 0x7C00          ; Stack boven bootloader
    
    ; ========================
    ; Flags & interrupts
    ; ========================
    cld                     ; DF = 0 (forward string ops)
    sti                     ; NOW enable interrupts
    
    ; ========================
    ; Print startup message
    ; ========================
    mov si, message
    call print_string
    
    ; ========================
    ; Main loop
    ; ========================
hang:
    cli
    hlt
    jmp hang

; ========================
; print_string: output string
; Input:  DS:SI -> null-terminated string
; Clobber: AL, AH, SI
; ========================
print_string:
    push ax
    push bx
    
.next_char:
    lodsb                   ; AL = [DS:SI++]
    test al, al             ; check null
    jz .done
    
    mov ah, 0x0E            ; TTY write
    xor bx, bx              ; BX = 0 (page 0, no color override)
    int 0x10
    
    jmp .next_char
    
.done:
    pop bx
    pop ax
    ret

; ========================
; Data
; ========================
message db "Nexo OS secure boot...", 0x0D, 0x0A, "Ready.", 0

; ========================
; Boot sector
; ========================
times 510 - ($ - $$) db 0
dw 0xAA55
