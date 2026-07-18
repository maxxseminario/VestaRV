# See LICENSE for license details.

#*****************************************************************************
# remu.S
#-----------------------------------------------------------------------------
#
# Test remu instruction.
#

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  #-------------------------------------------------------------
  # Arithmetic tests
  #-------------------------------------------------------------

  TEST_RR_OP( 2, remu,   2,  20,   6 );
  TEST_RR_OP( 3, remu,   2, -20,   6 );
  TEST_RR_OP( 4, remu,  20,  20,  -6 );
  TEST_RR_OP( 5, remu, -20, -20,  -6 );

  TEST_RR_OP( 6, remu,      0, -1<<31,  1 );
  TEST_RR_OP( 7, remu, -1<<31, -1<<31, -1 );

  TEST_RR_OP( 8, remu, -1<<31, -1<<31, 0 );
  TEST_RR_OP( 9, remu,      1,      1, 0 );
  TEST_RR_OP(10, remu,      0,      0, 0 );

  #-------------------------------------------------------------
  # Source/Destination tests
  #-------------------------------------------------------------

  TEST_RR_SRC1_EQ_DEST( 11, remu, 5, 47, 6 );
  TEST_RR_SRC2_EQ_DEST( 12, remu, 3, 47, 11 );
  TEST_RR_SRC12_EQ_DEST( 13, remu, 0, 169 );

  TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

RVTEST_DATA_END
