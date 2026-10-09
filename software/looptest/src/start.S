# VestaRV: looptest startup code
# Jumps straight to main; no BSS clear and no stack use, since main is an infinite loop.

.section .program_start, "ax"
.global __start_RAM_program__
.type __start_RAM_program__, @function

__start_RAM_program__:
    j _init
    nop
    nop

.section .text.init
_init:
    li sp, 0xA000           # top of the 8 KiB TCM; see software/blinky/src/start.S
    jal main
halt:
    j halt
