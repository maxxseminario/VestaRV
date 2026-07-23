# See LICENSE for license details.

#*****************************************************************************
# wtrng.S  (wound-config firmware smoke — digperiphs DP-SG)
#-----------------------------------------------------------------------------
# TRNG0 @0x6900 ring-oscillator entropy harvest engine smoke: register resets,
# the DR read-CONSUME contract (D9 same-cycle DRDY blind window, no spurious
# pop on an empty read), two successive entropy words proving the LFSR stub
# actually MOVES, and the combined data-ready/health-alarm interrupt (vector
# 121) delivered through the REAL meip path (irq_router H0ENX bit25 -> meip ->
# env MEIP_DISPATCHER -> IVT slot 121 -> plain-ret handler -> CLAIM/COMPLETE),
# same idiom as wrtc.S (114) / wdma.S (119) / shnpu.S's IRQ leg (120). Single-
# hart directed (hart 0; tiles stay parked — no MP_LAUNCH, no mp_boot.h).
#
# STAGE-E RIDER PROOF (irq_router RO words for sources 96-127), mirrored from
# wrtc/wdma:
#   * PENDX  @0x781C bit25 (source 121) — read with the ROUTE STILL OFF once
#     DRDY&DRDYIE has gone high: PEND reflects the RAW source level, not the
#     enable, so this is deterministic (no delivery yet). Then enable the route.
#   * INSVCX @0x782C bit25 — read INSIDE the handler (claimed, before W1C) and
#     require the claimed source's in_service bit is set.
#
# EXACTLY-ONCE MECHANISM (task-directed choice): the entropy engine keeps
# assembling words continuously while EN=1, so a fresh DRDY WILL reassert
# ~32 mclk after the handler's drain and re-pend the level if DRDYIE is left
# set. The handler therefore clears CR.DRDYIE (bit1) itself, right after it
# has drained the word that woke it, BEFORE returning — the dispatcher's
# COMPLETE(121) then finds the level already low for good. (The alternative,
# disabling EN, was rejected: it would also stop RUN, muddying the RUN=1
# assertion this test makes during the polling leg.)
#
# TRNG register map (trng_spec.md; slot n @ 0x6900 + 4n):
#   CR 0x6900  SR 0x6904  DR 0x6908  HT 0x690C
#   CR : EN[0] DRDYIE[1] ALMIE[2] ROSEL[7:4] DECIM[11:8]   (rest rsvd)
#   SR : DRDY[0](ro) ALMF[1](W1C) RUN[2](ro)               (rest rsvd)
#   DR : read-CONSUMES — a qualified read (DRDY=1) returns the word AND
#        clears DRDY the SAME cycle; a read while DRDY=0 returns 0 and does
#        NOT consume (no spurious pop).
#   HT : RCTC[7:0] RUNLEN[21:16](ro)                       (rest rsvd)
#   irq_trng (121) = (DRDY & DRDYIE) | (ALMF & ALMIE)
#
# DECIM=8 (one raw sample every 2^8=256 mclk, 32 samples/word => ~8192 mclk
# ~=341us at 24MHz) is DELIBERATELY not the fastest setting (D9/D10 bisect
# finding, see below) — every poll still finishes well inside POLL_BUD.
# TRNG0 machinery rides free-running MCLK (D4-clean) — NO SYS_CLK_CR write
# needed (that rule is only for the smclk peripherals).
#
# DECIM CHOICE IS LOAD-BEARING (bisected 2026-07-22): at DECIM=0 (32 mclk/
# word) the L2 IRQ-dispatch overhead (PENDX read, H0ENX write+readback, the
# meip trap, MEIP_DISPATCHER's CLAIM read + jalr, the handler's own INSVCX/
# SR reads) comfortably EXCEEDS one word period, so by the time the handler
# drains the word that woke it (D9's consume), the D10 stall logic has
# ALREADY assembled and parked a FOLLOW-ON word — which promotes into
# dr_word within ~2 clk of the consume (the instant word_valid frees up),
# so an SR read moments after the drain legitimately observes DRDY=1 again
# (a real, distinct word — not a D9 violation: D9 only guarantees the SAME
# CYCLE right at the qualifying read stays masked, not that DRDY stays low
# afterward once a backlog exists). DECIM=8 gives the whole L2 dispatch path
# (a handful of shared-bus round trips, each ~5-10 mclk) a period more than
# an order of magnitude shorter than one word (~8192 mclk), so no follow-on
# word is ever stalled-and-ready by the time SR_POST is sampled.
#
# The entropy source is a DETERMINISTIC LFSR stub in behavioral sim — word
# VALUES are never hardcoded; only structural properties are checked
# (nonzero, word-over-word movement, the DRDY/consume timing contract).
#
# Scratch: private TCM 0xA000-0xA010 (single-hart directed test — the
# majority w* precedent: wrtc/wow/wi2ct/wqspi/wgpio/wi3c all use 0xA000+
# private-TCM mailboxes, never the shared 0x10xxx ledger, because there is
# no second hart to rendezvous with; wdma is the lone outlier and says so in
# its own header). No shared-window word claimed by this test.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define TRNG_BASE   0x6900
#define O_CR        0x00
#define O_SR        0x04
#define O_DR        0x08
#define O_HT        0x0C

#define CR_EN       (1 << 0)
#define CR_DRDYIE   (1 << 1)
#define CR_DECIM8   (8 << 8)                /* DECIM=8 -- see the header note */
#define CR_EN_D8    (CR_EN | CR_DECIM8)     /* 0x0801 */
#define CR_EN_DIE_D8 (CR_EN | CR_DRDYIE | CR_DECIM8) /* 0x0803 */

#define SR_DRDY     (1 << 0)
#define SR_ALMF     (1 << 1)
#define SR_RUN      (1 << 2)

#define IRTR_ENX    0x700C            /* HhENX, hart-0 row (sources 96-127) */
#define IRTR_PENDX  0x781C            /* RO pending, sources 96-127          */
#define IRTR_INSVCX 0x782C            /* RO in_service, sources 96-127       */
#define TRNG_SRC_BIT 0x02000000       /* bit25 = source 121 (121-96) */

#define FLAG        0xA000            /* ISR exactly-once counter */
#define ISVC        0xA004            /* handler's masked INSVCX readback */
#define SR_SEEN     0xA008            /* handler's SR read BEFORE the drain */
#define WORD_SEEN   0xA00C            /* handler's drained DR word */
#define SR_POST     0xA010            /* handler's SR read AFTER the drain */

#define POLL_BUD    20000
#define SETTLE_BUD  10000                 /* spans > one DECIM=8 word period */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0                   # valid stack before any IRQ (IRQ_SV pushes PC)
    li   s0, TRNG_BASE

    # ================= L0: reset defaults + DR empty-read contract =====
    lw   t0, O_CR(s0)
    bnez t0, wtrng_fail                # CR resets 0
    lw   t0, O_SR(s0)
    bnez t0, wtrng_fail                # SR resets 0 (DRDY/ALMF/RUN all 0)
    lw   t0, O_HT(s0)
    bnez t0, wtrng_fail                # HT resets 0 (RCTC/RUNLEN both 0)

    lw   t0, O_DR(s0)
    bnez t0, wtrng_fail                # empty read (DRDY=0) returns 0
    lw   t0, O_SR(s0)
    andi t0, t0, SR_DRDY
    bnez t0, wtrng_fail                # ...and does NOT consume/assert DRDY

    # ================= L1: enable engine, drain two words ==============
    # EN=1, DRDYIE=0, ROSEL=0 (all rings), DECIM=8 (see the header note)
    li   t0, CR_EN_D8
    sw   t0, O_CR(s0)

    li   t6, POLL_BUD
wtrng_w1:
    lw   t0, O_SR(s0)
    andi t1, t0, SR_DRDY
    bnez t1, wtrng_r1
    addi t6, t6, -1
    bnez t6, wtrng_w1
    j    wtrng_fail
wtrng_r1:
    lw   s1, O_DR(s0)                 # consume first word -> t/s1 = word 1
    beqz s1, wtrng_fail                # must be nonzero (structural sanity)
    li   t0, 0xFFFFFFFF
    beq  s1, t0, wtrng_fail            # ...and not the all-ones sentinel either

    # D9 same-cycle blind window: the VERY NEXT bus access after the DR read
    # must observe DRDY already low.
    lw   t0, O_SR(s0)
    andi t0, t0, SR_DRDY
    bnez t0, wtrng_fail

    li   t6, POLL_BUD
wtrng_w2:
    lw   t0, O_SR(s0)
    andi t1, t0, SR_DRDY
    bnez t1, wtrng_r2
    addi t6, t6, -1
    bnez t6, wtrng_w2
    j    wtrng_fail
wtrng_r2:
    # RUN=1, ALMF=0 while the engine is live and healthy (captured from the
    # same SR sample that satisfied the poll, before the drain touches DRDY)
    andi t1, t0, SR_ALMF
    bnez t1, wtrng_fail
    andi t1, t0, SR_RUN
    beqz t1, wtrng_fail

    lw   s2, O_DR(s0)                 # consume second word -> s2 = word 2
    beqz s2, wtrng_fail
    beq  s1, s2, wtrng_fail           # LFSR must have moved (word1 != word2)

    # ================= L2: IRQ leg (vector 121) =========================
    li   t0, FLAG
    sw   x0, 0(t0)
    li   t0, ISVC
    sw   x0, 0(t0)
    li   t0, SR_SEEN
    sw   x0, 0(t0)
    li   t0, WORD_SEEN
    sw   x0, 0(t0)
    li   t0, SR_POST
    sw   x0, 0(t0)

    # arm DRDYIE (route still off) -> irq_in asserts once DRDY comes up again
    li   t0, CR_EN_DIE_D8
    sw   t0, O_CR(s0)

    li   t6, POLL_BUD
wtrng_w3:
    lw   t0, O_SR(s0)
    andi t1, t0, SR_DRDY
    bnez t1, wtrng_pendx
    addi t6, t6, -1
    bnez t6, wtrng_w3
    j    wtrng_fail

wtrng_pendx:
    # RIDER: PENDX bit25 must be set (raw source pending, deterministic) ----
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TRNG_SRC_BIT
    and  t1, t1, t2
    beqz t1, wtrng_fail               # source 121 not pending in PENDX -> FAIL

    # enable the route -> meip -> dispatcher -> claim 121 -> handler
    li   t0, IRTR_ENX
    li   t1, TRNG_SRC_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wtrng_fail           # H0ENX bit25 readback

    li   t6, POLL_BUD
wtrng_wtok:
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, wtrng_chk
    addi t6, t6, -1
    bnez t6, wtrng_wtok
    j    wtrng_fail

wtrng_chk:
    # exactly one delivery so far
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wtrng_fail
    # RIDER: the handler recorded INSVCX bit25 while claimed
    li   t0, ISVC
    lw   t1, 0(t0)
    li   t2, TRNG_SRC_BIT
    bne  t1, t2, wtrng_fail
    # handler's pre-drain SR sample had DRDY=1
    li   t0, SR_SEEN
    lw   t1, 0(t0)
    andi t1, t1, SR_DRDY
    beqz t1, wtrng_fail
    # the drained word is nonzero (structural sanity)
    li   t0, WORD_SEEN
    lw   t1, 0(t0)
    beqz t1, wtrng_fail
    # D9: handler's post-drain SR sample has DRDY=0 (same-cycle consume held)
    li   t0, SR_POST
    lw   t1, 0(t0)
    andi t1, t1, SR_DRDY
    bnez t1, wtrng_fail
    # PENDX bit25 clear now too (DRDY dropped, DRDYIE cleared by the handler
    # -> raw irq_in stays low even once the next word assembles)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TRNG_SRC_BIT
    and  t1, t1, t2
    bnez t1, wtrng_fail

    # settle window: let the engine assemble further words, confirm no
    # second delivery (the handler's DRDYIE clear is the exactly-once gate)
    li   t6, SETTLE_BUD
wtrng_settle:
    addi t6, t6, -1
    bnez t6, wtrng_settle
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wtrng_fail

    li   t0, IRTR_ENX
    sw   x0, 0(t0)                    # un-route (clean)

wtrng_pass:
    RVTEST_PASS

wtrng_fail:
    RVTEST_FAIL

    # ---- TRNG0 data-ready/alarm handler (vector 121; M19 plain-ret meip
    # ---- ABI). Reached via CLAIM=121 -> dispatcher jalr through IVT slot
    # ---- 121. Records the INSVCX in-handler proof, samples SR, drains DR
    # ---- (W1C-by-read of DRDY, clears the LEVEL's DRDY term SAME cycle),
    # ---- samples SR again, then clears CR.DRDYIE (the exactly-once gate —
    # ---- see the header note) BEFORE returning (dispatcher COMPLETEs
    # ---- after). t0-t2 = dispatcher-saved scratch; ra survives (ret). ----
    .section .text.init
trng0_h:
    li   t0, IRTR_INSVCX
    lw   t1, 0(t0)
    li   t2, TRNG_SRC_BIT
    and  t1, t1, t2                  # isolate bit25 (source 121 in service)
    li   t0, ISVC
    sw   t1, 0(t0)                   # mainline requires == 0x02000000

    li   t0, TRNG_BASE
    lw   t1, O_SR(t0)
    li   t2, SR_SEEN
    sw   t1, 0(t2)                   # mainline requires DRDY==1 here

    lw   t1, O_DR(t0)                # drain -> clears DRDY same cycle
    li   t2, WORD_SEEN
    sw   t1, 0(t2)                   # mainline requires nonzero

    lw   t1, O_SR(t0)
    li   t2, SR_POST
    sw   t1, 0(t2)                   # mainline requires DRDY==0 here

    lw   t1, O_CR(t0)
    andi t1, t1, -3                  # clear bit1 (DRDYIE) -- exactly-once gate
    sw   t1, O_CR(t0)

    li   t0, FLAG
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    ret

    # ---- env meip dispatcher (.isr_meip @0xB100) + arm IVT 83/84/85 -------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 121 = TRNG0 (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85). Slot 121 @ .ivt+4*121 = 0x1E4. --------
    .section .ivt, "ax"
    .org 4*121
    jal  zero, trng0_h                # slot 121 = IRQB_TRNG0
    .previous

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
