# See LICENSE for license details.

# VestaRV: reserved word-AMO funct5 trap side-effect probe
# A DIAGNOSTIC POISON, NOT A PASS/FAIL TEST. It executes encoding 0x3005A02F, a word-width AMO (funct3 = 010) with the RESERVED funct5 = 00110, rs1 = a1, rs2 = rd = x0, and by design never returns: on a legacy-delivery build that encoding is illegal and the core parks in the terminal TRAP_STATE.
# RUN IT ONLY UNDER A BOUNDED TCL or the trap harness. It is wired into the Makefrag so it is BUILT, and it is deliberately not in the default runner array, where it would sit in TRAP_STATE until the 100 ms tb watchdog.
# What it exposes: maindec's AMO valid_funct arm rejects reserved word funct5 codes, but amo_op is decoded WITHOUT that whitelist, and the store-lane decode is `WEN <= "0000" when (op = AMO_OPCODE and (sc_op or amo_op))`, so this encoding raises trap and asserts all four active-low write lanes at once. On the legacy path the EXECUTE trap arm routes to TRAP_STATE without forcing wen, and TRAP_STATE forces only pc_en, reg_write_dp and trap_flag, leaving wen at wen_controller and data_addr at pc_next. Measured on the default build: state TRAP_STATE, PC at the poison, ADDR at pc+4, and the word at pc+4 overwritten with zero. The write is a single shot only because TRAP_STATE does not hold instr_curr, so the decoder re-decodes the zero it just wrote, which is not a store; a written value that decoded to a store would keep writing every cycle.
# SCOPE. Legacy delivery and OFF builds only: in standard delivery the EXECUTE trap arm forces wen all-ones with mem_access_instr and reg_write_dp low before routing to MTRAP_SV, and MTRAP_SV and MTRAP_JUMP do the same, so no U-mode path is affected. The address is pc+4, since data_addr falls through to pc_next when mem_access_instr is low, so the blast radius is the hart's own instruction stream, or the SHARED bus for code executing from the shared window, because sh_we_lanes is `not wen_re` gated on sh_sel alone with no state qualifier. The fix is to give the legacy TRAP_STATE dispatch and the TRAP_STATE arm the same `wen <= (others => '1'); mem_access_instr <= '0';` the standard arm already has.

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
