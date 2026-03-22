;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; nexoOS BOOTLOADER STAGE 4 - FINAL VERSION
; ============================================================================
; 
; PURPOSE - Load kernel.bin and enter protected mode:
;   ✓ Load kernel.bin from disk (INT 13h LBA read)
;   ✓ Enable A20 address line (memory > 1MB)
;   ✓ Setup GDT (Global Descriptor Table)
;   ✓ Switch to 32-bit protected mode
;   ✓ Jump to kernel.bin entry point at 0x10000
;
; DISK LAYOUT (LBA sectors):
;   LBA 0        : MBR (Stage 1) - 512 bytes
;   LBA 1-7      : Available
;   LBA 8-135    : kernel.bin (128 blocks = 64KB) ⭐
;   LBA 136+     : Filesystem
;
; MEMORY MAP:
;   0x00000-0x1FFFF : Low memory (128KB)
;   0x10000-0x27FFF : ⭐ KERNEL.BIN LOADED HERE (64KB)
;   0x20000+        : Stack & heap
;
; ============================================================================

[BITS 16]
[ORG 0x2000]

; === CONFIGURATION ===
KERNEL_LBA_START    equ 8              ; kernel.bin starts at LBA 8
KERNEL_SIZE_BLOCKS  equ 128            ; 128 * 512 = 64KB
KERNEL_LOAD_ADDR    equ 0x10000        ; Load address
KERNEL_SEGMENT      equ 0x1000         ; Segment for load (0x1000:0x0000 = 0x10000)

GDT_CODE_SEL        equ 0x08
GDT_DATA_SEL        equ 0x10

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; ENTRY POINT - Stage 4 starts here
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

stage4_entry:
    cli                             ; Disable interrupts
    cld                             ; Clear direction flag
    
    ; Setup stack
    mov ax, 0x2000
    mov ss, ax
    mov sp, 0xFFF0
    
    ; Print boot message
    call print_msg
    db 13, 10, "nexoOS Stage 4 Bootloader", 13, 10, 0

    ; === STEP 1: Load kernel.bin from disk ===
    call print_msg
    db "Loading kernel.bin from LBA 8...", 13, 10, 0
    
    call load_kernel_bin
    cmp al, 0
    jne .load_error
    
    call print_msg
    db "OK: kernel.bin loaded at 0x10000", 13, 10, 0

    ; === STEP 2: Enable A20 line ===
    call print_msg
    db "Enabling A20 line...", 13, 10, 0
    
    call enable_a20
    
    call print_msg
    db "OK: A20 enabled", 13, 10, 0

    ; === STEP 3: Load GDT ===
    call print_msg
    db "Setting up GDT...", 13, 10, 0
    
    lgdt [gdt_descriptor]
    
    call print_msg
    db "OK: GDT loaded", 13, 10, 0

    ; === STEP 4: Enter protected mode ===
    call print_msg
    db "Entering 32-bit protected mode...", 13, 10, 0
    
    cli
    mov eax, cr0
    or eax, 0x00000001              ; Set PE (Protected Enable) bit
    mov cr0, eax
    
    ; Far jump to 32-bit code
    db 0xEA                         ; JMP FAR
    dw pm_start
    dw GDT_CODE_SEL

.load_error:
    call print_msg
    db "ERROR: Failed to load kernel!", 13, 10, 0
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Load kernel.bin from disk via INT 13h LBA Read
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

load_kernel_bin:
    push bp
    mov bp, sp
    
    ; Setup Disk Address Packet (DAP)
    mov byte [dap_size], 16
    mov byte [dap_reserved], 0
    mov word [dap_sectors], KERNEL_SIZE_BLOCKS
    mov word [dap_buffer_off], 0x0000
    mov word [dap_buffer_seg], KERNEL_SEGMENT
    mov dword [dap_lba_low], KERNEL_LBA_START
    mov dword [dap_lba_high], 0
    
    ; Call INT 13h, function 0x42 (Extended LBA Read)
    mov ah, 0x42
    mov dl, 0x80                    ; Drive 0x80 (first hard disk)
    mov si, dap                     ; DS:SI -> DAP
    int 0x13
    
    ; Check carry flag (0=success, 1=error)
    jnc .load_ok
    mov al, 1                       ; Error
    jmp .load_done
    
.load_ok:
    mov al, 0                       ; Success
    
.load_done:
    pop bp
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Enable A20 address line via keyboard controller
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

enable_a20:
    push ax
    
    ; Wait for input buffer empty
    mov cx, 0x10000
.wait1:
    in al, 0x64
    test al, 0x02
    jz .cmd1
    loop .wait1
    
.cmd1:
    mov al, 0xAD                    ; Disable keyboard
    out 0x64, al
    
    ; Wait for input buffer empty
    mov cx, 0x10000
.wait2:
    in al, 0x64
    test al, 0x02
    jz .cmd2
    loop .wait2
    
.cmd2:
    mov al, 0xD0                    ; Read output port
    out 0x64, al
    
    ; Wait for output buffer full
    mov cx, 0x10000
.wait3:
    in al, 0x64
    test al, 0x01
    jnz .read_port
    loop .wait3
    
.read_port:
    in al, 0x60                     ; Read data
    push ax
    
    ; Wait for input buffer empty
    mov cx, 0x10000
.wait4:
    in al, 0x64
    test al, 0x02
    jz .cmd3
    loop .wait4
    
.cmd3:
    mov al, 0xD1                    ; Write output port
    out 0x64, al
    
    ; Wait for input buffer empty
    mov cx, 0x10000
.wait5:
    in al, 0x64
    test al, 0x02
    jz .write_port
    loop .wait5
    
.write_port:
    pop ax
    or al, 0x02                     ; Set A20 bit
    out 0x60, al
    
    ; Wait for input buffer empty
    mov cx, 0x10000
.wait6:
    in al, 0x64
    test al, 0x02
    jz .cmd4
    loop .wait6
    
.cmd4:
    mov al, 0xAE                    ; Enable keyboard
    out 0x64, al
    
    pop ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Print string (16-bit real mode)
; Format: call print_msg
;         db "message", 0
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

print_msg:
    pop si                          ; Get string pointer from stack
    
.loop:
    lodsb                           ; Load byte
    test al, al
    jz .done
    
    mov ah, 0x0E                    ; BIOS teletype
    mov bh, 0
    int 0x10
    jmp .loop
    
.done:
    jmp si                          ; Return to caller

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 32-BIT PROTECTED MODE CODE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[BITS 32]

pm_start:
    ; Load data segment selector
    mov ax, GDT_DATA_SEL
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; Setup new stack
    mov esp, 0x20000
    
    ; Jump to kernel.bin entry point at 0x10000
    jmp GDT_CODE_SEL:KERNEL_LOAD_ADDR

    ; Should never return
    hlt
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; DATA SECTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; === Disk Address Packet ===
dap:
    dap_size:       db 16
    dap_reserved:   db 0
    dap_sectors:    dw 0
    dap_buffer_off: dw 0
    dap_buffer_seg: dw 0
    dap_lba_low:    dd 0
    dap_lba_high:   dd 0

; === Global Descriptor Table ===
align 8
gdt_start:
    ; Null descriptor
    dq 0x0000000000000000
    
    ; Code segment (selector 0x08)
    dq 0x00CF9A000000FFFF
    
    ; Data segment (selector 0x10)
    dq 0x00CF92000000FFFF
gdt_end:

; === GDT Descriptor ===
gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; === Padding ===
align 512
stage4_end:
