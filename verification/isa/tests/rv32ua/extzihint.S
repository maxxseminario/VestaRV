# See LICENSE for license details.

#*****************************************************************************
# extzihint.S   (X1 Zihintpause + Zihintntl ext-probe)
#-----------------------------------------------------------------------------
# Single-hart nop-safety + forward-progress probe for the hint extensions.
#
# WHY THIS PROBE IS BOTH-POLARITY IDENTICAL (unlike the misa/CORE_ENABLE
# dispatch probes): the Zihint encodings are LEGAL in BOTH polarities and NEVER
# trap either way --
#   * PAUSE = `fence w,0` (0x0100000F) is a FENCE encoding: always a legal nop.
#     ENABLE_ZIHINT gates only its MULTI-HART arbiter-yield side-effect, which a
#     single hart cannot observe. So there is nothing for a single-hart probe to
#     branch on -- it asserts NOP-SAFETY + FORWARD PROGRESS in either build.
#   * ntl.p1/pall/s1/all = `add x0,x0,x2/x3/x4/x5` are pure ADD-to-x0 nops today
#     through the base ALU path -- the probe asserts NO architectural effect.
# The observable ON/OFF side-effect (PAUSE de-asserts the arbiter request) is
# carried by the directed multi-hart test shpause.S, not here.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # ---- base-ISA sanity (runs on every build, like extprobe.S) ----
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, extzh_fail

    # =====================================================================
    # Zihintpause: PAUSE = fence w,0 = 0x0100000F
    # NEVER traps (FENCE encoding), both polarities. Assert the surrounding
    # architectural state is untouched and execution proceeds past each PAUSE.
    # =====================================================================
    li   a1, 0xA5A5A5A5              # sentinels that must survive the PAUSEs
    li   a2, 0x5A5A5A5A
    li   a3, 0                       # forward-progress marker (must reach 3)

    .word 0x0100000F                 # PAUSE
    addi a3, a3, 1                   # reached => PAUSE retired (PC advanced)
    .word 0x0100000F                 # PAUSE (back-to-back)
    addi a3, a3, 1
    .word 0x0100000F                 # PAUSE
    addi a3, a3, 1

    li   t4, 3
    bne  a3, t4, extzh_fail          # all three PAUSEs retired sequentially
    li   t4, 0xA5A5A5A5
    bne  a1, t4, extzh_fail          # PAUSE touched no register
    li   t4, 0x5A5A5A5A
    bne  a2, t4, extzh_fail

    # =====================================================================
    # Zihintntl: ntl.p1/pall/s1/all = add x0,x0,x2/x3/x4/x5
    # Pure nops (ADD result discarded to x0). Assert x0 stays 0, the rs2
    # source registers are untouched, and execution is sequential.
    # (rs2 must be x2/x3/x4/x5 -- that IS the hint encoding.)
    # =====================================================================
    li   x2, 0x11111111
    li   x3, 0x22222222
    li   x4, 0x33333333
    li   x5, 0x44444444

    add  x0, x0, x2                  # ntl.p1
    add  x0, x0, x3                  # ntl.pall
    add  x0, x0, x4                  # ntl.s1
    add  x0, x0, x5                  # ntl.all

    bnez x0, extzh_fail              # x0 must remain hardwired 0
    li   t4, 0x11111111
    bne  x2, t4, extzh_fail          # ntl left the source registers alone
    li   t4, 0x22222222
    bne  x3, t4, extzh_fail
    li   t4, 0x33333333
    bne  x4, t4, extzh_fail
    li   t4, 0x44444444
    bne  x5, t4, extzh_fail

    RVTEST_PASS                      # a0 = 0xCAFEBABE

extzh_fail:
    RVTEST_FAIL                      # a0 = 0xDEADBEEF

    # RVTEST_CODE_END is 'unimp' (traps) in this env -- never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
