# See LICENSE for license details.

# VestaRV: Zfinx off-polarity poison, fmadd.s
# It unconditionally executes fmadd.s a0,a1,a2,a3 (FMADD opcode 0x43), which MUST take the illegal-instruction trap when ENABLE_ZFINX is off. Zfinx sets no misa bit and every FP encoding is illegal on the base core, so this is the negative control for that gating. One of the four fused-multiply-add major opcodes.
# The encoding is emitted as a raw .word so it is PRESENT regardless of -march, and the file is run ONLY under the trap-watching harness (behavioral_mp_stripped/run_extoff.sh with trap_watch.tcl), never in the main suite, because it deliberately dead-ends in this core's TRAP_STATE. Surviving past the encoding means decode and gating disagree and is an explicit FAIL.

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # base-ISA sanity: prove the core runs before the illegal encoding
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, zffma_fail

    .word 0x68c5f543   # fmadd.s a0,a1,a2,a3 (FMADD opcode 0x43) -- MUST trap illegal when Zfinx off
    j    zffma_fail                # reached only if it did NOT trap -> FAIL

zffma_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
