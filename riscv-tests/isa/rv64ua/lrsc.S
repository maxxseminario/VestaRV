# See LICENSE for license details.

#*****************************************************************************
# lrsr.S
#-----------------------------------------------------------------------------
#
# Test LR/SC instructions.
#

#include "riscv_test.h"
#include "test_macros.h"

# Added my Maxx Seminario - due to signature being overwritten by previous tests. (In this case mulhsu test)
RVTEST_RV64U
RVTEST_CODE_BEGIN

# manual_rst:
#   li   t0, 0x83d0
#   sw   zero, 0(t0)
#   mv   t0, zero


# get a unique core id
la a0, coreid
li a1, 1
# Added by Maxx Seminario 11/13/25 to init memory location for post synthesis simulation
li   a0, 0x83d0
sw   zero, 0(a0)
amoadd.w a2, a1, (a0)

# for now, only run this on core 0
1:li a3, 1
bgeu a2, a3, 1b

1: lw a1, (a0)
bltu a1, a3, 1b

# # Added by Maxx Seminario 10/21/25 to test atomic instructions with only single core implemented.
# mv a3, a2    # a3 = core_id (0 for single-core)
# # end


# make sure that sc without a reservation fails.
TEST_CASE( 2, a4, 1, \
  la a0, foo; \
  li a5, 0xdeadbeef; \
  sc.w a4, a5, (a0); \
)

# Added by Maxx Seminario 11/13/25
# Explicitly zero foo before test 3 
# This is in order to not cause issues post genus / innovus where memory
# contents may be non-zero.
la t0, foo
sw zero, 0(t0)

# make sure the failing sc did not commit into memory
TEST_CASE( 3, a4, 0, \
  lw a4, foo; \
)

#
# Disable test case 4 for now. It assumes a <1K reservation granule, when
# in reality any size granule is valid. After discussion in issue #315,
# decided to simply disable the test for now.
# (See https://github.com/riscv/riscv-tests/issues/315)
#
## make sure that sc with the wrong reservation fails.
## TODO is this actually mandatory behavior?
#TEST_CASE( 4, a4, 1, \
#  la a0, foo; \
#  la a1, fooTest3; \
#  lr.w a1, (a1); \
#  sc.w a4, a1, (a0); \
#)

#define LOG_ITERATIONS 10

# have each core add its coreid+1 to foo 1024 times
la a0, foo
li a1, 1<<LOG_ITERATIONS
addi a2, a2, 1
1: lr.w a4, (a0)
add a4, a4, a2
sc.w a4, a4, (a0)
bnez a4, 1b
addi a1, a1, -1
bnez a1, 1b

# wait for all cores to finish
la a0, barrier
li a1, 1
amoadd.w x0, a1, (a0)
1: lw a1, (a0)
blt a1, a3, 1b
fence

# Test 5 and 6 out by Maxx Seminario 10/21/25 to test atomic instructions with only single core implemented.


TEST_PASSFAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN

  TEST_DATA

coreid: .word 0
barrier: .word 0
foo: .word 0
.skip 1024
fooTest3: .word 0
RVTEST_DATA_END
