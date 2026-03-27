bits 16
org 0x7C00

start:

    cli
    xor ax, ax
    mov ds, ax
    mov es, ax

    mov si, msg_start
    call print

; ================================
; CHECK 1: BIOS aanwezig (implicit)
; ================================
; Als we hier draaien → BIOS boot OK

    mov si, msg_bios_ok
    call print

; ================================
; CHECK 2: RAM >= 1MB (INT 12h)
; ================================
    int 0x12            ; AX = KB onder 1MB

    cmp ax, 640         ; minimaal 640KB conventioneel
    jb fail_ram

    mov si, msg_ram_ok
    call print

; ================================
; CHECK 3: A20 LINE (>=1MB toegang)
; ================================
    call check_a20
    cmp ax, 1
    jne fail_a20

    mov si, msg_a20_ok
    call print

; ================================
; CHECK 4: BOOTSECTOR SIZE (implicit)
; ================================
; BIOS laadt exact 512 bytes → OK

    mov si, msg_storage_ok
    call print

; ================================
; SUCCESS
; ================================
    mov si, msg_success
    call print

hang:
    hlt
    jmp hang

; ================================
; FAIL HANDLERS
; ================================
fail_ram:
    mov si, msg_ram_fail
    call print
    jmp halt_fail

fail_a20:
    mov si, msg_a20_fail
    call print
    jmp halt_fail

halt_fail:
    cli
    hlt
    jmp halt_fail

; ================================
; A20 CHECK (klassiek)
; ================================
check_a20:

    push ds
    push es

    xor ax, ax
    mov ds, ax
    mov es, ax

    mov si, 0x0500
    mov di, 0x0510

    mov al, [si]
    push ax

    mov byte [si], 0x00
    mov byte [di], 0xFF

    cmp byte [si], 0xFF
    jne .enabled

    mov ax, 0
    jmp .done

.enabled:
    mov ax, 1

.done:
    pop bx
    mov [si], bl

    pop es
    pop ds

    ret

; ================================
; PRINT (BIOS TTY)
; ================================
print:
    mov ah, 0x0E

.next:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .next

.done:
    ret

; ================================
; STRINGS
; ================================
msg_start:       db "Hardware check...", 13,10,0
msg_bios_ok:     db "[OK] BIOS detected", 13,10,0
msg_ram_ok:      db "[OK] RAM >= 640KB", 13,10,0
msg_ram_fail:    db "[FAIL] Not enough RAM", 13,10,0
msg_a20_ok:      db "[OK] A20 enabled (>=1MB)", 13,10,0
msg_a20_fail:    db "[FAIL] A20 line disabled", 13,10,0
msg_storage_ok:  db "[OK] Boot sector (512B)", 13,10,0
msg_success:     db "[SUCCESS] System compatible", 13,10,0

times 510 - ($ - $$) db 0
dw 0xAA55
