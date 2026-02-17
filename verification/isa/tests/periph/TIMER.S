#*****************************************************************************
# TIMER_TEST.S
#-----------------------------------------------------------------------------
# TIMER testbench for RISC-V assembly
# Author: Maxx Seminario
# Date: 08-22-2025
#
# Test Categories:
# 1. Basic Timer Operation Tests (Tests 1-8)
# 2. Compare and PWM Tests (Tests 9-16)
# 3. Input Capture Tests (Tests 17-22)
# 4. Interrupt Flag Tests (Tests 23-30)
# 5. Clock Source and Divider Tests (Tests 31-35)
# 
# Each test category validates different aspects of timer functionality:
# - Timer enable/disable and counting
# - Compare match detection and PWM output generation
# - Input capture on rising/falling edges
# - Interrupt flag generation and clearing
# - Clock source selection and frequency division
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"


# Clock source definitions
#define CLK_SRC_SMCLK   0x0000   // Sub-main clock
#define CLK_SRC_MCLK    0x0100   // Main clock
#define CLK_SRC_LFXT    0x0200   // Low-frequency crystal
#define CLK_SRC_HFXT    0x0300   // High-frequency crystal

# Clock divider definitions
#define CLK_DIV_1       0x00000  // Divide by 1
#define CLK_DIV_2       0x10000  // Divide by 2
#define CLK_DIV_4       0x20000  // Divide by 4
#define CLK_DIV_8       0x30000  // Divide by 8
#define CLK_DIV_16      0x40000  // Divide by 16
#define CLK_DIV_32      0x50000  // Divide by 32

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# Register Usage Convention
# ===============================================================================
# x10 (a0) - TIMER base address (preserved)
# x11 (a1) - GPIO base address (preserved)
# x12 (a2) - GPIO timer base address (preserved)

# x3  (gp) - Test counter (preserved)
# 
# x8  (s0) - Test loop counter
# x9  (s1) - Saved return address (for individual tests)
# x18 (s2) - Main test suite return address
# x19 (s3) - Test data/configuration values
# x20 (s4) - Expected values
# x21 (s5) - Timer control register value
# x22 (s6) - Status register snapshot
# x23 (s7) - Additional test values
# x24-x27 (s8-s11) - Additional saved values as needed
#
# x5-x7, x28-x31 (t0-t4) - Temporary (only between function calls)

# s10 (x26) for storing ra of test block
# s11 (x27) - timer_num: which timer peripheral is currently under test (0 or 1)
# a0        - TIMER base address (updated as needed)
# ===============================================================================


system_init: 
    li  a0, PERIPH_SYSTEM0_BASE
    sw zero, SYS_CLK_CR(a0)  # Disable clock
    mv a0, zero

timer_test_start:
    li   s11, 0                # timer_num = 0
test_timer_peripheral_loop:
    beqz  s11, use_timer_peripheral_0
use_timer_peripheral_1:
    # Load base addresses of peripherals corresponding to timer 1
    li  a0, PERIPH_TIMER1_BASE
    j    set_timer_gpio

use_timer_peripheral_0:
    # Load base addresses of peripherals corresponding to timer 0
    li  a0, PERIPH_TIMER0_BASE

set_timer_gpio:
    # Timer 0 and 1 share same GPIO port and interrogator port
    li  a1, PERIPH_GPIO1_BASE
    li  a2, PERIPH_GPIO2_BASE
    li  gp, 0                   # Initialize test counter

    jal ra, init_gpio_timer
    jal ra, init_gpio_interrogator 

init_resets:
    # address of timer we are testing is stored in a0
    li t0, TIMER_CMP2_RESET_MASK 
    sw t0, TIMER_CR(a0)   # Reset timer
    jal ra, wait_short
    sw zero, TIMER_CR(a0) # Clear reset

test_suite:
    # Run all test suites
    jal ra, basic_timer_tests
    jal ra, compare_pwm_tests
    jal ra, input_capture_tests
    jal ra, interrupt_flag_tests
    jal ra, clock_divider_tests

    # Prepare for next timer peripheral
    addi s11, s11, 1
    li   t0, 2                 # Number of timer peripherals to test
    blt  s11, t0, test_timer_peripheral_loop

# ===============================================================================
# SUCCESS - ALL TESTS PASSED
# ===============================================================================
all_tests_passed:
    TEST_PASSFAIL

# ===============================================================================
# 1. BASIC TIMER OPERATION TESTS (Tests 1-8)
# ===============================================================================

basic_timer_tests:
    mv   s10, ra

    # Test 1: Timer enable/disable
    addi gp, gp, 1
    jal ra, test_timer_enable_disable

    # Test 2: Timer counting functionality
    addi gp, gp, 1
    jal ra, test_timer_counting

    # Test 3: Timer value read/write
    addi gp, gp, 1
    jal ra, test_timer_value_rw

    # Test 4: Timer overflow detection
    addi gp, gp, 1
    jal ra, test_timer_overflow

    # Test 5: Timer reset functionality
    addi gp, gp, 1
    jal ra, test_timer_reset

    # Test 6: Multiple start/stop cycles
    addi gp, gp, 1
    jal ra, test_timer_start_stop_cycles

    # Test 7: Timer value persistence when disabled
    addi gp, gp, 1
    jal ra, test_timer_value_persistence

    # Test 8: Configuration register access
    addi gp, gp, 1
    jal ra, test_config_register_access

    mv   ra, s10
    ret

# ===============================================================================
# 2. COMPARE AND PWM TESTS (Tests 9-16)
# ===============================================================================

compare_pwm_tests:
    mv   s10, ra

    # Test 9: Compare 0 match detection
    addi gp, gp, 1
    jal ra, test_compare0_match

    # Test 10: Compare 1 match detection
    addi gp, gp, 1
    jal ra, test_compare1_match

    # Test 11: Compare 2 match and timer reset
    addi gp, gp, 1
    jal ra, test_compare2_reset

    # Test 12: PWM output generation
    addi gp, gp, 1
    jal ra, test_pwm_generation

    # Test 13: Multiple compare matches
    addi gp, gp, 1
    jal ra, test_multiple_compares

    # Test 14: Compare output initial levels
    addi gp, gp, 1
    jal ra, test_compare_initial_levels

    # Test 15: PWM duty cycle variations
    addi gp, gp, 1
    jal ra, test_pwm_duty_cycles

    # Test 16: Compare register updates during operation
    addi gp, gp, 1
    jal ra, test_compare_register_updates

    mv   ra, s10
    ret

# ===============================================================================
# 3. INPUT CAPTURE TESTS (Tests 17-22)
# ===============================================================================

input_capture_tests:
    mv   s10, ra

    # Test 17: Capture 0 rising edge
    addi gp, gp, 1
    jal ra, test_capture0_rising_edge

    # Test 18: Capture 0 falling edge
    addi gp, gp, 1
    jal ra, test_capture0_falling_edge

    # Test 19: Capture 1 rising edge
    addi gp, gp, 1
    jal ra, test_capture1_rising_edge

    # Test 20: Capture 1 falling edge
    addi gp, gp, 1
    jal ra, test_capture1_falling_edge

    # Test 21: Multiple capture events
    addi gp, gp, 1
    jal ra, test_multiple_captures

    # Test 22: Capture timing accuracy
    addi gp, gp, 1
    jal ra, test_capture_timing

    mv   ra, s10
    ret

# ===============================================================================
# 4. INTERRUPT FLAG TESTS (Tests 23-30)
# ===============================================================================

interrupt_flag_tests:
    mv   s10, ra

    # Test 23: Compare 0 interrupt flag
    addi gp, gp, 1
    jal ra, test_compare0_interrupt

    # Test 24: Compare 1 interrupt flag
    addi gp, gp, 1
    jal ra, test_compare1_interrupt

    # Test 25: Compare 2 interrupt flag
    addi gp, gp, 1
    jal ra, test_compare2_interrupt

    # Test 26: Overflow interrupt flag
    addi gp, gp, 1
    jal ra, test_overflow_interrupt

    # Test 27: Capture interrupt flags
    addi gp, gp, 1
    jal ra, test_capture_interrupts

    # Test 28: Interrupt enable/disable
    addi gp, gp, 1
    jal ra, test_interrupt_enable_disable

    # Test 29: Multiple interrupt flags
    addi gp, gp, 1
    jal ra, test_multiple_interrupt_flags

    # Test 30: Interrupt flag clearing
    addi gp, gp, 1
    jal ra, test_interrupt_flag_clearing

    mv   ra, s10
    ret

# ===============================================================================
# 5. CLOCK SOURCE AND DIVIDER TESTS (Tests 31-35)
# ===============================================================================

clock_divider_tests:
    mv   s10, ra

    # Test 31: Clock source selection
    addi gp, gp, 1
    jal ra, test_clock_source_selection

    # Test 32: Clock divider functionality
    addi gp, gp, 1
    jal ra, test_clock_divider_functionality

    # Test 33: Different divider ratios
    addi gp, gp, 1
    jal ra, test_divider_ratios

    # Test 34: Clock source switching during operation
    addi gp, gp, 1
    # jal ra, test_clock_source_switching

    # Test 35: Timer frequency verification
    addi gp, gp, 1
    # jal ra, test_timer_frequency

    mv   ra, s10
    ret

# ===============================================================================
# INDIVIDUAL TEST IMPLEMENTATIONS
# ===============================================================================

# Test 1: Timer enable/disable
test_timer_enable_disable:
    mv s1, ra

    # Reset timer
    jal ra, reset_timer

    # Verify timer starts disabled and at zero
    lw t0, TIMER_VAL(a0)
    bnez t0, fail

    # Enable timer
    li s5, TIMER_EN_MASK
    sw s5, TIMER_CR(a0)

    # Wait a bit and verify timer is counting
    jal ra, wait_short
    lw t1, TIMER_VAL(a0)
    beqz t1, fail  # Should be non-zero now

    # Disable timer
    sw zero, TIMER_CR(a0)
    lw t2, TIMER_VAL(a0)

    # Wait and verify timer stopped
    jal ra, wait_short
    lw t3, TIMER_VAL(a0)
    bne t2, t3, fail  # Should be same value

    mv ra, s1
    ret

# Test 2: Timer counting functionality
test_timer_counting:
    mv s1, ra

    # # Reset and enable timer with fastest clock
    # jal ra, reset_timer
    # li s5, TIMER_EN_MASK | CLK_SRC_MCLK
    # sw s5, TIMER_CR(a0)

    # Reset and enable timer with fastest clock
    jal ra, reset_timer
    li s5, CLK_SRC_MCLK
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    li s5, TIMER_EN_MASK | CLK_SRC_MCLK
    sw s5, TIMER_CR(a0)


    # Take initial reading
    lw s3, TIMER_VAL(a0)

    # Wait and verify counting
    jal ra, wait_medium
    lw s4, TIMER_VAL(a0)

    # Verify timer incremented
    bge s3, s4, fail  # s4 should be greater than s3

    # Verify continued counting
    mv s3, s4
    jal ra, wait_medium
    lw s4, TIMER_VAL(a0)
    bge s3, s4, fail

    mv ra, s1
    ret

# Test 3: Timer value read/write
test_timer_value_rw:
    mv s1, ra

    # Reset timer
    jal ra, reset_timer
    
    # Test writing to timer value
    li s3, 0x12345678
    sw s3, TIMER_VAL(a0)
    lw t0, TIMER_VAL(a0)
    bne s3, t0, fail

    # Test with different value
    li s3, 0xABCDEF00
    sw s3, TIMER_VAL(a0)
    lw t0, TIMER_VAL(a0)
    bne s3, t0, fail

    # Enable timer and verify it continues from written value
    li s5, TIMER_EN_MASK
    sw s5, TIMER_CR(a0)
    
    # Need to wait for clk_mux_glitch free to sync on smclk
    jal ra, wait_medium
    lw t1, TIMER_VAL(a0)
    bge s3, t1, fail  # Should be greater than written value

    mv ra, s1
    ret

# Test 4: Timer overflow detection
test_timer_overflow:
    mv s1, ra

    # Reset timer and enable overflow interrupt
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_OVF_IE_MASK
    sw s5, TIMER_CR(a0)

    # Set timer near overflow
    li s3, 0xFFFFFFFE
    sw s3, TIMER_VAL(a0)

    # Wait for overflow
    jal ra, wait_medium
    
    # Check overflow flag
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_OVF_IF_MASK
    beqz t0, fail

    # Verify timer wrapped to low value
    lw t1, TIMER_VAL(a0)
    li t2, 0xFFFF000  # Should be small value
    bge t1, t2, fail

    mv ra, s1
    ret

# Test 5: Timer reset functionality
test_timer_reset:
    mv s1, ra

    # Enable timer and let it count
    li s5, TIMER_EN_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_medium

    # Verify timer is non-zero
    lw t0, TIMER_VAL(a0)
    beqz t0, fail

    # Reset timer
    jal ra, reset_timer

    # Verify timer is zero
    lw t0, TIMER_VAL(a0)
    bnez t0, fail

    mv ra, s1
    ret

# Test 6: Multiple start/stop cycles
test_timer_start_stop_cycles:
    mv s1, ra

    # Reset timer
    jal ra, reset_timer

    li s0, 3  # Test 3 cycles

start_stop_loop:
    # Start timer
    li s5, TIMER_EN_MASK
    sw s5, TIMER_CR(a0)
    
    lw s3, TIMER_VAL(a0)  # Initial value
    jal ra, wait_short
    lw s4, TIMER_VAL(a0)  # After counting
    
    # Verify it counted
    bge s3, s4, fail

    # Stop timer
    sw zero, TIMER_CR(a0)
    
    lw s3, TIMER_VAL(a0)  # Value when stopped
    jal ra, wait_short
    lw s4, TIMER_VAL(a0)  # Should be same
    
    # Verify it stopped
    bne s3, s4, fail

    addi s0, s0, -1
    bnez s0, start_stop_loop

    mv ra, s1
    ret

# Test 7: Timer value persistence when disabled
test_timer_value_persistence:
    mv s1, ra

    # Enable timer and let it count
    li s5, TIMER_EN_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_medium
    
    # Stop timer and save value
    sw zero, TIMER_CR(a0)
    lw s3, TIMER_VAL(a0)

    # Wait while disabled
    jal ra, wait_medium
    
    # Verify value unchanged
    lw t0, TIMER_VAL(a0)
    bne s3, t0, fail

    # Re-enable and verify counting continues from saved value
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    lw t1, TIMER_VAL(a0)
    bge s3, t1, fail

    mv ra, s1
    ret

# Test 8: Configuration register access
test_config_register_access:
    mv s1, ra

    # Test writing various configurations
    li s3, TIMER_EN_MASK | TIMER_CMP0_IE_MASK | CLK_SRC_MCLK
    sw s3, TIMER_CR(a0)
    lw t0, TIMER_CR(a0)
    bne s3, t0, fail

    # Test different configuration
    li s3, TIMER_CAP0_EN_MASK | TIMER_CAP1_EN_MASK | CLK_DIV_8
    sw s3, TIMER_CR(a0)
    lw t0, TIMER_CR(a0)
    bne s3, t0, fail

    # Test clearing
    sw zero, TIMER_CR(a0)
    lw t0, TIMER_CR(a0)
    bnez t0, fail

    mv ra, s1
    ret

# Test 9: Compare 0 match detection
test_compare0_match:
    mv s1, ra

    # Reset timer and set compare value
    jal ra, reset_timer
    li s3, 100
    sw s3, TIMER_CMP0(a0)

    # Enable timer with compare interrupt
    li s5, TIMER_EN_MASK | TIMER_CMP0_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for compare match
    jal ra, wait_for_compare0_match

    # Verify compare flag is set
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_IF_MASK
    beqz t0, fail

    # Verify timer value matches compare
    lw t1, TIMER_VAL(a0)
    bge s3, t1, fail  # Timer should have passed compare value

    mv ra, s1
    ret

# Test 10: Compare 1 match detection
test_compare1_match:
    mv s1, ra

    # Reset timer and set compare value
    jal ra, reset_timer
    li s3, 200
    sw s3, TIMER_CMP1(a0)

    # Enable timer with compare interrupt
    li s5, TIMER_EN_MASK | TIMER_CMP1_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for compare match
    jal ra, wait_for_compare1_match

    # Verify compare flag is set
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP1_IF_MASK
    beqz t0, fail

    mv ra, s1
    ret

# Test 11: Compare 2 match and timer reset
test_compare2_reset:
    mv s1, ra

    # Reset timer and set compare value for reset
    jal ra, reset_timer
    li s3, 150
    sw s3, TIMER_CMP2(a0)

    # Enable timer with compare 2 reset and interrupt
    li s5, TIMER_EN_MASK | TIMER_CMP2_RESET_MASK | TIMER_CMP2_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for compare match
    jal ra, wait_for_compare2_match

    # Verify compare flag is set
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP2_IF_MASK
    beqz t0, fail

    # Verify timer was reset (should be small value)
    lw t1, TIMER_VAL(a0)
    li t2, 50
    bge t1, t2, fail  # Should be less than 50 if reset occurred

    mv ra, s1
    ret

# Test 12: PWM output generation
test_pwm_generation:
    mv s1, ra

    # Reset timer and configure for PWM
    jal ra, reset_timer
    
    # Set compare values for PWM
    li s3, 100
    li s4, 300
    sw s3, TIMER_CMP0(a0)  # PWM period (reset point)
    sw s4, TIMER_CMP2(a0)  # Reset timer at this value
    
    # Enable timer with compare 0 initial high, reset on compare 2
    li s5, TIMER_EN_MASK | TIMER_CMP0_INIT_MASK | TIMER_CMP2_RESET_MASK | TIMER_CMP0_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for first compare match (output should toggle)
    jal ra, wait_for_compare0_match
    
    # Check output is toggled (should be low if init was high)
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_OUT_MASK
    bnez t0, fail  # Should be low after toggle

    # Wait for timer reset
    jal ra, wait_for_compare2_match
    
    # Check output returned to initial state (high)
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_OUT_MASK
    beqz t0, fail  # Should be high after reset

    mv ra, s1
    ret

# Test 13: Multiple compare matches
test_multiple_compares:
    mv s1, ra

    # Reset timer
    jal ra, reset_timer
    
    # Set multiple compare values
    li t0, 50
    li t1, 100
    li t2, 150
    sw t0, TIMER_CMP0(a0)
    sw t1, TIMER_CMP1(a0)
    sw t2, TIMER_CMP2(a0)

    # Enable timer with all compare interrupts
    li s5, TIMER_CMP2_RESET_MASK | TIMER_EN_MASK | TIMER_CMP0_IE_MASK | TIMER_CMP1_IE_MASK | TIMER_CMP2_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for all compares to trigger
    jal ra, wait_for_compare0_match
    jal ra, wait_for_compare1_match
    jal ra, wait_for_compare2_match

    # Verify all flags are set
    lw t0, TIMER_SR(a0)
    andi t1, t0, TIMER_CMP0_IF_MASK
    beqz t1, fail
    andi t1, t0, TIMER_CMP1_IF_MASK
    beqz t1, fail
    andi t1, t0, TIMER_CMP2_IF_MASK
    beqz t1, fail

    mv ra, s1
    ret

# Test 14: Compare output initial levels
test_compare_initial_levels:
    mv s1, ra

    # Test initial level high for compare 0
    jal ra, reset_timer

    li s5, 0x4000  
    sw s5, TIMER_VAL(a0)  # Set timer to large nubmer to ensure no comparison event 


    li s5, TIMER_CMP0_INIT_MASK # Setup initial value of cmp0 before timer is enabled
    sw s5, TIMER_CR(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP0_INIT_MASK # then enable timer
    sw s5, TIMER_CR(a0) 
    
    # Check initial output level
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_OUT_MASK
    beqz t0, fail  # Should be high

    # Test initial level low for compare 1
    li s5, TIMER_EN_MASK  # CMP1_INIT = 0
    sw s5, TIMER_CR(a0)
    
    # Check initial output level
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP1_OUT_MASK
    bnez t0, fail  # Should be low

    mv ra, s1
    ret

# Test 15: PWM duty cycle variations
test_pwm_duty_cycles:
    mv s1, ra

    # Test different duty cycles
    li s0, 3  # Test 3 different duty cycles

duty_cycle_loop:
    jal ra, reset_timer
    
    # Set period
    li t0, 200  # Period
    sw t0, TIMER_CMP2(a0)
    
    # Calculate duty cycle using shifts and adds instead of division
    # s0 = 3: 25% duty = 200/4 = 50
    # s0 = 2: 50% duty = 200/2 = 100  
    # s0 = 1: 75% duty = 200*3/4 = 150
    
    li t1, 3
    sub t2, t1, s0        # s0 = 3,2,1 -> t2 = 0,1,2
    addi t2, t2, 1        # t2 = 1,2,3
    
    li t3, 200            # Start with period
    
    # Load comparison values into registers
    li t4, 1
    li t5, 2
    li t6, 3
    
    beq t2, t4, duty_25   # If t2 = 1, calculate 25%
    beq t2, t5, duty_50   # If t2 = 2, calculate 50%
    beq t2, t6, duty_75   # If t2 = 3, calculate 75%
    j duty_done

duty_25:
    # 25% = 200/4 = 200 >> 2
    srli t3, t3, 2        # t3 = 200 >> 2 = 50
    j duty_done

duty_50:
    # 50% = 200/2 = 200 >> 1  
    srli t3, t3, 1        # t3 = 200 >> 1 = 100
    j duty_done

duty_75:
    # 75% = 200*3/4 = (200 >> 2) * 3 = 50 * 3
    srli t4, t3, 2        # t4 = 200 >> 2 = 50
    add t3, t4, t4        # t3 = 50 + 50 = 100
    add t3, t3, t4        # t3 = 100 + 50 = 150

duty_done:
    sw t3, TIMER_CMP0(a0)

    # Enable with PWM configuration
    li s5, TIMER_CMP0_INIT_MASK | TIMER_CMP2_RESET_MASK | TIMER_CMP0_IE_MASK | TIMER_CMP2_IE_MASK
    sw s5, TIMER_CR(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP0_INIT_MASK | TIMER_CMP2_RESET_MASK | TIMER_CMP0_IE_MASK | TIMER_CMP2_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for compare match and verify toggle
    jal ra, wait_for_compare0_match
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_OUT_MASK
    bnez t0, fail  # Should toggle to low

    # Wait for reset and verify return to high
    jal ra, wait_for_compare2_match
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_OUT_MASK
    beqz t0, fail  # Should return to high

    addi s0, s0, -1
    bnez s0, duty_cycle_loop

    mv ra, s1
    ret

# Test 16: Compare register updates during operation
test_compare_register_updates:
    mv s1, ra

    # Start timer with initial compare value
    jal ra, reset_timer
    li s3, 100
    sw s3, TIMER_CMP0(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP0_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for timer to reach halfway point
    jal ra, wait_short
    
    # Update compare value while running
    li s4, 200
    sw s4, TIMER_CMP0(a0)

    # Wait for new compare match
    jal ra, wait_for_compare0_match
    
    # Verify timer reached the new compare value
    lw t0, TIMER_VAL(a0)
    blt t0, s4, fail  # Should be >= new compare value

    mv ra, s1
    ret

# Test 17: Capture 0 rising edge
test_capture0_rising_edge:
    mv s1, ra

    # Configure timer and capture
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_CAP0_EN_MASK | TIMER_CAP0_IE_MASK
    sw s5, TIMER_CR(a0)  # Rising edge capture (CAP0_EDGE = 0)

    # Wait for timer to have some value
    jal ra, wait_medium
    
    # Simulate rising edge on capture input via GPIO
    jal ra, generate_rising_edge_cap0

    # Check capture flag
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CAP0_IF_MASK
    beqz t0, fail

    # Read captured value
    lw s3, TIMER_CAP0(a0)
    # Verify it's reasonable (non-zero and less than current timer)
    beqz s3, fail
    lw t1, TIMER_VAL(a0)
    bge s3, t1, fail

    mv ra, s1
    ret

# Test 18: Capture 0 falling edge
test_capture0_falling_edge:
    mv s1, ra

    # Configure timer for falling edge capture
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_CAP0_EN_MASK | TIMER_CAP0_EDGE_MASK | TIMER_CAP0_IE_MASK
    sw s5, TIMER_CR(a0)  # Falling edge capture (CAP0_EDGE = 1)

    # Wait for timer to have some value
    jal ra, wait_medium
    
    # Simulate falling edge on capture input
    jal ra, generate_falling_edge_cap0

    # Check capture flag
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CAP0_IF_MASK
    beqz t0, fail

    # Read captured value
    lw s3, TIMER_CAP0(a0)
    beqz s3, fail

    mv ra, s1
    ret

# Test 19: Capture 1 rising edge
test_capture1_rising_edge:
    mv s1, ra

    # Configure timer and capture 1
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_CAP1_EN_MASK | TIMER_CAP1_IE_MASK
    sw s5, TIMER_CR(a0)  # Rising edge capture

    # Wait for timer to count
    jal ra, wait_medium
    
    # Simulate rising edge on capture 1 input
    jal ra, generate_rising_edge_cap1

    # Check capture flag
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CAP1_IF_MASK
    beqz t0, fail

    # Read captured value
    lw s3, TIMER_CAP1(a0)
    beqz s3, fail

    mv ra, s1
    ret

# Test 20: Capture 1 falling edge
test_capture1_falling_edge:
    mv s1, ra

    # Configure timer for falling edge capture
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_CAP1_EN_MASK | TIMER_CAP1_EDGE_MASK | TIMER_CAP1_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait and generate falling edge
    jal ra, wait_medium
    jal ra, generate_falling_edge_cap1

    # Verify capture occurred
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CAP1_IF_MASK
    beqz t0, fail

    mv ra, s1
    ret

# Test 21: Multiple capture events
test_multiple_captures:
    mv s1, ra

    # Enable both captures
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_CAP0_EN_MASK | TIMER_CAP1_EN_MASK | TIMER_CAP0_IE_MASK | TIMER_CAP1_IE_MASK
    sw s5, TIMER_CR(a0)

    # Generate capture events at different times
    jal ra, wait_short
    jal ra, generate_rising_edge_cap0
    lw s3, TIMER_CAP0(a0)  # Save first capture

    jal ra, wait_short  
    jal ra, generate_rising_edge_cap1
    lw s4, TIMER_CAP1(a0)  # Save second capture

    # Verify both captures occurred and are different
    beqz s3, fail
    beqz s4, fail
    bge s3, s4, fail  # s4 should be greater (later in time)

    # Verify both flags are set
    lw t0, TIMER_SR(a0)
    andi t1, t0, TIMER_CAP0_IF_MASK
    beqz t1, fail
    andi t1, t0, TIMER_CAP1_IF_MASK
    beqz t1, fail

    mv ra, s1
    ret

# Test 22: Capture timing accuracy
test_capture_timing:
    mv s1, ra

    # Set up timer with known period using compare 2 reset
    jal ra, reset_timer
    li s3, 1000  # Reset period
    sw s3, TIMER_CMP2(a0)
    
    li s5, TIMER_EN_MASK | TIMER_CMP2_RESET_MASK | TIMER_CAP0_EN_MASK | TIMER_CAP0_IE_MASK
    sw s5, TIMER_CR(a0)

    # Wait for specific timer value then capture
    li s4, 500  # Target capture time
timing_wait:
    lw t0, TIMER_VAL(a0)
    blt t0, s4, timing_wait

    # Generate capture event
    jal ra, generate_rising_edge_cap0

    # Verify captured value is close to expected
    lw t1, TIMER_CAP0(a0)
    sub t2, t1, s4  # Calculate difference
    
    # Check if difference is within acceptable range (±50)
    li t3, 50
    blt t2, zero, check_neg_diff
    bgt t2, t3, fail
    j timing_ok
check_neg_diff:
    sub t2, zero, t2  # Make positive
    bgt t2, t3, fail
timing_ok:

    mv ra, s1
    ret


# Test 23-30: Interrupt flag tests (similar to compare tests above)
test_compare0_interrupt:
    mv s1, ra

    jal ra, reset_timer
    li s3, 75
    sw s3, TIMER_CMP0(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP0_IE_MASK
    sw s5, TIMER_CR(a0)
    
    jal ra, wait_for_compare0_match
    
    # Test flag is set
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_IF_MASK
    beqz t0, fail

    # Test clearing flag by writing 1
    li t1, TIMER_CMP0_IF_MASK
    sw t1, TIMER_SR(a0)
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_IF_MASK
    bnez t0, fail

    mv ra, s1
    ret

# Similar implementations for other interrupt tests...
test_compare1_interrupt:
    mv s1, ra
    # Similar to test_compare0_interrupt but for compare 1
    jal ra, reset_timer
    li s3, 125
    sw s3, TIMER_CMP1(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP1_IE_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_for_compare1_match
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP1_IF_MASK
    beqz t0, fail
    mv ra, s1
    ret

test_compare2_interrupt:
    mv s1, ra
    jal ra, reset_timer
    li s3, 175
    sw s3, TIMER_CMP2(a0)
    li s5, TIMER_CMP2_RESET_MASK | TIMER_EN_MASK | TIMER_CMP2_IE_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_for_compare2_match
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP2_IF_MASK
    beqz t0, fail
    mv ra, s1
    ret

test_overflow_interrupt:
    mv s1, ra
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_OVF_IE_MASK
    sw s5, TIMER_CR(a0)
    li s3, 0xFFFFFFF0  # Near overflow
    sw s3, TIMER_VAL(a0)
    jal ra, wait_medium
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_OVF_IF_MASK
    beqz t0, fail
    mv ra, s1
    ret

test_capture_interrupts:
    mv s1, ra
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | TIMER_CAP0_EN_MASK | TIMER_CAP0_IE_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    jal ra, generate_rising_edge_cap0
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CAP0_IF_MASK
    beqz t0, fail
    mv ra, s1
    ret

test_interrupt_enable_disable:
    mv s1, ra
    # Test that flags are set regardless of interrupt enable
    jal ra, reset_timer
    li s3, 100
    sw s3, TIMER_CMP0(a0)
    li s5, TIMER_EN_MASK  # No interrupt enable
    sw s5, TIMER_CR(a0)
    jal ra, wait_for_compare0_match
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_IF_MASK
    beqz t0, fail  # Flag should still be set
    mv ra, s1
    ret

test_multiple_interrupt_flags:
    mv s1, ra
    jal ra, reset_timer
    li t0, 50
    li t1, 100
    sw t0, TIMER_CMP0(a0)
    sw t1, TIMER_CMP1(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP0_IE_MASK | TIMER_CMP1_IE_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_for_compare1_match  # Wait for both
    lw t0, TIMER_SR(a0)
    andi t1, t0, TIMER_CMP0_IF_MASK
    beqz t1, fail
    andi t1, t0, TIMER_CMP1_IF_MASK  
    beqz t1, fail
    mv ra, s1
    ret

test_interrupt_flag_clearing:
    mv s1, ra
    # Test individual and multiple flag clearing
    jal ra, reset_timer
    li t0, 60
    li t1, 120
    sw t0, TIMER_CMP0(a0)
    sw t1, TIMER_CMP1(a0)
    li s5, TIMER_EN_MASK | TIMER_CMP0_IE_MASK | TIMER_CMP1_IE_MASK
    sw s5, TIMER_CR(a0)
    jal ra, wait_for_compare1_match
    
    # Clear only CMP0 flag
    li t2, TIMER_CMP0_IF_MASK
    sw t2, TIMER_SR(a0)
    lw t0, TIMER_SR(a0)
    andi t1, t0, TIMER_CMP0_IF_MASK
    bnez t1, fail  # Should be cleared
    andi t1, t0, TIMER_CMP1_IF_MASK
    beqz t1, fail  # Should still be set
    
    mv ra, s1
    ret

# Test 31: Clock source selection
test_clock_source_selection:
    mv s1, ra

    li s0, 4  # Test 4 clock sources

clock_source_loop:
    jal ra, reset_timer
    
    # # Set clock source based on loop counter
    # li t0, 4
    # sub t1, t0, s0  # t1 = 0,1,2,3 for s0 = 4,3,2,1
    # slli t2, t1, 8  # Shift to bits 9:8
    # ori s5, t2, TIMER_EN_MASK
    # sw s5, TIMER_CR(a0)

    # Set clock source based on loop counter
    li t0, 4
    sub t1, t0, s0  # t1 = 0,1,2,3 for s0 = 4,3,2,1
    slli t2, t1, 8  # Shift to bits 9:8
    # ori s5, t2, TIMER_EN_MASK
    sw t2, TIMER_CR(a0)
    jal ra, wait_short  # Wait for clk_mux_glitch free to sync on new clock
    ori s5, t2, TIMER_EN_MASK
    sw s5, TIMER_CR(a0)

    # Let timer run and verify it's counting
    jal ra, wait_short
    lw t3, TIMER_VAL(a0)
    beqz t3, fail  # Should be counting regardless of source

    addi s0, s0, -1
    bnez s0, clock_source_loop

    mv ra, s1
    ret

# Test 32: Clock divider functionality  
test_clock_divider_functionality:
    mv s1, ra

    # Test with no divider (fastest)
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | CLK_SRC_MCLK  # No divider
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    lw s3, TIMER_VAL(a0)  # Fast count

    # Test with divider (slower)
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | CLK_SRC_MCLK | CLK_DIV_16
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    lw s4, TIMER_VAL(a0)  # Slow count

    # Verify divided clock is slower (smaller count for same time)
    bge s4, s3, fail

    mv ra, s1
    ret

# Test 33: Different divider ratios
test_divider_ratios:
    mv s1, ra

    li s0, 6  # Test 6 different divider ratios
    
divider_loop:
    jal ra, reset_timer
    
    # Set divider based on loop counter
    li t0, 6
    sub t1, t0, s0     # t1 = 0,1,2,3,4,5
    slli t2, t1, 16    # Shift to bits 19:16
    ori s5, t2, TIMER_EN_MASK | CLK_SRC_MCLK
    sw s5, TIMER_CR(a0)

    # Let timer run
    jal ra, wait_short
    lw t3, TIMER_VAL(a0)
    
    # All should be counting (non-zero)
    beqz t3, fail

    addi s0, s0, -1
    bnez s0, divider_loop

    mv ra, s1
    ret

# Test 34: Clock source switching during operation
test_clock_source_switching:
    mv s1, ra

    # Start with one clock source
    jal ra, reset_timer
    li s5, TIMER_EN_MASK | CLK_SRC_MCLK
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    lw s3, TIMER_VAL(a0)

    # Switch to different clock source
    li s5, TIMER_EN_MASK | CLK_SRC_SMCLK
    sw s5, TIMER_CR(a0)
    jal ra, wait_short
    lw s4, TIMER_VAL(a0)

    # Should continue counting from previous value
    bge s3, s4, fail

    mv ra, s1
    ret

# Test 35: Timer frequency verification
test_timer_frequency:
    mv s1, ra

    # Use compare match to measure frequency
    jal ra, reset_timer
    li s3, 1000  # Large compare value
    sw s3, TIMER_CMP0(a0)
    li s5, TIMER_EN_MASK | CLK_SRC_MCLK | TIMER_CMP0_IE_MASK
    sw s5, TIMER_CR(a0)

    # Measure time to reach compare (crude frequency test)
    li s4, 0  # Loop counter
freq_wait:
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_IF_MASK
    bnez t0, freq_done
    addi s4, s4, 1
    li t1, 100000  # Timeout
    blt s4, t1, freq_wait
    j fail  # Timeout - frequency too slow
freq_done:

    # Verify reasonable frequency (timer reached target in reasonable time)
    li t2, 50000
    bgt s4, t2, fail  # Too many loops = too slow

    mv ra, s1
    ret

# ===============================================================================
# UTILITY FUNCTIONS
# ===============================================================================

# Initialize GPIO for timer pins
init_gpio_timer:
    # Configure GPIO pins for timer I/O
    # Set pins as outputs for driving capture inputs
    li t0, 0xFF  # Configure pins for timer0 and timer1
    sw t0, GPIO_PxSEL(a2)
    sw zero, GPIO_PxDIR(a2)  # Set as inputs?
    sw zero, GPIO_PxOUT(a2)  # Start low
    ret

# Initialize GPIO for that will provide inputs (edgegs) to timer
init_gpio_interrogator:
    # Configure GPIO pins for interrogator I/O
    li t0, 0xFF
    sw zero, GPIO_PxSEL(a1)
    sw t0, GPIO_PxDIR(a1)  # Set as outputs
    sw zero, GPIO_PxOUT(a1)  # Start low
    ret

# Reset timer to known state
reset_timer:
    sw zero, TIMER_CR(a0)      # Disable timer
    sw zero, TIMER_VAL(a0)     # Clear timer value
    sw zero, TIMER_CMP0(a0)    # Clear compare registers
    sw zero, TIMER_CMP1(a0)
    sw zero, TIMER_CMP2(a0)
    
    # Clear all interrupt flags
    li t0, 0xFF
    sw t0, TIMER_SR(a0)
    ret

# Wait functions
wait_short:
    li t0, 1000
wait_short_loop:
    addi t0, t0, -1
    bnez t0, wait_short_loop
    ret

wait_medium:
    li t0, 10000
wait_medium_loop:
    addi t0, t0, -1
    bnez t0, wait_medium_loop
    ret

wait_long:
    li t0, 100000
wait_long_loop:
    addi t0, t0, -1
    bnez t0, wait_long_loop
    ret

# Wait for specific timer events
wait_for_compare0_match:
wait_cmp0_loop:
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP0_IF_MASK
    beqz t0, wait_cmp0_loop
    ret

wait_for_compare1_match:
wait_cmp1_loop:
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP1_IF_MASK
    beqz t0, wait_cmp1_loop
    ret

wait_for_compare2_match:
wait_cmp2_loop:
    lw t0, TIMER_SR(a0)
    andi t0, t0, TIMER_CMP2_IF_MASK
    beqz t0, wait_cmp2_loop
    ret

# Generate edge signals for capture testing
generate_rising_edge_cap0:
    # Generate rising edge on GPIO pin connected to cap0_in
    mv s2, s1
    mv s1, ra
    sw zero, GPIO_PxOUT(a1)  # Start low
    jal ra, wait_short
    li t0, GPIO2_T0_CAP0_MASK | GPIO2_T1_CAP0_MASK
    sw t0, GPIO_PxOUT(a1)    # Go high (rising edge)
    jal ra, wait_short
    mv ra, s1
    mv s1, s2
    ret

generate_falling_edge_cap0:
    # Generate falling edge on GPIO pin connected to cap0_in
    mv s2, s1
    mv s1, ra
    li t0, GPIO2_T0_CAP0_MASK | GPIO2_T1_CAP0_MASK
    sw t0, GPIO_PxOUT(a1)    # Start high
    jal ra, wait_short
    sw zero, GPIO_PxOUT(a1)  # Go low (falling edge)
    jal ra, wait_short
    mv ra, s1
    mv s1, s2
    ret

generate_rising_edge_cap1:
    # Generate rising edge on GPIO pin connected to cap1_in
    mv s2, s1
    mv s1, ra
    li t0, GPIO2_T0_CAP1_MASK | GPIO2_T1_CAP1_MASK
    sw t0, GPIO_PxOUTC(a1)    # Clear bit 1
    jal ra, wait_short
    li t0, GPIO2_T0_CAP1_MASK | GPIO2_T1_CAP1_MASK
    sw t0, GPIO_PxOUT(a1)    # Set bit 1 (rising edge)
    jal ra, wait_short
    mv ra, s1
    mv s1, s2
    ret

generate_falling_edge_cap1:
    # Generate falling edge on GPIO pin connected to cap1_in
    mv s2, s1
    mv s1, ra
    li t0, GPIO2_T0_CAP1_MASK | GPIO2_T1_CAP1_MASK
    sw t0, GPIO_PxOUT(a1)    # Start high
    jal ra, wait_short
    li t0, GPIO2_T0_CAP1_MASK | GPIO2_T1_CAP1_MASK
    sw t0, GPIO_PxOUTC(a1)    # Go low (falling edge)
    jal ra, wait_short
    mv ra, s1
    mv s1, s2
    ret


# Interrupt Service Routines (ISRs)
.section .isr_spi1 , "ax"
isr_timer0:



RVTEST_CODE_END

