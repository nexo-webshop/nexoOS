;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 16-BIT TO 32-BIT PROTECTED MODE SWITCH
; ============================================================================
;
; PURPOSE: Switch CPU from real mode (16-bit) to protected mode (32-bit)
;
; REQUIREMENTS (BEFORE calling this code):
;   ✓ GDT must be set up in memory
;   ✓ Interrupts should be disabled (CLI)
;   ✓ A20 line should be enabled
;   ✓ No paging (optional for basic setup)
;
; RESULT (AFTER this code):
;   ✓ CPU in 32-bit protected mode
;   ✓ All segment registers loaded
;   ✓ Stack pointer set up
;   ✓ Ready for 32-bit code execution
;
; MEMORY LAYOUT:
;   Real Mode (16-bit)      Protected Mode (32-bit)
;   EIP: 16-bit             EIP: 32-bit
;   Registers: 16-bit       Registers: 32-bit
;   Addressing: Segment     Addressing: Descriptor-based
;
; ============================================================================

[BITS 16]                           ; Start in 16-bit real mode
[ORG 0x2000]                        ; Bootloader location

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; STEP 0: PREREQUISITES CHECK
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Make sure you've done these BEFORE calling the mode switch:
;
; 1. Setup GDT:
;    lgdt [gdt_descriptor]        ; Load Global Descriptor Table
;
; 2. Enable A20:
;    call enable_a20             ; Enable address line 20
;
; 3. Disable interrupts:
;    cli                         ; No interrupts during switch
;
; 4. Clear direction flag:
;    cld                         ; Clear direction for string ops

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; STEP 1: LOAD GDT (GLOBAL DESCRIPTOR TABLE)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

setup_gdt:
    lgdt [gdt_descriptor]           ; Load GDT descriptor
                                    ; GDT_descriptor contains:
                                    ;   - GDT limit (size)
                                    ;   - GDT base address
                                    ;
                                    ; After LGDT:
                                    ; - CPU knows about GDT
                                    ; - Can use selectors to load segments
                                    ; - Still in real mode

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; STEP 2: SET CR0.PE BIT (PROTECTED MODE ENABLE)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

enable_protected_mode:
    mov eax, cr0                    ; Read CR0 register
                                    ; CR0 = Control Register 0
                                    ; Contains various CPU control bits
    
    or eax, 0x00000001              ; Set bit 0 (PE = Protected Enable)
                                    ; Bit layout of CR0:
                                    ; Bit 0: PE (Protected Mode Enable)
                                    ; Bit 1: MP (Math Present)
                                    ; Bit 2: EM (Emulation)
                                    ; Bit 3: TS (Task Switched)
                                    ; Bit 4: ET (Extension Type)
                                    ; Bit 5: NE (Numeric Error)
                                    ; Bit 16: WP (Write Protect)
                                    ; Bit 18: AM (Alignment Mask)
                                    ; Bit 29: NW (Not Write-through)
                                    ; Bit 30: CD (Cache Disable)
                                    ; Bit 31: PG (Paging)
    
    mov cr0, eax                    ; Write back to CR0
                                    ; After this write:
                                    ; - CPU switches to protected mode
                                    ; - BUT we're still in real mode code!
                                    ; - CPU pipeline might have stale instructions
                                    ; - MUST do FAR JUMP to flush pipeline

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; STEP 3: FAR JUMP TO FLUSH PIPELINE (CRITICAL!)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ; FAR JUMP: Absolute jump with new segment selector
    ; This is CRITICAL because:
    ; 1. CPU pipeline has real-mode instructions queued
    ; 2. Need to flush pipeline and reload CS (Code Segment)
    ; 3. CS must be loaded with valid protected mode selector
    ; 4. EIP must be valid address for protected mode code
    ;
    ; Syntax: JMP selector:offset
    ; Where:
    ;   selector = Segment selector (points to GDT entry)
    ;   offset   = 32-bit address in protected mode
    ;
    ; In protected mode:
    ; - Selector 0x08 = Code segment (usually)
    ; - Selector 0x10 = Data segment (usually)
    ; - Lower 2 bits of selector = RPL (Requested Privilege Level)
    ;   * 00 = Ring 0 (kernel)
    ;   * 01 = Ring 1
    ;   * 10 = Ring 2
    ;   * 11 = Ring 3 (user)
    ; - Bit 2 = TI (Table Indicator)
    ;   * 0 = GDT
    ;   * 1 = LDT

    jmp 0x08:protected_mode_start   ; FAR JUMP to protected mode code
                                    ; 0x08 = Code segment selector
                                    ; protected_mode_start = 32-bit offset
                                    ;
                                    ; Alternate syntax:
                                    ; db 0xEA              ; FAR JMP opcode
                                    ; dd protected_mode_start  ; 32-bit address
                                    ; dw 0x0008            ; Code selector

    ; NOTE: Code below will NOT execute!
    ; CPU has jumped to protected_mode_start
    ; This JMP never returns

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; 32-BIT PROTECTED MODE CODE SECTION
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

[BITS 32]                           ; Switch assembler to 32-bit mode
                                    ; All instructions now 32-bit
                                    ; Registers: EAX, EBX, ECX, etc.

protected_mode_start:
    ; === NOW IN 32-BIT PROTECTED MODE ===
    ;
    ; CPU state:
    ;   - PE bit = 1 (protected mode enabled)
    ;   - CS = 0x08 (code segment selector from FAR JMP)
    ;   - EIP = address of this label
    ;   - Other segments = UNDEFINED! Must be initialized
    ;   - Interrupts = DISABLED (from CLI earlier)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; STEP 4: LOAD DATA SEGMENT REGISTERS
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    mov ax, 0x10                    ; Data segment selector (0x10)
                                    ; In GDT:
                                    ; Selector 0x00 = Null (invalid)
                                    ; Selector 0x08 = Code segment
                                    ; Selector 0x10 = Data segment
    
    mov ds, ax                      ; DS (Data Segment)
    mov es, ax                      ; ES (Extra Segment)
    mov fs, ax                      ; FS (Extra)
    mov gs, ax                      ; GS (Extra)
    mov ss, ax                      ; SS (Stack Segment)
    
    ; After loading:
    ; - DS/ES/FS/GS/SS all point to data segment
    ; - CPU will use these selectors for memory addressing
    ; - All memory references go through descriptors in GDT
    ; - Flat memory model: all segments have same base (0x00000000)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; STEP 5: SETUP STACK POINTER
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    mov esp, 0x20000                ; Stack pointer = 0x20000 (128KB)
                                    ; Stack grows downward:
                                    ; PUSH: ESP -= 4
                                    ; POP:  ESP += 4
    
    ; Now stack is ready for:
    ; - Function calls (CALL/RET)
    ; - Local variables
    ; - Register saving

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; STEP 6: SETUP BASE POINTER
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    mov ebp, esp                    ; EBP = ESP (frame pointer)
                                    ; Used for:
                                    ; - Stack frame management
                                    ; - Local variable access
                                    ; - Function prologue/epilogue

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; STEP 7: CLEAR REGISTERS (OPTIONAL BUT GOOD PRACTICE)
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    xor eax, eax                    ; EAX = 0 (clear for safety)
    xor ebx, ebx                    ; EBX = 0
    xor ecx, ecx                    ; ECX = 0
    xor edx, edx                    ; EDX = 0
    xor esi, esi                    ; ESI = 0
    xor edi, edi                    ; EDI = 0

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; STEP 8: ENABLE INTERRUPTS (OPTIONAL)
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ; Uncomment if you want interrupts enabled:
    ; sti                           ; Set Interrupt Enable flag
    ;
    ; NOTE: IDT must be loaded first!
    ; If no IDT is loaded, any interrupt will triple fault and reboot
    
    ; For now, keep interrupts disabled (CLI from earlier)

    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ; NOW YOU'RE IN 32-BIT PROTECTED MODE!
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

    ; From here you can:
    ; ✓ Use 32-bit instructions
    ; ✓ Access full 4GB address space (with A20 enabled)
    ; ✓ Use descriptors for memory access
    ; ✓ Call 32-bit functions
    ; ✓ Load kernel or continue initialization

    ; Example: Jump to kernel
    ; jmp 0x10000                   ; Jump to kernel entry point
    
    ; Or call a 32-bit function
    ; call kernel_main

    ; For now, just halt
    hlt
    jmp $

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; REFERENCE: GDT STRUCTURE (must be set up beforehand)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; GDT = Global Descriptor Table
; Located in memory
; Contains segment descriptors

; Example GDT layout:
align 8
gdt_start:
    ; Descriptor 0: Null (required by architecture)
    dq 0x0000000000000000
    ; 8 bytes of zeros
    ; Cannot be used as a selector
    
    ; Descriptor 1 (Selector 0x08): Code Segment
    ; dq 0x00CF9A000000FFFF
    ; Bits explained:
    ;   0-15:   Limit low (0xFFFF)
    ;   16-31:  Base low (0x0000)
    ;   32-39:  Base mid (0x00)
    ;   40-47:  Access (0x9A)
    ;           Bit 7: P (Present) = 1
    ;           Bits 6-5: DPL (Privilege) = 00 (Ring 0)
    ;           Bit 4: S (Type) = 1 (code/data, not system)
    ;           Bit 3: E (Executable) = 1 (code)
    ;           Bit 2: DC (Direction/Conforming) = 0
    ;           Bit 1: RW (Readable) = 1
    ;           Bit 0: A (Accessed) = 0
    ;   48-51:  Limit high (0xF with granularity gives 4GB)
    ;   52-55:  Flags (0xC)
    ;           Bit 7: G (Granularity) = 1 (4KB pages)
    ;           Bit 6: D/B (Default size) = 1 (32-bit)
    ;           Bit 5: L (Long mode) = 0
    ;           Bit 4: AVL (Available) = 0
    ;   56-63:  Base high (0x00)
    
    ; Descriptor 2 (Selector 0x10): Data Segment
    ; dq 0x00CF92000000FFFF
    ; Similar to code but:
    ;   Bit 3: E = 0 (not executable, data)
    ;   Bit 1: W = 1 (writable)

gdt_end:

; GDT Descriptor (used by LGDT instruction)
gdt_descriptor:
    dw gdt_end - gdt_start - 1      ; Limit = size - 1
    dd gdt_start                    ; Base address

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; COMPLETE 16-TO-32 BIT SWITCH SEQUENCE
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Pseudocode summary:
;
; 1. CLI                              ; Disable interrupts
; 2. lgdt [gdt_descriptor]           ; Load GDT
; 3. call enable_a20                 ; Enable A20 line
; 4. mov eax, cr0                    ; Read CR0
; 5. or eax, 1                       ; Set PE bit
; 6. mov cr0, eax                    ; Write CR0
; 7. jmp 0x08:pm_start               ; FAR JUMP - CRITICAL!
;
; [BITS 32]                          ; Now 32-bit code
;
; 8. mov ax, 0x10                    ; Load data selector
; 9. mov ds, ax                      ; Setup DS
; 10. mov es, ax                     ; Setup ES
; 11. mov fs, ax                     ; Setup FS
; 12. mov gs, ax                     ; Setup GS
; 13. mov ss, ax                     ; Setup SS
; 14. mov esp, 0x20000               ; Setup stack
; 15. sti (optional)                 ; Enable interrupts
; 16. [Run 32-bit code]

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; COMMON MISTAKES TO AVOID
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; ❌ WRONG: jmp 0x2000:pm_start
;    Real mode selector values don't work in protected mode!
;    Must use GDT selectors (0x08, 0x10, etc)

; ❌ WRONG: mov eax, cr0 / or al, 1 / mov cr0, eax / next_instruction
;    Missing FAR JUMP causes CPU to execute real-mode code as protected!
;    Pipeline has stale instructions - FAR JMP is REQUIRED to flush

; ❌ WRONG: mov ax, 0x2000 / mov ds, ax
;    Real mode addressing doesn't work!
;    Use valid GDT selectors only

; ❌ WRONG: sti (before IDT setup)
;    If no IDT, any interrupt causes triple fault and reboot
;    Keep CLI until IDT is loaded

; ✓ CORRECT: Set up everything, FAR JMP, load selectors, set stack, done

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
; VERIFICATION CHECKLIST
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; After successful switch, verify:
; [ ] EIP is valid 32-bit address
; [ ] CS = 0x08 (code selector)
; [ ] DS = 0x10 (data selector)
; [ ] ESP has valid stack address
; [ ] No crash/triple fault
; [ ] 32-bit instructions execute correctly

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
