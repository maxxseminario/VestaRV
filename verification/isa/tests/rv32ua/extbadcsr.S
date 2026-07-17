# See LICENSE for license details.

#*****************************************************************************
# extbadcsr.S   (X1 Deliverable-A poison, 2026-07-17)
#-----------------------------------------------------------------------------
# UNCONDITIONAL negative control for the csr_valid base repair. Before the
# repair, csr_unit's read `others` arm returned zero with NO trap, so ANY
# unknown CSR silently read zero — the priv-spec gap. After the repair, maindec
# decodes the CSR address and drops valid_funct for an unknown one, so the
# access takes the illegal-instruction trap.
#
# 0x5C0 is outside every documented/implemented range (not mhartid/misa, not the
# counter or hpm ranges, not mcountinhibit/mcounteren) — a genuinely unknown
# CSR. Reading it MUST trap on EVERY build (this repair ships regardless of any
# generic), so this poison is run under the trap-watching harness in BOTH
# polarities. Surviving the read = the repair is broken = FAIL.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # base-ISA sanity so a broken image is distinguishable from a broken repair
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, badcsr_fail

    # Unknown CSR read — MUST take the illegal-instruction trap.
    .option push
    .option arch, +zicsr
    csrr t0, 0x5C0
    .option pop
    j    badcsr_fail            # reached only if the access did NOT trap

badcsr_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env — never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
