# See LICENSE for license details.

#*****************************************************************************
# privmret.S   (P0 privprobe OFF-polarity poison, 2026-07-28)
#-----------------------------------------------------------------------------
# MRET -- SYSTEM imm12=0x302, funct3=000 -- machine trap return.
# Encoding 0x30200073 is an ILLEGAL INSTRUCTION today: the SYSTEM arm's
# PRIV_FN3 case is commented out in maindec.vhd, so every funct3=000
# SYSTEM encoding falls through to valid_funct <= '0'.
#
# P-series contract (p0_specs.md 2.1/5.2): with ENABLE_TRAPCSR off -- which is
# EVERY build today, the P0 scaffold hard-errors on a true -- this encoding must
# take the ILLEGAL-INSTRUCTION trap. The probe PINS that OFF polarity so P1
# cannot silently regress it while adding the standard trap architecture.
#
# Emitted as a raw .word so no assembler march question can change
# WHICH bits the core sees.
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
    bne  t2, t3, pvmret_fail

    .word 0x30200073                # MRET -- MUST trap illegal
    j    pvmret_fail                 # reached only if it did NOT trap -> FAIL

pvmret_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
