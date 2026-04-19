//#define ENABLE_QREGS

//; Only save registers in IRQ wrapper that are to be saved by the caller in
//; the RISC-V ABI, with the excepetion of the stack pointer. The IRQ handler
//; will save the rest if necessary. I.e. skip x3, x4, x8, x9, and x18-x27.

//#undef ENABLE_FASTIRQ

//; Includes
#include "custom_ops.S"
#include "periph.S"

//; Defines
.equ DELAY, 1500
.equ CS_FLASH_MASK_INV, ~CS_FLASH_MASK
.equ BOOT_MASK_INV, ~BOOT_MASK

//; Globals
.global main

//; Main code
.section .text
SpiBoot:
	//; Loads the program stored on the SPI flash into RAM, then executes it
	//; This is what is executed first when the system is reset
	
	//; Disable all interrupts and set them to high priority
	li a0, SYSTEM_BASE
	sw zero, IRQEN_OFFSET(a0)
	sw zero, IRQPRI_OFFSET(a0)

	//; Initialize the stack pointer
	li sp, StackPointerInit	//; This is the stack pointer, x2

	//; Turn on all memory by setting MEMPWRCR to zero
	sw zero, MEMPWRCR_OFFSET(a0)	//; (a0 = SYSTEM_BASE) Clear MEMPWRCR
	
	//; Set a0 to contain the SPI0 base address
	li a0, SPI0_BASE
	
	//; Set a1 to contain the Port 1 base address
	li a1, GPIO1_BASE
	
	//; Set pin BOOT on GPIO1 to input mode and CS_FLASH to output mode
	li a2, CS_FLASH_MASK	//; CS_FLASH bit is '1', BOOT bit is '0'
	sb a2, P1DIR_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a2 to P1DIR

	//; Set P1SEL so that all the Port 1 pins are configured properly in GPIO mode or peripheral mode
	li a2, P1SEL_BOOT_VAL
	sb a2, P1SEL_OFFSET(a1)
	
	//; Set a2 to contain the current RAM address, beginning with the RAM start address
	li a2, RamStartAddress
	
	//; Set a3 to contain the end RAM address
	li a3, RamStartAddress + RamSize
	
	//; Port 1 OR bit mask for CS. Set a4 as all '0's, except the CS bit is a '1'
	li a4, CS_FLASH_MASK	//; Update this with a '1' for CS
	
	//; Port 1 AND bit mask for CS. Set a5 as all '1's, except the CS bit is a '0'
	//;li a5, CS_FLASH_MASK_INV	//; Update this with a '0' for CS, and the rest are '1's

checkBootPin:
	//; Check if the BOOT pin is set to forth interpreter mode or SPI flash mode. The BOOT pin must reset to GPIO input mode
	//; If BOOT = '0': Launch the forth interpreter from ROM
	//; If BOOT = '1': Launch the program stored in the SPI flash memory
	lw a5, P1IN_OFFSET(a1)	//; Load P1IN into a5
	andi a5, a5, BOOT_MASK	//; a5 &= BOOT_MASK, so only the BOOT_BIT can be a '1'
	beqz a5, main	//; If BOOT = '0', launch the forth interpreter from ROM, otherwise continue and load the program in the SPI flash
	
	//; Set the peripheral enable register for SCK, MOSI, MISO, and CS
//;setupPins:
	//;li a6, SPI0_P1DIR_MASK	//; Update this with '1's for SCK0, MOSI0, and MISO0
	//;lw a7, P1SEL_OFFSET(a1)	//; (a1 = GPIO1_BASE) Load value of P1SEL into a7
	//;or a7, a7, a6	//; a7 |= a6 (a6 temporarily contains the OR bit mask for SCK, MOSI, and MISO)
	//;and a7, a7, a5	//; a7 &= a5 (a5 contains the AND bit mask for CS)
	//;sw a7, P1SEL_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a7 to P1SEL
	
	//;//; Set P1OUT to make CS drive high (deasserted)
	//;sw a4, P1OUTS_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTS, setting the CS_FLASH bit
	
	//;//; Set P1DIR to make CS an output (SCK, MOSI, MISO data directions are controlled by SPI0 peripheral)
	//;lw a7, P1DIR_OFFSET(a1)	//; (a1 = GPIO1_BASE) Load value of P1DIR into a7
	//;or a7, a7, a4	//; a7 |= a4 (a4 contains the OR bit mask for CS)
	//;sw a7, P1DIR_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a7 to P1DIR
	
	//; Clear SPI0SR status register
setupSPI_1:
	not t0, zero
	sw t0, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Clear SPI0SR
	
	//; Set up SPI0 with SPIMODE3 (CPHA = 1, CPOL = 1), DL = 8 bits (SPIDL = "00"), MSB first, enabled, fast baud
	li a6, 0x00C3	//; The SPI0CR register value
	sw a6, SPI0CR_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0CR
	
	//; Assert CS (set CS low)
assertCS_1:
	sw a4, P1OUTC_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTC, clearing the CS_FLASH bit
	
	//; Send command over SPI to wake the SPI flash from deep power down mode
sendWakeup:
	li a6, 0xAB	//; The SPI flash command to wake from deep power down mode
	sw a6, SPI0TX_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0TXBUF
	
	//; Wait for the command to finish sending
.align 2
wait1:
	lw a7, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, 0x4	//; (0x4 = BIT2, SPIBUSY is at BIT2) Is SPIBUSY still active?
	bnez a7, wait1	//;	Go back to wait1 if SPIBUSY = 1 (transfer not yet complete)
	
	//; Deassert CS (set CS high)
deassertCS_1:
	sw a4, P1OUTS_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTS, setting the CS_FLASH bit
	
	//; Delay for at least 30 us to allow the SPI flash to wake up
	li a6, DELAY	//;	The number of delay cycles to perform
.align 2
delay1:
	addi a6, a6, -1	//; Subtract 1 from a6 every delay cycle (is this sign extended???)
	bnez a6, delay1	//; Go back to delay1 if the delay counter in a6 has not reached zero yet
	
	//; Assert CS (set CS low)
assertCS_2:
	sw a4, P1OUTC_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTC, clearing the CS_FLASH bit
	
	//; Send command over SPI to set to read mode
sendReadCmd:
	li a6, 0x0B	//; The SPI flash command for read mode (high frequency)
	sw a6, SPI0TX_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0TXBUF
	
	//; Wait for the command to finish sending
.align 2
wait2:
	lw a7, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, 0x4	//; (0x4 = BIT2, SPIBUSY is at BIT2) Is SPIBUSY still active?
	bnez a7, wait2	//;	Go back to wait2 if SPIBUSY = 2 (transfer not yet complete)
	
	//; Set up SPI0 with SPIMODE3 (CPHA = 1, CPOL = 1), DL = 32 bits (SPIDL = "10"), MSB first, swap bytes, enabled, fast baud
setupSPI_2:
	li a6, 0x100CB	//; The SPI0CR register value
	sw a6, SPI0CR_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0CR
	
	//; Send the 24-bit start address with a dummy byte on the end
sendAddress:
	//slli a6, a2, 8	//; Shift a2 (RamStartAddress) left by 8 and store in a6 (to shift up the 24-bit address and add a dummy byte)
	//sw a6, SPI0TX_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0TXBUF
	// This was modified so that the program begins at address 0x000000 of the SPI Flash
	sw zero, SPI0TX_OFFSET(a0)	//; (a0 = SPI0_BASE) Store 0x00000000 to SPI0TXBUF
	
	//; Wait for the command to finish sending
.align 2
wait3:
	lw a7, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, 0x4	//; (0x4 = BIT2, SPIBUSY is at BIT2) Is SPIBUSY still active?
	bnez a7, wait3	//;	Go back to wait3 if SPIBUSY = 2 (transfer not yet complete)
	
	//; Clear SPI0SR
clearSR_1:
	sw t0, SPI0SR_OFFSET(a0)
	
	//; Send a 0x00000000 out over SPI, during which time the SPI flash will respond with the first word
sendZero_1:
	sw zero, SPI0TX_OFFSET(a0)	//; Store 0 to SPI0TXBUF
	
.align 2
loadloop:
	//; Wait for the transfer to complete with SPITXCIFG (BIT1)
	lw a7, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, 0x2	//; (0x2 = BIT1, SPITXCIFG is at BIT1)
	beqz a7, loadloop	//;	Go back to loadloop if SPITXCIFG = 0 (not ready for new byte)
	
	//; Clear SPI0SR
clearSR_2:
	sw t0, SPI0SR_OFFSET(a0)
	
	//; Read the SPI RX buffer and store it in the next RAM location
readRXandStoreAndIncrement:
	//;//; This is assuming that the bytes stored in the SPI flash are NOT swapped and are in order (if commented out, see the next non-commented code)
	//;lw a7, SPI0RX_OFFSET(a0)	//; The bytes are currently flip-flopped (b3 & b2 & b1 & b0 <= b0 & b1 & b2 & b3)
	//;//;sw a7, SPI0TX_OFFSET(a0)	//; Send back what was just received (for debugging)
	//;sb a7, 3(a2)	//; a2 is the next RAM location to save to
	//;srli a7, a7, 8	//; Shift a7 right by 8
	//;sb a7, 2(a2)
	//;srli a7, a7, 8	//; Shift a7 right by 8
	//;sb a7, 1(a2)
	//;srli a7, a7, 8	//; Shift a7 right by 8
	//;sb a7, 0(a2)
	//;lw a7, 0(a2)
	//;sw a7, SPI0TX_OFFSET(a0)	//; Send back what was just received (for debugging)
	//;addi a2, a2, 4	//; Add 4 (32 bits, 4 bytes) to the next RAM location
	
	//; This is assuming that for every four bytes stored in the SPI flash, byte0 and byte3 are swapped, and byte1 and byte2 are swapped. (if commented out, see the previous non-commented code)
	lw a7, SPI0RX_OFFSET(a0)	//; a7 now contains the memory to be stored in the next RAM location
	sw a7, SPI0TX_OFFSET(a0)	//; Send back what was just received (for debugging)
	sw a7, 0(a2)				//; Store the data to RAM at the next RAM location
	addi a2, a2, 4				//; Add 4 (32 bits, 4 bytes) to the next RAM location
	
	//; If the next RAM location is < the RAM END, loop back
loopback:
	bltu a2, a3, loadloop

wait4:
	//; Wait for the transfer to complete with SPITXCIFG (BIT1)
	lw a7, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, 0x2	//; (0x2 = BIT1, SPITXCIFG is at BIT1)
	beqz a7, wait4	//;	Go back to wait4 if SPITXCIFG = 0 (not ready for new byte)
	
	//; Deassert CS (set CS high)
deassertCS_2:
	sw a4, P1OUTS_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTS, setting the CS_FLASH bit
	
	//; Set up SPI0 with SPIMODE3 (CPHA = 1, CPOL = 1), DL = 8 bits (SPIDL = "00"), MSB first, enabled, fast baud
setupSPI_3:
	li a6, 0x00C3	//; The SPI0CR register value
	sw a6, SPI0CR_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0CR
	
	//; Assert CS (set CS low)
assertCS_3:
	sw a4, P1OUTC_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTC, clearing the CS_FLASH bit
	
	//; Send command to SPI flash to put it in deep power down mode
sendSleepCmd:
	li a6, 0xB9	//; The SPI flash command for deep power down mode
	sw a6, SPI0TX_OFFSET(a0)	//; (a0 = SPI0_BASE) Store a6 to SPI0TXBUF

	//; Wait for the command to finish sending
.align 2
wait5:
	lw a7, SPI0SR_OFFSET(a0)	//; (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, 0x4	//; (0x4 = BIT2, SPIBUSY is at BIT2) Is SPIBUSY still active?
	bnez a7, wait5	//;	Go back to wait5 if SPIBUSY = 1 (transfer not yet complete)
	
	//; Deassert CS (set CS high)
deassertCS_3:
	sw a4, P1OUTS_OFFSET(a1)	//; (a1 = GPIO1_BASE) Store a4 (CS_FLASH_MASK) to P1OUTS, setting the CS_FLASH bit
	
	//; Initialize all registers
initRegs:
	li x1, 0
	li sp, StackPointerInit	//; This is the stack pointer, x2
	li x3, 0
	li x4, 0
	li x5, 0
	li x6, 0
	li x7, 0
	li x8, 0
	li x9, 0
	li x10, 0
	li x11, 0
	li x12, 0
	li x13, 0
	li x14, 0
	li x15, 0
	li x16, 0
	li x17, 0
	li x18, 0
	li x19, 0
	li x20, 0
	li x21, 0
	li x22, 0
	li x23, 0
	li x24, 0
	li x25, 0
	li x26, 0
	li x27, 0
	li x28, 0
	li x29, 0
	li x30, 0
	li x31, 0
	
	//; Jump to the beginning of the RAM
jumpToMain:
	j RamProgramStartAddress