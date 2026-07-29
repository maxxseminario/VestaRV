# See LICENSE for license details.

#*****************************************************************************
# amorsv.S   (RESERVED word-AMO funct5 — TRAP_STATE side-effect probe)
#-----------------------------------------------------------------------------
# A DIAGNOSTIC POISON, not a pass/fail suite test.  It executes a WORD-width
# AMO (funct3 = 010) with the RESERVED funct5 = 00110 and then, by design,
# never returns: on a legacy-delivery build that encoding is an illegal
# instruction and the core parks in the TERMINAL TRAP_STATE.
#
#   encoding 0x3005A02F
#     funct5 = 00110 (RESERVED — not one of the nine standard AMOs, not LR,
#                     not SC, not amocas)          aq = rl = 0
#     funct3 = 010 (word)   rs1 = a1   rs2 = x0   rd = x0   opcode = 0101111
#
# WHY: maindec's AMO valid_funct arm rejects reserved word funct5 codes
# (maindec.vhd, the X2 Zacas whitelist) but `amo_op` is decoded WITHOUT that
# whitelist (maindec.vhd:~496 — every funct5 except LR/SC), and the store-lane
# decode is `WEN <= "0000" when (op = AMO_OPCODE and (sc_op or amo_op))`.
# So this encoding sets trap = '1' AND all four ACTIVE-LOW write lanes at once.
# In LEGACY delivery the EXECUTE trap arm routes to TRAP_STATE without forcing
# `wen`, and TRAP_STATE itself only forces pc_en / reg_write_dp / trap_flag —
# leaving wen at wen_controller and data_addr at pc_next.  The maindec comment
# on that arm says it outright: "No existing test exercises the reserved word
# funct5 codes."  This file is the probe that does.
#
# RUN IT ONLY UNDER A BOUNDED TCL (or the behavioral_mp_stripped trap harness).
# It is wired into the Makefrag so it is BUILT, and it is deliberately NOT in
# the default behavioral_mp runner array — running it there would sit in
# TRAP_STATE until the 100 ms tb watchdog.
#
# Probe recipe (from xcelium/riscv_test/behavioral_mp):
#   cat > /tmp/amorsv.tcl <<'EOF'
#   source ../../disable_x_warnings.tcl
#   run 60us
#   puts "state = [value :dut:hart0:core:current_state]"
#   puts "wen   = [value :dut:hart0:wen_re]"
#   puts "addr  = [value :dut:hart0:data_addr]"
#   exit
#   EOF
#   XRUN_MODE=batch XRUN_EXTRA_INPUT=/tmp/amorsv.tcl ./xrun.sh xxxrv32ua-p-amorsv
#
# CONFIRMED IN SIMULATION (red-team agent, 2026-07-28, DEFAULT/OFF build,
# behavioral_mp):
#
#   RES STATE=TRAP_STATE
#   RES PC=000082BC        <- arsv_poison (objdump: 82bc  3005a02f)
#   RES ADDR=000082C0      <- arsv_target
#   RES RDATA=00000000     <- the image has 0x12345678 THERE (objdump)
#   RES INSTR=00000000
#   RES WEN="1111"
#
# The word at pc+4 was OVERWRITTEN WITH ZERO by an instruction that took the
# illegal-instruction trap.  The write is a SINGLE shot, not a loop, and only
# because it is self-limiting: TRAP_STATE does not hold instr_curr, so the
# decoder immediately re-decodes the word it just zeroed, 0x00000000 decodes
# to a non-store, and wen returns to "1111".  Had the written value decoded to
# a store/AMO the dead hart would keep writing every cycle.
#
# SCOPE (all three verified by RTL inspection):
#   * LEGACY delivery / OFF builds ONLY.  In STANDARD delivery the EXECUTE
#     trap arm forces `wen <= (others => '1')` (and mem_access_instr '0',
#     reg_write_dp '0') before routing to MTRAP_SV, and MTRAP_SV/MTRAP_JUMP do
#     the same — so P1/P2 standard mode, and therefore every U-mode path, is
#     immune.  This is NOT a P2 regression and NOT a U-mode escape.
#   * The address is pc+4 (data_addr falls through to pc_next when
#     mem_access_instr = '0'), so the blast radius is the hart's own
#     instruction stream — or, for code executing from the shared window,
#     the SHARED bus (sh_we_lanes is `not wen_re` gated on sh_sel alone,
#     hart_tile.vhd:~713 — no state qualifier).
#   * MATTERS FOR P3.  D5 requires that a denied access issue NO transaction.
#     This is the same class, already broken on the legacy path: a trapping
#     instruction leaking one write.  The two-line fix is to give the legacy
#     TRAP_STATE dispatch and the TRAP_STATE arm the same
#     `wen <= (others => '1'); mem_access_instr <= '0';` the standard arm
#     already has.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # base-ISA sanity: prove the core runs before the poison
    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, arsv_fail

    la   a1, arsv_word              # a well-defined AMO address (never used:
    li   a2, 0xA5A5A5A5             #   the access that DOES issue rides pc_next)

    .align 2
arsv_poison:
    .word 0x3005A02F                # reserved word AMO -> trap + all write lanes
arsv_target:
    .word 0x12345678                # the pc+4 word TRAP_STATE hammers
    .word 0x12345678
    .word 0x12345678
    .word 0x12345678

    # Unreachable on any build that traps the encoding.  If a future core
    # legalises it, fall into FAIL rather than run off the end.
    j    arsv_fail

arsv_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
arsv_word: .word 0
RVTEST_DATA_END
