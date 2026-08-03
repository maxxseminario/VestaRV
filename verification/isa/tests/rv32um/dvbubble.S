# See LICENSE for license details.

#*****************************************************************************
# dvbubble.S
#-----------------------------------------------------------------------------
#
# DET-B: divide dispatch in the split-fetch bubble.
#
# K5 BLIND DETECTOR.  Authored at unfixed HEAD 5c91e35 by an agent that has
# never seen the fix (root-cause report sections 1-9 only; section 10, the fix
# design, was not read).  Every expected value below is the RISC-V ISA value,
# computed by an independent oracle -- not copied from any report.
#
# Self checking, and it does NOT stop at the first wrong row: each row ORs a
# bit into x31 (value failures) or x30 (structural/alignment failures), and the
# verdict is taken once at the end.  So a single run exercises and reports on
# every row, and the accumulators give per row attribution.
#

# WHAT IT COVERS.  The ALU's divide FSM arms off a RAW combinational
# decode of alu_control with no dispatch qualification.  In the shape-E
# split-fetch bubble -- the EXECUTE cycle of a 32-bit instruction that
# straddles a word boundary, in which instr_curr is HELD at the previous
# instruction -- the strobe therefore fires for a divide that already
# retired, latches THAT divide's sel_signed/sel_rem, and sticks in
# ALU_DIV_WAIT.  The next divide, at ANY distance, then computes a
# DIFFERENT OPCODE ON ITS OWN CORRECT OPERANDS.
#
# STRUCTURAL CONSTRUCTION, not tuned constants.  Each row starts with
# `.balign 4' OUTSIDE `.option norvc' (measured to be the only form that
# aligns here) and then differs ONLY by whole halfwords emitted as
# explicit `.2byte 0x0001' (c.nop).  Inside norvc every instruction is
# exactly 4 bytes, so each row's parity follows from its own text.  Every
# address relationship the mechanism needs is ALSO ASSERTED AT RUN TIME
# (x30), so a toolchain change cannot make this test silently stop
# covering -- it makes it fail.
#
# ROW INDEPENDENCE.  Only the instruction IMMEDIATELY after a divide can
# arm the bubble (instr_curr_prev holds that divide for exactly one
# EXECUTE cycle).  So every row whose last divide sits at mod4==2 is
# followed by a c.nop, which is compressed and therefore not a straddle.
# Each row additionally opens with a WORD ALIGNED canary divide that would
# absorb, and report, any stale arm leaking out of the row before it.

#include "riscv_test.h"
#include "test_macros.h"

RVTEST_RV32U
RVTEST_CODE_BEGIN

  #-------------------------------------------------------------
  # Accumulators.  x30 structural, x31 value.  a0 (x10) is NEVER
  # touched -- it carries the PASS/FAIL contract.
  #-------------------------------------------------------------
  li   x30, 0
  li   x31, 0

  #-------------------------------------------------------------
  # Operands.  Leader and victim use DIFFERENT operands, so a victim
  # computed under the leader's SELECTS is distinguishable from one
  # computed on the leader's OPERANDS.
  #-------------------------------------------------------------
  li   x9, 0xffffff9c
  li   x18, 0x00000007
  li   x11, 0xfffffc18
  li   x12, 0x0000000b

  #============================================================
  # ROW B0 -- CONTROL: opcode change + adjacency, word aligned
  #   leader divu(ffffff9c,00000007) ISA=24924916   MUST PASS ALWAYS
  #   victim rem (fffffc18,0000000b) ISA=fffffff6   MUST PASS ALWAYS
  #============================================================
  .balign 4
  .option push
  .option norvc
b0_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
b0_leader:
  divu x28, x9, x18
b0_victim:
  rem  x14, x11, x12
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 0
  or   x31, x31, x8
  li   x7, 0x24924916
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 1
  or   x31, x31, x8
  li   x7, 0xfffffff6
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 2
  or   x31, x31, x8

  #============================================================
  # ROW B1 -- DEFECT: victim rem runs under divu selects
  #   leader divu(ffffff9c,00000007) ISA=24924916   MUST PASS ALWAYS
  #   victim rem (fffffc18,0000000b) ISA=fffffff6   MUST FAIL TODAY (runs under divu selects -> 1745d119)
  #============================================================
  .balign 4
  .option push
  .option norvc
b1_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
  .2byte 0x0001                /* c.nop: everything below is at mod4==2 */
b1_leader:
  divu x28, x9, x18
b1_victim:
  rem  x14, x11, x12           /* 32-bit, at mod4==2: THE STRADDLE */
  .2byte 0x0001                /* realign; keeps the row self contained */
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 3
  or   x31, x31, x8
  li   x7, 0x24924916
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 4
  or   x31, x31, x8
  li   x7, 0xfffffff6
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 5
  or   x31, x31, x8

  #============================================================
  # ROW B2 -- DEFECT: reverse direction
  #   leader rem (ffffff9c,00000007) ISA=fffffffe   MUST PASS ALWAYS
  #   victim divu(fffffc18,0000000b) ISA=1745d119   MUST FAIL TODAY (runs under rem selects -> fffffff6)
  #============================================================
  .balign 4
  .option push
  .option norvc
b2_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
  .2byte 0x0001                /* c.nop: everything below is at mod4==2 */
b2_leader:
  rem  x28, x9, x18
b2_victim:
  divu x14, x11, x12           /* 32-bit, at mod4==2: THE STRADDLE */
  .2byte 0x0001                /* realign; keeps the row self contained */
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 6
  or   x31, x31, x8
  li   x7, 0xfffffffe
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 7
  or   x31, x31, x8
  li   x7, 0x1745d119
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 8
  or   x31, x31, x8

  #============================================================
  # ROW B3 -- DEFECT at distance: victim WORD-ALIGNED, 5 insns away
  #   leader divu(ffffff9c,00000007) ISA=24924916   MUST PASS ALWAYS
  #   victim rem (fffffc18,0000000b) ISA=fffffff6   MUST FAIL TODAY (runs under divu selects -> 1745d119)
  #============================================================
  .balign 4
  .option push
  .option norvc
b3_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
  .2byte 0x0001                /* c.nop: everything below is at mod4==2 */
b3_leader:
  divu x28, x9, x18
b3_strad:
  addi x29, zero, 1            /* 32-bit straddling NON divide: arms the FSM */
  .2byte 0x0001                /* realign */
  addi x29, x29, 1             /* word aligned filler */
  addi x29, x29, 1             /* word aligned filler */
  addi x29, x29, 1             /* word aligned filler */
  addi x29, x29, 1             /* word aligned filler */
b3_victim:
  rem  x14, x11, x12           /* WORD ALIGNED victim, 5 insns downstream */
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 9
  or   x31, x31, x8
  li   x7, 0x24924916
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 10
  or   x31, x31, x8
  li   x7, 0xfffffff6
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 11
  or   x31, x31, x8

  #============================================================
  # ROW B4 -- IMMUNE: same selects -> corruption fires, invisible
  #   leader rem (ffffff9c,00000007) ISA=fffffffe   MUST PASS ALWAYS
  #   victim rem (fffffc18,0000000b) ISA=fffffff6   MUST PASS ALWAYS
  #============================================================
  .balign 4
  .option push
  .option norvc
b4_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
  .2byte 0x0001                /* c.nop: everything below is at mod4==2 */
b4_leader:
  rem  x28, x9, x18
b4_victim:
  rem  x14, x11, x12           /* 32-bit, at mod4==2: THE STRADDLE */
  .2byte 0x0001                /* realign; keeps the row self contained */
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 12
  or   x31, x31, x8
  li   x7, 0xfffffffe
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 13
  or   x31, x31, x8
  li   x7, 0xfffffff6
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 14
  or   x31, x31, x8

  #============================================================
  # ROW B5 -- DEFECT: BOTH select bits differ
  #   leader div (ffffff9c,00000007) ISA=fffffff2   MUST PASS ALWAYS
  #   victim remu(fffffc18,0000000b) ISA=00000005   MUST FAIL TODAY (runs under div selects -> ffffffa6)
  #============================================================
  .balign 4
  .option push
  .option norvc
b5_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
  .2byte 0x0001                /* c.nop: everything below is at mod4==2 */
b5_leader:
  div  x28, x9, x18
b5_victim:
  remu x14, x11, x12           /* 32-bit, at mod4==2: THE STRADDLE */
  .2byte 0x0001                /* realign; keeps the row self contained */
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 15
  or   x31, x31, x8
  li   x7, 0xfffffff2
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 16
  or   x31, x31, x8
  li   x7, 0x00000005
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 17
  or   x31, x31, x8

  #============================================================
  # ROW B6 -- NEAR MISS: odd parity but NO straddle -> no bubble
  #   leader divu(ffffff9c,00000007) ISA=24924916   MUST PASS ALWAYS
  #   victim rem (fffffc18,0000000b) ISA=fffffff6   MUST PASS ALWAYS
  #============================================================
  .balign 4
  .option push
  .option norvc
b6_canary:
  divu x13, x11, x12           /* word aligned drain + leak detector */
  .2byte 0x0001                /* c.nop: everything below is at mod4==2 */
b6_leader:
  divu x28, x9, x18
  .2byte 0x0001                /* COMPRESSED successor: no straddle, no bubble */
b6_victim:
  rem  x14, x11, x12           /* word aligned victim */
  .option pop
  li   x7, 0x1745d119
  xor  x8, x13, x7
  snez x8, x8
  slli x8, x8, 18
  or   x31, x31, x8
  li   x7, 0x24924916
  xor  x8, x28, x7
  snez x8, x8
  slli x8, x8, 19
  or   x31, x31, x8
  li   x7, 0xfffffff6
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 20
  or   x31, x31, x8

  #-------------------------------------------------------------
  # STRUCTURAL ASSERTIONS.  Every address relationship the
  # mechanism depends on, checked at run time into x30.
  #-------------------------------------------------------------
  /* b0_leader must be at mod4 == 0 */
  la   x5, b0_leader
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 0
  or   x30, x30, x5
  /* b0_victim must be at mod4 == 0 */
  la   x5, b0_victim
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 1
  or   x30, x30, x5
  /* b0_canary must be at mod4 == 0 */
  la   x5, b0_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 2
  or   x30, x30, x5
  /* b1_leader must be at mod4 == 2 */
  la   x5, b1_leader
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 3
  or   x30, x30, x5
  /* b1_victim must be at mod4 == 2 */
  la   x5, b1_victim
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 4
  or   x30, x30, x5
  /* b1_canary must be at mod4 == 0 */
  la   x5, b1_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 5
  or   x30, x30, x5
  /* b2_leader must be at mod4 == 2 */
  la   x5, b2_leader
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 6
  or   x30, x30, x5
  /* b2_victim must be at mod4 == 2 */
  la   x5, b2_victim
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 7
  or   x30, x30, x5
  /* b2_canary must be at mod4 == 0 */
  la   x5, b2_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 8
  or   x30, x30, x5
  /* b3_leader must be at mod4 == 2 */
  la   x5, b3_leader
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 9
  or   x30, x30, x5
  /* b3_victim must be at mod4 == 0 */
  la   x5, b3_victim
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 10
  or   x30, x30, x5
  /* b3_strad must be at mod4 == 2 */
  la   x5, b3_strad
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 11
  or   x30, x30, x5
  /* b3_canary must be at mod4 == 0 */
  la   x5, b3_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 12
  or   x30, x30, x5
  /* b4_leader must be at mod4 == 2 */
  la   x5, b4_leader
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 13
  or   x30, x30, x5
  /* b4_victim must be at mod4 == 2 */
  la   x5, b4_victim
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 14
  or   x30, x30, x5
  /* b4_canary must be at mod4 == 0 */
  la   x5, b4_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 15
  or   x30, x30, x5
  /* b5_leader must be at mod4 == 2 */
  la   x5, b5_leader
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 16
  or   x30, x30, x5
  /* b5_victim must be at mod4 == 2 */
  la   x5, b5_victim
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 17
  or   x30, x30, x5
  /* b5_canary must be at mod4 == 0 */
  la   x5, b5_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 18
  or   x30, x30, x5
  /* b6_leader must be at mod4 == 2 */
  la   x5, b6_leader
  andi x5, x5, 3
  li   x6, 2
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 19
  or   x30, x30, x5
  /* b6_victim must be at mod4 == 0 */
  la   x5, b6_victim
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 20
  or   x30, x30, x5
  /* b6_canary must be at mod4 == 0 */
  la   x5, b6_canary
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 21
  or   x30, x30, x5

  #-------------------------------------------------------------
  # VERDICT.  x30 = structural failures, x31 = value failures.
  #-------------------------------------------------------------
  or   x5, x30, x31
  bne  x5, x0, det_fail
  RVTEST_PASS
det_fail:
  RVTEST_FAIL

RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
