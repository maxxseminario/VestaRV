#*****************************************************************************
# UART_BASIC_TEST.S
#-----------------------------------------------------------------------------
# Basic UART testbench for RISC-V assembly
# Author: Maxx Seminario
# Date: 08-17-2025
#
# Test Categories:
# 1. Basic Communication Tests (Tests 1-11)
# 
# Each test category runs 3 times with different baud rates:
# - High baud rate (0x01)
# - Medium baud rate (0x4D)  
# - Low baud rate (0xFF)
#
# Each baud rate set is run twice, swapping UART0 and UART1 roles to ensure
# both UARTs are fully tested in both transmit and receive roles.
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"

# Baud rate settings
#define BAUD_RATE_HIGH      0x01    # High baud rate (fastest)
#define BAUD_RATE_MEDIUM    0x4D    # Medium baud rate
#define BAUD_RATE_LOW       0xFF    # Low baud rate (slowest)

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# UPDATED Register Usage Convention
# ===============================================================================
# x10 (a0) - UART0 base address (preserved)
# x11 (a1) - UART1 base address (preserved)  
# x12 (a2) - GPIO base address (preserved)
# x13 (a3) - Temporary UART base for subroutines
# x14 (a4) - Temporary UART base for subroutines
# x3  (gp) - Test counter (preserved)
# x15 (a5) - SYSTEM base address (preserved)
# x8  (s0) - Baud rate loop counter
# x9  (s1) - Saved return address (for individual tests)
# x18 (s2) - Main test suite return address (RESERVED - don't use for data!)
# x19 (s3) - Test data byte 1  
# x20 (s4) - Test data byte 2
# x21 (s5) - Configuration values
# x22 (s6) - Current baud rate value (PRESERVED across all tests)
# x23 (s7) - Additional configuration values
# x24-x27 (s8-s11) - Additional saved values as needed
# x16 (a6) - IRQ pending flags (for bidirectional test)
# x17 (a7) - IRQ expected count
#
# x5-x7, x28-x31 (t0-t4) - Temporary (only between function calls)
# ===============================================================================


# Configure smclk to be hfxt
system_init: 
    li  a5, PERIPH_SYSTEM0_BASE # Preserved SYSTEM base address
    sw zero, SYS_CLK_CR(a5)  # Disable clock

    # Initialize SP 
    li sp, SP_INIT_VAL

    # Configure interrupts - initially enable all UART interrupts
    li t0, IRQB_UART0_RC | IRQB_UART0_TC | IRQB_UART0_TE #In lower IRQ word
    li t1, IRQB_UART1_RC | IRQB_UART1_TC | IRQB_UART1_TE #In middle IRQ word
    li t2, SYS_IRQ_GEN_MASK # Global IRQ enable
    sw t0, SYS_IRQ_ENL(a5)
    sw t1, SYS_IRQ_ENM(a5)
    sw t2, SYS_IRQ_CR(a5)

    mv t0, zero
    mv t1, zero
    mv t2, zero




uart_basic_test_start:

    li  a2, PERIPH_GPIO1_BASE
    li  gp, 0                   # Initialize test counter

    jal ra, init_gpio_uart

    li  s8, 0                   # UART swap iteration counter

# ===============================================================================
# MAIN UART SWAP LOOP
# ===============================================================================
uart_swap_loop:

    sw zero, UART_CR(a0)  # Disable UART0
    sw zero, UART_CR(a1)  # Disable UART1


    beqz s8, no_swap
    
    # Swap UART addresses for second iteration
    li  t0, PERIPH_UART0_BASE
    li  t1, PERIPH_UART1_BASE
    mv  a0, t1                  # a0 = PERIPH_UART1_BASE
    mv  a1, t0                  # a1 = PERIPH_UART0_BASE
    j   start_baud_tests

no_swap:
    # Keep original addresses for first iteration
    li  a0, PERIPH_UART0_BASE
    li  a1, PERIPH_UART1_BASE

start_baud_tests:
    # Initialize baud rate loop counter for each swap iteration
    li  s0, 0                   # Baud rate loop index (0=high, 1=medium, 2=low)

# ===============================================================================
# MAIN BAUD RATE LOOP
# ===============================================================================
baud_rate_loop:
    # Set current baud rate based on loop counter
    jal ra, set_current_baud_rate

    # Set baud rate for both UARTs
    sw  s6, UART_BR(a0)
    sw  s6, UART_BR(a1)

    # Run all test suites with current baud rate
    jal ra, basic_communication_tests

    # Next baud rate
    addi s0, s0, 1
    li   t0, 3
    blt  s0, t0, baud_rate_loop

    # Next UART swap iteration
    addi s8, s8, 1
    li   t0, 2
    blt  s8, t0, uart_swap_loop

# ===============================================================================
# SUCCESS - ALL TESTS PASSED
# ===============================================================================
all_tests_passed:
    TEST_PASSFAIL

# ===============================================================================
# BAUD RATE SELECTION
# ===============================================================================
set_current_baud_rate:
    # Select baud rate based on s0 value
    li   t1, 0
    beq  s0, t1, use_high_baud
    
    li   t1, 1
    beq  s0, t1, use_medium_baud
    
    li   t1, 2
    beq  s0, t1, use_low_baud
    
    # Default to medium if invalid
    j    use_medium_baud

use_high_baud:
    li   s6, BAUD_RATE_HIGH
    ret

use_medium_baud:
    li   s6, BAUD_RATE_MEDIUM
    ret

use_low_baud:
    li   s6, BAUD_RATE_LOW
    ret

# ===============================================================================
# 1. BASIC COMMUNICATION TESTS (Tests 1-11)
# ===============================================================================

basic_communication_tests:
    # Save return address
    mv   s2, ra

    # Test 1: Simple UART0 -> UART1 communication (no parity)
    addi gp, gp, 1
    jal ra, test_simple_tx_rx

    # Test 2: Simple UART1 -> UART0 communication (no parity)
    addi gp, gp, 1
    jal ra, test_reverse_tx_rx

    # Test 3: Communication with even parity
    addi gp, gp, 1
    jal ra, test_even_parity_comm

    # Test 4: Communication with odd parity
    addi gp, gp, 1
    jal ra, test_odd_parity_comm

    # Test 5: Back-to-back transmission
    addi gp, gp, 1
    jal ra, test_back_to_back

    # Test 6-9: Multiple data patterns
    addi gp, gp, 1
    jal ra, test_data_patterns

    # Test 10: Bidirectional communication
    addi gp, gp, 1
    jal ra, test_bidirectional

    # Test 11: Communication after disable/enable
    addi gp, gp, 1
    jal ra, test_enable_disable

    # Restore return address
    mv   ra, s2
    ret

# Test 1: Simple UART0 -> UART1 communication (no parity)
test_simple_tx_rx:
    # Save return address
    mv s1, ra

    # Configure both UARTs: Enable, no parity, all interrupts enabled
    li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Clear any pending interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Send test byte from UART0 to UART1 
    li s3, 0xA5
    sw s3, UART_TX(a0)

    # Wait for RX complete on UART1
    jal ra, en_uart1_rc_only
    extinguish

    # Verify received data 
    lw t1, UART_RX(a1)
    bne s3, t1, fail

    # Restore return address and return
    mv ra, s1
    ret

# Test 2: Simple UART1 -> UART0 communication (no parity)
test_reverse_tx_rx:
    # Save return address
    mv s1, ra

    # Clear any pending interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Send test byte from UART1 to UART0 
    li s3, 0x5A
    sw s3, UART_TX(a1)

    # Wait for RX complete on UART0
    jal ra, en_uart0_rc_only
    extinguish

    # Verify received data 
    lw t1, UART_RX(a0)
    bne s3, t1, fail

    # Restore return address and return
    mv ra, s1
    ret

# Test 3: Communication with even parity
test_even_parity_comm:
    # Save return address
    mv s1, ra

    # Configure both UARTs: Enable, even parity, all interrupts
    li s5, UCR_EN_MASK | UCR_PEN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Clear interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Send byte with even parity 
    li s3, 0x33  # Even number of 1s
    sw s3, UART_TX(a0)

    # Wait for RX complete on UART1
    jal ra, en_uart1_rc_only
    extinguish

    lw t1, UART_RX(a1)
    bne s3, t1, fail

    # Check no parity error
    lw t2, UART_SR(a1)
    andi t2, t2, USR_PEF_MASK
    bnez t2, fail

    # Restore return address
    mv ra, s1
    ret

# Test 4: Communication with odd parity
test_odd_parity_comm:
    mv s1, ra

    # Configure both UARTs: Enable, odd parity, all interrupts
    li s5, UCR_EN_MASK | UCR_PEN_MASK | UCR_PSEL_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Clear interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Send byte with odd parity 
    li s3, 0x07  # Odd number of 1s
    sw s3, UART_TX(a0)

    # Wait for RX complete on UART1
    jal ra, en_uart1_rc_only
    extinguish

    lw t1, UART_RX(a1)
    bne s3, t1, fail

    # Check no parity error
    lw t2, UART_SR(a1)
    andi t2, t2, USR_PEF_MASK
    bnez t2, fail

    mv ra, s1
    ret

# Test 5: Back-to-back transmission
test_back_to_back:
    mv s1, ra

    # Configure UARTs (no parity)
    li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Clear interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Store both test bytes in saved registers
    li s3, 0x11  # First byte
    li s4, 0x22  # Second byte

    # Send first byte
    sw s3, UART_TX(a0)

    # Wait for TX empty (ready for next byte)
    jal ra, en_uart0_te_only
    extinguish

    # Send second byte immediately
    sw s4, UART_TX(a0)

    # Wait for first byte to be received
    jal ra, en_uart1_rc_only
    extinguish

    # Read first byte
    lw t2, UART_RX(a1)
    bne s3, t2, fail

    # Wait for second byte to be received
    # The interrupt is still enabled from previous call
    extinguish

    # Read second byte
    lw t2, UART_RX(a1)
    bne s4, t2, fail

    mv ra, s1
    ret

# Test 6-9: Multiple data patterns
test_data_patterns:
    mv s1, ra

    # Configure UARTs
    li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Test pattern: 0x00 
    li s3, 0x00
    jal ra, test_single_pattern

    # Test pattern: 0xFF
    addi gp, gp, 1
    li s3, 0xFF
    jal ra, test_single_pattern

    # Test pattern: 0x55 (alternating)
    addi gp, gp, 1
    li s3, 0x55
    jal ra, test_single_pattern

    # Test pattern: 0xAA (inverse alternating)
    addi gp, gp, 1
    li s3, 0xAA
    jal ra, test_single_pattern

    mv ra, s1
    ret

test_single_pattern:
    mv s7, ra  # Save return address for this subroutine

    # Clear interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Send pattern in s3 
    sw s3, UART_TX(a0)

    # Wait for RX complete on UART1
    jal ra, en_uart1_rc_only
    extinguish

    lw t1, UART_RX(a1)
    bne s3, t1, fail

    mv ra, s7
    ret

# Test 10: Bidirectional communication
test_bidirectional:
    mv s1, ra

    # Configure UARTs
    li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Clear interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Store test data in saved registers
    li s3, 0x12  # UART0 -> UART1
    li s4, 0x34  # UART1 -> UART0

    # Clear IRQ pending flags
    la t0, uart0_rx_pending
    sw zero, 0(t0)
    la t0, uart1_rx_pending
    sw zero, 0(t0)

    # Enable both UART interrupts for bidirectional
    jal ra, en_both_uart_rc

    # Send from both UARTs simultaneously
    sw s3, UART_TX(a0)
    sw s4, UART_TX(a1)

    # Wait for UART0 RX
    la t1, uart0_rx_pending
    wait_uart0_rx:
        lw t0, 0(t1)
        beqz t0, wait_uart0_rx

    # Wait for UART1 RX
    la t1, uart1_rx_pending
    wait_uart1_rx:
        lw t0, 0(t1)
        beqz t0, wait_uart1_rx

    # Verify data
    lw t2, UART_RX(a1)
    bne s3, t2, fail
    lw t2, UART_RX(a0)
    bne s4, t2, fail

    mv ra, s1
    ret

# Test 11: Communication after disable/enable
test_enable_disable:
    mv s1, ra

    # Store configuration and test data 
    li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
    li s3, 0x77  # Test data

    # Configure UARTs
    sw s5, UART_CR(a0)
    sw s5, UART_CR(a1)

    # Disable UART1
    li t0, 0x00
    sw t0, UART_CR(a1)

    # Try to send (should not be received)
    li t0, 0x99
    sw t0, UART_TX(a0)

    # Wait a bit (for transfer to complete if it would)
    li t1, 50000
disable_wait_loop:
    addi t1, t1, -1
    bnez t1, disable_wait_loop

    # Re-enable UART1
    sw s5, UART_CR(a1)

    # Clear interrupts
    mv a3, a0
    jal ra, clear_uart_interrupts
    mv a3, a1
    jal ra, clear_uart_interrupts

    # Send valid data 
    sw s3, UART_TX(a0)

    # Wait for RX complete on UART1
    jal ra, en_uart1_rc_only
    extinguish

    lw t1, UART_RX(a1)
    bne s3, t1, fail

    mv ra, s1
    ret

# ===============================================================================
# UTILITY FUNCTIONS
# ===============================================================================

# Initialize GPIO for UART pins
init_gpio_uart:
    li t0, 0xF0
    sw t0, GPIO_PxSEL(a2)
    ret

# Clear UART interrupt flags (base address in a3)
clear_uart_interrupts:
    li t0, USR_UTCIF_MASK | USR_UTEIF_MASK
    sw t0, UART_SR(a3)
    ret

# Enable UART1 RX complete interrupt only
en_uart1_rc_only:
    li t1, IRQB_UART1_RC
    sw zero, SYS_IRQ_ENL(a5)
    sw t1, SYS_IRQ_ENM(a5)
    sw zero, SYS_IRQ_ENH(a5)
    ret

# Enable UART0 RX complete interrupt only
en_uart0_rc_only:
    li t0, IRQB_UART0_RC
    sw t0, SYS_IRQ_ENL(a5)
    sw zero, SYS_IRQ_ENM(a5)
    sw zero, SYS_IRQ_ENH(a5)
    ret

# Enable UART0 TX empty interrupt only
en_uart0_te_only:
    li t0, IRQB_UART0_TE
    sw t0, SYS_IRQ_ENL(a5)
    sw zero, SYS_IRQ_ENM(a5)
    sw zero, SYS_IRQ_ENH(a5)
    ret

# Enable UART0 TX complete interrupt only
en_uart0_tc_only:
    li t0, IRQB_UART0_TC
    sw t0, SYS_IRQ_ENL(a5)
    sw zero, SYS_IRQ_ENM(a5)
    sw zero, SYS_IRQ_ENH(a5)
    ret

# Enable both UART RX complete interrupts
en_both_uart_rc:
    li t0, IRQB_UART0_RC
    li t1, IRQB_UART1_RC
    sw t0, SYS_IRQ_ENL(a5)
    sw t1, SYS_IRQ_ENM(a5)
    sw zero, SYS_IRQ_ENH(a5)
    ret

# Enable all UART interrupts
en_both_uart_all:
    li t0, IRQB_UART0_RC | IRQB_UART0_TC | IRQB_UART0_TE
    li t1, IRQB_UART1_RC | IRQB_UART1_TC | IRQB_UART1_TE
    sw t0, SYS_IRQ_ENL(a5)
    sw t1, SYS_IRQ_ENM(a5)
    sw zero, SYS_IRQ_ENH(a5)
    ret

disable_all_irqs:
    sw zero, SYS_IRQ_CR(a5)
    ret

RVTEST_CODE_END

# ===============================================================================
# Data Section for IRQ pending flags
# ===============================================================================
.section .data
.align 4
uart0_rx_pending: .word 0
uart1_rx_pending: .word 0
uart0_tc_pending: .word 0
uart1_tc_pending: .word 0
uart_irq_expected: .word 0

# ===============================================================================
# Interrupt Service Routines
# ===============================================================================

.section .isr_uart0_rc , "ax"
.align 4
isr_uart0_rc:
    SAVE_CONTEXT()
    # Set pending flag
    li t0, 1
    la t1, uart0_rx_pending
    sw t0, 0(t1)
    # Clear interrupt flag
    li t0, PERIPH_UART0_BASE
    li t1, USR_RCIF_MASK
    sw t1, UART_SR(t0)
    ignite
    RESTORE_CONTEXT()

.section .isr_uart0_te , "ax"
.align 4
isr_uart0_te:
    SAVE_CONTEXT()
    # Clear interrupt flag
    li t0, PERIPH_UART0_BASE
    li t1, USR_UTEIF_MASK
    sw t1, UART_SR(t0)
    ignite
    RESTORE_CONTEXT()

.section .isr_uart0_tc , "ax"
.align 4
isr_uart0_tc:
    SAVE_CONTEXT()
    # Set pending flag
    li t0, 1
    la t1, uart0_tc_pending
    sw t0, 0(t1)
    # Clear interrupt flag
    li t0, PERIPH_UART0_BASE
    li t1, USR_UTCIF_MASK
    sw t1, UART_SR(t0)
    ignite
    RESTORE_CONTEXT()

.section .isr_uart1_rc , "ax"
.align 4
isr_uart1_rc:
    SAVE_CONTEXT()
    # Set pending flag
    li t0, 1
    la t1, uart1_rx_pending
    sw t0, 0(t1)
    # Clear interrupt flag
    li t0, PERIPH_UART1_BASE
    li t1, USR_RCIF_MASK
    sw t1, UART_SR(t0)
    ignite
    RESTORE_CONTEXT()

.section .isr_uart1_te , "ax"
.align 4
isr_uart1_te:
    SAVE_CONTEXT()
    # Clear interrupt flag
    li t0, PERIPH_UART1_BASE
    li t1, USR_UTEIF_MASK
    sw t1, UART_SR(t0)
    ignite
    RESTORE_CONTEXT()

.section .isr_uart1_tc , "ax"
.align 4
isr_uart1_tc:
    SAVE_CONTEXT()
    # Set pending flag
    li t0, 1
    la t1, uart1_tc_pending
    sw t0, 0(t1)
    # Clear interrupt flag
    li t0, PERIPH_UART1_BASE
    li t1, USR_UTCIF_MASK
    sw t1, UART_SR(t0)
    ignite
    RESTORE_CONTEXT()


# #*****************************************************************************
# # UART_BASIC_TEST.S
# #-----------------------------------------------------------------------------
# # Basic UART testbench for RISC-V assembly
# # Author: Maxx Seminario
# # Date: 08-17-2025
# #
# # Test Categories:
# # 1. Basic Communication Tests (Tests 1-11)
# # 2. Interrupt Flag Tests (Tests 12-19)
# # 
# # Each test category runs 3 times with different baud rates:
# # - High baud rate (0x01)
# # - Medium baud rate (0x4D)  
# # - Low baud rate (0xFF)
# #
# # Each baud rate set is run twice, swapping UART0 and UART1 roles to ensure
# # both UARTs are fully tested in both transmit and receive roles.
# #-----------------------------------------------------------------------------

# #include "riscv_test.h"
# #include "test_macros.h"
# #include "myshkin_s.h"

# # Baud rate settings
# #define BAUD_RATE_HIGH      0x01    // High baud rate (fastest)
# #define BAUD_RATE_MEDIUM    0x4D    // Medium baud rate
# #define BAUD_RATE_LOW       0xFF    // Low baud rate (slowest)

# RVTEST_RV32U
# RVTEST_CODE_BEGIN

# # ===============================================================================
# # UPDATED Register Usage Convention
# # ===============================================================================
# # x10 (a0) - UART0 base address (preserved)
# # x11 (a1) - UART1 base address (preserved)  
# # x12 (a2) - GPIO base address (preserved)
# # x13 (a3) - Temporary UART base for subroutines
# # x14 (a4) - Temporary UART base for subroutines
# # x3  (gp) - Test counter (preserved)
# # x15 (a5) - SYSTEM base address (preserved)
# # x8  (s0) - Baud rate loop counter
# # x9  (s1) - Saved return address (for individual tests)
# # x18 (s2) - Main test suite return address (RESERVED - don't use for data!)
# # x19 (s3) - Test data byte 1  
# # x20 (s4) - Test data byte 2
# # x21 (s5) - Configuration values
# # x22 (s6) - Current baud rate value (PRESERVED across all tests)
# # x23 (s7) - Additional configuration values
# # x24-x27 (s8-s11) - Additional saved values as needed
# #
# # x5-x7, x28-x31 (t0-t4) - Temporary (only between function calls)
# # ===============================================================================


# # Configure smclk to be hfxt
# system_init: 
#     li  a5, PERIPH_SYSTEM0_BASE # Preserved SYSTEM base address
#     sw zero, SYS_CLK_CR(a5)  # Disable clock

#     # Initialize SP 
#     li sp, SP_INIT_VAL

#     # Configure interrupts 
#     li t0, IRQB_UART0_RC | IRQB_UART0_TC #In lower IRQ word
#     li t1, IRQB_UART1_RC | IRQB_UART1_TC #In middle IRQ word
#     li t2, SYS_IRQ_GEN_MASK # Global IRQ enable
#     sw t0, SYS_IRQ_ENL(a5)
#     sw t1, SYS_IRQ_ENM(a5)
#     sw t2, SYS_IRQ_CR(a5)

#     mv t0, zero
#     mv t1, zero
#     mv t2, zero




# uart_basic_test_start:

#     li  a2, PERIPH_GPIO1_BASE
#     li  gp, 0                   # Initialize test counter

#     jal ra, init_gpio_uart

#     li  s8, 0                   # UART swap iteration counter

# # ===============================================================================
# # MAIN UART SWAP LOOP
# # ===============================================================================
# uart_swap_loop:

#     # li  s0, 0                   # Baud rate loop index (0=high, 1=medium, 2=low)

#     sw zero, UART_CR(a0)  # Disable UART0
#     sw zero, UART_CR(a1)  # Disable UART1


#     beqz s8, no_swap
    
#     # Swap UART addresses for second iteration
#     li  t0, PERIPH_UART0_BASE
#     li  t1, PERIPH_UART1_BASE
#     mv  a0, t1                  # a0 = PERIPH_UART1_BASE
#     mv  a1, t0                  # a1 = PERIPH_UART0_BASE
#     j   start_baud_tests

# no_swap:
#     # Keep original addresses for first iteration
#     li  a0, PERIPH_UART0_BASE
#     li  a1, PERIPH_UART1_BASE

# start_baud_tests:
#     # Initialize baud rate loop counter for each swap iteration
#     li  s0, 0                   # Baud rate loop index (0=high, 1=medium, 2=low)

# # ===============================================================================
# # MAIN BAUD RATE LOOP
# # ===============================================================================
# baud_rate_loop:
#     # Set current baud rate based on loop counter
#     jal ra, set_current_baud_rate


#     # Set baud rate for both UARTs
#     sw  s6, UART_BR(a0)
#     sw  s6, UART_BR(a1)

#     # li gp, 0                  

#     # Run all test suites with current baud rate
#     jal ra, basic_communication_tests
#     # jal ra, interrupt_flag_tests
#     addi gp, gp, 8          # 8 tests in basic communication suite

#     # Next baud rate
#     addi s0, s0, 1
#     li   t0, 3
#     blt  s0, t0, baud_rate_loop

#     # Next UART swap iteration
#     addi s8, s8, 1
#     li   t0, 2
#     blt  s8, t0, uart_swap_loop

# # ===============================================================================
# # SUCCESS - ALL TESTS PASSED
# # ===============================================================================
# all_tests_passed:
#     TEST_PASSFAIL

# # ===============================================================================
# # BAUD RATE SELECTION
# # ===============================================================================
# set_current_baud_rate:
#     # Select baud rate based on s0 value
#     li   t1, 0
#     beq  s0, t1, use_high_baud
    
#     li   t1, 1
#     beq  s0, t1, use_medium_baud
    
#     li   t1, 2
#     beq  s0, t1, use_low_baud
    
#     # Default to medium if invalid
#     j    use_medium_baud

# use_high_baud:
#     li   s6, BAUD_RATE_HIGH
#     ret

# use_medium_baud:
#     li   s6, BAUD_RATE_MEDIUM
#     ret

# use_low_baud:
#     li   s6, BAUD_RATE_LOW
#     ret

# # ===============================================================================
# # 1. BASIC COMMUNICATION TESTS (Tests 1-11)
# # ===============================================================================

# basic_communication_tests:
#     # Save return address
#     mv   s2, ra

#     # Test 1: Simple UART0 -> UART1 communication (no parity)
#     addi gp, gp, 1
#     jal ra, test_simple_tx_rx

#     # Test 2: Simple UART1 -> UART0 communication (no parity)
#     addi gp, gp, 1
#     jal ra, test_reverse_tx_rx

#     # Test 3: Communication with even parity
#     addi gp, gp, 1
#     jal ra, test_even_parity_comm

#     # Test 4: Communication with odd parity
#     addi gp, gp, 1
#     jal ra, test_odd_parity_comm

#     # Test 5: Back-to-back transmission
#     addi gp, gp, 1
#     # jal ra, test_back_to_back

#     # Test 6-9: Multiple data patterns
#     addi gp, gp, 1
#     jal ra, test_data_patterns

#     # Test 10: Bidirectional communication
#     addi gp, gp, 1
#     jal ra, test_bidirectional

#     # Test 11: Communication after disable/enable
#     addi gp, gp, 1
#     jal ra, test_enable_disable

#     # Restore return address
#     mv   ra, s2
#     ret

# # ===============================================================================
# # 2. INTERRUPT FLAG TESTS (Tests 12-19)
# # ===============================================================================

# interrupt_flag_tests:
#     # Save return address
#     mv   s2, ra

#     # Test 12: TX Complete Interrupt Flag (UTCIF)
#     addi gp, gp, 1
#     jal ra, test_tx_complete_flag

#     # Test 13: TX Empty Interrupt Flag (UTEIF)
#     addi gp, gp, 1
#     jal ra, test_tx_empty_flag

#     # Test 14: RX Complete Interrupt Flag (RCIF)
#     addi gp, gp, 1
#     jal ra, test_rx_complete_flag

#     # Test 15: Interrupt flag clearing
#     addi gp, gp, 1
#     jal ra, test_flag_clearing

#     # Test 16: Multiple interrupt flags simultaneously
#     addi gp, gp, 1
#     jal ra, test_multiple_flags

#     # Test 17: Interrupt enable/disable functionality
#     addi gp, gp, 1
#     jal ra, test_interrupt_enable

#     # Test 18: Flag behavior during continuous operation
#     addi gp, gp, 1
#     jal ra, test_continuous_flags

#     # Test 19: Flag timing verification
#     addi gp, gp, 1
#     jal ra, test_flag_timing

#     # Restore return address
#     mv   ra, s2
#     ret



# # Test 1: Simple UART0 -> UART1 communication (no parity)
# test_simple_tx_rx:
#     # Save return address
#     mv s1, ra

#     # Configure both UARTs: Enable, no parity, all interrupts enabled
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear any pending interrupts
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # lw t1, UART_RX(a0)  # Clear RX register to ensure no stale data
#     # lw t1, UART_RX(a1)  # Clear RX register to ensure no stale data

#     # Send test byte from UART0 to UART1 
#     li s3, 0xA5
#     sw s3, UART_TX(a0)



#     # Wait for RX complete on UART1
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     # If here, then UART1 RX Complete (assuming uart1_rc triggered)

#     # Verify received data 
#     lw t1, UART_RX(a1)
#     bne s3, t1, fail

#     # Reading RX register should clear RX flags
#     lw t1, UART_RX(a1)

#     # Restore return address and return
#     mv ra, s1
#     ret

# # Test 2: Simple UART1 -> UART0 communication (no parity)
# test_reverse_tx_rx:
#     # Save return address
#     mv s1, ra

#     # Send test byte from UART1 to UART0 
#     li s3, 0x5A
#     sw s3, UART_TX(a1)

#     # Wait for RX complete on UART0
#     mv a4, a0
#     jal ra, en_uart0_irqs
#     extinguish;
#     # jal ra, wait_rx_complete

#     # Verify received data 
#     lw t1, UART_RX(a0)
#     bne s3, t1, fail

#     # Clear RX flags
#     lw t1, UART_RX(a0)

#     # Restore return address and return
#     mv ra, s1
#     ret

# # Test 3: Communication with even parity
# test_even_parity_comm:
#     # Save return address
#     mv s1, ra

#     # Configure both UARTs: Enable, even parity, all interrupts
#     li s5, UCR_EN_MASK | UCR_PEN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear interrupts TODO?
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Send byte with even parity 
#     li s3, 0x33  # Even number of 1s
#     sw s3, UART_TX(a0)

#     # Wait and verify
#     mv a4, a1 #Wait fn assumes base addr is in a4
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     lw t1, UART_RX(a1)
#     bne s3, t1, fail

#     # Check no parity error
#     lw t2, UART_SR(a1)
#     andi t2, t2, USR_PEF_MASK
#     bnez t2, fail

#     # Clear RX flags
#     lw t1, UART_RX(a1)

#     # Restore return address
#     mv ra, s1
#     ret

# # Test 4: Communication with odd parity
# test_odd_parity_comm:
#     mv s1, ra

#     # Configure both UARTs: Enable, odd parity, all interrupts
#     li s5, UCR_EN_MASK | UCR_PEN_MASK | UCR_PSEL_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear interrupts
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Send byte with odd parity 
#     li s3, 0x07  # Odd number of 1s
#     sw s3, UART_TX(a0)

#     # Wait and verify
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     lw t1, UART_RX(a1)
#     bne s3, t1, fail

#     # Check no parity error
#     lw t2, UART_SR(a1)
#     andi t2, t2, USR_PEF_MASK
#     bnez t2, fail

#     # Clear RX flags
#     lw t1, UART_RX(a1)
#     mv ra, s1
#     ret

# # Test 5: Back-to-back transmission
# test_back_to_back:
#     mv s1, ra

#     # Configure UARTs (no parity)
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear interrupts
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Store both test bytes in saved registers (changed from s2/s3 to s3/s4)
#     li s3, 0x11  # First byte
#     li s4, 0x22  # Second byte

#     # Send first byte
#     sw s3, UART_TX(a0)

#     # Wait for TX ready for next byte
#     mv a4, a0
#     jal ra, wait_tx_ready

#     # Clear tx'ers interrupts before sending second byte
#     mv a3, a0
#     jal ra, clear_uart_interrupts

#     # Send second byte immediately
#     sw s4, UART_TX(a0)
#     # jal ra, wait_tx_complete # Wait for TX completion
#     # extinguish;

#     # Wait for both bytes to be received
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     extinguish; #For second byte
#     lw t2, UART_RX(a1)  # Read second byte
#     bne s4, t2, fail

#     mv ra, s1
#     ret

# # Test 6-9: Multiple data patterns
# test_data_patterns:
#     mv s1, ra

#     # Configure UARTs
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Test pattern: 0x00 
#     li s3, 0x00
#     jal ra, test_single_pattern

#     # Test pattern: 0xFF
#     addi gp, gp, 1
#     li s3, 0xFF
#     jal ra, test_single_pattern

#     # Test pattern: 0x55 (alternating)
#     addi gp, gp, 1
#     li s3, 0x55
#     jal ra, test_single_pattern

#     # Test pattern: 0xAA (inverse alternating)
#     addi gp, gp, 1
#     li s3, 0xAA
#     jal ra, test_single_pattern

#     mv ra, s1
#     ret

# test_single_pattern:
#     mv s7, ra  # Save return address for this subroutine

#     # Clear interrupts
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Send pattern in s3 
#     sw s3, UART_TX(a0)

#     # Wait and verify
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     lw t1, UART_RX(a1)
#     bne s3, t1, fail

#     # Clear RX flags
#     lw t1, UART_RX(a1)

#     mv ra, s7
#     ret

# # Test 10: Bidirectional communication
# test_bidirectional:
#     mv s1, ra

#     # jal ra, disable_all_irqs

#     # Configure UARTs
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear interrupts
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Store test data in saved registers (changed from s2/s3 to s3/s4)
#     li s3, 0x12  # UART0 -> UART1
#     li s4, 0x34  # UART1 -> UART0

#     # Send from both UARTs simultaneously
#     sw s3, UART_TX(a0)
#     sw s4, UART_TX(a1)

#     # Wait for both receptions
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     # jal ra, en_uart1_irqs
#     # extinguish;
#     mv a4, a0
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     # Hopefully this is enough waiting - changed to just polling

#     # Verify data
#     lw t2, UART_RX(a1)
#     bne s3, t2, fail
#     lw t2, UART_RX(a0)
#     bne s4, t2, fail

#     mv ra, s1
#     ret

# # Test 11: Communication after disable/enable
# test_enable_disable:
#     mv s1, ra

#     # Store configuration and test data 
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     li s3, 0x77  # Test data

#     # Configure UARTs
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Disable UART1
#     li t0, 0x00
#     sw t0, UART_CR(a1)

#     # Try to send (should not be received)
#     li t0, 0x99
#     sw t0, UART_TX(a0)

#     # Wait a bit (for transfer to complete)
#     li t1, 50000
# disable_wait_loop:
#     addi t1, t1, -1
#     bnez t1, disable_wait_loop

#     # Re-enable UART1
#     sw s5, UART_CR(a1)

#     # Clear interrupts
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Send valid data 
#     sw s3, UART_TX(a0)

#     # Wait and verify
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     jal ra, en_uart1_irqs
#     extinguish;
#     lw t1, UART_RX(a1)
#     bne s3, t1, fail

#     mv ra, s1
#     ret

# # Test 12: TX Complete Interrupt Flag (UTCIF)
# test_tx_complete_flag:
#     mv s1, ra

#     # Configure UART0
#     li s5, UCR_EN_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)

#     # Clear interrupt flags
#     mv a3, a0
#     jal ra, clear_uart_interrupts

#     # Send byte 
#     li s3, 0xAB
#     sw s3, UART_TX(a0)

#     # Wait for transmission complete
#     mv a4, a0
#     # jal ra, wait_tx_complete
#     extinguish;

#     # Verify UTCIF is set
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTCIF_MASK
#     beqz t1, fail

#     # Clear flag and verify it's cleared
#     li t0, USR_UTCIF_MASK
#     sw t0, UART_SR(a0)
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTCIF_MASK
#     bnez t1, fail

#     mv ra, s1
#     ret

# # Test 13: TX Empty Interrupt Flag (UTEIF)
# test_tx_empty_flag:
#     mv s1, ra

#     # Configure UART0
#     li s5, UCR_EN_MASK | UCR_TEIE_MASK
#     sw s5, UART_CR(a0)

#     # Clear interrupt flags
#     mv a3, a0
#     jal ra, clear_uart_interrupts

#     # Send byte 
#     li s3, 0xCD
#     sw s3, UART_TX(a0)

#     # UTEIF should be cleared when TX register is loaded
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTEIF_MASK
#     bnez t1, fail

#     # Wait for transmission to start
#     mv a4, a0
#     # jal ra, wait_tx_ready
#     extinguish;

#     # UTEIF should now be set (TX register empty, ready for new data)
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTEIF_MASK
#     beqz t1, fail

#     mv ra, s1
#     ret

# # Test 14: RX Complete Interrupt Flag (RCIF)
# test_rx_complete_flag:
#     mv s1, ra

#     # Configure both UARTs
#     li s5, UCR_EN_MASK | UCR_CIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear interrupt flags
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Send byte from UART0 to UART1 
#     li s3, 0xEF
#     sw s3, UART_TX(a0)

#     # Wait for RX complete
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     extinguish;

#     # Verify RCIF is set
#     lw t1, UART_SR(a1)
#     andi t1, t1, USR_RCIF_MASK
#     beqz t1, fail

#     # Reading RX register should clear RCIF
#     lw t2, UART_RX(a1)
#     lw t1, UART_SR(a1)
#     andi t1, t1, USR_RCIF_MASK
#     bnez t1, fail

#     mv ra, s1
#     ret

# # Test 15: Interrupt flag clearing
# test_flag_clearing:
#     mv s1, ra

#     # Configure UARTs with all interrupts enabled
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Generate all interrupt conditions 
#     li s3, 0x42
#     sw s3, UART_TX(a0)  # This will generate UTEIF and eventually UTCIF

#     # Wait for TX complete
#     mv a4, a0
#     # jal ra, wait_tx_complete
#     extinguish;

#     # Clear all interrupt flags at once
#     li t0, USR_UTCIF_MASK | USR_UTEIF_MASK
#     sw t0, UART_SR(a0)

#     # Verify all flags are cleared
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTCIF_MASK | USR_UTEIF_MASK
#     bnez t1, fail

#     mv ra, s1
#     ret

# # Test 16: Multiple interrupt flags simultaneously
# test_multiple_flags:
#     mv s1, ra

#     # Configure both UARTs
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear all flags
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Store test data 
#     li s3, 0x88

#     # Generate TX and RX activity simultaneously
#     sw s3, UART_TX(a0)  # UART0 -> UART1
#     sw s3, UART_TX(a1)  # UART1 -> UART0

#     # Wait for both operations to complete
#     mv a4, a0
#     # jal ra, wait_rx_complete
#     # jal ra, wait_tx_complete
#     # extinguish;
#     mv a4, a1
#     # jal ra, wait_rx_complete
#     # jal ra, wait_tx_complete
#     extinguish;

#     # Check that multiple flags are set on both UARTs
#     lw t1, UART_SR(a0)
#     andi t2, t1, USR_RCIF_MASK
#     beqz t2, fail  # Should have RCIF
#     andi t2, t1, USR_UTCIF_MASK
#     beqz t2, fail  # Should have UTCIF

#     # Clear by reading RX
#     lw t1, UART_RX(a0)
#     lw t1, UART_RX(a1)



#     mv ra, s1
#     ret

# # Test 17: Interrupt enable/disable functionality
# test_interrupt_enable:
#     # mv s1, ra

#     # # Store configuration values 
#     # li s5, UCR_EN_MASK  # UART enabled, no interrupts
#     # li s7, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK  # All interrupts

#     # # Test with interrupts disabled
#     # sw s5, UART_CR(a0)
#     # sw s5, UART_CR(a1)

#     # # Clear all flags
#     # mv a3, a0
#     # jal ra, clear_uart_interrupts
#     # mv a3, a1
#     # jal ra, clear_uart_interrupts

#     # # Send byte 
#     # li s3, 0x66
#     # sw s3, UART_TX(a0)

#     # # Wait for transmission
#     # mv a4, a0
#     # jal ra, wait_tx_complete

#     # # TODO: Re-check once interrupts are implemented
#     # # Interrupt flags should still be set even if interrupts are disabled
#     # lw t1, UART_SR(a0)
#     # andi t1, t1, USR_UTCIF_MASK
#     # beqz t1, fail

#     # # Read data to clear flags
#     # lw t1, UART_RX(a1)
#     # bne t1, s3, fail

#     # # Re-enable interrupts 
#     # sw s7, UART_CR(a0)
#     # sw s7, UART_CR(a1)


#     # mv ra, s1
#     ret

# # Test 18: Flag behavior during continuous operation
# test_continuous_flags:
#     mv s1, ra

#     # Configure UARTs
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Send multiple bytes continuously
#     li s3, 5     # Send 5 bytes (counter)
#     li s4, 0x10  # Starting pattern

# continuous_loop:
#     # Clear flags
#     mv a3, a0
#     jal ra, clear_uart_interrupts
#     mv a3, a1
#     jal ra, clear_uart_interrupts

#     # Send current pattern
#     sw s4, UART_TX(a0)

#     # Wait for completion and verify flags
#     mv a4, a1
#     jal ra, wait_rx_complete
    
#     # Verify RCIF is set
#     lw t1, UART_SR(a1)
#     andi t1, t1, USR_RCIF_MASK
#     beqz t1, fail

#     # Read data to clear flags
#     lw t1, UART_RX(a1)
#     bne t1, s4, fail

#     # Next iteration
#     addi s4, s4, 1
#     addi s3, s3, -1
#     bnez s3, continuous_loop

#     mv ra, s1
#     ret

# # Test 19: Flag timing verification
# test_flag_timing:
#     mv s1, ra

#     # Configure UARTs
#     li s5, UCR_EN_MASK | UCR_CIE_MASK | UCR_TEIE_MASK | UCR_TCIE_MASK
#     sw s5, UART_CR(a0)
#     sw s5, UART_CR(a1)

#     # Clear flags
#     mv a3, a0
#     jal ra, clear_uart_interrupts

#     # Verify no TX flags are set initially
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTCIF_MASK | USR_UTEIF_MASK
#     bnez t1, fail

#     # Send byte 
#     li s3, 0x99
#     sw s3, UART_TX(a0)

#     # UTEIF should be clear immediately after writing TX
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTEIF_MASK
#     bnez t1, fail

#     # Wait for TX ready
#     mv a4, a0
#     jal ra, wait_tx_ready

#     # UTEIF should now be set
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTEIF_MASK
#     beqz t1, fail

#     # Wait for TX complete
#     jal ra, wait_tx_complete

#     # UTCIF should now be set
#     lw t1, UART_SR(a0)
#     andi t1, t1, USR_UTCIF_MASK
#     beqz t1, fail

#     # Read RX to clear flags
#     lw t1, UART_RX(a1)

#     mv ra, s1
#     ret

# # ===============================================================================
# # UTILITY FUNCTIONS
# # ===============================================================================

# # Initialize GPIO for UART pins
# init_gpio_uart:
#     li t0, 0xF0
#     sw t0, GPIO_PxSEL(a2)
#     ret

# # Clear UART interrupt flags (base address in a3)
# clear_uart_interrupts:
#     li t0, USR_UTCIF_MASK | USR_UTEIF_MASK
#     sw t0, UART_SR(a3)
#     ret

# # Wait for RX completion (UART base in a4)
# wait_rx_complete:
#     lw t0, UART_SR(a4)
#     andi t0, t0, USR_RCIF_MASK
#     beqz t0, wait_rx_complete
#     ret

# # Wait for TX ready (UART base in a4)
# wait_tx_ready:
#     lw t0, UART_SR(a4)
#     andi t0, t0, USR_TX_BUSY_MASK
#     bnez t0, wait_tx_ready
#     ret

# # Wait for TX complete (UART base in a4)
# wait_tx_complete:
#     lw t0, UART_SR(a4)
#     andi t0, t0, USR_UTCIF_MASK
#     beqz t0, wait_tx_complete
#     ret

# en_uart1_irqs:
#     # Configure Interrupts 
#     # li t0, IRQB_UART0_RC | IRQB_UART0_TC #In lower IRQ word
#     li t1, IRQB_UART1_RC | IRQB_UART1_TC #In middle IRQ word
#     sw zero, SYS_IRQ_ENL(a5)
#     sw t1, SYS_IRQ_ENM(a5)
#     sw zero, SYS_IRQ_ENH(a5)
#     ret

# en_uart0_irqs:
#     # Configure Interrupts 
#     li t0, IRQB_UART0_RC | IRQB_UART0_TC #In lower IRQ word
#     # li t1, IRQB_UART1_RC | IRQB_UART1_TC #In middle IRQ word
#     sw t0, SYS_IRQ_ENL(a5)
#     sw zero, SYS_IRQ_ENM(a5)
#     sw zero, SYS_IRQ_ENH(a5)
#     ret

# disable_all_irqs:
#     sw zero, SYS_IRQ_CR(a5)
#     ret

# RVTEST_CODE_END


# # ===============================================================================

# # # Start of interrupt section
# .section .isr_uart0_rc , "ax"
# isr_uart0_rc:
#     SAVE_CONTEXT()
#     li a1, PERIPH_UART0_BASE
#     li t0, USR_RCIF_MASK
#     sw t0, UART_RX(a1) 
#     ignite;
#     RESTORE_CONTEXT()


# .section .isr_uart0_te , "ax"
# isr_uart0_te:
#     SAVE_CONTEXT()

#     RESTORE_CONTEXT()


# .section .isr_uart0_tc , "ax"
# isr_uart0_tc:
#     SAVE_CONTEXT()
#     li a1, PERIPH_UART0_BASE
#     li t0, USR_UTCIF_MASK
#     sw t0, UART_RX(a1) 
#     ignite; 
#     RESTORE_CONTEXT()

# .section .isr_uart1_rc , "ax"
# isr_uart1_rc:
#     SAVE_CONTEXT()
#     li a1, PERIPH_UART1_BASE
#     li t0, USR_RCIF_MASK
#     sw t0, UART_RX(a1) 
#     ignite; 
#     RESTORE_CONTEXT()


# .section .isr_uart1_te , "ax"
# isr_uart1_te:
#     SAVE_CONTEXT()

#     RESTORE_CONTEXT()


# .section .isr_uart1_tc , "ax"
# isr_uart1_tc:
#     SAVE_CONTEXT()
#     li a1, PERIPH_UART1_BASE
#     li t0, USR_UTCIF_MASK
#     sw t0, UART_RX(a1) 
#     ignite; 
#     RESTORE_CONTEXT()


