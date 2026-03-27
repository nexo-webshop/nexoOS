bits 32
global kernel_main

kernel_main:

    cli                         ; geen interrupts tijdens init

; ================================
; CORE INIT
; ================================
    call init_segments
    call init_stack
    call init_idt
    call init_timer
    call init_keyboard
    call init_vga

    sti                         ; 🔥 interrupts AAN

; ================================
; MAIN LOOP
; ================================
main_loop:

    call update
    call render

    hlt                         ; CPU efficiënt
    jmp main_loop
