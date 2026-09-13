# See LICENSE for license details.

# VestaRV: PWM0 smoke, shadow buffering and interrupt claim priority
# Hart 0 only, tiles parked. PWM0 sits at 0x6600 and this covers configuration, shadow-buffered update behaviour, the period-event interrupt on vector 116 and the software fault-trip interrupt on vector 115 through the meip dispatcher, and the fault-at-lower-id claim priority when both pend.
# Register map: CR 0x6600 = PWMEN[0] CH0EN[1] CH1EN[2] PEVIE[7] FLTIE[8] FLTEN[12] FLTTRIG[14], which is write-1, self-clearing and reads 0, and PSC[19:16]; PER 0x6604; DTY0 0x6608; DTY1 0x660C; POL 0x6618; SR 0x6620 = FLTF[0] and PEVF[1], both write-1-to-clear, and UPDF[2], read-only, meaning a shadow commit is pending. PER, DTY0 and DTY1 are SHADOW-BUFFERED, so a readback returns the STAGING value and the commit happens at the period wrap, observable through UPDF, while POL is immediate. The period is (PER + 1) mclk at prescaler 0.
# Router row 0 uses HhENX at 0x700C with sources 115 and 116 at bits 19 and 20. The IVT is a per-test tail that supersedes the env's meip arming, placing plain-ret handlers at slots 115 and 116.
# THE PRIORITY PROOF: with the route OFF, both flags are set, the period event from the first boundary and the fault from a software trip, and neither delivers. Then BOTH routes are enabled in one write, and the router's claim must return the LOWEST pending id first, the fault before the event. The handlers stamp a monotonic order counter, and the fault MUST be first.
# PWM0 is mclk-domain, so no SYS_CLK_CR write is needed. A large period value makes the period about 2.7 ms, so EXACTLY ONE period event asserts in the test window.

#include "riscv_test.h"
#include "test_macros.h"

#define PWM_CR      0x6600
#define PWM_PER     0x6604
#define PWM_DTY0    0x6608
#define PWM_SR      0x6620
#define IRTR_ENX    0x700C

/* CR: PWMEN(0)|CH0EN(1)|PEVIE(7)|FLTIE(8)|FLTEN(12), PSC=0 */
#define PWM_CR_EN   0x00001183
/* same + FLTTRIG(14) to trip the SW fault */
#define PWM_CR_FLT  0x00005183
#define PWM_PER_VAL 0x0000FFFF        /* ~2.7ms period -> one PEVF in window */
#define ENX_PWM     0x00180000        /* bit19 (115 fault) + bit20 (116 evt) */
#define SR_FLTF     0x1
#define SR_PEVF     0x2
#define SR_UPDF     0x4
#define SR_FLT_PEV  0x3               /* FLTF | PEVF */

#define DONE_FAULT  0xA000
#define DONE_EVT    0xA004
#define ORDER_CTR   0xA008            /* monotonic claim-order counter */
#define FAULT_SEQ   0xA00C            /* order stamp of the fault handler */
#define EVT_SEQ     0xA010            /* order stamp of the evt handler   */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0

    li   t0, DONE_FAULT
    sw   x0, 0(t0)
    li   t0, DONE_EVT
    sw   x0, 0(t0)
    li   t0, ORDER_CTR
    sw   x0, 0(t0)
    li   t0, FAULT_SEQ
    sw   x0, 0(t0)
    li   t0, EVT_SEQ
    sw   x0, 0(t0)

    # ================= L0: reset defaults ==============================
    li   a0, PWM_CR
    lw   t0, 0(a0)
    bnez t0, wpwm_fail
    li   a0, PWM_SR
    lw   t0, 0(a0)
    bnez t0, wpwm_fail

    # ================= L1: shadow-buffer spot check (PWMEN=0) ==========
    # Stage PER + DTY0 with the engine stopped: readback returns STAGING and
    # UPDF (SR bit2) latches pending (no period boundary can commit yet).
    li   a0, PWM_PER
    li   t1, PWM_PER_VAL
    sw   t1, 0(a0)
    li   a0, PWM_DTY0
    li   t1, 0x00000010
    sw   t1, 0(a0)
    lw   t0, 0(a0)                    # DTY0 readback = staging
    li   t1, 0x00000010
    bne  t0, t1, wpwm_fail
    li   a0, PWM_SR
    lw   t0, 0(a0)
    andi t0, t0, SR_UPDF
    beqz t0, wpwm_fail                # UPDF must be pending (staged, uncommitted)

    # ================= L2: enable engine -> first boundary commits =====
    # PWMEN|CH0EN|PEVIE|FLTIE|FLTEN, route STILL off. At reset per_active=0 so
    # the first tick wraps immediately: PEVF sets AND the staged PER commits
    # (UPDF clears) — proving the shadow value became active.
    li   a0, PWM_CR
    li   t1, PWM_CR_EN
    sw   t1, 0(a0)

    li   a1, PWM_SR
    li   s3, 20000
wpwm_wevt:
    lw   t0, 0(a1)
    andi t0, t0, SR_PEVF
    bnez t0, wpwm_committed
    addi s3, s3, -1
    bnez s3, wpwm_wevt
    j    wpwm_fail
wpwm_committed:
    lw   t0, 0(a1)
    andi t0, t0, SR_UPDF
    bnez t0, wpwm_fail               # UPDF must have cleared at the boundary

    # ================= L3: SW fault-trip (route still off) =============
    li   a0, PWM_CR
    li   t1, PWM_CR_FLT
    sw   t1, 0(a0)                    # FLTEN already 1 -> FLTTRIG sets FLTF

    # wait until BOTH FLTF and PEVF are pending (deterministic before routing)
    li   s3, 20000
wpwm_wboth:
    lw   t0, 0(a1)
    andi t0, t0, SR_FLT_PEV
    li   t1, SR_FLT_PEV
    beq  t0, t1, wpwm_route
    addi s3, s3, -1
    bnez s3, wpwm_wboth
    j    wpwm_fail

    # ================= L4: enable BOTH routes -> priority claim ========
wpwm_route:
    li   t0, IRTR_ENX
    li   t1, ENX_PWM
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wpwm_fail

    # both delivered? (order-independent DONE flags)
    li   s0, DONE_FAULT
    li   s1, DONE_EVT
    li   s3, 20000
wpwm_poll:
    lw   t0, 0(s0)
    beqz t0, wpwm_dec
    lw   t1, 0(s1)
    beqz t1, wpwm_dec
    j    wpwm_check
wpwm_dec:
    addi s3, s3, -1
    bnez s3, wpwm_poll
    j    wpwm_fail

wpwm_check:
    # fault (115) claimed FIRST (order 1); evt (116) second (order 2)
    li   t0, FAULT_SEQ
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wpwm_fail
    li   t0, EVT_SEQ
    lw   t1, 0(t0)
    li   t2, 2
    bne  t1, t2, wpwm_fail

    RVTEST_PASS

wpwm_fail:
    RVTEST_FAIL

    # ---- PWM0 fault handler (vec 115, plain-ret) — W1C FLTF, stamp order ---
    .section .text.init
pwm0_fault_h:
    li   t0, PWM_SR
    li   t1, SR_FLTF
    sw   t1, 0(t0)                    # W1C FLTF -> drop irq_fault level
    li   t0, ORDER_CTR
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    li   t0, FAULT_SEQ
    sw   t1, 0(t0)                    # record my order (must be 1)
    li   t0, DONE_FAULT
    li   t1, 0x00000115
    sw   t1, 0(t0)
    ret

    # ---- PWM0 period-event handler (vec 116, plain-ret) — W1C PEVF --------
pwm0_evt_h:
    li   t0, PWM_SR
    li   t1, SR_PEVF
    sw   t1, 0(t0)                    # W1C PEVF -> drop irq_evt level
    li   t0, ORDER_CTR
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    li   t0, EVT_SEQ
    sw   t1, 0(t0)                    # record my order (must be 2)
    li   t0, DONE_EVT
    li   t1, 0x00000116
    sw   t1, 0(t0)
    ret

    # ---- per-test IVT tail: arm 83/84/85 then slots 115 & 116 ------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00               # 83 msip  -> park
    jal  zero, 0x0BB00               # 84 mtip  -> park
    jal  zero, 0x09100               # 85 meip  -> env dispatcher (.isr_meip)
    .org 4*115                       # slot 115 @ 0x1CC
    jal  zero, pwm0_fault_h          # 115 = IRQB_PWM0_FAULT
    jal  zero, pwm0_evt_h            # 116 = IRQB_PWM0_EVT (next word 0x1D0)
    .previous

    # ---- env meip dispatcher (.isr_meip @0x9100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
