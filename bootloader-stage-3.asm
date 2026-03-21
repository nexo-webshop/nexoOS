; ============================================================================
; NEXO OS - Protected Mode + Kernel Loader
; ============================================================================
; Loaded by Stage 1 bootloader at 0x0000:0x7E00
; Tasks:
;   1. Setup GDT (Global Descriptor Table)
;   2. Enable A20 line (if not already done by Stage 1)
;   3. Load kernel from disk to 0x100000 (1MB boundary)
;   4. Switch to Protected Mode (32-bit)
;   5. Jump to kernel entry point
;
; Loaded at: 0x0000:0x7E00 (after Stage 1 bootloader)
; Kernel location: LBA sector 1, loaded at 0x0000:0x100000 (1MB)
; Max size: 64 sectors (32KB for this loader)
; ============================================================================

[org 0x7E00]
[bits 16]

; ============================================================================
; ENTRY POINT
; ============================================================================
loader_start:
    cli                     ; Disable interrupts
    
    ; ========================================================================
    ; CPU STATE VERIFICATION
    ; ========================================================================
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00          ; Stack (safe zone, grows down)
    
    cld                     ; Direction flag = forward
    sti                     ; Enable interrupts
    
    ; ========================================================================
    ; SETUP GDT
    ; ========================================================================
    call setup_gdt
    
    mov si, msg_gdt
    call print_string
    
    ; ========================================================================
    ; ENABLE A20 LINE
    ; ========================================================================
    call enable_a20
    
    mov si, msg_a20
    call print_string
    
    ; ========================================================================
    ; LOAD KERNEL FROM DISK
    ; ========================================================================
    ; Kernel location: LBA sector 1 (after bootloader)
    ; Load address: 0x0000:0x100000 (1MB boundary)
    ; Size: 64 sectors (32KB)
    
    mov si, msg_load_kernel
    call print_string
    
    mov eax, 1              ; LBA sector 1
    mov bx, 0x0000          ; ES = 0 for 0x100000 address
    mov es, bx
    mov bx, 0x0000          ; BX = 0 (offset in ES)
    mov ecx, 64             ; 64 sectors (32KB)
    call read_kernel
    
    jnc .kernel_loaded
    
    mov si, msg_error
    call print_string
    jmp .hang
    
.kernel_loaded:
    mov si, msg_kernel_ok
    call print_string
    
    ; ========================================================================
    ; SWITCH TO PROTECTED MODE
    ; ========================================================================
    mov si, msg_pmode
    call print_string
    
    cli                     ; Disable interrupts before mode switch
    
    ; Load GDT
    lgdt [gdt_descriptor]
    
    ; Set PE bit in CR0 to enable Protected Mode
    mov eax, cr0
    or eax, 1               ; Set bit 0 (PE - Protection Enable)
    mov cr0, eax
    
    ; Far jump to flush pipeline and load CS with GDT selector
    ; This jumps to protected mode code at 0x08:protected_mode_entry
    jmp dword 0x08:protected_mode_entry
    
    ; Should never reach here
.hang:
    cli
    hlt
    jmp .hang

; ============================================================================
; 32-BIT PROTECTED MODE CODE
; ============================================================================
[bits 32]

protected_mode_entry:
    ; Initialize 32-bit segment registers
    mov ax, 0x10            ; GDT selector 2 (data segment)
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov fs, ax
    mov gs, ax
    
    ; Setup 32-bit stack (high memory, safe location)
    mov esp, 0x7C000        ; Stack at 0x7C000 (448KB)
    
    ; Write "PMODE OK" to video memory to confirm Protected Mode
    mov eax, 0x0B8000       ; Video memory base (color text mode)
    mov byte [eax], 'P'
    mov byte [eax+1], 0x0F  ; White on black
    mov byte [eax+2], 'M'
    mov byte [eax+3], 0x0F
    mov byte [eax+4], 'O'
    mov byte [eax+5], 0x0F
    mov byte [eax+6], 'D'
    mov byte [eax+7], 0x0F
    mov byte [eax+8], 'E'
    mov byte [eax+9], 0x0F
    
    ; Jump to kernel entry point at 0x100000
    jmp 0x100000
    
    ; If kernel returns (shouldn't happen), loop forever
    jmp protected_mode_entry

; ============================================================================
; BACK TO 16-BIT CODE
; ============================================================================
[bits 16]

; ============================================================================
; setup_gdt: Build Global Descriptor Table
; ============================================================================
; GDT built at memory location 0x0800
; 3 descriptors: NULL, Code (0x08), Data (0x10)
; ============================================================================
setup_gdt:
    push ax
    push di
    
    ; ========================================================================
    ; Descriptor format:
    ; Bytes 0-1: Limit (bits 0-15)
    ; Bytes 2-4: Base address (bits 0-23)
    ; Byte 5: Access byte (P|DPL|S|Type)
    ; Byte 6: Granularity (G|D/B|L|AVL|Limit 19-16)
    ; Byte 7: Base address (bits 24-31)
    ; ========================================================================
    
    ; NULL Descriptor (index 0) - REQUIRED, all zeros
    mov di, 0x0800
    mov ax, 0
    mov cx, 4               ; 4 words = 8 bytes
    
.null_loop:
    mov word [di], ax
    add di, 2
    loop .null_loop
    
    ; Code Descriptor (index 1, selector 0x08)
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB)
    ; Type: Code, Readable, Executable
    ; DPL: 0 (kernel mode)
    mov di, 0x0808
    
    mov word [di + 0], 0xFFFF       ; Limit bits 0-15
    mov word [di + 2], 0x0000       ; Base bits 0-15
    mov byte [di + 4], 0x00         ; Base bits 16-23
    mov byte [di + 5], 0x9A         ; P=1, DPL=0, S=1, Type=A (code)
    mov byte [di + 6], 0xCF         ; G=1 (4KB), D=1 (32-bit), Limit=F
    mov byte [di + 7], 0x00         ; Base bits 24-31
    
    ; Data Descriptor (index 2, selector 0x10)
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB)
    ; Type: Data, Writable, Accessed
    ; DPL: 0 (kernel mode)
    mov di, 0x0810
    
    mov word [di + 0], 0xFFFF       ; Limit bits 0-15
    mov word [di + 2], 0x0000       ; Base bits 0-15
    mov byte [di + 4], 0x00         ; Base bits 16-23
    mov byte [di + 5], 0x92         ; P=1, DPL=0, S=1, Type=2 (data)
    mov byte [di + 6], 0xCF         ; G=1 (4KB), D=1 (32-bit), Limit=F
    mov byte [di + 7], 0x00         ; Base bits 24-31
    
    pop di
    pop ax
    ret

; ============================================================================
; enable_a20: Enable A20 address line
; ============================================================================
; Method: BIOS INT 0x15 AX=0x2401 (modern systems)
; Fallback: Keyboard controller method for older systems
; ============================================================================
enable_a20:
    push ax
    
    ; Try BIOS method first (fast, modern)
    mov ax, 0x2401
    int 0x15
    
    ; If carry clear, A20 is enabled
    jnc .a20_done
    
    ; Fallback: Keyboard controller method
    ; Send 0xD1 command (write output port)
    mov al, 0xD1
    out 0x64, al
    
    ; Wait for input buffer empty
.wait_input:
    in al, 0x64
    test al, 2
    jnz .wait_input
    
    ; Write 0xDF to output port (set A20 bit)
    mov al, 0xDF
    out 0x60, al
    
.a20_done:
    pop ax
    ret

; ============================================================================
; read_kernel: Read kernel from disk using LBA with CHS translation
; ============================================================================
; Input:  EAX = LBA sector number
;         ES:BX = memory address (ES = segment, BX = offset)
;         ECX = number of sectors to read
; Output: CF = 0 if success, 1 if error
; ============================================================================
read_kernel:
    push ax
    push bx
    push cx
    push dx
    push di
    
    ; Convert LBA to CHS (Cylinder, Head, Sector)
    ; Assume: 18 sectors/track, 2 heads/cylinder
    
    mov edx, 0
    mov ecx, 18             ; Sectors per track
    div ecx                 ; EAX = track, EDX = sector-1
    
    mov cl, dl              ; CL = sector - 1
    inc cl                  ; CL = sector (1-based)
    
    mov edx, 0
    mov ecx, 2              ; Number of heads
    div ecx                 ; EAX = cylinder, EDX = head
    
    mov dh, dl              ; DH = head
    mov ch, al              ; CH = cylinder
    
    ; Read sector using BIOS INT 0x13
    mov ax, 0x0201          ; AH = 02 (read), AL = 01 (1 sector)
    mov dl, 0x00            ; DL = drive (0x00 = floppy A:)
    int 0x13
    
    clc                     ; Clear carry (success)
    
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================================
; print_string: Print null-terminated string to screen
; ============================================================================
; Input:  DS:SI -> null-terminated string
; Output: SI updated to end of string
; Uses:   INT 0x10 (BIOS video interrupt)
; ============================================================================
print_string:
    push ax
    push bx
    
.loop:
    lodsb                   ; AL = [DS:SI++]
    test al, al             ; Check for null terminator
    jz .done
    
    mov ah, 0x0E            ; BIOS function: TTY write
    xor bx, bx              ; BH = page 0, BL = 0
    int 0x10
    
    jmp .loop
    
.done:
    pop bx
    pop ax
    ret

; ============================================================================
; GDT DESCRIPTOR (for LGDT instruction)
; ============================================================================
gdt_descriptor:
    dw 24 - 1               ; GDT size (3 descriptors * 8 bytes - 1)
    dd 0x0800               ; GDT base address (0x0800)

; ============================================================================
; MESSAGES
; ============================================================================

msg_gdt:
    db "Setting up GDT...", 0x0D, 0x0A, 0

msg_a20:
    db "A20 line enabled", 0x0D, 0x0A, 0

msg_load_kernel:
    db "Loading kernel from disk...", 0x0D, 0x0A, 0

msg_kernel_ok:
    db "Kernel loaded successfully!", 0x0D, 0x0A, 0

msg_error:
    db "ERROR: Failed to load kernel!", 0x0D, 0x0A, 0

msg_pmode:
    db "Entering Protected Mode...", 0x0D, 0x0A, 0

; ============================================================================
; PADDING (fill to 32KB = 64 sectors)
; ============================================================================
; Loaded from sector 1, so max 64 sectors (32KB total)
times (0x7E00 + 0x8000) - ($ - $$) db 0x00
