#include "myshkin_s.h"




//001 0000 1000 1100 0000
#define SPI_CR_INIT 0x108C0 // Initial value for SPI Flash Control Register - 8 bit transfers

//001 0000 1000 1000 1000
#define SPI_CR_LOADBEEF 0x108C8 // Initial value for SPI Flash Control Register - 32 bit transfers 

// Boot by polling instead of interrupts 
#define SPI_TCIF_MASK           0x02 // SPI Transfer Complete Interrupt Flag
#define SPITEIF_MASK            0x01 // Mask for SPI Transfer Complete Interrupt Flag

// SPI Flash Slave Commands
#define FLASH_SLAVE_PU          0xAB // Flash Slave Power Up Command
#define FLASH_SLAVE_SRREAD      0xD7 // Flash Slave Status Register Read Command
#define FLASH_SLAVE_HFREAD      0x0B // Flash Slave High Frequency Read Command
#define FLASH_SLAVE_PU_DELAY    4000 // at least 30 us delay (in cycles) (40 us with 100MHz clock)
#define FLASH_SLAVE_PD          0xB9 // Flash Slave Power Down Command

# For dir, '1' means input on xcelium, write '1' in assembly for output 
#define P1_SEL_BOOT             (GPIO0_MISO_MASK | GPIO0_MOSI_MASK | GPIO0_SCK_MASK | GPIO0_TRAP_MASK) // Set GPIO Select Register for boot mode (MISO and BOOT to alt function, rest to GPIO)
#define SPI0_DIR_MASK           GPIO0_MISO_MASK  
//#define P1_DIR_BOOT             (GPIO0_MISO_MASK | GPIO0_BOOT_MASK) // Inputs 
//define P1_DIR_BOOT             (GPIO0_MOSI_MASK | GPIO0_CS_MASK | GPIO0_SCK_MASK) // Inputs 
#define P1_DIR_BOOT             (GPIO0_CS_MASK | GPIO0_TRAP_MASK) // CSFlash bit 1, Boot 0

// Globals 
.global main

    .section .text
    .globl _start
_start:

spi_flash_boot:
    // Upon chip reset, chip will load program from SPI Flash memory to RAM

    //System Setup 
    li a0, PERIPH_SYSTEM0_BASE
    sw zero, SYS_IRQ_CR(a0) // Disable all interrupts
    sw zero, SYS_BLOCK_PWR(a0) // Power on all blocks
    li sp, SP_INIT_VAL // Initialize Stack Pointer to the top of RAM

    // Set Periphearl Base Addresses
    li a0, PERIPH_SPI0_BASE
    li a1, PERIPH_GPIO0_BASE

    //Get ready for SPI Flash Setup / RV4th Boot
    # sb zero, GPIO_PxREN(a1) // Disable GPIO Pullup/Pulldown Resistors
    li a2, P1_DIR_BOOT     // Set GPIO Direction Register for Flash (output)
    sb a2, GPIO_PxDIR(a1)   // Set GPIO Direction Register to output for CS Flash 
    li a2, P1_SEL_BOOT      // Set GPIO PSEL for boot mode
    sb a2, GPIO_PxSEL(a1)   // Set GPIO Select Register for boot mode

    //Load Constants 
    li a2, RAM0_BASE_ADDR   //Start of RAM
    li a3, RAM0_BASE_ADDR + RAM_SIZE - 4 //End of RAM
    li a4, GPIO0_CS_PIN // Load CS Flash mask 


check_boot_mode:
    lw a4, GPIO_PxIN(a1) // Read GPIO0 Input Register
    andi a4, a4, GPIO0_BOOT_MASK // Mask out all but boot mode bit
    beqz a4, main // If boot mode pin is low (rv4th mode), launch forth interpreter from ROM, otherwise, load program from flash


SPI_FlashSetup: 
    jal ra, clr_spi0sr // Clear SPI Flash Status Register

    //Setup SPI Mode 
    li a6, SPI_CR_INIT // Load SPI Flash Control Register Initialization Value
    sw a6, SPI_CR(a0) // Set SPI Flash Control Register

    # //Setup SPI1 (For testing.. TODO: Create separate fn for setting up all peripherals in boot)
    # # li a4, PERIPH_SPI1_BASE // Load SPI1 Base Address
    # # mv t0, a6 // Copy SPI Flash Control Register Initialization Value to t2
    # li   t1, 0x00040000    # t1 = 0xFFF7C000   (bit 18 is 0, rest are 1 in upper bits)
    # or   t0, t0, t1     # clear bit 18 of t0, leave other bits unchanged
    # sw t0, SPI_CR(a4) // Set SPI1 Control Register as slave 

    //Assert CS
    li a4, GPIO0_CS_MASK // Load CS Flash mask
    sw a4, GPIO_PxOUTC(a1) // Clear GPIO Output Register to clear (assert) CS bit

    //Write Flash Slave Power Up Command
    li a6, FLASH_SLAVE_PU // Load Flash Slave Power Up Command
    sw a6, SPI_TX(a0) // Write to SPI Flash Transmit Register

    //Wait for PU command to send
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    //Deassert CS
    sw a2, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit

    //Wait for Flash Slave to power up (at least 30 us)
    jal ra, flash_slave_power_up_delay 

    //Assert CS
    sw a4, GPIO_PxOUTC(a1) // Clear GPIO Output Register to clear (assert) CS bit
    //Write Flash Slave Status Register Read Command
    //li a6, FLASH_SLAVE_SRREAD // Load Flash Slave Status Register Read Command
    li a6, FLASH_SLAVE_HFREAD // Load Flash Slave High Frequency Read Command
    sw a6, SPI_TX(a0) // Write to SPI Flash Transmit Register
    //Wait for SRREAD command to send
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete


    li a6, SPI_CR_LOADBEEF // Load SPI Flash Control Register for loading beef command
    sw a6, SPI_CR(a0) // Set SPI Flash Control Register for loading beef command


    //Send 24 bit start address for reading SPI Flash memory, followed by 8 bit dummy byte
    sw zero , SPI_TX(a0) // Send 24 bit start address (0x000000) for reading SPI Flash memory
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    //clear SPI0SR
    jal ra, clr_spi0sr // Clear SPI Flash Status Register

    // Send a 0x00000000 to the SPI flash, during which time the SPI flash will respond with the command word
    sw zero, SPI_TX(a0) // Send 0x00000000 to the SPI Flash

    # Prepare for error checkin by loading upper and lower bounds of where SPI Flash may write in RAM
    li s2, RAM0_BASE_ADDR // Load RAM base address
    li s3, RAM0_BASE_ADDR + RAM_SIZE -4 // Load RAM end address


getCommandWord:

    // Get command word from SPI Flash
    jal ra, spi0_complete_read_init_read
    li a7, 0x10adbeef //load beef command 
    beq t0, a7, loadSegmentToRAM // Check if command word is 0x10adbeef
    li a7, 0xdeadbeef
    beq t0, a7, eraseSegmentFromRAM // Check if command word is 0xdeadbeef - Note: This is not tested.
    li a7, 0xcafebabe // Check if command word is 0xcafebabe
    beq t0, a7, executeProgram // Check if command word is
    //Program should never get here, but if it does, just loop forever
    //TODO: Throw trap error here 
    # j getCommandWord
    j force_trap	

loadSegmentToRAM:
    // Load segment to RAM
    // FORMAT:
	//	word[0]: dump segment command 0xloadbeef
	//	word[1]: start address of RAM segment to dump to
	//	word[2]: end address of RAM segment to dump to (not inclusive)
	//	word[3, ..., 3 + (end address - start address) / 4]: The words to dump to the RAM segment. Must be exactly (end address - start address) / 4 words long.
	jal ra, spi0_complete_read_init_read
    addi a2, t0, 0 // Store the start address of RAM segment to a2
    jal ra, spi0_complete_read_init_read
    addi a3, t0, 0 // Store the end address of RAM segment to a3

    //TODO: Do some input validation here to see if addresses are valid (RAM).
    bgeu a2, a3, force_trap	// If start address >= stop address, make a trap condition
    # s2 is RamStartAddress
    bltu a2, s2, force_trap	// If start address < peripheral memory start address, make a trap condition
	# s3 is RamStartAddress + RamSize -4 
	bltu s3, a3, force_trap	// If RAM end address < end address, make a trap condition

getNextProgramWord:
    jal ra, spi0_complete_read_init_read // Read next word from SPI Flash
    sw t0, 0(a2) // Store the word to RAM at address a2
    addi a2, a2, 4 // Increment address by 4 bytes (next word)
    bltu a2, a3, getNextProgramWord // If not reached end address, continue reading words

    // Deassert CS
    sw a2, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit
    j getCommandWord // Go back to get next command word 

eraseSegmentFromRAM:
    // Erase segment from RAM
    // FORMAT:
    //	word[0]: erase segment command 0xdeadbeef
    //	word[1]: start address of RAM segment to erase
    //	word[2]: end address of RAM segment to erase (not inclusive)
    //	word[3]: The value to write each word in the erase segment of the RAM as.
    jal ra, spi0_complete_read_init_read
    addi a2, t0, 0 // Store the start address of RAM segment to a2
    jal ra, spi0_complete_read_init_read
    addi a3, t0, 0 // Store the end address of RAM segment to a3
    //TODO: Do some input validation here to see if addresses are valid (RAM).

    # s2 is RamStartAddress
    # s3 is RamStartAddress + RamSize -4
    bgeu a2, a3, force_trap	// If start address >= stop address, make a trap condition
    bltu a2, s2, force_trap    // If start address < peripheral memory start address, make a trap condition
    bltu s3, a3, force_trap    // If RAM end address < end address, make a trap condition   


    jal ra, spi0_complete_read_init_read // Read next word from SPI Flash
    
eraseWord: 
    sw t0, 0(a2) // Store the word to RAM at address a2
    addi a2, a2, 4 // Increment address by 4 bytes (next word)
    bltu a2, a3, eraseWord // If not reached end address, continue erasing words

    // Deassert CS
    j getCommandWord // Go back to get next command word

clr_spi0sr: 
    not a6, zero // a6 = 0xFFFFFFFF
    sw a6, SPI_SR(a0) // Clear SPI Flash Status Register
    ret


spi0_complete_read_init_read:
    //a0 has spibase
    //Wait for SPIO0TX register to be empty
    lw s9, SPI_SR(a0) // Read SPI0SR
    andi a7, s9, SPITEIF_MASK // Check if SPITXEMT is set
    beqz a7, spi0_complete_read_init_read // If SPITXEMT is not set, loop back

    //Get next word for transmission (dont care about the value)
    sw zero, SPI_TX(a0) // Write 0x00000000 to SPI Flash Transmit Register

    //Wait for the transmission to complete
spi0_wait_until_tx_complete:
	lw a7, SPI_SR(a0)	// (a0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, SPI_TCIF_MASK	// Zero everything except SPITCIF
	beqz a7, spi0_wait_until_tx_complete	// Loop back again to read SPI0SR if SPITCIF is a 0 (aka wait until SPITCIF == 1, meaning the SPI transfer is complete)

	// Load the received word to register t0
	lw t0, SPI_RX(a0)	// (a0 = SPI_BASE) Read SPI0RX and store in t0. Reading SPI0RX also clears SPITCIF
	ret // pop return address and jump to it

// Function to delay for FLASH_SLAVE_PU_DELAY cycles
flash_slave_power_up_delay:
    // Delay loop for FLASH_SLAVE_PU_DELAY cycles
    li a6, FLASH_SLAVE_PU_DELAY // Load delay count
delay_loop:
    addi a6, a6, -1 // Decrement delay count
    bnez a6, delay_loop // If delay count is not zero, loop back
    ret

executeProgram:

    // Clear SPI0SR
    jal ra, clr_spi0sr // Clear SPI Flash Status Register

    //Deassert CS (Needed to put Flash slave in Idle state)
    li a2, GPIO0_CS_MASK // Load CS Flash mask
    sw a2, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit

    li a6, FLASH_SLAVE_PD // Load Flash Slave Power Down Command

    //assert CS
    sw a2, GPIO_PxOUTC(a1) // Set GPIO Output Register to clear (assert) CS bit

    sw a6, SPI_TX(a0) // Write to SPI Flash Transmit Register
    jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    //Set GPIO0 to not alternative function mode 
    sw zero, GPIO_PxSEL(a1) // Set GPIO Select Register to not alternative function mode
    
    //Deassert CS
    li a2, GPIO0_CS_MASK // Load CS Flash mask
    sw a2, GPIO_PxOUTS(a1) // Set GPIO Output Register to set (deassert) CS bit

    
    
    # //Set smclk to lfxt 
    li t0, PERIPH_SYSTEM0_BASE
    # li t1, 0x02 // Set smclk to lfxt
    # Set mclk to hfxt, and smclk to lftxt
    li t1, SYS_MCLKSEL_HFXT | SYS_SMCLKSEL_LFXT
    sw t1, SYS_CLK_CR(t0) // Write to System Clock Control Register
    li t1, 0X080 
    sw t1, SYS_DCO0_BIAS(t0) // Write to System DCO0 Bias Register
    sw t1, SYS_DCO1_BIAS(t0) // Write to System DCO1 Bias Register


    # # For testing 
    # li t1, SYS_MCLKSEL_HFXT | SYS_SMCLKSEL_LFXT
    # sw t1, SYS_CLK_CR(t0) // Write to System Clock Control Register

#     # Wait a while for clk to settle (For debugging, not needed in real application)
#     li t2, 1000
# wait_clk_settle:
#     addi t2, t2, -1
#     bnez t2, wait_clk_settle

    //Jump to the start of the program in RAM

    clear_regs:
	li x1, 0
	li sp, SP_INIT_VAL	
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

    j PROG_BASE_ADDR // Jump to the start of the program in RAM


    # TODO: Perhaps Delay for clk sel to settle. 

# Invalid intstruction that will induce trap state in the core. 
force_trap:
	.word 0xFFFFFFFF


# VestaRV Documentation
.section .vestarv_doc, "ax"
vestarv_id:
    .asciz "Myshkin \November, 2025\nThe first instantiation of VestaRV.\nDesigned by Maxx Seminario featuring ECS by Seth McRobert.\nShe herself is my best apology for all her accusations. \n\nWhat beautiful things there are at every step, even the most hopeless man must feel so beautiful! \n"

# for now, 4th code here 
# main: 
#     jal zero, main // Jump to the start of the forth interpreter in ROM




