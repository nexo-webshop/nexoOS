# GUIDE FOR NexoOS

- this guide provides the steps the bootloader has to proceed before starting. if not: please report this as a bug.

under here is the BOOTSEQUENCE OVERVIEW: later, more stuff will be added.

BOOT SEQUENCE OVERVIEW
┌─────────────────────────────────────────────────────────────────┐
│ COMPUTER POWER-ON                                               │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 1️⃣  BIOS/FIRMWARE (< 1 second)                                   │
│    - POST (Power-on Self Test)                                  │
│    - Detect hardware                                            │
│    - Load MBR from disk                                         │
│    - Jump to 0x7C00 (Stage 1 bootloader)                        │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 2️⃣  STAGE 1 BOOTLOADER (512 bytes at 0x7C00)                     │
│    - Real mode (16-bit)                                         │
│    - Load Stage 2 from disk (LBA 1-7)                           │
│    - Jump to Stage 2 entry point                                │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 3️⃣  STAGE 2/3 BOOTLOADER (optional, ~3-4 sectors)               │
│    - Real mode (16-bit)                                         │
│    - More complex setup (A20, VESA, memory probe)               │
│    - Load Stage 4 from disk                                     │
│    - Jump to Stage 4 entry point (0x2000)                       │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────────┐
│ 4️⃣  STAGE 4 BOOTLOADER ⭐ (THIS COMPONENT)                       │
│    - Real mode initially (16-bit)                               │
│    - Load kernel from disk (LBA 8+)                             │
│    - Enable A20 line                                            │
│    - Setup GDT (Global Descriptor Table)                        │
│    - Setup minimal IDT (Interrupt Descriptor Table)             │
│    - Switch to protected mode (32-bit)                          │
│    - Jump to kernel entry point (0x10000)                       │
└────────────────────┬────────────────────────────────────────────┘
