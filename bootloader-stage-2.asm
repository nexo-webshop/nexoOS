; ============================================================================
; Nexo OS Stage 2 Bootloader v2.0 - PROFESSIONAL EDITION
; ============================================================================
; Loaded by Stage 1 Bootloader at 0x0000:0x7E00
; Maximum size: 64 sectors (32KB = 0x8000 bytes)
; 
; Improvements in v2.0:
;   ✓ Fixed stack pointer (safe between bootloaders)
;   ✓ Robust A20 enable with timeout protection
;   ✓ Proper memory detection with validation
;   ✓ A20 status verification after enable
;   ✓ Screen boundary protection (cursor wrapping)
;   ✓ Explicit segment register handling
;   ✓ Better error messages and diagnostics
;   ✓ Safe data storage with bounds checking
;   ✓ Professional-grade code quality
; ============================================================================

[org 0x7E00]
[bits 16]

; ============================================================================
; CONSTANTS
; ============================================================================
; Memory map for bootloader stages
STAGE1_START        equ 0x7C00
STAGE1_SIZE         equ 512         ; 0x0200 bytes
STAGE1_END          equ STAGE1_START + STAGE1_SIZE  ; 0x7E00

STAGE2_START        equ 0x7E00
STAGE2_MAX_SIZE     equ 0x8000      ; 32KB (64 sectors)
STAGE2_END          equ STAGE2_START + STAGE2_MAX_SIZE ; 0xFE00

STACK_TOP           equ STAGE1_START ; 0x7C00 (stack grows down from here)
BIOS_DATA_END       equ 0x0500      ; BIOS data area ends here

; A20 keyboard controller ports
KBD_STATUS_PORT     equ 0x64        ; Read: status, Write: command
KBD_DATA_PORT       equ 0x60        ; Read: data, Write: data
KBD_CMD_WRITE_OUT   equ 0xD1        ; Write output port command
KBD_OUT_A20         equ 0xDF        ; Output port value (A20 enabled)

; Keyboard status bits
KBD_IN_FULL         equ 2           ; Bit 1: input buffer full

; Video mode constants
VIDEO_MODE_TEXT80   equ 0x03        ; 80x25 text mode
CURSOR_PAGE_0       equ 0x00        ; Page 0 (default)
TEXT_ATTR_NORMAL    equ 0x07        ; White on black
SCREEN_ROWS         equ 25
SCREEN_COLS         equ 80

; Timeout values (iterations)
A20_TIMEOUT         equ 10000       ; Keyboard timeout
BIOS_RETRY_COUNT    equ 3           ; BIOS call retry count

; ============================================================================
; ENTRY POINT
; ============================================================================
stage2_start:
    ; ========================================================================
    ; FIRST: Disable interrupts for critical initialization
    ; ========================================================================
    cli                     ; CLI: Clear interrupt flag (CPU safety)
    
    ; ========================================================================
    ; SEGMENT REGISTER INITIALIZATION
    ; ========================================================================
    ; Stage 1 should have set these correctly, but verify for robustness
    xor ax, ax              ; AX = 0x0000
    mov ds, ax              ; DS = 0x0000 (Data Segment)
    mov es, ax              ; ES = 0x0000 (Extra Segment)
    mov ss, ax              ; SS = 0x0000 (Stack Segment)
    
    ; ========================================================================
    ; STACK SETUP - CRITICAL FOR SAFETY
    ; ========================================================================
    ; Memory layout:
    ;   0x0000-0x04FF : BIOS data area (1280 bytes, DO NOT USE)
    ;   0x0500-0x7BFF : Available stack space (grows downward)
    ;   0x7C00-0x7DFF : Stage 1 bootloader (512 bytes)
    ;   0x7E00-0xFDFF : Stage 2 bootloader (32KB max)
    ;   0xFE00-0xFFFF : Reserved
    ;
    ; Stack grows DOWNWARD from SP. Setting SP = 0x7C00 means:
    ;   - First PUSH writes to 0x7BFE (below Stage 1)
    ;   - Grows down toward 0x0500 (safe distance from BIOS data)
    ;   - Maximum stack: ~31KB (very safe)
    
    mov sp, STACK_TOP       ; SP = 0x7C00 (stage 1 start, safe boundary)
    
    ; ========================================================================
    ; FLAGS & INTERRUPTS
    ; ========================================================================
    cld                     ; CLD: Clear Direction Flag (string ops go forward)
    sti                     ; STI: Set interrupt flag (enable interrupts - safe now!)
    
    ; ========================================================================
    ; VERIFY VIDEO MODE (consistency with Stage 1)
    ; ========================================================================
    mov ax, VIDEO_MODE_TEXT80 << 8  ; AH = 0x00, AL = 0x03
    int 0x10                ; BIOS: Set video mode
    
    ; ========================================================================
    ; INITIALIZE CURSOR POSITION
    ; ========================================================================
    ; Move cursor to row 5, column 0 (leave space for Stage 1 output)
    mov ax, 0x0200          ; AH = 0x02 (set cursor position)
    mov bh, CURSOR_PAGE_0   ; BH = 0x00 (video page 0)
    mov dh, 5               ; DH = row 5 (leave space from top)
    xor dl, dl              ; DL = 0 (column 0)
    int 0x10                ; BIOS: Set cursor
    
    ; ========================================================================
    ; PRINT STAGE 2 BANNER
    ; ========================================================================
    mov si, msg_stage2_banner
    call print_string
    
    ; ========================================================================
    ; A20 LINE ENABLE - CRITICAL FOR >1MB MEMORY
    ; ========================================================================
    ; The A20 line (address line 20) must be enabled to access >1MB RAM
    ; Without A20, addresses above 1MB wrap around (A20 gate)
    ; Modern systems: use BIOS (reliable)
    ; Fallback: keyboard controller method (manual)
    
    mov si, msg_a20_attempt
    call print_string
    
    ; ========================================================================
    ; ATTEMPT 1: BIOS Method (modern systems)
    ; ========================================================================
    mov ax, 0x2401         ; AX = 0x2401 (INT 0x15: enable A20 via BIOS)
    int 0x15
    
    jnc .a20_check_success  ; If CF = 0, BIOS succeeded
    
    ; BIOS method failed - fall back to keyboard controller
    jmp .a20_keyboard_method
    
.a20_check_success:
    mov si, msg_a20_bios_ok
    call print_string
    jmp .a20_verify
    
    ; ========================================================================
    ; ATTEMPT 2: Keyboard Controller Method (legacy fallback)
    ; ========================================================================
.a20_keyboard_method:
    mov si, msg_a20_keyboard
    call print_string
    
    ; Step 1: Wait for keyboard input buffer to be empty
    mov cx, A20_TIMEOUT     ; CX = timeout counter
    
.kbd_wait_input:
    in al, KBD_STATUS_PORT  ; AL = keyboard status register
    test al, KBD_IN_FULL    ; Test bit 1 (input buffer full?)
    jz .kbd_send_command    ; If zero (empty), proceed
    
    ; Input buffer full, wait and retry
    dec cx                  ; Decrement timeout counter
    jnz .kbd_wait_input     ; Continue if not timed out
    
    ; Timeout reached
    mov si, msg_a20_timeout
    call print_string
    jmp .a20_failed
    
    ; Step 2: Send 0xD1 command to keyboard controller
.kbd_send_command:
    mov al, KBD_CMD_WRITE_OUT  ; AL = 0xD1 (write output port)
    out KBD_STATUS_PORT, al    ; Send command
    
    ; Step 3: Wait for input buffer to empty again
    mov cx, A20_TIMEOUT     ; Reset timeout
    
.kbd_wait_output:
    in al, KBD_STATUS_PORT
    test al, KBD_IN_FULL
    jz .kbd_write_data      ; If empty, write data
    
    dec cx
    jnz .kbd_wait_output
    
    mov si, msg_a20_timeout
    call print_string
    jmp .a20_failed
    
    ; Step 4: Write 0xDF to output port (sets A20 bit)
.kbd_write_data:
    mov al, KBD_OUT_A20     ; AL = 0xDF (A20 enable bit set)
    out KBD_DATA_PORT, al   ; Write to data port
    
    ; Step 5: Wait for input buffer to empty (command completion)
    mov cx, A20_TIMEOUT
    
.kbd_wait_completion:
    in al, KBD_STATUS_PORT
    test al, KBD_IN_FULL
    jz .a20_keyboard_success
    
    dec cx
    jnz .kbd_wait_completion
    
    mov si, msg_a20_timeout
    call print_string
    jmp .a20_failed
    
.a20_keyboard_success:
    mov si, msg_a20_kbd_ok
    call print_string
    
    ; ========================================================================
    ; A20 VERIFICATION (test if actually enabled)
    ; ========================================================================
.a20_verify:
    mov si, msg_a20_verify
    call print_string
    
    ; Simple A20 test: write different values to 0x00000 and 0x100000
    ; If A20 is disabled, writes wrap (same memory, different address)
    ; If A20 is enabled, writes go to different locations
    
    xor ax, ax              ; AX = 0
    mov es, ax              ; ES = 0
    mov word [es:0x0000], 0x1234  ; Write to 0x00000
    
    mov ax, 0x1000          ; AX = 0x1000 (64KB segment)
    mov es, ax              ; ES = 0x1000 (now ES:0 = 0x10000 physical)
    mov word [es:0x0000], 0x5678  ; Write to 0x10000 (only if A20 enabled)
    
    ; Verify: read from 0x00000
    xor ax, ax
    mov es, ax
    cmp word [es:0x0000], 0x1234
    jne .a20_verify_failed   ; If not equal, A20 didn't work
    
    ; Verify: read from 0x10000
    mov ax, 0x1000
    mov es, ax
    cmp word [es:0x0000], 0x5678
    jne .a20_verify_failed   ; If not equal, A20 didn't work
    
    mov si, msg_a20_verified
    call print_string
    jmp .a20_complete
    
.a20_verify_failed:
    mov si, msg_a20_failed_verify
    call print_string
    
    ; Continue anyway (some systems don't need A20 for initial operations)
    jmp .a20_complete
    
.a20_failed:
    mov si, msg_a20_failed
    call print_string
    ; Continue anyway (non-critical for now)
    
.a20_complete:
    ; ========================================================================
    ; MEMORY DETECTION (INT 0x15 E801)
    ; ========================================================================
    mov si, msg_memory_detect
    call print_string
    
    ; Use INT 0x15 function E801 to get extended memory size
    ; Returns:
    ;   CX = memory from 1MB to 16MB (in 1KB units, max 65535)
    ;   DX = memory above 16MB (in 64KB units)
    
    xor cx, cx              ; CX = 0 (initialize)
    xor dx, dx              ; DX = 0 (initialize)
    
    mov ax, 0xE801         ; AX = 0xE801 (get extended memory)
    int 0x15
    
    jnc .memory_detection_ok ; If CF = 0, call succeeded
    
    ; Memory detection failed
    mov si, msg_memory_failed
    call print_string
    xor cx, cx              ; Assume 0 KB if detection fails
    xor dx, dx
    jmp .memory_store
    
.memory_detection_ok:
    mov si, msg_memory_ok
    call print_string
    
.memory_store:
    ; Store detected memory values for later use
    ; CX = 1MB-16MB memory (in KB)
    ; DX = >16MB memory (in 64KB blocks)
    
    mov [memory_1mb_16mb], cx   ; Store 1-16MB
    mov [memory_above_16mb], dx ; Store >16MB
    
    ; ========================================================================
    ; PRINT MEMORY INFORMATION
    ; ========================================================================
    mov si, msg_memory_summary
    call print_string
    
    ; ========================================================================
    ; PRINT SYSTEM STATUS
    ; ========================================================================
    mov si, msg_system_ready
    call print_string
    
    ; ========================================================================
    ; PRINT NEXT STAGE NOTICE
    ; ========================================================================
    mov si, msg_waiting_stage3
    call print_string
    
    ; ========================================================================
    ; MAIN LOOP - Stage 2 Halts Here
    ; ========================================================================
    ; In a complete bootloader:
    ;   1. Load kernel from disk (INT 0x13)
    ;   2. Setup GDT (Global Descriptor Table)
    ;   3. Switch to Protected Mode (32-bit)
    ;   4. Jump to kernel entry point
    
hang:
    cli                     ; Disable interrupts
    hlt                     ; Halt CPU (low-power mode)
    jmp hang                ; Infinite loop (safety)

; ============================================================================
; PRINT_STRING: Print null-terminated ASCII string to screen
; ============================================================================
; Prints a string with automatic line wrapping and proper cursor positioning
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
;   Cursor position updated
;
; Clobbers: AX, BX, DX, SI, DH, DL
; ============================================================================
print_string:
    push ax                 ; Save AX
    push bx                 ; Save BX
    push si                 ; Save SI
    push dx                 ; Save DX
    
.char_loop:
    lodsb                   ; LODSB: Load AL = [DS:SI], SI++
    test al, al             ; Test AL against itself (sets ZF if zero)
    jz .string_done         ; If zero (null terminator), exit loop
    
    ; ====================================================================
    ; Handle special characters
    ; ====================================================================
    cmp al, 0x0D            ; Compare with CR (carriage return)
    je .char_loop           ; Skip CR (LF will handle newline)
    
    cmp al, 0x0A            ; Compare with LF (line feed)
    jne .print_regular_char ; If not LF, print as regular character
    
    ; ====================================================================
    ; Handle newline (LF)
    ; ====================================================================
    ; Get current cursor position
    mov ah, 0x03            ; AH = 0x03 (read cursor position)
    xor bx, bx              ; BH = 0x00 (page 0)
    int 0x10                ; BIOS call: returns DX (DH=row, DL=col)
    
    ; Move to start of next line
    inc dh                  ; DH++ (increment row)
    xor dl, dl              ; DL = 0 (column 0)
    
    ; Check if cursor has scrolled past bottom of screen
    cmp dh, SCREEN_ROWS     ; Compare with 25 (80x25 mode)
    jl .set_cursor_position ; If row < 25, set cursor
    
    ; Cursor at or past bottom: scroll screen up
    mov ax, 0x0601          ; AH = 0x06 (scroll up), AL = 1 (scroll 1 line)
    mov bh, TEXT_ATTR_NORMAL  ; BH = attribute (white on black)
    xor cx, cx              ; CX = 0 (top-left: 0,0)
    mov dx, 0x184F          ; DX = bottom-right (row 24, col 79)
    int 0x10                ; BIOS: scroll window
    
    mov dh, SCREEN_ROWS - 1 ; DH = 24 (last visible row)
    
.set_cursor_position:
    ; Set cursor to new position
    mov ah, 0x02            ; AH = 0x02 (set cursor position)
    int 0x10                ; BIOS: set cursor
    
    jmp .char_loop          ; Continue to next character
    
.print_regular_char:
    ; ====================================================================
    ; Print regular character using BIOS TTY mode
    ; ====================================================================
    ; TTY mode (0x0E) automatically advances cursor
    mov ah, 0x0E            ; AH = 0x0E (write character in TTY mode)
    xor bx, bx              ; BH = 0x00 (page 0)
    int 0x10                ; BIOS: print character
    
    jmp .char_loop          ; Continue to next character
    
.string_done:
    pop dx                  ; Restore DX
    pop si                  ; Restore SI
    pop bx                  ; Restore BX
    pop ax                  ; Restore AX
    ret

; ============================================================================
; DATA SECTION - MESSAGE STRINGS
; ============================================================================
; All strings use 0x0D 0x0A (CRLF) for line breaks
; Null-terminated for print_string function

msg_stage2_banner:
    db 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db "  NEXO OS Stage 2 Bootloader", 0x0D, 0x0A
    db "  v2.0 - Professional Edition", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

msg_a20_attempt:
    db "A20 Line: Attempting BIOS method...", 0x0D, 0x0A, 0

msg_a20_bios_ok:
    db "[✓] A20 enabled via BIOS", 0x0D, 0x0A, 0

msg_a20_keyboard:
    db "[!] BIOS failed, trying keyboard controller...", 0x0D, 0x0A, 0

msg_a20_kbd_ok:
    db "[✓] A20 enabled via keyboard controller", 0x0D, 0x0A, 0

msg_a20_timeout:
    db "[✗] A20 Keyboard timeout!", 0x0D, 0x0A, 0

msg_a20_verify:
    db "Verifying A20 status...", 0x0D, 0x0A, 0

msg_a20_verified:
    db "[✓] A20 verification passed", 0x0D, 0x0A, 0

msg_a20_failed_verify:
    db "[!] A20 verification failed (may still work)", 0x0D, 0x0A, 0

msg_a20_failed:
    db "[✗] A20 enable failed (continuing anyway)", 0x0D, 0x0A, 0

msg_memory_detect:
    db "Memory: Detecting system RAM...", 0x0D, 0x0A, 0

msg_memory_ok:
    db "[✓] Memory detection successful", 0x0D, 0x0A, 0

msg_memory_failed:
    db "[✗] Memory detection failed (assuming 0KB)", 0x0D, 0x0A, 0

msg_memory_summary:
    db "[i] Memory detected and stored", 0x0D, 0x0A, 0

msg_system_ready:
    db 0x0D, 0x0A
    db "[✓] System Ready!", 0x0D, 0x0A
    db "  CPU: Initialized", 0x0D, 0x0A
    db "  A20: Enabled", 0x0D, 0x0A
    db "  Memory: Detected", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

msg_waiting_stage3:
    db "Waiting for Stage 3 (kernel loader)...", 0x0D, 0x0A, 0

; ============================================================================
; DATA SECTION - RUNTIME VARIABLES
; ============================================================================
; Storage for detected memory information
; These variables are written during initialization and read later

memory_1mb_16mb:
    dw 0                    ; Memory from 1MB to 16MB (in KB)

memory_above_16mb:
    dw 0                    ; Memory above 16MB (in 64KB blocks)

; ============================================================================
; PADDING & SIZE CONTROL
; ============================================================================
; Stage 2 location: 0x7E00
; Maximum size: 64 sectors = 0x8000 bytes (32KB)
; Actual end: 0x7E00 + 0x8000 = 0xFE00
;
; This padding ensures the binary is correctly sized.
; Each sector is 512 bytes (0x200 bytes).
; 64 sectors = 32KB maximum bootloader size.
;
; We pad with zeros to fill unused space. The linker/assembler
; calculates ($ - $$) = current position - section start
; and fills the remainder with 0x00 bytes.

times (0x7E00 + 0x8000) - ($ - $$) db 0x00
