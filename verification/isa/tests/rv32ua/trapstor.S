# See LICENSE for license details.

# VestaRV: detector for stores committed out of the terminal trap state
# THE DEFECT: TRAP_STATE assigns pc_en, reg_write_dp, next_state and trap_flag and NOTHING ELSE, so `wen` falls through to wen_controller, and TRAP_STATE is absent from the instr_curr hold list, so instr_curr takes the decode of the LIVE BUS WORD. Meanwhile mem_access_instr is low, so data_addr falls all the way through to pc_next_trad_reg, the fetch address latched at the trapping EXECUTE edge, which is the trapping PC plus 4. The word at that address is therefore decoded as an instruction AND is the store target, so if it is a store encoding the core commits a real store to it, and TRAP_STATE self-loops forever so it can keep doing so until the 100 ms watchdog. riscv_tb does not watch trap_flag.
# THIS NEEDS TWO HARTS, because TRAP_STATE is TERMINAL and a hart that enters it never writes a0 again. The victim is tile hart 1 and the observer is hart 0, which keeps the ordinary pass/fail contract. FOR HART 0 TO SEE THE CORRUPTION AT ALL THE VICTIM MUST BE EXECUTING FROM THE SHARED WINDOW when it traps, since the store target is the fetch address and a TCM fetch address would corrupt a private word no other hart can read.
# The planted payload, written by hart 0 before any launch: 0x10420 CODE = 0x0000007F, whose opcode is not in maindec's valid_opcode list on any build so it is an illegal instruction, with bits [1:0] = "11" so it is a full 32-bit instruction and the next fetch address is pc + 4; 0x10424 VICTIM = 0x00002023, `sw x0, 0(x0)`, which decoded out of TRAP_STATE drives all four active-low lanes with write data 0 and therefore overwrites THIS VERY WORD; 0x10428 and 0x1042C canaries holding 0xC0DEC0DE, to catch a store that lands near the victim instead of on it; and 0x10438 ARM = 0xA5A5A5A5, written by hart 1 in the instruction immediately before it jumps into the payload. HART 0 REFUSES TO RENDER A VERDICT UNTIL IT SEES ARM, so a tile that never launched must fail rather than vacuously pass.
# Verdicts: a0 = 0xCAFEBABE means the victim word and both canaries stayed intact for the whole observation window with ARM proven set; a0 = 0xDEADBEEF with a1 = 0xF8F8F8F8 means the victim word changed. Other a1 codes are setup breaks rather than the finding: 0x5E800001 the planted payload did not read back, 0x5E800002 ARM never appeared so tile 1 never reached the payload, 0x5E80000C a canary moved, so a store landed off-target and the result must be analysed rather than scored as a clean hit.
# A SECOND OBSERVABLE EXISTS IN TRACED RUNS: the tracer emits a TRAPSTORE record for exactly this event, which is a POSITIVE CONTROL this detector must provoke, so the count must be above zero on hart 1 when the defect is present and zero when it is not. The per-hart trace limit is 8, so any nonzero count is a floor.
# NOT IN THE STANDING SUITE: the victim ends parked in TRAP_STATE forever and never writes its a0, which riscv_tb reports as a NOTE rather than a failure, and the test is kept out of the runner array so the suite floor stays at its pinned count. Invoke it explicitly with ./xrun_batch.sh xrv32ua-p-trapstor.
# Shared words, all below 0x10500 and inside the bootrom zero range: 0x10420 CODE, 0x10424 VICTIM, 0x10428 and 0x1042C canaries, 0x10438 ARM. 0x10430 IS DELIBERATELY SKIPPED, because it belongs to the sibling detector scfailrd.S.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_CODE    0x10420
#define SH_VICTIM  0x10424
#define SH_CAN1    0x10428
#define SH_CAN2    0x1042C
#define SH_ARM     0x10438

#define ILLEGAL_W  0x0000007F      /* opcode 0x7F: illegal on every build   */
#define STORE_W    0x00002023      /* sw x0, 0(x0)                          */
#define CANARY_V   0xC0DEC0DE
#define ARM_V      0xA5A5A5A5

#define TILE_WORDS  1024      /* covers 0x8000-0x8FFF; tile_entry links at ~0x8374 */
#define ARM_BUDGET  12000
#define WATCH_ITERS 4000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # build march has no zicsr — enable it just for the mhartid read
    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry        # belt-and-braces: only hart 0 orchestrates

    li   s2, SH_CODE
    li   s3, SH_VICTIM
    li   s4, SH_CAN1
    li   s5, SH_CAN2
    li   s6, SH_ARM

    li   s7, STORE_W            # the value VICTIM must keep
    li   s8, CANARY_V

    # ---- plant the payload, read-back verified ------------------------------
    li   a1, 0x5E800001
    li   t0, ILLEGAL_W
    sw   t0, 0(s2)
    lw   t1, 0(s2)
    bne  t1, t0, trapstor_fail

    sw   s7, 0(s3)
    lw   t1, 0(s3)
    bne  t1, s7, trapstor_fail

    sw   s8, 0(s4)
    lw   t1, 0(s4)
    bne  t1, s8, trapstor_fail

    sw   s8, 0(s5)
    lw   t1, 0(s5)
    bne  t1, s8, trapstor_fail

    sw   x0, 0(s6)              # ARM starts clear
    lw   t1, 0(s6)
    bnez t1, trapstor_fail

    # ---- launch ONLY tile hart 1 into the payload ---------------------------
    # TILE_WORDS (not the full 4096-word TCM): the tile only needs the code
    # up to tile_entry, and a 4096-word stage + a 4096-word loader copy costs
    # ~5 ms of contended arbiter traffic that pushed hart 0's ARM budget out.
    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)

    # ---- wait (bounded) for tile 1 to say it is about to jump ---------------
    li   t6, ARM_BUDGET
    li   t5, ARM_V
arm_wait:
    lw   t2, 0(s6)
    beq  t2, t5, armed
    addi t6, t6, -1
    bnez t6, arm_wait
    li   a1, 0x5E800002         # tile never reached the payload: NOT a pass
    j    trapstor_fail

armed:
    # ---- observe: VICTIM (and its neighbours) must not move -----------------
    li   t6, WATCH_ITERS
watch_loop:
    lw   t2, 0(s3)
    bne  t2, s7, trapstor_fired # THE finding: TRAP_STATE committed a store
    lw   t2, 0(s4)
    bne  t2, s8, trapstor_canary
    lw   t2, 0(s5)
    bne  t2, s8, trapstor_canary
    addi t6, t6, -1
    bnez t6, watch_loop

    RVTEST_PASS                 # a0 = 0xCAFEBABE: TRAP_STATE stayed silent

trapstor_canary:
    li   a1, 0x5E80000C         # a store landed, but off the expected word
    j    trapstor_fail
trapstor_fired:
    li   a1, 0xF8F8F8F8         # F8 fired
trapstor_fail:
    RVTEST_FAIL                 # a0 = 0xDEADBEEF

    # ---- tile hart 1 enters here (loader ABI: only sp is defined) -----------
tile_entry:
    li   sp, 0xBFF0
    li   t0, SH_ARM
    li   t1, ARM_V
    sw   t1, 0(t0)              # liveness: hart 0 may now render a verdict
    li   t2, SH_CODE
    jr   t2                     # EXECUTE FROM SHARED -> illegal word ->
                                # terminal TRAP_STATE with the store encoding
                                # at pc_next_trad_reg on the bus.  Never
                                # returns; this hart never writes a0_1.

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) — never fall
    # through; every hart-0 path above ends in a spin and the tile path ends
    # in an unconditional jump.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
