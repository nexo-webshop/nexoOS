bits 16
org 0x7C00

boot:

    jmp short start
    nop

; ================================
; BPB (ONGEWIJZIGD)
; ================================
OEMname:           db "mkfs.fat"
bytesPerSector:    dw 512
sectPerCluster:    db 1
reservedSectors:   dw 1
numFAT:            db 2
numRootDirEntries: dw 224
numSectors:        dw 2880
mediaType:         db 0xF0
numFATsectors:     dw 9
sectorsPerTrack:   dw 18
numHeads:          dw 2
numHiddenSectors:  dd 0
numSectorsHuge:    dd 0
driveNum:          db 0
reserved:          db 0
signature:         db 0x29
volumeID:          dd 0x2D7E5A1A
volumeLabel:       db "NO NAME    "
fileSysType:       db "FAT12   "

start:

    cli                         ; 🔥 FIX: interrupts uit

    xor ax, ax
    mov ds, ax
    mov es, ax

    mov [bootdrv], dl

; ----------------
; STACK FIX (VEILIG!)
; ----------------
    mov ax, 0x9000
    mov ss, ax
    mov sp, 0xFFFF

; ----------------
; VIDEO MODE
; ----------------
    mov ax, 0x0013
    int 0x10

; ----------------
; LOAD STAGE 2
; ----------------
    mov dl, [bootdrv]

.load_stage2:

    mov ah, 0x02
    mov al, 1              ; 1 sector
    mov ch, 0
    mov dh, 0
    mov cl, 2
    mov bx, 0x8000         ; 🔥 VEILIGER dan label

    int 0x13
    jc .retry

    jmp 0x0000:0x8000      ; FAR jump

.retry:
    mov dl, 0x80
    jmp .load_stage2

bootdrv: db 0

times 510 - ($ - $$) db 0
dw 0xAA55
org 0x8000
bits 16

stage2:

    cli

    xor ax, ax
    mov ds, ax
    mov es, ax

    mov ax, 0x9000
    mov ss, ax
    mov sp, 0xFFFF

    sti; ----------------
; LOAD KERNEL (MEER ROBUUST)
; ----------------
    mov dl, [bootdrv]

    mov ah, 0x02
    mov al, 10             ; sectors
    mov ch, 0
    mov dh, 0
    mov cl, 3
    mov bx, 0x1000

    int 0x13
    jc disk_error

    jmp 0x0000:0x1000

disk_error:
    cli
    hlt
