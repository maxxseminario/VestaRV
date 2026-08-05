# See LICENSE for license details.

#*****************************************************************************
# dbgstepmp.S   (D-series, D1 -- STEP EXACTNESS, dret, ebreakm, dscratch)
#-----------------------------------------------------------------------------
# BLIND-AUTHORED against d1_spec.md sections 1-2, FROZEN 2026-08-05, by an agent
# that has not seen and will never see the D1 implementation.  Committed
# polarity: CORRECT RTL = PASS (R-K5-8).
#
# NEEDS A HARNESS:  ./xrun_dbg.sh rv32ua-p-dbgstepmp dbg_step.tcl
# (one hierarchical force, on hart 1's dbg_haltreq, to get INTO debug mode the
# first time -- see dbghaltmp.S's header for why no software path exists).
# Everything after that first entry is driven by DEBUG CODE, not by the
# harness: the stub itself writes dpc, sets dcsr.step, drets, counts its own
# re-entries and finally arms dcsr.ebreakm.  So this file tests the parts of
# d1_spec.md section 2 that only debug mode can reach, with exactly ONE
# external event in the whole run.
#
# ---------------------------------------------------------------------------
# WHY THE STEP START POINT IS WRITTEN, NOT WAITED FOR
#   d1_spec.md 2: "If dcsr.step: exactly ONE instruction retires, then
#   re-entry with cause=step."  To measure that you must know WHICH instruction
#   was about to retire.  Waiting for a halt request to land on a chosen
#   instruction is a calibration, and a calibrated test passes on the machine
#   it was tuned on and silently stops covering anything afterwards (method
#   rule 7).  So the stub does not wait: on its FIRST entry it WRITES dpc with
#   the address of step_zone, read from a shared word the subject published
#   before parking.  The step sequence therefore starts at a structurally
#   determined address no matter where the halt request happened to land -- and
#   writing dpc is itself part of the spec (dpc is a read/write CSR in debug
#   mode) and part of what `dret` must honour.
#
# THE STEP MEASUREMENT IS TWO INDEPENDENT COUNTS, ON PURPOSE
#   step_zone is four identical `addi s1, s1, 1` instructions followed by a
#   store and an `ebreak`.  After four steps:
#     (a) the PC LEDGER.  Each re-entry's dpc must be exactly 4 past the
#         previous one (norvc region, so 4 is the whole instruction).  The stub
#         keeps the previous dpc in dscratch1 and records any deviation.
#     (b) the INSTRUCTION COUNT.  s1 must have been incremented EXACTLY four
#         times.  d1_spec.md 5 asks for step exactness "count instructions, not
#         cycles", and this is that count.
#   The two disagree under different mistakes and that is the point.  A step
#   that retires TWO instructions per re-entry gives dpc deltas of 8 -- caught
#   by (a) -- AND s1 = 8 after four entries -- caught by (b).  A step that
#   re-enters without retiring anything gives delta 0 and s1 = 0.  But a step
#   implemented as "re-enter after the NEXT instruction, and also let the one
#   at dpc go" gives clean deltas of 4 with s1 = 8: (a) alone would pass it.
#   Neither count is redundant.
#
# THE ebreakm PAIR, and where the other half lives
#   Entry 5 clears dcsr.step and SETS dcsr.ebreakm, then drets.  The subject
#   runs on and hits the `ebreak` at step_zone+20, which must now enter debug
#   with cause = 1 and dpc = the ebreak's own address (d1_spec.md 2: dpc <-
#   interrupted pc; for a synchronous breakpoint that is the ebreak itself,
#   NOT the instruction after -- which is why entry 6 advances dpc by 4 before
#   its dret, and why a build that already advanced it would resume past the
#   next instruction and be caught by the PROG word).
#   The dcsr.ebreakm = 0 polarity is NOT here: it cannot be, because the only
#   way to reach debug mode is a halt request and the only way to clear
#   ebreakm afterwards is more debug code.  It is dbgdenymp.S's hart 3, where
#   `ebreak` runs on a hart that has never been in debug mode and must take an
#   ordinary breakpoint exception.  Between the two files both polarities are
#   covered; neither file covers both.
#
# dscratch0/1 ARE THE STUB'S ONLY STATE, deliberately
#   The stub has no stack (debug code must not assume one), no static data of
#   its own, and it must survive being re-entered six times.  It keeps its
#   entry counter in dscratch0 and the previous dpc in dscratch1.  That is
#   what those CSRs are for, and it means a broken dscratch is not a silent
#   omission: the entry counter stops advancing and the run fails with
#   ENTRIES wrong rather than with a subtle miscount.
#
# ---------------------------------------------------------------------------
# VERDICT.  a0 = 0xCAFEBABE => single-step retires exactly one instruction per
# re-entry by both counts, dret honours a written dpc, ebreakm arms and
# disarms, ebreak-in-debug reports cause 1 at its own address, and dscratch0/1
# hold 32 bits across six debug entries.  a0 = 0xDEADBEEF with:
#   a1 = 0x0D57E001   THE SUBJECT NEVER ENTERED DEBUG MODE (a2 = ENTRIES = 0).
#                     Expected under xrun_batch.sh; under dbg_step.tcl it is
#                     THE finding -- cross-read the harness's STEPLOG lines.
#   a1 = 0x0D57E003   a step re-entry moved dpc by something other than 4
#                     (a2 = the offending delta with bit 31 set, a3 = LAST_DPC)
#   a1 = 0x0D57E004   the stepped instructions did not retire exactly once each
#                     (a2 = SUBJ_COUNTER; 4 expected).  8 = two per step,
#                     0 = none, anything else = the step count itself drifted.
#   a1 = 0x0D57E002   wrong number of debug entries (a2 = ENTRIES; 6 expected).
#                     Checked AFTER the two counts above, deliberately -- see
#                     the CHECK ORDER note at ds_check.
#   a1 = 0x0D57E005   the FIRST entry's cause was not 3 = haltreq (a2 = dcsr)
#   a1 = 0x0D57E006   the ebreak entry's cause was not 1 (a2 = dcsr)
#   a1 = 0x0D57E007   the ebreak entry's dpc was not the ebreak's own address
#                     (a2 = EBRK_DPC, a3 = the expected address)
#   a1 = 0x0D57E008   the subject never resumed past the ebreak (a2 = PROG):
#                     dret from the ebreak entry did not honour dpc+4
#   a1 = 0x0D57E009   dpc was not written back as asked on entry 1
#                     (a2 = the first recorded dpc, a3 = step_zone)
#   a1 = 0x0D57E00A   a shared word did not read back / base-ISA sanity failed
#   a1 = 0x0D57E00B   dpc did not WARL-mask an unaligned write (a2 = the value
#                     read back after writing &step_zone|3, a3 = step_zone).
#                     Bit 0 must be hardwired 0 and bits 31:2 must survive;
#                     bit 1 is ENABLE_COMPRESSED-dependent and is published,
#                     not asserted.
#
# NEGATIVE CONTROL -- how the non-debug half was SEEN TO WORK at unimplemented
#   HEAD:  -DDBGSTEP_NC_SELF.  The subject calls the stub as an ordinary
#   subroutine six times in a row and the stub, in this arm, uses ORDINARY
#   registers instead of dscratch0/1 and publishes synthetic dcsr/dpc values
#   shaped exactly like the real ones, walking step_zone by hand.  Every
#   publish, every hart-0 assertion and the whole verdict path then run for
#   real.  A PASS on that arm proves the instrument is LIVE (method rule 5);
#   it makes NO claim about debug mode and must never be quoted as a result.
#
# SHARED WORDS CLAIMED -- the same 12-word D1 band 0x10050-0x1007C that
#   dbgdenymp.S and dbghaltmp.S use, with this file's meanings (one image per
#   sim; the three never coexist):
#     0x10050 STEPPC       &step_zone, published by the subject, READ by the stub
#     0x10054 ENTRIES      debug entries so far (the stub's dscratch0 shadow)
#     0x10058 STEP_ERR     nonzero = a dpc delta other than 4 was seen
#     0x1005C SUBJ_COUNTER s1 after the stepped region
#     0x10060 EBRK_DPC     dpc at the ebreak entry
#     0x10064 EBRK_DCSR    dcsr at the ebreak entry
#     0x10068 ENTRY1_DCSR  dcsr at the FIRST (haltreq) entry
#     0x1006C PROG         subject progress; DONE = resumed past the ebreak
#     0x10070 LAST_DPC     the most recent dpc (diagnosis only)
#     0x10074 DPC_WARL     dpc read back after writing (&step_zone | 3)
#     0x10078-0x1007C      unused by this file
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_STEPPC     0x10050
#define SH_ENTRIES    0x10054
#define SH_STEP_ERR   0x10058
#define SH_SUBJCNT    0x1005C
#define SH_EBRK_DPC   0x10060
#define SH_EBRK_DCSR  0x10064
#define SH_ENTRY1_DCSR 0x10068
#define SH_PROG       0x1006C
#define SH_LAST_DPC   0x10070
#define SH_DPC_WARL   0x10074

#define PROG_DONE     0x0D57ED0E

#define DBG_ENTRY     0xBE00
#define TILE_WORDS    1024
#define ARM_BUDGET    40000
#define DRET_INSN     0x7B200073
#define DCSR_STEP     4             /* dcsr bit 2  */
#define DCSR_EBREAKM  0x8000        /* dcsr bit 15 */

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
    # clear the band and prove it read back
    # ==================================================================
    li   a1, 0x0D57E00A
    li   t0, 0x10050
    li   t1, 12
ds_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, ds_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, ds_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, ds_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    MP_LAUNCH_HART(1, tile_entry, TILE_WORDS)

    # ==================================================================
    # bounded wait for the subject to finish its whole debug programme.
    # PROG = DONE is written LAST, after the resume past the ebreak, so
    # one word means "all six entries happened and the subject came back".
    # ~40000 rounds of one shared load ~= 20 ms, inside the 100 ms watchdog.
    # ==================================================================
    li   s4, SH_PROG
    li   s5, PROG_DONE
    li   t6, ARM_BUDGET
ds_wait:
    lw   t2, 0(s4)
    beq  t2, s5, ds_check
    addi t6, t6, -1
    bnez t6, ds_wait

    # the programme did not complete: name how far it got
    li   t0, SH_ENTRIES
    lw   a2, 0(t0)
    li   a1, 0x0D57E001
    beqz a2, ds_fail                # never entered debug mode at all
    li   t0, SH_PROG
    lw   a3, 0(t0)
    li   a1, 0x0D57E008
    j    ds_fail

ds_check:
    # ==================================================================
    # CHECK ORDER IS LOAD-BEARING (R-D1-3(1), authorized instrument fix
    # by this file's author, 2026-08-05; F-K2b-1 precedent).
    #   The FINE checks come FIRST.  They were originally third and
    #   second, behind the coarse ENTRIES count, and the D1 validation
    #   pass measured what that costs: sealed mutant M3 (step retires two
    #   instructions per re-entry) perturbs the entry count as well as
    #   the step counts, so ENTRIES fired first and reported "wrong
    #   number of debug entries" -- true, but it MASKED both of the
    #   counts whose independence is this file's whole argument.  A
    #   coarse liveness check standing in front of two diagnosis checks
    #   will mask them for every mutant that also moves the coarse one.
    #   ENTRIES is now LAST of the three: it is the catch-all for a
    #   subject that got through the fine checks with the wrong number
    #   of entries, which is the only thing it can say that the other
    #   two cannot.
    #   THE GUARD THAT MAKES THIS SAFE: ds_check is reached only when
    #   PROG == PROG_DONE, i.e. the subject completed all six entries
    #   AND resumed past its ebreak.  Every word read below has
    #   therefore been written.  The "never entered debug mode at all"
    #   case (ENTRIES = 0) is caught upstream by the ARM_BUDGET arm,
    #   which reports 0x0D57E001, and is not what this ordering is
    #   about.
    # ==================================================================
    li   t0, SH_STEP_ERR            # FINE 1: every step moved dpc by exactly 4
    lw   a2, 0(t0)
    li   t0, SH_LAST_DPC
    lw   a3, 0(t0)
    li   a1, 0x0D57E003
    bnez a2, ds_fail

    li   t0, SH_SUBJCNT             # FINE 2: exactly four instructions retired
    lw   a2, 0(t0)
    li   t1, 4
    li   a1, 0x0D57E004
    bne  a2, t1, ds_fail

    li   t0, SH_ENTRIES             # COARSE: exactly six entries
    lw   a2, 0(t0)
    li   t1, 6
    li   a1, 0x0D57E002
    bne  a2, t1, ds_fail

    li   t0, SH_ENTRY1_DCSR         # entry 1 was a haltreq entry
    lw   a2, 0(t0)
    srli t3, a2, 6
    andi t3, t3, 7
    li   t4, 3
    li   a1, 0x0D57E005
    bne  t3, t4, ds_fail

    li   t0, SH_EBRK_DCSR           # entry 6 was an ebreak entry
    lw   a2, 0(t0)
    srli t3, a2, 6
    andi t3, t3, 7
    li   t4, 1
    li   a1, 0x0D57E006
    bne  t3, t4, ds_fail

    li   t0, SH_EBRK_DPC            # ...at the ebreak's OWN address
    lw   a2, 0(t0)
    la   a3, step_ebreak
    li   a1, 0x0D57E007
    bne  a2, a3, ds_fail

    li   t0, SH_STEPPC              # dpc was written back as asked
    lw   a2, 0(t0)
    la   a3, step_zone
    li   a1, 0x0D57E009
    bne  a2, a3, ds_fail

    li   t0, SH_DPC_WARL            # dpc masked bit 0 of an unaligned write
    lw   a2, 0(t0)
    la   a3, step_zone
    li   a1, 0x0D57E00B
    andi t3, a2, 1
    bnez t3, ds_fail                # bit 0 must be hardwired 0
    li   t4, -4
    and  t3, a2, t4
    bne  t3, a3, ds_fail            # and the upper 30 bits must survive

    RVTEST_PASS                     # a0 = 0xCAFEBABE

ds_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # ds_plant -- copy the debug stub to DEBUG_ENTRY_ADDR.  Clobbers t0-t3.
    # =====================================================================
ds_plant:
    la   t0, ds_stub_start
    la   t1, ds_stub_end
    li   t2, DBG_ENTRY
1:  lw   t3, 0(t0)
    sw   t3, 0(t2)
    addi t0, t0, 4
    addi t2, t2, 4
    blt  t0, t1, 1b
    ret

    # =====================================================================
    # THE DEBUG STUB.  Copied verbatim to DEBUG_ENTRY_ADDR (0xBE00).  It is
    # entered SIX times and must behave differently each time, so it is the
    # longest of the three D1 stubs -- about 60 words, which is why the
    # region reserved for it is 0xBE00-0xBEFF (64 words) with 0xBF00-0xBFEF
    # left clear below the stack at 0xBFF0.  If it ever outgrows that, move
    # DEBUG_ENTRY_ADDR down, do not creep toward the stack.
    #
    # Relocation rules as in the other two stubs: no `la`, no `auipc`, no
    # branch or jump leaving the block; every internal branch is
    # relocation-invariant; every absolute address arrives via `li`.
    # State lives in dscratch0 (entry counter) and dscratch1 (previous dpc).
    # Clobbers t0-t4 and a2-a5 only; the subject's s1 is never touched.
    # =====================================================================
    .option push
    .option arch, +zicsr
ds_stub_start:
#ifdef DBGSTEP_NC_SELF
    # CONTROL ARM: no debug CSRs exist on the tree this was authored against.
    # a6 stands in for dscratch0, a7 for dscratch1, and the subject drives the
    # walk by hand (see tile_h1).  Everything downstream runs for real.
    addi a6, a6, 1
    mv   t2, a6                     # n = entry counter
    mv   t0, s4                     # "dpc" -- the subject supplies it
    li   t1, 0x400000C3             # "dcsr": ver=4, cause=3 (haltreq), prv=3
    li   a2, 1
    beq  t2, a2, 3f
    li   t1, 0x40000103             # "dcsr": ver=4, cause=4 (step), prv=3
    li   a2, 6
    bne  t2, a2, 3f
    li   t1, 0x40000043             # "dcsr": ver=4, cause=1 (ebreak), prv=3
3:
#else
    csrr t2, dscratch0
    addi t2, t2, 1
    csrw dscratch0, t2              # n = this entry's index, 1-based
    csrr t0, dpc
    csrr t1, dcsr
#endif

    li   a5, SH_ENTRIES
    sw   t2, 0(a5)
    li   a5, SH_LAST_DPC
    sw   t0, 0(a5)

    # ---- entry 1: the haltreq entry.  Aim dpc at step_zone and arm step. --
    li   a2, 1
    bne  t2, a2, 4f
    li   a5, SH_ENTRY1_DCSR
    sw   t1, 0(a5)
    li   a5, SH_STEPPC
    lw   t3, 0(a5)                  # t3 = &step_zone (published by the subject)
#ifndef DBGSTEP_NC_SELF
    # dpc IALIGN-WARL probe (d1_spec.md 1: "31 b + IALIGN-WARL mask exactly as
    # mepc does it -- bit 0 hardwired, bit 1 per ENABLE_COMPRESSED").  Write
    # the target with BOTH low bits set and read it back.  Only bit 0 is
    # asserted, because bit 1's behaviour is ENABLE_COMPRESSED-dependent and
    # this file must stay knob-independent; the full read-back is published.
    li   t4, 3
    or   t4, t3, t4
    csrw dpc, t4
    csrr t4, dpc
    li   a4, SH_DPC_WARL
    sw   t4, 0(a4)
    csrw dpc, t3                    # ...and now the real target
    csrw dscratch1, t3              # previous dpc := the first step's address
    csrsi dcsr, DCSR_STEP
#else
    mv   a7, t3
    li   a4, SH_DPC_WARL
    sw   t3, 0(a4)
#endif
    sw   t3, 0(a5)                  # STEPPC now doubles as "dpc as written"
    j    9f

    # ---- entries 2..5: step re-entries.  dpc must advance by exactly 4. ---
4:  li   a2, 6
    beq  t2, a2, 6f
#ifndef DBGSTEP_NC_SELF
    csrr t4, dscratch1
#else
    mv   t4, a7
#endif
    sub  a3, t0, t4                 # delta
    li   a4, 4
    beq  a3, a4, 5f
    li   a5, SH_STEP_ERR
    li   a4, 0x80000000
    or   a3, a3, a4                 # bit 31 marks "this is a delta, not zero"
    sw   a3, 0(a5)
5:
#ifndef DBGSTEP_NC_SELF
    csrw dscratch1, t0
#else
    mv   a7, t0
#endif
    li   a2, 5
    bne  t2, a2, 9f
    # entry 5 is the last step: disarm step, arm ebreakm, run free
#ifndef DBGSTEP_NC_SELF
    csrci dcsr, DCSR_STEP
    li   a4, DCSR_EBREAKM
    csrs dcsr, a4
#endif
    j    9f

    # ---- entry 6: the ebreak entry.  Record it, disarm, resume PAST it. ---
6:  li   a5, SH_EBRK_DPC
    sw   t0, 0(a5)
    li   a5, SH_EBRK_DCSR
    sw   t1, 0(a5)
#ifndef DBGSTEP_NC_SELF
    li   a4, DCSR_EBREAKM
    csrc dcsr, a4
    addi t0, t0, 4                  # resume PAST the ebreak, not onto it
    csrw dpc, t0
#endif

9:
#ifdef DBGSTEP_NC_SELF
    ret
#else
    .word DRET_INSN
#endif
ds_stub_end:
    .option pop

    # ---- tile harts enter here (loader ABI: only sp is defined) ----------
tile_entry:
    li   sp, 0xBFF0
    jal  ra, ds_plant
    .option push
    .option arch, +zicsr
    csrr t3, mhartid
    .option pop
    li   t4, 1
    beq  t3, t4, tile_h1
tile_park:
    j    tile_park

tile_h1:
    li   s1, 0                      # the instruction counter under test
    la   t0, step_zone              # publish &step_zone for the stub
    li   t1, SH_STEPPC
    sw   t0, 0(t1)

#ifdef DBGSTEP_NC_SELF
    # CONTROL ARM: drive the six entries by hand.  s4 carries the "dpc" the
    # stub will see; the walk mirrors exactly what single-step would produce.
    li   a6, 0                      # "dscratch0"
    li   a7, 0                      # "dscratch1"
    la   s4, step_zone
    li   t2, DBG_ENTRY
    jalr ra, t2, 0                  # entry 1 (haltreq)
    addi s4, s4, 4
    li   t2, DBG_ENTRY
    jalr ra, t2, 0                  # entry 2
    addi s1, s1, 1
    addi s4, s4, 4
    li   t2, DBG_ENTRY
    jalr ra, t2, 0                  # entry 3
    addi s1, s1, 1
    addi s4, s4, 4
    li   t2, DBG_ENTRY
    jalr ra, t2, 0                  # entry 4
    addi s1, s1, 1
    addi s4, s4, 4
    li   t2, DBG_ENTRY
    jalr ra, t2, 0                  # entry 5
    addi s1, s1, 1
    li   t1, SH_SUBJCNT
    sw   s1, 0(t1)
    la   s4, step_ebreak
    li   t2, DBG_ENTRY
    jalr ra, t2, 0                  # entry 6 (ebreak)
    j    h1_done
#else
    # THE PARK.  Absorbing: the subject spins here until the harness's single
    # halt request lands.  Where inside this loop it lands does not matter --
    # the stub rewrites dpc on entry 1.
h1_wait:
    j    h1_wait
#endif

    # ---- THE STEPPED REGION.  Four identical increments, then a store, then
    # the ebreak.  norvc, so every instruction is exactly 4 bytes and a dpc
    # delta of 4 is the whole of one instruction.  Reached ONLY through the
    # stub's dret with dpc = step_zone.
step_zone:
    addi s1, s1, 1                  # +0
    addi s1, s1, 1                  # +4
    addi s1, s1, 1                  # +8
    addi s1, s1, 1                  # +12
    li   t1, SH_SUBJCNT             # +16  (the first free-running instruction)
    sw   s1, 0(t1)
    .option push
    .option arch, +zicsr
step_ebreak:
    ebreak                          # entry 6 must report cause 1 at THIS pc
    .option pop
h1_done:
    li   t1, SH_PROG                # reached only if dret honoured dpc+4
    li   t2, PROG_DONE
    sw   t2, 0(t1)
tile_h1_park:
    j    tile_h1_park

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
