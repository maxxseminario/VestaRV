# See LICENSE for license details.

# VestaRV: RTC0 register, write-commit handshake and periodic-tick interrupt
# Hart 0 only, tiles parked. RTC0 sits at 0x6500 and this proves the CPU can drive it, that the write-commit SYNC handshake works, and that the periodic tick on vector 114 routes through irq_router HhENX, meip, the env MEIP_DISPATCHER, the IVT and a plain-ret handler that claims and completes, and then RE-ARMS, which is why two ticks are taken. It also reads PENDX at 0x781C bit 18 WITH THE ROUTE STILL OFF once the tick flag is high, which is deterministic because PEND reflects the raw source level rather than the enable, and reads INSVCX at 0x782C bit 18 inside the handler before the W1C.
# Register map: CR 0x6500 = RTCEN[0] ALMEN[1] TICKEN[2] ALMIE[3] TICKIE[4]; SEC 0x6504; SUB 0x6508; ALM 0x650C; PER 0x6510, a 16-bit down-counter RELOAD whose tick period is (PER + 1) LFXT ticks of about 30.5 us each, read back as the staging value on the mclk side; SR 0x6514 = SYNC[0], read-only and meaning a commit is busy, ALMF[1] and TICKF[2], both write-1-to-clear. The interrupt is the alarm flag gated by ALMIE or the tick flag gated by TICKIE.
# THE ALARM PATH IS NOT USED, deliberately: it is a 32-bit seconds equality with a rising edge, so a same-second alarm cannot fire without a seconds rollover, about a second of LFXT, which is too slow and not deterministic. Only the sub-second periodic tick is exercised.
# RTC0 is mclk-domain, with its register file on the gated bus clock, its flags and interrupt on free-running mclk and its counter on ungated LFXT, so no SYS_CLK_CR write is needed; that rule is only for smclk peripherals.

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

    # ---- env meip dispatcher (.isr_meip @0x9100) + arm IVT 83/84/85 -------
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
