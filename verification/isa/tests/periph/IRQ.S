#*****************************************************************************
# IRQ_TESTBENCH.S
#-----------------------------------------------------------------------------
# Comprehensive IRQ handling testbench for RISC-V assembly (riscv32ui)
# Author: Maxx Seminario
# Date: 09-05-2025
#
# Test Categories:
# 1-5: Basic IRQ Vector Tests (5 tests)
# 6-10: Context Preservation Tests (5 tests) 
# 11-15: Priority and Nesting Tests (5 tests)
# 16-20: Multiple IRQ Source Tests (5 tests)
# 21-25: IRQ Enable/Disable Tests (5 tests)
# 26-30: Edge Cases and Error Conditions (5 tests)
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"

# Include your IVT definitions
DEFINE_IVT()
DEFINE_ISR_STUBS()

# Peripheral Base Addresses
#define SYSTEM_BASE_ADDR   0x4900
#define GPIO0_BASE_ADDR    0x4100
#define GPIO1_BASE_ADDR    0x4200
#define GPIO2_BASE_ADDR    0x4300
#define GPIO3_BASE_ADDR    0x4400
#define TIMER0_BASE_ADDR   0x4500
#define TIMER1_BASE_ADDR   0x4600
#define UART0_BASE_ADDR    0x4700
#define UART1_BASE_ADDR    0x4800
#define SPI0_BASE_ADDR     0x4A00
#define SPI1_BASE_ADDR     0x4B00

# System Register Offsets
#define SYS_IRQ_EN         0x14
#define SYS_IRQ_PRI        0x18
#define SYS_IRQ_STATUS     0x1C

# GPIO Register Offsets
#define GPIO_DATA          0x00
#define GPIO_DIR           0x04
#define GPIO_IRQ_EN        0x08
#define GPIO_IRQ_EDGE      0x0C
#define GPIO_IRQ_FLAG      0x10

# Timer Register Offsets
#define TIMER_CTRL         0x00
#define TIMER_COUNT        0x04
#define TIMER_COMPARE      0x08
#define TIMER_IRQ_EN       0x0C
#define TIMER_IRQ_FLAG     0x10

# UART Register Offsets
#define UART_DATA          0x00
#define UART_CTRL          0x04
#define UART_STATUS        0x08
#define UART_IRQ_EN        0x0C
#define UART_IRQ_FLAG      0x10

# SPI Register Offsets
#define SPI_DATA           0x00
#define SPI_CTRL           0x04
#define SPI_STATUS         0x08
#define SPI_IRQ_EN         0x0C
#define SPI_IRQ_FLAG       0x10

# IRQ bit definitions
#define IrqBitSYSTEM       0
#define IrqBitGPIO0        1
#define IrqBitSPI0         2
#define IrqBitSPI1         3
#define IrqBitUART0        4
#define IrqBitTIMER0       5
#define IrqBitTIMER1       6
#define IrqBitGPIO1        7
#define IrqBitGPIO2        8
#define IrqBitGPIO3        9
#define IrqBitUART1        10
#define IrqBitNN0          11
#define IrqBitAFE0         12

# Test data locations for context verification
#define TEST_CONTEXT_BASE  0x10000
#define PRE_IRQ_MARKER     0xDEADBEEF
#define POST_IRQ_MARKER    0xBEEFDEAD
#define IRQ_HANDLED_MARKER 0xCAFEBABE
#define CONTEXT_SAVE_AREA  0x11000

# Timer control bits
#define TIMER_EN           0x01
#define TIMER_IRQ_EN_BIT   0x01

# GPIO control bits
#define GPIO_IRQ_EN_BIT    0x01
#define GPIO_EDGE_RISING   0x01

# UART control bits
#define UART_TX_IRQ_EN     0x01
#define UART_RX_IRQ_EN     0x02

RVTEST_RV32U
RVTEST_CODE_BEGIN

# Initialize test environment
li a0, SYSTEM_BASE_ADDR
li s10, TEST_CONTEXT_BASE

# Run all IRQ tests
jal ra, test_basic_irq_vectors
jal ra, test_context_preservation
jal ra, test_irq_priority_handling
jal ra, test_multiple_irq_sources
jal ra, test_irq_enable_disable
jal ra, test_irq_edge_cases

TEST_PASSFAIL

# ===============================================================================
# Tests 1-5: Basic IRQ Vector Tests
# ===============================================================================
test_basic_irq_vectors:
    mv s1, ra
    
    # Test 1: SYSTEM IRQ (IRQ 0)
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, trigger_system_irq
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 2: GPIO0 IRQ (IRQ 1)  
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, trigger_gpio0_irq
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 3: Timer IRQ (IRQ 5)
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, trigger_timer0_irq
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 4: UART IRQ (IRQ 4)
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, trigger_uart0_irq
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 5: Verify no spurious IRQs
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, wait_no_irq_period
    jal ra, verify_no_irq_occurred
    jal ra, cleanup_irq_test
    
    mv ra, s1
    ret

# ===============================================================================
# Tests 6-10: Context Preservation Tests
# ===============================================================================
test_context_preservation:
    mv s1, ra
    
    # Test 6: Register preservation (x1-x31)
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, load_test_context
    jal ra, trigger_system_irq
    jal ra, verify_context_preserved
    jal ra, cleanup_irq_test
    
    # Test 7: Stack pointer preservation
    addi gp, gp, 1
    jal ra, setup_irq_test
    mv s2, sp  # Save original SP
    li sp, 0x12000  # Set test SP
    li t1, 0x12000  # Expected SP value
    jal ra, trigger_gpio0_irq
    bne sp, t1, fail  # SP should be restored
    mv sp, s2  # Restore original SP
    jal ra, cleanup_irq_test
    
    # Test 8: Multiple register preservation
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, 0x11111111
    li t1, 0x22222222
    li t2, 0x33333333
    li t3, 0x44444444
    li t4, 0x55555555
    li t5, 0x66666666
    li t6, 0x77777777
    jal ra, trigger_timer0_irq
    li s3, 0x11111111
    bne t0, s3, fail
    li s3, 0x22222222
    bne t1, s3, fail
    li s3, 0x33333333
    bne t2, s3, fail
    jal ra, cleanup_irq_test
    
    # Test 9: Saved register preservation (s0-s11)
    addi gp, gp, 1
    jal ra, setup_irq_test
    li s3, 0xAAAABBBB
    li s4, 0xCCCCDDDD
    li s5, 0xEEEEFFFF
    jal ra, trigger_uart0_irq
    li s6, 0xAAAABBBB
    bne s3, s6, fail
    li s6, 0xCCCCDDDD
    bne s4, s6, fail
    li s6, 0xEEEEFFFF
    bne s5, s6, fail
    jal ra, cleanup_irq_test
    
    # Test 10: Program counter preservation
    addi gp, gp, 1
    jal ra, setup_irq_test
    li s3, PRE_IRQ_MARKER
    sw s3, 0(s10)
    jal ra, trigger_gpio0_irq
    li s3, POST_IRQ_MARKER
    sw s3, 4(s10)
    # Verify both markers exist (PC was preserved and execution continued)
    lw t0, 0(s10)
    li t1, PRE_IRQ_MARKER
    bne t0, t1, fail
    lw t0, 4(s10)
    li t1, POST_IRQ_MARKER
    bne t0, t1, fail
    jal ra, cleanup_irq_test
    
    mv ra, s1
    ret

# ===============================================================================
# Tests 11-15: Priority and Nesting Tests
# ===============================================================================
test_irq_priority_handling:
    mv s1, ra
    
    # Test 11: High priority IRQ (Timer) vs Low priority (GPIO)
    addi gp, gp, 1
    jal ra, setup_irq_test
    # Set Timer higher priority than GPIO
    li t0, SYSTEM_BASE_ADDR
    li t1, 0x1000  # Timer priority = 1, GPIO priority = 0
    sw t1, SYS_IRQ_PRI(t0)
    # Enable both IRQs
    li t1, (1 << IrqBitTIMER0) | (1 << IrqBitGPIO0)
    sw t1, SYS_IRQ_EN(t0)
    # Trigger both simultaneously
    jal ra, trigger_timer0_irq_no_wait
    jal ra, trigger_gpio0_irq_no_wait
    # Timer should be handled first
    jal ra, verify_timer_irq_handled_first
    jal ra, cleanup_irq_test
    
    # Test 12: IRQ nesting capability
    addi gp, gp, 1
    jal ra, setup_irq_test
    # Configure nested IRQ test
    jal ra, setup_nested_irq_test
    jal ra, trigger_nested_irq_sequence
    jal ra, verify_nested_irq_handling
    jal ra, cleanup_irq_test
    
    # Test 13: IRQ priority inversion test
    addi gp, gp, 1
    jal ra, setup_irq_test
    # Set GPIO higher priority than Timer
    li t0, SYSTEM_BASE_ADDR
    li t1, 0x0100  # GPIO priority = 1, Timer priority = 0
    sw t1, SYS_IRQ_PRI(t0)
    li t1, (1 << IrqBitTIMER0) | (1 << IrqBitGPIO0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_timer0_irq_no_wait
    jal ra, trigger_gpio0_irq_no_wait
    # GPIO should be handled first now
    jal ra, verify_gpio_irq_handled_first
    jal ra, cleanup_irq_test
    
    # Test 14: Same priority IRQ handling
    addi gp, gp, 1
    jal ra, setup_irq_test
    # Set same priority for both
    li t0, SYSTEM_BASE_ADDR
    li t1, 0x0000  # Both priority = 0
    sw t1, SYS_IRQ_PRI(t0)
    li t1, (1 << IrqBitUART0) | (1 << IrqBitSPI0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_uart0_irq_no_wait
    jal ra, trigger_spi0_irq_no_wait
    # Lower IRQ number should be handled first (UART0=4, SPI0=2)
    jal ra, verify_spi_irq_handled_first
    jal ra, cleanup_irq_test
    
    # Test 15: Maximum priority levels
    addi gp, gp, 1
    jal ra, setup_irq_test
    # Set maximum priority difference
    li t0, SYSTEM_BASE_ADDR
    li t1, 0xF000  # Max priority for Timer
    sw t1, SYS_IRQ_PRI(t0)
    li t1, (1 << IrqBitTIMER0) | (1 << IrqBitGPIO0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_gpio0_irq_no_wait
    jal ra, trigger_timer0_irq_no_wait
    jal ra, verify_timer_irq_handled_first
    jal ra, cleanup_irq_test
    
    mv ra, s1
    ret

# ===============================================================================
# Tests 16-20: Multiple IRQ Source Tests
# ===============================================================================
test_multiple_irq_sources:
    mv s1, ra
    
    # Test 16: Two IRQs triggered simultaneously
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitGPIO0) | (1 << IrqBitTIMER0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_gpio0_irq_no_wait
    jal ra, trigger_timer0_irq_no_wait
    jal ra, verify_both_irqs_handled
    jal ra, cleanup_irq_test
    
    # Test 17: Three IRQs in sequence
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitGPIO0) | (1 << IrqBitTIMER0) | (1 << IrqBitUART0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_gpio0_irq
    jal ra, wait_short
    jal ra, trigger_timer0_irq
    jal ra, wait_short
    jal ra, trigger_uart0_irq
    jal ra, verify_three_irqs_handled
    jal ra, cleanup_irq_test
    
    # Test 18: All peripheral IRQs enabled
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, 0x1FFF  # Enable all 13 IRQs
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_system_irq
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 19: IRQ burst handling
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitGPIO0)
    sw t1, SYS_IRQ_EN(t0)
    # Trigger multiple IRQs quickly
    jal ra, trigger_gpio0_irq_no_wait
    jal ra, trigger_gpio0_irq_no_wait
    jal ra, trigger_gpio0_irq_no_wait
    jal ra, verify_irq_burst_handled
    jal ra, cleanup_irq_test
    
    # Test 20: Cross-peripheral IRQ interaction
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitSPI0) | (1 << IrqBitSPI1)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_spi0_irq
    jal ra, trigger_spi1_irq
    jal ra, verify_spi_irqs_handled
    jal ra, cleanup_irq_test
    
    mv ra, s1
    ret

# ===============================================================================
# Tests 21-25: IRQ Enable/Disable Tests
# ===============================================================================
test_irq_enable_disable:
    mv s1, ra
    
    # Test 21: IRQ enable functionality
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitGPIO0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_gpio0_irq
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 22: IRQ disable functionality
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    sw zero, SYS_IRQ_EN(t0)  # Disable all IRQs
    jal ra, trigger_gpio0_irq
    jal ra, verify_no_irq_occurred
    jal ra, cleanup_irq_test
    
    # Test 23: Selective IRQ enable
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitTIMER0)  # Only Timer enabled
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_gpio0_irq  # Should not generate IRQ
    jal ra, verify_no_irq_occurred
    jal ra, trigger_timer0_irq  # Should generate IRQ
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 24: Dynamic IRQ enable/disable
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitUART0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_uart0_irq
    jal ra, verify_irq_handled
    # Now disable and test
    sw zero, SYS_IRQ_EN(t0)
    jal ra, clear_irq_markers
    jal ra, trigger_uart0_irq
    jal ra, verify_no_irq_occurred
    jal ra, cleanup_irq_test
    
    # Test 25: IRQ enable register bit patterns
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    # Test alternating pattern
    li t1, 0x1555  # 010101010101
    sw t1, SYS_IRQ_EN(t0)
    lw t2, SYS_IRQ_EN(t0)
    bne t1, t2, fail
    # Test inverted pattern
    li t1, 0x0AAA  # 101010101010
    sw t1, SYS_IRQ_EN(t0)
    lw t2, SYS_IRQ_EN(t0)
    bne t1, t2, fail
    jal ra, cleanup_irq_test
    
    mv ra, s1
    ret

# ===============================================================================
# Tests 26-30: Edge Cases and Error Conditions
# ===============================================================================
test_irq_edge_cases:
    mv s1, ra
    
    # Test 26: IRQ during IRQ handler execution
    addi gp, gp, 1
    jal ra, setup_irq_test
    jal ra, setup_recursive_irq_test
    jal ra, trigger_recursive_irq
    jal ra, verify_recursive_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 27: IRQ with corrupted stack
    addi gp, gp, 1
    jal ra, setup_irq_test
    # Simulate stack corruption scenario
    mv s2, sp
    li sp, 0x1  # Invalid stack pointer
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitSYSTEM)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_system_irq
    mv sp, s2  # Restore stack
    jal ra, verify_irq_with_bad_stack
    jal ra, cleanup_irq_test
    
    # Test 28: Rapid IRQ enable/disable transitions
    addi gp, gp, 1
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitGPIO0)
    li t2, 100
rapid_toggle_loop:
    sw t1, SYS_IRQ_EN(t0)
    sw zero, SYS_IRQ_EN(t0)
    addi t2, t2, -1
    bnez t2, rapid_toggle_loop
    # Final state should be disabled
    lw t3, SYS_IRQ_EN(t0)
    bnez t3, fail
    
    # Test 29: IRQ with maximum delay
    addi gp, gp, 1
    jal ra, setup_irq_test
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitTIMER0)
    sw t1, SYS_IRQ_EN(t0)
    jal ra, trigger_timer0_irq
    jal ra, wait_long  # Long delay
    jal ra, verify_irq_handled
    jal ra, cleanup_irq_test
    
    # Test 30: IRQ register boundary conditions
    addi gp, gp, 1
    li t0, SYSTEM_BASE_ADDR
    li t1, 0xFFFF  # All bits set
    sw t1, SYS_IRQ_EN(t0)
    lw t2, SYS_IRQ_EN(t0)
    li t3, 0x1FFF  # Only valid bits should be set
    bne t2, t3, fail
    li t1, 0x0000  # All bits clear
    sw t1, SYS_IRQ_EN(t0)
    lw t2, SYS_IRQ_EN(t0)
    bnez t2, fail
    
    mv ra, s1
    ret

# ===============================================================================
# Helper Functions
# ===============================================================================

setup_irq_test:
    # Clear all previous IRQ states
    li t0, SYSTEM_BASE_ADDR
    sw zero, SYS_IRQ_EN(t0)
    sw zero, SYS_IRQ_PRI(t0)
    
    # Clear all peripheral IRQ flags
    jal ra, clear_all_peripheral_irq_flags
    
    # Clear test markers
    jal ra, clear_irq_markers
    
    ret

cleanup_irq_test:
    # Disable all IRQs
    li t0, SYSTEM_BASE_ADDR
    sw zero, SYS_IRQ_EN(t0)
    sw zero, SYS_IRQ_PRI(t0)
    
    # Clear all peripheral IRQ flags
    jal ra, clear_all_peripheral_irq_flags
    
    ret

clear_all_peripheral_irq_flags:
    # Clear GPIO0 IRQ flags
    li t0, GPIO0_BASE_ADDR
    li t1, 0xFF
    sw t1, GPIO_IRQ_FLAG(t0)
    
    # Clear Timer0 IRQ flags  
    li t0, TIMER0_BASE_ADDR
    li t1, 0xFF
    sw t1, TIMER_IRQ_FLAG(t0)
    
    # Clear UART0 IRQ flags
    li t0, UART0_BASE_ADDR
    li t1, 0xFF
    sw t1, UART_IRQ_FLAG(t0)
    
    # Clear SPI0 IRQ flags
    li t0, SPI0_BASE_ADDR
    li t1, 0xFF
    sw t1, SPI_IRQ_FLAG(t0)
    
    # Clear SPI1 IRQ flags
    li t0, SPI1_BASE_ADDR
    li t1, 0xFF
    sw t1, SPI_IRQ_FLAG(t0)
    
    ret

clear_irq_markers:
    li t0, TEST_CONTEXT_BASE
    sw zero, 0(t0)   # Clear PRE_IRQ_MARKER
    sw zero, 4(t0)   # Clear POST_IRQ_MARKER
    sw zero, 8(t0)   # Clear IRQ_HANDLED_MARKER
    sw zero, 12(t0)  # Clear additional markers
    sw zero, 16(t0)
    sw zero, 20(t0)
    ret

trigger_system_irq:
    # Enable system IRQ
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitSYSTEM)
    sw t1, SYS_IRQ_EN(t0)
    
    # Trigger system IRQ (implementation specific)
    # This would typically involve writing to a system register
    # that generates an IRQ condition
    
    jal ra, wait_medium
    ret

trigger_gpio0_irq:
    # Enable GPIO0 IRQ
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitGPIO0)
    sw t1, SYS_IRQ_EN(t0)
    
    # Configure GPIO0 for IRQ generation
    li t0, GPIO0_BASE_ADDR
    li t1, GPIO_IRQ_EN_BIT
    sw t1, GPIO_IRQ_EN(t0)
    li t1, GPIO_EDGE_RISING
    sw t1, GPIO_IRQ_EDGE(t0)
    
    # Generate rising edge on GPIO0
    sw zero, GPIO_DATA(t0)
    li t1, 0x01
    sw t1, GPIO_DATA(t0)
    
    jal ra, wait_medium
    ret

trigger_timer0_irq:
    # Enable Timer0 IRQ
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitTIMER0)
    sw t1, SYS_IRQ_EN(t0)
    
    # Configure Timer0 for IRQ generation
    li t0, TIMER0_BASE_ADDR
    li t1, 100  # Small compare value
    sw t1, TIMER_COMPARE(t0)
    li t1, TIMER_IRQ_EN_BIT
    sw t1, TIMER_IRQ_EN(t0)
    li t1, TIMER_EN
    sw t1, TIMER_CTRL(t0)
    
    jal ra, wait_medium
    ret

trigger_uart0_irq:
    # Enable UART0 IRQ
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitUART0)
    sw t1, SYS_IRQ_EN(t0)
    
    # Configure UART0 for IRQ generation
    li t0, UART0_BASE_ADDR
    li t1, UART_TX_IRQ_EN
    sw t1, UART_IRQ_EN(t0)
    
    # Send data to trigger TX IRQ
    li t1, 0x55
    sw t1, UART_DATA(t0)
    
    jal ra, wait_medium
    ret

trigger_spi0_irq:
    # Enable SPI0 IRQ
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitSPI0)
    sw t1, SYS_IRQ_EN(t0)
    
    # Configure SPI0 for IRQ generation
    li t0, SPI0_BASE_ADDR
    li t1, 0x01  # TX complete IRQ enable
    sw t1, SPI_IRQ_EN(t0)
    
    # Send data to trigger IRQ
    li t1, 0xAA
    sw t1, SPI_DATA(t0)
    
    jal ra, wait_medium
    ret

trigger_spi1_irq:
    # Enable SPI1 IRQ
    li t0, SYSTEM_BASE_ADDR
    li t1, (1 << IrqBitSPI1)
    sw t1, SYS_IRQ_EN(t0)
    
    # Configure SPI1 for IRQ generation
    li t0, SPI1_BASE_ADDR
    li t1, 0x01  # TX complete IRQ enable
    sw t1, SPI_IRQ_EN(t0)
    
    # Send data to trigger IRQ
    li t1, 0x33
    sw t1, SPI_DATA(t0)
    
    jal ra, wait_medium
    ret

# No-wait versions for simultaneous triggering
trigger_gpio0_irq_no_wait:
    li t0, GPIO0_BASE_ADDR
    li t1, GPIO_IRQ_EN_BIT
    sw t1, GPIO_IRQ_EN(t0)
    sw zero, GPIO_DATA(t0)
    li t1, 0x01
    sw t1, GPIO_DATA(t0)
    ret

trigger_timer0_irq_no_wait:
    li t0, TIMER0_BASE_ADDR
    li t1, 50
    sw t1, TIMER_COMPARE(t0)
    li t1, TIMER_IRQ_EN_BIT
    sw t1, TIMER_IRQ_EN(t0)
    li t1, TIMER_EN
    sw t1, TIMER_CTRL(t0)
    ret

trigger_uart0_irq_no_wait:
    li t0, UART0_BASE_ADDR
    li t1, UART_TX_IRQ_EN
    sw t1, UART_IRQ_EN(t0)
    li t1, 0x77
    sw t1, UART_DATA(t0)
    ret

trigger_spi0_irq_no_wait:
    li t0, SPI0_BASE_ADDR
    li t1, 0x01
    sw t1, SPI_IRQ_EN(t0)
    li t1, 0xBB
    sw t1, SPI_DATA(t0)
    ret

verify_irq_handled:
    # Check if IRQ was handled by looking for the handled marker
    # This assumes the ISR sets this marker
    li t0, TEST_CONTEXT_BASE
    lw t1, 8(t0)  # IRQ_HANDLED_MARKER location
    li t2, IRQ_HANDLED_MARKER
    bne t1, t2, fail
    ret

verify_no_irq_occurred:
    # Check that no IRQ occurred
    li t0, TEST_CONTEXT_BASE
    lw t1, 8(t0)  # IRQ_HANDLED_MARKER location
    li t2, IRQ_HANDLED_MARKER
    beq t1, t2, fail  # Should NOT be equal
    ret

load_test_context:
    # Load known values into registers for context testing
    li t0, 0x12345678
    li t1, 0x9ABCDEF0
    li t2, 0x11111111
    li t3, 0x22222222
    li t4, 0x33333333
    li t5, 0x44444444
    li t6, 0x55555555
    ret

verify_context_preserved:
    # Verify registers still contain expected values
    li s2, 0x12345678
    bne t0, s2, fail
    li s2, 0x9ABCDEF0
    bne t1, s2, fail
    li s2, 0x11111111
    bne t2, s2, fail
    li s2, 0x22222222
    bne t3, s2, fail
    ret

wait_no_irq_period:
    # Wait long enough for any IRQ to occur
    jal ra, wait_long
    ret

setup_nested_irq_test:
    # Setup for nested IRQ testing
    # Implementation depends on your IRQ controller capabilities
    ret

trigger_nested_irq_sequence:
    # Trigger sequence that tests IRQ nesting
    ret

verify_nested_irq_handling:
    # Verify nested IRQ was handled correctly
    ret

verify_timer_irq_handled_first:
    # Check that timer IRQ was handled before GPIO IRQ
    # Implementation specific based on your IRQ handling markers
    ret

verify_gpio_irq_handled_first:
    # Check that GPIO IRQ was handled before timer IRQ
    ret

verify_spi_irq_handled_first:
    # Check that SPI IRQ was handled before UART IRQ
    ret

verify_both_irqs_handled:
    # Verify both IRQs were handled
    ret

verify_three_irqs_handled:
    # Verify all three IRQs were handled
    ret

verify_irq_burst_handled:
    # Verify burst of IRQs was handled
    ret

verify_spi_irqs_handled:
    # Verify both SPI IRQs were handled
    ret

setup_recursive_irq_test:
    # Setup for recursive IRQ testing
    ret

trigger_recursive_irq:
    # Trigger IRQ that causes another IRQ
    ret

verify_recursive_irq_handled:
    # Verify recursive IRQ was handled correctly
    ret

verify_irq_with_bad_stack:
    # Verify IRQ handling with corrupted stack
    ret

# ===============================================================================
# Timing Functions
# ===============================================================================
wait_short:
    li t0, 100
1:  addi t0, t0, -1
    bnez t0, 1b
    ret

wait_medium:
    li t0, 1000
1:  addi t0, t0, -1
    bnez t0, 1b
    ret

wait_long:
    li t0, 10000
1:  addi t0, t0, -1
    bnez t0, 1b
    ret

RVTEST_CODE_END

# ===============================================================================
# Custom ISR Implementations (replace the stub versions)
# ===============================================================================

.section .text

# Custom ISRs that set markers for verification
.org 0x13000
system_isr:
    # Save context
    addi sp, sp, -64
    sw ra, 60(sp)
    sw t0, 56(sp)
    sw t1, 52(sp)
    sw t2, 48(sp)
    
    # Set IRQ handled marker
    li t0, TEST_CONTEXT_BASE
    li t1, IRQ_HANDLED_MARKER
    sw t1, 8(t0)
    
    # Clear IRQ source (implementation specific)
    
    # Restore context
    lw t2, 48(sp)
    lw t1, 52(sp)
    lw t0, 56(sp)
    lw ra, 60(sp)
    addi sp, sp, 64
    
    # Return from interrupt
    mret

.org 0x13100
gpio0_isr:
    # Save context
    addi sp, sp, -64
    sw ra, 60(sp)
    sw t0, 56(sp)
    sw t1, 52(sp)
    
    # Set IRQ handled marker
    li t0, TEST_CONTEXT_BASE
    li t1, IRQ_HANDLED_MARKER
    sw t1, 8(t0)
    
    # Clear GPIO IRQ flag
    li t0, GPIO0_BASE_ADDR
    li t1, 0xFF
    sw t1, GPIO_IRQ_FLAG(t0)
    
    # Restore context
    lw t1, 52(sp)
    lw t0, 56(sp)
    lw ra, 60(sp)
    addi sp, sp, 64
    
    mret

.org 0x13500
timer0_isr:
    # Save context
    addi sp, sp, -64
    sw ra, 60(sp)
    sw t0, 56(sp)
    sw t1, 52(sp)
    
    # Set IRQ handled marker
    li t0, TEST_CONTEXT_BASE
    li t1, IRQ_HANDLED_MARKER
    sw t1, 8(t0)
    
    # Clear Timer IRQ flag
    li t0, TIMER0_BASE_ADDR
    li t1, 0xFF
    sw t1, TIMER_IRQ_FLAG(t0)
    
    # Stop timer
    sw zero, TIMER_CTRL(t0)
    
    # Restore context
    lw t1, 52(sp)
    lw t0, 56(sp)
    lw ra, 60(sp)
    addi sp, sp, 64
    
    mret

.org 0x13400
uart0_isr:
    # Save context
    addi sp, sp, -64
    sw ra, 60(sp)
    sw t0, 56(sp)
    sw t1, 52(sp)
    
    # Set IRQ handled marker
    li t0, TEST_CONTEXT_BASE
    li t1, IRQ_HANDLED_MARKER
    sw t1, 8(t0)
    
    # Clear UART IRQ flag
    li t0, UART0_BASE_ADDR
    li t1, 0xFF
    sw t1, UART_IRQ_FLAG(t0)
    
    # Restore context
    lw t1, 52(sp)
    lw t0, 56(sp)
    lw ra, 60(sp)
    addi sp, sp, 64
    
    mret

# Add other ISRs as needed...