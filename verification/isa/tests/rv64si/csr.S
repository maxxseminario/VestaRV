#*****************************************************************************
# CSR_TESTBENCH.S
#-----------------------------------------------------------------------------
# CSR (Control and Status Register) testbench for RISC-V RV32IMC
# Tests performance counter CSR registers for read/write functionality
#
# CSR Register Map (from VHDL):
# - MCYCLE    (0xB00) - Machine cycle counter low   - 32 bits R/W
# - MCYCLEH   (0xB80) - Machine cycle counter high  - 32 bits R/W  
# - MINSTRET  (0xB02) - Machine instret counter low - 32 bits R/W
# - MINSTRETH (0xB82) - Machine instret counter high- 32 bits R/W
# - CYCLE     (0xC00) - User cycle counter low      - 32 bits R (shadow)
# - CYCLEH    (0xC80) - User cycle counter high     - 32 bits R (shadow)
# - INSTRET   (0xC02) - User instret counter low    - 32 bits R (shadow)
# - INSTRETH  (0xC82) - User instret counter high   - 32 bits R (shadow)
# - TIME      (0xC01) - User time counter low       - 32 bits R (returns 0)
# - TIMEH     (0xC81) - User time counter high      - 32 bits R (returns 0)
#
# Test Categories:
# 1. Machine Counter Register Tests (MCYCLE, MCYCLEH, MINSTRET, MINSTRETH)
# 2. User Shadow Register Tests (CYCLE, CYCLEH, INSTRET, INSTRETH)  
# 3. Time Register Tests (TIME, TIMEH)
# 4. CSR Operation Tests (CSRRW, CSRRS, CSRRC)
# 5. Counter Increment Tests
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"

# CSR Addresses
#define CSR_MCYCLE      0xB00
#define CSR_MCYCLEH     0xB80
#define CSR_MINSTRET    0xB02
#define CSR_MINSTRETH   0xB82
#define CSR_CYCLE       0xC00
#define CSR_CYCLEH      0xC80
#define CSR_INSTRET     0xC02
#define CSR_INSTRETH    0xC82
#define CSR_TIME        0xC01
#define CSR_TIMEH       0xC81

# Test patterns
#define PATTERN_AA      0xAAAAAAAA
#define PATTERN_55      0x55555555
#define PATTERN_FF      0xFFFFFFFF
#define PATTERN_00      0x00000000
#define PATTERN_1       0x12345678
#define PATTERN_2       0x9ABCDEF0
#define PATTERN_3       0xDEADBEEF
#define PATTERN_4       0xCAFEBABE

RVTEST_RV32U
RVTEST_CODE_BEGIN

# ===============================================================================
# Register Usage Convention
# ===============================================================================
# x3  (gp) - Test counter (preserved)
# x8  (s0) - Test pattern/value
# x9  (s1) - Expected value
# x18 (s2) - Test suite return address
# x19 (s3) - CSR address
# x20 (s4) - Read value from CSR
# x21 (s5) - Temporary test value
# x5-x7, x28-x31 (t0-t4) - Temporary registers
# ===============================================================================

csr_testbench_start:
    # Initialize test counter
    li  gp, 0

    # Run all test suites
    jal ra, test_machine_counters
    # jal ra, test_user_shadow_registers
    # jal ra, test_time_registers
    # jal ra, test_csr_operations
    jal ra, test_counter_increments

    # All tests passed
    TEST_PASSFAIL

# ===============================================================================
# 1. MACHINE COUNTER REGISTER TESTS (Tests 1-40)
# ===============================================================================
test_machine_counters:
    mv s2, ra

    # Test 1-4: MCYCLE basic read/write tests
    addi gp, gp, 1
    li s0, PATTERN_00
    csrrw s4, CSR_MCYCLE, s0
    csrr s4, CSR_MCYCLE
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_FF
    csrrw s4, CSR_MCYCLE, s0
    csrr s4, CSR_MCYCLE
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_AA
    csrrw s4, CSR_MCYCLE, s0
    csrr s4, CSR_MCYCLE
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_55
    csrrw s4, CSR_MCYCLE, s0
    csrr s4, CSR_MCYCLE
    bne s0, s4, fail

    # Test 5-8: MCYCLEH basic read/write tests
    addi gp, gp, 1
    li s0, PATTERN_1
    csrrw s4, CSR_MCYCLEH, s0
    csrr s4, CSR_MCYCLEH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_2
    csrrw s4, CSR_MCYCLEH, s0
    csrr s4, CSR_MCYCLEH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_3
    csrrw s4, CSR_MCYCLEH, s0
    csrr s4, CSR_MCYCLEH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_4
    csrrw s4, CSR_MCYCLEH, s0
    csrr s4, CSR_MCYCLEH
    bne s0, s4, fail

    # Test 9-16: Walking 1s test for MCYCLE (32 bits)
    li t0, 0
    li t1, 32

walk_1_mcycle:
    addi gp, gp, 1
    li s0, 1
    sll s0, s0, t0
    csrrw s4, CSR_MCYCLE, s0
    csrr s4, CSR_MCYCLE
    bne s0, s4, fail
    addi t0, t0, 4  # Test every 4th bit to keep test reasonable
    blt t0, t1, walk_1_mcycle

    # Test 17-24: Walking 0s test for MCYCLE
    li t0, 0
    li t1, 32

walk_0_mcycle:
    addi gp, gp, 1
    li s0, 1
    sll s0, s0, t0
    not s0, s0
    csrrw s4, CSR_MCYCLE, s0
    csrr s4, CSR_MCYCLE
    bne s0, s4, fail
    addi t0, t0, 4
    blt t0, t1, walk_0_mcycle

    # Test 25-28: MINSTRET basic read/write tests
    addi gp, gp, 1
    li s0, PATTERN_00
    csrrw s4, CSR_MINSTRET, s0
    csrr s4, CSR_MINSTRET
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_FF
    csrrw s4, CSR_MINSTRET, s0
    csrr s4, CSR_MINSTRET
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_1
    csrrw s4, CSR_MINSTRET, s0
    csrr s4, CSR_MINSTRET
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_2
    csrrw s4, CSR_MINSTRET, s0
    csrr s4, CSR_MINSTRET
    bne s0, s4, fail

    # Test 29-32: MINSTRETH basic read/write tests
    addi gp, gp, 1
    li s0, PATTERN_3
    csrrw s4, CSR_MINSTRETH, s0
    csrr s4, CSR_MINSTRETH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_4
    csrrw s4, CSR_MINSTRETH, s0
    csrr s4, CSR_MINSTRETH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_AA
    csrrw s4, CSR_MINSTRETH, s0
    csrr s4, CSR_MINSTRETH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_55
    csrrw s4, CSR_MINSTRETH, s0
    csrr s4, CSR_MINSTRETH
    bne s0, s4, fail

    mv ra, s2
    ret

# ===============================================================================
# 2. USER SHADOW REGISTER TESTS (Tests 33-44)
# ===============================================================================
test_user_shadow_registers:
    mv s2, ra

    # Set known values in machine registers first
    li s0, PATTERN_1
    csrrw x0, CSR_MCYCLE, s0
    li s0, PATTERN_2
    csrrw x0, CSR_MCYCLEH, s0
    li s0, PATTERN_3
    csrrw x0, CSR_MINSTRET, s0
    li s0, PATTERN_4
    csrrw x0, CSR_MINSTRETH, s0

    # Test 33: CYCLE should read same as MCYCLE
    addi gp, gp, 1
    csrr s4, CSR_CYCLE
    li s1, PATTERN_1
    bne s1, s4, fail

    # Test 34: CYCLEH should read same as MCYCLEH
    addi gp, gp, 1
    csrr s4, CSR_CYCLEH
    li s1, PATTERN_2
    bne s1, s4, fail

    # Test 35: INSTRET should read same as MINSTRET
    addi gp, gp, 1
    csrr s4, CSR_INSTRET
    li s1, PATTERN_3
    bne s1, s4, fail

    # Test 36: INSTRETH should read same as MINSTRETH
    addi gp, gp, 1
    csrr s4, CSR_INSTRETH
    li s1, PATTERN_4
    bne s1, s4, fail

    # Test 37-40: Change machine values and verify shadows follow
    addi gp, gp, 1
    li s0, PATTERN_AA
    csrrw x0, CSR_MCYCLE, s0
    csrr s4, CSR_CYCLE
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_55
    csrrw x0, CSR_MCYCLEH, s0
    csrr s4, CSR_CYCLEH
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_FF
    csrrw x0, CSR_MINSTRET, s0
    csrr s4, CSR_INSTRET
    bne s0, s4, fail

    addi gp, gp, 1
    li s0, PATTERN_00
    csrrw x0, CSR_MINSTRETH, s0
    csrr s4, CSR_INSTRETH
    bne s0, s4, fail

    mv ra, s2
    ret

# ===============================================================================
# 3. TIME REGISTER TESTS (Tests 41-42)
# ===============================================================================
test_time_registers:
    mv s2, ra

    # Test 41: TIME should return 0
    addi gp, gp, 1
    csrr s4, CSR_TIME
    li s1, 0
    bne s1, s4, fail

    # Test 42: TIMEH should return 0
    addi gp, gp, 1
    csrr s4, CSR_TIMEH
    li s1, 0
    bne s1, s4, fail

    mv ra, s2
    ret

# ===============================================================================
# 4. CSR OPERATION TESTS (Tests 43-50)
# ===============================================================================
test_csr_operations:
    mv s2, ra

    # Test 43: CSRRS (set bits) operation on MCYCLE
    addi gp, gp, 1
    li s0, 0xF0F0F0F0
    csrrw x0, CSR_MCYCLE, s0     # Set base value
    li s0, 0x0F0F0F0F
    csrrs s4, CSR_MCYCLE, s0     # Set additional bits
    li s1, 0xFFFFFFFF
    bne s1, s4, fail             # Should return old value before set

    # Test 44: Verify CSRRS result
    addi gp, gp, 1
    csrr s4, CSR_MCYCLE
    li s1, 0xFFFFFFFF
    bne s1, s4, fail

    # Test 45: CSRRC (clear bits) operation on MCYCLE
    addi gp, gp, 1
    li s0, 0xFFFFFFFF
    csrrw x0, CSR_MCYCLE, s0     # Set all bits
    li s0, 0xF0F0F0F0
    csrrc s4, CSR_MCYCLE, s0     # Clear some bits
    li s1, 0xFFFFFFFF
    bne s1, s4, fail             # Should return old value before clear

    # Test 46: Verify CSRRC result
    addi gp, gp, 1
    csrr s4, CSR_MCYCLE
    li s1, 0x0F0F0F0F
    bne s1, s4, fail

    # Test 47-50: Test CSR operations on MINSTRET
    addi gp, gp, 1
    li s0, PATTERN_AA
    csrrw s4, CSR_MINSTRET, s0
    csrr s5, CSR_MINSTRET
    bne s0, s5, fail

    addi gp, gp, 1
    li s0, 0x0000FFFF
    csrrs s4, CSR_MINSTRET, s0
    li s1, 0xAAAAFFFF
    csrr s5, CSR_MINSTRET
    bne s1, s5, fail

    addi gp, gp, 1
    li s0, 0x00FF00FF
    csrrc s4, CSR_MINSTRET, s0
    li s1, 0xAA00FF00
    csrr s5, CSR_MINSTRET
    bne s1, s5, fail

    addi gp, gp, 1
    # Test CSRRWI (immediate write)
    csrrwi s4, CSR_MINSTRET, 0x1F
    li s1, 0x0000001F
    csrr s5, CSR_MINSTRET
    bne s1, s5, fail

    mv ra, s2
    ret

# ===============================================================================
# 5. COUNTER INCREMENT TESTS (Tests 51-54)
# ===============================================================================
test_counter_increments:
    mv s2, ra

    # Test 51: MCYCLE should increment automatically
    addi gp, gp, 1
    csrr s0, CSR_MCYCLE          # Read initial value
    nop                          # Some instructions to let cycle count
    nop
    nop
    nop
    csrr s1, CSR_MCYCLE          # Read again
    bgeu s0, s1, fail            # New value should be greater

    # Test 52: Verify MCYCLE increments consistently
    addi gp, gp, 1
    csrr s0, CSR_MCYCLE
    li t0, 10                    # Execute 10 instructions
test_cycle_loop:
    nop
    addi t0, t0, -1
    bnez t0, test_cycle_loop
    csrr s1, CSR_MCYCLE
    bgeu s0, s1, fail            # Should have incremented

    # Test 53: Test that shadow register CYCLE follows MCYCLE
    addi gp, gp, 1
    csrr s0, CSR_MCYCLE
    csrr s1, CSR_CYCLE
    bne s0, s1, fail             # Should be equal

    # Test 54: Final verification - set known value and read back
    addi gp, gp, 1
    li s0, 0x12345678
    csrrw x0, CSR_MCYCLE, s0
    csrr s1, CSR_MCYCLE
    bne s0, s1, fail

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