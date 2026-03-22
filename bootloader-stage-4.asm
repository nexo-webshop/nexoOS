;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; nexoOS Bootloader Stage 4
; ============================================================================
; Purpose: Final bootloader stage
;   - Load kernel from disk
;   - Switch to protected mode (32-bit)
;   - Setup GDT and IDT
;   - Jump to kernel entry point
;
; Context: Runs after stage 3 in real mode (16-bit)
; Assumptions: 
;   - Stage 3 left us at ~0x2000 (or configurable STAGE3_BASE)
;   - We have access to BIOS services (int 13h for disk read)
;   - Kernel is at fixed disk location (LBA block)
; ============================================================================

[BITS 16]
[ORG 0x2000]  ; Stage 4 starts here (after stage 3)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CONSTANTS & CONFIGURATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

KERNEL_LBA_START    equ 8              ; Kernel starts at LBA block 8
KERNEL_SIZE_BLOCKS  equ 128            ; Kernel is 128 blocks (64KB)
KERNEL_LOAD_ADDR    equ 0x10000        ; Load kernel at 64KB (0x10000)

KERNEL_ENTRY_ADDR   equ 0x10000        ; Kernel entry point (same as load addr)

GDT_LIMIT           equ gdt_end - gdt_start - 1
IDT_LIMIT           equ 255            ; IDT limit (256 entries)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ENTRY POINT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

stage4_start:
    cli                             ; Disable interrupts
    cld                             ; Clear direction flag
    
    ; Setup temporary stack
    mov ax, 0x2000
    mov ss, ax
    mov sp, 0xFFF0                  ; Stack from 0x2FFF0 downward
    
    call print_msg
    db "nexoOS Stage 4: Loading kernel...", 0x0D, 0x0A, 0x00
    
    ; Load kernel from disk
    call load_kernel
    
    cmp al, 0
    jne .kernel_load_failed
    
    call print_msg
    db "nexoOS Stage 4: Kernel loaded successfully!", 0x0D, 0x0A, 0x00
    
    call print_msg
    db "nexoOS Stage 4: Switching to protected mode...", 0x0D, 0x0A, 0x00
    
    ; Prepare for protected mode transition
    call setup_protected_mode
    
    ; Switch to protected mode
    call switch_to_protected_mode
    
    ; *** We should never reach here in real mode ***
    jmp $
    
.kernel_load_failed:
    call print_msg
    db "ERROR: Failed to load kernel!", 0x0D, 0x0A, 0x00
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; KERNEL LOADING FROM DISK (INT 13h LBA READ)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

load_kernel:
    push bp
    mov bp, sp
    push bx
    push cx
    push dx
    push si
    push di
    
    ; Setup Disk Address Packet (DAP) for LBA read
    ; Format:
    ;   Offset 0: Size of DAP (16 bytes)
    ;   Offset 1: Reserved (0)
    ;   Offset 2: Number of sectors to read (word)
    ;   Offset 4: Buffer offset (word)
    ;   Offset 6: Buffer segment (word)
    ;   Offset 8: LBA address (dword)
    ;   Offset 12: LBA high part (dword) - for > 2TB
    
    mov byte [dap_size], 16          ; DAP size
    mov byte [dap_reserved], 0       ; Reserved
    mov word [dap_sectors], KERNEL_SIZE_BLOCKS  ; Number of sectors
    
    ; Set buffer address (0x1000:0x0000 -> physical 0x10000)
    mov word [dap_buffer_off], 0x0000
    mov word [dap_buffer_seg], 0x1000
    
    ; Set LBA start address
    mov dword [dap_lba_low], KERNEL_LBA_START
    mov dword [dap_lba_high], 0      ; High 32 bits of LBA
    
    ; Call INT 13h, function 42h (Extended LBA Read)
    mov ah, 0x42                     ; Read LBA
    mov dl, 0x80                     ; Drive 0x80 (first hard disk)
    mov si, dap                      ; DS:SI -> DAP
    int 0x13
    
    jnc .load_success
    
    ; If carry flag set, load failed
    mov al, 1
    jmp .load_exit
    
.load_success:
    mov al, 0
    
.load_exit:
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop bp
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; SETUP PROTECTED MODE (GDT, IDT, ENABLE A20)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

setup_protected_mode:
    push bp
    mov bp, sp
    
    ; Enable A20 line (keyboard controller method)
    call enable_a20
    
    ; Load GDT
    lgdt [gdt_descriptor]
    
    ; Load temporary IDT (will be replaced by kernel)
    lidt [idt_descriptor]
    
    pop bp
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ENABLE A20 ADDRESS LINE (Keyboard Controller)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

enable_a20:
    push ax
    
    ; Disable interrupts during A20 setup
    cli
    
    ; Read keyboard controller status
    mov al, 0xAD                     ; Disable keyboard
    out 0x64, al
    
    ; Read controller output port
    mov al, 0xD0
    out 0x64, al
    
    ; Wait for data
    mov cx, 0x10000
.wait_read:
    in al, 0x64
    test al, 0x01
    jnz .read_ok
    loop .wait_read
    
.read_ok:
    in al, 0x60                      ; Read data
    push ax
    
    ; Write controller output port
    mov al, 0xD1
    out 0x64, al
    
    ; Wait for write
    mov cx, 0x10000
.wait_write:
    in al, 0x64
    test al, 0x02
    jz .write_ok
    loop .wait_write
    
.write_ok:
    pop ax
    or al, 0x02                      ; Set A20 bit
    out 0x60, al
    
    ; Re-enable keyboard
    mov al, 0xAE
    out 0x64, al
    
    pop ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; SWITCH TO PROTECTED MODE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

switch_to_protected_mode:
    push bp
    mov bp, sp
    
    ; Disable interrupts
    cli
    
    ; Set PE bit in CR0 to enable protected mode
    mov eax, cr0
    or eax, 0x00000001              ; Set PE (bit 0)
    mov cr0, eax
    
    ; Far jump to flush pipeline and enter protected mode
    ; This jumps to 0x08:protected_mode_start
    db 0xEA                         ; JMP FAR opcode
    dw protected_mode_start
    dw 0x0008                       ; Code segment selector (GDT offset 0x08)
    
    ; We should never return here
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PROTECTED MODE CODE (32-bit)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[BITS 32]

protected_mode_start:
    ; Setup segment registers with data segment selector (0x10 = GDT offset 0x10)
    mov ax, 0x10                    ; Data segment selector
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; Setup new stack in protected mode
    mov esp, 0x20000                ; Stack at 128KB
    
    ; Clear screen (optional, if video mode available)
    ; For now, just proceed to kernel
    
    ; *** JUMP TO KERNEL ENTRY POINT ***
    ; Kernel is loaded at KERNEL_LOAD_ADDR (0x10000)
    
    jmp 0x08:0x10000                ; Far jump to kernel with code segment
    
    ; Should never return
    hlt
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; UTILITY: PRINT MESSAGE (16-bit real mode)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

print_msg:
    ; Call convention: address of message on stack (from CALL print_msg)
    pop si                          ; Get message address
    
.print_loop:
    lodsb                           ; Load byte from [DS:SI]
    test al, al                     ; Check for null terminator
    jz .print_done
    
    cmp al, 0x0A                    ; Check for newline
    je .print_newline
    
    mov ah, 0x0E                    ; BIOS teletype output
    mov bh, 0                       ; Page number
    int 0x10
    jmp .print_loop
    
.print_newline:
    mov ah, 0x0E
    mov al, 0x0D                    ; Carriage return
    int 0x10
    mov al, 0x0A                    ; Line feed
    mov ah, 0x0E
    int 0x10
    jmp .print_loop
    
.print_done:
    jmp si                          ; Return to caller

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; DISK ADDRESS PACKET (DAP) for LBA Read
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

dap:
    dap_size:       db 0x10         ; Size of DAP
    dap_reserved:   db 0            ; Reserved
    dap_sectors:    dw 0            ; Sectors to read
    dap_buffer_off: dw 0            ; Buffer offset
    dap_buffer_seg: dw 0            ; Buffer segment
    dap_lba_low:    dd 0            ; LBA low 32 bits
    dap_lba_high:   dd 0            ; LBA high 32 bits

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; GLOBAL DESCRIPTOR TABLE (GDT)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

align 8
gdt_start:
    ; Null descriptor (required)
    dq 0x0000000000000000
    
    ; Code segment descriptor
    ; Base: 0x00000000, Limit: 0xFFFFF, Present, Ring 0, Code/Read
    dq 0x00CF9A000000FFFF
    
    ; Data segment descriptor
    ; Base: 0x00000000, Limit: 0xFFFFF, Present, Ring 0, Data/Write
    dq 0x00CF92000000FFFF

gdt_end:

gdt_descriptor:
    dw GDT_LIMIT                    ; GDT limit
    dd gdt_start                    ; GDT base address

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; INTERRUPT DESCRIPTOR TABLE (IDT) - Temporary, minimal
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

align 8
idt_start:
    times 256 dq 0                  ; 256 null IDT entries (placeholder)
idt_end:

idt_descriptor:
    dw IDT_LIMIT                    ; IDT limit
    dd idt_start                    ; IDT base address

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PADDING TO FILL STAGE 4 BLOCK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Pad to 512 bytes (standard bootloader sector size)
; In practice, you may want a larger stage 4
align 512
stage4_end:

; Signature for bootloader validation (optional)
db 0x55, 0xAA                       ; Boot signature at end of sector
