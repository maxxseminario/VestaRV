# See LICENSE for license details.

#*****************************************************************************
# dbgprvmp.S   (D-series, D2 -- dcsr.prv UNDER A U-MODE VICTIM; carryover 3)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d2_spec.md section 8 and d1_spec.md section 1
# (dcsr.prv), FROZEN 2026-08-05, by an agent that has not seen and will never
# see the D2 implementation.  Committed polarity: CORRECT RTL = PASS.
#
# NEEDS A HARNESS:  ./xrun_dbg.sh rv32ua-p-dbgprvmp dbg_prv.tcl
#
# THE ROW IT RUNS ON: config/castalia_debug.json, THE 29th, AS AMENDED.
#   This file needs debug.enable AND priv.umode in the SAME build.  When it was
#   written no config in the tree had both -- the two debug rows omitted
#   priv.umode and the two umode rows were debug-OFF -- and the acceptance
#   author reported that as a spec gap rather than inventing a config.
#   R-D2-2(2) ruled it: **castalia_debug.json gains
#   "priv": {"trapCsr": true, "umode": true}**, explicitly rather than by
#   inheritance (the CLAUDE.md inheritance-trap discipline), and there is NO
#   31st Castalia row.  The re-base and the new CATALOG rows are ONE
#   deliberate re-pin of that row's verify count, predicted before measured.
#   argus_debug.json stays minimal: this instrument has no N=18 obligation.
#       SUITE=full make verify CONFIG=config/castalia_debug.json
#   The d2mut `umode` scratch arm remains available for a hand-staged run
#   (it is how this file's liveness control was proved), but it is no longer
#   the only vehicle.
#
# WHY dcsr.prv NEEDS A U-MODE VICTIM AT ALL -- the D1 residual, quoted
#   d1_acceptance_report section 4: "no mutant here targets dcsr.prv, because
#   every victim in this set is in M-mode and a prv that always reads 3 is
#   indistinguishable from a correct one".  R-D1-3(2) made it a NAMED D2 item.
#   The ONLY way to distinguish is a victim that is genuinely NOT in M-mode
#   when it is halted, so this file's whole construction exists to put one
#   there and to prove it was there.
#
# THE TWO-SIDED PROOF
#   * the DM side (dbg_prv.tcl): abstract-read dcsr (0x7B0) on the halted
#     victim and require prv == 0.  That is the assertion carryover 3 asks
#     for, and it is only meaningful if the victim really was in U-mode --
#     which the harness cannot know.
#   * the ARCHITECTURAL side (this file): the victim proves its own privilege
#     TWICE, once before the halt and once after the resume, by executing
#     `ecall` and having the M-mode handler record mcause.  ECALL_FROM_U is
#     cause 8; ECALL_FROM_M is cause 11.  Two 8s bracket the debug visit:
#     the first says the victim was in U when it parked, the second says
#     `dret` put it back in U and not in M.  A dret that silently promoted
#     the hart would give 11 on the second -- and nothing else in the D-series
#     can see that.
#
# THE DELIVERY PATH, and why the test must ask for it
#   trapCsr defaults ON (R-DK3) but mtrapctl.LEGACY RESETS TO 1, so a fresh
#   hart delivers traps down the legacy irq_handler/IVT path and mtvec is not
#   consulted.  Standard delivery is a per-hart FIRMWARE OPT-IN: `csrw 0x7C0,
#   x0`.  The victim does exactly that before it drops to U, and it never
#   parks with `extinguish` afterwards -- the CLAUDE.md PARK/WAKE hazard
#   (clearing LEGACY on a hart that then EXTINGUISHes makes it UNWAKEABLE) is
#   avoided by construction, not by luck.  hart 0 is untouched and keeps the
#   legacy path.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => the victim was in U-mode before the halt, and
# `dret` returned it to U-mode.
#   a1 = 0x0D240001   a shared word did not read back
#   a1 = 0x0D240002   base-ISA sanity failed
#   a1 = 0x0D240003   THE VICTIM NEVER FINISHED (a2 = PROG): 1 = reached
#                     U-mode, 2 = first ecall taken, 3 = parked, 4 = released.
#                     Under xrun_batch.sh this is the expected result.
#   a1 = 0x0D240004   the FIRST ecall did not report cause 8 (a2 = mcause):
#                     the victim was not in U-mode when it parked, so the
#                     whole test would have been measuring nothing
#   a1 = 0x0D240005   the SECOND ecall did not report cause 8 (a2 = mcause):
#                     `dret` did not return the hart to U-mode.  a2 = 11 means
#                     it came back in M -- a privilege ESCALATION through the
#                     debug visit
#   a1 = 0x0D240006   the victim's U-mode counter did not advance across the
#                     debug visit (a2 = the counter): it never really resumed
#
# NEGATIVE CONTROL -- how the non-DM half was SEEN TO WORK:
#   -DDBGPRV_NC_SELF.  The victim releases itself instead of waiting for the
#   harness, so both ecalls, both mcause recordings, the U-mode counter and
#   hart 0's whole assertion chain run with no debugger at all.  A PASS proves
#   the privilege plumbing and the grading are LIVE (method rule 5); it makes
#   no claim about dcsr.prv and must never be quoted as a D2 result.
#
# N-AGNOSTIC.  ONE victim, hart 1, at any NHARTS.
#
# SHARED WORDS CLAIMED -- the D-series debug acceptance band 0x10050-0x1007C,
#   REUSED with this file's meanings (one image per sim):
#     0x10050  READY     victim: in U-mode, first ecall done, about to park
#     0x10054  REL       the harness plants 1 here to release the victim
#     0x10058  DONE      victim: second ecall done, everything published
#     0x1005C  CAUSE1    mcause of the ecall taken BEFORE the halt (want 8)
#     0x10060  CAUSE2    mcause of the ecall taken AFTER the resume (want 8)
#     0x10064  UCNT      the victim's U-mode counter
#     0x10068  PROG      victim progress
#     0x1006C-0x1007C  unused by this file
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_READY   0x10050
#define SH_REL     0x10054
#define SH_DONE    0x10058
#define SH_CAUSE1  0x1005C
#define SH_CAUSE2  0x10060
#define SH_UCNT    0x10064
#define SH_PROG    0x10068

#define DONE_MAGIC 0x0D24D0E5
#define TILE_WORDS 1024
#define ARM_BUDGET 40000
#define MTRAPCTL   0x7C0            /* the custom trap-control CSR (P1)      */

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    li   a1, 0x0D240001
    li   t0, SH_READY
    li   t1, 12
dp_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dp_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dp_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D240002
    bne  t2, t3, dp_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)

    li   s4, SH_DONE
    li   s5, DONE_MAGIC
    li   t6, ARM_BUDGET
dp_wait:
    lw   t2, 0(s4)
    beq  t2, s5, dp_check
    addi t6, t6, -1
    bnez t6, dp_wait
    li   t0, SH_PROG
    lw   a2, 0(t0)
    li   a1, 0x0D240003
    j    dp_fail

dp_check:
    li   t0, SH_CAUSE1
    lw   a2, 0(t0)
    li   a3, 8                      # ECALL_FROM_U
    li   a1, 0x0D240004
    bne  a2, a3, dp_fail

    li   t0, SH_CAUSE2
    lw   a2, 0(t0)
    li   a3, 8
    li   a1, 0x0D240005
    bne  a2, a3, dp_fail

    li   t0, SH_UCNT
    lw   a2, 0(t0)
    li   a3, 2
    li   a1, 0x0D240006
    blt  a2, a3, dp_fail

    RVTEST_PASS

dp_fail:
    RVTEST_FAIL

    # ---- the victim (hart 1) --------------------------------------------
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    bne  t3, t4, tile_park

    .option push
    .option arch, +zicsr
    # STANDARD delivery, per hart, by opt-in.  mtrapctl.LEGACY resets 1 and a
    # legacy trap never consults mtvec; without this the ecalls below would
    # vector down the IVT and this test would measure the IVT.
    csrw MTRAPCTL, x0
    la   t0, dp_mhandler
    csrw mtvec, t0
    # MPP = 00 (U) and MPIE clear: `mret` then enters U-mode at mepc.
    li   t0, 0x1800                 # MPP field mask
    csrc mstatus, t0
    la   t0, dp_umode
    csrw mepc, t0
    .option pop
    li   s1, 0                      # the U-mode counter shadow
    mret                            # ---- now in U-mode ----

    # ---- U-MODE CODE.  No CSR access of any kind lives below this line:
    # every one would be illegal from U and would turn this test into a trap
    # test.  The only privileged act is `ecall`, which is the point.
dp_umode:
    li   t0, SH_PROG
    li   t1, 1
    sw   t1, 0(t0)
    addi s1, s1, 1
    li   t0, SH_UCNT
    sw   s1, 0(t0)
    li   s2, 1                      # "this is the FIRST ecall"
    ecall                           # -> dp_mhandler, cause 8, returns here+4
    li   t0, SH_PROG
    li   t1, 3
    sw   t1, 0(t0)
    li   t0, SH_READY
    li   t1, 1
    sw   t1, 0(t0)                  # publish LAST: READY means "in U, parked"

#ifdef DBGPRV_NC_SELF
    li   t0, SH_REL                 # CONTROL ARM: release itself
    li   t1, 1
    sw   t1, 0(t0)
#endif

    # THE PARK.  Holds no live register but s1/s2, which the debug visit must
    # not touch; the address is recomputed every round.
dp_park:
    li   t0, SH_REL
    lw   t1, 0(t0)
    beqz t1, dp_park

    li   t0, SH_PROG
    li   t1, 4
    sw   t1, 0(t0)
    addi s1, s1, 1                  # ...still running, still in U
    li   t0, SH_UCNT
    sw   s1, 0(t0)
    li   s2, 2                      # "this is the SECOND ecall"
    ecall                           # -> cause 8 again IF dret returned to U
    li   t0, SH_DONE
    li   t1, DONE_MAGIC
    sw   t1, 0(t0)                  # publish LAST
dp_upark:
    j    dp_upark

    # ---- M-MODE TRAP HANDLER (standard delivery, mtvec) ------------------
    # It records mcause into CAUSE1 or CAUSE2 according to s2 and returns to
    # mepc+4.  It runs in M-mode; s1/s2 belong to the U-mode code and are
    # only READ here.
    .option push
    .option arch, +zicsr
    # NO .align here.  mtvec needs a 4-byte-aligned base, and it has one for a
    # structural reason rather than a directive: this whole file is
    # `.option norvc`, every instruction is 4 bytes, and `.align`/`.balign` is
    # a SILENT NO-OP inside a norvc region anyway (CLAUDE.md).  Writing one
    # would be a rationale that is false, which is worse than none.
dp_mhandler:
    csrr t0, mcause
    li   t1, 1
    bne  s2, t1, 1f
    li   t2, SH_CAUSE1
    j    2f
1:  li   t2, SH_CAUSE2
2:  sw   t0, 0(t2)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    # return to U: MPP is already 00 because the trap came from U, so a plain
    # mret goes back where it came from, in the mode it came from.
    mret
    .option pop

tile_park:
    j    tile_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
