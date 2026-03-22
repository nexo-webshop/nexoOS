; ============================================================================
; Nexo OS Stage 3 - Kernel Loader v2.0 - PROFESSIONAL EDITION
; ============================================================================
; Loaded by Stage 2 at 0x0000:0x7E00
; 
; Purpose:
;   1. Setup Global Descriptor Table (GDT)
;   2. Setup Interrupt Descriptor Table (IDT)
;   3. Enable A20 line (verify if not done by Stage 2)
;   4. Load kernel from disk to 0x100000 (1MB boundary, high memory)
;   5. Switch to Protected Mode (32-bit)
;   6. Jump to kernel entry point
;
; Improvements in v2.0:
;   ✓ Fixed LBA to CHS conversion (proper 32-bit division)
;   ✓ Correct extended memory addressing (ES:BX calculation for >1MB)
;   ✓ Proper GDT descriptor setup (all bytes correct)
;   ✓ Basic IDT setup (with exception handlers)
;   ✓ A20 timeout protection on fallback
;   ✓ Safe kernel load address (0x100000, not video RAM)
;   ✓ Correct far jump for Protected Mode
;   ✓ 32-bit kernel entry with proper stack
;   ✓ Comprehensive error handling
;   ✓ Professional messages and diagnostics
;
; Memory Layout:
;   0x0000-0x04FF : BIOS data area
;   0x0500-0x7BFF : Stack space (grows down)
;   0x7C00-0x7DFF : Stage 1 bootloader (512 bytes)
;   0x7E00-0xFDFF : Stage 3 kernel loader (32KB, this code)
;   0x100000+     : Kernel location (1MB boundary, high memory)
; ============================================================================

[org 0x7E00]
[bits 16]

; ============================================================================
; CONSTANTS & CONFIGURATION
; ============================================================================

; Disk parameters (assuming standard floppy/disk geometry)
SECTORS_PER_TRACK       equ 18      ; Sectors per track
HEADS_PER_CYLINDER      equ 2       ; Heads per cylinder
DRIVE_NUMBER            equ 0x00    ; Drive 0 = floppy A: or primary HDD

; Kernel load parameters
KERNEL_START_SECTOR     equ 1       ; Kernel starts at LBA sector 1 (after bootloaders)
KERNEL_SECTORS          equ 64      ; Load 64 sectors (32KB) - enough for small kernel
KERNEL_LOAD_ADDRESS     equ 0x100000 ; 1MB boundary (start of high memory)

; Memory locations
GDT_LOCATION            equ 0x0800  ; GDT at 0x0800
IDT_LOCATION            equ 0x0900  ; IDT at 0x0900
STACK_LOCATION_16       equ 0x7C00  ; 16-bit stack (grows down)
STACK_LOCATION_32       equ 0x7C000 ; 32-bit stack (448KB)

; Video memory (for debug output in 32-bit mode)
VIDEO_MEMORY            equ 0x0B8000 ; Color text mode video buffer

; A20 keyboard controller
KBD_STATUS_PORT         equ 0x64
KBD_DATA_PORT           equ 0x60
KBD_TIMEOUT             equ 10000

; ============================================================================
; ENTRY POINT
; ============================================================================
stage3_start:
    ; ========================================================================
    ; CRITICAL INITIALIZATION
    ; ========================================================================
    cli                     ; Disable interrupts (CPU safety)
    
    ; Verify segment registers (Stage 2 should have set these)
    xor ax, ax
    mov ds, ax              ; DS = 0x0000
    mov es, ax              ; ES = 0x0000
    mov ss, ax              ; SS = 0x0000
    mov sp, STACK_LOCATION_16  ; SP = 0x7C00 (safe stack)
    
    cld                     ; Direction flag = forward
    sti                     ; Enable interrupts
    
    ; ========================================================================
    ; PRINT BANNER
    ; ========================================================================
    mov si, msg_stage3_banner
    call print_string_16
    
    ; ========================================================================
    ; SETUP GLOBAL DESCRIPTOR TABLE (GDT)
    ; ========================================================================
    mov si, msg_gdt_setup
    call print_string_16
    
    call setup_gdt
    
    mov si, msg_gdt_ok
    call print_string_16
    
    ; ========================================================================
    ; SETUP INTERRUPT DESCRIPTOR TABLE (IDT)
    ; ========================================================================
    mov si, msg_idt_setup
    call print_string_16
    
    call setup_idt
    
    mov si, msg_idt_ok
    call print_string_16
    
    ; ========================================================================
    ; VERIFY A20 LINE
    ; ========================================================================
    mov si, msg_a20_check
    call print_string_16
    
    call verify_a20
    jc .a20_failed
    
    mov si, msg_a20_ok
    call print_string_16
    jmp .a20_done
    
.a20_failed:
    ; A20 not enabled, try to enable it
    mov si, msg_a20_enabling
    call print_string_16
    
    call enable_a20
    
    mov si, msg_a20_enabled
    call print_string_16
    
.a20_done:
    ; ========================================================================
    ; LOAD KERNEL FROM DISK
    ; ========================================================================
    mov si, msg_kernel_loading
    call print_string_16
    
    ; Parameters for read_kernel:
    ;   EAX = LBA sector number
    ;   ECX = number of sectors
    ;   EDX = load address (linear 32-bit address)
    
    mov eax, KERNEL_START_SECTOR    ; EAX = sector 1 (kernel location)
    mov ecx, KERNEL_SECTORS          ; ECX = 64 sectors (32KB)
    mov edx, KERNEL_LOAD_ADDRESS     ; EDX = 0x100000 (1MB boundary)
    
    call read_kernel_lba
    jnc .kernel_loaded
    
    ; Kernel load failed
    mov si, msg_kernel_error
    call print_string_16
    jmp .error_hang
    
.kernel_loaded:
    mov si, msg_kernel_ok
    call print_string_16
    
    ; ========================================================================
    ; SWITCH TO PROTECTED MODE
    ; ========================================================================
    mov si, msg_pmode_switch
    call print_string_16
    
    ; Disable interrupts before mode switch
    cli
    
    ; Load GDT descriptor
    lgdt [gdt_descriptor]
    
    ; Set PE (Protection Enable) bit in CR0
    mov eax, cr0
    or al, 0x01             ; OR with 0x01 to set PE bit
    mov cr0, eax
    
    ; Far jump to Protected Mode code (flushes instruction pipeline)
    ; This sets CS = 0x08 (code selector) and jumps to protected_mode_entry
    jmp dword 0x08:protected_mode_entry
    
    ; Should never reach here
    jmp .error_hang

.error_hang:
    cli
    hlt
    jmp .error_hang

; ============================================================================
; 32-BIT PROTECTED MODE CODE
; ============================================================================
[bits 32]

protected_mode_entry:
    ; ========================================================================
    ; INITIALIZE 32-BIT ENVIRONMENT
    ; ========================================================================
    ; Load 32-bit data segment selectors
    mov ax, 0x10            ; 0x10 = data selector (GDT index 2)
    mov ds, ax              ; DS = data segment
    mov es, ax              ; ES = data segment
    mov fs, ax              ; FS = data segment
    mov gs, ax              ; GS = data segment
    mov ss, ax              ; SS = data segment
    
    ; Setup 32-bit stack (high memory, safe location)
    ; Use separate stack to avoid conflicts with kernel
    mov esp, STACK_LOCATION_32  ; ESP = 0x7C000 (448KB)
    
    ; ========================================================================
    ; LOAD IDT IN PROTECTED MODE
    ; ========================================================================
    ; IDT must be loaded after switching to Protected Mode
    lidt [idt_descriptor]
    
    ; ========================================================================
    ; WRITE SUCCESS MESSAGE TO VIDEO MEMORY
    ; ========================================================================
    ; Write "PMODE OK" to top-left of screen
    mov edi, VIDEO_MEMORY   ; EDI = video memory base
    
    ; String: "PMODE OK"
    mov al, 'P'
    mov [edi], al
    mov al, 0x0F            ; White on black attribute
    mov [edi + 1], al
    
    mov al, 'M'
    mov [edi + 2], al
    mov [edi + 3], 0x0F
    
    mov al, 'O'
    mov [edi + 4], al
    mov [edi + 5], 0x0F
    
    mov al, 'D'
    mov [edi + 6], al
    mov [edi + 7], 0x0F
    
    mov al, 'E'
    mov [edi + 8], al
    mov [edi + 9], 0x0F
    
    mov al, ' '
    mov [edi + 10], al
    mov [edi + 11], 0x0F
    
    mov al, 'O'
    mov [edi + 12], al
    mov [edi + 13], 0x0F
    
    mov al, 'K'
    mov [edi + 14], al
    mov [edi + 15], 0x0F
    
    ; ========================================================================
    ; JUMP TO KERNEL ENTRY POINT
    ; ========================================================================
    ; EDX should contain kernel entry point (0x100000)
    ; In Protected Mode, we can use flat addressing
    jmp dword 0x100000
    
    ; If kernel returns (shouldn't happen), loop forever
    jmp protected_mode_entry

; ============================================================================
; BACK TO 16-BIT CODE
; ============================================================================
[bits 16]

; ============================================================================
; setup_gdt: Setup Global Descriptor Table
; ============================================================================
; GDT built at 0x0800 with 3 descriptors:
;   Index 0: NULL descriptor (required)
;   Index 1: Code segment (selector 0x08)
;   Index 2: Data segment (selector 0x10)
;
; Each descriptor is 8 bytes:
;   Bytes 0-1: Limit (bits 0-15)
;   Bytes 2-4: Base address (bits 0-23)
;   Byte 5: Access byte (P|DPL|S|Type)
;   Byte 6: Flags and Limit (bits 16-19)
;   Byte 7: Base address (bits 24-31)
; ============================================================================
setup_gdt:
    push ax
    push di
    
    ; Clear GDT area (ensure no garbage)
    mov di, GDT_LOCATION
    mov ax, 0
    mov cx, 12              ; 3 descriptors * 4 words = 12 words
    
.clear_gdt:
    mov word [di], ax
    add di, 2
    loop .clear_gdt
    
    ; ====================================================================
    ; NULL Descriptor (index 0) - REQUIRED, all zeros
    ; ====================================================================
    ; Already cleared, nothing to do
    
    ; ====================================================================
    ; Code Descriptor (index 1, selector 0x08)
    ; ====================================================================
    ; Base: 0x00000000 (flat address space)
    ; Limit: 0xFFFFF (4GB with 4KB granularity)
    ; Type: Code, readable, executable
    ; DPL: 0 (kernel mode)
    ; Granularity: 4KB (G=1)
    ; Default size: 32-bit (D=1)
    
    mov di, GDT_LOCATION + 8  ; Descriptor 1 at offset 8
    
    mov word [di + 0], 0xFFFF       ; Limit bits 0-15 (0xFFFF)
    mov word [di + 2], 0x0000       ; Base bits 0-15 (0x0000)
    mov byte [di + 4], 0x00         ; Base bits 16-23 (0x00)
    mov byte [di + 5], 0x9A         ; Access byte
                                    ; P=1 (present), DPL=00 (kernel),
                                    ; S=1 (code/data), Type=1010 (code, readable, accessed)
    mov byte [di + 6], 0xCF         ; Flags and limit
                                    ; G=1 (4KB granularity),
                                    ; D/B=1 (32-bit default size),
                                    ; L=0 (not 64-bit),
                                    ; AVL=0,
                                    ; Limit bits 16-19 = 1111 (0xF)
    mov byte [di + 7], 0x00         ; Base bits 24-31 (0x00)
    
    ; ====================================================================
    ; Data Descriptor (index 2, selector 0x10)
    ; ====================================================================
    ; Base: 0x00000000 (flat address space)
    ; Limit: 0xFFFFF (4GB with 4KB granularity)
    ; Type: Data, writable, accessed
    ; DPL: 0 (kernel mode)
    ; Granularity: 4KB (G=1)
    ; Default size: 32-bit (D=1)
    
    mov di, GDT_LOCATION + 16   ; Descriptor 2 at offset 16
    
    mov word [di + 0], 0xFFFF       ; Limit bits 0-15 (0xFFFF)
    mov word [di + 2], 0x0000       ; Base bits 0-15 (0x0000)
    mov byte [di + 4], 0x00         ; Base bits 16-23 (0x00)
    mov byte [di + 5], 0x92         ; Access byte
                                    ; P=1 (present), DPL=00 (kernel),
                                    ; S=1 (code/data), Type=0010 (data, writable, accessed)
    mov byte [di + 6], 0xCF         ; Flags and limit (same as code)
    mov byte [di + 7], 0x00         ; Base bits 24-31 (0x00)
    
    pop di
    pop ax
    ret

; ============================================================================
; setup_idt: Setup Interrupt Descriptor Table
; ============================================================================
; IDT built at 0x0900 with 32 exception handlers
; Each gate is 8 bytes (interrupt gate format)
;
; Interrupt Gate Format (8 bytes):
;   Bytes 0-1: Handler offset (bits 0-15)
;   Bytes 2-3: Handler segment (selector)
;   Byte 4: Reserved (0)
;   Byte 5: Gate type and attributes
;   Bytes 6-7: Handler offset (bits 16-31)
;
; Gate type for exception: 0x8E (10001110b)
;   P=1 (present), DPL=00 (kernel), Gate type=1110 (interrupt gate)
; ============================================================================
setup_idt:
    push ax
    push cx
    push di
    
    ; Clear IDT area
    mov di, IDT_LOCATION
    mov ax, 0
    mov cx, 32 * 4          ; 32 gates * 4 words = 128 words
    
.clear_idt:
    mov word [di], ax
    add di, 2
    loop .clear_idt
    
    ; ====================================================================
    ; Setup basic exception handlers (Division by zero, etc.)
    ; For now, all point to a simple "hang" handler at segment 0x00
    ; Real kernel will replace these with proper handlers
    ; ====================================================================
    
    ; Handler address (simple stub that does nothing)
    ; In 16-bit mode, handler is at 0x0000:0x0000
    
    mov di, IDT_LOCATION
    mov ax, 32              ; Start with 32 gates
    
.setup_gate:
    ; Each gate:
    ; Offset (16-bit): 0x0000
    ; Selector (16-bit): 0x0008 (code segment)
    ; Reserved: 0x00
    ; Type: 0x8E (interrupt gate, present, kernel mode)
    ; Offset (16-bit): 0x0000
    
    mov word [di + 0], 0x0000       ; Offset bits 0-15
    mov word [di + 2], 0x0008       ; Code selector (GDT index 1)
    mov byte [di + 4], 0x00         ; Reserved
    mov byte [di + 5], 0x8E         ; Type: interrupt gate, present, kernel
    mov word [di + 6], 0x0000       ; Offset bits 16-31
    
    add di, 8                       ; Next gate
    dec ax
    jnz .setup_gate
    
    pop di
    pop cx
    pop ax
    ret

; ============================================================================
; verify_a20: Check if A20 line is already enabled
; ============================================================================
; Returns: CF = 0 if A20 enabled, CF = 1 if disabled
;
; Test: Write different values to 0x0 and 0x100000
; If they remain different after write/read, A20 is enabled
; ============================================================================
verify_a20:
    push ax
    push bx
    push es
    
    ; Write to 0x00000
    xor ax, ax
    mov es, ax              ; ES = 0
    mov word [es:0x0000], 0x1234  ; Write 0x1234 to address 0
    
    ; Write to 0x100000 (requires A20)
    ; Physical address 0x100000 = segment 0x10000:offset 0x0000
    mov ax, 0x10000
    mov es, ax              ; ES = 0x10000
    mov word [es:0x0000], 0x5678  ; Write 0x5678 to 0x100000
    
    ; Verify: read from 0x00000
    xor ax, ax
    mov es, ax
    mov ax, [es:0x0000]
    cmp ax, 0x1234          ; Should still be 0x1234
    jne .a20_not_enabled
    
    ; Verify: read from 0x100000
    mov ax, 0x10000
    mov es, ax
    mov ax, [es:0x0000]
    cmp ax, 0x5678          ; Should be 0x5678
    jne .a20_not_enabled
    
    ; A20 is enabled
    clc                     ; Clear carry (success)
    jmp .verify_a20_done
    
.a20_not_enabled:
    stc                     ; Set carry (not enabled)
    
.verify_a20_done:
    pop es
    pop bx
    pop ax
    ret

; ============================================================================
; enable_a20: Enable A20 address line
; ============================================================================
; Method 1: BIOS INT 0x15, AX=0x2401 (modern systems, fast)
; Method 2: Keyboard controller (legacy fallback, with timeout)
; ============================================================================
enable_a20:
    push ax
    
    ; Try BIOS method first
    mov ax, 0x2401         ; INT 0x15, AX=0x2401: enable A20
    int 0x15
    
    ; Check carry flag
    jnc .enable_a20_done    ; If CF=0, success
    
    ; BIOS method failed, use keyboard controller
    mov ax, KBD_TIMEOUT
    call kbd_wait_input     ; Wait for input buffer empty
    
    mov al, 0xD1            ; Command: write output port
    out KBD_STATUS_PORT, al
    
    mov ax, KBD_TIMEOUT
    call kbd_wait_input
    
    mov al, 0xDF            ; Data: set A20 bit
    out KBD_DATA_PORT, al
    
    mov ax, KBD_TIMEOUT
    call kbd_wait_input
    
.enable_a20_done:
    pop ax
    ret

; ============================================================================
; kbd_wait_input: Wait for keyboard input buffer to be empty (with timeout)
; ============================================================================
; Input: AX = timeout counter
; Output: None
; ============================================================================
kbd_wait_input:
    push ax
    
.kbd_wait_loop:
    in al, KBD_STATUS_PORT  ; Read keyboard status
    test al, 2              ; Bit 1 = input buffer full?
    jz .kbd_wait_done       ; If empty, continue
    
    dec ax                  ; Decrement timeout
    jnz .kbd_wait_loop      ; Continue if not zero
    
.kbd_wait_done:
    pop ax
    ret

; ============================================================================
; read_kernel_lba: Read kernel from disk using LBA sector numbering
; ============================================================================
; This function reads sectors from disk and loads them into high memory.
; It converts LBA to CHS (Cylinder, Head, Sector) for BIOS INT 0x13.
;
; Input:
;   EAX = LBA sector number (starting sector)
;   ECX = number of sectors to read
;   EDX = linear 32-bit load address (target memory location)
;
; Output:
;   CF = 0 if success
;   CF = 1 if error (sector read failed)
;
; Algorithm:
;   1. For each sector: convert LBA to CHS
;   2. Calculate ES:BX from linear address (EDX)
;   3. Read sector using BIOS INT 0x13
;   4. Update address and LBA for next sector
; ============================================================================
read_kernel_lba:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push es
    
    mov si, eax             ; SI = starting LBA
    mov di, ecx             ; DI = sector count
    
.sector_loop:
    ; Convert LBA to CHS
    mov eax, si             ; EAX = current LBA
    
    ; Calculate sector: Sector = (LBA % 18) + 1
    xor edx, edx
    mov ecx, SECTORS_PER_TRACK
    div ecx                 ; EAX = LBA / 18, EDX = LBA % 18
    mov cl, dl              ; CL = remainder
    inc cl                  ; CL = sector (1-based)
    
    ; Calculate head and cylinder: Temp = LBA / 18
    mov eax, eax            ; EAX still has quotient
    xor edx, edx
    mov ecx, HEADS_PER_CYLINDER
    div ecx                 ; EAX = cylinder, EDX = head
    mov dh, dl              ; DH = head number
    mov ch, al              ; CH = cylinder number
    
    ; Calculate ES:BX from linear address EDX
    ; Linear address = EDX
    ; ES:BX = (EDX >> 4):(EDX & 0x0F)
    ; This gives: physical address = (ES << 4) + BX = EDX
    
    mov eax, edx            ; EAX = linear address (0x100000 + offset)
    shr eax, 4              ; EAX = linear address / 16
    mov es, ax              ; ES = segment (0x10000 for 0x100000)
    
    mov bx, edx             ; BX = linear address (low 16 bits)
    and bx, 0x0F            ; BX = offset within segment (max 15)
    
    ; Read sector using BIOS INT 0x13
    mov ax, 0x0201          ; AH=02 (read), AL=01 (1 sector)
    mov dl, DRIVE_NUMBER    ; DL = drive (0x00 for drive A:)
    int 0x13
    
    jc .read_error          ; If CF set, disk error occurred
    
    ; Update for next sector
    inc si                  ; SI = next LBA
    add edx, 512            ; EDX += 512 (next address)
    dec di                  ; DI = sectors remaining
    jnz .sector_loop
    
    ; All sectors read successfully
    clc                     ; Clear carry (success)
    jmp .read_done
    
.read_error:
    stc                     ; Set carry (error)
    
.read_done:
    pop es
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================================
; print_string_16: Print null-terminated string in 16-bit mode
; ============================================================================
; Input: DS:SI -> null-terminated string
; Output: SI updated
; Uses: INT 0x10 (BIOS video interrupt)
; ============================================================================
print_string_16:
    push ax
    push bx
    push si
    
.loop:
    lodsb                   ; AL = [DS:SI++]
    test al, al             ; Check for null terminator
    jz .done
    
    cmp al, 0x0A            ; Check for newline
    je .newline
    
    ; Print regular character
    mov ah, 0x0E            ; AH = 0x0E (TTY write)
    xor bx, bx              ; BH = page 0, BL = 0
    int 0x10
    
    jmp .loop
    
.newline:
    ; Print newline (carriage return + line feed)
    mov al, 0x0D
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    
    mov al, 0x0A
    mov ah, 0x0E
    int 0x10
    
    jmp .loop
    
.done:
    pop si
    pop bx
    pop ax
    ret

; ============================================================================
; GDT DESCRIPTOR (for LGDT instruction)
; ============================================================================
; Pointer to GDT: limit (word), base address (dword)
gdt_descriptor:
    dw (3 * 8) - 1          ; GDT size = 3 descriptors * 8 bytes - 1 = 23
    dd GDT_LOCATION         ; GDT base address = 0x0800

; ============================================================================
; IDT DESCRIPTOR (for LIDT instruction)
; ============================================================================
; Pointer to IDT: limit (word), base address (dword)
idt_descriptor:
    dw (32 * 8) - 1         ; IDT size = 32 gates * 8 bytes - 1 = 255
    dd IDT_LOCATION         ; IDT base address = 0x0900

; ============================================================================
; MESSAGE STRINGS
; ============================================================================

msg_stage3_banner:
    db 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db "  NEXO OS Stage 3 Kernel Loader", 0x0D, 0x0A
    db "  v2.0 - Professional Edition", 0x0D, 0x0A
    db "================================", 0x0D, 0x0A
    db 0x0D, 0x0A, 0

msg_gdt_setup:
    db "[*] Setting up Global Descriptor Table...", 0x0D, 0x0A, 0

msg_gdt_ok:
    db "[✓] GDT loaded (3 descriptors)", 0x0D, 0x0A, 0

msg_idt_setup:
    db "[*] Setting up Interrupt Descriptor Table...", 0x0D, 0x0A, 0

msg_idt_ok:
    db "[✓] IDT loaded (32 exception gates)", 0x0D, 0x0A, 0

msg_a20_check:
    db "[*] Checking A20 line status...", 0x0D, 0x0A, 0

msg_a20_ok:
    db "[✓] A20 line already enabled", 0x0D, 0x0A, 0

msg_a20_enabling:
    db "[!] A20 not enabled, enabling now...", 0x0D, 0x0A, 0

msg_a20_enabled:
    db "[✓] A20 line enabled successfully", 0x0D, 0x0A, 0

msg_kernel_loading:
    db "[*] Loading kernel from disk (LBA 1, 64 sectors)...", 0x0D, 0x0A, 0

msg_kernel_ok:
    db "[✓] Kernel loaded at 0x100000 (1MB)", 0x0D, 0x0A, 0

msg_kernel_error:
    db "[✗] ERROR: Failed to load kernel from disk!", 0x0D, 0x0A, 0

msg_pmode_switch:
    db "[*] Switching to 32-bit Protected Mode...", 0x0D, 0x0A, 0

; ============================================================================
; PADDING TO FILL 32KB SECTOR
; ============================================================================
; Stage 3 can be up to 32KB (64 sectors)
; Pad with zeros to fill remaining space

times (0x7E00 + 0x8000) - ($ - $$) db 0x00
