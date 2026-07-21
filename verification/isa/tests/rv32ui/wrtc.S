# See LICENSE for license details.

#*****************************************************************************
# wrtc.S  (wound-config firmware smoke — digperiphs Stage E)
#-----------------------------------------------------------------------------
# RTC0 @0x6500 register + write-commit SYNC handshake + periodic-tick IRQ
# delivery smoke. Single-hart directed (hart 0; tiles stay parked — no
# MP_LAUNCH, no mp_boot.h). Proves the CPU can drive the RTC, that the D8
# write-commit SYNC handshake works, and that the periodic tick (vector 114)
# routes through irq_router (HhENX) -> meip -> env MEIP_DISPATCHER -> IVT ->
# plain-ret handler -> CLAIM/COMPLETE, and RE-ARMS (two ticks).
#
# STAGE-E RIDER PROOF (irq_router RO words for sources 96-127):
#   * PENDX  @0x781C bit18 (source 114) — read with the ROUTE STILL OFF once
#     TICKF is high: PEND reflects the RAW source level (irq_in), NOT the
#     enable, so this is deterministic (no delivery yet). Then enable the route.
#   * INSVCX @0x782C bit18 — read INSIDE the handler (claimed, before W1C) and
#     require the claimed source's in_service bit is set.
#
# RTC register map (rtc_spec.md / RTC.vhd AS-BUILT; MemoryMap RegSlotRTCx*):
#   CR 0x6500  SEC 0x6504  SUB 0x6508  ALM 0x650C  PER 0x6510  SR 0x6514
#   CR : RTCEN[0] ALMEN[1] TICKEN[2] ALMIE[3] TICKIE[4]        (rest rsvd)
#   SR : SYNC[0](ro,1=commit-busy) ALMF[1](W1C) TICKF[2](W1C)
#   PER: 16-bit down-counter RELOAD; tick period = (PER+1) lfxt ticks
#        (1 lfxt tick = 1/32768 s ~= 30.5us). PER read = staging (direct mclk).
#   irq_rtc (114) = (ALMF & ALMIE) | (TICKF & TICKIE)   (RTC.vhd:203)
#
# The ALARM path is 32-bit SECONDS-equality + rising-edge — a same-second
# alarm cannot fire without a seconds rollover (~1s of lfxt), too slow and not
# deterministic, so this test uses ONLY the sub-second periodic tick (task
# directive). RTC0 is mclk-domain (register file on gated ClkMem, flags/IRQ on
# free-running mclk, counter on ungated lfxt) — NO SYS_CLK_CR write is needed
# (that rule is only for the smclk peripherals; wqspi writes it because QSPI's
# serial core is smclk).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define RTC_CR      0x6500
#define RTC_ALM     0x650C
#define RTC_PER     0x6510
#define RTC_SR      0x6514
#define IRTR_ENX    0x700C            /* HhENX, hart-0 row (sources 96-127) */
#define IRTR_PENDX  0x781C            /* RO pending, sources 96-127          */
#define IRTR_INSVCX 0x782C            /* RO in_service, sources 96-127       */

/* CR: RTCEN(0) | TICKEN(2) | TICKIE(4) — no alarm */
#define RTC_CR_VAL  0x00000015
#define RTC_PER_VAL 3                 /* tick every PER+1 = 4 lfxt ~= 122us */
#define ENX_RTC     0x00040000        /* bit18 = source 114 */
#define SYNC_BUSY   0x1               /* SR bit0 */
#define TICKF       0x4               /* SR bit2 (W1C) */
#define RTC_SRC_BIT 0x00040000        /* PENDX/INSVCX bit18 = source 114-96 */

#define TICK_CNT    0xA000            /* private-TCM handler tick counter */
#define ISVC_SEEN   0xA004            /* handler's masked INSVCX readback  */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0                   # valid stack before any IRQ (IRQ_SV pushes PC)

    li   s0, TICK_CNT
    li   s1, ISVC_SEEN
    sw   x0, 0(s0)
    sw   x0, 0(s1)

    # ================= L0: reset defaults ==============================
    li   a0, RTC_CR
    lw   t0, 0(a0)
    bnez t0, wrtc_fail                # CR resets 0
    li   a0, RTC_SR
    lw   t0, 0(a0)
    bnez t0, wrtc_fail                # SR resets 0 (SYNC/ALMF/TICKF all 0)

    # ================= L1: PER write + D8 SYNC handshake ===============
    # Write PER (a domain-crossing commit) -> SR.SYNC busy -> poll until idle,
    # then read PER back (staging readback, direct mclk).
    li   a0, RTC_PER
    li   t1, RTC_PER_VAL
    sw   t1, 0(a0)                    # commit -> SYNC asserts
    li   a1, RTC_SR
    li   s3, 20000
wrtc_sync:
    lw   t0, 0(a1)
    andi t0, t0, SYNC_BUSY
    beqz t0, wrtc_synced             # SYNC cleared -> commit landed
    addi s3, s3, -1
    bnez s3, wrtc_sync
    j    wrtc_fail
wrtc_synced:
    lw   t0, 0(a0)                   # PER readback (staging)
    li   t1, RTC_PER_VAL
    bne  t0, t1, wrtc_fail

    # ALM write/readback (direct mclk staging) + its own SYNC drain
    li   a0, RTC_ALM
    li   t1, 0x12345678
    sw   t1, 0(a0)
    li   s3, 20000
wrtc_async:
    lw   t0, 0(a1)
    andi t0, t0, SYNC_BUSY
    beqz t0, wrtc_asynced
    addi s3, s3, -1
    bnez s3, wrtc_async
    j    wrtc_fail
wrtc_asynced:
    lw   t0, 0(a0)
    li   t1, 0x12345678
    bne  t0, t1, wrtc_fail

    # ================= L2: arm tick, prove PENDX with route OFF ========
    # Enable RTCEN|TICKEN|TICKIE (NO route yet). The tick counts autonomously
    # on lfxt; once TICKF sets, irq_in(114)=TICKF&TICKIE=1 but no meip is
    # delivered while HhENX bit18 is clear.
    li   a0, RTC_CR
    li   t1, RTC_CR_VAL
    sw   t1, 0(a0)

    # wait for the first TICKF (route off -> no interrupt races this poll)
    li   a1, RTC_SR
    li   s3, 20000
wrtc_wtick:
    lw   t0, 0(a1)
    andi t0, t0, TICKF
    bnez t0, wrtc_pendx
    addi s3, s3, -1
    bnez s3, wrtc_wtick
    j    wrtc_fail

wrtc_pendx:
    # RIDER: PENDX bit18 must be set (raw source pending, deterministic) ----
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, RTC_SRC_BIT
    and  t1, t1, t2
    beqz t1, wrtc_fail               # source 114 not pending in PENDX -> FAIL

    # ================= L3: enable route -> deliver + re-arm =============
    li   t0, IRTR_ENX
    li   t1, ENX_RTC
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wrtc_fail           # HhENX bit18 readback

    # first delivery: wait counter == 1 (meip taken mid-poll)
    li   s3, 20000
wrtc_p1:
    lw   t0, 0(s0)
    li   t1, 1
    bge  t0, t1, wrtc_chk1
    addi s3, s3, -1
    bnez s3, wrtc_p1
    j    wrtc_fail
wrtc_chk1:
    # RIDER: the handler recorded INSVCX bit18 while claimed
    lw   t0, 0(s1)
    li   t1, RTC_SRC_BIT
    bne  t0, t1, wrtc_fail

    # re-arm: TICKEN stays on -> a SECOND tick fires -> second delivery
    li   s3, 20000
wrtc_p2:
    lw   t0, 0(s0)
    li   t1, 2
    bge  t0, t1, wrtc_pass
    addi s3, s3, -1
    bnez s3, wrtc_p2
    j    wrtc_fail

wrtc_pass:
    RVTEST_PASS

wrtc_fail:
    RVTEST_FAIL

    # ---- RTC0 tick handler (vec 114, plain-ret M19 ABI). Reached via
    # ---- CLAIM=114 -> dispatcher jalr through IVT slot 114. Records the
    # ---- INSVCX in-handler proof, clears the LEVEL (W1C TICKF) BEFORE
    # ---- returning (dispatcher COMPLETEs after), bumps the tick counter.
    # ---- t0-t2 = dispatcher-saved scratch; ra survives (ret). ------------
    .section .text.init
rtc0_tick_h:
    li   t0, IRTR_INSVCX
    lw   t1, 0(t0)
    li   t2, RTC_SRC_BIT
    and  t1, t1, t2                  # isolate bit18 (source 114 in service)
    li   t0, ISVC_SEEN
    sw   t1, 0(t0)                   # mainline requires == 0x40000
    li   t0, RTC_SR
    li   t1, TICKF
    sw   t1, 0(t0)                   # W1C TICKF -> drop irq_rtc level
    li   t0, TICK_CNT
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    ret

    # ---- env meip dispatcher (.isr_meip @0xB100) + arm IVT 83/84/85 -------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 114 = RTC0 (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85). Slot 114 @ .ivt+4*114 = 0x1C8. --------
    .section .ivt, "ax"
    .org 4*114
    jal  zero, rtc0_tick_h           # slot 114 = IRQB_RTC0
    .previous

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
