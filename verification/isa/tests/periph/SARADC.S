#*****************************************************************************
# SARADC_TESTBENCH.S
#-----------------------------------------------------------------------------
# SARADC (Successive Approximation Register ADC) testbench for RISC-V RV32IMC
# Tests all SARADC registers for read/write functionality
#
# Register Map (from VHDL):
# - SARADC_CR   (Control Register)    - 9 bits R/W
# - SARADC_SR   (Status Register)     - 4 bits R/W (write 1 to clear)
# - SARADC_DATA (ADC Data Register)   - 10 bits R only
# - SARADC_TPR  (Test Port Register)  - 8 bits R/W
#
# SARADC_CR Bit Map:
# - Bit 0: ADC Reset
# - Bits 4:1: ADC sync init sample step
# - Bit 5: ADC Enable
# - Bit 6: Debug Mode
# - Bit 7: ADC Data Valid Interrupt Enable
# - Bit 8: ADC Continuous Measurement
#
# SARADC_SR Bit Map:
# - Bit 0: Conversion Busy
# - Bit 1: ADC Data Valid
# - Bit 2: ADC Overflow Interrupt Flag
# - Bit 3: ADC Ready
#
# Test Categories:
# 1. Control Register Tests
# 2. Status Register Tests
# 3. Data Register Tests
# 4. Test Port Register Tests
# 5. ADC Operation Tests
# 6. Interrupt Tests
# 7. Continuous Mode Tests
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"

# SARADC Register Offsets (assuming 4-byte aligned addresses)
#define SARADC_CR        0x00
#define SARADC_SR        0x04
#define SARADC_DATA      0x08
#define SARADC_TPR       0x0C


# Reset values
#define SARADC_CR_RESET         0x00000000
#define SARADC_SR_RESET         0x00000000
#define SARADC_TPR_RESET        0x00000000

# Test patterns
#define PATTERN_AA              0x000000AA
#define PATTERN_55              0x00000055
#define PATTERN_FF              0x000000FF
#define PATTERN_00              0x00000000

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# Register Usage Convention
# ===============================================================================
# x10 (a0) - SARADC base address (preserved)
# x3  (gp) - Test counter (preserved)
# x8  (s0) - Test pattern/value
# x9  (s1) - Expected value
# x18 (s2) - Test suite return address
# x19 (s3) - Mask for current register
# x20 (s4) - Read value from register
# x21 (s5) - Temporary test value
# x5-x7, x28-x31 (t0-t4) - Temporary registers
# ===============================================================================

saradc_testbench_start:
    # Initialize base address and test counter
    li  a0, PERIPH_SARADC0_BASE  # You'll need to define this in myshkin_s.h
    li  gp, 0

    # Initialize SARADC peripheral
    jal ra, init_saradc_peripheral

    # Run all test suites
    jal ra, test_control_register

    # All tests passed
    TEST_PASSFAIL

# ===============================================================================
# SARADC INITIALIZATION
# ===============================================================================
init_saradc_peripheral:
    # Reset the ADC by setting reset bit
    li t0, ADC_RESET_BIT
    sw t0, SARADC_CR(a0)
    
    # Clear reset and set defaults
    li t0, SARADC_CR_RESET
    sw t0, SARADC_CR(a0)
    
    # Clear any pending status bits
    li t0, 0x06  # Clear data valid and overflow flags
    sw t0, SARADC_SR(a0)
    
    ret

# ===============================================================================
# 1. CONTROL REGISTER TESTS (Tests 1-20)
# ===============================================================================
test_control_register:
    mv s2, ra

    # Test 1: SARADC_CR write/read with 0x00
    addi gp, gp, 1
    li s0, 0x00000000
    li s3, SARADC_CR_MASK
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 2: SARADC_CR write/read with 0x1FF (all bits set)
    addi gp, gp, 1
    li s0, 0x000001FF
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 3: SARADC_CR write/read with 0x155
    addi gp, gp, 1
    li s0, 0x00000155
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 4: SARADC_CR write/read with 0x0AA
    addi gp, gp, 1
    li s0, 0x000000AA
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 5-9: Walking 1s test for SARADC_CR
    li t0, 0
    li t1, 9  # 9 bits in SARADC_CR

walk_1_saradc_cr:
    addi gp, gp, 1
    li s0, 1
    sll s0, s0, t0
    and s0, s0, s3
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail
    addi t0, t0, 1
    blt t0, t1, walk_1_saradc_cr

    # Test 10-14: Walking 0s test for SARADC_CR
    li t0, 0
    li t1, 9

walk_0_saradc_cr:
    addi gp, gp, 1
    li s0, 1
    sll s0, s0, t0
    not s0, s0
    and s0, s0, s3
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail
    addi t0, t0, 1
    blt t0, t1, walk_0_saradc_cr

    # Test 15: Test ADC reset bit
    addi gp, gp, 1
    li s0, ADC_RESET_BIT
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 16: Test sample step field (bits 4:1)
    addi gp, gp, 1
    li s0, 0x0000001E  # Max sample step value (1111 in bits 4:1)
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 17: Test ADC enable bit
    addi gp, gp, 1
    li s0, ADC_EN_BIT
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 18: Test debug mode bit
    addi gp, gp, 1
    li s0, DEBUG_MODE_BIT
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 19: Test interrupt enable bit
    addi gp, gp, 1
    li s0, ADC_DATA_VALID_IE_BIT
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 20: Test continuous measurement bit
    addi gp, gp, 1
    li s0, ADC_CONT_MEAS_BIT
    sw s0, SARADC_CR(a0)
    lw s4, SARADC_CR(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Reset control register
    sw zero, SARADC_CR(a0)

    mv ra, s2
    ret


# ===============================================================================
# Test failed - store test number and halt
# ===============================================================================
# fail:
#     # gp contains the test number that failed
#     RVTEST_FAIL

# ===============================================================================
# End of test
# ===============================================================================
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 4
test_data:
    .word 0xDEADBEEF
    .word 0xCAFEBABE
    .word 0x12345678
    .word 0x9ABCDEF0
    .word 0x00000000
    .word 0xFFFFFFFF
    .word 0x5A5A5A5A
    .word 0xA5A5A5A5
RVTEST_DATA_END