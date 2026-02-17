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
#include "myshkin_s.h"


#define NPU_XVECT_ADDR      0x000 # Offset/4 from RAM2 BASE (0x10000)
#define NPU_WVECT_ADDR      0x800 # Offset/4 from RAM2 BASE (0x10800)
#define NPU_YVECT_ADDR      0x100 # Offset/4 from RAM2 BASE (0x10100)
#define NPU_YHAT_ADDR       0x2000 # Offset/4 from RAM2 BASE (0x10200)



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
li a0, PERIPH_NPU0_BASE
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
# Test 29: NPU Test Run - Exact VHDL Testbench Recreation
# ===============================================================================
test_run:
    mv s1, ra
    li a0, PERIPH_NPU0_BASE
    li a1, RAM1_BASE_ADDR

    # Constants matching VHDL testbench exactly
    li s4, 201        # layer_loop constant
    li s5, 0          # x_address variable (starts at 0)
    li s6, 256        # y_address variable (starts at 256)

    #=======================================================================
    # INITIALIZE MEMORY MAPPED REGISTER VALUES FOR FIRST LAYER
    #=======================================================================
    
    # NPU Control Register - First Layer Setup
    addi gp, gp, 1    # Test 29 counter
    
    # Write NPU Control Register: BEN=1, AEN=1, THINK=0, INPUTS=1(0+1), NEURONS=5(4+1)
    li t2, NPUBEN_MASK | NPUAEN_MASK | (0 << 8) | 4
    sw t2, NPU_CR(a0)
    
    # NPU Weight Vector Start Address Register - Layer 1 weights at 2048
    li t2, 2048       # Weight vector start address = 2048 (exactly matching VHDL)
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
    li t2, NPUBEN_MASK | NPUAEN_MASK | NPUTHINK_MASK | (0 << 8) | 4
    sw t2, NPU_CR(a0)
    
    # Wait for NPU THINK to complete (poll THINK bit until it goes low)
layer1_wait:
    lw t3, NPU_CR(a0)         # Read NPU Control Register
    li s9, NPUTHINK_MASK
    and t3, t3, s9    # Check THINK bit
    bnez t3, layer1_wait      # Loop while THINK=1
    
    # Update Address Variables (matching VHDL exactly)
    addi s5, s5, 1    # x_address := x_address + 1
    addi s6, s6, 5    # y_address := y_address + 5
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
    
    # NPU Weight Vector Start Address Register - Layer 2 weights at 2058
    li t2, 2058       # Weight vector start address = 2058 
    sw t2, NPU_WVSAR(a0)

    #=======================================================================
    # LOOP FOR SECOND LAYER (exactly matching VHDL LAYER_2_LOOP)
    #=======================================================================
    
    # Reset address variables for Layer 2 (matching VHDL exactly)
    li s5, 256        # x_address := 256 (exactly matching VHDL)
    li s6, 0          # y_address := 0 (exactly matching VHDL)
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
    li t2, NPUTHINK_MASK | (4 << 8) | 0
    sw t2, NPU_CR(a0)
    
    # Wait for NPU THINK to complete (poll THINK bit until it goes low)
layer2_wait:
    lw t3, NPU_CR(a0)         # Read NPU Control Register
    li s9, NPUTHINK_MASK
    and t3, t3, s9    # Check THINK bit
    bnez t3, layer2_wait      # Loop while THINK=1
    
    # Update Address Variables (matching VHDL exactly)
    addi s5, s5, 5    # x_address := x_address + 5
    addi s6, s6, 1    # y_address := y_address + 1
    addi s2, s2, 1    # increment loop counter

    # j fail
    j layer2_loop

layer2_done:
    #=======================================================================
    # NPU DONE! EXTRACT OUTPUT VALUES (VHDL GET_Y_LOOP)
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
    .word 0x01000000, 0x01028F5C, 0x01051EB8, 0x0107AE14, 0x010A3D71, 0x010CCCCD, 0x010F5C29, 0x0111EB85
    .word 0x01147AE1, 0x01170A3D, 0x0119999A, 0x011C28F6, 0x011EB852, 0x012147AE, 0x0123D70A, 0x01266666
    .word 0x0128F5C3, 0x012B851F, 0x012E147B, 0x0130A3D7, 0x01333333, 0x0135C28F, 0x013851EC, 0x013AE148
    .word 0x013D70A4, 0x01400000, 0x01428F5C, 0x01451EB8, 0x0147AE14, 0x014A3D71, 0x014CCCCD, 0x014F5C29
    .word 0x0151EB85, 0x01547AE1, 0x01570A3D, 0x0159999A, 0x015C28F6, 0x015EB852, 0x016147AE, 0x0163D70A
    .word 0x01666666, 0x0168F5C3, 0x016B851F, 0x016E147B, 0x0170A3D7, 0x01733333, 0x0175C28F, 0x017851EC
    .word 0x017AE148, 0x017D70A4, 0x01800000, 0x01828F5C, 0x01851EB8, 0x0187AE14, 0x018A3D71, 0x018CCCCD
    .word 0x018F5C29, 0x0191EB85, 0x01947AE1, 0x01970A3D, 0x0199999A, 0x019C28F6, 0x019EB852, 0x01A147AE
    .word 0x01A3D70A, 0x01A66666, 0x01A8F5C3, 0x01AB851F, 0x01AE147B, 0x01B0A3D7, 0x01B33333, 0x01B5C28F
    .word 0x01B851EC, 0x01BAE148, 0x01BD70A4, 0x01C00000, 0x01C28F5C, 0x01C51EB8, 0x01C7AE14, 0x01CA3D71
    .word 0x01CCCCCD, 0x01CF5C29, 0x01D1EB85, 0x01D47AE1, 0x01D70A3D, 0x01D9999A, 0x01DC28F6, 0x01DEB852
    .word 0x01E147AE, 0x01E3D70A, 0x01E66666, 0x01E8F5C3, 0x01EB851F, 0x01EE147B, 0x01F0A3D7, 0x01F33333
    .word 0x01F5C28F, 0x01F851EC, 0x01FAE148, 0x01FD70A4, 0x00000000, 0x00028F5C, 0x00051EB8, 0x0007AE14
    .word 0x000A3D71, 0x000CCCCD, 0x000F5C29, 0x0011EB85, 0x00147AE1, 0x00170A3D, 0x0019999A, 0x001C28F6
    .word 0x001EB852, 0x002147AE, 0x0023D70A, 0x00266666, 0x0028F5C3, 0x002B851F, 0x002E147B, 0x0030A3D7
    .word 0x00333333, 0x0035C28F, 0x003851EC, 0x003AE148, 0x003D70A4, 0x00400000, 0x00428F5C, 0x00451EB8
    .word 0x0047AE14, 0x004A3D71, 0x004CCCCD, 0x004F5C29, 0x0051EB85, 0x00547AE1, 0x00570A3D, 0x0059999A
    .word 0x005C28F6, 0x005EB852, 0x006147AE, 0x0063D70A, 0x00666666, 0x0068F5C3, 0x006B851F, 0x006E147B
    .word 0x0070A3D7, 0x00733333, 0x0075C28F, 0x007851EC, 0x007AE148, 0x007D70A4, 0x00800000, 0x00828F5C
    .word 0x00851EB8, 0x0087AE14, 0x008A3D71, 0x008CCCCD, 0x008F5C29, 0x0091EB85, 0x00947AE1, 0x00970A3D
    .word 0x0099999A, 0x009C28F6, 0x009EB852, 0x00A147AE, 0x00A3D70A, 0x00A66666, 0x00A8F5C3, 0x00AB851F
    .word 0x00AE147B, 0x00B0A3D7, 0x00B33333, 0x00B5C28F, 0x00B851EC, 0x00BAE148, 0x00BD70A4, 0x00C00000
    .word 0x00C28F5C, 0x00C51EB8, 0x00C7AE14, 0x00CA3D71, 0x00CCCCCD, 0x00CF5C29, 0x00D1EB85, 0x00D47AE1
    .word 0x00D70A3D, 0x00D9999A, 0x00DC28F6, 0x00DEB852, 0x00E147AE, 0x00E3D70A, 0x00E66666, 0x00E8F5C3
    .word 0x00EB851F, 0x00EE147B, 0x00F0A3D7, 0x00F33333, 0x00F5C28F, 0x00F851EC, 0x00FAE148, 0x00FD70A4
    .word 0x00FFFFFF


# NPU Test Weights
.section .npu0_w , "ax"
npu0_w:
# NPU Data Here
    .word 0xFE76A70A, 0xFE561906, 0xFFC25E27, 0x0004C163, 0xFBEE5EA8, 0xFC1ECEAD, 0xFEBD369D, 0x01657F72
    .word 0xFC0FAF23, 0x03CD76E9, 0x017790CB, 0x00F18BBD, 0x03D28D78, 0x014CFA13, 0x03FA77C4


# # NPU Expected Output Vector 
.section .npu0_yhat , "ax"
npu0_yhat:
# NPU Data Here
    .word 0x02FFFEAD, 0x02F5E2BF, 0x02EBDDC7, 0x02E1EFBB, 0x02D818A0, 0x02CE5877, 0x02C4AF43, 0x02BB1CFF
    .word 0x02B1A1E0, 0x02A84057, 0x029EF913, 0x0295CC15, 0x028CB95A, 0x0283C0E4, 0x027AE2AF, 0x02721EC9
    .word 0x0269751C, 0x0260E5BA, 0x02587099, 0x025015C6, 0x0247D531, 0x023FAEE2, 0x0237A2CE, 0x022FB10C
    .word 0x0227D98A, 0x02201C4D, 0x02187955, 0x0210F0A4, 0x02098231, 0x02022E0A, 0x01FAF426, 0x01F3D483
    .word 0x01ECCF28, 0x01E5E412, 0x01DF1341, 0x01D85CAF, 0x01D1C06B, 0x01CB3E66, 0x01C4D6A7, 0x01BE892B
    .word 0x01B855FA, 0x01B23D03, 0x01AC3E59, 0x01A659F2, 0x01A08FD1, 0x019ADFF5, 0x01954A57, 0x018FCF03
    .word 0x018A6DF6, 0x0185272B, 0x017FFAA8, 0x017AE864, 0x0175F066, 0x017112AF, 0x016C4F3D, 0x0167A610
    .word 0x01631724, 0x015EA282, 0x015A4823, 0x01560804, 0x0151E230, 0x014DD69D, 0x0149E550, 0x01460E46
    .word 0x01425184, 0x013EAF07, 0x013B26CC, 0x0137B8D7, 0x01346527, 0x01312BBF, 0x012E0C97, 0x012B07B4
    .word 0x01281D16, 0x01254CBC, 0x012296AB, 0x011FFADA, 0x011D7950, 0x011B120B, 0x0118C50B, 0x0116924C
    .word 0x011479D7, 0x01127BA5, 0x011097B6, 0x010ECE0F, 0x010D1EAC, 0x010B898B, 0x010A0EAF, 0x0108AE1C
    .word 0x010767C9, 0x01063BBB, 0x010529F8, 0x01043276, 0x01035537, 0x0102923B, 0x0101E986, 0x01015B16
    .word 0x0100E6EB, 0x01008D06, 0x01004D65, 0x0100255A, 0x01001666, 0x010021B1, 0x01004744, 0x0100871D
    .word 0x0100E133, 0x01015592, 0x0101E431, 0x01028D15, 0x01035042, 0x01042DAC, 0x0105255C, 0x01063755
    .word 0x0107638B, 0x0108AA07, 0x010A0ACA, 0x010B85CE, 0x010D1B17, 0x010ECAA0, 0x0110946F, 0x01127883
    .word 0x011476DB, 0x01168F76, 0x0118C258, 0x011B0F7D, 0x011D76E0, 0x011FF88A, 0x0122947C, 0x01254AAE
    .word 0x01281B24, 0x012B05E0, 0x012E0ADD, 0x01312A22, 0x013463A6, 0x0137B771, 0x013B257E, 0x013EADCD
    .word 0x01425067, 0x01460D41, 0x0149E45A, 0x014DD5BE, 0x0151E15F, 0x0156074C, 0x015A4779, 0x015EA1EA
    .word 0x0163169F, 0x0167A597, 0x016C4ED3, 0x01711254, 0x0175F01A, 0x017AE820, 0x017FFA6B, 0x018526FB
    .word 0x018A6DCE, 0x018FCEE7, 0x01954A41, 0x019ADFE3, 0x01A08FC7, 0x01A659EB, 0x01AC3E53, 0x01B23D02
    .word 0x01B855FA, 0x01BE892E, 0x01C4D6A7, 0x01CB3E67, 0x01D1C066, 0x01D85CAD, 0x01DF1338, 0x01E5E408
    .word 0x01ECCF18, 0x01F3D46F, 0x01FAF404, 0x02022DE2, 0x0209820A, 0x0210F06B, 0x02187912, 0x02201C00
    .word 0x0227D931, 0x022FB0A5, 0x0237A25C, 0x023FAE60, 0x0247D49B, 0x02501521, 0x02586FE5, 0x0260E4ED
    .word 0x02697441, 0x02721DD7, 0x027AE1AC, 0x0283BFC5, 0x028CB827, 0x0295CACC, 0x029EF7B3, 0x02A83E57
    .word 0x02B19D43, 0x02BB145D, 0x02C4A3A8, 0x02CE4B25, 0x02D80ACF, 0x02E1E2AC, 0x02EBD2B7, 0x02F5DAEF
    .word 0x02FFFB54