# See LICENSE for license details.

# VestaRV: Zicond conditional-zero directed test
# Directed riscv-tests-style coverage for czero.eqz and czero.nez, authored here because no upstream source for this suite exists. It is compiled with a -march that includes zicond, which the installed toolchain accepts, so it uses the mnemonics directly. `czero.eqz rd,rs1,rs2` gives rd = (rs2 == 0) ? 0 : rs1, and `czero.nez` gives rd = (rs2 != 0) ? 0 : rs1.
# POLARITY: this suite executes real czero encodings, so it is meaningful ONLY against a Zicond-on RTL build. On a Zicond-off build every czero traps illegal-instruction and this trapless core hangs, SO DO NOT ADD THIS SUITE TO THE DEFAULT RUNNER. Both-polarity and trap coverage belongs to the adaptive probe rv32ua/extzicond.S.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  #-------------------------------------------------------------
  # czero.eqz : rd = (rs2 == 0) ? 0 : rs1
  #-------------------------------------------------------------
  TEST_RR_OP(  2, czero.eqz, 0x00000000, 0xABCD1234, 0x00000000 );  # rs2==0 -> 0
  TEST_RR_OP(  3, czero.eqz, 0xABCD1234, 0xABCD1234, 0x00000001 );  # rs2!=0 -> rs1
  TEST_RR_OP(  4, czero.eqz, 0xABCD1234, 0xABCD1234, 0xFFFFFFFF );  # rs2!=0 (sign) -> rs1
  TEST_RR_OP(  5, czero.eqz, 0xABCD1234, 0xABCD1234, 0x80000000 );  # rs2!=0 (msb) -> rs1
  TEST_RR_OP(  6, czero.eqz, 0x00000000, 0x00000000, 0x00000000 );  # rs1==0 -> 0
  TEST_RR_OP(  7, czero.eqz, 0x00000000, 0x00000000, 0x00000007 );  # rs1==0 -> 0

  #-------------------------------------------------------------
  # czero.nez : rd = (rs2 != 0) ? 0 : rs1
  #-------------------------------------------------------------
  TEST_RR_OP( 10, czero.nez, 0x00000000, 0xABCD1234, 0x00000001 );  # rs2!=0 -> 0
  TEST_RR_OP( 11, czero.nez, 0xABCD1234, 0xABCD1234, 0x00000000 );  # rs2==0 -> rs1
  TEST_RR_OP( 12, czero.nez, 0x00000000, 0xABCD1234, 0xFFFFFFFF );  # rs2!=0 (sign) -> 0
  TEST_RR_OP( 13, czero.nez, 0x00000000, 0xABCD1234, 0x80000000 );  # rs2!=0 (msb) -> 0
  TEST_RR_OP( 14, czero.nez, 0x00000000, 0x00000000, 0x00000000 );  # rs1==0 -> 0
  TEST_RR_OP( 15, czero.nez, 0xDEADBEEF, 0xDEADBEEF, 0x00000000 );  # rs2==0 -> rs1

  #-------------------------------------------------------------
  # Source/Destination aliasing
  #-------------------------------------------------------------
  # rd == rs1
  TEST_RR_SRC1_EQ_DEST( 20, czero.eqz, 0x00000000, 0xABCD1234, 0x00000000 ); # -> 0
  TEST_RR_SRC1_EQ_DEST( 21, czero.nez, 0xABCD1234, 0xABCD1234, 0x00000000 ); # -> rs1
  # rd == rs2
  TEST_RR_SRC2_EQ_DEST( 22, czero.eqz, 0x00000000, 0xABCD1234, 0x00000000 ); # rs2(=dest)==0 -> 0
  TEST_RR_SRC2_EQ_DEST( 23, czero.nez, 0x00000000, 0xABCD1234, 0x00000007 ); # rs2(=dest)!=0 -> 0
  # rd == rs1 == rs2
  TEST_RR_SRC12_EQ_DEST( 24, czero.eqz, 0x00000005, 0x00000005 ); # rs2==5!=0 -> rs1
  TEST_RR_SRC12_EQ_DEST( 25, czero.nez, 0x00000000, 0x00000005 ); # rs2==5!=0 -> 0

  #-------------------------------------------------------------
  # rd == x0 : write discarded, must not fault
  #-------------------------------------------------------------
  TEST_CASE( 30, x0, 0x00000000, \
    li x11, 0xABCD1234; \
    li x12, 0x00000000; \
    czero.eqz x0, x11, x12; \
  )

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
