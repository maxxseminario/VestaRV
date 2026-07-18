# See LICENSE for license details.

#*****************************************************************************
# amoalias.S  (WORD AMO rd/rs1/rs2 register-aliasing — DEFAULT build)
#-----------------------------------------------------------------------------
# The AMO datapath must read the address and the rs2 operand from ALIAS-PROOF
# REGISTERED copies (latched at AMO_READ), not the live regfile ports: the FSM
# writes rd in AMO_WRITEBACK, two states before the memory write, so for rd==rs1
# or rd==rs2 the live ports carry the sign-extended old value, not the address /
# original rs2. GCC can emit these aliased forms (e.g. amoadd rd,rd,(rs1)), so
# they are real. This runs on the DEFAULT build (word A extension) and needs no
# Zabha — it also pins the pre-existing word rd==rs2 fault (X2 F2).
#
# amoadd.w rd==rs1 (Case C) uses the registered address today and must ALREADY
# pass — it proves the address path and is the negative control for Case A/B/D.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +a

    # Case A: amoadd.w rd == rs2   (a3 is both rd and rs2)
    la   a4, amo_w
    li   t0, 100
    sw   t0, 0(a4)
    li   a3, 5
    amoadd.w a3, a3, (a4)          # rd=old=100 ; mem=old+rs2=105 (F2 bug: 100+100=200)
    li   t1, 100
    bne  a3, t1, alias_fail
    lw   a5, 0(a4)
    li   t1, 105
    bne  a5, t1, alias_fail

    # Case B: amoswap.w rd == rs2
    la   a4, amo_w
    li   t0, 0x0000AAAA
    sw   t0, 0(a4)
    li   a3, 0x0000BBBB
    amoswap.w a3, a3, (a4)         # rd=old=0xAAAA ; mem=rs2=0xBBBB (F2 bug: mem=0xAAAA)
    li   t1, 0x0000AAAA
    bne  a3, t1, alias_fail
    lw   a5, 0(a4)
    li   t1, 0x0000BBBB
    bne  a5, t1, alias_fail

    # Case C: amoadd.w rd == rs1 (address) — MUST already pass (address path)
    la   a3, amo_w
    li   t0, 100
    sw   t0, 0(a3)
    li   a4, 7
    amoadd.w a3, a4, (a3)          # rd=old=100 ; mem=107 (address is registered)
    li   t1, 100
    bne  a3, t1, alias_fail
    la   a5, amo_w
    lw   a5, 0(a5)
    li   t1, 107
    bne  a5, t1, alias_fail

    # Case D: amoadd.w rd == rs1 == rs2 (one reg = the address); mem=0 so
    # correct result = old(0) + rs2(=address) = the address value itself.
    la   a3, amo_w
    sw   x0, 0(a3)
    mv   t0, a3                    # save the address
    amoadd.w a3, a3, (a3)          # rd=old=0 ; mem = 0 + address (F2 bug: 0+0=0)
    bnez a3, alias_fail            # rd = old = 0
    lw   a5, 0(t0)
    bne  a5, t0, alias_fail        # mem must equal the (nonzero) address

    .option pop

    RVTEST_PASS

alias_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
  .align 2
amo_w: .word 0
RVTEST_DATA_END
