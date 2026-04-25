/*
 * looptest - Startup Assembly
 * Minimal: jump straight to main (no BSS clear, no stack init needed).
 * main() is an infinite loop, no trap.
 */

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
