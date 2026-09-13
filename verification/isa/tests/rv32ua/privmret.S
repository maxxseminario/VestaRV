# See LICENSE for license details.

# VestaRV: MRET must trap with ENABLE_TRAPCSR off
# MRET (SYSTEM imm12 = 0x302, funct3 = 000, machine trap return) is encoding 0x30200073, which is an ILLEGAL INSTRUCTION on every build that leaves ENABLE_TRAPCSR off: maindec.vhd's SYSTEM arm has the PRIV_FN3 case commented out, so every funct3 = 000 SYSTEM encoding falls through to valid_funct = '0'. It is emitted as a raw .word, so no assembler -march question can change which bits the core sees.
# The probe PINS the OFF polarity, so that adding the standard trap architecture cannot silently regress it. RUN IT ONLY UNDER THE TRAP-WATCHING HARNESS (behavioral_mp_stripped/run_extoff.sh with trap_watch.tcl, where trap_flag means TRAP_OK), never in the default runner array, which would hang on the terminal TRAP_STATE. Surviving past the encoding means the gating is broken and is an explicit FAIL.
# When ENABLE_TRAPCSR graduates, convert this file to the extjvt.S shape, an #ifdef CORE_ENABLE_TRAPCSR positive arm with this poison in the #else, rather than deleting it: the OFF polarity stays a required gate.

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
