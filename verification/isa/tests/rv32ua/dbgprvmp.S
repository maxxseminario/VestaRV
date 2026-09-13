# See LICENSE for license details.

# VestaRV: dcsr.prv under a U-mode victim
# NEEDS A HARNESS: ./xrun_dbg.sh rv32ua-p-dbgprvmp dbg_prv.tcl. IT NEEDS debug.enable AND priv.umode IN THE SAME BUILD, which is config/castalia_debug.json, whose priv block sets trapCsr and umode EXPLICITLY rather than by inheritance. Run it as `SUITE=full make verify CONFIG=config/castalia_debug.json`. argus_debug.json stays minimal: this instrument has no N=18 obligation.
# dcsr.prv NEEDS A U-MODE VICTIM, because a prv that always reads 3 is indistinguishable from a correct one when every victim is in M-mode. The whole construction exists to put a hart genuinely outside M-mode when it is halted and to prove it was there.
# THE PROOF IS TWO-SIDED. The DM side, in dbg_prv.tcl, abstract-reads dcsr on the halted victim and requires prv == 0, which is only meaningful if the victim really was in U-mode, something the harness cannot know. The ARCHITECTURAL side is this file: the victim proves its own privilege TWICE, once before the halt and once after the resume, by executing `ecall` and having the M-mode handler record mcause. ECALL_FROM_U is cause 8 and ECALL_FROM_M is cause 11, so two 8s bracket the debug visit, the first saying the victim was in U when it parked and the second that dret put it back in U rather than M. A dret that silently promoted the hart would give 11 on the second, and nothing else in the series can see that.
# THE DELIVERY PATH MUST BE ASKED FOR: trapCsr defaults on but mtrapctl.LEGACY RESETS TO 1, so a fresh hart delivers traps down the legacy IVT path and mtvec is not consulted. Standard delivery is a per-hart firmware opt-in, `csrw 0x7C0, x0`, which the victim does before it drops to U. It never parks with `extinguish` afterwards, because clearing LEGACY on a hart that then extinguishes makes it UNWAKEABLE; that is avoided by construction, not by luck. Hart 0 is untouched and keeps the legacy path.
# Verdicts: a0 = 0xCAFEBABE means the victim was in U-mode before the halt and dret returned it to U-mode. a1 = 0x0D240001 a shared word did not read back; 0x0D240002 base-ISA sanity failed; 0x0D240003 the victim never finished, with a2 = PROG naming how far, 1 reached U-mode, 2 first ecall taken, 3 parked, 4 released, which is the expected result under a plain batch run; 0x0D240004 the first ecall did not report cause 8, so the victim was not in U-mode when it parked and the whole test would have measured nothing; 0x0D240005 the second ecall did not report cause 8, so dret did not return the hart to U-mode, and a2 = 11 means it came back in M, a privilege escalation through the debug visit; 0x0D240006 the victim's U-mode counter did not advance across the visit, so it never really resumed.
# NEGATIVE CONTROL -DDBGPRV_NC_SELF: the victim releases itself instead of waiting for the harness, so both ecalls, both mcause recordings, the U-mode counter and hart 0's whole assertion chain run with no debugger at all. A pass proves the privilege plumbing and the grading are LIVE; it makes no claim about dcsr.prv.
# N-agnostic: one victim, hart 1, at any NHARTS. Shared words, in the D-series debug acceptance band 0x10050-0x1007C, reused with this file's meanings under the one-image-per-sim rule: 0x10050 READY, 0x10054 REL (harness-planted to release the victim), 0x10058 DONE, 0x1005C CAUSE1 (want 8), 0x10060 CAUSE2 (want 8), 0x10064 UCNT, 0x10068 PROG.

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
