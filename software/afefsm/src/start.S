/*
 * afefsm - Startup Assembly
 * VestaRV Firmware Boot Code
 */

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
    # Initialize global pointer (rv4th `call0` leaves gp=0; we must
    # set it before any gp-relative access). Disable linker relaxation
    # around the load so the assembler emits a real auipc/addi pair.
.option push
.option norelax
    la gp, __global_pointer$
.option pop

    # Initialize stack pointer to end of RAM
    li sp, 0x10000

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

halt:
    j halt
