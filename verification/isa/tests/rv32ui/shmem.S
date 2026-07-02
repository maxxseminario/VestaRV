# See LICENSE for license details.

#*****************************************************************************
# shmem.S  (M3c.3)
#-----------------------------------------------------------------------------
# Directed test for the MCU_MP shared-RAM window at 0x10000 (region 4), which is
# served through mp_arbiter on the free-running mclk. Every access to 0x10000
# exercises the core's mem_ready stall path: request -> (arbiter grant, 3-cycle
# transaction) -> data return -> release. Distinct from the private RAM path.
#
# Writes patterns to two shared-window words, reads them back, and checks value
# + isolation (writing one word must not disturb the other). PASS => a0=CAFEBABE.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 0x10000            # shared-window base (region 4 -> mp_arbiter)

    # ---- write two distinct words, read each back ----
    li   t1, 0x12345678
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t1, t2, shmem_fail     # word0 readback mismatch

    li   t3, 0xABCDEF01
    sw   t3, 4(t0)
    lw   t4, 4(t0)
    bne  t3, t4, shmem_fail     # word1 readback mismatch

    # ---- isolation: word0 must be untouched by the word1 write ----
    lw   t2, 0(t0)
    li   t1, 0x12345678
    bne  t1, t2, shmem_fail

    # ---- overwrite word0, confirm the new value + word1 intact ----
    li   t1, 0xCA11AB1E
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t1, t2, shmem_fail
    li   t3, 0xABCDEF01
    lw   t4, 4(t0)
    bne  t3, t4, shmem_fail

    RVTEST_PASS                 # a0 = 0xCAFEBABE, spin at _pass_label

shmem_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — the pass/fail
    # spins above must come from RVTEST_PASS/RVTEST_FAIL, never fall-through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
