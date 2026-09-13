# See LICENSE for license details.

# VestaRV: dark-hart test, dmstatus.unavail and halt-on-power-up
# NEEDS A HARNESS: ./xrun_dbg.sh rv32ua-p-dbgdarkmp dbg_dark.tcl. ONLY SOFTWARE CAN GATE A TILE: PWRCR lives at 0x4B00 on the shared bus and there is no DMI path to it, so hart 0 drives the whole power sequence and publishes each step while the harness watches what the DM says about a hart that is not there. Hart 0 launches hart 3, sees it counting, gates it, polls PWRSR until the nibble reads 3 for S_OFF, publishes DARK, waits for the harness, ungates, polls PWRSR back to 0 for S_ON, publishes WOKE, RE-LAUNCHES the tile, asserts it does not run, waits for the harness's resume and asserts it does. The harness holds setresethaltreq on hart 3 throughout and checks dmstatus during the dark window for anyunavail and not halted, not running, not nonexistent.
# THE ONE TRAP: a tile returning from power-down COLD-BOOTS. It re-runs the ROM and parks in WFI; it does NOT resume the test image. So "the victim's RAN flag is still 0 after the power-up" is true whether or not resethaltreq did anything, and asserting it alone would be decorative. THE DISCRIMINATOR IS THE RE-LAUNCH: hart 0 writes hart 3's loader row and sets its msip again, and a hart parked in the ROM's WFI takes the msip, loads the image and sets RAN, while a hart halted in debug mode does not, because it is not executing and the msip stays pending until it resumes.
# AND THE DISCRIMINATOR IS AN ORDERING, NOT A DURATION. Hart 0 races the victim's RAN flag against the harness's RACK flag, which the harness plants only after an actual dmcontrol.resumereq, and asserts which arrives first. A timed quiet window was tried twice and was wrong both times; the second version could make the real arm falsely pass on a chip with no debug module at all. No length is provably long enough here, because a cold ROM boot plus a loader copy is not a quantity this test can bound, so the duration had to go rather than be enlarged.
# Verdicts: a0 = 0xCAFEBABE means a tile really went dark, the management hart brought it back, and it came back HALTED rather than parked. a1 = 0x0D250001 a shared word did not read back; 0x0D250002 base-ISA sanity failed; 0x0D250003 the victim never started counting; 0x0D250004 the tile never reached S_OFF, which is a PWRCTRL finding rather than a DM one; 0x0D250005 the tile never came back to S_ON; 0x0D250006 the victim RAN after the re-launch while it should have been halted on reset, which is expected under a plain batch run with no DM and is the finding under dbg_dark.tcl; 0x0D250008 hart 0 could not read PWRCR back, so the power controller is not where this test thinks; 0x0D250009 neither the victim's first instruction nor the harness's resume ever arrived; 0x0D25000A the harness never acknowledged the dark window, which is a harness or plumbing finding and replaces a silent fall-through that ungated the tile on its own and made a correct DM read as one that never marks a hart unavail; 0x0D25000B the harness never armed, so the tile was never gated.
# NEGATIVE CONTROL -DDBGDARK_NC_NOHALT inverts the ordering assertion, requiring the victim to run BEFORE any resume, which is what a chip with no debug module does. Everything else runs for real, so a pass on that arm proves the power sequence and the grading are LIVE. It makes no claim about unavail or halt-on-reset.
# N-agnostic: one victim, hart 3, at any NHARTS >= 4, and PWRCR bit 3 and PWRSR0 nibble 3 are in the same place for every NHARTS <= 8, since pwr_ctrl packs eight harts per status word. Shared words, in the D-series debug acceptance band 0x10050-0x1007C, reused with this file's meanings under the one-image-per-sim rule: 0x10050 PHASE, 0x10054 RAN, 0x10058 CNT3, 0x1005C ACK (harness-planted, the dark window is a HANDSHAKE and hart 0 holds the tile at S_OFF until it arrives), 0x10060 DARK, 0x10064 WOKE, 0x10068 RACK (harness-planted after the resume), 0x1006C SRSAW, 0x10070 ALIVE, 0x10074 AACK (harness-planted once it has armed resethaltreq; hart 0 gates only after this), 0x10078 RANP, published and never asserted.

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"

#define SH_PHASE   0x10050
#define SH_RAN     0x10054
#define SH_CNT3    0x10058
#define SH_ACK     0x1005C
#define SH_DARK    0x10060
#define SH_WOKE    0x10064
#define SH_RACK    0x10068
#define SH_SRSAW   0x1006C
/* THE ARM HANDSHAKE (validation wave, 2026-08-06).  The harness used to
   detect the victim's liveness itself, by watching SH_CNT3 ADVANCE across two
   200 us samples -- and hart 0 CLEARS SH_CNT3 the moment it publishes DARK,
   so the harness raced the image for that word and lost: alive=0, the
   resethaltreq arm was skipped entirely, and every later leg failed for a
   reason that had nothing to do with the DM.  Liveness is now published by
   the hart that knows it (hart 0, which has already required CNT3 >= START_T)
   and the image WAITS for the harness's acknowledgement before it gates, so
   D1 reads a hart that is certainly still running and the arm certainly
   lands after reset release (R-D2-7(2)) and before the power-up.  Both
   directions are orderings; neither is a duration.                         */
#define SH_ALIVE   0x10070          /* hart 0 -> harness: victim is running  */
#define SH_AACK    0x10074          /* harness -> hart 0: armed, go ahead    */
#define SH_RANP    0x10078          /* hart 0: did the RESUMED victim run?   */

#define PWRCR      0x4B00
#define PWRSR0     0x4B04
#define VICTIM     3
#define GATE_BIT   (1 << VICTIM)
#define ST_SHIFT   (4 * VICTIM)     /* nibble position of hart 3 in PWRSR0 */

#define TILE_WORDS 1024
/* SELF-CALIBRATING BUDGETS.  The first draft used fixed round counts and its
   own liveness control caught them expiring before the tiles were up (the
   same defect dbgdmimp.S records).  Now: one GLOBAL poll budget bounds the
   whole test inside the 100 ms tb watchdog, liveness is an ABSOLUTE counter
   threshold, and -- the important one -- THE QUIET WINDOW IS MEASURED, NOT
   CHOSEN.  hart 0 times its OWN first launch (how many polls from
   MP_LAUNCH_HART until the victim sets RAN) and then waits QUIET_MULT times
   that long after the re-launch -- but never less than QUIET_MIN.
   THE FLOOR IS THERE BECAUSE THE MEASUREMENT UNDER-COUNTS, and that was
   measured too: the FIRST launch finds the tile already parked in the ROM's
   WFI, so it costs only the loader copy, while the SECOND finds it having to
   COLD-BOOT the whole ROM first (pwr_ctrl.vhd's S_UNISO comment).  4x the
   first latency was not enough and the control arm caught it -- the control
   REQUIRES the victim to run inside the window, so a window that is too
   short fails the control loudly instead of silently strengthening the real
   arm's assertion.  The control arm is therefore this window's calibration,
   and it is re-run whenever the number changes.                            */
#define GLOBAL_BUDGET 15000
#define START_T     16
#define QUIET_MULT  4
#define QUIET_MIN   20000           /* see QUIET WINDOW below                */
#define PWR_BUDGET  20000           /* PWRSR polls: a local, cheap register  */

/* ACK_BUDGET -- the dark window is held by a HANDSHAKE, not by a timeout
   (validation wave, 2026-08-06; R-D2-10 item 2's sibling defect).  The
   ACK wait used to draw on the SHARED global budget and, when it ran out,
   FALL THROUGH to the ungate -- so a harness that was slow to look found the
   tile already back on, and reported it as a DM that fails to mark a
   power-gated hart unavail.  Measured at this wave: with ACK never planted at
   all the image still ungated, 6.17 ms after publishing DARK; and with the
   window forced open, dmstatus for the dark hart reads unavail=1 halted=0
   running=0 nonexistent=0, which is exactly what D2/D3/D4 require.  So the
   DM was right and the fall-through was the whole finding.
   The wait is now on its OWN budget and its expiry is a VERDICT
   (0x0D25000A), never a silent ungate: an unmet handshake must be visible,
   not papered over.  Sized against the measured ~0.77 us per shared poll so
   it trips well inside the 100 ms tb watchdog with the run's own ~25 ms of
   work already spent.                                                      */
#define ACK_BUDGET  30000

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    .option push
    .option arch, +zicsr
    csrr s10, mhartid
    .option pop
    bnez s10, tile_entry

    li   a1, 0x0D250001
    li   t0, SH_PHASE
    li   t1, 12
dk_clr:
    sw   x0, 0(t0)
    lw   t2, 0(t0)
    bnez t2, dk_fail
    addi t0, t0, 4
    addi t1, t1, -1
    bnez t1, dk_clr

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    li   a1, 0x0D250002
    bne  t2, t3, dk_fail

    # PWRCR must read back what we can write, or nothing below means anything
    li   s2, PWRCR
    sw   x0, 0(s2)
    lw   a2, 0(s2)
    li   a1, 0x0D250008
    bnez a2, dk_fail

    MP_STAGE_IMAGE(TILE_WORDS)
    li   s11, GLOBAL_BUDGET         # ONE budget for every phase below
    mv   s7, s11                    # ...and a mark, to MEASURE the latency
    MP_LAUNCH_HART(VICTIM, tile_entry, TILE_WORDS)

    # ---- 1. the victim must be ALIVE before it can meaningfully go dark ----
    # This loop also TIMES the launch: s7 ends up holding the number of polls
    # the bootrom loader needed to get this hart from msip to its first
    # instruction, and that measurement -- not a constant -- sets the quiet
    # window in step 4.
    li   t0, SH_PHASE
    li   t1, 1
    sw   t1, 0(t0)
dk_alive:
    li   t0, SH_CNT3
    lw   s4, 0(t0)
    li   t1, START_T
    bge  s4, t1, dk_isalive
    addi s11, s11, -1
    bnez s11, dk_alive
    mv   a2, s4
    li   a1, 0x0D250003
    j    dk_fail

dk_isalive:
    sub  s7, s7, s11                # L = polls consumed by launch + START_T
    li   t1, QUIET_MULT
    mul  s7, s7, t1                 # 4x the measured launch latency...
    li   t0, QUIET_MIN
    bge  s7, t0, 1f
    mv   s7, t0                     # ...but never below QUIET_MIN
1:
    # ---- 1c. THE ARM HANDSHAKE.  Publish "the victim is running" and hold
    # here until the harness has read D1 and armed resethaltreq.  The harness
    # plants AACK unconditionally (so the no-DM FAIL leg still completes its
    # power sequence), and expiry is a verdict, never a silent gate.
    li   t0, SH_ALIVE
    li   t1, 1
    sw   t1, 0(t0)
    li   t4, ACK_BUDGET
dk_aackwait:
    li   t0, SH_AACK
    lw   t1, 0(t0)
    bnez t1, dk_armed
    addi t4, t4, -1
    bnez t4, dk_aackwait
    li   a1, 0x0D25000B             # the harness never armed
    j    dk_fail
dk_armed:
    # ---- 2. GATE it.  pwr_ctrl's software contract asks for a quiesced tile;
    # this one is spinning, which the block documents as survivable (a clamped
    # req is a released req to the wait-for-release arbiter) and which shpwr's
    # HAMMER leg already exercises.  Cold-gating destroys the tile's work --
    # that is what cold-gating MEANS, and this test wants exactly that.
    li   t0, SH_PHASE
    li   t1, 2
    sw   t1, 0(t0)
    li   t1, GATE_BIT
    sw   t1, 0(s2)                  # PWRCR |= 1 << 3

    li   t6, PWR_BUDGET
    li   s5, PWRSR0
dk_off:
    lw   s6, 0(s5)
    srli t2, s6, ST_SHIFT
    andi t2, t2, 0xF
    li   t3, 3                      # S_OFF
    beq  t2, t3, dk_isdark
    addi t6, t6, -1
    bnez t6, dk_off
    li   t0, SH_SRSAW
    sw   s6, 0(t0)
    mv   a2, s6
    li   a1, 0x0D250004
    j    dk_fail

dk_isdark:
    li   t0, SH_SRSAW
    sw   s6, 0(t0)
    li   t0, SH_DARK
    li   t1, 1
    sw   t1, 0(t0)
    # clear the victim's traces so a post-wake retire is detectable
    li   t0, SH_RAN
    sw   x0, 0(t0)
    li   t0, SH_CNT3
    sw   x0, 0(t0)

    # ---- 3. hold the dark window until the harness says it has looked -----
    # A HANDSHAKE, on its own budget.  The harness plants ACK unconditionally
    # AFTER its dark-window reads -- including on a chip with no DM, so the
    # FAIL leg still completes its power sequence -- and the ONLY way past
    # this loop is that plant.  Expiry is a verdict, not a fall-through: an
    # image that ungates on its own turns "the harness was slow" into "the DM
    # does not report unavail", which is the mis-attribution this whole
    # protocol exists to prevent, and it did exactly that at SS16.1.
    li   t4, ACK_BUDGET
dk_ackwait:
    li   t0, SH_ACK
    lw   t1, 0(t0)
    bnez t1, dk_ungate
    addi t4, t4, -1
    bnez t4, dk_ackwait
    li   t0, SH_SRSAW
    lw   a2, 0(s5)
    sw   a2, 0(t0)
    li   a1, 0x0D25000A             # the harness never acknowledged the window
    j    dk_fail

dk_ungate:
    li   t0, SH_PHASE
    li   t1, 3
    sw   t1, 0(t0)
    sw   x0, 0(s2)                  # PWRCR = 0

    li   t6, PWR_BUDGET
dk_on:
    lw   s6, 0(s5)
    srli t2, s6, ST_SHIFT
    andi t2, t2, 0xF
    beqz t2, dk_ison                # S_ON
    addi t6, t6, -1
    bnez t6, dk_on
    li   t0, SH_SRSAW
    sw   s6, 0(t0)
    mv   a2, s6
    li   a1, 0x0D250005
    j    dk_fail

dk_ison:
    li   t0, SH_SRSAW
    sw   s6, 0(t0)
    li   t0, SH_WOKE
    li   t1, 1
    sw   t1, 0(t0)

    # ---- 4. THE DISCRIMINATOR.  Re-launch the tile exactly as before.  A
    # ROM-PARKED hart takes the msip and runs; a HALTED hart cannot.
    li   t0, SH_PHASE
    li   t1, 4
    sw   t1, 0(t0)
    MP_LAUNCH_HART(VICTIM, tile_entry, TILE_WORDS)

    # ---- THE DISCRIMINATOR IS AN ORDERING, NOT A WINDOW ------------------
    # This was a timed "quiet window" in the first two drafts and BOTH were
    # wrong, in the two opposite directions, and the control arm caught both:
    # a window that is too short lets the real arm FALSELY PASS at
    # unimplemented HEAD (RAN is 0 merely because the tile has not finished
    # cold-booting yet), and there is no length that is provably long enough,
    # because a cold ROM boot plus a loader copy is not a quantity this test
    # can bound.  A committed-polarity instrument that can pass on a chip with
    # no debug module is worse than no instrument at all.
    #
    # So the timing is gone.  hart 0 races TWO shared words against each
    # other and asserts their ORDER:
    #     RAN  becomes 1  =  the victim executed something
    #     RACK becomes 1  =  the harness resumed the victim (it plants RACK
    #                        ONLY after an actual dmcontrol.resumereq)
    # If RAN wins, the victim ran with nobody having resumed it -- nothing
    # halted it on reset.  If RACK wins, the victim was still halted when the
    # debugger let it go, and it must then run.  Neither branch contains a
    # duration, so there is nothing to calibrate and nothing that can rot.
    li   t0, SH_PHASE
    li   t1, 5
    sw   t1, 0(t0)
dk_race:
    li   t0, SH_RACK
    lw   t1, 0(t0)
    bnez t1, dk_wasresumed
    li   t0, SH_RAN
    lw   a2, 0(t0)
    bnez a2, dk_ranfirst
    addi s11, s11, -1
    bnez s11, dk_race
    li   t0, SH_CNT3                # neither ever happened
    lw   a3, 0(t0)
    li   a1, 0x0D250009
    j    dk_fail

dk_ranfirst:
    li   t0, SH_CNT3
    lw   a3, 0(t0)
#ifdef DBGDARK_NC_NOHALT
    # CONTROL ARM: with no debug module nothing holds resethaltreq, so the
    # tile parks in the ROM, takes the re-launch msip and RUNS long before
    # any resume.  Requiring THAT proves the whole power-cycle-and-relaunch
    # sequence -- gate, S_OFF, un-gate, S_ON, re-launch, execute -- works.
    j    dk_pass
#else
    li   a1, 0x0D250006             # it ran with nobody resuming it
    j    dk_fail
#endif

dk_wasresumed:
#ifdef DBGDARK_NC_NOHALT
    # CONTROL ARM: reaching here means the victim did NOT run before the
    # (nonexistent) resume, which on a chip with no debug module cannot
    # happen for any reason this test understands.
    li   t0, SH_CNT3
    lw   a3, 0(t0)
    li   a1, 0x0D250006
    j    dk_fail
#endif
    # ---- THE POST-RESUME RUN IS PUBLISHED, NOT ASSERTED ------------------
    # (validation wave, 2026-08-06; the SS16.2 idiom, and rule 9.)
    # This leg used to REQUIRE the resumed victim to execute.  Measured at
    # this wave, on a DM that halts and resumes exactly per spec, it cannot:
    #   * the victim is halted at reset RELEASE, dpc = 0x00000004 -- one
    #     instruction into the bootrom, long before the ROM's park path has
    #     armed the tile's IVT slot 83 (measured: TCM[0x814C] = 0x00000000
    #     while halted);
    #   * this image raised the re-launch msip while the victim was halted,
    #     which is the point of the leg -- but an msip is a LEVEL, so it is
    #     still asserted at the `dret`;
    #   * traced at 100 ns: dret -> pc = 0x00000004 -> IVT slot 83 at
    #     0x0000814C -> TRAP_STATE, terminal.  The hart takes the pending
    #     interrupt on its first instruction back and lands on a slot the
    #     bootrom never got to arm.
    # That is a real park/wake interaction (CLAUDE.md's PARK/WAKE HAZARD
    # neighbourhood) and it belongs in the D-series ledger, but it is NOT a
    # Debug Module defect and this instrument must not report it as one.
    # THE ASSERTION IS THE ORDERING -- RACK before RAN, i.e. the victim did
    # not run before the debugger released it, which IS halt-on-power-up --
    # and it is intact: RACK is planted only after a real `resumereq`, so a
    # chip with no DM can never reach here.  Whether the released hart then
    # executes is published into RANP for the harness to print.
dk_ranwait:
    li   t5, ACK_BUDGET
1:
    li   t0, SH_RAN
    lw   a2, 0(t0)
    bnez a2, 2f
    addi t5, t5, -1
    bnez t5, 1b
2:
    li   t0, SH_RANP
    sw   a2, 0(t0)
    j    dk_pass

dk_pass:
    li   t0, SH_PHASE
    li   t1, 6
    sw   t1, 0(t0)
    RVTEST_PASS

dk_fail:
    RVTEST_FAIL

    # ---- the victim (hart 3) --------------------------------------------
    # RAN is set on the FIRST instruction group it executes, so "did this hart
    # retire anything of its own?" is one shared word.
tile_entry:
    li   sp, 0xBFF0
    li   t0, SH_RAN
    li   t1, 1
    sw   t1, 0(t0)
    li   t5, SH_CNT3
tile_loop:
    lw   t0, 0(t5)
    addi t0, t0, 1
    sw   t0, 0(t5)
    j    tile_loop

    # NOTE: RVTEST_CODE_END is `unimp` in this env (it traps) -- never fall
    # through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
