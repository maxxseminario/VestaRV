# See LICENSE for license details.

#*****************************************************************************
# dvintmin.S
#-----------------------------------------------------------------------------
#
# DET-A: the divide family's signed restoring loop, at INT_MIN.
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

# WHAT IT COVERS.  div/rem magnitudes and the partial remainder live in
# 32-bit SIGNED registers, so abs(INT_MIN) stays negative and the loop's
# comparison is decided on the wrong side.  Rows 0-10 are inside that
# predicate and are WRONG at 5c91e35.  Rows 11-26 are immune, several of
# them by one LSB (|b| = 2^30 exactly vs 2^30+1), and they must stay
# correct -- they are what an OVER WIDE fix would break.
#
# STRUCTURAL REQUIREMENT.  This test must contain NO split-fetch bubble,
# so that it isolates the arithmetic defect from the control-path one.
# It gets that by construction: `.balign 4' OUTSIDE a `.option norvc'
# region (measured: alignment directives are SILENT NO-OPS inside norvc,
# because gas cannot emit a 2-byte pad when compression is off), and then
# every instruction in the region is exactly 4 bytes.  The parity is also
# ASSERTED AT RUN TIME below, so the test can never silently stop covering.

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
  # STRUCTURAL ASSERTION: the arithmetic block is word aligned.
  #-------------------------------------------------------------
  la   x5, a_block
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 0
  or   x30, x30, x5
  la   x5, a_mid
  andi x5, x5, 3
  li   x6, 0
  xor  x5, x5, x6
  snez x5, x5
  slli x5, x5, 1
  or   x30, x30, x5

  .balign 4
  .option push
  .option norvc
a_block:
  #ROW 0  div (000002f4,80000000) ISA=00000000  MUST FAIL TODAY  [b=INT_MIN, small +a (ledger row)]
  li   x11, 0x000002f4
  li   x12, 0x80000000
  div  x14, x11, x12
  li   x7, 0x00000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 0
  or   x31, x31, x8

  #ROW 1  rem (00000000,80000000) ISA=00000000  MUST FAIL TODAY  [b=INT_MIN, a=0]
  li   x11, 0x00000000
  li   x12, 0x80000000
  rem  x14, x11, x12
  li   x7, 0x00000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 1
  or   x31, x31, x8

  #ROW 2  rem (7fffffff,80000000) ISA=7fffffff  MUST FAIL TODAY  [b=INT_MIN, a=INT_MAX]
  li   x11, 0x7fffffff
  li   x12, 0x80000000
  rem  x14, x11, x12
  li   x7, 0x7fffffff
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 2
  or   x31, x31, x8

  #ROW 3  div (ffffffff,80000000) ISA=00000000  MUST FAIL TODAY  [b=INT_MIN, a=-1]
  li   x11, 0xffffffff
  li   x12, 0x80000000
  div  x14, x11, x12
  li   x7, 0x00000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 3
  or   x31, x31, x8

  #ROW 4  rem (64046d0a,80000000) ISA=64046d0a  MUST FAIL TODAY  [b=INT_MIN, a arbitrary]
  li   x11, 0x64046d0a
  li   x12, 0x80000000
  rem  x14, x11, x12
  li   x7, 0x64046d0a
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 4
  or   x31, x31, x8

  #ROW 5  div (80000000,80000000) ISA=00000001  MUST FAIL TODAY  [CANCELLATION HAZARD: div(INT_MIN,INT_MIN)]
  li   x11, 0x80000000
  li   x12, 0x80000000
  div  x14, x11, x12
  li   x7, 0x00000001
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 5
  or   x31, x31, x8

  #ROW 6  rem (80000000,aaaaaaaa) ISA=d5555556  MUST FAIL TODAY  [a=INT_MIN, |b|>2^30 (ledger row)]
  li   x11, 0x80000000
  li   x12, 0xaaaaaaaa
  rem  x14, x11, x12
  li   x7, 0xd5555556
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 6
  or   x31, x31, x8

  #ROW 7  div (80000000,40000001) ISA=ffffffff  MUST FAIL TODAY  [a=INT_MIN, |b| = 2^30 + 1  (BOUNDARY+1)]
  li   x11, 0x80000000
  li   x12, 0x40000001
  div  x14, x11, x12
  li   x7, 0xffffffff
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 7
  or   x31, x31, x8

  #ROW 8  rem (80000000,40000001) ISA=c0000001  MUST FAIL TODAY  [a=INT_MIN, |b| = 2^30 + 1  (BOUNDARY+1)]
  li   x11, 0x80000000
  li   x12, 0x40000001
  rem  x14, x11, x12
  li   x7, 0xc0000001
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 8
  or   x31, x31, x8

  #ROW 9  div (80000000,bfffffff) ISA=00000001  MUST FAIL TODAY  [a=INT_MIN, |b| = 2^30 + 1, b<0]
  li   x11, 0x80000000
  li   x12, 0xbfffffff
  div  x14, x11, x12
  li   x7, 0x00000001
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 9
  or   x31, x31, x8

  #ROW 10 div (80000000,59c45951) ISA=ffffffff  MUST FAIL TODAY  [a=INT_MIN, |b|>2^30]
  li   x11, 0x80000000
  li   x12, 0x59c45951
  div  x14, x11, x12
  li   x7, 0xffffffff
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 10
  or   x31, x31, x8

  #ROW 11 div (80000000,40000000) ISA=fffffffe  MUST PASS ALWAYS  [NEAR MISS |b| = 2^30 EXACTLY]
  li   x11, 0x80000000
  li   x12, 0x40000000
  div  x14, x11, x12
  li   x7, 0xfffffffe
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 11
  or   x31, x31, x8

  #ROW 12 rem (80000000,40000000) ISA=00000000  MUST PASS ALWAYS  [NEAR MISS |b| = 2^30 EXACTLY]
  li   x11, 0x80000000
  li   x12, 0x40000000
  rem  x14, x11, x12
  li   x7, 0x00000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 12
  or   x31, x31, x8

  #ROW 13 div (80000000,c0000000) ISA=00000002  MUST PASS ALWAYS  [NEAR MISS |b| = 2^30 EXACTLY, b<0]
  li   x11, 0x80000000
  li   x12, 0xc0000000
  div  x14, x11, x12
  li   x7, 0x00000002
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 13
  or   x31, x31, x8

a_mid:
  #ROW 14 div (80000000,3fffffff) ISA=fffffffe  MUST PASS ALWAYS  [NEAR MISS |b| = 2^30 - 1]
  li   x11, 0x80000000
  li   x12, 0x3fffffff
  div  x14, x11, x12
  li   x7, 0xfffffffe
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 14
  or   x31, x31, x8

  #ROW 15 rem (80000000,3fffffff) ISA=fffffffe  MUST PASS ALWAYS  [NEAR MISS |b| = 2^30 - 1]
  li   x11, 0x80000000
  li   x12, 0x3fffffff
  rem  x14, x11, x12
  li   x7, 0xfffffffe
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 15
  or   x31, x31, x8

  #ROW 16 div (80000000,00000001) ISA=80000000  MUST PASS ALWAYS  [CANCELLATION HAZARD: div(INT_MIN,1)]
  li   x11, 0x80000000
  li   x12, 0x00000001
  div  x14, x11, x12
  li   x7, 0x80000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 16
  or   x31, x31, x8

  #ROW 17 rem (80000000,80000000) ISA=00000000  MUST PASS ALWAYS  [CANCELLATION HAZARD: rem(INT_MIN,INT_MIN)]
  li   x11, 0x80000000
  li   x12, 0x80000000
  rem  x14, x11, x12
  li   x7, 0x00000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 17
  or   x31, x31, x8

  #ROW 18 div (80000000,ffffffff) ISA=80000000  MUST PASS ALWAYS  [signed overflow special case]
  li   x11, 0x80000000
  li   x12, 0xffffffff
  div  x14, x11, x12
  li   x7, 0x80000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 18
  or   x31, x31, x8

  #ROW 19 rem (80000000,ffffffff) ISA=00000000  MUST PASS ALWAYS  [signed overflow special case]
  li   x11, 0x80000000
  li   x12, 0xffffffff
  rem  x14, x11, x12
  li   x7, 0x00000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 19
  or   x31, x31, x8

  #ROW 20 div (80000000,00000000) ISA=ffffffff  MUST PASS ALWAYS  [divide by zero special case]
  li   x11, 0x80000000
  li   x12, 0x00000000
  div  x14, x11, x12
  li   x7, 0xffffffff
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 20
  or   x31, x31, x8

  #ROW 21 rem (80000000,00000000) ISA=80000000  MUST PASS ALWAYS  [remainder by zero special case]
  li   x11, 0x80000000
  li   x12, 0x00000000
  rem  x14, x11, x12
  li   x7, 0x80000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 21
  or   x31, x31, x8

  #ROW 22 remu(80000000,ffffffff) ISA=80000000  MUST PASS ALWAYS  [unsigned path, a=INT_MIN]
  li   x11, 0x80000000
  li   x12, 0xffffffff
  remu x14, x11, x12
  li   x7, 0x80000000
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 22
  or   x31, x31, x8

  #ROW 23 divu(80000000,80000000) ISA=00000001  MUST PASS ALWAYS  [unsigned path, both INT_MIN]
  li   x11, 0x80000000
  li   x12, 0x80000000
  divu x14, x11, x12
  li   x7, 0x00000001
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 23
  or   x31, x31, x8

  #ROW 24 remu(14a4b043,8576b3e8) ISA=14a4b043  MUST PASS ALWAYS  [unsigned path (ledger row)]
  li   x11, 0x14a4b043
  li   x12, 0x8576b3e8
  remu x14, x11, x12
  li   x7, 0x14a4b043
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 24
  or   x31, x31, x8

  #ROW 25 div (fffffc18,0000000b) ISA=ffffffa6  MUST PASS ALWAYS  [ordinary mixed sign]
  li   x11, 0xfffffc18
  li   x12, 0x0000000b
  div  x14, x11, x12
  li   x7, 0xffffffa6
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 25
  or   x31, x31, x8

  #ROW 26 rem (64046d0a,55555555) ISA=0eaf17b5  MUST PASS ALWAYS  [the D-2026-08-03-1 operands, word-aligned]
  li   x11, 0x64046d0a
  li   x12, 0x55555555
  rem  x14, x11, x12
  li   x7, 0x0eaf17b5
  xor  x8, x14, x7
  snez x8, x8
  slli x8, x8, 26
  or   x31, x31, x8

  .option pop

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
