#*****************************************************************************
# AFE_TESTBENCH.S
#-----------------------------------------------------------------------------
# AFE (Analog Front End) testbench for RISC-V RV32IM
# Tests all AFE registers for read/write functionality
#
# Register Map (from VHDL):
# - AFE_CR          (Control Register)        - 24 bits R/W
# - AFE_TPR         (Test Port Register)      - 20 bits R/W  
# - AFE_SR          (Status Register)         - 4 bits  R/W (write to clear)
# - AFE_ADC_VAL     (ADC Value)               - 12 bits R, Write triggers conversion
# - BIAS_CR         (Bias Control)            - 5 bits  R/W
# - BIAS_ADJ        (Bias Adjustment)         - 6 bits  R/W
# - BIAS_DBP/DBPC/DBNC/DBN                    - 14 bits R/W each
# - BIAS_TC_POT/LC_POT                        - 6 bits  R/W each
# - BIAS_TIA_G_POT                            - 16 bits R/W
# - BIAS_DSADC_VCM/REV_POT                    - 14 bits R/W each
# - BIAS_TC_DSADC/LC_DSADC/RIN_DSADC/RFB_DSADC - 6 bits R/W each
#
# Test Categories:
# 1. Basic Register R/W Tests
# 2. Bias Register Tests
# 3. ADC Control Tests
# 4. Status Register Tests
# 5. Test Port Register Tests
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"
#include "myshkin_s.h"

# AFE Register Offsets (assuming 4-byte aligned addresses)
#define AFE_CR_OFFSET           0x00
#define AFE_TPR_OFFSET          0x04
#define AFE_SR_OFFSET           0x08
#define AFE_ADC_VAL_OFFSET      0x0C
#define BIAS_CR_OFFSET          0x10
#define BIAS_ADJ_OFFSET         0x14
#define BIAS_DBP_OFFSET         0x18
#define BIAS_DBPC_OFFSET        0x1C
#define BIAS_DBNC_OFFSET        0x20
#define BIAS_DBN_OFFSET         0x24
#define BIAS_TC_POT_OFFSET      0x28
#define BIAS_LC_POT_OFFSET      0x2C
#define BIAS_TIA_G_POT_OFFSET   0x30
#define BIAS_DSADC_VCM_OFFSET   0x34
#define BIAS_REV_POT_OFFSET     0x38
#define BIAS_TC_DSADC_OFFSET    0x3C
#define BIAS_LC_DSADC_OFFSET    0x40
#define BIAS_RIN_DSADC_OFFSET   0x44
#define BIAS_RFB_DSADC_OFFSET   0x48

# Bit masks for register fields
#define AFE_CR_MASK             0x00FFFFFF  # 24 bits
#define AFE_TPR_MASK            0x000FFFFF  # 20 bits
#define AFE_SR_MASK             0x0000000F  # 4 bits
#define AFE_ADC_VAL_MASK        0x00000FFF  # 12 bits
#define BIAS_CR_MASK            0x0000001F  # 5 bits
#define BIAS_ADJ_MASK           0x0000003F  # 6 bits
#define BIAS_14BIT_MASK         0x00003FFF  # 14 bits
#define BIAS_6BIT_MASK          0x0000003F  # 6 bits
#define BIAS_TIA_G_MASK         0x0001FFFF  # 16 bits

# Reset values from VHDL
#define AFE_CR_RESET            0x00FFF717
#define BIAS_CR_RESET           0x0000000C  # "01100"
#define BIAS_TC_POT_RESET       0x00000010  # "010000"
#define BIAS_LC_POT_RESET       0x00000028  # "101000"
#define BIAS_TIA_G_POT_RESET    0x0000FFF8 # "1111111111111000" Note: This is not used but it should be reset to unity gain
#define BIAS_DSADC_VCM_RESET    0x00002000  # "10000000000000"
#define BIAS_REV_POT_RESET      0x00000F5C  # "00111101011100"
#define BIAS_ADJ_RESET          0x00000018  # "011000"
#define BIAS_TC_DSADC_RESET     0x00000030  # "110000"
#define BIAS_LC_DSADC_RESET     0x00000028  # "101000"
#define BIAS_RFB_DSADC_RESET    0x0000002F  # "101111"
#define BIAS_RIN_DSADC_RESET    0x00000023  # "100011"

# Test patterns
#define PATTERN_AA              0x000000AA
#define PATTERN_55              0x00000055
#define PATTERN_WALK_1          0x00000001
#define PATTERN_WALK_0          0xFFFFFFFE

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# Register Usage Convention
# ===============================================================================
# x10 (a0) - AFE base address (preserved)
# x3  (gp) - Test counter (preserved)
# x8  (s0) - Test pattern/value
# x9  (s1) - Expected value
# x18 (s2) - Test suite return address
# x19 (s3) - Mask for current register
# x20 (s4) - Read value from register
# x21 (s5) - Temporary test value
# x5-x7, x28-x31 (t0-t4) - Temporary registers
# ===============================================================================

afe_testbench_start:
    # Initialize base address and test counter
    li  a0, PERIPH_AFE0_BASE  # You'll need to define this in myshkin_s.h
    li  gp, 0

    # Initialize AFE peripheral
    jal ra, init_afe_peripheral #seth has changed these 

    # # Run all test suites
    jal ra, test_control_registers
    jal ra, test_bias_registers
    jal ra, test_test_port_register
    jal zero, pass

    # All tests passed
    TEST_PASSFAIL

# ===============================================================================
# AFE INITIALIZATION
# ===============================================================================
init_afe_peripheral:
    # Load AFE_CR reset value and verify
    li t0, AFE_CR_RESET
    sw t0, AFE_CR_OFFSET(a0)
    lw t1, AFE_CR_OFFSET(a0)
    li t2, AFE_CR_MASK
    and t1, t1, t2
    bne t0, t1, fail

    # Clear any pending status bits
    li t0, 0x0F
    sw t0, AFE_SR_OFFSET(a0)
    
    ret

# ===============================================================================
# 1. CONTROL REGISTER TESTS (Tests 1-10)
# ===============================================================================
test_control_registers:
    mv s2, ra

    # Test 1: AFE_CR write/read with 0x555555
    addi gp, gp, 1
    li s0, 0x00555555
    li s3, AFE_CR_MASK
    and s0, s0, s3
    sw s0, AFE_CR_OFFSET(a0)
    lw s4, AFE_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 2: AFE_CR write/read with 0xAAAAAA
    addi gp, gp, 1
    li s0, 0x00AAAAAA
    and s0, s0, s3
    sw s0, AFE_CR_OFFSET(a0)
    lw s4, AFE_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 3: AFE_CR walking 1s test
    addi gp, gp, 1
    li t0, 0
    li t1, 24  # 24 bits in AFE_CR

walk_1_afe_cr:
    li s0, 1
    sll s0, s0, t0
    and s0, s0, s3
    sw s0, AFE_CR_OFFSET(a0)
    lw s4, AFE_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail
    addi t0, t0, 1
    blt t0, t1, walk_1_afe_cr

    # Test 4: AFE_CR walking 0s test
    addi gp, gp, 1
    li t0, 0
    li t1, 24

walk_0_afe_cr:
    li s0, 1
    sll s0, s0, t0
    not s0, s0
    and s0, s0, s3
    sw s0, AFE_CR_OFFSET(a0)
    lw s4, AFE_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail
    addi t0, t0, 1
    blt t0, t1, walk_0_afe_cr

    # Test 5: AFE_CR specific bit fields
    addi gp, gp, 1
    # Test adc_ramp_num field (bits 23:12)
    li s0, 0x00AAA000
    and s0, s0, s3
    sw s0, AFE_CR_OFFSET(a0)
    lw s4, AFE_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    mv ra, s2
    ret

# ===============================================================================
# 2. BIAS REGISTER TESTS (Tests 11-50)
# ===============================================================================
test_bias_registers:
    mv s2, ra

    # Test 6-10: BIAS_CR register tests
    addi gp, gp, 1
    li s3, BIAS_CR_MASK
    
    # Pattern 0x15 (10101)
    li s0, 0x15
    and s0, s0, s3
    sw s0, BIAS_CR_OFFSET(a0)
    lw s4, BIAS_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Pattern 0x0A (01010)
    addi gp, gp, 1
    li s0, 0x0A
    and s0, s0, s3
    sw s0, BIAS_CR_OFFSET(a0)
    lw s4, BIAS_CR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 11-15: BIAS_ADJ register tests
    addi gp, gp, 1
    li s3, BIAS_ADJ_MASK
    
    # Pattern 0x2A (101010)
    li s0, 0x2A
    and s0, s0, s3
    sw s0, BIAS_ADJ_OFFSET(a0)
    lw s4, BIAS_ADJ_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Pattern 0x15 (010101)
    addi gp, gp, 1
    li s0, 0x15
    and s0, s0, s3
    sw s0, BIAS_ADJ_OFFSET(a0)
    lw s4, BIAS_ADJ_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 16-20: BIAS_DBP register tests (14-bit)
    addi gp, gp, 1
    li s3, BIAS_14BIT_MASK
    
    # Pattern 0x2AAA
    li s0, 0x2AAA
    and s0, s0, s3
    sw s0, BIAS_DBP_OFFSET(a0)
    lw s4, BIAS_DBP_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Pattern 0x1555
    addi gp, gp, 1
    li s0, 0x1555
    and s0, s0, s3
    sw s0, BIAS_DBP_OFFSET(a0)
    lw s4, BIAS_DBP_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 21-25: BIAS_DBPC register tests (14-bit)
    addi gp, gp, 1
    li s3, BIAS_14BIT_MASK
    
    # Pattern 0x3FFF (all 1s)
    li s0, 0x3FFF
    sw s0, BIAS_DBPC_OFFSET(a0)
    lw s4, BIAS_DBPC_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Pattern 0x0000 (all 0s)
    addi gp, gp, 1
    li s0, 0x0000
    sw s0, BIAS_DBPC_OFFSET(a0)
    lw s4, BIAS_DBPC_OFFSET(a0)
    bne s0, s4, fail

    # Test 26-30: BIAS_DBNC register tests (14-bit)
    addi gp, gp, 1
    li s3, BIAS_14BIT_MASK
    li s0, 0x1234
    sw s0, BIAS_DBNC_OFFSET(a0)
    lw s4, BIAS_DBNC_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 31-35: BIAS_DBN register tests (14-bit)
    addi gp, gp, 1
    li s3, BIAS_14BIT_MASK
    li s0, 0x0F0F
    sw s0, BIAS_DBN_OFFSET(a0)
    lw s4, BIAS_DBN_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 36-40: 6-bit bias registers
    # BIAS_TC_POT
    addi gp, gp, 1
    li s3, BIAS_6BIT_MASK
    li s0, 0x3F  # Max value
    sw s0, BIAS_TC_POT_OFFSET(a0)
    lw s4, BIAS_TC_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # BIAS_LC_POT
    addi gp, gp, 1
    li s0, 0x2A
    sw s0, BIAS_LC_POT_OFFSET(a0)
    lw s4, BIAS_LC_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # BIAS_TC_DSADC
    addi gp, gp, 1
    li s0, 0x15
    sw s0, BIAS_TC_DSADC_OFFSET(a0)
    lw s4, BIAS_TC_DSADC_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # BIAS_LC_DSADC
    addi gp, gp, 1
    li s0, 0x0A
    sw s0, BIAS_LC_DSADC_OFFSET(a0)
    lw s4, BIAS_LC_DSADC_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # BIAS_RIN_DSADC
    addi gp, gp, 1
    li s0, 0x35
    sw s0, BIAS_RIN_DSADC_OFFSET(a0)
    lw s4, BIAS_RIN_DSADC_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # BIAS_RFB_DSADC
    addi gp, gp, 1
    li s0, 0x1C
    sw s0, BIAS_RFB_DSADC_OFFSET(a0)
    lw s4, BIAS_RFB_DSADC_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 41-45: BIAS_TIA_G_POT (17-bit) - Updated comment
    addi gp, gp, 1
    li s3, BIAS_TIA_G_MASK  # Should be 0x1FFFF for 17 bits
    li s0, 0x1FFFF          # All 17 bits set
    sw s0, BIAS_TIA_G_POT_OFFSET(a0)
    lw s4, BIAS_TIA_G_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, 0x15555          # 17-bit alternating pattern (0x15555)
    sw s0, BIAS_TIA_G_POT_OFFSET(a0)
    lw s4, BIAS_TIA_G_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, 0x0AAAA          # 17-bit alternating pattern (0x0AAAA)
    sw s0, BIAS_TIA_G_POT_OFFSET(a0)
    lw s4, BIAS_TIA_G_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # New 17th bit with Seth's 1M ohm Rf option 
    # Test the 17th bit specifically
    addi gp, gp, 1
    li s0, 0x10000          # Only 17th bit set
    sw s0, BIAS_TIA_G_POT_OFFSET(a0)
    lw s4, BIAS_TIA_G_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test with 17th bit clear
    addi gp, gp, 1
    li s0, 0x0FFFF          # All bits except 17th set
    sw s0, BIAS_TIA_G_POT_OFFSET(a0)
    lw s4, BIAS_TIA_G_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 46-50: 14-bit DAC registers
    # BIAS_DSADC_VCM
    addi gp, gp, 1
    li s3, BIAS_14BIT_MASK
    li s0, 0x1FFF
    sw s0, BIAS_DSADC_VCM_OFFSET(a0)
    lw s4, BIAS_DSADC_VCM_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # BIAS_REV_POT
    addi gp, gp, 1
    li s0, 0x2AAA
    sw s0, BIAS_REV_POT_OFFSET(a0)
    lw s4, BIAS_REV_POT_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    mv ra, s2
    ret


# ===============================================================================
# 5. TEST PORT REGISTER TESTS (Tests 71-80)
# ===============================================================================
test_test_port_register:
    mv s2, ra

    # AFE_TPR controls digital test port outputs
    # 20 bits total: 4 x 5-bit selectors for dtp0-3
    
    # Test 71: Write all zeros
    addi gp, gp, 1
    li s0, 0x00000
    li s3, AFE_TPR_MASK
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 72: Write all ones (within mask)
    addi gp, gp, 1
    li s0, 0xFFFFF
    and s0, s0, s3
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 73: Set different selectors
    addi gp, gp, 1
    li s0, 0x08421  # dtp3=1, dtp2=2, dtp1=4, dtp0=8
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 74: Pattern 0x55555
    addi gp, gp, 1
    li s0, 0x55555
    and s0, s0, s3
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 75: Pattern 0xAAAAA
    addi gp, gp, 1
    li s0, 0xAAAAA
    and s0, s0, s3
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Test 76-80: Test individual selector fields
    # dtp0_sel only (bits 4:0)
    addi gp, gp, 1
    li s0, 0x0001F
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # dtp1_sel only (bits 9:5)
    addi gp, gp, 1
    li s0, 0x003E0
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # dtp2_sel only (bits 14:10)
    addi gp, gp, 1
    li s0, 0x07C00
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # dtp3_sel only (bits 19:15)
    addi gp, gp, 1
    li s0, 0xF8000
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    # Mixed pattern
    addi gp, gp, 1
    li s0, 0x6B5A4  # Random valid pattern
    sw s0, AFE_TPR_OFFSET(a0)
    lw s4, AFE_TPR_OFFSET(a0)
    and s4, s4, s3
    bne s0, s4, fail

    mv ra, s2
    ret

# # # ===============================================================================
# # # Test failed - store test number and halt
# # # ===============================================================================
# # fail:
# #     # gp contains the test number that failed
# #     RVTEST_FAIL

# # ===============================================================================
# # End of test
# # ===============================================================================
RVTEST_CODE_END

RVTEST_DATA_BEGIN
    .align 4
test_data:
    .word 0xDEADBEEF
    .word 0xCAFEBABE
    .word 0x12345678
    .word 0x9ABCDEF0
RVTEST_DATA_END