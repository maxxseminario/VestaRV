# See LICENSE for license details.

#*****************************************************************************
# dbgabsmp.S   (D-series, D2 -- ABSTRACT COMMANDS: GPR, CSR, progbuf memory,
#               postexec, and the EXCEPTION cmderr)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d2_spec.md sections 3-4, FROZEN 2026-08-05, by an agent
# that has not seen and will never see the D2 implementation.  Committed
# polarity: CORRECT RTL = PASS (R-K5-8).
#
# NEEDS A HARNESS:  ./xrun_dbg.sh rv32ua-p-dbgabsmp dbg_abs.tcl
#
# ---------------------------------------------------------------------------
# THE SHAPE OF THE PROOF, AND WHY IT IS TWO-SIDED
#   An abstract command has two observable faces and a DM can get one right
#   while getting the other wrong:
#     * the DMI face -- data0 comes back with the right value, cmderr is 0,
#       busy cleared.  The harness checks that half (dbg_abs.tcl, A-checks).
#     * the ARCHITECTURAL face -- the victim's register file and memory really
#       changed, and really did NOT change in any other way.  A DM that
#       answers data0 from a cache, or that writes the wrong register, or that
#       leaves the hart's state mangled, passes the DMI face.
#   This file is the architectural face.  The victim sets up known state,
#   parks, is worked on by the debugger, is resumed, and then READS BACK its
#   OWN state with ordinary instructions and publishes what it found.  hart 0
#   grades it.  Neither half is redundant, and neither can be forged by the
#   other.
#
# THE FIVE THINGS BEING PROVED, and the code that proves each
#   1. ABSTRACT GPR READ.  The victim leaves s1 = GPR_MAGIC before parking.
#      The harness abstract-reads x9 and must get GPR_MAGIC.  After the
#      resume, the victim publishes s1 AGAIN: an abstract READ must not be
#      destructive, and OBS_S1 is what catches a DM whose dscratch save/
#      restore drops a register.
#   2. ABSTRACT GPR WRITE.  s2 starts at 0.  The harness abstract-writes
#      x18 = ABS_WR_MAGIC.  The victim publishes s2 after resume.
#   3. ABSTRACT CSR READ+WRITE.  mscratch (0x340) starts at CSR_MAGIC; the
#      harness reads it, then writes CSR_WR_MAGIC; the victim publishes what
#      it reads back.  mscratch is chosen because it is architecturally inert
#      -- writing it cannot perturb anything else the test depends on.
#   4. PROGBUF MEMORY ROUND TRIP -- DD5's memory answer, exercised.  There is
#      no access-memory abstract command on this chip (cmdtype 2 returns
#      NOT_SUPPORTED by design), so a debugger moves memory by loading a
#      program buffer with `lw`/`sw` and running it on the hart.  The harness
#      points a6/a7 at MEM_SRC/MEM_DST by abstract GPR writes, loads progbuf0
#      = lw / progbuf1 = sw, and issues a POSTEXEC command.  MEM_DST must
#      contain MEM_MAGIC afterwards -- and the victim reads it back in band,
#      so the word really landed in the shared RAM the hart sees and not just
#      in the DM.
#      NOTE this also exercises impebreak: progbufsize is 2 and the sequence
#      needs a third word to return, which is the implicit ebreak's whole job.
#   5. THE EXCEPTION cmderr.  An abstract read of an unimplemented CSR must
#      set cmderr = EXCEPTION and leave the hart HALTED -- not wedged, not
#      resumed, not silently zero.  The harness checks cmderr and re-reads
#      dmstatus; this file's contribution is that everything AFTER it still
#      works, which is the real requirement: a hart that survives a debug-mode
#      exception must still answer the next abstract command and must still
#      resume.  So the exception leg is issued BEFORE the resume, and a
#      correct run reaches DONE anyway.
#
# THE VICTIM'S PARK, and the register discipline it needs
#   The victim spins reading the shared word REL, which the HARNESS plants
#   (a forced shared word -- the measured mechanism; see dbg_bfm.tcl).  The
#   loop body recomputes its address with `li` every round and holds no live
#   register, so the debugger's visits -- which clobber t-registers, a6, a7
#   and whatever the DM's own sequence uses -- cannot perturb it.  It touches
#   NO s0: Spike's reference sequence saves s0 to dscratch0, and a victim that
#   depended on s0 would be testing the DM's save/restore with an assertion
#   that could not distinguish it from a clobber.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => every abstract face landed architecturally.
#   a1 = 0x0D220001   a shared word did not read back
#   a1 = 0x0D220002   base-ISA sanity failed
#   a1 = 0x0D220003   THE VICTIM NEVER FINISHED (a2 = PROG).  Under
#                     xrun_batch.sh this is the expected result and means
#                     nothing; under dbg_abs.tcl it is THE finding -- PROG
#                     names how far it got: 1 = set up and parked (so the
#                     debugger never released it), 2 = released.
#   a1 = 0x0D220004   abstract GPR WRITE did not land (a2 = s2 observed,
#                     a3 = expected)
#   a1 = 0x0D220005   abstract CSR WRITE did not land (a2 = mscratch observed)
#   a1 = 0x0D220006   the progbuf lw/sw round trip did not move the word
#                     (a2 = MEM_DST, a3 = MEM_MAGIC)
#   a1 = 0x0D220007   an abstract READ was DESTRUCTIVE: s1 no longer holds
#                     GPR_MAGIC after the visits (a2 = s1 observed)
#   a1 = 0x0D220008   MEM_SRC was corrupted (a2 = MEM_SRC): the progbuf wrote
#                     the wrong way round
#
# NEGATIVE CONTROL -- how the non-DM half was SEEN TO WORK at unimplemented
#   HEAD:  -DDBGABS_NC_SELF.  The victim performs, ON ITSELF, exactly the
#   architectural effects the debugger would have performed (s2, mscratch,
#   MEM_SRC -> MEM_DST) and then releases itself instead of waiting for REL.
#   Every publish, hart 0's whole assertion chain and the verdict path then
#   run for real.  A PASS on that arm proves the instrument is LIVE (method
#   rule 5).  It is a CONTROL: it makes no claim about the DM and must never
#   be quoted as a D2 result.
#
# N-AGNOSTIC.  ONE victim, hart 1, at any NHARTS; no shared word is indexed by
#   hartid.  Argus harts 2-17 stay parked in the bootrom.
#
# SHARED WORDS CLAIMED -- the D-series debug acceptance band 0x10050-0x1007C,
#   REUSED with this file's meanings (one image per sim; the D-series debug
#   instruments never coexist):
#     0x10050  READY     victim: state set up, about to park
#     0x10054  REL       the harness plants 1 here to release the victim
#     0x10058  DONE      victim: verification complete
#     0x1005C  OBS_S2    s2 as the victim read it after the resume
#     0x10060  OBS_MSCR  mscratch as the victim read it after the resume
#     0x10064  MEM_SRC   the progbuf load's source word (holds MEM_MAGIC)
#     0x10068  MEM_DST   the progbuf store's destination word
#     0x1006C  OBS_S1    s1 after the visits (must still be GPR_MAGIC)
#     0x10070  PROG      victim progress (1 = parked, 2 = released, 3 = done)
#     0x10074-0x1007C  unused by this file
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_READY     0x10050
#define SH_REL       0x10054
#define SH_DONE      0x10058
#define SH_OBS_S2    0x1005C
#define SH_OBS_MSCR  0x10060
#define SH_MEM_SRC   0x10064
#define SH_MEM_DST   0x10068
#define SH_OBS_S1    0x1006C
#define SH_PROG      0x10070

#define GPR_MAGIC    0x0AB50001
#define CSR_MAGIC    0x0AB50002
#define MEM_MAGIC    0x0AB50003
#define ABS_WR_MAGIC 0x0AB5FEED     /* the harness abstract-writes this to s2 */
#define CSR_WR_MAGIC 0x0AB5BEEF     /* ...and this to mscratch               */
#define DONE_MAGIC   0x0AB5D0E5

#define TILE_WORDS   1024
#define ARM_BUDGET   40000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    # ==================================================================
    # clear every claimed word and prove it read back
    # ==================================================================
    li   a1, 0x0D220001
    li   t0, SH_READY
    li   t1, 12
da_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, da_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, da_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D220002
    bne  t2, t3, da_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for the victim's whole programme.  DONE is written LAST,
    # so one word means "released, read back and published".
    # ~40000 rounds of one shared load ~= 20 ms, inside the 100 ms watchdog.
    # ==================================================================
    li   s4, SH_DONE
    li   s5, DONE_MAGIC
    li   t6, ARM_BUDGET
da_wait:
    lw   t2, 0(s4)
    beq  t2, s5, da_check
    addi t6, t6, -1
    bnez t6, da_wait
    li   t0, SH_PROG
    lw   a2, 0(t0)
    li   a1, 0x0D220003
    j    da_fail

da_check:
    li   t0, SH_OBS_S2              # 2. the abstract GPR WRITE
    lw   a2, 0(t0)
    li   a3, ABS_WR_MAGIC
    li   a1, 0x0D220004
    bne  a2, a3, da_fail

    li   t0, SH_OBS_MSCR            # 3. the abstract CSR WRITE
    lw   a2, 0(t0)
    li   a3, CSR_WR_MAGIC
    li   a1, 0x0D220005
    bne  a2, a3, da_fail

    li   t0, SH_MEM_DST             # 4. the progbuf lw/sw round trip
    lw   a2, 0(t0)
    li   a3, MEM_MAGIC
    li   a1, 0x0D220006
    bne  a2, a3, da_fail

    li   t0, SH_OBS_S1              # 1. the abstract READ was NOT destructive
    lw   a2, 0(t0)
    li   a3, GPR_MAGIC
    li   a1, 0x0D220007
    bne  a2, a3, da_fail

    li   t0, SH_MEM_SRC             # ...and the copy went the right way
    lw   a2, 0(t0)
    li   a3, MEM_MAGIC
    li   a1, 0x0D220008
    bne  a2, a3, da_fail

    RVTEST_PASS                     # a0 = 0xCAFEBABE

da_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # ---- the victim (hart 1) --------------------------------------------
tile_entry:
    li   sp, 0xBFF0
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    bne  t3, t4, tile_park

    li   s1, GPR_MAGIC              # 1. the abstract read's subject
    li   s2, 0                      # 2. the abstract write's target
    .option push
    .option arch, +zicsr
    li   t0, CSR_MAGIC              # 3. the abstract CSR read's subject
    csrw mscratch, t0
    .option pop
    li   t0, SH_MEM_SRC             # 4. the progbuf copy's source
    li   t1, MEM_MAGIC
    sw   t1, 0(t0)
    li   t0, SH_MEM_DST
    sw   x0, 0(t0)

    li   t0, SH_PROG
    li   t1, 1
    sw   t1, 0(t0)
    li   t0, SH_READY
    li   t1, 1
    sw   t1, 0(t0)                  # publish LAST: READY means all of it

#ifdef DBGABS_NC_SELF
    # CONTROL ARM: no DM exists on the tree this was authored against, so the
    # victim performs the debugger's architectural effects on itself.  Nothing
    # here claims anything about abstract commands; it proves the publish,
    # the read-back and hart 0's whole assertion chain execute.
    li   s2, ABS_WR_MAGIC
    .option push
    .option arch, +zicsr
    li   t0, CSR_WR_MAGIC
    csrw mscratch, t0
    .option pop
    li   t0, SH_MEM_SRC
    lw   t1, 0(t0)
    li   t0, SH_MEM_DST
    sw   t1, 0(t0)
    li   t0, SH_REL                 # ...and release itself
    li   t1, 1
    sw   t1, 0(t0)
#endif

    # THE PARK.  The loop holds no live register: the address is recomputed
    # every round, so a debug visit that clobbers t0/t1 is invisible to it.
da_park:
    li   t0, SH_REL
    lw   t1, 0(t0)
    beqz t1, da_park

    li   t0, SH_PROG
    li   t1, 2
    sw   t1, 0(t0)

    # ---- read back what the debugger did, with ordinary instructions ----
    li   t0, SH_OBS_S2
    sw   s2, 0(t0)
    li   t0, SH_OBS_S1
    sw   s1, 0(t0)
    .option push
    .option arch, +zicsr
    csrr t1, mscratch
    .option pop
    li   t0, SH_OBS_MSCR
    sw   t1, 0(t0)

    li   t0, SH_PROG
    li   t1, 3
    sw   t1, 0(t0)
    li   t0, SH_DONE
    li   t1, DONE_MAGIC
    sw   t1, 0(t0)                  # publish LAST
tile_h1_park:
    j    tile_h1_park

tile_park:
    j    tile_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
