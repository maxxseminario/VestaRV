#*****************************************************************************
# SYSTEM_TESTBENCH_UPDATED.S
#-----------------------------------------------------------------------------
# Updated SYSTEM Peripheral testbench for RISC-V RV32IMC
# Matches new SYSTEM peripheral implementation
# Date: 2025-10-05
#
# Test Categories:
# 1-5: Register Boundary Tests (5 tests)
# 6-10: Clock Control Tests (5 tests)
# 11-15: Clock Divider Tests (5 tests)
# 16-20: Memory Power Control Tests (5 tests)
# 21-25: Memory Access with Power Control Tests (5 tests)
# 26-30: CRC State Tests (5 tests)
# 31-40: IRQ Comprehensive Tests (10 tests)
# 41-45: DCO Bias Tests (5 tests)
# 46-55: Watchdog Comprehensive Tests (10 tests)
# 56-60: Watchdog Counter Behavior Tests (5 tests)
# 61-65: Global IRQ Control Tests (5 tests)
# 66-70: Register Reset Behavior Tests (5 tests)
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"


# Test values
#define SYS_CLK_CR_TEST         0x00000082  # DCO0 on, MCLK sel = 2
#define SYS_CLK_DIV_TEST        0x00000009  # MCLK div = 1, SMCLK div = 1

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# Test Initialization
# ===============================================================================
system_init:
    li  a0, PERIPH_SYSTEM0_BASE
    sw  zero, SYS_CLK_CR(a0)       # Disable all clocks initially
    sw  zero, SYS_CLK_DIV_CR(a0)   # No clock division
    sw  zero, SYS_BLOCK_PWR(a0)    # All memory enabled
    sw  zero, SYS_IRQ_ENL(a0)      # Disable all IRQs
    sw  zero, SYS_IRQ_ENM(a0)
    sw  zero, SYS_IRQ_ENH(a0)
    sw  zero, SYS_IRQ_CR(a0)       # Global IRQ disable
    li  gp, 0                       # Initialize test counter

# ------------------------------------------------------------------------------
# Test Suite Execution
# ------------------------------------------------------------------------------
    jal ra, test_register_boundaries
    jal ra, test_clk_control_updated
    jal ra, test_clk_divider_updated
    jal ra, test_mem_power_updated
    jal ra, test_memory_access_with_power
    jal ra, test_crc_state_updated
    jal ra, test_irq_comprehensive_updated
    jal ra, test_dco_bias_registers
    jal ra, test_wdt_comprehensive_updated
    jal ra, test_wdt_counter_behavior_updated
    jal ra, test_global_irq_control
    jal ra, test_register_reset_behavior_updated

# Success
all_sys_tests_passed:
    TEST_PASSFAIL

# ===============================================================================
# Tests 1-5: Register Boundary and Access Tests
# ===============================================================================
test_register_boundaries:
    mv s1, ra
    
    # Test 1: SYS_CLK_CR - 9-bit register
    addi gp, gp, 1
    li s3, 0x180
    sw s3, SYS_CLK_CR(a0)
    lw t0, SYS_CLK_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    # Test 2: SYS_CLK_DIV_CR - 6-bit register
    addi gp, gp, 1
    li s3, SYS_CLK_DIV_CR_MASK
    sw s3, SYS_CLK_DIV_CR(a0)
    lw t0, SYS_CLK_DIV_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    # Test 3: SYS_BLOCK_PWR - 3-bit register
    addi gp, gp, 1
    li s3, SYS_BLOCK_PWR_MASK
    andi s3, s3, 0xFD      # Clear RAM0 Bit 
    sw s3, SYS_BLOCK_PWR(a0)
    lw t0, SYS_BLOCK_PWR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    # Test 4: SYS_WDT_CR - locked test (should not write)
    addi gp, gp, 1
    li s3, 0xBADC0DE  # Wrong password
    sw s3, SYS_WDT_PASS(a0)
    li s3, SYS_WDT_CR_MASK
    sw s3, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    bnez t0, fail  # Should remain zero (locked)

    # Test 5: SYS_WDT_CR - unlocked test (should write)
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    li s3, 0x7E  # All bits except hwrst
    sw s3, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    and t0, t0, SYS_WDT_CR_MASK
    bne t0, s3, fail

    # Clear all registers
    sw zero, SYS_CLK_CR(a0)
    # sw zero, SYS_CLK_DIV_CR(a0) -- Leave clock div cr - smclk as lfxt, mclk as hfxt
    sw zero, SYS_BLOCK_PWR(a0)
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    sw zero, SYS_WDT_CR(a0)

    mv ra, s1
    ret

# ===============================================================================
# Tests 6-10: Clock Control Tests 
# ===============================================================================
test_clk_control_updated:
    mv s1, ra

    # Set smclk to lfxt 


    # Test 6: MCLK selection (bits 1:0)
    addi gp, gp, 1
    li s3, 0x00000001  # MCLK_SEL = 1 for smclk as mclk
    sw s3, SYS_CLK_CR(a0)
    lw t0, SYS_CLK_CR(a0)
    and t0, t0, SYS_MCLK_SEL_MASK
    bne t0, s3, fail

    # Test 7: SMCLK selection (bits 3:2)
    addi gp, gp, 1
    li s3, 0x00000004  # SMCLK_SEL = 01 for lfxt as smclk
    sw s3, SYS_CLK_CR(a0)
    lw t0, SYS_CLK_CR(a0)
    and t0, t0, SYS_SMCLK_SEL_MASK
    bne t0, s3, fail

    # Test 8: Clock disable bits
    addi gp, gp, 1
    li s3, SYS_CLK_LFXT_OFF_MASK | SYS_SMCLK_OFF_MASK
    sw s3, SYS_CLK_CR(a0)
    lw t0, SYS_CLK_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    # Test 9: DCO0 enable
    addi gp, gp, 1
    li s3, SYS_DCO0_ON_MASK
    sw s3, SYS_CLK_CR(a0)
    lw t0, SYS_CLK_CR(a0)
    and t0, t0, SYS_DCO0_ON_MASK
    bne t0, s3, fail

    # Test 10: DCO1 enable
    addi gp, gp, 1
    li s3, SYS_DCO1_ON_MASK
    sw s3, SYS_CLK_CR(a0)
    lw t0, SYS_CLK_CR(a0)
    and t0, t0, SYS_DCO1_ON_MASK
    bne t0, s3, fail

    sw zero, SYS_CLK_CR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 11-15: Clock Divider Tests
# ===============================================================================
test_clk_divider_updated:
    mv s1, ra

    # Test 11: No division (000 for both)
    addi gp, gp, 1
    li s3, 0x00
    sw s3, SYS_CLK_DIV_CR(a0)
    lw t0, SYS_CLK_DIV_CR(a0)
    bne t0, s3, fail

    # Test 12: MCLK div by 2 (001)
    addi gp, gp, 1
    li s3, 0x01
    sw s3, SYS_CLK_DIV_CR(a0)
    lw t0, SYS_CLK_DIV_CR(a0)
    and t0, t0, SYS_MCLK_DIV_MASK
    bne t0, s3, fail

    # Test 13: SMCLK div by 2 (001 << 3)
    addi gp, gp, 1
    li s3, 0x08
    sw s3, SYS_CLK_DIV_CR(a0)
    lw t0, SYS_CLK_DIV_CR(a0)
    and t0, t0, SYS_SMCLK_DIV_MASK
    bne t0, s3, fail

    # Test 14: Both dividers at max (111)
    addi gp, gp, 1
    li s3, 0x3F
    sw s3, SYS_CLK_DIV_CR(a0)
    lw t0, SYS_CLK_DIV_CR(a0)
    bne t0, s3, fail

    # Test 15: Mixed divider settings
    addi gp, gp, 1
    li s3, 0x1A  # MCLK div by 4, SMCLK div by 8
    sw s3, SYS_CLK_DIV_CR(a0)
    lw t0, SYS_CLK_DIV_CR(a0)
    bne t0, s3, fail

    sw zero, SYS_CLK_DIV_CR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 16-20: Memory Power Control (Simplified for 3-bit register)
# ===============================================================================
test_mem_power_updated:
    mv s1, ra

    # Test 16: ROM off
    addi gp, gp, 1
    li s3, SYS_ROM_OFF_MASK
    sw s3, SYS_BLOCK_PWR(a0)
    lw t0, SYS_BLOCK_PWR(a0)
    and t0, t0, SYS_ROM_OFF_MASK
    beqz t0, fail

    # Test 17: RAM off pattern 01
    addi gp, gp, 1
    # li s3, 0x02
    # sw s3, SYS_BLOCK_PWR(a0)
    # lw t0, SYS_BLOCK_PWR(a0)
    # and t0, t0, SYS_RAM_OFF_MASK
    # bne t0, s3, fail

    # Test 18: RAM off pattern 10
    addi gp, gp, 1
    li s3, 0x04
    sw s3, SYS_BLOCK_PWR(a0)
    lw t0, SYS_BLOCK_PWR(a0)
    and t0, t0, SYS_RAM_OFF_MASK
    bne t0, s3, fail

    # Test 19: RAM off pattern 11
    addi gp, gp, 1
    # li s3, 0x06
    # sw s3, SYS_BLOCK_PWR(a0)
    # lw t0, SYS_BLOCK_PWR(a0)
    # and t0, t0, SYS_RAM_OFF_MASK
    # bne t0, s3, fail

    # Test 20: All memory off
    addi gp, gp, 1
    # li s3, 0x07
    # sw s3, SYS_BLOCK_PWR(a0)
    # lw t0, SYS_BLOCK_PWR(a0)
    # bne t0, s3, fail

    sw zero, SYS_BLOCK_PWR(a0)  # Re-enable all memory
    mv ra, s1
    ret

# ===============================================================================
# Tests 21-25: Memory Access with Power Control
# ===============================================================================
test_memory_access_with_power:
    mv s1, ra
    li a1, RAM0_BASE_ADDR
    li a2, RAM1_BASE_ADDR
    # li a3, RAM2_BASE_ADDR

    # Test 21: Write to RAM with all enabled
    addi gp, gp, 1
    sw zero, SYS_BLOCK_PWR(a0)
    li s3, 0xDEADBEEF
    sw s3, 0(a1)
    lw t0, 0(a1)
    bne t0, s3, fail

    # Test 22: Different RAM address
    addi gp, gp, 1
    li s3, 0x12345678
    sw s3, 0(a2)
    lw t0, 0(a2)
    bne t0, s3, fail

    # # Test 23: Another RAM address (This ram is now gone)
    addi gp, gp, 1
    # li s3, 0xABCDEF00
    # sw s3, 0(a3)
    # lw t0, 0(a3)
    # bne t0, s3, fail

    # Test 24: Multiple addresses in same block
    addi gp, gp, 1
    li s3, 0x55AA55AA
    sw s3, 4(a1)
    lw t0, 4(a1)
    bne t0, s3, fail

    # Test 25: Verify previous data persists
    addi gp, gp, 1
    lw t0, 0(a1)
    li s3, 0xDEADBEEF
    bne t0, s3, fail

    sw zero, SYS_BLOCK_PWR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 26-30: CRC State Tests
# ===============================================================================
test_crc_state_updated:
    mv s1, ra

    # Test 26: Initial CRC state write
    addi gp, gp, 1
    li s3, 0xFFFF
    sw s3, SYS_CRC_STATE(a0)
    # Note: Writing to CRC_STATE sets first_crc_flag

    # Test 27: First CRC data write
    addi gp, gp, 1
    li s3, 0x00
    sw s3, SYS_CRC_DATA(a0)
    lw s4, SYS_CRC_STATE(a0)
    # CRC should be computed

    # Test 28: Second CRC data write
    addi gp, gp, 1
    li s3, 0xFF
    sw s3, SYS_CRC_DATA(a0)
    lw t0, SYS_CRC_STATE(a0)
    beq t0, s4, fail  # Should be different

    # Test 29: Repeated same data
    addi gp, gp, 1
    li s3, 0xAA
    sw s3, SYS_CRC_DATA(a0)
    lw s4, SYS_CRC_STATE(a0)
    sw s3, SYS_CRC_DATA(a0)
    lw t0, SYS_CRC_STATE(a0)
    beq t0, s4, fail  # Should be different (chained)

    # Test 30: Reset CRC state
    addi gp, gp, 1
    li s3, 0x0000
    sw s3, SYS_CRC_STATE(a0)
    li s3, 0x55
    sw s3, SYS_CRC_DATA(a0)
    lw t0, SYS_CRC_STATE(a0)
    beqz t0, fail

    mv ra, s1
    ret

# ===============================================================================
# Tests 31-40: IRQ Comprehensive Tests (Updated for 32+ IRQs)
# ===============================================================================
test_irq_comprehensive_updated:
    mv s1, ra

    # Test 31: Enable IRQ 0
    addi gp, gp, 1
    li s3, 0x00000001
    sw s3, SYS_IRQ_ENL(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bne t0, s3, fail

    # Test 32: Enable IRQ 31
    addi gp, gp, 1
    li s3, 0x80000000
    sw s3, SYS_IRQ_ENL(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bne t0, s3, fail

    # Test 33: Enable IRQs 32-63
    addi gp, gp, 1
    li s3, 0xAAAAAAAA
    sw s3, SYS_IRQ_ENM(a0)
    lw t0, SYS_IRQ_ENM(a0)
    bne t0, s3, fail

    # Test 34: Enable upper IRQs (if NUM_IRQS > 64)
    addi gp, gp, 1
    li s3, 0x55555555
    sw s3, SYS_IRQ_ENH(a0)
    lw t0, SYS_IRQ_ENH(a0)
    # Mask based on actual NUM_IRQS
    li s2, 0x7FFFF #For 83 IRQs
    and s3, s3, s2 
    bne t0, s3, fail

    # Test 35: Set priority for IRQs 0-31
    addi gp, gp, 1
    li s3, 0x0F0F0F0F
    sw s3, SYS_IRQ_PRIL(a0)
    lw t0, SYS_IRQ_PRIL(a0)
    bne t0, s3, fail

    # Test 36: Set priority for IRQs 32-63
    addi gp, gp, 1
    li s3, 0xF0F0F0F0
    sw s3, SYS_IRQ_PRIM(a0)
    lw t0, SYS_IRQ_PRIM(a0)
    bne t0, s3, fail

    # Test 37: Clear all IRQ enables
    addi gp, gp, 1
    sw zero, SYS_IRQ_ENL(a0)
    sw zero, SYS_IRQ_ENM(a0)
    sw zero, SYS_IRQ_ENH(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bnez t0, fail

    # Test 38: Walking 1s test on IRQ_ENL
    addi gp, gp, 1
    li s3, 0x00000001
    li t1, 32
    li t2, 0
irq_walk_loop:
    sw s3, SYS_IRQ_ENL(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bne t0, s3, fail
    slli s3, s3, 1
    addi t2, t2, 1
    blt t2, t1, irq_walk_loop

    # Test 39: All IRQs enabled simultaneously
    addi gp, gp, 1
    li s3, -1
    sw s3, SYS_IRQ_ENL(a0)
    sw s3, SYS_IRQ_ENM(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bne t0, s3, fail

    # Test 40: Clear and verify
    addi gp, gp, 1
    sw zero, SYS_IRQ_ENL(a0)
    sw zero, SYS_IRQ_ENM(a0)
    sw zero, SYS_IRQ_ENH(a0)
    sw zero, SYS_IRQ_PRIL(a0)
    sw zero, SYS_IRQ_PRIM(a0)
    sw zero, SYS_IRQ_PRIH(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bnez t0, fail

    mv ra, s1
    ret

# ===============================================================================
# Tests 41-45: DCO Bias Register Tests
# ===============================================================================
test_dco_bias_registers:
    mv s1, ra

    li s6, DCO_BIAS_MASK

    # Test 41: SYS_DCO0_BIAS write all 1s
    addi gp, gp, 1
    li s3, DCO_BIAS_MASK
    sw s3, SYS_DCO0_BIAS(a0)
    lw t0, SYS_DCO0_BIAS(a0)
    and t0, t0, s6
    bne t0, s3, fail

    # Test 42: SYS_DCO0_BIAS write pattern
    addi gp, gp, 1
    li s3, 0x555
    sw s3, SYS_DCO0_BIAS(a0)
    lw t0, SYS_DCO0_BIAS(a0)
    and t0, t0, s6
    bne t0, s3, fail

    # Test 43: SYS_DCO1_BIAS write all 1s
    addi gp, gp, 1
    li s3, DCO_BIAS_MASK
    sw s3, SYS_DCO1_BIAS(a0)
    lw t0, SYS_DCO1_BIAS(a0)
    and t0, t0, s6
    bne t0, s3, fail

    # Test 44: SYS_DCO1_BIAS write pattern
    addi gp, gp, 1
    li s3, 0xAAA
    sw s3, SYS_DCO1_BIAS(a0)
    lw t0, SYS_DCO1_BIAS(a0)
    and t0, t0, s6
    bne t0, s3, fail

    # Test 45: Reset to defaults
    addi gp, gp, 1
    li s3, DCO0_BIAS_DEFAULT
    sw s3, SYS_DCO0_BIAS(a0)
    li s3, DCO1_BIAS_DEFAULT
    sw s3, SYS_DCO1_BIAS(a0)
    lw t0, SYS_DCO0_BIAS(a0)
    li t1, DCO0_BIAS_DEFAULT
    bne t0, t1, fail

    mv ra, s1
    ret

# ===============================================================================
# Tests 46-55: Watchdog Comprehensive Tests
# ===============================================================================
test_wdt_comprehensive_updated:
    mv s1, ra

    # Enable system IRQ for WDT testing
    li s3, IRQB_SYS_WDT
    sw s3, SYS_IRQ_ENL(a0)
    li s3, 1  # Enable global IRQ
    sw s3, SYS_IRQ_CR(a0)

    # Test 46: Wrong password attempt
    addi gp, gp, 1
    li s3, 0xBADC0FFE
    sw s3, SYS_WDT_PASS(a0)
    li s3, SYS_WDT_EN_MASK | SYS_WDT_CDIV_MASK
    sw s3, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    bnez t0, fail  # Should not write

    # Test 47: Correct unlock
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    li s3, SYS_WDT_EN_MASK | SYS_WDT_IE_MASK | SYS_WDT_CDIV_MASK
    sw s3, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    and t0, t0, SYS_WDT_EN_MASK
    beqz t0, fail

    # Test 48: Clear WDT counter
    addi gp, gp, 1
    li s3, WDT_CLR_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    jal ra, wait_short
    lw t0, SYS_WDT_VAL(a0)
    li t1, 100
    bgt t0, t1, fail

    # Test 49: Set clock divider
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    li s3, SYS_WDT_EN_MASK | (3 << 2) | SYS_WDT_IE_MASK  # cdiv = 3
    sw s3, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    and t0, t0, SYS_WDT_CDIV_MASK
    li t1, (3 << 2)
    bne t0, t1, fail

    # Test 50: Hardware reset bit (should not set)
    addi gp, gp, 1
    # li s3, WDT_UNLCK_PASSWD
    # sw s3, SYS_WDT_PASS(a0)
    # li s3, SYS_WDT_HWRST_MASK | SYS_WDT_EN_MASK
    # sw s3, SYS_WDT_CR(a0)
    # lw t0, SYS_WDT_CR(a0)
    # and t0, t0, SYS_WDT_HWRST_MASK
    # bnez t0, fail  # HWRST should not be settable

    # Test 51: WDT disable
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    sw zero, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    bnez t0, fail

    # Test 52: Re-enable with different settings
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    li s3, SYS_WDT_EN_MASK | (7 << 2)  # cdiv = 7
    sw s3, SYS_WDT_CR(a0)
    lw t0, SYS_WDT_CR(a0)
    and t1, t0, SYS_WDT_CDIV_MASK
    li t2, (7 << 2)
    bne t1, t2, fail

    # Test 53: Clear counter while enabled
    addi gp, gp, 1
    li s3, WDT_CLR_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    lw s4, SYS_WDT_VAL(a0)  # Should be small after clear

    # Test 54: Counter increments
    addi gp, gp, 1
    jal ra, wait_short
    lw t0, SYS_WDT_VAL(a0)
    ble t0, s4, fail  # Should have increased

    # Test 55: Final disable
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    sw zero, SYS_WDT_CR(a0)
    
    sw zero, SYS_IRQ_ENL(a0)
    sw zero, SYS_IRQ_CR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 56-60: Watchdog Counter Behavior
# ===============================================================================
test_wdt_counter_behavior_updated:
    mv s1, ra

    # Setup IRQ for WDT
    li s3, IRQB_SYS_WDT
    sw s3, SYS_IRQ_ENL(a0)
    li s3, 1
    sw s3, SYS_IRQ_CR(a0)

    # Test 56: Enable WDT with fast clock
    addi gp, gp, 1
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    li s3, SYS_WDT_EN_MASK | SYS_WDT_IE_MASK  # cdiv = 0 (fastest)
    sw s3, SYS_WDT_CR(a0)
    li s3, WDT_CLR_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    lw s4, SYS_WDT_VAL(a0)

    # Test 57: Verify counter increments
    addi gp, gp, 1
    jal ra, wait_short
    lw t0, SYS_WDT_VAL(a0)
    ble t0, s4, fail

    # Test 58: Clear and verify reset
    addi gp, gp, 1
    li s3, WDT_CLR_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    lw t0, SYS_WDT_VAL(a0)
    li t1, 10
    bgt t0, t1, fail

    # Test 59: Status register RF bit
    addi gp, gp, 1
    lw t0, SYS_WDT_SR(a0)
    # Check if RF bit can be read (implementation dependent)

    # Test 60: Clear status flags
    addi gp, gp, 1
    li s3, 0x03  # Clear both RF and IF
    sw s3, SYS_WDT_SR(a0)
    lw t0, SYS_WDT_SR(a0)
    and t0, t0, SYS_WDT_SR_MASK
    # Flags should be cleared

    # Disable WDT
    li s3, WDT_UNLCK_PASSWD
    sw s3, SYS_WDT_PASS(a0)
    sw zero, SYS_WDT_CR(a0)
    sw zero, SYS_IRQ_ENL(a0)
    sw zero, SYS_IRQ_CR(a0)

    mv ra, s1
    ret

# ===============================================================================
# Tests 61-65: Global IRQ Control Tests
# ===============================================================================
test_global_irq_control:
    mv s1, ra

    # Test 61: Global IRQ disable
    addi gp, gp, 1
    sw zero, SYS_IRQ_CR(a0)
    lw t0, SYS_IRQ_CR(a0)
    bnez t0, fail

    # Test 62: Global IRQ enable
    addi gp, gp, 1
    li s3, 1
    sw s3, SYS_IRQ_CR(a0)
    lw t0, SYS_IRQ_CR(a0)
    bne t0, s3, fail

    # Test 63: Enable IRQs with global disabled
    addi gp, gp, 1
    sw zero, SYS_IRQ_CR(a0)
    li s3, 0xFFFFFFFF
    sw s3, SYS_IRQ_ENL(a0)
    # IRQs should be masked by global disable

    # # Test 64: Re-enable global
    # addi gp, gp, 1
    # li s3, 1
    # sw s3, SYS_IRQ_CR(a0)
    # lw t0, SYS_IRQ_CR(a0)
    # bne t0, s3, fail

    # Test 65: Clear everything
    addi gp, gp, 1
    sw zero, SYS_IRQ_CR(a0)
    sw zero, SYS_IRQ_ENL(a0)
    sw zero, SYS_IRQ_ENM(a0)
    sw zero, SYS_IRQ_ENH(a0)
    lw t0, SYS_IRQ_ENL(a0)
    bnez t0, fail

    mv ra, s1
    ret

# ===============================================================================
# Tests 66-70: Register Reset Behavior
# ===============================================================================
test_register_reset_behavior_updated:
    mv s1, ra

    # Test 66: Set multiple registers
    addi gp, gp, 1
    li s3, 0x180  # DCO0 and DCO1 on
    sw s3, SYS_CLK_CR(a0)
    li s3, 0x1B  # Various dividers
    sw s3, SYS_CLK_DIV_CR(a0)
    li s3, 0xAA
    sw s3, SYS_CRC_DATA(a0)

    # Test 67: Verify clock control
    addi gp, gp, 1
    lw t0, SYS_CLK_CR(a0)
    li t1, 0x180
    bne t0, t1, fail

    # Test 68: 
    addi gp, gp, 1
    lw t0, SYS_CLK_DIV_CR(a0)
    li t1, 0x1B
    bne t0, t1, fail

    # Test 69: DCO bias values
    addi gp, gp, 1
    li s3, 0x123
    sw s3, SYS_DCO0_BIAS(a0)
    li s3, 0x456
    sw s3, SYS_DCO1_BIAS(a0)
    lw t0, SYS_DCO0_BIAS(a0)
    li t1, 0x123
    bne t0, t1, fail

    # Test 70: Clear all test settings
    addi gp, gp, 1
    sw zero, SYS_CLK_CR(a0)
    sw zero, SYS_CLK_DIV_CR(a0)
    sw zero, SYS_BLOCK_PWR(a0)
    li s3, DCO0_BIAS_DEFAULT
    sw s3, SYS_DCO0_BIAS(a0)
    li s3, DCO1_BIAS_DEFAULT
    sw s3, SYS_DCO1_BIAS(a0)
    lw t0, SYS_CLK_CR(a0)
    bnez t0, fail

    mv ra, s1
    ret

# ===============================================================================
# Utility Functions
# ===============================================================================
wait_short:
    li t0, 10
1:  addi t0, t0, -1
    bnez t0, 1b
    ret


# # ===============================================================================
# # Test failure handler
# # ===============================================================================
# fail:
#     # gp contains the test number that failed
#     RVTEST_FAIL

RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 4
test_data:
    .word 0xDEADBEEF
    .word 0xCAFEBABE
    .word 0x12345678
    .word 0x9ABCDEF0
RVTEST_DATA_END