# See LICENSE for license details.

#*****************************************************************************
# div.S
#-----------------------------------------------------------------------------
#
# Test div instruction.
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  #-------------------------------------------------------------
  # Arithmetic tests
  #-------------------------------------------------------------

  TEST_RR_OP( 2, div,  3,  20,   6 );
  TEST_RR_OP( 3, div, -3, -20,   6 );
  TEST_RR_OP( 4, div, -3,  20,  -6 );
  TEST_RR_OP( 5, div,  3, -20,  -6 );

  TEST_RR_OP( 6, div, -1<<31, -1<<31,  1 );
  TEST_RR_OP( 7, div, -1<<31, -1<<31, -1 );

  TEST_RR_OP( 8, div, -1, -1<<31, 0 );
  TEST_RR_OP( 9, div, -1,      1, 0 );
  TEST_RR_OP(10, div, -1,      0, 0 );

  #-------------------------------------------------------------
  # Source/Destination tests
  #-------------------------------------------------------------

  TEST_RR_SRC1_EQ_DEST( 11, div, 13, 143, 11 );
  TEST_RR_SRC2_EQ_DEST( 12, div, 11, 154, 14 );
  TEST_RR_SRC12_EQ_DEST( 13, div, 1, 169 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
