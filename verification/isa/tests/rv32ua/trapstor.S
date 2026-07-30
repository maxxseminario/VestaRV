# See LICENSE for license details.

#*****************************************************************************
# trapstor.S   (F-series fix pass, wave W1 — DETECTOR for finding F8)
#-----------------------------------------------------------------------------
# F8: TRAP_STATE is NOT SILENT — it commits real stores.
#
#   vesta.vhd's TRAP_STATE arm (:3464-3468) assigns pc_en, reg_write_dp,
#   next_state and trap_flag — and NOTHING ELSE.  `wen` therefore falls
#   through to the process default `wen <= wen_controller` (:2110), and
#   TRAP_STATE is absent from the instr_curr hold list (:1429-1474) so
#   `instr_curr <= instr_decomp` of the LIVE BUS WORD.  Meanwhile
#   mem_access_instr is '0', so the data_addr mux (:1551-1563) falls all the
#   way through to `pc_next` = pc_next_trad = pc_next_trad_reg — the fetch
#   address latched at the trapping EXECUTE edge, i.e. PC_of_trap + 4.
#
#   Consequence: the word AT pc_next_trad_reg is decoded as an instruction AND
#   is the store target.  If that word is a store encoding, the core commits a
#   real store to it, and TRAP_STATE self-loops forever, so it can keep doing
#   so until the 100 ms tb watchdog.  riscv_tb does not watch trap_flag.
#
# WHY THIS TEST NEEDS TWO HARTS
#   TRAP_STATE is TERMINAL (self-loop, no exit).  A hart that enters it never
#   writes a0 again, so the trapping hart can never be the a0 gate.  Here the
#   VICTIM is tile hart 1 and the OBSERVER is hart 0, which keeps the ordinary
#   PASS/FAIL contract.  For hart 0 to see the corruption at all, the victim
#   must be executing FROM THE SHARED WINDOW when it traps (the store target is
#   the fetch address; a TCM fetch address would corrupt a private word that no
#   other hart can read).  Execute-from-shared is proven by shexec.S (M10).
#
# THE PLANTED PAYLOAD (hart 0 writes it into shared RAM before any launch):
#     0x10420  CODE   = 0x0000007F   opcode 0x7F is not in maindec's
#                                    valid_opcode list (maindec.vhd:608-630)
#                                    on ANY build => illegal-instruction trap;
#                                    bits[1:0]="11" so it is a full 32-bit
#                                    insn and pc_next_trad = pc + 4.
#     0x10424  VICTIM = 0x00002023   `sw x0, 0(x0)`.  Decoded out of TRAP_STATE
#                                    it drives wen_controller to "0000" (all
#                                    four lanes, ACTIVE-LOW) with write_data =
#                                    x0 = 0 — so the pre-fix core overwrites
#                                    THIS VERY WORD with 0x00000000.
#     0x10428  CAN1   = 0xC0DEC0DE   canaries: catch a store that lands near
#     0x1042C  CAN2   = 0xC0DEC0DE   the victim instead of on it.
#     0x10438  ARM    = 0xA5A5A5A5   liveness flag, written by hart 1 in the
#                                    instruction immediately before it jumps
#                                    into the payload.  Hart 0 REFUSES to
#                                    render a verdict until it sees ARM — a
#                                    tile that never launched must FAIL, never
#                                    vacuously pass.
#
# VERDICT
#   pre-fix : a0 = 0xDEADBEEF  (a1 = 0xF8F8F8F8, "F8 fired" — VICTIM changed)
#   post-fix: a0 = 0xCAFEBABE  (VICTIM and both canaries intact for the whole
#                               observation window, with ARM proven set)
#   Other a1 codes on a FAIL are setup breaks, not the finding:
#       a1 = 0x5E800001  the planted payload did not read back
#       a1 = 0x5E800002  ARM never appeared: tile 1 never reached the payload
#       a1 = 0x5E80000C  a CANARY moved (store landed off-target — analyse,
#                        do NOT score this as a clean F8 hit)
#
#   SECOND OBSERVABLE (traced runs): the tracer emits
#   `# TRAPSTORE <hart> <cycle> <addr> <size> <data>` (vesta_tracer.vhd:563)
#   for exactly this event.  W0 measured TRAPSTORE = 0 everywhere at HEAD, so
#   per ruling R-W0-1 this diagnostic is a POSITIVE CONTROL this detector must
#   PROVOKE: pre-fix TRAPSTORE > 0 on hart 1, post-fix 0.  Note
#   TRAPSTORE_LIMIT := 8 per hart — any nonzero count is a FLOOR.
#
# NOT IN THE STANDING SUITE.  Post-fix, tile hart 1 is parked in TRAP_STATE
# forever and never writes a0_1; riscv_tb reports "tile hart(s) silent/parked",
# which is a NOTE, not a failure.  The test is still kept OUT of
# xrun_parallel.sh's TEST_FILES array so the suite floor stays at its pinned
# count; invoke it explicitly with ./xrun_batch.sh xrv32ua-p-trapstor.
#
# Shared words claimed (all < 0x10500 and inside the bootrom zero range):
#     0x10420 CODE, 0x10424 VICTIM, 0x10428 CAN1, 0x1042C CAN2, 0x10438 ARM
#   Free band 0x10420-0x1043C sits between shexec's N=18 DONE top (0x1041C) and
#   shfault's HEARTBEAT base (0x10440) — unclaimed at N=4 and N=18.  0x10430 is
#   deliberately skipped: it belongs to the sibling W1 detector scfailrd.S.
#*****************************************************************************

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
