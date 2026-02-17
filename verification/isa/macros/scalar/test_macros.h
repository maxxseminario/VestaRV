// See LICENSE for license details.

#ifndef __TEST_MACROS_SCALAR_H
#define __TEST_MACROS_SCALAR_H


#-----------------------------------------------------------------------
# GPIO Testing Data 
# Added by Maxx Seminario, 07/14/2025
#-----------------------------------------------------------------------

#include "myshkin_s.h"

/* Mask for XLEN (32-bit) */
#define MASK_XLEN(val)   ((val) & 0xFFFFFFFF)




#-----------------------------------------------------------------------
# Helper macros
#-----------------------------------------------------------------------

#define MASK_XLEN(x) ((x) & ((1 << (__riscv_xlen - 1) << 1) - 1))

#define TEST_CASE( testnum, testreg, correctval, code... ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    code; \
    li  x7, MASK_XLEN(correctval); \
    bne testreg, x7, fail;

#define TEST_CASE_REGTN( testnum, testreg, correctval, code... ) \
test_ ## testnum: \
    code; \
    li  s5, MASK_XLEN(correctval); \
    bne testreg, s5, fail;

#define TEST_CASE_NTN(testreg, correctval, code... ) \
    code; \
    li  s5, MASK_XLEN(correctval); \
    bne testreg, s5, fail;

#define TEST_CASE_TESTREG_VALREG(testreg, correctval, code... ) \
  code; \
  mv s5, correctval; \
  bne testreg, s5, fail;

#define TEST_CASE_SSR_REGTN( testnum, testreg, correctval, code... ) \
test_SSR_ ## testnum: \
    code; \
    li  s5, MASK_XLEN(correctval); \
    bne testreg, s5, fail;

#define TEST_CASE_REG( testnum, testreg, correctval, code... ) \
    mv  TESTNUM, testnum; \
    code; \
    bne testreg, correctval, fail;

# We use a macro hack to simpify code generation for various numbers
# of bubble cycles.

#define TEST_INSERT_NOPS_0
#define TEST_INSERT_NOPS_1  nop; TEST_INSERT_NOPS_0
#define TEST_INSERT_NOPS_2  nop; TEST_INSERT_NOPS_1
#define TEST_INSERT_NOPS_3  nop; TEST_INSERT_NOPS_2
#define TEST_INSERT_NOPS_4  nop; TEST_INSERT_NOPS_3
#define TEST_INSERT_NOPS_5  nop; TEST_INSERT_NOPS_4
#define TEST_INSERT_NOPS_6  nop; TEST_INSERT_NOPS_5
#define TEST_INSERT_NOPS_7  nop; TEST_INSERT_NOPS_6
#define TEST_INSERT_NOPS_8  nop; TEST_INSERT_NOPS_7
#define TEST_INSERT_NOPS_9  nop; TEST_INSERT_NOPS_8
#define TEST_INSERT_NOPS_10 nop; TEST_INSERT_NOPS_9

#if __riscv_xlen == 64
#define LOAD_PTR ld
#define STORE_PTR sd
#else
#define LOAD_PTR lw
#define STORE_PTR sw
#endif








#-----------------------------------------------------------------------
# RV64UI MACROS
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# Tests for instructions with immediate operand
#-----------------------------------------------------------------------

#define SEXT_IMM(x) ((x) | (-(((x) >> 11) & 1) << 11))

#define TEST_IMM_OP( testnum, inst, result, val1, imm ) \
    TEST_CASE( testnum, x14, result, \
      li  x13, MASK_XLEN(val1); \
      inst x14, x13, SEXT_IMM(imm); \
    )

#define TEST_IMM_SRC1_EQ_DEST( testnum, inst, result, val1, imm ) \
    TEST_CASE( testnum, x11, result, \
      li  x11, MASK_XLEN(val1); \
      inst x11, x11, SEXT_IMM(imm); \
    )

#define TEST_IMM_DEST_BYPASS( testnum, nop_cycles, inst, result, val1, imm ) \
    TEST_CASE( testnum, x6, result, \
      li  x4, 0; \
1:    li  x1, MASK_XLEN(val1); \
      inst x14, x1, SEXT_IMM(imm); \
      TEST_INSERT_NOPS_ ## nop_cycles \
      addi  x6, x14, 0; \
      addi  x4, x4, 1; \
      li  x5, 2; \
      bne x4, x5, 1b \
    )

#define TEST_IMM_SRC1_BYPASS( testnum, nop_cycles, inst, result, val1, imm ) \
    TEST_CASE( testnum, x14, result, \
      li  x4, 0; \
1:    li  x1, MASK_XLEN(val1); \
      TEST_INSERT_NOPS_ ## nop_cycles \
      inst x14, x1, SEXT_IMM(imm); \
      addi  x4, x4, 1; \
      li  x5, 2; \
      bne x4, x5, 1b \
    )

#define TEST_IMM_ZEROSRC1( testnum, inst, result, imm ) \
    TEST_CASE( testnum, x1, result, \
      inst x1, x0, SEXT_IMM(imm); \
    )

#define TEST_IMM_ZERODEST( testnum, inst, val1, imm ) \
    TEST_CASE( testnum, x0, 0, \
      li  x1, MASK_XLEN(val1); \
      inst x0, x1, SEXT_IMM(imm); \
    )

#-----------------------------------------------------------------------
# Tests for an instruction with register operands
#-----------------------------------------------------------------------

#define TEST_R_OP( testnum, inst, result, val1 ) \
    TEST_CASE( testnum, x14, result, \
      li  x1, val1; \
      inst x14, x1; \
    )

#define TEST_R_SRC1_EQ_DEST( testnum, inst, result, val1 ) \
    TEST_CASE( testnum, x1, result, \
      li  x1, val1; \
      inst x1, x1; \
    )

#define TEST_R_DEST_BYPASS( testnum, nop_cycles, inst, result, val1 ) \
    TEST_CASE( testnum, x6, result, \
      li  x4, 0; \
1:    li  x1, val1; \
      inst x14, x1; \
      TEST_INSERT_NOPS_ ## nop_cycles \
      addi  x6, x14, 0; \
      addi  x4, x4, 1; \
      li  x5, 2; \
      bne x4, x5, 1b \
    )

#-----------------------------------------------------------------------
# Tests for an instruction with register-register operands
#-----------------------------------------------------------------------

#define TEST_RR_OP( testnum, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x14, result, \
      li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x14, x11, x12; \
    )

#define TEST_RR_SRC1_EQ_DEST( testnum, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x11, result, \
      li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x11, x11, x12; \
    )

#define TEST_RR_SRC2_EQ_DEST( testnum, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x12, result, \
      li  x11, MASK_XLEN(val1); \
      li  x12, MASK_XLEN(val2); \
      inst x12, x11, x12; \
    )

#define TEST_RR_SRC12_EQ_DEST( testnum, inst, result, val1 ) \
    TEST_CASE( testnum, x11, result, \
      li  x11, MASK_XLEN(val1); \
      inst x11, x11, x11; \
    )

#define TEST_RR_DEST_BYPASS( testnum, nop_cycles, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x6, result, \
      li  x4, 0; \
1:    li  x1, MASK_XLEN(val1); \
      li  x2, MASK_XLEN(val2); \
      inst x14, x1, x2; \
      TEST_INSERT_NOPS_ ## nop_cycles \
      addi  x6, x14, 0; \
      addi  x4, x4, 1; \
      li  x5, 2; \
      bne x4, x5, 1b \
    )

#define TEST_RR_SRC12_BYPASS( testnum, src1_nops, src2_nops, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x14, result, \
      li  x4, 0; \
1:    li  x1, MASK_XLEN(val1); \
      TEST_INSERT_NOPS_ ## src1_nops \
      li  x2, MASK_XLEN(val2); \
      TEST_INSERT_NOPS_ ## src2_nops \
      inst x14, x1, x2; \
      addi  x4, x4, 1; \
      li  x5, 2; \
      bne x4, x5, 1b \
    )

#define TEST_RR_SRC21_BYPASS( testnum, src1_nops, src2_nops, inst, result, val1, val2 ) \
    TEST_CASE( testnum, x14, result, \
      li  x4, 0; \
1:    li  x2, MASK_XLEN(val2); \
      TEST_INSERT_NOPS_ ## src1_nops \
      li  x1, MASK_XLEN(val1); \
      TEST_INSERT_NOPS_ ## src2_nops \
      inst x14, x1, x2; \
      addi  x4, x4, 1; \
      li  x5, 2; \
      bne x4, x5, 1b \
    )

#define TEST_RR_ZEROSRC1( testnum, inst, result, val ) \
    TEST_CASE( testnum, x2, result, \
      li x1, MASK_XLEN(val); \
      inst x2, x0, x1; \
    )

#define TEST_RR_ZEROSRC2( testnum, inst, result, val ) \
    TEST_CASE( testnum, x2, result, \
      li x1, MASK_XLEN(val); \
      inst x2, x1, x0; \
    )

#define TEST_RR_ZEROSRC12( testnum, inst, result ) \
    TEST_CASE( testnum, x1, result, \
      inst x1, x0, x0; \
    )

#define TEST_RR_ZERODEST( testnum, inst, val1, val2 ) \
    TEST_CASE( testnum, x0, 0, \
      li x1, MASK_XLEN(val1); \
      li x2, MASK_XLEN(val2); \
      inst x0, x1, x2; \
    )

#-----------------------------------------------------------------------
# Test memory instructions
#-----------------------------------------------------------------------

#define TEST_LD_OP( testnum, inst, result, offset, base ) \
    TEST_CASE( testnum, x14, result, \
      li  x15, result; /* Tell the exception handler the expected result. */ \
      la  x2, base; \
      inst x14, offset(x2); \
    )

#define TEST_ST_OP( testnum, load_inst, store_inst, result, offset, base ) \
    TEST_CASE( testnum, x14, result, \
      la  x2, base; \
      li  x1, result; \
      la  x15, 7f; /* Tell the exception handler how to skip this test. */ \
      store_inst x1, offset(x2); \
      load_inst x14, offset(x2); \
      j 8f; \
7:    \
      /* Set up the correct result for TEST_CASE(). */ \
      mv x14, x1; \
8:    \
    )

#define TEST_LD_DEST_BYPASS( testnum, nop_cycles, inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  la  x13, base; \
    inst x14, offset(x13); \
    TEST_INSERT_NOPS_ ## nop_cycles \
    addi  x6, x14, 0; \
    li  x7, result; \
    bne x6, x7, fail; \
    addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b; \

#define TEST_LD_SRC1_BYPASS( testnum, nop_cycles, inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  la  x13, base; \
    TEST_INSERT_NOPS_ ## nop_cycles \
    inst x14, offset(x13); \
    li  x7, result; \
    bne x14, x7, fail; \
    addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \

#define TEST_ST_SRC12_BYPASS( testnum, src1_nops, src2_nops, load_inst, store_inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  li  x13, result; \
    TEST_INSERT_NOPS_ ## src1_nops \
    la  x12, base; \
    TEST_INSERT_NOPS_ ## src2_nops \
    store_inst x13, offset(x12); \
    load_inst x14, offset(x12); \
    li  x7, result; \
    bne x14, x7, fail; \
    addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \

#define TEST_ST_SRC21_BYPASS( testnum, src1_nops, src2_nops, load_inst, store_inst, result, offset, base ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  la  x2, base; \
    TEST_INSERT_NOPS_ ## src1_nops \
    li  x1, result; \
    TEST_INSERT_NOPS_ ## src2_nops \
    store_inst x1, offset(x2); \
    load_inst x14, offset(x2); \
    li  x7, result; \
    bne x14, x7, fail; \
    addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \

#define TEST_LD_ST_BYPASS(testnum, load_inst, store_inst, result, offset, base) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    la  x2, base;        \
    li x1, result; \
    store_inst x1, offset(x2); \
    load_inst x14, offset(x2);  \
    store_inst x14, offset(x2); \
    load_inst x2, offset(x2);  \
    li  x7, result; \
    bne x2, x7, fail;  \
    la  x2, base;        \
    STORE_PTR x2,8(x2); \
    LOAD_PTR x4,8(x2); \
    store_inst x1, offset(x4); \
    bne x4, x2, fail;  \
    load_inst x14, offset(x4);  \
    bne x14, x7, fail;  \

#define TEST_ST_LD_BYPASS(testnum, load_inst, store_inst, result, offset, base) \
test_ ## testnum: \
    li  TESTNUM, testnum;            \
    la  x2, base;                    \
    li  x1, result;                  \
    store_inst x1, offset(x2);       \
    load_inst x14, offset(x2);       \
    li  x7, result;                  \
    bne x14, x7, fail;               \

#define TEST_BR2_OP_TAKEN(testnum, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x1, val1; \
    li  x2, val2; \
    inst x1, x2, 2f; \
    bne x0, TESTNUM, fail; \
1:  bne x0, TESTNUM, 3f; \
2:  inst x1, x2, 1b; \
    bne x0, TESTNUM, fail; \
3:

#define TEST_BR2_OP_NOTTAKEN( testnum, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x1, val1; \
    li  x2, val2; \
    inst x1, x2, 1f; \
    bne x0, TESTNUM, 2f; \
1:  bne x0, TESTNUM, fail; \
2:  inst x1, x2, 1b; \
3:

#define TEST_BR2_SRC12_BYPASS( testnum, src1_nops, src2_nops, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  li  x1, val1; \
    TEST_INSERT_NOPS_ ## src1_nops \
    li  x2, val2; \
    TEST_INSERT_NOPS_ ## src2_nops \
    inst x1, x2, fail; \
    addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \

#define TEST_BR2_SRC21_BYPASS( testnum, src1_nops, src2_nops, inst, val1, val2 ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  li  x2, val2; \
    TEST_INSERT_NOPS_ ## src1_nops \
    li  x1, val1; \
    TEST_INSERT_NOPS_ ## src2_nops \
    inst x1, x2, fail; \
    addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \

#-----------------------------------------------------------------------
# Test jump instructions
#-----------------------------------------------------------------------

#define TEST_JR_SRC1_BYPASS( testnum, nop_cycles, inst ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  la  x6, 2f; \
    TEST_INSERT_NOPS_ ## nop_cycles \
    inst x6; \
    bne x0, TESTNUM, fail; \
2:  addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \

#define TEST_JALR_SRC1_BYPASS( testnum, nop_cycles, inst ) \
test_ ## testnum: \
    li  TESTNUM, testnum; \
    li  x4, 0; \
1:  la  x6, 2f; \
    TEST_INSERT_NOPS_ ## nop_cycles \
    inst x13, x6, 0; \
    bne x0, TESTNUM, fail; \
2:  addi  x4, x4, 1; \
    li  x5, 2; \
    bne x4, x5, 1b \



#-----------------------------------------------------------------------
# Tests GPIO Peripheral (s)
# Added by Maxx Seminario, 07/14/2025
#-----------------------------------------------------------------------
/*
 * Test GPIO output functionality
 * Author: Maxx Seminario 07/14/2025
 * Arguments:
 *   testnum: Test case number
 *   gpio_base: Base address of GPIO peripheral
 *   pin_mask: Bitmask of pins to test (e.g., 0x01 for pin 0)
 *   value: Value to write (0 or 1 for single pin, pattern for multiple)
 */

 /* Tests Reading and Writing to a GPIO register*/
#define TEST_GPIO_REG_RW(testnum, gpio_base, reg_offset, write_value, correct_value) \
    TEST_CASE(testnum, x14, correct_value, \
        li  x4, gpio_base;                /* Load GPIO base address */ \
        li  x6, write_value;                    /* Value to write */ \
        sw  x6, reg_offset(x4);      /* Write to output register */ \
        lw  x8, reg_offset(x4);      /* Read back */ \
        mv x14, x8; \
    )

 /* Tests Reading from GPIO register*/
#define TEST_GPIO_REG_READ(testnum, gpio_base, reg_offset, correct_value) \
    TEST_CASE(testnum, x14, correct_value, \
      li t0, gpio_base; \
      lw t2, reg_offset(t0); \
      mv x14, t2; \
    )
  

 /* Tests Setting a GPIO output */
#define TEST_GPIO_OUT(testnum, gpio_base, dir_en, REN, func_reg_offset, write_value, correct_value) \
    TEST_CASE(testnum, x14, correct_value, \
        li  x4, gpio_base;                /* Load GPIO base address */ \
        li  s2, 0x0F;                \
        li  s3, 0xF0;                \
        and s2, s2, dir_en;         \
        and s3, s3, dir_en;         \
        li  s4, REN;            /* Load REN value */ \
        sw  s4, GPIO_REN_REG(x4);     /* Disable pull-up resistors */ \
        sw  s2, GPIO_DIR_REG(x4);     /* Set bits 3 downto 0 output, 7 downto 4 input */ \
        li  t1, write_value;          /* Value to write */ \
        sw  t1, func_reg_offset(x4);      /* write_value is written to output on 3 downto 0 */ \
        lw  a2, GPIO_INPUT_REG(x4);      /* Read in inputs */ \
        and a2, a2, s3;               /* Mask to isolate bits 7 downto 4 */ \
        srli a2, a2, 4;               /* Shift bits 7 downto 4 to bits 3 downto 0 */ \
        sw  s3, GPIO_DIR_REG(x4);     /* Set bits 3 downto 0 input, 7 downto 4 output */ \
        lw  a3, GPIO_INPUT_REG(x4);    /* Read in inputs */ \
        and a3, a3, s2;               /* Mask to isolate bits 3 downto 0 */ \
        slli a3, a3, 4;               /* Shift bits 3 downto 0 to bits 7 downto 4 */ \
        or a3, a3, a2;                    /* Combine inputs */ \
        mv x14, a3;                      /* Store result in x14 */ \
    )

/*
Macro for initializing a GPIO Port. 
Disables alt function, sets output level high, lets direction to out, disables pullup res
Author: Maxx Seminario 07/15/2025
*/
.macro INIT_GPIO base
  init_gpio:
  li t0, \base
  li t1, 0x00
  li t2, 0xFF
  sw t1, 36(t0)      /*PxSEL - offset 9 bytes  */ 
  sw t1,  4(t0)      /*PxOUT - offset 1 bytes  */ 
  sw t2, 20(t0)      /*PxDIR - offset 5 bytes  */      
  sw t1, 40(t0)      /*PxREN - offset 10 bytes  */
.endm


 /* Tests SPI Peripheral Register Read/Write 
  Assumes SPI0 and SPI1 are on different GPIO ports
  Assumptoins 
  a0 = SPI0 base address
  a1 = GPIO0 base address
  a2 = SPI1 base address
  a3 = GPIO1 base address
  a4 - test result 
  spi_tx_sb (bit 17)   = t1        # (SPITXSB_i)
  spi_rx_sb (bit 16)   = t2        # (SPIRXSB_i)
  spi_cpol (1)         = t3        # (SPICPOL_i)
  spi_cpha (0)         = t4        # (SPIC
  spi_msb  (6)         = t5        # (SPIMSB_i)
  spi_dl   (3:2)       = t6        # (SPIDL_i, 2 bits)

  s7 = ~tx_val = s_tx_val
  Starts SPI Transfer and checks status register immedietly upon transfer 

  TODO: Check for correct behaviour of interrupts
*/
// #define TEST_SPI_TX_SRX(testnum, tx_val, correct_value, s_tx_val) \
//     TEST_CASE_REG(testnum, a4, correct_value, \
//         not a6, zero;                   /* a6 = 0xFFFFFFFF */ \
//         sw a6, SPI_FLASH_SR(a0);       /* Clear SPI0 Flash Status Register */ \
//         sw a6, SPI_FLASH_SR(a2);       /* Clear SPI1 Flash Status Register */ \
//         ASSERT_SPI_CS(a1);         /* Assert CS for SPI0 */ \
//         not s_tx_val, tx_val;               /* s7 = ~tx_val */ \
//         sw s_tx_val, SPI_FLASH_TX(a2);      /* Slave should transmit inverse of tx_val to master*/ \
//         sw tx_val, SPI_FLASH_TX(a0);      /* Data Transfer */ \
//     spi0_wait_until_mtx_complete: \
//         lw s3, SPI_FLASH_SR(a0);          /* Wait for tx to complete: Read Status Register */ \
//         andi s3, s3, SPI_TCIF_MASK;                /* Check if tx is complete */ \
//         beqz s3, spi0_wait_until_mtx_complete; \
//         lw a4, SPI_FLASH_RX(a2);       /* Read RX Data */ \  
//         sw a6, SPI_FLASH_SR(a2); \
//     )
#define TEST_SPI_TX_SRX(testnum, correct_value) \
    TEST_CASE_REG(testnum, a4, correct_value, \
      lw a4, SPI_RX(a2);       /* Read RX Data */ \  
      sw a6, SPI_SR(a2); \
    )


/* Tests SPI Peripheral Register Read/Write 
  Assumes SPI0 and SPI1 are on different GPIO ports
  Assumptoins 
  a0 = SPI0 base address (MASTER)
  a1 = GPIO0 base address
  a2 = SPI1 base address (SLAVE)
  a3 = GPIO1 base address
  a4 - test result 
  spi_tx_sb (bit 17)   = t1        # (SPITXSB_i)
  spi_rx_sb (bit 16)   = t2        # (SPIRXSB_i)
  spi_cpol (1)         = t3        # (SPICPOL_i)
  spi_cpha (0)         = t4        # (SPIC
  spi_msb  (6)         = t5        # (SPIMSB_i)
  spi_dl   (3:2)       = t6        # (SPIDL_i, 2 bits)

  s7 = ~tx_val = s_tx_val
  Starts SPI Transfer and checks status register immedietly upon transfer 

  TODO: Check for correct behaviour of interrupts

  This test assumes master has alrady performed the transfer, data is now ready to be read
*/
#define TEST_SPI_MRX(testnum, correct_value) \
  TEST_CASE_REG(testnum, a4, correct_value, \
    lw a4, SPI_RX(a0);       /* Read RX Data */ \  
  )

/* Tests SPI Peripheral SR Is correct
  Assumes SPI0 and SPI1 are on different GPIO ports
  Assumptoins 
  a0 = SPI0 base address (MASTER)
  a1 = GPIO0 base address
  a2 = SPI1 base address (SLAVE)
  a3 = GPIO1 base address
  a4 - test result 
  spi_tx_sb (bit 17)   = t1        # (SPITXSB_i)
  spi_rx_sb (bit 16)   = t2        # (SPIRXSB_i)
  spi_cpol (1)         = t3        # (SPICPOL_i)
  spi_cpha (0)         = t4        # (SPIC
  spi_msb  (6)         = t5        # (SPIMSB_i)
  spi_dl   (3:2)       = t6        # (SPIDL_i, 2 bits)

  s7 = ~tx_val = s_tx_val
  Starts SPI Transfer and checks status register immedietly upon transfer 

  TODO: Check for correct behaviour of interrupts

  This test assumes master has alrady performed the transfer, data is now ready to be read
*/
#define TEST_SPI_MSR(testnum, correct_value) \
TEST_CASE_REGTN(testnum, a4, correct_value, \
    lw a4, SPI_FLASH_SR(a0);       /* Read RX Data */ \  
    CLR_SPI_SR(a0);                /* Clear SPI Flash Status Register */ \
)


/* Tests SPI Peripheral SR Is correct
  Assumes SPI0 and SPI1 are on different GPIO ports
  Assumptoins 
  a0 = SPI0 base address (MASTER)
  a1 = GPIO0 base address
  a2 = SPI1 base address (SLAVE)
  a3 = GPIO1 base address
  a4 - test result 
  spi_tx_sb (bit 17)   = t1        # (SPITXSB_i)
  spi_rx_sb (bit 16)   = t2        # (SPIRXSB_i)
  spi_cpol (1)         = t3        # (SPICPOL_i)
  spi_cpha (0)         = t4        # (SPIC
  spi_msb  (6)         = t5        # (SPIMSB_i)
  spi_dl   (3:2)       = t6        # (SPIDL_i, 2 bits)

  s7 = ~tx_val = s_tx_val
  Starts SPI Transfer and checks status register immedietly upon transfer 

  TODO: Check for correct behaviour of interrupts

  This test assumes master has alrady performed the transfer, data is now ready to be read
*/
#define TEST_SPI_SSR(testnum, correct_value) \
TEST_CASE_SSR_REGTN(testnum, a4, correct_value, \
    lw a4, SPI_FLASH_SR(a2);       /* Read RX Data */ \  
    CLR_SPI_SR(a2);                /* Clear SPI Flash Status Register */ \
)


#define CLR_SPI_SR(base_addr_reg) \
    not a6, zero; \
    sw a6, SPI_FLASH_SR(base_addr_reg); \

#define ASSERT_SPI_CS(base_addr_reg) \
    li s2, SPI_CS_FLASH_MASK; \
    sw s2, GPIO_OUT_CLR_REG(base_addr_reg); /* Assert CS */ \

#define DEASSERT_SPI_CS(base_addr_reg) \
    li s2, SPI_CS_FLASH_MASK; \
    sw s2, GPIO_OUT_SET_REG(base_addr_reg); /* Deassert CS */ \


// -----------------------------------------------------------------------
// UART Peripheral Macros
// Author: Maxx Seminario 08/13/2025
// -----------------------------------------------------------------------

// Assume Register containing base address of rx uart is in rx_base_address
#define UART_TXRX_Test( result, rx_base_address ) \
    TEST_CASE_TESTREG_VALREG( x14, result, \
      lw x14, UART_RX(rx_base_address); \
    )

#define UART_SR_Test( result, rx_base_address ) \
    TEST_CASE_TESTREG_VALREG( x14, result, \
      lw x14, UART_SR(rx_base_address); \
    )

#define UART_REGREAD_TEST(result, rx_base_address, regoffset ) \
    TEST_CASE_TESTREG_VALREG( x14, result, \
      lw x14, regoffset(rx_base_address); \
    )

    // Parity Error Test
#define UART_PERR_Test( result, rx_base_address ) \
    TEST_CASE_NTN( x14, result, \
      lw x14, UART_SR(rx_base_address); \
      andi x14, x14, UART_PEF_MASK; \
    )

    //Rx overflow Test
#define UART_OVF_Test( result, rx_base_address ) \
    TEST_CASE_NTN( x14, result, \
      lw x14, UART_SR(rx_base_address); \
      andi x14, x14, UART_OVF_MASK; \
    )

#-----------------------------------------------------------------------
# RV64UF MACROS
#-----------------------------------------------------------------------

#-----------------------------------------------------------------------
# Tests floating-point instructions
#-----------------------------------------------------------------------

#define qNaNh 0h:7e00
#define sNaNh 0h:7c01
#define qNaNf 0f:7fc00000
#define sNaNf 0f:7f800001
#define qNaN 0d:7ff8000000000000
#define sNaN 0d:7ff0000000000001

#define TEST_FP_OP_H_INTERNAL( testnum, flags, result, val1, val2, val3, code... ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  flh f10, 0(a0); \
  flh f11, 2(a0); \
  flh f12, 4(a0); \
  lh  a3, 6(a0); \
  code; \
  fsflags a1, x0; \
  li a2, flags; \
  bne a0, a3, fail; \
  bne a1, a2, fail; \
  .pushsection .data; \
  .align 1; \
  test_ ## testnum ## _data: \
  .float16 val1; \
  .float16 val2; \
  .float16 val3; \
  .result; \
  .popsection

#define TEST_FP_OP_S_INTERNAL( testnum, flags, result, val1, val2, val3, code... ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  flw f10, 0(a0); \
  flw f11, 4(a0); \
  flw f12, 8(a0); \
  lw  a3, 12(a0); \
  code; \
  fsflags a1, x0; \
  li a2, flags; \
  bne a0, a3, fail; \
  bne a1, a2, fail; \
  .pushsection .data; \
  .align 2; \
  test_ ## testnum ## _data: \
  .float val1; \
  .float val2; \
  .float val3; \
  .result; \
  .popsection

#define TEST_FP_OP_D_INTERNAL( testnum, flags, result, val1, val2, val3, code... ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  fld f10, 0(a0); \
  fld f11, 8(a0); \
  fld f12, 16(a0); \
  ld  a3, 24(a0); \
  code; \
  fsflags a1, x0; \
  li a2, flags; \
  bne a0, a3, fail; \
  bne a1, a2, fail; \
  .pushsection .data; \
  .align 3; \
  test_ ## testnum ## _data: \
  .double val1; \
  .double val2; \
  .double val3; \
  .result; \
  .popsection

// TODO: assign a separate mem location for the comparison address?
#define TEST_FP_OP_D32_INTERNAL( testnum, flags, result, val1, val2, val3, code... ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  fld f10, 0(a0); \
  fld f11, 8(a0); \
  fld f12, 16(a0); \
  lw  a3, 24(a0); \
  lw  t1, 28(a0); \
  code; \
  fsflags a1, x0; \
  li a2, flags; \
  bne a0, a3, fail; \
  bne t1, t2, fail; \
  bne a1, a2, fail; \
  .pushsection .data; \
  .align 3; \
  test_ ## testnum ## _data: \
  .double val1; \
  .double val2; \
  .double val3; \
  .result; \
  .popsection

#define TEST_FCVT_S_D32( testnum, result, val1 ) \
  TEST_FP_OP_D32_INTERNAL( testnum, 0, double result, val1, 0.0, 0.0, \
                    fcvt.s.d f13, f10; fcvt.d.s f13, f13; fsd f13, 0(a0); lw t2, 4(a0); lw a0, 0(a0))

#define TEST_FCVT_S_D( testnum, result, val1 ) \
  TEST_FP_OP_D_INTERNAL( testnum, 0, double result, val1, 0.0, 0.0, \
                    fcvt.s.d f13, f10; fcvt.d.s f13, f13; fmv.x.d a0, f13)

#define TEST_FCVT_D_S( testnum, result, val1 ) \
  TEST_FP_OP_S_INTERNAL( testnum, 0, float result, val1, 0.0, 0.0, \
                    fcvt.d.s f13, f10; fcvt.s.d f13, f13; fmv.x.s a0, f13)

#define TEST_FCVT_H_S( testnum, result, val1 ) \
  TEST_FP_OP_H_INTERNAL( testnum, 0, float16 result, val1, 0.0, 0.0, \
                    fcvt.s.h f13, f10; fcvt.h.s f13, f13; fmv.x.h a0, f13)

#define TEST_FCVT_H_D( testnum, result, val1 ) \
  TEST_FP_OP_H_INTERNAL( testnum, 0, float16 result, val1, 0.0, 0.0, \
                    fcvt.d.h f13, f10; fcvt.h.d f13, f13; fmv.x.h a0, f13)


#define TEST_FP_OP1_H( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_H_INTERNAL( testnum, flags, float16 result, val1, 0.0, 0.0, \
                    inst f13, f10; fmv.x.h a0, f13;)

#define TEST_FP_OP1_S( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_S_INTERNAL( testnum, flags, float result, val1, 0.0, 0.0, \
                    inst f13, f10; fmv.x.s a0, f13)

#define TEST_FP_OP1_D32( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_D32_INTERNAL( testnum, flags, double result, val1, 0.0, 0.0, \
                    inst f13, f10; fsd f13, 0(a0); lw t2, 4(a0); lw a0, 0(a0))
// ^: store computation result in address from a0, load high-word into t2

#define TEST_FP_OP1_D( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_D_INTERNAL( testnum, flags, double result, val1, 0.0, 0.0, \
                    inst f13, f10; fmv.x.d a0, f13)

#define TEST_FP_OP1_S_DWORD_RESULT( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_S_INTERNAL( testnum, flags, dword result, val1, 0.0, 0.0, \
                    inst f13, f10; fmv.x.s a0, f13)

#define TEST_FP_OP1_H_DWORD_RESULT( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_H_INTERNAL( testnum, flags, word result, val1, 0.0, 0.0, \
                    inst f13, f10; fmv.x.h a0, f13)

#define TEST_FP_OP1_D32_DWORD_RESULT( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_D32_INTERNAL( testnum, flags, dword result, val1, 0.0, 0.0, \
                    inst f13, f10; fsd f13, 0(a0); lw t2, 4(a0); lw a0, 0(a0))
// ^: store computation result in address from a0, load high-word into t2

#define TEST_FP_OP1_D_DWORD_RESULT( testnum, inst, flags, result, val1 ) \
  TEST_FP_OP_D_INTERNAL( testnum, flags, dword result, val1, 0.0, 0.0, \
                    inst f13, f10; fmv.x.d a0, f13)

#define TEST_FP_OP2_S( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_S_INTERNAL( testnum, flags, float result, val1, val2, 0.0, \
                    inst f13, f10, f11; fmv.x.s a0, f13)

#define TEST_FP_OP2_H( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_H_INTERNAL( testnum, flags, float16 result, val1, val2, 0.0, \
                    inst f13, f10, f11; fmv.x.h a0, f13)

#define TEST_FP_OP2_D32( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_D32_INTERNAL( testnum, flags, double result, val1, val2, 0.0, \
                    inst f13, f10, f11; fsd f13, 0(a0); lw t2, 4(a0); lw a0, 0(a0))
// ^: store computation result in address from a0, load high-word into t2

#define TEST_FP_OP2_D( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_D_INTERNAL( testnum, flags, double result, val1, val2, 0.0, \
                    inst f13, f10, f11; fmv.x.d a0, f13)

#define TEST_FP_OP3_S( testnum, inst, flags, result, val1, val2, val3 ) \
  TEST_FP_OP_S_INTERNAL( testnum, flags, float result, val1, val2, val3, \
                    inst f13, f10, f11, f12; fmv.x.s a0, f13)

#define TEST_FP_OP3_H( testnum, inst, flags, result, val1, val2, val3 ) \
  TEST_FP_OP_H_INTERNAL( testnum, flags, float16 result, val1, val2, val3, \
                    inst f13, f10, f11, f12; fmv.x.h a0, f13)

#define TEST_FP_OP3_D32( testnum, inst, flags, result, val1, val2, val3 ) \
  TEST_FP_OP_D32_INTERNAL( testnum, flags, double result, val1, val2, val3, \
                    inst f13, f10, f11, f12; fsd f13, 0(a0); lw t2, 4(a0); lw a0, 0(a0))
// ^: store computation result in address from a0, load high-word into t2

#define TEST_FP_OP3_D( testnum, inst, flags, result, val1, val2, val3 ) \
  TEST_FP_OP_D_INTERNAL( testnum, flags, double result, val1, val2, val3, \
                    inst f13, f10, f11, f12; fmv.x.d a0, f13)

#define TEST_FP_INT_OP_S( testnum, inst, flags, result, val1, rm ) \
  TEST_FP_OP_S_INTERNAL( testnum, flags, word result, val1, 0.0, 0.0, \
                    inst a0, f10, rm)

#define TEST_FP_INT_OP_H( testnum, inst, flags, result, val1, rm ) \
  TEST_FP_OP_H_INTERNAL( testnum, flags, word result, val1, 0.0, 0.0, \
                    inst a0, f10, rm)

#define TEST_FP_INT_OP_D32( testnum, inst, flags, result, val1, rm ) \
  TEST_FP_OP_D32_INTERNAL( testnum, flags, dword result, val1, 0.0, 0.0, \
                    inst a0, f10, f11; li t2, 0)

#define TEST_FP_INT_OP_D( testnum, inst, flags, result, val1, rm ) \
  TEST_FP_OP_D_INTERNAL( testnum, flags, dword result, val1, 0.0, 0.0, \
                    inst a0, f10, rm)

#define TEST_FP_CMP_OP_S( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_S_INTERNAL( testnum, flags, word result, val1, val2, 0.0, \
                    inst a0, f10, f11)

#define TEST_FP_CMP_OP_H( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_H_INTERNAL( testnum, flags, hword result, val1, val2, 0.0, \
                    inst a0, f10, f11)

#define TEST_FP_CMP_OP_D32( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_D32_INTERNAL( testnum, flags, dword result, val1, val2, 0.0, \
                    inst a0, f10, f11; li t2, 0)

#define TEST_FP_CMP_OP_D( testnum, inst, flags, result, val1, val2 ) \
  TEST_FP_OP_D_INTERNAL( testnum, flags, dword result, val1, val2, 0.0, \
                    inst a0, f10, f11)

#define TEST_FCLASS_S(testnum, correct, input) \
  TEST_CASE(testnum, a0, correct, li a0, input; fmv.s.x f10, a0; \
                    fclass.s a0, f10)

#define TEST_FCLASS_D32(testnum, correct, input) \
  TEST_CASE(testnum, a0, correct, \
            la a0, test_ ## testnum ## _data ;\
            fld f10, 0(a0); \
            fclass.d a0, f10) \
    .pushsection .data; \
    .align 3; \
    test_ ## testnum ## _data: \
    .dword input; \
    .popsection

#define TEST_FCLASS_D(testnum, correct, input) \
  TEST_CASE(testnum, a0, correct, li a0, input; fmv.d.x f10, a0; \
                    fclass.d a0, f10)

#define TEST_INT_FP_OP_S( testnum, inst, result, val1 ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  lw  a3, 0(a0); \
  li  a0, val1; \
  inst f10, a0; \
  fsflags x0; \
  fmv.x.s a0, f10; \
  bne a0, a3, fail; \
  .pushsection .data; \
  .align 2; \
  test_ ## testnum ## _data: \
  .float result; \
  .popsection

#define TEST_INT_FP_OP_H( testnum, inst, result, val1 ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  lh  a3, 0(a0); \
  li  a0, val1; \
  inst f10, a0; \
  fsflags x0; \
  fmv.x.h a0, f10; \
  bne a0, a3, fail; \
  .pushsection .data; \
  .align 1; \
  test_ ## testnum ## _data: \
  .float16 result; \
  .popsection

#define TEST_INT_FP_OP_D32( testnum, inst, result, val1 ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  lw  a3, 0(a0); \
  lw  a4, 4(a0); \
  li  a1, val1; \
  inst f10, a1; \
  \
  fsd f10, 0(a0); \
  lw a1, 4(a0); \
  lw a0, 0(a0); \
  \
  fsflags x0; \
  bne a0, a3, fail; \
  bne a1, a4, fail; \
  .pushsection .data; \
  .align 3; \
  test_ ## testnum ## _data: \
  .double result; \
  .popsection

#define TEST_INT_FP_OP_D( testnum, inst, result, val1 ) \
test_ ## testnum: \
  li  TESTNUM, testnum; \
  la  a0, test_ ## testnum ## _data ;\
  ld  a3, 0(a0); \
  li  a0, val1; \
  inst f10, a0; \
  fsflags x0; \
  fmv.x.d a0, f10; \
  bne a0, a3, fail; \
  .pushsection .data; \
  .align 3; \
  test_ ## testnum ## _data: \
  .double result; \
  .popsection

// We need some special handling here to allow 64-bit comparison in 32-bit arch
// TODO: find a better name and clean up when intended for general usage?
#define TEST_CASE_D32( testnum, testreg1, testreg2, correctval, code... ) \
test_ ## testnum: \
    code; \
    la  x15, test_ ## testnum ## _data ; \
    lw  x7, 0(x15); \
    lw  x15, 4(x15); \
    li  TESTNUM, testnum; \
    bne testreg1, x7, fail;\
    bne testreg2, x15, fail;\
    .pushsection .data; \
    .align 3; \
    test_ ## testnum ## _data: \
    .dword correctval; \
    .popsection

// ^ x14 is used in some other macros, to avoid issues we use x15 for upper word

#define MISALIGNED_LOAD_HANDLER \
  li t0, CAUSE_MISALIGNED_LOAD; \
  csrr t1, mcause; \
  bne t0, t1, fail; \
  \
  /* We got a misaligned exception. Pretend we handled it in software */ \
  /* by loading the correct result here. */ \
  mv  a4, a5; \
  \
  /* And skip this instruction */ \
  csrr t0, mepc; \
  addi t0, t0, 4; \
  csrw mepc, t0; \
  mret

#define MISALIGNED_STORE_HANDLER \
  li t0, CAUSE_MISALIGNED_STORE; \
  csrr t1, mcause; \
  bne t0, t1, fail; \
  \
  /* We got a misaligned exception. Skip this test. */ \
  csrw mepc, x15; \
  mret

#-----------------------------------------------------------------------
# Pass and fail code (assumes test num is in TESTNUM)
#-----------------------------------------------------------------------

#define TEST_PASSFAIL \
        bne x0, TESTNUM, pass; \
fail: \
        RVTEST_FAIL; \
pass: \
        RVTEST_PASS \


#-----------------------------------------------------------------------
# Test data section
#-----------------------------------------------------------------------

#define TEST_DATA

#endif
