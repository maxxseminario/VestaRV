# See LICENSE for license details.

#*****************************************************************************
# divu.S
#-----------------------------------------------------------------------------
#
# Test divu instruction.
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  #-------------------------------------------------------------
  # Arithmetic tests
  #-------------------------------------------------------------

  TEST_RR_OP( 2, divu,                   3,  20,   6 );
  TEST_RR_OP( 3, divu,           715827879, -20,   6 );
  TEST_RR_OP( 4, divu,                   0,  20,  -6 );
  TEST_RR_OP( 5, divu,                   0, -20,  -6 );

  TEST_RR_OP( 6, divu, -1<<31, -1<<31,  1 );
  TEST_RR_OP( 7, divu,     0,  -1<<31, -1 );

  TEST_RR_OP( 8, divu, -1, -1<<31, 0 );
  TEST_RR_OP( 9, divu, -1,      1, 0 );
  TEST_RR_OP(10, divu, -1,      0, 0 );

  #-------------------------------------------------------------
  # Source/Destination tests
  #-------------------------------------------------------------

  TEST_RR_SRC1_EQ_DEST( 11, divu, 13, 143, 11 );
  TEST_RR_SRC2_EQ_DEST( 12, divu, 11, 154, 14 );
  TEST_RR_SRC12_EQ_DEST( 13, divu, 1, 169 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
