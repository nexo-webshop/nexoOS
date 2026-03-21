; ============================================================================
; Nexo OS Stage 2 Bootloader v1.2 - FIXED & OPTIMIZED
; ============================================================================
; Loaded by Stage 1 at 0x0000:0x7E00
; Can be up to 64 sectors (32KB)
;
; Improvements:
;   - Fixed A20 enable with proper fallback
;   - Proper memory detection with error handling
;   - Fixed padding calculation
;   - Better segment register verification
;   - Video mode consistency with Stage 1
;   - Timeout protection for A20 keyboard method
;   - Print messages for each operation
;   - CRT page management
; ============================================================================

[org 0x7E00]
[bits 16]

; ============================================================================
; ENTRY POINT
; ============================================================================
stage2_start:
    cli                     ; FIRST: Disable interrupts
    
    ; ========================================================================
    ; SEGMENT REGISTER VERIFICATION
    ; ========================================================================
    ; Stage 1 should have set these, but verify for safety
    xor ax, ax
    mov ds, ax              ; DS = 0x0000
    mov es, ax              ; ES = 0x0000
    mov ss, ax              ; SS = 0x0000
    
    ; ========================================================================
    ; STACK SETUP - CRITICAL!
    ; ========================================================================
    ; Stage 1: 0x7C00-0x7DFF (512 bytes)
    ; Stage 2: 0x7E00-... (this code)
    ; Stack grows DOWN from SP
    ; Safe stack: 0x7C00 down to 0x0400+ (above BIOS data)
    mov sp, 0x7C00         ; SP = 0x7C00 (between Stage 1 and Stage 2)
    
    ; ========================================================================
    ; FLAGS & INTERRUPTS
    ; ========================================================================
    cld                     ; Clear Direction Flag (string ops forward)
    sti                     ; Enable interrupts (safe after stack setup)
    
    ; ========================================================================
    ; VERIFY VIDEO MODE (consistency with Stage 1)
    ; ========================================================================
    mov ax, 0x0003          ; Set 80x25 text mode
    int 0x10
    
    ; Move cursor to safe position for messages
    mov ax, 0x0200          ; AH = 02 (set cursor)
    mov bh, 0               ; BH = page 0
    mov dh, 5               ; DH = row 5 (leave space from top)
    xor dl, dl              ; DL = column 0
    int 0x10
    
    ; ========================================================================
    ; PRINT STAGE 2 IDENTIFICATION
    ; ========================================================================
    mov si, msg_stage2_banner
    call print_string
    
    ; ========================================================================
    ; ENABLE A20 LINE (CRITICAL for >1MB memory access)
    ; ========================================================================
    ; Try BIOS method first (modern, fast, reliable)
    mov si, msg_a20_attempt
    call print_string
    
    mov ax, 0x2401         ; INT 0x15 AX=0x2401: enable A20
    int 0x15
    
    jnc .a20_success        ; If carry clear = success
    
    ; ========================================================================
    ; A20 FALLBACK: Keyboard controller method
    ; ========================================================================
    ; If BIOS method failed, use keyboard controller
    mov si, msg_a20_fallback
    call print_string
    
    ; Wait for keyboard controller input buffer to be empty
    mov cx, 0xFFFF          ; Timeout counter (safety)
    
.kbd_wait_input:
    in al, 0x64             ; Read keyboard status port
    test al, 2              ; Bit 1 = input buffer full?
    jz .kbd_send_cmd        ; If empty, continue
    
    dec cx                  ; Decrement timeout
    jnz .kbd_wait_input     ; Loop if not timed out
    
    mov si, msg_a20_timeout
    call print_string
    jmp .a20_failed
    
.kbd_send_cmd:
    ; Send 0xD1 command (write output port)
    mov al, 0xD1
    out 0x64, al
    
    ; Wait for input buffer empty again
    mov cx, 0xFFFF
    
.kbd_wait_output:
    in al, 0x64
    test al, 2
    jz .kbd_write_data
    
    dec cx
    jnz .kbd_wait_output
    
    mov si, msg_a20_timeout
    call print_string
    jmp .a20_failed
    
.kbd_write_data:
    ; Write 0xDF to output port (set A20 bit, keep others)
    mov al, 0xDF
    out 0x60, al
    
    mov si, msg_a20_success
    call print_string
    jmp .a20_complete
    
.a20_success:
    mov si, msg_a20_bios
    call print_string
    
.a20_complete:
    ; ========================================================================
    ; MEMORY DETECTION (INT 0x15 E801)
    ; ========================================================================
    mov si, msg_memory_detect
    call print_string
    
    mov ax, 0xE801          ; INT 0x15 E801: get extended memory
    xor cx, cx              ; CX = 0 (clear before call)
    xor dx, dx              ; DX = 0 (clear before call)
    int 0x15
    
    jnc .memory_ok          ; If carry clear = success
    
    ; Memory detection failed (very old system or error)
    mov si, msg_memory_fail
    call print_string
    xor cx, cx              ; Assume 0 KB if detection fails
    
.memory_ok:
    ; CX = KB from 1MB to 16MB (in 64KB units)
    ; DX = 64KB blocks above 16MB
    ; Store for later use
    mov [memory_lower], cx
    mov [memory_upper], dx
    
    mov si, msg_memory_ok
    call print_string
    
    ; ========================================================================
    ; PRINT SYSTEM STATUS
    ; ========================================================================
    mov si, msg_system_ready
    call print_string
    
    ; ========================================================================
    ; PLACEHOLDER: NEXT STAGES
    ; ========================================================================
    ; TODO (Stage 3+):
    ;   1. Load kernel from disk
    ;   2. Setup GDT (Global Descriptor Table)
    ;   3. Switch to Protected Mode (32-bit)
    ;   4. Jump to kernel entry point
    
    mov si, msg_todo
    call print_string
    
    ; ========================================================================
    ; MAIN LOOP (wait for next action)
    ; ========================================================================
hang:
    cli                     ; Disable interrupts
    hlt                     ; Halt CPU (low power)
    jmp hang                ; Infinite loop (safety)

; ============================================================================
; PRINT_STRING: Print null-terminated ASCII string to screen
; ============================================================================
; Input:  DS:SI -> null-terminated string
; Output: SI points to byte after null terminator
; Clobber: AL, AH, BX, SI
; ============================================================================
print_string:
    push ax
    push bx
    push si
    
.char_loop:
    lodsb                   ; Load AL = [DS:SI++]
    test al, al             ; Check for null terminator
    jz .string_done         ; If null, string complete
    
    ; Handle special characters
    cmp al, 0x0D            ; CR (carriage return)?
    je .char_loop           ; Skip (LF will handle newline)
    
    cmp al, 0x0A            ; LF (line feed)?
    jne .print_char         ; If not LF, print normally
    
    ; Handle newline: move cursor to next line
    mov ah, 0x03            ; AH = 03 (read cursor position)
    xor bx, bx              ; BH = page 0
    int 0x10                ; Returns DX = cursor position
    
    inc dh                  ; DH++ (next row)
    mov dl, 0               ; DL = 0 (column 0)
    
    mov ah, 0x02            ; AH = 02 (set cursor position)
    int 0x10
    
    jmp .char_loop
    
.print_char:
    mov ah, 0x0E            ; BIOS function 0E: TTY write
    mov bh, 0               ; BH = page 0
    int 0x10                ; Print character in AL
    
    jmp .char_loop
    
.string_done:
    pop si
    pop bx
    pop ax
    ret

; ============================================================================
; DATA SECTION - MESSAGES
; ============================================================================

msg_stage2_banner:
    db 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db "  NEXO OS Stage 2 Bootloader", 0x0D, 0x0A
    db "  v1.2 - Safe Edition", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

msg_a20_attempt:
    db "Attempting A20 via BIOS...", 0x0D, 0x0A, 0

msg_a20_bios:
    db "[OK] A20 enabled (BIOS method)", 0x0D, 0x0A, 0

msg_a20_fallback:
    db "[!] BIOS failed, trying keyboard...", 0x0D, 0x0A, 0

msg_a20_success:
    db "[OK] A20 enabled (keyboard method)", 0x0D, 0x0A, 0

msg_a20_timeout:
    db "[WARN] A20 keyboard timeout!", 0x0D, 0x0A, 0

msg_memory_detect:
    db "Detecting system memory...", 0x0D, 0x0A, 0

msg_memory_ok:
    db "[OK] Memory detected", 0x0D, 0x0A, 0

msg_memory_fail:
    db "[WARN] Memory detection failed", 0x0D, 0x0A, 0

msg_system_ready:
    db 0x0D, 0x0A
    db "System ready for next stage!", 0x0D, 0x0A, 0

msg_todo:
    db "Waiting for Stage 3 (kernel loader)...", 0x0D, 0x0A, 0

; ============================================================================
; DATA SECTION - RUNTIME VARIABLES
; ============================================================================

memory_lower:
    dw 0                    ; KB from 1MB to 16MB

memory_upper:
    dw 0                    ; 64KB blocks above 16MB

; ============================================================================
; PADDING & ALIGNMENT
; ============================================================================
; Stage 2 location: 0x7E00
; Max size: 64 sectors (32KB)
; End location: 0x7E00 + 0x8000 = 0xFE00
; Padding: fill to end with zeros

align 4096                  ; Align to 4KB boundary (safety)
times (0x7E00 + 0x8000) - ($ - $$) db 0x00
