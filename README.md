# nexoOS
mostly C but we want to have an OS with mostly Python in it!
# MAIN information
this OS is in pre-alpha development, you can experience bugs and errors. we're working on it...
this OS is as most as possible based on python. it can contain many bugs as the OS is in pre-alpha development
as we are moving this development to something else. we will direct you to NexoOS. (yes, the dot to). our new OS is based on linux. we are creating the best with you. those bootloaders can be used for your own use, under the GNU-3 license. thanks for being with us!
# current state of the OS
- 100% assembly
# EVERY WEEK SEVERAL UPDATES!
# latest update (22/3/2026)
build 000.006
- in this build we did a big bugfix update so we can get further with the next step to make this OS work!
Bootloader (0.00.00.05):
- fixed a bug where the CPUID flag check was wrong
- fixed a bug where the position of the cursor wasn't saved after reading
- fixed a bug where the video mode check 0x0003 was missing
- fixed a bug where Stack SP = 0x7C00, this was border dangerous
- fixed a bug where DS was not garanteed for string operations

Bootloader stage 2 (0.00.00.03)
- fixed a bug with stack pointer
- fixed a bug with A20 timeout hang
- fixed a bug with A20 fallback reports
- fixed a bug where there was no A20 verification
- fixed a bug where there was cursor wrapping
- fixed a bug with memory storage

Bootloader stage 3 (0.00.00.02)
- fixed a bug where the LBA to CHS was completely wrong
- fixed a bug where the A20 keyboard fallback could take infinite time
- fixed a bug where the kernel load was not in the CPU but in the GPU
- fixed a bug where ES:BX was not corrently for 0x100000
- fixed a bug where GDT description byte 6 was wrong
- fixed a bug where the kernel jump was unsafe
- fixed a bug where there was no IDT setup
- fixed a bug where there was stack overlap risk

Bootloader stage 4 (0.00.00.01)
- initial release
# ENJOY!

# the size of our OS:
- 29KB
