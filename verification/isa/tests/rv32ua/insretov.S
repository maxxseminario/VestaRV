# See LICENSE for license details.

#*****************************************************************************
# insretov.S  (F-series fix pass, W3 -- the DETECTOR for findings F1 and F1+)
#-----------------------------------------------------------------------------
# SUBJECT: minstret (CSR 0xB02).  Unlike the W2 detectors, which deliberately
# used mcycle to stay orthogonal to this wave, this test's subject IS the
# counter under repair.
#
# THE RTL UNDER TEST (hdl/common/vesta/vesta.vhd, re-grepped on rtl-fixpass
# HEAD 03ee011 -- every line number below was read, not inherited):
#
#   :1124  en_cg_insret <= '1' when next_state = EXECUTE else '0';
#   :1125  cg_insret: ClkGate(ClkIn => not clk_cpu, En => en_cg_insret,
#   :1129                     ClkOut => inst_retired);
#   :1132  -- inst_retired <= clk_inst_ret when en_clk_cpu = '1' else '0';
#                                                     <- the author's disabled fix
#   csr_unit.vhd:681  if inst_retired = '1' and not (...mcountinhibit(2)...) then
#   csr_unit.vhd:682      minstret <= minstret + 1;      -- on rising_edge(CLK)
#
# WHAT THAT ACTUALLY COUNTS.  ClkGate is a latch-then-AND
# (hdl/common/sim/ClkGate.vhd): ClkSync follows En while ClkIn='0' and holds
# otherwise, ClkOut = ClkSync and ClkIn.  With ClkIn = not clk_cpu the latch is
# transparent while clk_cpu is HIGH and inst_retired = ClkSync while clk_cpu is
# LOW.  csr_unit samples on rising_edge(clk), at which instant clk (and so
# clk_cpu) is low, so it sees the value en_cg_insret had during the last
# clk_cpu high phase.  Therefore, un-stalled:
#
#     minstret increments once per clk_cpu edge that LANDS THE FSM IN EXECUTE
#     == once per EXECUTE cycle,  NOT once per architectural retire.
#
# and while clk_cpu is gated off (en_clk_cpu='0', vesta.vhd:1108) the latch
# cannot be re-loaded, so inst_retired STICKS at whatever it last held and
# minstret increments once per FREE-RUNNING clk cycle for the entire stall.
# That is F1+, and it fires exactly when the state that stalls has
# next_state = EXECUTE -- i.e. on an INSTRUCTION FETCH from the shared window.
#
# THE FIX (w3_spec.md 2) replaces both halves with the v1_retire_enumeration.md
# 3-R0 retire condition, gated by en_clk_cpu.  So post-fix minstret counts
# ARCHITECTURAL RETIRES.  This test measures the gap.
#
# ---------------------------------------------------------------------------
# BRACKET-READ ACCOUNTING -- state it or the test lies
# ---------------------------------------------------------------------------
# A bracket is  csrr t0,minstret / <payload> / csrr t1,minstret ; d = t1-t0.
# `csrr` is csrrs rd,csr,x0, and csr_unit.vhd:456 leaves csr_write_en '0' for
# the rs1=x0 form, so the read neither writes minstret nor (P3's fixed
# behaviour) freezes it.  rd is captured at the SAME clk edge at which minstret
# increments; the two reads are phased identically with respect to their own
# increment, so exactly ONE of the two bracket reads contributes its own count
# to d and the other cancels.  Which one it is depends on read/increment
# phasing and affects no delta.  Hence, model-independently,
#
#     d = 1 (one bracket read's own increment) + <payload increments>
#
# and an EMPTY bracket must read exactly 1.  Leg 0 asserts that; it is the
# accounting anchor for every other leg, and it is the ONLY absolute number
# this whole test rests on.
#
# The same rule is what makes legs 4 and 4b comparable: leg 4's bracket spans
# {one bracket read, the iret}; leg 4b's spans {one bracket read, the iret,
# the IVT slot's own `jal zero,<isr>`}, because the second trap vectors
# through the IVT and the first return does not.  Exactly one architectural
# instruction more -- so d_fb - d4 must be exactly 1, whatever the phasing.
#
# ---------------------------------------------------------------------------
# WHY EVERY DISCRIMINATING CHECK IS A MATCHED PAIR (R-W2-2: do not calibrate)
# ---------------------------------------------------------------------------
# Each leg is TWO brackets containing the SAME NUMBER OF ARCHITECTURAL
# INSTRUCTIONS and differing ONLY by the mechanism under test.  Post-fix the
# two deltas must be EQUAL; pre-fix they differ by the over-count.  No leg
# depends on an absolute instruction count, on interrupt latency, or on any
# number tuned to this machine.  The seven ABSOLUTE checks are all on CONTROL
# quantities that contain no over-count mechanism and therefore have identical
# pre- and post-fix values; they exist only to stop a degenerate "counter
# stopped counting" fix from satisfying the equalities vacuously.  Five of them
# are control halves of a pair (d0, d1a, d2n, d5lt, d5ct); the other two are
# legs 4 and 4b, which w3_spec.md 6.3 rules are correct as they stand.
#
#   leg 0  accounting anchor   empty bracket                      d0  == 1
#   leg 1  STRADDLE            c.nop / 32-bit @halfword / c.nop   d1s == d1a
#                        vs    c.nop / c.nop / 32-bit @word
#   leg 2  FENCE               fence          vs  nop             d2f == d2n
#   leg 3  AMO                 amoadd.w       vs  nop             d3a == d2n
#   leg 4  IRET (resume arm)   minstret across the ISR's last     d4  == 2
#                              read -> iret -> resume                 CONTROL
#   leg 4b IRET (re-park arm)  same, but the ISR does NOT ignite  d_fb ==
#                              so IRQ_REST re-parks the hart          d4 + 1
#                              (F1-b; the +1 is the IVT jal)          CONTROL
#   leg 5a SHARED DATA         8 lw from shared vs 8 lw from TCM   d5ls == d5lt
#   leg 5b SHARED FETCH        call an 8-instruction routine       d5cs == d5ct
#                              resident in SHARED RAM vs the
#                              byte-identical TCM copy
#
# leg 5b is F1+'s dominant term: the fetch of every instruction in the shared
# copy stalls clk_cpu in a state whose next_state is EXECUTE.
#
# HONEST NOTE ON LEGS 2 AND 3.  Read the FSM before believing the inherited
# claim that a FENCE or an AMO is double-counted.  vesta.vhd:3300 FENCE_WAIT
# and :2988 AMO_COMPLETE are the "fetch the next instruction" states
# (pc_en='1'), so a FENCE occupies exactly ONE EXECUTE cycle
# (EXECUTE -> FENCE_WAIT -> EXECUTE-of-the-next-instruction) and an AMO
# exactly one (EXECUTE -> AMO_READ -> AMO_WRITEBACK -> AMO_COMPUTE ->
# AMO_WRITE -> AMO_COMPLETE -> EXECUTE-of-the-next-instruction).  One EXECUTE
# cycle, one 3-R0 retire (at EXECUTE for the FENCE, at AMO_WRITE for the AMO)
# -- so both are predicted to count CORRECTLY pre-fix, and legs 2 and 3 are
# predicted GREEN in both polarities.  They are kept because a measured
# equality is the evidence for that correction, and because they must not
# REGRESS: post-fix they still have to hold.
#
# ---------------------------------------------------------------------------
# Verdict / a1 codes
# ---------------------------------------------------------------------------
#   a0=0xCAFEBABE                  PASS (post-fix expectation)
#   a0=0xDEADBEEF, a1=0xF1F10006   leg 5b RED: shared-FETCH burst inflated
#   a0=0xDEADBEEF, a1=0xF1F10001   leg 1  RED: straddling 32-bit counted twice
#   a0=0xDEADBEEF, a1=0xF1F10007   leg 4b RED: the RE-PARKING iret is not
#                                  counted exactly once (finding F1-b)
#   a0=0xDEADBEEF, a1=0xF1F10005   leg 5a RED: shared DATA burst inflated
#   a0=0xDEADBEEF, a1=0xF1F10002   leg 2  RED: fence miscounted
#   a0=0xDEADBEEF, a1=0xF1F10003   leg 3  RED: amo miscounted
#   a0=0xDEADBEEF, a1=0x5E80001x   a CONTROL bracket moved -- the accounting
#                                  itself changed; NOT a fix result.
#                                  0x5E800015 is leg 4: the RESUMING iret
#                                  stopped being counted exactly once.
#   a0=0xDEADBEEF, a1=0x5E800001   the msip ISR never ran
#   a0=0xDEADBEEF, a1=0x5E800002   the interrupt did not land on f1_landing
#   a0=0xDEADBEEF, a1=0x5E800006   the second mtip ISR pass never ran
#   a0=0xDEADBEEF, a1=0x5E800007   the two mtip traps pushed DIFFERENT return
#                                  PCs -- the hart resumed instead of
#                                  re-parking, so leg 4b never reached its arm
#   a0=0xDEADBEEF, a1=0x5E800003   the shared-RAM copy did not read back
#   a0=0xDEADBEEF, a1=0x5E800004   the shared LOAD burst cost no extra clk
#                                  cycles -- leg 5a would be vacuous
#   a0=0xDEADBEEF, a1=0x5E800008   the re-park lasted < 64 clk cycles, so it
#                                  is no evidence that a clock-gated SLEEPING
#                                  window contributes nothing
#   a0=0xDEADBEEF, a1=0x5E800005   the shared CALL cost no extra clk cycles
#                                  -- leg 5b would be vacuous
#
# EVERY measured delta stays in a live register to the verdict so a probe run
# harvests all of them at once regardless of which check fired first:
#   s2  minstret AT TEST ENTRY (the whole bootrom, F1+'s real-world instance)
#   tp  mcycle   AT TEST ENTRY (the same window measured in clk cycles)
#   s3  d0   s4 d1s  s5 d1a  s6 d2n  s7 d2f  s8 d3a
#   s9  d5lt s10 d5ls s11 d5ct  a2 d5cs  a3 d4
#   s0  c5lt s1 c5ls  t4 c5ct  t5 c5cs      (mcycle deltas = REAL clk cost)
#   a4  the ISR-observed return PC   a5 minstret at the resume landing
#   a6  ISR-ran flag                 a7 &f1_landing
#   ra  d_fb (leg 4b)  gp f1b_retpc1  t6 f1b_retpc2 (equal = the hart re-parked)
#   t2  clk cycles spent RE-PARKED (leg 4b's anti-vacuous gate)
# Both ISRs deliberately avoid s0/s1/t4/t5 so the leg-5 data survives them.
#
# ---------------------------------------------------------------------------
# SHARED WORDS CLAIMED: 0x103E8 .. 0x10404 (8 words).
#   shexec.S's ledger comment names 0x103E8 as its next-free word at N=4, and
#   W1's band starts at 0x10420, so the claim is free at N=4 and sits below
#   both.  It is < 0x10500 and inside the bootrom zero range (< 0x10800).
#   At N=18 it overlaps shexec's DONE[10..17] array (which tops at 0x1041C) --
#   benign under CLAUDE.md's isolation rule (one image per sim), and this test
#   is single-hart and is NOT in the standing TEST_FILES array.
#   The same 8 words serve as the leg-5b code payload AND the leg-5a load
#   targets, so no second band is needed.
# Other non-private hardware touched: CLINT msip[0] (0x5000) + IVT slot 83,
#   and CLINT mtime/mtimecmp[0] + IVT slot 84 (leg 4b).
#
# Conventions: `.option arch, +zicsr` (rv32ua's -march has no zicsr);
#   `.option norvc` throughout with ONE rvc-enabled `.balign 4` at the top, so
#   every instruction is word-aligned EXCEPT the three deliberately-placed
#   halfword ones in leg 1.  The alignment leg 1 depends on is verified from
#   `riscv-none-elf-objdump -d` on the built image, never from the directives
#   (W2 measured that .text.init does not start word-aligned in this env).
#   RVTEST_CODE_END is `unimp` in this env, so every path spins.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"
#include "mp_boot.h"                 /* NHARTS (default 4) -- CLINT layout */

.option norelax

#define MINSTRET      0xB02
#define MCYCLE        0xB00
#define CLINT         0x5000
#define MSIP0         0x5000
#define SH_BASE       0x103E8       /* 8 words: code payload + load targets */

/* CLINT offsets from base 0x5000 -- the RTL's N-parameterized layout */
#define MTIME_OFF     ((4*NHARTS + 15) & ~15)
#define MTIME_LO      (MTIME_OFF)
#define MTIMECMP0_LO  (MTIME_OFF + 0x10)
#define MTIMECMP0_HI  (MTIME_OFF + 0x14)

/* expected values of the CONTROL brackets -- mechanism-free, so identical
   before and after the fix; each is 1 (the opening csrr) + the payload's
   architectural instruction count, cross-checked against the objdump. */
#define EXP_D0        1             /* empty bracket                        */
#define EXP_D1A       4             /* c.nop + c.nop + 32-bit nop           */
#define EXP_D2N       2             /* one nop                              */
#define EXP_D5LT      9             /* eight lw                             */
#define EXP_D5CT      10            /* jalr + 7 nop + jr ra                 */
/* w3_spec.md 6.3 RULING: `iret` is an instruction, it executes, it completes,
   minstret counts it -- exactly as 3-R0 already counts `mret`.  3-R0 excludes
   it only because Spike has no encoding for this custom instruction, which is
   a statement about what the TRACER can compare, not about what retired.  So
   legs 4 and 4b are CONTROLS at 2, and a fix that drives either to 1 has
   introduced a new defect (an executed instruction that stopped counting). */
#define EXP_D4        2             /* the RESUMING iret + the closing csrr */
/* Leg 4b has NO absolute constant: its check is d_fb == d4 + 1, and the +1 is
   the IVT slot's own `jal zero,<isr>` -- the one architectural instruction
   that is inside leg 4b's bracket and not inside leg 4's, because the second
   trap vectors through the IVT and the first return does not.  d2n = 2 fixes
   the cost of one plain instruction at 1 independently. */

RVTEST_RV32U
RVTEST_CODE_BEGIN

.option arch, +zicsr
.option rvc
    .balign 4                       /* one c.nop of padding if .text.init   */
.option norvc                       /*   started on a halfword; from here    */
                                    /*   on every instruction is aligned     */

    li   sp, 0xBFF0                 # sp MUST be valid before any IRQ

    la   t0, f1_retpc               # clear the ISR observation words
    sw   x0, 0(t0)
    la   t0, f1_isrflag
    sw   x0, 0(t0)

    # =====================================================================
    # OBSERVATION (not a pass criterion): minstret as the test image finds
    # it.  Everything before this point ran out of the SHARED boot ROM, so
    # post-fix this is roughly the bootrom's instruction count and pre-fix
    # it carries F1+'s per-clk stall inflation for every ROM fetch.
    # =====================================================================
    csrr s2, MINSTRET
    csrr tp, MCYCLE                 # ...against the clk cycles it took.  Both
                                    # free-run from reset, so tp is the whole
                                    # boot in clk cycles and s2/tp is the
                                    # fraction of boot clk cycles that this
                                    # counter called an instruction retire.

    # =====================================================================
    # LEG 0 -- the accounting anchor.  An empty bracket must read exactly 1.
    # =====================================================================
    csrr t0, MINSTRET
    csrr t1, MINSTRET
    sub  s3, t1, t0                 # d0

    # =====================================================================
    # LEG 1 -- the straddling 32-bit instruction (shape E, vesta.vhd:2464).
    # Both halves execute the SAME three instructions: two compressed and one
    # 32-bit.  Only the ORDER differs, and with it bit 1 of the 32-bit
    # instruction's PC.  Both blocks are 8 bytes, so alignment is restored.
    # =====================================================================
    # -- 1a: ALIGNED control.  c.nop @word, c.nop @halfword, 32-bit @word.
    csrr t0, MINSTRET
.option rvc
    c.nop
    c.nop
.option norvc
    nop
    csrr t1, MINSTRET
    sub  s5, t1, t0                 # d1a

    # -- 1b: STRADDLED.  c.nop @word, 32-bit @HALFWORD, c.nop @halfword.
    csrr t0, MINSTRET
.option rvc
    c.nop
.option norvc
    nop                             # <- straddles the word boundary
.option rvc
    c.nop
.option norvc
    csrr t1, MINSTRET
    sub  s4, t1, t0                 # d1s

    # =====================================================================
    # LEG 2 -- FENCE, against a one-nop control (also leg 3's control).
    # =====================================================================
    csrr t0, MINSTRET
    nop
    csrr t1, MINSTRET
    sub  s6, t1, t0                 # d2n

    csrr t0, MINSTRET
    fence
    csrr t1, MINSTRET
    sub  s7, t1, t0                 # d2f

    # =====================================================================
    # LEG 3 -- AMO.  Private TCM target, so no shared stall is mixed in.
    # =====================================================================
    la   t2, f1_amoword
    csrr t0, MINSTRET
    amoadd.w x0, x0, (t2)
    csrr t1, MINSTRET
    sub  s8, t1, t0                 # d3a

    # =====================================================================
    # Stage the leg-5 payload into the shared window, read-back verified.
    # =====================================================================
    la   t0, f1_rout
    li   t1, SH_BASE
    li   t2, 8
f1_copy:
    lw   t3, 0(t0)
    sw   t3, 0(t1)
    lw   t5, 0(t1)                  # read-back: the shared write really landed
    bne  t3, t5, f1_copyerr
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -1
    bnez t2, f1_copy

    # =====================================================================
    # LEG 5a -- a burst of shared-window DATA accesses vs the same burst to
    # private TCM.  Eight DISTINCT words in each (the M10 ack remembers the
    # word address, hart_tile.vhd:717, so eight loads of ONE address would be
    # absorbed into a single transaction and would measure nothing).
    #
    # Each half is ALSO bracketed in mcycle, which free-runs on clk and so
    # measures the REAL cost including every stalled cycle.  Without that,
    # "d5ls == d5lt" would be indistinguishable from "the loads never went to
    # the shared window at all" -- the gate below requires the shared half to
    # have cost strictly more clk cycles.  The two mcycle brackets carry the
    # same csrr/sub overhead, so it cancels in the comparison.
    # =====================================================================
    la   t2, f1_rout
    csrr s0, MCYCLE
    csrr t0, MINSTRET
    lw   t3,  0(t2)
    lw   t3,  4(t2)
    lw   t3,  8(t2)
    lw   t3, 12(t2)
    lw   t3, 16(t2)
    lw   t3, 20(t2)
    lw   t3, 24(t2)
    lw   t3, 28(t2)
    csrr t1, MINSTRET
    sub  s9, t1, t0                 # d5lt
    csrr t1, MCYCLE
    sub  s0, t1, s0                 # c5lt

    li   t2, SH_BASE
    csrr s1, MCYCLE
    csrr t0, MINSTRET
    lw   t3,  0(t2)
    lw   t3,  4(t2)
    lw   t3,  8(t2)
    lw   t3, 12(t2)
    lw   t3, 16(t2)
    lw   t3, 20(t2)
    lw   t3, 24(t2)
    lw   t3, 28(t2)
    csrr t1, MINSTRET
    sub  s10, t1, t0                # d5ls
    csrr t1, MCYCLE
    sub  s1, t1, s1                 # c5ls

    # =====================================================================
    # LEG 5b -- THE STALL BURST.  Call an 8-instruction leaf routine, once
    # where it is resident in private TCM and once where it is resident in
    # the shared window.  The two calls execute byte-identical instructions;
    # the only difference is which memory the FETCHES come from.  Same mcycle
    # bracketing, for the same reason -- and here the two differences are
    # meant to be compared with each other: if F1+ is "one phantom retire per
    # stalled clk cycle" then (d5cs - d5ct) must equal (c5cs - c5ct).
    # =====================================================================
    la   t2, f1_rout
    csrr t4, MCYCLE
    csrr t0, MINSTRET
    jalr ra, 0(t2)
    csrr t1, MINSTRET
    sub  s11, t1, t0                # d5ct
    csrr t1, MCYCLE
    sub  t4, t1, t4                 # c5ct

    li   t2, SH_BASE
    csrr t5, MCYCLE
    csrr t0, MINSTRET
    jalr ra, 0(t2)
    csrr t1, MINSTRET
    sub  a2, t1, t0                 # d5cs
    csrr t1, MCYCLE
    sub  t5, t1, t5                 # c5cs

    # =====================================================================
    # LEG 4 -- the interrupt return.  Structurally determined, NOT calibrated:
    # the arming `sw` to MSIP0 raises the level inside its OWN MEMORY_WAIT,
    # where vesta.vhd:3339 checks irq_save, so the pushed resume PC is
    # store+4 = f1_landing.  The measurement is entirely LOCAL: t6 is minstret
    # read by the LAST instruction of the ISR before `iret`, a5 is minstret
    # read by the FIRST instruction after the resume.  Between those two reads
    # exactly two things happen -- that csrr's own retire, and the iret.  So
    # a3 = 1 + <whatever the iret is worth>, and it does not depend on the
    # ISR's length, on where the interrupt landed, or on latency.
    # (vesta.vhd:3339/3573: iret runs EXECUTE -> MEMORY_WAIT(isr_ret='1') ->
    #  IRQ_REST -> EXECUTE.)
    #
    # w3_spec.md 6.3 RULES that the iret COUNTS, so this is a CONTROL at 2 in
    # BOTH polarities -- see the EXP_D4 comment.  It was originally filed as a
    # red leg on the grounds that 3-R0 does not retire in any of those three
    # states; that reading was overruled, because 3-R0 is the tracer's
    # comparison contract (Spike has no encoding for this custom instruction)
    # and 3-R0 already retires the analogous `mret`.
    # =====================================================================
    li   t6, 0                      # so a never-run ISR cannot look plausible
    li   t2, MSIP0
    li   t1, 1
    sw   t1, 0(t2)                  # <- the interrupt is taken ON THIS STORE
f1_landing:
    csrr a5, MINSTRET               # <- the resume lands HERE (store + 4)
    sub  a3, a5, t6                 # d4

    # =====================================================================
    # LEG 4b (F1-b) -- the OTHER IRQ_REST exit: an iret that RE-PARKS a
    # sleeping hart (vesta.vhd:3573, the `elsif sleep_cpu = '1'` arm, which
    # goes to SLEEPING with pc_en='0' instead of to EXECUTE).  This is the
    # bootrom park contract's normal path -- every msip round-trip on harts
    # 1..N-1 takes it -- and w3_spec.md 6.4 asks whether the iret is counted
    # there.  Same local bracket as leg 4, and no calibration: the SLEEPING
    # -> IRQ_SV edge is structurally determined (R-W2-2), and the anti-vacuous
    # gate is ignleak.S's -- the SECOND trap must push the SAME return PC as
    # the first, which only a hart that never resumed can produce.
    #
    #   z  = minstret read by the LAST instruction of ISR pass 1 before iret
    #   w  = minstret read by the FIRST instruction of ISR pass 2
    #   d_fb = w - z  = that csrr's own retire + the RE-PARKING iret
    #                   + the whole SLEEPING window (which must contribute
    #                     nothing: SLEEPING's next_state is SLEEPING, so the
    #                     sticky latch holds '0' -- a ~32-mtime-tick re-park
    #                     is deliberately used so that any SLEEPING inflation
    #                     would be unmistakable rather than marginal).
    # Required POST-fix: 2, the same as d4 -- w3_spec.md 6.4's own words,
    # "count iret exactly once on BOTH IRQ_REST exits".
    # =====================================================================
    la   t0, f1b_pass
    sw   x0, 0(t0)
    la   t0, f1b_retpc1
    sw   x0, 0(t0)
    la   t0, f1b_retpc2
    sw   x0, 0(t0)
    la   t0, f1b_delta
    sw   x0, 0(t0)

    li   t2, CLINT
    lw   t1, MTIME_LO(t2)
    addi t1, t1, 64
    sw   t1, MTIMECMP0_LO(t2)       # cmp lo FIRST (cmp hi still all-ones: quiet)
    sw   x0, MTIMECMP0_HI(t2)       # ...then hi = 0: ARMED
    extinguish                      # -> SLEEPING; the mtip arrives here
f1b_wake:                           # ISR pass 2 ignites and resumes here
    nop

    # =====================================================================
    # VERDICT
    # =====================================================================
    la   t0, f1_isrflag
    lw   a6, 0(t0)
    beqz a6, f1_setup1              # the ISR never ran at all

    la   t0, f1_retpc
    lw   a4, 0(t0)
    la   a7, f1_landing
    bne  a4, a7, f1_setup2          # the interrupt did not land on the bracket

    # -- leg 4b setup gates: two ISR entries, and the SECOND one must have
    #    found the hart still parked at the SAME return PC (ignleak's gate --
    #    positive proof of re-parking, not an absence of failure).
    la   t0, f1b_pass
    lw   t0, 0(t0)
    li   t1, 2
    bne  t0, t1, f1_setup6          # the second mtip ISR never ran (or ran 3x)
    la   t0, f1b_retpc1
    lw   gp, 0(t0)
    la   t0, f1b_retpc2
    lw   t6, 0(t0)
    bne  gp, t6, f1_setup7          # the hart RESUMED instead of re-parking
    la   t0, f1b_delta
    lw   ra, 0(t0)                  # d_fb
    la   t0, f1b_mcdelta
    lw   t2, 0(t0)                  # clk cycles spent re-parked
    li   t1, 64
    bltu t2, t1, f1_setup8          # the re-park was too short to be evidence

    # -- leg 5 anti-vacuous gates: the SHARED halves must really have cost
    #    clk cycles.  A floor of +8 over the private half is one extra clk per
    #    access, which no real arbiter round trip can undercut.
    addi t0, s0, 8
    bltu s1, t0, f1_setup4          # the shared load burst never stalled
    addi t0, t4, 8
    bltu t5, t0, f1_setup5          # the shared call never stalled

    # -- control brackets: these must NOT move.  A fix does not touch them.
    li   t0, EXP_D0
    bne  s3, t0, f1_ctl0
    li   t0, EXP_D1A
    bne  s5, t0, f1_ctl1
    li   t0, EXP_D2N
    bne  s6, t0, f1_ctl2
    li   t0, EXP_D5LT
    bne  s9, t0, f1_ctl3
    li   t0, EXP_D5CT
    bne  s11, t0, f1_ctl4
    li   t0, EXP_D4                 # w3_spec.md 6.3: iret COUNTS. This is a
    bne  a3, t0, f1_ctl5            #   CONTROL, 2 before AND after; a fix that
                                    #   drives it to 1 is a NEW DEFECT.

    # -- the discriminating equalities, dominant mechanism first
    bne  a2,  s11, f1_leg5b         # shared FETCH burst   (F1+, dominant)
    bne  s4,  s5,  f1_leg1          # straddling 32-bit    (F1)
    bne  s10, s9,  f1_leg5a         # shared DATA burst    (F1+)
    bne  s7,  s6,  f1_leg2          # fence                (F1, predicted OK)
    bne  s8,  s6,  f1_leg3          # amo                  (F1, predicted OK)
    addi t0, a3, 1                  # F1-b, RELATIONAL: leg 4b's bracket holds
    bne  ra, t0, f1_legfb           #   exactly ONE architectural instruction
                                    #   more than leg 4's -- the IVT slot's own
                                    #   `jal zero,<isr>`, which the second trap
                                    #   executes and the first return does not.
                                    #   d2n = 2 independently fixes one plain
                                    #   instruction at 1, so d_fb must be
                                    #   d4 + 1 iff the RE-PARKING iret costs
                                    #   the same as the RESUMING one.

    RVTEST_PASS                     # a0 = 0xCAFEBABE

f1_leg1:    li a1, 0xF1F10001
            j  f1_fail
f1_leg2:    li a1, 0xF1F10002
            j  f1_fail
f1_leg3:    li a1, 0xF1F10003
            j  f1_fail
f1_legfb:   li a1, 0xF1F10007
            j  f1_fail
f1_leg5a:   li a1, 0xF1F10005
            j  f1_fail
f1_leg5b:   li a1, 0xF1F10006
            j  f1_fail
f1_ctl0:    li a1, 0x5E800010
            j  f1_fail
f1_ctl1:    li a1, 0x5E800011
            j  f1_fail
f1_ctl2:    li a1, 0x5E800012
            j  f1_fail
f1_ctl3:    li a1, 0x5E800013
            j  f1_fail
f1_ctl4:    li a1, 0x5E800014
            j  f1_fail
f1_ctl5:    li a1, 0x5E800015
            j  f1_fail
f1_setup6:  li a1, 0x5E800006
            j  f1_fail
f1_setup7:  li a1, 0x5E800007
            j  f1_fail
f1_setup8:  li a1, 0x5E800008
            j  f1_fail
f1_setup1:  li a1, 0x5E800001
            j  f1_fail
f1_setup2:  li a1, 0x5E800002
            j  f1_fail
f1_setup4:  li a1, 0x5E800004
            j  f1_fail
f1_setup5:  li a1, 0x5E800005
            j  f1_fail
f1_copyerr: li a1, 0x5E800003
f1_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF

    # =====================================================================
    # The leg-5 payload.  Position-independent, no register clobber beyond
    # the return through ra.  Copied verbatim into SH_BASE; reached only by
    # jalr, never by fall-through (RVTEST_FAIL above spins).
    # =====================================================================
    .balign 4
f1_rout:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    jalr x0, ra, 0

    # =====================================================================
    # msip ISR (IVT slot 83, hardware-vectored).  Hart 0 is AWAKE, so no
    # ignite is needed.  Uses only t3/t4/t6, which the main flow does not
    # rely on across this point.  The `csrr t6` MUST stay the instruction
    # immediately before `iret` -- that adjacency is leg 4's whole design.
    # =====================================================================
f1_msip_isr:
    lw    t3, 0(sp)                 # the return PC hardware pushed at sp-4
    la    t6, f1_retpc              # t6 is about to be reloaded below, so the
    sw    t3, 0(t6)                 #   ISR needs only t3 and t6 -- everything
    li    t3, 1                     #   else (t4/t5/s0/s1) carries leg-5 data
    la    t6, f1_isrflag            #   across this point
    sw    t3, 0(t6)
    li    t3, MSIP0
    sw    x0, 0(t3)                 # clear the msip LEVEL before returning
    csrr  t6, MINSTRET              # z -- LAST instruction before iret
    iret

    # =====================================================================
    # mtip ISR (IVT slot 84) -- leg 4b.  Two passes over ONE entry point:
    #   pass 1  records the pushed PC, RE-ARMS mtip for a fresh assertion ~32
    #           ticks out (a clean level drop-and-rise, so the wake cannot
    #           depend on how the irq_handler treats a still-high level), does
    #           NOT ignite -- so IRQ_REST takes its sleep_cpu='1' arm and the
    #           hart RE-PARKS.  Its last instruction before iret is the csrr.
    #   pass 2  reads minstret as its FIRST instruction, records the second
    #           pushed PC (must equal the first), publishes the delta, disarms
    #           mtip for good, ignites and returns.
    # Uses only t0/t1/t2/t3/t6 so that s0/s1/t4/t5 (leg 5) and s2-s11/a2/a3/a5
    # survive.  A third entry can only be a malfunction; it is routed to the
    # pass-2 path so it can never loop, and f1b_pass then trips f1_setup6.
    # =====================================================================
f1b_mtip_isr:
    csrr  t2, MINSTRET              # w   -- FIRST instruction on every entry
    csrr  t1, MCYCLE                # mc2 -- SECOND, for the sleep-length gate
    la    t3, f1b_pass
    lw    t0, 0(t3)
    addi  t0, t0, 1
    sw    t0, 0(t3)
    li    t3, 2
    bgeu  t0, t3, f1b_second

    lw    t3, 0(sp)                 # pass 1: the pushed return PC
    la    t0, f1b_retpc1
    sw    t3, 0(t0)
    li    t0, CLINT
    li    t3, -1
    sw    t3, MTIMECMP0_HI(t0)      # drop the level...
    lw    t3, MTIME_LO(t0)
    addi  t3, t3, 512               # NOT 32: mtime advances at roughly the
                                    # clk rate and the three shared-window
                                    # CLINT accesses below already eat ~20 clk,
                                    # so a short re-arm produces a ~14-cycle
                                    # park that is no evidence of anything.
                                    # 512 gives a park two orders of magnitude
                                    # longer than the +1 under measurement.
    sw    t3, MTIMECMP0_LO(t0)
    sw    x0, MTIMECMP0_HI(t0)      # ...and re-arm it, fresh
    csrr  t3, MCYCLE                # mc1
    la    t0, f1b_mc1
    sw    t3, 0(t0)
                                    # NO ignite: IRQ_REST must re-park us
    csrr  t6, MINSTRET              # z -- LAST instruction before iret
    iret

f1b_second:
    lw    t3, 0(sp)                 # pass 2: the second pushed return PC
    la    t0, f1b_retpc2
    sw    t3, 0(t0)
    sub   t3, t2, t6                # d_fb = w - z
    la    t0, f1b_delta
    sw    t3, 0(t0)
    la    t0, f1b_mc1
    lw    t3, 0(t0)
    sub   t3, t1, t3                # clk cycles spent RE-PARKED
    la    t0, f1b_mcdelta
    sw    t3, 0(t0)
    li    t0, CLINT
    li    t3, -1
    sw    t3, MTIMECMP0_HI(t0)      # disarm mtip for good
    ignite                          # the hart IS asleep: wake it for real
    iret

    # ---- extend the env IVT: DEFINE_IVT emitted slots 0-82 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, f1_msip_isr          # slot 83 = IRQB_CLINT_MSIP
    jal  zero, f1b_mtip_isr         # slot 84 = IRQB_CLINT_MTIP
    .previous

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
f1_retpc:   .word 0
f1_isrflag: .word 0
f1_amoword: .word 0
f1b_pass:   .word 0
f1b_retpc1: .word 0
f1b_retpc2: .word 0
f1b_delta:  .word 0
f1b_mc1:    .word 0
f1b_mcdelta: .word 0
  TEST_DATA
RVTEST_DATA_END
