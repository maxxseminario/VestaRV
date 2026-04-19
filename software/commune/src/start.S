//; Only save registers in IRQ wrapper that are to be saved by the caller in
//; the RISC-V ABI, with the excepetion of the stack pointer. The IRQ handler
//; will save the rest if necessary. I.e. skip x3, x4, x8, x9, and x18-x27.
//#define ENABLE_FASTIRQ

//; Includes
#include "custom_ops.S"
#include "periph.S"

//; Globals
.global main
#ifndef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
.global IRQ_master_handler_C
#endif	// #ifndef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
.global __start_RAM_program__

//; Start code
//; This is put in the .program_start section so that it will be what the bootloader calls when it finishes loading the program from the SPI flash
.section .program_start
__start_RAM_program__:
	//; WARNING: this may be no longer than 16 bytes (4 uncompressed instructions)
	//; Note: Interrupts have already been globally disabled in the boot ROM code
	//; To re-enable interrupts, use the irq.c library or use picorv32_maskirq_insn(zero, zero)

#ifdef RedefinedStackPointerInit
	//; Set the stack pointer
	li sp, RedefinedStackPointerInit
#endif

	//; Call the either the main function or the _start function
	//; If you use the -nostdlib linker flag, you must call main
	//; If you do not use the -nostdlib linker flag, you must call _start, which will internally call main
	//; The makefiles should handle defining __nostdlib__ for you
#ifdef __nostdlib__
	call main
#else
	call _start
#endif
	//; If the main function returns, cause a TRAP condition
	ebreak

//; The master IRQ handler
//; This is put in a special region of the .text section to ensure it is the first thing in the .text section, thereby placing it at the proper address that the CPU will call when an interrupt occurs
.section .text.master_interrupt
IRQ_master_handler_asm:
	//; This function is located at RamStartAddress + 16. TODO: Verify the location is the same as PROGADDR_IRQ in generate.py
#ifdef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
	//; When an interrupt occurs on the CPU, it immediately stores the pre-interrupt program counter to q0, and the address to the appropriate IVT element in register x10/a0. It also automatically saves all CPU registers to a separate register file in a single cycle before calling this interrupt handler

	//; Load the value of the RAM word at the address stored in x10/a0. The data stored in that RAM word is a pointer to the ISR function
	lw a0, 0(a0)

	//; Jump to the ISR function. (This sets register x1/ra (return address) to the current program counter and then jumps execution to the location stored in a0)
	jalr ra, a0, 0
#else	// #ifdef ENABLE_IRQ_FAST_CONTEXT_SWITCHING
	//; When an interrupt occurs on the CPU, it immediately stores the pre-interrupt program counter to q0, and the IRQ flag bits to q1
#ifdef ENABLE_IRQ_QREGS
	/* Save CPU registers to RAM */
	picorv32_setq_insn(q2, ra)	//; Save the pre-interrupt return address to q2
	picorv32_setq_insn(q3, sp)	//; Save the pre-interrupt stack pointer to q3
#endif	//; #ifdef ENABLE_IRQ_QREGS
	
	//; Save the rest of the registers
	addi sp, sp, -128	//; Allocate 128 bytes of memory to the stack to make space for the CPU register copies
#ifdef ENABLE_FASTIRQ
	sw x5,   5*4(sp)
	sw x6,   6*4(sp)
	sw x7,   7*4(sp)
	sw x10, 10*4(sp)
	sw x11, 11*4(sp)
	sw x12, 12*4(sp)
	sw x13, 13*4(sp)
	sw x14, 14*4(sp)
	sw x15, 15*4(sp)
	sw x16, 16*4(sp)
	sw x17, 17*4(sp)
	sw x28, 28*4(sp)
	sw x29, 29*4(sp)
	sw x30, 30*4(sp)
	sw x31, 31*4(sp)
#else	//; #ifdef ENABLE_FASTIRQ
	sw x3,   3*4(sp)
	sw x4,   4*4(sp)
	sw x5,   5*4(sp)
	sw x6,   6*4(sp)
	sw x7,   7*4(sp)
	sw x8,   8*4(sp)
	sw x9,   9*4(sp)
	sw x10, 10*4(sp)
	sw x11, 11*4(sp)
	sw x12, 12*4(sp)
	sw x13, 13*4(sp)
	sw x14, 14*4(sp)
	sw x15, 15*4(sp)
	sw x16, 16*4(sp)
	sw x17, 17*4(sp)
	sw x18, 18*4(sp)
	sw x19, 19*4(sp)
	sw x20, 20*4(sp)
	sw x21, 21*4(sp)
	sw x22, 22*4(sp)
	sw x23, 23*4(sp)
	sw x24, 24*4(sp)
	sw x25, 25*4(sp)
	sw x26, 26*4(sp)
	sw x27, 27*4(sp)
	sw x28, 28*4(sp)
	sw x29, 29*4(sp)
	sw x30, 30*4(sp)
	sw x31, 31*4(sp)
#endif	//; #ifdef ENABLE_FASTIRQ
	
	/* Call the master interrupt handler C function */
#ifdef ENABLE_IRQ_QREGS
	//; The IRQ flag bits are stored in q1, need to move them to a0 (argument #0)
	//; argument 0: 32-bit IRQ flag bits
	picorv32_getq_insn(a0, q1)
#else	//; #ifdef ENABLE_IRQ_QREGS
	//; The IRQ flag bits are stored in x4 (tp), need to move them to a0 (argument #0)
	addi a0, tp, 0
#endif	//; #ifdef ENABLE_IRQ_QREGS

	//; Call the IRQ C function (takes one uint32_t argument: the 32-bit IRQ flag bits. Returns void)
	call IRQ_master_handler_C	//; Store the return address (which is the current program counter + 2 or 4 bytes) to register ra (return address), jump to IRQ_master_handler_C
	
	/* Restore CPU registers */
#ifdef ENABLE_FASTIRQ
	lw x5,   5*4(sp)
	lw x6,   6*4(sp)
	lw x7,   7*4(sp)
	lw x10, 10*4(sp)
	lw x11, 11*4(sp)
	lw x12, 12*4(sp)
	lw x13, 13*4(sp)
	lw x14, 14*4(sp)
	lw x15, 15*4(sp)
	lw x16, 16*4(sp)
	lw x17, 17*4(sp)
	lw x28, 28*4(sp)
	lw x29, 29*4(sp)
	lw x30, 30*4(sp)
	lw x31, 31*4(sp)
#else	//; #ifdef ENABLE_FASTIRQ
	lw x3,   3*4(sp)
	lw x4,   4*4(sp)
	lw x5,   5*4(sp)
	lw x6,   6*4(sp)
	lw x7,   7*4(sp)
	lw x8,   8*4(sp)
	lw x9,   9*4(sp)
	lw x10, 10*4(sp)
	lw x11, 11*4(sp)
	lw x12, 12*4(sp)
	lw x13, 13*4(sp)
	lw x14, 14*4(sp)
	lw x15, 15*4(sp)
	lw x16, 16*4(sp)
	lw x17, 17*4(sp)
	lw x18, 18*4(sp)
	lw x19, 19*4(sp)
	lw x20, 20*4(sp)
	lw x21, 21*4(sp)
	lw x22, 22*4(sp)
	lw x23, 23*4(sp)
	lw x24, 24*4(sp)
	lw x25, 25*4(sp)
	lw x26, 26*4(sp)
	lw x27, 27*4(sp)
	lw x28, 28*4(sp)
	lw x29, 29*4(sp)
	lw x30, 30*4(sp)
	lw x31, 31*4(sp)
#endif	//; #ifdef ENABLE_FASTIRQ
	
#ifdef ENABLE_IRQ_QREGS
	picorv32_getq_insn(ra, q2)	//; Restore return address
	picorv32_getq_insn(sp, q3)	//; Restore the stack pointer
#endif	//; #ifdef ENABLE_IRQ_QREGS

#endif	//; #ifdef ENABLE_IRQ_FAST_CONTEXT_SWITCHING

	/* Return to prior location of program counter */
	picorv32_retirq_insn()
