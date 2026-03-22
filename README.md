# nexoOS
mostly C but what we want to do: create the best OS and build python above it and make it as most python as possible!
# MAIN information
this OS is in pre-alpha development, you can experience bugs and errors. we're working on it...
this OS is as most as possible based on python. it can contain many bugs as the OS is in pre-alpha development
# current state of the OS
- 100% assembly
# EVERY WEEK SEVERAL UPDATES!
# latest update (21/3/2026)
build 000.004
- in this build we did a big bugfix update so we can get further with the next step to make this OS work!
Bootloader (0.00.00.05):
- fixed a bug where the CPUID flag check was wrong
- fixed a bug where the position of the cursor wasn't saved after reading
- fixed a bug where the video mode check 0x0003 was missing
- fixed a bug where Stack SP = 0x7C00, this was border dangerous
- fixed a bug where DS was not garanteed for string operations

Bootloader stage 2 (0.00.00.02)
- fixed a bug where the A20 line had an infinite timeout
- fixed a bug where there was no fallback handling
- fixed a bug where there was no saved memory
- fixed a bug where the memory detection didn't make comments
- fixed a bug where the padding calculation was wrong
- fixed a bug where the cursor was trash on the screen
- fixed a bug where there was no CR/LF handling
- fixed a bug where the A20 method was unknown

Bootloader stage 3 (0.00.00.01)
- initial release
# ENJOY!

# the size of our OS:
- 18KB
