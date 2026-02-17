#*****************************************************************************
# NPU_TESTBENCH_ENHANCED.S
#-----------------------------------------------------------------------------
# Enhanced NPU (Neural Processing Unit) Peripheral testbench for RISC-V assembly (riscv32ui)
# Author: Maxx Seminario
# Date: 09-15-2025
#
# Test Categories:
# 1-4: Register Boundary Tests (4 tests)
# 5-8: NPUCR Control Register Tests (4 tests)
# 9-12: Address Register Tests (4 tests)
# 13-16: Register Field Tests (4 tests)
# 17-20: Bit Field Isolation Tests (4 tests)
# 21-24: Sequential Access Tests (4 tests)
# 25-28: Reset Behavior Tests (4 tests)
#-----------------------------------------------------------------------------

#include "riscv_test.h"
#include "test_macros.h"

# NPU Peripheral Base Address
#define NPU_BASE_ADDR      0x4A00
#define NPU_SRAM_BASE_ADDR 0x10000

#define NPU_XVECT_ADDR      0x000 # Offset/4 from RAM2 BASE (0x10000)
#define NPU_WVECT_ADDR      0x800 # Offset/4 from RAM2 BASE (0x10800)
#define NPU_YVECT_ADDR      0x100 # Offset/4 from RAM2 BASE (0x10100)
#define NPU_YHAT_ADDR       0x2000 # Offset/4 from RAM2 BASE (0x10200)
    

# NPU Register Offsets
#define NPU_CR             0x00
#define NPU_IVSAR          0x04
#define NPU_WVSAR          0x08
#define NPU_OVSAR          0x0C

# NPU Control Register Bit Definitions
#define NPU_BEN            0x40000
#define NPU_AEN            0x20000
#define NPU_THINK          0x10000
#define NPU_NI_MASK        0xFF00
#define NPU_NN_MASK        0x00FF

# Address Register Masks
#define ADDR_12BIT_MASK    0x0FFF

# Test Values
#define NPU_CR_TEST1       0x10101
#define NPU_CR_TEST2       0x20202
#define NPU_CR_TEST3       0x7FFFF
#define ADDR_TEST1         0x123
#define ADDR_TEST2         0x456
#define ADDR_TEST3         0x789
#define ADDR_TEST4         0xABC

RVTEST_RV32U
RVTEST_CODE_BEGIN

# Register usage convention
li a0, NPU_BASE_ADDR
li a1, 0  # Test counter

# ------------------------------------------------------------------------------
# Enhanced Test Suite
# ------------------------------------------------------------------------------
# jal ra, test_register_boundaries
# jal ra, test_npucr_control_register
# jal ra, test_address_registers
# jal ra, test_register_fields
# jal ra, test_bit_field_isolation
# jal ra, test_sequential_access
# jal ra, test_reset_behavior
jal ra, test_run

# Success
all_npu_tests_passed:
    TEST_PASSFAIL

# ===============================================================================
# Tests 1-4: Register Boundary Tests
# ===============================================================================
test_register_boundaries:
    mv s1, ra
    
    # Test 1: NPU_CR - 19-bit register
    addi gp, gp, 1
    li s3, NPU_CR_TEST3
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li t1, 0x7FFFF
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    # Test 2: NPU_IVSAR - 12-bit register
    addi gp, gp, 1
    li s3, 0xFFF
    sw s3, NPU_IVSAR(a0)
    lw t0, NPU_IVSAR(a0)
    li t1, ADDR_12BIT_MASK
    and t0, t0, t1
    bne t0, s3, fail

    # Test 3: NPU_WVSAR - 12-bit register
    addi gp, gp, 1
    li s3, 0xFFF
    sw s3, NPU_WVSAR(a0)
    lw t0, NPU_WVSAR(a0)
    li t1, ADDR_12BIT_MASK
    and t0, t0, t1
    bne t0, s3, fail

    # Test 4: NPU_OVSAR - 12-bit register
    addi gp, gp, 1
    li s3, 0xFFF
    sw s3, NPU_OVSAR(a0)
    lw t0, NPU_OVSAR(a0)
    li t1, ADDR_12BIT_MASK
    and t0, t0, t1
    bne t0, s3, fail

    # Clear all registers
    sw zero, NPU_CR(a0)
    sw zero, NPU_IVSAR(a0)
    sw zero, NPU_WVSAR(a0)
    sw zero, NPU_OVSAR(a0)

    mv ra, s1
    ret

# ===============================================================================
# Tests 5-8: NPUCR Control Register Tests
# ===============================================================================
test_npucr_control_register:
    mv s1, ra
    li a0, NPU_BASE_ADDR

    # Test 5: Basic control register write/read
    addi gp, gp, 1
    li s3, NPU_CR_TEST1
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li t1, 0x7FFFF
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    # Test 6: Different pattern
    addi gp, gp, 1
    li s3, NPU_CR_TEST2
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li t1, 0x7FFFF
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    # Test 7: NPUBEN bit test
    addi gp, gp, 1
    li s3, NPU_BEN
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    and t0, t0, s3
    beqz t0, fail

    # Test 8: NPUAEN bit test
    addi gp, gp, 1
    li s3, NPU_AEN
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    and t0, t0, s3
    beqz t0, fail

    sw zero, NPU_CR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 9-12: Address Register Tests
# ===============================================================================
test_address_registers:
    mv s1, ra
    li a0, NPU_BASE_ADDR

    # Test 9: NPU_IVSAR write/read
    addi gp, gp, 1
    li s3, ADDR_TEST1
    sw s3, NPU_IVSAR(a0)
    lw t0, NPU_IVSAR(a0)
    li t1, ADDR_12BIT_MASK
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    # Test 10: NPU_WVSAR write/read
    addi gp, gp, 1
    li s3, ADDR_TEST2
    sw s3, NPU_WVSAR(a0)
    lw t0, NPU_WVSAR(a0)
    li t1, ADDR_12BIT_MASK
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    # Test 11: NPU_OVSAR write/read
    addi gp, gp, 1
    li s3, ADDR_TEST3
    sw s3, NPU_OVSAR(a0)
    lw t0, NPU_OVSAR(a0)
    li t1, ADDR_12BIT_MASK
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    # Test 12: All address registers with same value
    addi gp, gp, 1
    li s3, ADDR_TEST4
    sw s3, NPU_IVSAR(a0)
    sw s3, NPU_WVSAR(a0)
    sw s3, NPU_OVSAR(a0)
    lw t0, NPU_IVSAR(a0)
    lw t1, NPU_WVSAR(a0)
    lw t2, NPU_OVSAR(a0)
    li t3, ADDR_12BIT_MASK
    and t0, t0, t3
    and t1, t1, t3
    and t2, t2, t3
    and s3, s3, t3
    bne t0, s3, fail
    bne t1, s3, fail
    bne t2, s3, fail

    # Clear address registers
    sw zero, NPU_IVSAR(a0)
    sw zero, NPU_WVSAR(a0)
    sw zero, NPU_OVSAR(a0)

    mv ra, s1
    ret

# ===============================================================================
# Tests 13-16: Register Field Tests
# ===============================================================================
test_register_fields:
    mv s1, ra
    li a0, NPU_BASE_ADDR

    # Test 13: NPUNI field (bits 15-8)
    addi gp, gp, 1
    li s3, 0x5500
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li s4, NPU_NI_MASK
    and t0, t0, s4
    bne t0, s3, fail

    # Test 14: NPUNN field (bits 7-0)
    addi gp, gp, 1
    li s3, 0x00AA
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li s4, NPU_NN_MASK
    and t0, t0, s4
    bne t0, s3, fail

    # Test 15: Combined NPUNI and NPUNN
    addi gp, gp, 1
    li s3, 0x1234
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li t1, 0xFFFF
    and t0, t0, t1
    bne t0, s3, fail

    # Test 16: All control bits with fields
    addi gp, gp, 1
    li s3, 0x71234
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    li t1, 0x7FFFF
    and t0, t0, t1
    and s3, s3, t1
    bne t0, s3, fail

    sw zero, NPU_CR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 17-20: Bit Field Isolation Tests
# ===============================================================================


test_bit_field_isolation:
    mv s1, ra
    li a0, NPU_BASE_ADDR

    # Test 21: Test NPUBEN bit isolation
    addi gp, gp, 1
    li s3, NPU_BEN
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail
    # Verify other bits are clear
    lw t0, NPU_CR(a0)
    li t1, NPU_AEN
    li t2, NPU_THINK
    or t1, t1, t2
    and t0, t0, t1
    bnez t0, fail

    # Test 22: Test NPUAEN bit isolation
    addi gp, gp, 1
    sw zero, NPU_CR(a0)
    li s3, NPU_AEN
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    # Test 23: Test NPUTHINK bit isolation
    addi gp, gp, 1
    sw zero, NPU_CR(a0)
    li s3, NPU_THINK
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    # Test 24: Test bit combinations
    addi gp, gp, 1
    li s3, NPU_BEN
    li t1, NPU_AEN
    or s3, s3, t1
    sw s3, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    and t0, t0, s3
    bne t0, s3, fail

    sw zero, NPU_CR(a0)
    mv ra, s1
    ret

# ===============================================================================
# Tests 21-24: Sequential Access Tests
# ===============================================================================
test_sequential_access:
    mv s1, ra
    li a0, NPU_BASE_ADDR

    # Test 25: Sequential write to all registers
    addi gp, gp, 1
    li s3, 0x11111
    sw s3, NPU_CR(a0)
    li s3, 0x222
    sw s3, NPU_IVSAR(a0)
    li s3, 0x333
    sw s3, NPU_WVSAR(a0)
    li s3, 0x444
    sw s3, NPU_OVSAR(a0)
    # Verify all values
    lw t0, NPU_CR(a0)
    li t1, 0x11111
    li t2, 0x7FFFF
    and t0, t0, t2
    bne t0, t1, fail

    # Test 26: Sequential read from all registers
    addi gp, gp, 1
    lw t0, NPU_IVSAR(a0)
    li t1, 0x222
    li s3 , ADDR_12BIT_MASK
    and t0, t0, s3
    bne t0, t1, fail
    lw t0, NPU_WVSAR(a0)
    li t1, 0x333
    and t0, t0, s3
    bne t0, t1, fail
    lw t0, NPU_OVSAR(a0)
    li t1, 0x444
    and t0, t0, s3
    bne t0, t1, fail

    # Test 27: Alternating access pattern
    addi gp, gp, 1
    li s3, 0x555
    sw s3, NPU_IVSAR(a0)
    lw t0, NPU_CR(a0)
    li s3, 0x666
    sw s3, NPU_WVSAR(a0)
    lw t0, NPU_IVSAR(a0)
    li t1, 0x555
    li s3, ADDR_12BIT_MASK
    and t0, t0, s3
    bne t0, t1, fail

    # Test 28: Rapid successive writes
    addi gp, gp, 1
    li s3, 0x777
    sw s3, NPU_OVSAR(a0)
    li s3, 0x888
    sw s3, NPU_OVSAR(a0)
    lw t0, NPU_OVSAR(a0)
    li t1, 0x888
    li s3, ADDR_12BIT_MASK
    and t0, t0, s3
    bne t0, t1, fail

    # Clear all registers
    sw zero, NPU_CR(a0)
    sw zero, NPU_IVSAR(a0)
    sw zero, NPU_WVSAR(a0)
    sw zero, NPU_OVSAR(a0)

    mv ra, s1
    ret

# ===============================================================================
# Tests 25-28: Reset Behavior Tests
# ===============================================================================
test_reset_behavior:
    mv s1, ra
    li a0, NPU_BASE_ADDR

    # Test 29: Verify registers start at zero
    addi gp, gp, 1
    lw t0, NPU_CR(a0)
    bnez t0, fail
    lw t0, NPU_IVSAR(a0)
    bnez t0, fail
    lw t0, NPU_WVSAR(a0)
    bnez t0, fail
    lw t0, NPU_OVSAR(a0)
    bnez t0, fail

    # Test 30: Set all registers to non-zero values
    addi gp, gp, 1
    li s3, 0x7FFFF
    sw s3, NPU_CR(a0)
    li s3, 0xFFF
    sw s3, NPU_IVSAR(a0)
    sw s3, NPU_WVSAR(a0)
    sw s3, NPU_OVSAR(a0)
    # Verify they are set
    lw t0, NPU_CR(a0)
    beqz t0, fail

    # Test 31: Individual register clear
    addi gp, gp, 1
    sw zero, NPU_CR(a0)
    lw t0, NPU_CR(a0)
    bnez t0, fail
    # Other registers should still have values
    lw t0, NPU_IVSAR(a0)
    beqz t0, fail

    # Test 32: Clear all remaining registers
    addi gp, gp, 1
    sw zero, NPU_IVSAR(a0)
    sw zero, NPU_WVSAR(a0)
    sw zero, NPU_OVSAR(a0)
    # Verify all are clear
    lw t0, NPU_IVSAR(a0)
    bnez t0, fail
    lw t0, NPU_WVSAR(a0)
    bnez t0, fail
    lw t0, NPU_OVSAR(a0)
    bnez t0, fail

    mv ra, s1
    ret

# ===============================================================================
# Test 29: NPU Test Run - Exact VHDL Testbench Recreation
# ===============================================================================
test_run:
    mv s1, ra
    li a0, NPU_BASE_ADDR
    li a1, NPU_SRAM_BASE_ADDR

    # Constants matching VHDL testbench
    li s4, 201                  # layer_loop constant
    li s5, NPU_XVECT_ADDR        # x_address variable 
    li s6, NPU_YVECT_ADDR        # y_address variable 

    #=======================================================================
    # INITIALIZE MEMORY MAPPED REGISTER VALUES FOR FIRST LAYER
    #=======================================================================
    
    # NPU Control Register - First Layer Setup
    addi gp, gp, 1    # Test 29 counter
    
    # Write NPU Control Register: BEN=1, AEN=1, THINK=0, INPUTS=1(0+1), NEURONS=5(4+1)
    li t2, NPU_BEN | NPU_AEN | (0 << 8) | 4
    sw t2, NPU_CR(a0)
    
    # NPU Weight Vector Start Address Register
    li t2, NPU_WVECT_ADDR       # Weight vector start address
    sw t2, NPU_WVSAR(a0)

    #=======================================================================
    # LOOP FOR FIRST LAYER (exactly matching VHDL LAYER_1_LOOP)
    #=======================================================================
    
    li s2, 1          # Loop counter i (starts at 1, goes to layer_loop)

layer1_loop:
    # Check if loop is complete
    bgt s2, s4, layer1_done
    
    # Set NPU Input Vector Start Address Register
    sw s5, NPU_IVSAR(a0)      # Write x_address
    
    # Set NPU Output Vector Start Address Register
    sw s6, NPU_OVSAR(a0)      # Write y_address
    
    # Set NPU THINK (trigger NPU operation)
    # Write: BEN=1, AEN=1, THINK=1, INPUTS=1(0+1), NEURONS=5(4+1)
    li t2, NPU_BEN | NPU_AEN | NPU_THINK | (0 << 8) | 4
    sw t2, NPU_CR(a0)
    
    # Wait for NPU THINK to complete (poll THINK bit until it goes low)
layer1_wait:
    lw t3, NPU_CR(a0)         # Read NPU Control Register
    li s0, NPU_THINK
    and t3, t3, s0    # Check THINK bit
    bnez t3, layer1_wait      # Loop while THINK=1
    
    # Update Address Variables (matching VHDL exactly)
    addi s5, s5, 1    # x_address := x_address + 1 TODO: define 
    addi s6, s6, 5    # y_address := y_address + 5 TODO: define (each input produces 5 outputs), layer 2 will later read these as inputs
    addi s2, s2, 1    # increment loop counter
    j layer1_loop

layer1_done:
    #=======================================================================
    # INITIALIZE MEMORY MAPPED REGISTER VALUES FOR SECOND LAYER
    #=======================================================================
    
    # NPU Control Register - Second Layer Setup
    # Write: BEN=0, AEN=0, THINK=0, INPUTS=5(4+1), NEURONS=1(0+1)
    li t2, (4 << 8) | 0
    sw t2, NPU_CR(a0)
    
    # NPU Weight Vector Start Address Register
    li t2, NPU_WVECT_ADDR       # Weight vector start address = 2058
    sw t2, NPU_WVSAR(a0)

    #=======================================================================
    # LOOP FOR SECOND LAYER (VHDL LAYER_2_LOOP)
    #=======================================================================
    
    # Reset address variables for Layer 2 (matching VHDL exactly)
    li s5, 256        # x_address := 256
    li s6, 0          # y_address := 0
    li s2, 1          # Reset loop counter i

layer2_loop:
    # Check if loop is complete
    bgt s2, s4, layer2_done
    
    # Set NPU Input Vector Start Address Register
    sw s5, NPU_IVSAR(a0)      # Write x_address
    
    # Set NPU Output Vector Start Address Register
    sw s6, NPU_OVSAR(a0)      # Write y_address
    
    # Set NPU THINK (trigger NPU operation)
    # Write: BEN=0, AEN=0, THINK=1, INPUTS=5(4+1), NEURONS=1(0+1)
    li t2, NPU_THINK | (4 << 8) | 0
    sw t2, NPU_CR(a0)
    
    # Wait for NPU THINK to complete (poll THINK bit until it goes low)
layer2_wait:
    lw t3, NPU_CR(a0)         # Read NPU Control Register
    li s0, NPU_THINK
    and t3, t3, s0    # Check THINK bit
    bnez t3, layer2_wait      # Loop while THINK=1
    
    # Update Address Variables (matching VHDL exactly)
    addi s5, s5, 5    # x_address := x_address + 5
    addi s6, s6, 1    # y_address := y_address + 1
    addi s2, s2, 1    # increment loop counter
    j layer2_loop

layer2_done:
    #=======================================================================
    # NPU NOW DONE!!! EXTRACT OUTPUT VALUES (matching VHDL GET_Y_LOOP)
    #=======================================================================
    
    li s2, 1          # Reset loop counter i
    li s3, 0          # ram_address := 0
    la s7, npu0_yhat  # Load address of expected outputs

get_y_loop:
    # Check if loop is complete
    bgt s2, s4, verification_done
    
    # Calculate SRAM address for reading output (s3 * 4 bytes)
    slli t1, s3, 2    # t1 = ram_address * 4
    add t2, a1, t1    # t2 = SRAM_BASE + offset
    
    # Read actual output from SRAM
    lw t3, 0(t2)      # Load actual output
    
    # Calculate expected output address (s3 * 4 bytes from base)
    add t4, s7, t1    # t4 = npu0_yhat + offset
    lw t5, 0(t4)      # Load expected output
    
    # Compare actual vs expected (mask to Y_M_BITS + N_BITS = 19 bits)
    li t6, 0x7FFFF    # Mask for 19 bits (3 integer + 15 fractional + 1 sign)
    and t3, t3, t6    # Mask actual output
    and t5, t5, t6    # Mask expected output
    
    # Check if they match - if not, jump to fail
    bne t3, t5, test_fail
    
    # Update counters (matching VHDL exactly)
    addi s3, s3, 1    # ram_address := ram_address + 1
    addi s2, s2, 1    # increment loop counter
    j get_y_loop

verification_done:
    # Test passed - all outputs matched expected values
    mv ra, s1
    ret

test_fail:
    # Test failed - jump to global fail handler
    j fail

RVTEST_CODE_END



# NPU Test Input Vector
.section .npu0_x , "ax"
npu0_x:
# NPU Data Here
    .word 0xFFFF8000, 0xFFFF8148, 0xFFFF828F, 0xFFFF83D7, 0xFFFF851F, 0xFFFF8666, 0xFFFF87AE, 0xFFFF88F6
    .word 0xFFFF8A3D, 0xFFFF8B85, 0xFFFF8CCD, 0xFFFF8E14, 0xFFFF8F5C, 0xFFFF90A4, 0xFFFF91EC, 0xFFFF9333
    .word 0xFFFF947B, 0xFFFF95C3, 0xFFFF970A, 0xFFFF9852, 0xFFFF999A, 0xFFFF9AE1, 0xFFFF9C29, 0xFFFF9D71
    .word 0xFFFF9EB8, 0xFFFFA000, 0xFFFFA148, 0xFFFFA28F, 0xFFFFA3D7, 0xFFFFA51F, 0xFFFFA666, 0xFFFFA7AE
    .word 0xFFFFA8F6, 0xFFFFAA3D, 0xFFFFAB85, 0xFFFFACCD, 0xFFFFAE14, 0xFFFFAF5C, 0xFFFFB0A4, 0xFFFFB1EC
    .word 0xFFFFB333, 0xFFFFB47B, 0xFFFFB5C3, 0xFFFFB70A, 0xFFFFB852, 0xFFFFB99A, 0xFFFFBAE1, 0xFFFFBC29
    .word 0xFFFFBD71, 0xFFFFBEB8, 0xFFFFC000, 0xFFFFC148, 0xFFFFC28F, 0xFFFFC3D7, 0xFFFFC51F, 0xFFFFC666
    .word 0xFFFFC7AE, 0xFFFFC8F6, 0xFFFFCA3D, 0xFFFFCB85, 0xFFFFCCCD, 0xFFFFCE14, 0xFFFFCF5C, 0xFFFFD0A4
    .word 0xFFFFD1EC, 0xFFFFD333, 0xFFFFD47B, 0xFFFFD5C3, 0xFFFFD70A, 0xFFFFD852, 0xFFFFD99A, 0xFFFFDAE1
    .word 0xFFFFDC29, 0xFFFFDD71, 0xFFFFDEB8, 0xFFFFE000, 0xFFFFE148, 0xFFFFE28F, 0xFFFFE3D7, 0xFFFFE51F
    .word 0xFFFFE666, 0xFFFFE7AE, 0xFFFFE8F6, 0xFFFFEA3D, 0xFFFFEB85, 0xFFFFECCD, 0xFFFFEE14, 0xFFFFEF5C
    .word 0xFFFFF0A4, 0xFFFFF1EC, 0xFFFFF333, 0xFFFFF47B, 0xFFFFF5C3, 0xFFFFF70A, 0xFFFFF852, 0xFFFFF99A
    .word 0xFFFFFAE1, 0xFFFFFC29, 0xFFFFFD71, 0xFFFFFEB8, 0x00000000, 0x00000148, 0x0000028F, 0x000003D7
    .word 0x0000051F, 0x00000666, 0x000007AE, 0x000008F6, 0x00000A3D, 0x00000B85, 0x00000CCD, 0x00000E14
    .word 0x00000F5C, 0x000010A4, 0x000011EC, 0x00001333, 0x0000147B, 0x000015C3, 0x0000170A, 0x00001852
    .word 0x0000199A, 0x00001AE1, 0x00001C29, 0x00001D71, 0x00001EB8, 0x00002000, 0x00002148, 0x0000228F
    .word 0x000023D7, 0x0000251F, 0x00002666, 0x000027AE, 0x000028F6, 0x00002A3D, 0x00002B85, 0x00002CCD
    .word 0x00002E14, 0x00002F5C, 0x000030A4, 0x000031EC, 0x00003333, 0x0000347B, 0x000035C3, 0x0000370A
    .word 0x00003852, 0x0000399A, 0x00003AE1, 0x00003C29, 0x00003D71, 0x00003EB8, 0x00004000, 0x00004148
    .word 0x0000428F, 0x000043D7, 0x0000451F, 0x00004666, 0x000047AE, 0x000048F6, 0x00004A3D, 0x00004B85
    .word 0x00004CCD, 0x00004E14, 0x00004F5C, 0x000050A4, 0x000051EC, 0x00005333, 0x0000547B, 0x000055C3
    .word 0x0000570A, 0x00005852, 0x0000599A, 0x00005AE1, 0x00005C29, 0x00005D71, 0x00005EB8, 0x00006000
    .word 0x00006148, 0x0000628F, 0x000063D7, 0x0000651F, 0x00006666, 0x000067AE, 0x000068F6, 0x00006A3D
    .word 0x00006B85, 0x00006CCD, 0x00006E14, 0x00006F5C, 0x000070A4, 0x000071EC, 0x00007333, 0x0000747B
    .word 0x000075C3, 0x0000770A, 0x00007852, 0x0000799A, 0x00007AE1, 0x00007C29, 0x00007D71, 0x00007EB8
    .word 0x00007FFF


# NPU Test Weights
.section .npu0_w , "ax"
npu0_w:
# NPU Data Here
    .word 0xFFFF3B54, 0xFFFF2B0D, 0xFFFFE12F, 0x00000261, 0xFFFDF72F, 0xFFFE0F67, 0xFFFF5E9B, 0x0000B2C0
    .word 0xFFFE07D8, 0x0001E6BB, 0x0000BBC8, 0x000078C6, 0x0001E947, 0x0000A67D, 0x0001FD3C


# NPU Expected Output Vector 
.section .npu0_yhat , "ax"
npu0_yhat:
# NPU Data Here
    .word 0x00018005, 0x00017AF5, 0x000175F7, 0x00017101, 0x00016C10, 0x00016730, 0x00016259, 0x00015D91
    .word 0x000158D5, 0x00015428, 0x00014F7E, 0x00014AEB, 0x00014661, 0x000141E1, 0x00013D73, 0x00013915
    .word 0x000134C2, 0x00013076, 0x00012C39, 0x00012810, 0x000123ED, 0x00011FDD, 0x00011BD5, 0x000117DD
    .word 0x000113F4, 0x00011011, 0x00010C3D, 0x0001087C, 0x000104C5, 0x0001011D, 0x0000FD80, 0x0000F9EE
    .word 0x0000F668, 0x0000F2F7, 0x0000EF8A, 0x0000EC32, 0x0000E8E5, 0x0000E5A1, 0x0000E26C, 0x0000DF49
    .word 0x0000DC2F, 0x0000D921, 0x0000D622, 0x0000D32E, 0x0000D04C, 0x0000CD6E, 0x0000CAAB, 0x0000C7EA
    .word 0x0000C537, 0x0000C295, 0x0000BFFF, 0x0000BD79, 0x0000BAFC, 0x0000B88D, 0x0000B62B, 0x0000B3D6
    .word 0x0000B18C, 0x0000AF54, 0x0000AD28, 0x0000AB04, 0x0000A8F6, 0x0000A6ED, 0x0000A4F5, 0x0000A30A
    .word 0x0000A12C, 0x00009F5B, 0x00009D97, 0x00009BDD, 0x00009A33, 0x00009899, 0x00009706, 0x00009587
    .word 0x00009410, 0x000092A9, 0x0000914D, 0x00009002, 0x00008EBB, 0x00008D8C, 0x00008C65, 0x00008B4C
    .word 0x00008A3E, 0x00008941, 0x0000884D, 0x00008766, 0x00008690, 0x000085C8, 0x0000850B, 0x00008458
    .word 0x000083B3, 0x0000831F, 0x00008295, 0x0000821C, 0x000081AE, 0x0000814B, 0x000080F6, 0x000080AE
    .word 0x00008076, 0x00008046, 0x00008028, 0x00008013, 0x0000800D, 0x00008011, 0x00008025, 0x00008046
    .word 0x00008074, 0x000080AE, 0x000080F4, 0x00008148, 0x000081AA, 0x00008217, 0x00008293, 0x0000831E
    .word 0x000083B1, 0x00008457, 0x00008507, 0x000085C4, 0x0000868E, 0x00008767, 0x0000884F, 0x0000893D
    .word 0x00008A3F, 0x00008B48, 0x00008C62, 0x00008D89, 0x00008EBB, 0x00008FFE, 0x0000914C, 0x000092A7
    .word 0x00009412, 0x00009587, 0x0000970A, 0x00009896, 0x00009A32, 0x00009BDC, 0x00009D94, 0x00009F58
    .word 0x0000A12A, 0x0000A309, 0x0000A4F6, 0x0000A6EF, 0x0000A8F3, 0x0000AB08, 0x0000AD29, 0x0000AF51
    .word 0x0000B18E, 0x0000B3D2, 0x0000B629, 0x0000B88A, 0x0000BAFB, 0x0000BD77, 0x0000BFFD, 0x0000C297
    .word 0x0000C53B, 0x0000C7ED, 0x0000CAAB, 0x0000CD74, 0x0000D04A, 0x0000D32E, 0x0000D620, 0x0000D920
    .word 0x0000DC2E, 0x0000DF46, 0x0000E270, 0x0000E5A3, 0x0000E8E6, 0x0000EC31, 0x0000EF8D, 0x0000F2F5
    .word 0x0000F669, 0x0000F9EC, 0x0000FD7D, 0x00010117, 0x000104C6, 0x0001087F, 0x00010C3B, 0x00011012
    .word 0x000113F5, 0x000117DD, 0x00011BD3, 0x00011FDA, 0x000123ED, 0x0001280D, 0x00012C3C, 0x00013077
    .word 0x000134BE, 0x00013913, 0x00013D74, 0x000141E4, 0x00014661, 0x00014AED, 0x00014F7D, 0x00015422
    .word 0x000158D2, 0x00015D8F, 0x00016258, 0x00016729, 0x00016C0A, 0x000170F7, 0x000175EF, 0x00017AF0
    .word 0x00018000