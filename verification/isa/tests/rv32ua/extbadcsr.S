# See LICENSE for license details.

# VestaRV: unknown-CSR poison, the negative control for the csr_valid base repair
# Before the repair csr_unit's read `others` arm returned zero with NO trap, so any unknown CSR silently read zero; after it, maindec decodes the CSR address and drops valid_funct for an unknown one, so the access takes the illegal-instruction trap.
# 0x5C0 is outside every documented and implemented range, so it is a genuinely unknown CSR. READING IT MUST TRAP ON EVERY BUILD, since this repair ships regardless of any generic, so the poison is run under the trap-watching harness in BOTH polarities. Surviving the read means the repair is broken and is a FAIL.

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
