;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; nexoOS BOOTLOADER STAGE 4 - VERSION 2
; ============================================================================
; 
; PURPOSE:
;   ✓ Load kernel.bin from disk (LBA-based)
;   ✓ Enable A20 address line (access memory > 1MB)
;   ✓ Setup Global Descriptor Table (GDT)
;   ✓ Switch to 32-bit protected mode
;   ✓ Jump to kernel.bin entry point
;
; MEMORY MAP:
;   0x00000-0x07BFF : Real mode / BIOS / available
;   0x07C00-0x07DFF : Stage 1 Bootloader (MBR) - 512 bytes
;   0x07E00-0x1FFFF : Available
;   0x02000-0x0FFFF : Stage 4 execution area
;   0x10000-0x27FFF : ⭐ KERNEL LOADED HERE (kernel.bin) - 64KB
;   0x28000+        : Available for kernel use
;
; EXECUTION CONTEXT:
;   - Called from Stage 3 bootloader (usually at 0x2000:0x0000)
;   - Real mode (16-bit), interrupts disabled
;   - Stack at 0x2FFF0 downward
;   - BIOS services available (INT 13h for disk, INT 10h for video)
;
; DISK LAYOUT:
;   LBA 0        : MBR (Stage 1) - 512 bytes
;   LBA 1-7      : Available (for Stage 2/3)
;   LBA 8-135    : kernel.bin (128 blocks = 64KB) ⭐
;   LBA 136+     : Filesystem / data
;
; ============================================================================

[BITS 16]                           ; 16-bit real mode
[ORG 0x2000]                        ; Loaded at 0x2000 by Stage 3

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; CONFIGURATION - Customize for your system
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

KERNEL_LBA_START    equ 8              ; kernel.bin starts at LBA 8
KERNEL_SIZE_BLOCKS  equ 128            ; kernel.bin size: 128 * 512 = 64KB
KERNEL_LOAD_ADDR    equ 0x10000        ; Physical address 0x10000 (64KB)
KERNEL_SEGMENT      equ 0x1000         ; Segment for loading (0x1000:0x0000 = 0x10000)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; GDT CONFIGURATION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

GDT_LIMIT           equ gdt_end - gdt_start - 1
GDT_CODE_SELECTOR   equ 0x08            ; Code segment selector
GDT_DATA_SELECTOR   equ 0x10            ; Data segment selector

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; STAGE 4 ENTRY POINT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

stage4_start:
    cli                             ; Disable interrupts
    cld                             ; Clear direction flag
    
    ; Setup temporary stack (real mode)
    mov ax, 0x2000
    mov ss, ax
    mov sp, 0xFFF0                  ; Stack from 0x2FFF0 downward
    
    ; === STEP 1: Print boot messages ===
    call print_string
    db 13, 10, "=================================", 13, 10, 0
    
    call print_string
    db "nexoOS Stage 4 Bootloader", 13, 10, 0
    
    call print_string
    db "Loading kernel.bin...", 13, 10, 0
    
    ; === STEP 2: Load kernel.bin from disk ===
    call load_kernel_from_disk
    cmp al, 0
    jne .kernel_load_error
    
    call print_string
    db "✓ Kernel loaded at 0x10000", 13, 10, 0
    
    ; === STEP 3: Enable A20 address line ===
    call print_string
    db "Enabling A20 line...", 13, 10, 0
    
    call enable_a20_line
    
    call print_string
    db "✓ A20 line enabled", 13, 10, 0
    
    ; === STEP 4: Setup GDT ===
    call print_string
    db "Setting up GDT...", 13, 10, 0
    
    lgdt [gdt_descriptor]
    
    call print_string
    db "✓ GDT loaded", 13, 10, 0
    
    ; === STEP 5: Switch to protected mode ===
    call print_string
    db "Entering protected mode...", 13, 10, 0
    
    call switch_to_protected_mode
    
    ; Should never return here (we enter protected mode)
    jmp $

.kernel_load_error:
    call print_string
    db 13, 10, "ERROR: Failed to load kernel!", 13, 10, 0
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Load kernel.bin from disk via LBA
;
; Uses INT 13h function 0x42 (Extended LBA Read)
; Returns: AL = 0 (success) or AL != 0 (failure)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

load_kernel_from_disk:
    push bp
    mov bp, sp
    push bx
    push cx
    push dx
    push si
    
    ; === Build Disk Address Packet (DAP) ===
    ; DAP Structure (16 bytes):
    ;   +0: size (16)
    ;   +1: reserved (0)
    ;   +2-3: number of sectors
    ;   +4-5: buffer offset
    ;   +6-7: buffer segment
    ;   +8-11: LBA low
    ;   +12-15: LBA high
    
    mov byte [dap_size], 16
    mov byte [dap_reserved], 0
    mov word [dap_sectors], KERNEL_SIZE_BLOCKS
    mov word [dap_buffer_off], 0x0000
    mov word [dap_buffer_seg], KERNEL_SEGMENT
    mov dword [dap_lba_low], KERNEL_LBA_START
    mov dword [dap_lba_high], 0
    
    ; === Call INT 13h, Function 0x42 ===
    mov ah, 0x42                    ; Extended read function
    mov dl, 0x80                    ; Drive 0x80 (first hard disk / USB)
    mov si, dap                     ; DS:SI -> DAP structure
    int 0x13
    
    ; Check result
    jnc .load_success
    
    ; Carry flag set = error
    mov al, 1                       ; Error code
    jmp .load_done
    
.load_success:
    mov al, 0                       ; Success
    
.load_done:
    pop si
    pop dx
    pop cx
    pop bx
    pop bp
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Enable A20 address line
;
; Method: Keyboard Controller (most reliable)
; Allows access to memory addresses beyond 1MB (bit 20 and above)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

enable_a20_line:
    push ax
    
    ; Disable keyboard
    call .wait_input_empty
    mov al, 0xAD                    ; Keyboard disable command
    out 0x64, al
    
    ; Read controller output port
    call .wait_input_empty
    mov al, 0xD0                    ; Read output port command
    out 0x64, al
    
    call .wait_output_full
    in al, 0x60                     ; Read output port data
    push ax                         ; Save it
    
    ; Write output port with A20 bit set
    call .wait_input_empty
    mov al, 0xD1                    ; Write output port command
    out 0x64, al
    
    call .wait_input_empty
    pop ax                          ; Restore data
    or al, 0x02                     ; Set bit 1 (A20)
    out 0x60, al                    ; Write back
    
    ; Re-enable keyboard
    call .wait_input_empty
    mov al, 0xAE                    ; Keyboard enable command
    out 0x64, al
    
    pop ax
    ret
    
.wait_input_empty:
    push ax
    mov cx, 0x10000
.wait_input_loop:
    in al, 0x64                     ; Read keyboard status
    test al, 0x02                   ; Check input buffer full bit
    jz .wait_input_ok
    loop .wait_input_loop
.wait_input_ok:
    pop ax
    ret
    
.wait_output_full:
    push ax
    mov cx, 0x10000
.wait_output_loop:
    in al, 0x64                     ; Read keyboard status
    test al, 0x01                   ; Check output buffer full bit
    jnz .wait_output_ok
    loop .wait_output_loop
.wait_output_ok:
    pop ax
    ret

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Switch to 32-bit protected mode
;
; This function:
;   1. Sets CR0.PE bit (Protected Enable)
;   2. Does far jump to flush pipeline and load CS with code segment
;   3. Enters 32-bit protected mode code
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

switch_to_protected_mode:
    ; Disable interrupts (already done, but be safe)
    cli
    
    ; Set CR0.PE (Protected Mode Enable) bit
    mov eax, cr0
    or eax, 0x00000001              ; Set PE bit
    mov cr0, eax
    
    ; Far jump to 32-bit code
    ; This flushes CPU pipeline and loads new code segment selector
    db 0xEA                         ; JMP FAR (absolute far jump)
    dw protected_mode_code          ; Offset in protected mode
    dw GDT_CODE_SELECTOR            ; Selector (0x08 = code segment)
    
    ; Never reached
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 32-BIT PROTECTED MODE CODE
; ============================================================================
; From here on, CPU is in 32-bit protected mode
; We're running at privilege level 0 (kernel mode)
; GDT is loaded and functional
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[BITS 32]

protected_mode_code:
    ; === Setup segment registers ===
    mov ax, GDT_DATA_SELECTOR       ; 0x10 = data segment
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax
    
    ; === Setup new stack for protected mode ===
    mov esp, 0x20000                ; Stack at 128KB (plenty of space)
    
    ; === Print message that we're in protected mode ===
    ; (Optional - requires real video/serial output code)
    ; For now, we'll skip this to avoid complexity
    
    ; === Jump to kernel ===
    ; kernel.bin is loaded at 0x10000
    ; We do a far jump with code segment selector
    
    jmp GDT_CODE_SELECTOR:KERNEL_LOAD_ADDR
    
    ; If kernel returns (it shouldn't), halt
    hlt
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; FUNCTION: Print string (16-bit real mode only)
;
; Call: call print_string
;       db "text", 0
;       (next instruction)
;
; Uses: BIOS INT 10h (video output)
; Modifies: AX, BX, SI
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

print_string:
    pop si                          ; Get return address (string pointer)
    
.print_loop:
    lodsb                           ; Load byte from [DS:SI], increment SI
    test al, al                     ; Check for null terminator
    jz .print_done
    
    mov ah, 0x0E                    ; BIOS teletype output
    mov bh, 0                       ; Page 0
    int 0x10
    jmp .print_loop
    
.print_done:
    jmp si                          ; Jump back to caller

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; DATA STRUCTURES & TABLES
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; === Disk Address Packet (DAP) for LBA Read ===
dap:
    dap_size:       db 0x10         ; Size of DAP structure (16 bytes)
    dap_reserved:   db 0            ; Reserved byte
    dap_sectors:    dw 0            ; Number of sectors to read
    dap_buffer_off: dw 0            ; Offset of transfer buffer
    dap_buffer_seg: dw 0            ; Segment of transfer buffer
    dap_lba_low:    dd 0            ; LBA address (low 32 bits)
    dap_lba_high:   dd 0            ; LBA address (high 32 bits)

; === Global Descriptor Table (GDT) ===
; GDT entries are 8 bytes each
; Format: [Base 15:0] [Limit 15:0] [Base 23:16] [Access] [Limit 19:16] [Base 31:24]

align 8, db 0
gdt_start:
    ; Null descriptor (required by architecture)
    dq 0x0000000000000000
    
    ; Code segment descriptor
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB with 4K pages)
    ; Present=1, DPL=00 (ring 0), Type=1 (code/data)
    ; Executable=1, Readable=1, Access=1
    ; Granularity=1 (4K), Default=1 (32-bit)
    ; Binary: 00CF 9A00 0000 FFFF
    dq 0x00CF9A000000FFFF
    
    ; Data segment descriptor
    ; Base: 0x00000000, Limit: 0xFFFFF (4GB with 4K pages)
    ; Present=1, DPL=00 (ring 0), Type=0 (data)
    ; Writable=1, Access=1
    ; Granularity=1 (4K), Default=1 (32-bit)
    ; Binary: 00CF 9200 0000 FFFF
    dq 0x00CF92000000FFFF

gdt_end:

; === GDT Descriptor for LGDT instruction ===
gdt_descriptor:
    dw GDT_LIMIT                    ; Size of GDT minus 1
    dd gdt_start                    ; Base address of GDT

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; PADDING & ALIGNMENT
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Align to 512-byte boundary (standard sector size)
align 512, db 0

; End marker
stage4_end:
    db 0x55, 0xAA                   ; Boot signature (optional for stage 4)
