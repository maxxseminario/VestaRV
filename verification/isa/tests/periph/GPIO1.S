#*****************************************************************************
# GPIO_TESTBENCH.S
#-----------------------------------------------------------------------------
# GPIO testbench for RISC-V assembly with GPIO0 to GPIO1 communication
# Author: [Your name]
# Date: [Current date]
#
# Test Categories:
# 1. Basic GPIO Register Tests (Tests 1-15)
# 2. GPIO Set/Clear/Toggle Tests (Tests 16-60)  
# 3. GPIO Direction Control Tests (Tests 61-70)
# 4. GPIO Communication Tests (Tests 71-80)
# 5. GPIO Interrupt Tests (Tests 81-130)
#
# GPIO3 and GPIO2 are connected externally for loopback testing
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"



#define GPIO_JUNK_REG       0x2C  // Junk Reg for Testing

# Constants
#define ALL_PINS_MASK       0x000000FF
#define ALL_OUTPUT          0x000000FF
#define ALL_INPUT           0x00000000

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# Register Usage Convention
# ===============================================================================
# x10 (a0) - GPIO0 base address (preserved)
# x11 (a1) - GPIO1 base address (preserved)  
# x3  (gp) - Test counter (preserved)
# 
# x8  (s0) - Loop counter 1
# x9  (s1) - Loop counter 2
# x18 (s2) - Test suite return address
# x19 (s3) - Test data/pattern
# x20 (s4) - Expected result
# x21 (s5) - Temporary test value
# x22 (s6) - Pin mask for current test
# x23 (s7) - Configuration value
# 
# x5-x7, x28-x31 (t0-t4) - Temporary registers
# ===============================================================================

gpio_testbench_start:
    # Initialize base addresses and test counter
    li  a0, PERIPH_GPIO1_BASE
    li  a1, PERIPH_GPIO2_BASE  
    li  gp, 0

    # Initialize both GPIO peripherals
    jal ra, init_gpio_peripherals

    # Run all test suites
    # jal ra, basic_register_tests
    li gp, 15
    jal ra, set_clear_toggle_tests
    jal ra, direction_control_tests
    jal ra, communication_tests
    jal ra, interrupt_tests  # NEW: Comprehensive interrupt tests

    # All tests passed
    TEST_PASSFAIL

# ===============================================================================
# GPIO INITIALIZATION
# ===============================================================================
init_gpio_peripherals:
    # Initialize GPIO0 - Set as output, clear all pins
    li t0, ALL_OUTPUT
    sw t0, GPIO_PxDIR(a0)
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    sw t0, GPIO_PxREN(a0)
    sw t0, GPIO_PxSEL(a0)
    sw t0, GPIO_PxIE(a0)    # Disable all interrupts
    sw t0, GPIO_PxIES(a0)   # Clear edge select
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a0)    # Clear all interrupt flags

    # Initialize GPIO1 - Set as input initially  
    li t0, ALL_INPUT
    sw t0, GPIO_PxDIR(a1)
    li t0, 0x00
    sw t0, GPIO_PxOUT(a1)
    sw t0, GPIO_PxREN(a1)
    sw t0, GPIO_PxSEL(a1)
    sw t0, GPIO_PxIE(a1)    # Disable all interrupts
    sw t0, GPIO_PxIES(a1)   # Clear edge select
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)    # Clear all interrupt flags

    ret

# ===============================================================================
# 1. BASIC GPIO REGISTER TESTS (Tests 1-15)
# ===============================================================================
basic_register_tests:
    mv s2, ra

    # Test 1-8: Individual register read/write tests
    li s0, 0        # Register offset counter
    li s1, 8        # Number of registers to test

register_rw_loop:
    addi gp, gp, 1
    
    # Calculate register address
    slli t0, s0, 2  # s0 * 4 for register offset
    add t1, a0, t0  # GPIO0 base + offset
    
    # Skip input register (read-only) and junk register (special behavior)
    li t2, GPIO_PxIN
    beq t0, t2, skip_register
    li t2, GPIO_JUNK_REG  
    beq t0, t2, test_junk_register
    
    # Test normal read/write register
    li s3, 0x55     # Test pattern
    sw s3, 0(t1)    # Write test pattern
    lw s4, 0(t1)    # Read back
    bne s3, s4, fail
    
    li s3, 0xAA     # Alternate pattern
    sw s3, 0(t1)
    lw s4, 0(t1)
    bne s3, s4, fail
    
    j next_register

test_junk_register:
    # Junk register should always read 0
    li s3, 0x55
    sw s3, 0(t1)    # Write any value
    lw s4, 0(t1)    # Should read 0
    bnez s4, fail

skip_register:
next_register:
    addi s0, s0, 1
    blt s0, s1, register_rw_loop

    # Test 9-15: Pattern tests on output register
    li s0, 0        # Pattern counter
    li s1, 7        # Number of patterns

pattern_test_loop:
    addi gp, gp, 1
    
    # Select test pattern based on counter
    jal ra, get_test_pattern
    
    # Write pattern to GPIO0 output register
    sw s3, GPIO_PxOUT(a0)
    
    # Read back and verify
    lw s4, GPIO_PxOUT(a0)
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, pattern_test_loop

    mv ra, s2
    ret

# ===============================================================================
# 2. GPIO SET/CLEAR/TOGGLE TESTS (Tests 16-60)
# ===============================================================================
set_clear_toggle_tests:
    mv s2, ra

    # Tests 16-30: Set register functionality
    jal ra, test_set_register
    
    # Tests 31-45: Clear register functionality  
    jal ra, test_clear_register
    
    # Tests 46-60: Toggle register functionality
    jal ra, test_toggle_register

    mv ra, s2
    ret

test_set_register:
    # Initialize output register to 0
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    # Test setting individual bits
    li s0, 0        # Bit position counter
    li s1, 8        # Number of bits
    li s3, 0x00     # Expected accumulator

set_individual_bits:
    addi gp, gp, 1
    
    # Calculate bit mask (1 << s0)
    li s6, 1
    sll s6, s6, s0
    
    # Set the bit
    sw s6, GPIO_PxOUTS(a0)
    
    # Update expected value
    or s3, s3, s6
    
    # Read and verify output register
    lw s4, GPIO_PxOUT(a0)
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, set_individual_bits

    # Test setting multiple bits at once
    li s0, 0        # Pattern counter
    li s1, 4        # Number of multi-bit patterns

    mv t3, ra       #Save return adddress

set_multiple_bits:
    addi gp, gp, 1
    
    # Reset output register
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    # Get multi-bit pattern
    jal ra, get_multibit_pattern
    
    # Set the pattern
    sw s3, GPIO_PxOUTS(a0)
    
    # Verify result
    lw s4, GPIO_PxOUT(a0)
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, set_multiple_bits

    mv ra, t3       #Restore return adddress
    ret

test_clear_register:
    # Initialize output register to all 1s
    li t0, ALL_PINS_MASK
    sw t0, GPIO_PxOUT(a0)
    
    # Test clearing individual bits
    li s0, 0        # Bit position counter
    li s1, 8        # Number of bits
    li s3, ALL_PINS_MASK  # Expected accumulator

clear_individual_bits:
    addi gp, gp, 1
    
    # Calculate bit mask (1 << s0)
    li s6, 1
    sll s6, s6, s0
    
    # Clear the bit
    sw s6, GPIO_PxOUTC(a0)
    
    # Update expected value
    not t0, s6
    and s3, s3, t0
    
    # Read and verify output register
    lw s4, GPIO_PxOUT(a0)
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, clear_individual_bits

    # Test clearing multiple bits at once
    li s0, 0        # Pattern counter
    li s1, 4        # Number of multi-bit patterns

    mv t3, ra       #Save return adddress
clear_multiple_bits:
    addi gp, gp, 1
    
    # Reset output register to all 1s
    li t0, ALL_PINS_MASK
    sw t0, GPIO_PxOUT(a0)
    
    # Get multi-bit pattern to clear
    jal ra, get_multibit_pattern
    
    # Clear the pattern
    sw s3, GPIO_PxOUTC(a0)
    
    # Calculate expected result
    not t0, s3
    li s4, ALL_PINS_MASK
    and s4, s4, t0
    
    # Verify result
    lw t1, GPIO_PxOUT(a0)
    bne s4, t1, fail
    
    addi s0, s0, 1
    blt s0, s1, clear_multiple_bits

    mv ra, t3       #Restore return adddress
    ret

test_toggle_register:

    # addi gp, gp, 2 #account for two above missing tests
    # Test toggling from 0
    li s0, 0        # Pattern counter
    li s1, 8        # Number of patterns

    mv t3, ra       #Save return adddress

toggle_from_zero:
    addi gp, gp, 1
    
    # Reset output register to 0
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    # Get toggle pattern
    jal ra, get_test_pattern
    
    # Toggle the pattern
    sw s3, GPIO_PxOUTT(a0)
    
    # Result should equal the pattern
    lw s4, GPIO_PxOUT(a0)
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, toggle_from_zero

    # Test toggling from 1
    li s0, 0        # Pattern counter
    li s1, 8        # Number of patterns

toggle_from_ones:
    addi gp, gp, 1
    
    # Reset output register to all 1s
    li t0, ALL_PINS_MASK
    sw t0, GPIO_PxOUT(a0)
    
    # Get toggle pattern
    jal ra, get_test_pattern
    
    # Toggle the pattern
    sw s3, GPIO_PxOUTT(a0)
    
    # Calculate expected result (all 1s XOR pattern)
    li t0, ALL_PINS_MASK
    xor s4, t0, s3
    
    # Verify result
    lw t1, GPIO_PxOUT(a0)
    bne s4, t1, fail
    
    addi s0, s0, 1
    blt s0, s1, toggle_from_ones

    mv ra, t3       #Restore return adddress

    ret

# ===============================================================================
# 3. GPIO DIRECTION CONTROL TESTS (Tests 61-70)
# ===============================================================================
direction_control_tests:
    mv s2, ra

    # Test output functionality with different direction settings
    li s0, 0        # Test counter
    li s1, 10       # Number of direction tests

direction_test_loop:
    addi gp, gp, 1
    
    # Get direction mask for this test
    jal ra, get_direction_pattern
    
    # Set GPIO0 direction
    sw s3, GPIO_PxDIR(a0)
    
    # Set GPIO1 as input for pins that GPIO0 drives
    not t0, s3
    sw t0, GPIO_PxDIR(a1)
    
    # Test output only on pins configured as output
    li s5, 0x55     # Test pattern
    and s5, s5, s3  # Mask with direction
    
    # Write to GPIO0 output
    sw s5, GPIO_PxOUT(a0)
    
    # Small delay for signal propagation
    # 
    
    # Read GPIO1 input (should see the driven values)
    lw s4, GPIO_PxIN(a1)
    and s4, s4, s3  # Mask with direction
    
    # Compare (only check pins that are outputs)
    bne s5, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, direction_test_loop

    mv ra, s2
    ret

# ===============================================================================
# 4. GPIO COMMUNICATION TESTS (Tests 71-80)
# ===============================================================================
communication_tests:
    mv s2, ra

    # Test bidirectional communication
    li s0, 0        # Test counter
    li s1, 10       # Number of communication patterns

communication_loop:
    addi gp, gp, 1
    
    # Get test pattern
    jal ra, get_test_pattern
    
    # Configure GPIO0 as output, GPIO1 as input
    li t0, ALL_OUTPUT
    sw t0, GPIO_PxDIR(a0)
    li t0, ALL_INPUT  
    sw t0, GPIO_PxDIR(a1)
    
    # Send pattern from GPIO0
    sw s3, GPIO_PxOUT(a0)
    
    # Delay for propagation
    # 
    
    # Read at GPIO1
    lw s4, GPIO_PxIN(a1)
    bne s3, s4, fail
    
    # Test reverse direction
    # Configure GPIO1 as output, GPIO0 as input
    li t0, ALL_OUTPUT
    sw t0, GPIO_PxDIR(a1)
    li t0, ALL_INPUT
    sw t0, GPIO_PxDIR(a0)
    
    # Invert pattern for reverse test
    not s5, s3
    andi s5, s5, ALL_PINS_MASK
    
    # Send from GPIO1
    sw s5, GPIO_PxOUT(a1)
    
    # Delay for propagation
    # 
    
    # Read at GPIO0
    lw s4, GPIO_PxIN(a0)
    bne s5, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, communication_loop

    mv ra, s2
    ret

# ===============================================================================
# 5. GPIO INTERRUPT TESTS (Tests 81-130) 
# ===============================================================================
interrupt_tests:
    mv s2, ra

    # Test 81-90: Interrupt register access tests
    jal ra, interrupt_register_tests
    
    # Test 91-100: Rising edge interrupt tests
    jal ra, rising_edge_interrupt_tests
    
    # Test 101-110: Falling edge interrupt tests
    jal ra, falling_edge_interrupt_tests
    
    # Test 111-120: Multiple pin interrupt tests
    jal ra, multiple_pin_interrupt_tests
    
    # Test 121-130: Interrupt flag clearing tests
    jal ra, interrupt_flag_clearing_tests

    mv ra, s2
    ret

# ===============================================================================
# 5.1 INTERRUPT REGISTER ACCESS TESTS (Tests 81-90)
# ===============================================================================
interrupt_register_tests:
    mv t3, ra

    # Test 81-83: Test IES register read/write
    li s0, 0
    li s1, 3

ies_register_test_loop:
    addi gp, gp, 1
    
    jal ra, get_test_pattern
    sw s3, GPIO_PxIES(a1)    # Write to GPIO1 IES
    lw s4, GPIO_PxIES(a1)    # Read back
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, ies_register_test_loop

    # Test 84-86: Test IE register read/write  
    li s0, 0
    li s1, 3

ie_register_test_loop:
    addi gp, gp, 1
    
    jal ra, get_test_pattern
    sw s3, GPIO_PxIE(a1)     # Write to GPIO1 IE
    lw s4, GPIO_PxIE(a1)     # Read back
    bne s3, s4, fail
    
    addi s0, s0, 1
    blt s0, s1, ie_register_test_loop

    # Test 87-89: Test IF register clearing behavior
    li s0, 0
    li s1, 3

if_register_test_loop:
    addi gp, gp, 1
    
    # First clear any existing flags
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Verify IF register reads 0 after clear
    lw s4, GPIO_PxIFG(a1)
    bnez s4, fail
    
    addi s0, s0, 1
    blt s0, s1, if_register_test_loop

    # Test 90: Test that writing 0 to IF doesn't clear flags (if any are set)
    addi gp, gp, 1
    
    # This test assumes no interrupts are pending currently
    # Write 0 to IF register
    li t0, 0x00
    sw t0, GPIO_PxIFG(a1)
    
    # Verify IF register still reads 0 (no effect)
    lw s4, GPIO_PxIFG(a1)
    bnez s4, fail

    mv ra, t3
    ret

# ===============================================================================
# 5.2 RISING EDGE INTERRUPT TESTS (Tests 91-100)
# ===============================================================================
rising_edge_interrupt_tests:
    mv t3, ra

    # Setup: Configure GPIO0 as output, GPIO1 as input for interrupt testing
    li t0, ALL_OUTPUT
    sw t0, GPIO_PxDIR(a0)
    li t0, ALL_INPUT
    sw t0, GPIO_PxDIR(a1)
    
    # Clear all interrupt settings
    li t0, 0x00
    sw t0, GPIO_PxIE(a1)     # Disable all interrupts
    sw t0, GPIO_PxIES(a1)    # Set for rising edge (0 = low-to-high)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)     # Clear all flags

    # Test 91-98: Individual pin rising edge tests
    li s0, 0        # Pin counter
    li s1, 8        # Number of pins to test

single_pin_rising_test:
    addi gp, gp, 1
    
    # Calculate pin mask
    li s6, 1
    sll s6, s6, s0  # Pin mask for current pin
    
    # Clear all outputs (start low)
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    # Clear interrupt flags
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Configure interrupt for this pin (rising edge, enabled)
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)    # Rising edge
    sw s6, GPIO_PxIE(a1)     # Enable only this pin
    
    # Verify no interrupt flag is set initially
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    bnez s4, fail
    
    # Create rising edge by setting the output pin
    sw s6, GPIO_PxOUT(a0)
    
    # Check that interrupt flag is now set for this pin
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    beqz s4, fail
    
    # Verify only this pin's flag is set
    not t0, s6
    and s5, s4, t0
    bnez s5, fail
    
    addi s0, s0, 1
    blt s0, s1, single_pin_rising_test

    # Test 99: Multiple transitions on same pin
    addi gp, gp, 1
    
    li s6, 0x01     # Test pin 0
    
    # Clear outputs and flags
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Configure for rising edge on pin 0
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    sw s6, GPIO_PxIE(a1)
    
    
    # Generate multiple rising edges
    li s0, 0        # Transition counter
    li s1, 3        # Number of transitions

multiple_rising_transitions:
    # Create falling edge first (high to low)
    sw s6, GPIO_PxOUT(a0)
    
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    
    # Create rising edge (low to high)
    sw s6, GPIO_PxOUT(a0)
    
    
    # Check interrupt flag is set
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    beqz s4, fail
    
    # Clear the flag
    sw s6, GPIO_PxIFG(a1)
    
    addi s0, s0, 1
    blt s0, s1, multiple_rising_transitions

    # Test 100: Verify no interrupt on falling edge when configured for rising
    addi gp, gp, 1
    
    # Start high
    sw s6, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)     # Clear flags
    
    
    # Create falling edge
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    
    # Verify no interrupt flag set
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    bnez s4, fail

    mv ra, t3
    ret

# ===============================================================================
# 5.3 FALLING EDGE INTERRUPT TESTS (Tests 101-110)
# ===============================================================================
falling_edge_interrupt_tests:
    mv t3, ra

    # Test 101-108: Individual pin falling edge tests
    li s0, 0        # Pin counter
    li s1, 8        # Number of pins to test

single_pin_falling_test:
    addi gp, gp, 1
    
    # Calculate pin mask
    li s6, 1
    sll s6, s6, s0  # Pin mask for current pin
    
    # Start high
    sw s6, GPIO_PxOUT(a0)
    
    # Clear interrupt flags  
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Configure interrupt for this pin (falling edge, enabled)
    sw s6, GPIO_PxIES(a1)    # Falling edge (1 = high-to-low)
    sw s6, GPIO_PxIE(a1)     # Enable only this pin
    
    # Wait for signals to settle
    
    
    # Verify no interrupt flag is set initially
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    bnez s4, fail
    
    # Create falling edge by clearing the output pin
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    # Wait for interrupt to propagate
    
    
    # Check that interrupt flag is now set for this pin
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    beqz s4, fail
    
    addi s0, s0, 1
    blt s0, s1, single_pin_falling_test

    # Test 109: Verify no interrupt on rising edge when configured for falling
    addi gp, gp, 1
    
    li s6, 0x01     # Test pin 0
    
    # Start low
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)     # Clear flags
    
    # Configure for falling edge
    sw s6, GPIO_PxIES(a1)    # Falling edge
    sw s6, GPIO_PxIE(a1)     # Enable pin 0
    
    
    
    # Create rising edge
    sw s6, GPIO_PxOUT(a0)
    
    
    # Verify no interrupt flag set
    lw s4, GPIO_PxIFG(a1)
    and s4, s4, s6
    bnez s4, fail

    # Test 110: Mixed edge configuration test
    addi gp, gp, 1
    
    # Configure pin 0 for rising edge, pin 1 for falling edge
    li t0, 0x02     # Pin 1 for falling edge
    sw t0, GPIO_PxIES(a1)
    li t0, 0x03     # Enable both pins 0 and 1
    sw t0, GPIO_PxIE(a1)
    
    # Start both low
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)     # Clear flags
    
    
    # Create rising edge on pin 0 (should trigger)
    li t0, 0x01
    sw t0, GPIO_PxOUT(a0)
    
    
    # Check only pin 0 flag is set
    lw s4, GPIO_PxIFG(a1)
    andi t0, s4, 0x01
    beqz t0, fail              # Pin 0 should be set
    andi t0, s4, 0x02
    bnez t0, fail              # Pin 1 should not be set

    mv ra, t3
    ret

# ===============================================================================
# 5.4 MULTIPLE PIN INTERRUPT TESTS (Tests 111-120)
# ===============================================================================
multiple_pin_interrupt_tests:
    mv t3, ra

    # Test 111-115: Multiple simultaneous interrupts
    li s0, 0        # Test pattern counter
    li s1, 5        # Number of patterns to test

multiple_simultaneous_test:
    addi gp, gp, 1
    
    # Get test pattern for multiple pins
    jal ra, get_multibit_pattern
    mv s6, s3       # Pin mask
    
    # Start all pins low
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)     # Clear flags
    
    # Configure all test pins for rising edge interrupts
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)    # All rising edge
    sw s6, GPIO_PxIE(a1)     # Enable test pins
    
    
    
    # Create simultaneous rising edges on all test pins
    sw s6, GPIO_PxOUT(a0)
    
    
    # Check that all test pin flags are set
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    bne s5, s6, fail           # All enabled pins should have flags set
    
    # Check that no other pins have flags set
    not t0, s6
    and s5, s4, t0
    bnez s5, fail              # No other pins should have flags
    
    addi s0, s0, 1
    blt s0, s1, multiple_simultaneous_test

    # Test 116-118: Sequential interrupts on different pins
    li s0, 0        # Pin counter
    li s1, 3        # Test 3 pins sequentially

sequential_interrupt_test:
    addi gp, gp, 1
    
    # Clear everything
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Enable interrupts on first 3 pins (rising edge)
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    li t0, 0x07     # Pins 0, 1, 2
    sw t0, GPIO_PxIE(a1)
    
    
    
    # Trigger interrupt on pin s0
    li s6, 1
    sll s6, s6, s0  # Pin mask
    sw s6, GPIO_PxOUT(a0)
    
    
    # Check only this pin's flag is set
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    beqz s5, fail              # This pin should be set
    
    # Clear this pin's flag
    sw s6, GPIO_PxIFG(a1)
    
    # Set output low again for next iteration
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    
    addi s0, s0, 1
    blt s0, s1, sequential_interrupt_test

    # Test 119: Interrupt priority/accumulation test
    addi gp, gp, 1
    
    # Clear everything
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Enable interrupts on pins 0 and 1 (rising edge)
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    li t0, 0x03     # Pins 0, 1
    sw t0, GPIO_PxIE(a1)
    
    
    
    # Trigger pin 0 first
    li t0, 0x01
    sw t0, GPIO_PxOUT(a0)
    
    
    # Trigger pin 1 while pin 0 flag is still set
    li t0, 0x03
    sw t0, GPIO_PxOUT(a0)
    
    
    # Both flags should be set
    lw s4, GPIO_PxIFG(a1)
    andi t0, s4, 0x03
    li t1, 0x03
    bne t0, t1, fail

    # Test 120: Disabled interrupt test
    addi gp, gp, 1
    
    # Clear everything
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    sw t0, GPIO_PxIE(a1)     # Disable all interrupts
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)     # Clear flags
    
    
    
    # Try to trigger interrupt on pin 0 (should not work since disabled)
    li t0, 0x01
    sw t0, GPIO_PxOUT(a0)
    
    
    # Verify no interrupt flag is set
    lw s4, GPIO_PxIFG(a1)
    bnez s4, fail

    mv ra, t3
    ret

# ===============================================================================
# 5.5 INTERRUPT FLAG CLEARING TESTS (Tests 121-130)
# ===============================================================================
interrupt_flag_clearing_tests:
    mv t3, ra

    # Test 121-125: Individual flag clearing
    li s0, 0        # Pin counter
    li s1, 5        # Test first 5 pins

individual_flag_clear_test:
    addi gp, gp, 1
    
    # Setup: Generate interrupt on pin s0
    li s6, 1
    sll s6, s6, s0  # Pin mask
    
    # Clear outputs and flags
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Configure for rising edge interrupt
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    sw s6, GPIO_PxIE(a1)
    
    
    
    # Generate interrupt
    sw s6, GPIO_PxOUT(a0)
    
    
    # Verify flag is set
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    beqz s5, fail
    
    # Clear only this flag
    sw s6, GPIO_PxIFG(a1)
    
    # Verify flag is cleared
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    bnez s5, fail
    
    addi s0, s0, 1
    blt s0, s1, individual_flag_clear_test

    # Test 126-128: Multiple flag clearing
    li s0, 0        # Test counter
    li s1, 3        # Number of tests

multiple_flag_clear_test:
    addi gp, gp, 1
    
    # Generate interrupts on multiple pins
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Configure pins 0, 1, 2 for rising edge
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    li t0, 0x07     # Pins 0, 1, 2
    sw t0, GPIO_PxIE(a1)
    
    
    
    # Generate interrupts on all three pins
    li t0, 0x07
    sw t0, GPIO_PxOUT(a0)
    
    
    # Verify all flags are set
    lw s4, GPIO_PxIFG(a1)
    andi t0, s4, 0x07
    li t1, 0x07
    bne t0, t1, fail
    
    # Clear only pins 0 and 2
    li t0, 0x05     # Clear pins 0 and 2
    sw t0, GPIO_PxIFG(a1)
    
    # Verify only pin 1 flag remains
    lw s4, GPIO_PxIFG(a1)
    andi t0, s4, 0x07
    li t1, 0x02     # Only pin 1
    bne t0, t1, fail
    
    addi s0, s0, 1
    blt s0, s1, multiple_flag_clear_test

    # Test 129: Clear all flags at once
    addi gp, gp, 1
    
    # Generate interrupts on all pins
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Enable all pins for rising edge
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    li t0, 0xFF
    sw t0, GPIO_PxIE(a1)
    
    
    
    # Generate interrupts on all pins
    li t0, 0xFF
    sw t0, GPIO_PxOUT(a0)
    
    
    # Verify all flags are set
    lw s4, GPIO_PxIFG(a1)
    li t0, 0xFF
    bne s4, t0, fail
    
    # Clear all flags
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    # Verify all flags are cleared
    lw s4, GPIO_PxIFG(a1)
    bnez s4, fail

    # Test 130: Flag persistence test (flags should remain set until cleared)
    addi gp, gp, 1
    
    # Generate interrupt
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    li t0, 0xFF
    sw t0, GPIO_PxIFG(a1)
    
    li s6, 0x01     # Pin 0
    li t0, 0x00
    sw t0, GPIO_PxIES(a1)
    sw s6, GPIO_PxIE(a1)
    
    
    
    # Generate interrupt
    sw s6, GPIO_PxOUT(a0)
    
    
    # Verify flag is set
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    beqz s5, fail
    
    # Change signal back to low (should not affect flag)
    li t0, 0x00
    sw t0, GPIO_PxOUT(a0)
    
    
    # Flag should still be set
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    beqz s5, fail
    
    # Generate another rising edge (should not change existing flag)
    sw s6, GPIO_PxOUT(a0)
    
    
    # Flag should still be set (not cleared by new edge)
    lw s4, GPIO_PxIFG(a1)
    and s5, s4, s6
    beqz s5, fail

    mv ra, t3
    ret

# ===============================================================================
# UTILITY FUNCTIONS
# ===============================================================================

# Get test pattern based on s0 counter
get_test_pattern:
    # Pattern selection based on s0
    li t0, 0
    beq s0, t0, pattern_0x00
    li t0, 1
    beq s0, t0, pattern_0xFF
    li t0, 2
    beq s0, t0, pattern_0x55
    li t0, 3
    beq s0, t0, pattern_0xAA
    li t0, 4
    beq s0, t0, pattern_0x0F
    li t0, 5
    beq s0, t0, pattern_0xF0
    li t0, 6
    beq s0, t0, pattern_0x33
    # Default
    li s3, 0xCC
    ret

pattern_0x00:
    li s3, 0x00
    ret
pattern_0xFF:
    li s3, 0xFF
    ret
pattern_0x55:
    li s3, 0x55
    ret
pattern_0xAA:
    li s3, 0xAA
    ret
pattern_0x0F:
    li s3, 0x0F
    ret
pattern_0xF0:
    li s3, 0xF0
    ret
pattern_0x33:
    li s3, 0x33
    ret

# Get multi-bit pattern for set/clear tests
get_multibit_pattern:
    li t0, 0
    beq s0, t0, multi_0x11
    li t0, 1
    beq s0, t0, multi_0x22
    li t0, 2
    beq s0, t0, multi_0x44
    li t0, 3
    beq s0, t0, multi_0x88
    # Default
    li s3, 0x0F
    ret

multi_0x11:
    li s3, 0x11
    ret
multi_0x22:
    li s3, 0x22
    ret
multi_0x44:
    li s3, 0x44
    ret
multi_0x88:
    li s3, 0x88
    ret

# Get direction pattern for direction tests
get_direction_pattern:
    # Create varying direction patterns
    li t0, 0
    beq s0, t0, dir_all_out
    li t0, 1
    beq s0, t0, dir_all_in
    li t0, 2
    beq s0, t0, dir_alternate
    li t0, 3
    beq s0, t0, dir_lower_half
    li t0, 4
    beq s0, t0, dir_upper_half
    # Generate pattern based on counter
    andi s3, s0, 0xFF
    ret

dir_all_out:
    li s3, 0xFF
    ret
dir_all_in:
    li s3, 0x00
    ret
dir_alternate:
    li s3, 0x55
    ret
dir_lower_half:
    li s3, 0x0F
    ret
dir_upper_half:
    li s3, 0xF0
    ret

# Short delay for signal propagation
short_delay:
    li t0, 1000
delay_loop:
    addi t0, t0, -1
    bnez t0, delay_loop
    ret

RVTEST_CODE_END

    .data
RVTEST_DATA_BEGIN
    TEST_DATA
RVTEST_DATA_END






