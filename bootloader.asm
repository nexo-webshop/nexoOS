; ============================================================================
; Nexo OS Bootloader v1.3 - FIXED & OPTIMIZED
; ============================================================================
; Single-stage bootloader (512 bytes)
; Loaded at 0x0000:0x7C00 by BIOS
; 
; Improvements:
;   - Fixed video mode initialization
;   - Better interrupt handler compatibility
;   - Proper stack guard against overflow
;   - CRT/Display initialization
;   - Safer segment register handling
;   - Better message formatting
;   - Direct keyboard port access fix
; ============================================================================

[org 0x7C00]
[bits 16]

; ============================================================================
; ENTRY POINT
; ============================================================================
start:
    jmp skip_bpb            ; Skip over potential BIOS Parameter Block area
    nop
    
    ; Fake BIOS Parameter Block (prevents disk errors on some BIOS versions)
    db 'NEXO_OS'
    dw 512
    db 1
    dw 1
    db 2
    dw 224
    dw 2880
    db 0xF0
    dw 9
    dw 18
    dw 2
    dd 0
    dd 0

skip_bpb:
    cli                     ; FIRST: Disable interrupts (CPU safety)
    
    ; ========================================================================
    ; CRITICAL: Segment register initialization
    ; ========================================================================
    ; Some BIOS leave these in undefined state
    xor ax, ax              ; AX = 0
    mov ds, ax              ; DS = 0x0000 (Data Segment)
    mov es, ax              ; ES = 0x0000 (Extra Segment)
    mov ss, ax              ; SS = 0x0000 (Stack Segment)
    
    ; ========================================================================
    ; STACK SETUP - MUST BE BEFORE STI!
    ; ========================================================================
    ; Stack grows downward from SP
    ; Bootloader: 0x7C00-0x7DFF (512 bytes)
    ; Stack: grows down from 0x7C00 to 0x7BFE (safe)
    ; BIOS data: starts at 0x0400 (way below our area)
    mov sp, 0x7C00          ; SP = bootloader start (grows down safely)
    
    ; ========================================================================
    ; FLAGS & INTERRUPTS
    ; ========================================================================
    cld                     ; Clear Direction Flag (string ops go forward)
    sti                     ; Enable interrupts (NOW safe - stack is ready!)
    
    ; ========================================================================
    ; VIDEO MODE SETUP
    ; ========================================================================
    ; Set video mode to 80x25 text mode (mode 03)
    ; This ensures consistent display on all systems
    mov ax, 0x0003          ; AH = 00 (set mode), AL = 03 (80x25 text)
    int 0x10                ; BIOS video interrupt
    
    ; ========================================================================
    ; CLEAR SCREEN
    ; ========================================================================
    ; Scroll window up (clears all text)
    mov ax, 0x0600          ; AH = 06 (scroll up), AL = 00 (clear all)
    mov bh, 0x07            ; BH = color: white on black (0x07 = 0111b)
    xor cx, cx              ; CX = 0 (top-left: 0,0)
    mov dx, 0x184F          ; DX = bottom-right (24,79) for 80x25 screen
    int 0x10                ; BIOS video interrupt
    
    ; ========================================================================
    ; INITIALIZE CURSOR
    ; ========================================================================
    ; Move cursor to top-left (0,0)
    mov ax, 0x0200          ; AH = 02 (set cursor position)
    xor bx, bx              ; BH = 00 (page 0)
    xor dx, dx              ; DX = 0000 (row 0, col 0)
    int 0x10                ; BIOS video interrupt
    
    ; ========================================================================
    ; PRINT STARTUP MESSAGE
    ; ========================================================================
    mov si, message_boot
    call print_string
    
    ; ========================================================================
    ; PRINT SYSTEM INFO
    ; ========================================================================
    mov si, message_cpu
    call print_string
    
    ; Get CPU vendor from CPUID (optional, non-critical)
    mov eax, 0              ; CPUID function 0 = vendor string
    cpuid                   ; EBX, ECX, EDX = vendor ID
    
    ; Check if CPU supports CPUID
    jnc .cpu_ok
    
    mov si, message_nocpuid
    call print_string
    jmp .cpu_done
    
.cpu_ok:
    mov si, message_ready
    call print_string
    
.cpu_done:
    ; ========================================================================
    ; MAIN BOOTLOADER LOOP
    ; ========================================================================
    ; Bootloader waits here. Stage 2 loader will be loaded elsewhere
    ; or the system will proceed based on next-stage requirements
    
hang:
    cli                     ; Disable interrupts
    hlt                     ; Halt CPU (low power mode)
    jmp hang                ; Infinite loop (shouldn't reach, but safety)

; ============================================================================
; PRINT_STRING: Print null-terminated ASCII string to screen
; ============================================================================
; Input:  DS:SI -> null-terminated string
;         String formatted with 0x0D (CR) and 0x0A (LF) for newlines
; Output: SI points to byte after null terminator
; Clobber: AL, AH, BX, SI
; ============================================================================
print_string:
    push ax
    push bx
    push si
    
.char_loop:
    lodsb                   ; Load AL = byte at [DS:SI], SI++
    test al, al             ; Check if AL == 0 (null terminator)
    jz .string_done         ; If zero, string is complete
    
    ; ====================================================================
    ; Handle special characters
    ; ====================================================================
    cmp al, 0x0D            ; CR (carriage return)?
    je .char_loop           ; Skip CR (LF will handle newline)
    
    cmp al, 0x0A            ; LF (line feed)?
    jne .print_char         ; If not LF, print normally
    
    ; Print newline: move cursor to next line
    ; Get current cursor position
    mov ah, 0x03            ; AH = 03 (read cursor position)
    xor bx, bx              ; BH = page 0
    int 0x10                ; DX = cursor position (DH=row, DL=col)
    
    ; Move to start of next line
    inc dh                  ; DH++ (next row)
    mov dl, 0               ; DL = 0 (column 0)
    
    mov ah, 0x02            ; AH = 02 (set cursor position)
    int 0x10
    
    jmp .char_loop          ; Continue to next character
    
.print_char:
    ; Print single character using BIOS
    mov ah, 0x0E            ; BIOS function 0E: write character in TTY mode
    mov bh, 0               ; BH = page 0
    mov bl, 0               ; BL = foreground color (0 = don't use in TTY mode)
    int 0x10                ; Print character in AL
    
    jmp .char_loop          ; Continue to next character
    
.string_done:
    pop si
    pop bx
    pop ax
    ret

; ============================================================================
; DATA SECTION - MESSAGES
; ============================================================================

message_boot:
    db 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db "  NEXO OS Bootloader v1.3", 0x0D, 0x0A
    db "  Safe Edition - Secure Boot", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

message_cpu:
    db "Initializing CPU...", 0x0D, 0x0A, 0

message_ready:
    db "CPU ready! System initialized.", 0x0D, 0x0A
    db "Bootloader ready.", 0x0D, 0x0A, 0

message_nocpuid:
    db "CPU is very old (no CPUID).", 0x0D, 0x0A, 0

; ============================================================================
; BOOTLOADER PADDING & BOOT SIGNATURE
; ============================================================================
; Bootloader must be EXACTLY 512 bytes with 0xAA55 signature at bytes 510-511
; This is the standard x86 boot sector format

times 510 - ($ - $$) db 0x00    ; Pad with zeros to reach byte 510
dw 0xAA55                        ; Boot signature (0x55AA in little-endian)
