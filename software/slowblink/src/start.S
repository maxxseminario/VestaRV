# VestaRV: slowblink startup code
# Jumps straight to main; identical to the gpiotoggle and looptest startup.

.section .program_start, "ax"
.global __start_RAM_program__
.type __start_RAM_program__, @function

__start_RAM_program__:
    j _init
    nop
    nop

.section .text.init
_init:
    li sp, 0x10000
    jal main
halt:
    j halt
