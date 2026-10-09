# VestaRV: blinky startup code
# The .program_start entry must fit in 16 bytes, so it only jumps to _init.

.section .program_start, "ax"
.global __start_RAM_program__
.type __start_RAM_program__, @function

__start_RAM_program__:
    # Jump to actual initialization (entry must be <=16 bytes)
    j _init
    nop
    nop

.section .text.init
_init:
    # Stack at the top of the 8 KiB TCM (0x8000-0x9FFF) every current chip has, which is also
    # inside Myshkin's RAM. 0x10000 put it in the NPU staging RAM, absent on fpga_default.
    li sp, 0xA000
    
    # Clear BSS section
    la a0, __bss_start
    la a1, _end
bss_clear:
    beq a0, a1, bss_done
    sw zero, 0(a0)
    addi a0, a0, 4
    j bss_clear
bss_done:
    
    # Jump to main
    jal main
    
    # Infinite loop if main returns
halt:
    j halt
