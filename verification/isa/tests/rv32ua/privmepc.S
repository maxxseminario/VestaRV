# See LICENSE for license details.

#*****************************************************************************
# privmepc.S   (P0 privprobe OFF-polarity poison, 2026-07-28)
#-----------------------------------------------------------------------------
# mepc (CSR 0x341, machine exception PC) is absent from maindec.vhd's csr_addr_valid
# whitelist, so ANY access to it is an UNKNOWN CSR -> illegal instruction
# (the X1 Deliverable-A base repair).
#
# P-series contract (p0_specs.md 2.1/5.2): with ENABLE_TRAPCSR off -- which is
# EVERY build today, the P0 scaffold hard-errors on a true -- this encoding must
# take the ILLEGAL-INSTRUCTION trap. The probe PINS that OFF polarity so P1
# cannot silently regress it while adding the standard trap architecture.
#
# Run ONLY under the trap-watching harness (behavioral_mp_stripped/run_extoff.sh
# + trap_watch.tcl, where trap_flag => TRAP_OK) -- never in the default
# behavioral_mp array, which would hang on the terminal TRAP_STATE. Surviving
# PAST the encoding => the gating is broken => explicit FAIL.
#
# P1 NOTE: when ENABLE_TRAPCSR graduates, convert this file to the extjvt.S
# shape (#ifdef CORE_ENABLE_TRAPCSR positive arm / #else this poison) rather
# than deleting it -- the OFF polarity stays a required gate.
#*****************************************************************************

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
    bne  t2, t3, pvmepc_fail

    # mepc (0x341): unknown CSR today -> the read MUST trap illegal
    .option push
    .option arch, +zicsr
    csrr t0, 0x341
    .option pop
    j    pvmepc_fail                 # reached only if it did NOT trap -> FAIL

pvmepc_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
