#*****************************************************************************
# test_spi_flash.S
#-----------------------------------------------------------------------------
#
# Test SPI peripheral with flash extended memory execution
#

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"

#define SP_INIT_TEST 0xF9FF     // Init stack pointer - below ISRs

# Flash memory base address (where we'll jump to)
#define FLASH_BASE              0x10000    // Flash starts at 0x10000
#define PROG_ADDR_IN_FLASH      0x2001
#define SPI_FOS_VAL             0xFFF2000  // Flash Offset Value to add to PC for flash execution
#define GPIO0_PSEL              0x0F  // Flash selected on SPI0
#define FLASH_SLAVE_PU          0xAB // Flash Slave Power Up Command
#define P1_DIR_BOOT             (GPIO0_CS_MASK) // CSFlash bit 1, Boot 0
#define P1_SEL_BOOT             (GPIO0_MISO_MASK | GPIO0_MOSI_MASK | GPIO0_SCK_MASK | GPIO0_TRAP_MASK)

# Corrected SPI_CR_INIT for 32-bit, MSB first, byte swap
# Bit 17: SPITXSB = 1 (byte swap enabled)
# Bit 16: SPIRXSB = 1 (byte swap enabled)  
# Bits 15-8: SPIBR = 0x04 (baud rate divider)
# Bit 7: SPIEN = 1 (SPI enabled)
# Bit 6: SPIMSB = 1 (MSB first)
# Bit 5: SPITCIE = 0 (TX complete interrupt disabled)
# Bit 4: SPITEIE = 0 (TX empty interrupt disabled)
# Bits 3-2: SPIDL = 10 (32-bit transfers)
# Bit 1: SPICPOL = 0 (clock idle low)
# Bit 0: SPICPHA = 0 (sample on leading edge)
#define SPI_CR_INIT 0x304C8 // 0b110000010011001000 = TX/RX byte swap, BR=4, EN, MSB, 32-bit

#define FLASH_SLAVE_HFREAD      0x0B // Flash Slave High Frequency Read Command
//# define FLASH_SLAVE_PU_DELAY    4000 // at least 30 us delay (in cycles) (40 us with 100MHz clock) this is sufficient when smclk = mclk, not else
#define FLASH_SLAVE_PU_DELAY    200000 // at least 30 us delay (in cycles) (80 us with 100MHz clock) to be safe when smclk != mclk
#define FLASH_SLAVE_PD          0xB9 // Flash Slave Power Down Command

### define SPI_CR_INIT_FLASH   (SPI_FEN_MASK | SPI_BR(SPI_BR_DIV10) |SPI_EN_MASK | SPI_MSB_MASK |  SPI_DL_32BIT | SPI_RXSB_MASK)
#define SPI_CR_INIT_FLASH   (SPI_FEN_MASK | SPI_BR(SPI_BR_DIV2) |SPI_EN_MASK | SPI_MSB_MASK |  SPI_DL_32BIT | SPI_RXSB_MASK)

RVTEST_RV64U
RVTEST_CODE_BEGIN
INIT_XREG 

    # Initialize stack pointer
    li sp, SP_INIT_TEST


    # //Set smclk to lfxt 
    li t0, PERIPH_SYSTEM0_BASE
    # li t1, 0x02 // Set smclk to lfxt
    # Set mclk to hfxt, and smclk to lftxt
    li t1, SYS_MCLKSEL_HFXT | SYS_SMCLKSEL_LFXT
    sw t1, SYS_CLK_CR(t0) // Write to System Clock Control Register



    # Load SPI0 base address
    li      t0, PERIPH_SPI0_BASE
    li      a0, PERIPH_GPIO0_BASE  # Load flash base address for reference
    
    # First, make sure SPI is disabled before configuration
    sw      zero, SPI_CR(t0)
        
    # Wake up the flash chip
    //Get ready for SPI Flash Setup / RV4th Boot
    # sb zero, GPIO_PxREN(a1) // Disable GPIO Pullup/Pulldown Resistors
    li a2, P1_DIR_BOOT     // Set GPIO Direction Register for Flash (output)
    sb a2, GPIO_PxDIR(a0)   // Set GPIO Direction Register to output for CS Flash 
    li a2, P1_SEL_BOOT      // Set GPIO PSEL for boot mode
    sb a2, GPIO_PxSEL(a0)   // Set GPIO Select Register for boot mode

    li a6, SPI_CR_INIT // Load corrected SPI Flash Control Register Initialization Value
    sw a6, SPI_CR(t0) // Set SPI Flash Control Register

    //Assert CS
    li a4, GPIO0_CS_MASK // Load CS Flash mask
    sw a4, GPIO_PxOUTC(a0) // Clear GPIO Output Register to clear (assert) CS bit

    //Write Flash Slave Power Up Command
    li a6, FLASH_SLAVE_PU // Load Flash Slave Power Up Command
    sw a6, SPI_TX(t0) // Write to SPI Flash Transmit Register

    # /Wait for PU command to send
    # jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete
    //Wait for Flash Slave to power up (at least 30 us)
    jal ra, flash_slave_power_up_delay 
    # li a6, FLASH_SLAVE_HFREAD // Load Flash Slave High Frequency Read Command
    # sw a6, SPI_TX(t0) // Write to SPI Flash Transmit Register
    # //Wait for SRREAD command to send
    # jal ra, spi0_wait_until_tx_complete // Wait until SPI transfer is complete

    j setup_spi

    # ---------------------------------------------------------------
    # Step 1: Configure SPI peripheral for flash extended memory
    # ---------------------------------------------------------------

    setup_spi:



        li      t1, SPI_FOS_VAL 
        sw      t1, SPI_FOS(t0)
        
        # Configure SPI Control Register for Flash Extended Memory
        # Build the control register value properly:
        # Bit 19: SPIFEN = 1 (Flash extended memory enable)
        # Bit 17: SPITXSB = 1 (TX byte swap)
        # Bit 16: SPIRXSB = 1 (RX byte swap)
        # Bits 15-8: SPIBR = 0x04 (baud rate)
        # Bit 7: SPIEN = 1 (SPI enable)
        # Bit 6: SPIMSB = 1 (MSB first)
        # Bits 3-2: SPIDL = 10 (32-bit)
        
        # First set the base configuration
        li      t1, SPI_CR_INIT_FLASH

        li     t2, GPIO0_PSEL
        sw     t2, GPIO_PxSEL(a0)  # Select flash on GPIO0
        
        # Write configuration to SPI_CR
        sw      t1, SPI_CR(t0)


        

# ---------------------------------------------------------------
# Step 3: Prepare for flash code execution
# # ---------------------------------------------------------------

# prepare_flash_exec:
#     # Clear all registers before jumping to flash
#     li      ra, 0
#     li      gp, 0
#     li      tp, 0
#     li      t0, 0
#     li      t1, 0
#     li      t2, 0
#     li      s0, 0
#     li      s1, 0
#     li      a0, 0
#     li      a1, 0
#     li      a2, 0
#     li      a3, 0
#     li      a4, 0
#     li      a5, 0
#     li      a6, 0
#     li      a7, 0
#     li      s2, 0
#     li      s3, 0
#     li      s4, 0
#     li      s5, 0
#     li      s6, 0
#     li      s7, 0
#     li      s8, 0
#     li      s9, 0
#     li      s10, 0
#     li      s11, 0
#     li      t3, 0
#     li      t4, 0
#     li      t5, 0
#     li      t6, 0

# ---------------------------------------------------------------
# Step 4: Jump to flash memory to execute test code
# ---------------------------------------------------------------

jump_to_flash:
    # Load the flash test address
    # The test code starts at 0x8150 in the binary,
    # but will be mapped to 0x18150 in the flash address space
    li      t0, FLASH_BASE #This should place us exacty at the simple.S code in flash memory 
    
    # Save expected test result for verification
    # The test loads 0xcafebabe into a0
    li      s0, 0xcafebabe
    
    # Jump to flash memory
    jalr    ra, t0, 0
    
    # If we return here (shouldn't happen with infinite loop in test)
    # Check if a0 contains expected value
    bne     a0, s0, flash_test_fail

# ---------------------------------------------------------------
# Test passed - should not reach here normally as test has infinite loop
# ---------------------------------------------------------------

test_pass:
    # Indicate test passed
    li      a0, 1
    j       end_test

# ---------------------------------------------------------------
# Error handlers
# ---------------------------------------------------------------

spi_config_fail:
    # SPI configuration failed
    li      a0, 0xDEAD0001
    j       end_test

flash_test_fail:
    # Flash test execution failed
    li      a0, 0xDEAD0002
    j       end_test

//Wait for the transmission to complete
spi0_wait_until_tx_complete:
	lw a7, SPI_SR(t0)	// (t0 = SPI_BASE) Read SPI0SR and store in a7
	andi a7, a7, SPI_TCIF_MASK	// Zero everything except SPITCIF
	beqz a7, spi0_wait_until_tx_complete	// Loop back again to read SPI0SR if SPITCIF is a 0 (aka wait until SPITCIF == 1, meaning the SPI transfer is complete)

	// Load the received word to register t0
	lw zero, SPI_RX(t0)	// (t0 = SPI_BASE) Read SPI0RX and store in t0. Reading SPI0RX also clears SPITCIF
	ret // pop return address and jump to it

// Function to delay for FLASH_SLAVE_PU_DELAY cycles
flash_slave_power_up_delay:
    // Delay loop for FLASH_SLAVE_PU_DELAY cycles
    li a6, FLASH_SLAVE_PU_DELAY // Load delay count
delay_loop:
    addi a6, a6, -1 // Decrement delay count
    bnez a6, delay_loop // If delay count is not zero, loop back
    ret

# ---------------------------------------------------------------
# End of test
# ---------------------------------------------------------------

end_test:
    # Store result for testbench
    li      t0, 0x8200      # tohost address
    sw      a0, 0(t0)
    
    # Infinite loop
end_loop:
    j       end_loop

RVTEST_CODE_END

# ---------------------------------------------------------------
# Test data section
# ---------------------------------------------------------------

RVTEST_DATA_BEGIN

test_data:
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000

RVTEST_DATA_END


