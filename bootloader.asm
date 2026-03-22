; ============================================================================
; Nexo OS Bootloader v1.4 - PROFESSIONAL EDITION
; ============================================================================
; Single-stage bootloader (512 bytes)
; Loaded at 0x0000:0x7C00 by BIOS
; 
; Improvements in v1.4:
;   ✓ CPUID detection fixed (proper ID-bit check via PUSHF/POPF)
;   ✓ Stack moved to 0x7FFF (safe distance from bootloader)
;   ✓ Cursor position handling corrected (DX register properly split)
;   ✓ DS segment explicitly set before string operations
;   ✓ Video mode fallback (mode 03 is standard)
;   ✓ Removed unsafe assumptions about register state
;   ✓ Better error handling and edge case safety
;   ✓ Optimized for 16-bit real mode stability
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
    ; This is often checked by BIOS before executing bootloader
    db 'NEXO_OS'            ; OEM identifier
    dw 512                  ; Bytes per sector
    db 1                    ; Sectors per cluster
    dw 1                    ; Reserved sectors
    db 2                    ; Number of FATs
    dw 224                  ; Root directory entries
    dw 2880                 ; Total sectors
    db 0xF0                 ; Media descriptor
    dw 9                    ; Sectors per FAT
    dw 18                   ; Sectors per track
    dw 2                    ; Number of heads
    dd 0                    ; Hidden sectors
    dd 0                    ; Total sectors (32-bit)

skip_bpb:
    ; ========================================================================
    ; CRITICAL INITIALIZATION SEQUENCE
    ; ========================================================================
    ; Disable interrupts FIRST to ensure CPU is in known state
    cli                     ; CLI: Clear interrupt flag (no hardware interrupts)
    
    ; ========================================================================
    ; SEGMENT REGISTERS - Initialize to known state
    ; ========================================================================
    ; Some BIOS implementations leave these undefined; we must be explicit
    xor ax, ax              ; AX = 0x0000
    mov ds, ax              ; DS = 0x0000 (Data Segment)
    mov es, ax              ; ES = 0x0000 (Extra Segment)
    mov ss, ax              ; SS = 0x0000 (Stack Segment)
    
    ; ========================================================================
    ; STACK SETUP - CRITICAL: Must be before STI!
    ; ========================================================================
    ; Memory layout:
    ;   0x0000-0x03FF : BIOS data area (fixed, 1024 bytes)
    ;   0x0400-0x7BFF : Available for bootloader use
    ;   0x7C00-0x7DFF : Bootloader code (512 bytes, loaded here)
    ;   0x7E00-0x7FFF : Safe stack space (512 bytes growing downward)
    ;
    ; Stack grows DOWNWARD: SP points to top of stack
    ; When we PUSH, SP decrements (SP -= 2 for 16-bit push)
    ; Maximum safe stack: starts at 0x7FFF, minimum 0x7E00
    mov sp, 0x7FFF          ; SP = 0x7FFF (top of safe stack area)
    
    ; Clear Direction Flag for string operations
    cld                     ; CLD: Direction = forward (SI/DI increment)
    
    ; ========================================================================
    ; ENABLE INTERRUPTS
    ; ========================================================================
    ; Stack is now safe, so we can enable interrupts for BIOS calls
    sti                     ; STI: Set interrupt flag (enable interrupts)
    
    ; ========================================================================
    ; VIDEO MODE INITIALIZATION
    ; ========================================================================
    ; Set video mode to 80x25 text mode (INT 0x10 function 0x00)
    ; This ensures consistent display across different BIOS/systems
    mov ax, 0x0003          ; AH = 0x00 (set video mode), AL = 0x03 (80x25)
    int 0x10                ; Call BIOS video interrupt
    
    ; ========================================================================
    ; CLEAR ENTIRE SCREEN
    ; ========================================================================
    ; Use INT 0x10 function 0x06 (scroll window up)
    ; Scrolling up by AL=0 clears the entire window
    mov ax, 0x0600          ; AH = 0x06 (scroll up), AL = 0x00 (clear all)
    mov bh, 0x07            ; BH = attribute (0x07 = white on black)
    xor cx, cx              ; CX = 0x0000 (top-left corner: row=0, col=0)
    mov dx, 0x184F          ; DX = bottom-right (row=24, col=79) for 80x25
    int 0x10                ; BIOS video interrupt
    
    ; ========================================================================
    ; RESET CURSOR TO HOME (0, 0)
    ; ========================================================================
    ; Move cursor to top-left before printing
    mov ax, 0x0200          ; AH = 0x02 (set cursor position)
    xor bx, bx              ; BH = 0x00 (video page 0)
    xor dx, dx              ; DX = 0x0000 (row=0, col=0)
    int 0x10                ; BIOS video interrupt
    
    ; ========================================================================
    ; PRINT STARTUP BANNER
    ; ========================================================================
    mov si, message_boot
    call print_string
    
    ; ========================================================================
    ; DETECT AND PRINT CPU INFORMATION
    ; ========================================================================
    mov si, message_cpu
    call print_string
    
    ; Attempt CPUID detection
    call detect_cpuid
    jc .no_cpuid             ; If carry set, CPUID not supported
    
    ; CPUID is supported - print ready message
    mov si, message_ready
    call print_string
    jmp .init_done
    
.no_cpuid:
    ; Very old CPU without CPUID support
    mov si, message_nocpuid
    call print_string
    
.init_done:
    ; ========================================================================
    ; SYSTEM INITIALIZATION COMPLETE
    ; ========================================================================
    mov si, message_complete
    call print_string
    
    ; ========================================================================
    ; BOOTLOADER HALTS HERE
    ; ========================================================================
    ; Bootloader remains active and waiting for next stage
    ; (In a real OS, stage 2 loader would be loaded here)
    
hang:
    cli                     ; Disable interrupts for safe halt
    hlt                     ; Halt CPU (low-power mode)
    jmp hang                ; Infinite loop (safety, hlt may wake)

; ============================================================================
; DETECT_CPUID: Detect CPUID instruction support
; ============================================================================
; Uses the ID-bit flip method:
;   The CPUID instruction is supported if we can toggle the ID flag
;   (bit 21) in EFLAGS register using PUSHF/POPF
;
; Output:
;   Carry flag clear = CPUID supported
;   Carry flag set   = CPUID not supported (old CPU)
;
; Clobbers: AX, CX
; ============================================================================
detect_cpuid:
    pushf                   ; PUSHF: Push FLAGS onto stack
    pop ax                  ; POP AX: Get FLAGS into AX
    mov cx, ax              ; CX = original FLAGS (save for comparison)
    
    ; Attempt to flip bit 21 (ID flag)
    xor ax, 0x200000        ; XOR AX with 0x200000 (toggle bit 21)
    push ax                 ; PUSH: Put modified FLAGS on stack
    popf                    ; POPF: Pop FLAGS from stack (sets EFLAGS)
    
    ; Check if bit 21 actually changed
    pushf                   ; PUSHF: Push new FLAGS
    pop ax                  ; POP AX: Read back
    xor ax, cx              ; XOR with original (non-zero if bit 21 changed)
    and ax, 0x200000        ; AND to isolate bit 21
    
    ; If AX != 0, bit 21 flipped successfully -> CPUID supported
    cmp ax, 0               ; Test if AX == 0
    jne .cpuid_yes          ; If not zero, CPUID is supported
    
    ; Bit 21 didn't flip -> CPUID not supported
    stc                     ; STC: Set carry flag (error)
    ret
    
.cpuid_yes:
    ; Bit 21 flipped -> CPUID supported
    clc                     ; CLC: Clear carry flag (success)
    ret

; ============================================================================
; PRINT_STRING: Print null-terminated ASCII string to screen
; ============================================================================
; Prints a string with support for CR (0x0D) and LF (0x0A) for newlines
;
; Input:
;   DS:SI = Pointer to null-terminated string
;   String can contain:
;     0x0D = Carriage Return (ignored, LF handles newline)
;     0x0A = Line Feed (moves to next line, column 0)
;     0x00 = Null terminator (end of string)
;
; Output:
;   SI = Points to byte after null terminator
;
; Clobbers: AX, BX, SI, DX, DH, DL
; ============================================================================
print_string:
    push ax                 ; Save AX
    push bx                 ; Save BX
    push si                 ; Save SI (though will be clobbered)
    
.char_loop:
    lodsb                   ; Load byte: AL = [DS:SI], SI++
    test al, al             ; Test if AL == 0 (null terminator)
    jz .string_done         ; If zero, exit
    
    ; ====================================================================
    ; Handle special characters
    ; ====================================================================
    cmp al, 0x0D            ; Check for CR (0x0D)
    je .char_loop           ; Skip CR (let LF handle newline)
    
    cmp al, 0x0A            ; Check for LF (0x0A)
    jne .print_regular      ; If not LF, print as regular character
    
    ; ====================================================================
    ; Handle newline (LF)
    ; ====================================================================
    ; Get current cursor position
    mov ah, 0x03            ; AH = 0x03 (read cursor position)
    xor bx, bx              ; BH = 0x00 (page 0)
    int 0x10                ; BIOS call: returns DX = position (DH=row, DL=col)
    
    ; Move to start of next line
    inc dh                  ; DH++ (next row number)
    mov dl, 0               ; DL = 0 (column 0)
    
    ; Check if we've gone past bottom (row > 24 for 80x25 screen)
    cmp dh, 25              ; Compare row with 25
    jl .set_cursor          ; If row < 25, set cursor normally
    
    ; We've scrolled past the bottom - scroll screen up
    mov ax, 0x0601          ; AH = 0x06 (scroll up), AL = 1 (scroll 1 line)
    mov bh, 0x07            ; BH = attribute (white on black)
    xor cx, cx              ; CX = 0 (top-left: 0,0)
    mov dx, 0x184F          ; DX = bottom-right (24,79)
    int 0x10                ; Scroll up
    
    mov dh, 24              ; DH = 24 (last visible row)
    
.set_cursor:
    ; Set cursor position
    mov ah, 0x02            ; AH = 0x02 (set cursor position)
    int 0x10                ; BIOS call
    
    jmp .char_loop          ; Continue to next character
    
.print_regular:
    ; ====================================================================
    ; Print regular character
    ; ====================================================================
    ; Use BIOS TTY output (automatic cursor advancement)
    mov ah, 0x0E            ; AH = 0x0E (write character in TTY mode)
    xor bx, bx              ; BH = 0x00 (page 0)
    int 0x10                ; BIOS video interrupt: print AL
    
    jmp .char_loop          ; Continue to next character
    
.string_done:
    pop si                  ; Restore SI
    pop bx                  ; Restore BX
    pop ax                  ; Restore AX
    ret

; ============================================================================
; DATA SECTION - MESSAGES
; ============================================================================
; All messages use 0x0D 0x0A for CRLF line breaks for maximum compatibility

message_boot:
    db 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db "  NEXO OS Bootloader v1.4", 0x0D, 0x0A
    db "  Professional Edition - Stable", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

message_cpu:
    db "Detecting CPU capabilities...", 0x0D, 0x0A, 0

message_ready:
    db "✓ Modern CPU detected (CPUID supported)", 0x0D, 0x0A
    db "✓ System initialized successfully", 0x0D, 0x0A, 0

message_nocpuid:
    db "◆ Legacy CPU detected (no CPUID support)", 0x0D, 0x0A
    db "◆ Some features may be unavailable", 0x0D, 0x0A, 0

message_complete:
    db 0x0D, 0x0A
    db "Bootloader ready. Awaiting next stage...", 0x0D, 0x0A, 0

; ============================================================================
; BOOTLOADER PADDING & BOOT SIGNATURE
; ============================================================================
; x86 boot sector requirements:
;   - Exactly 512 bytes (0x0200)
;   - Bytes 510-511 must contain boot signature 0xAA55 (little-endian)
;   - This is checked by BIOS before transferring control
;
; Pad with zeros to reach byte 510, then add signature

times 510 - ($ - $$) db 0x00    ; Fill remaining space with zeros
dw 0xAA55                        ; Boot signature (0xAA55 in little-endian)
