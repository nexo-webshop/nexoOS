; NexoOS Minimal Bootloader + Hardware Check
BITS 16
ORG 0x7C00

start:
    ; -------------------------
    ; 1. Controleer 64KB RAM
    ; -------------------------
    mov ax, 0x0000
    mov es, ax
    mov bx, 0xFFFF
    mov al, [es:bx] ; lees laatste byte van eerste 64KB
    ; Als dit een fout geeft, BIOS stopt al vaak, verder testen is moeilijk

    ; -------------------------
    ; 2. Controleer x86 CPU (16-bit support)
    ; -------------------------
    ; BIOS draait al in x86 real mode → gegarandeerd aanwezig

    ; -------------------------
    ; 3. Controleer VGA compatibiliteit
    ; -------------------------
    mov ax, 0x0013 ; video mode 13h (320x200x256)
    int 0x10
    jc vga_fail
    ; terug naar text mode 80x25
    mov ax, 0x0003
    int 0x10

    ; -------------------------
    ; 4. Controleer opslag (512 bytes vrije ruimte)
    ; -------------------------
    ; moeilijk exact te checken in BIOS, we checken alleen of floppy/HD kan gelezen worden
    mov ah, 0x02   ; read sector
    mov al, 1      ; 1 sector
    mov ch, 0      ; cylinder 0
    mov cl, 2      ; sector 2 (boot sector is 1)
    mov dh, 0      ; head 0
    mov dl, 0x80   ; eerste HDD
    mov es, 0x8000
    mov bx, 0x0000
    int 0x13
    jc disk_fail

    ; -------------------------
    ; 5. Legacy BIOS / CSM-mode check
    ; -------------------------
    ; als BIOS bootsector draait, legacy BIOS / CSM is actief → gegarandeerd aanwezig

    ; -------------------------
    ; Alles ok → verder booten
    ; -------------------------
    mov si, msg_ok
    jmp print_msg

vga_fail:
    mov si, msg_vga
    jmp print_msg

disk_fail:
    mov si, msg_disk
    jmp print_msg

print_msg:
    mov ah, 0x0E
.print_loop:
    lodsb
    cmp al, 0
    je halt
    int 0x10
    jmp .print_loop

halt:
    cli
    hlt

; -------------------------
; Boodschappen
; -------------------------
msg_ok   db "Hardware OK. NexoOS start...",0
msg_vga  db "Fout: VGA niet gevonden!",0
msg_disk db "Fout: Disk check mislukt!",0

; -------------------------
; Bootsector pad
; -------------------------
times 510-($-$$) db 0
dw 0xAA55
