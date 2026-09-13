# See LICENSE for license details.

# VestaRV: NPU activation-mux firmware smoke
# Hart 0 only, tiles parked; MODE = 0 (legacy MLP) at the silicon generics X_M = 0, W_M = 7, Y_M = 7, N = 24, RHO = 2, taking the same vector-120 think-done IRQ leg as the rest of the family on the LAST THINK (PENDX rider with the route OFF first, then enable ENX, INSVCX in the handler, exactly-once, negctrl-lite settle, un-route).
# ONE staged MLP layer (NI = 0 for a single input, NN = 1 for two neurons, BEN = 0) is reused across SEVEN THINKs; only OVSAR, and WVSAR for the groups needing a different accumulator magnitude, is re-pointed between THINKs so no result overwrites another. Group A (X = 0.5, W = +1.0 and -1.0, so acc = +0.5 and -0.5, both inside the linear band and mixed in sign) runs THINK1 ACTF = 0 sigmoid, THINK2 ACTF = 1 ReLU, THINK3 ACTF = 2 tanh, THINK6 ACTF = 5 reserved which MUST equal THINK1's sigmoid words bit for bit, and THINK7 ACTF = 2 with AEN = 0, which must pass the raw Q7.24 accumulator through. Group B (W = +3.0 and +0.25, acc = +1.5 and +0.125) runs THINK4 ACTF = 3 clamp, where acc0 clamps to the + rail 0x00FFFFFF and acc1 is the identity. Group C (W = 0.0 and -1.0, acc = 0 exactly and -0.5) runs THINK5 ACTF = 4 exp-approx, where acc0 = 0 must give exactly 0x01000000 and acc1 < 0 a word strictly inside (0, 1.0).
# Register bank: NPUCR 0x4A00 = ACTF[25:23] MODE[22:20] TDIE[19] BEN[18] AEN[17] THINK[16] NI[15:8] NN[7:0]; IVSAR 0x4A04, WVSAR 0x4A08, OVSAR 0x4A0C are 12-bit staging-RAM WORD indices; NPUSR 0x4A10 bit 0 THINKDONE is sticky W1C and sets regardless of TDIE, which only gates delivery; NPUCFG1 0x4A14 and NPUCFG2 0x4A18 are unconsumed in MLP mode and are written and read back only as a generic MMR storage proof; NPUCFG3 0x4A1C has no storage and reads 0; offset +0x20 is outside the 8-word decode and reads 0. L2 reads those two known-zero corners as the MabMmrA decode smoke, and L3 round-trips NPUCR[25:23] on a THINK = 0 write.
# Staging RAM, word index = (addr - 0xC000)/4, clear of the shnpu, wnpuconv, wxnpu and wgemm bands: X_ADDR 0xCA00 is the one shared input, WVA 0xCA10, WVB 0xCA20 and WVC 0xCA30 hold two weight words each, and OV_T1..OV_T7 at 0xCA40 through 0xCA70 in steps of 8 hold two words each, one region per THINK.
# Golden values come from verification/npu/gen_wactf_golden.py, built on the validated npu_fixed.py arithmetic core, which self-checks each group's defining property before printing.
# Scratch lives in private TCM, TD_FLAG = 0xA000 and TD_ISVC = 0xA004. The NPU is mclk-domain, so no SYS_CLK_CR write is needed. IVT GOTCHA: this file's .ivt extension stops at slot 120, and slots 121-127 MUST stay parked, or the trailing zero run to the fixed .text.init link address 0x8200 is one word short of flash_prepend.sh's GAP_MIN of 8 and the regions merge into one oversized segment that corrupts the boot copy.

#include "riscv_test.h"
#include "test_macros.h"

#define NPU_BASE     0x4A00
#define O_CR         0x00
#define O_IVSAR      0x04
#define O_WVSAR      0x08
#define O_OVSAR      0x0C
#define O_SR         0x10
#define O_CFG1       0x14
#define O_CFG2       0x18
#define O_CFG3       0x1C
#define O_OFF8       0x20

#define X_ADDR       0xCA00
#define WVA_ADDR     0xCA10
#define WVB_ADDR     0xCA20
#define WVC_ADDR     0xCA30

#define X_WORD       0x280          /* 0xCA00 */
#define WVA_WORD     0x284          /* 0xCA10 */
#define WVB_WORD     0x288          /* 0xCA20 */
#define WVC_WORD     0x28C          /* 0xCA30 */

#define OV_T1        0xCA40
#define OV_T2        0xCA48
#define OV_T3        0xCA50
#define OV_T4        0xCA58
#define OV_T5        0xCA60
#define OV_T6        0xCA68
#define OV_T7        0xCA70

#define OV_T1_WORD   0x290
#define OV_T2_WORD   0x292
#define OV_T3_WORD   0x294
#define OV_T4_WORD   0x296
#define OV_T5_WORD   0x298
#define OV_T6_WORD   0x29A
#define OV_T7_WORD   0x29C

#define CFG1_SMOKE   0x00005A5A      /* MLP ignores CFG1 (D8); readback-only */
#define CFG2_SMOKE   0x00002468      /* MLP ignores CFG2 (D8); readback-only */

#define TDIE         0x00080000     /* NPUCR bit19: think-done IRQ enable */
#define AEN_BIT      0x00020000     /* NPUCR bit17 */
#define THINK_BIT    0x00010000     /* NPUCR bit16 */
#define NI_NN_FIELD  0x00000001     /* NI=0(1 input)[15:8], NN=1(2 neurons)[7:0] */

#define ACTF0_FIELD  0x00000000     /* ACTF=0 sigmoid   (bits 25:23 = 000) */
#define ACTF1_FIELD  0x00800000     /* ACTF=1 ReLU      (bits 25:23 = 001) */
#define ACTF2_FIELD  0x01000000     /* ACTF=2 tanh      (bits 25:23 = 010) */
#define ACTF3_FIELD  0x01800000     /* ACTF=3 clamp     (bits 25:23 = 011) */
#define ACTF4_FIELD  0x02000000     /* ACTF=4 exp       (bits 25:23 = 100) */
#define ACTF5_FIELD  0x02800000     /* ACTF=5 reserved  (bits 25:23 = 101) */
#define ACTF7_FIELD  0x03800000     /* ACTF=7 reserved  (bits 25:23 = 111; readback-only smoke */

/* MODE[22:20] = 0 (legacy MLP) at every THINK below -- no field needed */
#define CR_THINK1      (THINK_BIT | AEN_BIT | ACTF0_FIELD | NI_NN_FIELD)  /* 0x00030001 */
#define CR_THINK2      (THINK_BIT | AEN_BIT | ACTF1_FIELD | NI_NN_FIELD)  /* 0x00830001 */
#define CR_THINK3      (THINK_BIT | AEN_BIT | ACTF2_FIELD | NI_NN_FIELD)  /* 0x01030001 */
#define CR_THINK4      (THINK_BIT | AEN_BIT | ACTF3_FIELD | NI_NN_FIELD)  /* 0x01830001 */
#define CR_THINK5      (THINK_BIT | AEN_BIT | ACTF4_FIELD | NI_NN_FIELD)  /* 0x02030001 */
#define CR_THINK6      (THINK_BIT | AEN_BIT | ACTF5_FIELD | NI_NN_FIELD)  /* 0x02830001 */
#define CR_THINK7_TDIE (THINK_BIT | ACTF2_FIELD | TDIE | NI_NN_FIELD)     /* 0x01090001 (AEN=0) */

#define IRTR_ENX     0x700C         /* HhENX, hart-0 row (sources 96-127) */
#define IRTR_PENDX   0x781C         /* RO pending, sources 96-127 */
#define IRTR_INSVCX  0x782C         /* RO in_service, sources 96-127 */
#define TD_SRC_BIT   0x01000000     /* bit24: source 120 (120-96) */

#define TD_FLAG      0xA000         /* ISR exactly-once counter */
#define TD_ISVC      0xA004         /* handler's masked INSVCX readback */

#define POLL_BUD     20000
#define SETTLE_BUD   2000

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0                 # valid stack before any IRQ (IRQ_SV pushes PC)
    li   s0, NPU_BASE

    # ================= L0: reset defaults ==============================
    lw   t0, O_CR(s0)
    bnez t0, wactf_fail             # NPUCR resets 0
    lw   t0, O_IVSAR(s0)
    bnez t0, wactf_fail
    lw   t0, O_WVSAR(s0)
    bnez t0, wactf_fail
    lw   t0, O_OVSAR(s0)
    bnez t0, wactf_fail
    lw   t0, O_CFG1(s0)
    bnez t0, wactf_fail
    lw   t0, O_CFG2(s0)
    bnez t0, wactf_fail

    # NPUSR (0x4A10) is sticky W1C; clear unconditionally (no reset
    # precondition asserted -- mirrors shnpu/wnpuconv/wxnpu/wgemm's IRQ-leg
    # discipline) and prove the clear actually lands.
    li   t0, 1
    sw   t0, O_SR(s0)
    lw   t1, O_SR(s0)
    bnez t1, wactf_fail

    # ================= L1: stage the shared input + all 3 weight groups ===
    li   t0, X_ADDR
    li   t1, 0x00800000              # X = 0.5 (Q0.24, shared by every group)
    sw   t1, 0(t0)

    li   t0, WVA_ADDR
    li   t1, 0x01000000              # W_A0 = +1.0 (Q7.24) -> acc0 = +0.5
    sw   t1, 0(t0)
    li   t1, 0xFF000000              # W_A1 = -1.0 (Q7.24) -> acc1 = -0.5
    sw   t1, 4(t0)

    li   t0, WVB_ADDR
    li   t1, 0x03000000              # W_B0 = +3.0 (Q7.24) -> acc0 = +1.5 (clamp rail)
    sw   t1, 0(t0)
    li   t1, 0x00400000              # W_B1 = +0.25 (Q7.24) -> acc1 = +0.125 (in-range)
    sw   t1, 4(t0)

    li   t0, WVC_ADDR
    sw   x0, 0(t0)                   # W_C0 = 0.0 -> acc0 = 0 exactly
    li   t1, 0xFF000000              # W_C1 = -1.0 (Q7.24) -> acc1 = -0.5
    sw   t1, 4(t0)

    # C_Tn output regions -- zero (must be overwritten by their own THINK)
    li   t0, OV_T1
    sw   x0, 0(t0)
    sw   x0, 4(t0)
    li   t0, OV_T2
    sw   x0, 0(t0)
    sw   x0, 4(t0)
    li   t0, OV_T3
    sw   x0, 0(t0)
    sw   x0, 4(t0)
    li   t0, OV_T4
    sw   x0, 0(t0)
    sw   x0, 4(t0)
    li   t0, OV_T5
    sw   x0, 0(t0)
    sw   x0, 4(t0)
    li   t0, OV_T6
    sw   x0, 0(t0)
    sw   x0, 4(t0)
    li   t0, OV_T7
    sw   x0, 0(t0)
    sw   x0, 4(t0)

    # ================= L2: NPUCFG1/2 generic MMR storage smoke (MLP =======
    # ================= ignores both, D8) + the CFG3/offset-8 known-zero ====
    # ================= corners (4-bit MabMmrA decode, unchanged by mode) ===
    li   t0, CFG1_SMOKE
    sw   t0, O_CFG1(s0)
    lw   t1, O_CFG1(s0)
    bne  t1, t0, wactf_fail

    li   t0, CFG2_SMOKE
    sw   t0, O_CFG2(s0)
    lw   t1, O_CFG2(s0)
    bne  t1, t0, wactf_fail

    lw   t0, O_CFG3(s0)
    bnez t0, wactf_fail
    lw   t0, O_OFF8(s0)
    bnez t0, wactf_fail

    # clear CFG1/CFG2 back to 0 (no residue into the THINK sweep below)
    sw   x0, O_CFG1(s0)
    sw   x0, O_CFG2(s0)

    # ================= L3: NPUCR ACTF-field readback smoke (D12) -- a =====
    # ================= plain register round-trip, THINK=0 so no FSM ever ==
    # ================= starts; write ACTF=7 (all-ones field) + confirm =====
    # ================= the exact bit pattern reads back, then clear ========
    li   t0, ACTF7_FIELD
    sw   t0, O_CR(s0)
    lw   t1, O_CR(s0)
    bne  t1, t0, wactf_fail
    sw   x0, O_CR(s0)
    lw   t1, O_CR(s0)
    bnez t1, wactf_fail

    # ================= L4: configure Group A (IVSAR/WVSAR) =================
    li   t0, X_WORD
    sw   t0, O_IVSAR(s0)
    lw   t1, O_IVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, WVA_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wactf_fail

    # ================= THINK1: ACTF=0 sigmoid (legacy compat anchor) ======
    li   t0, OV_T1_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK1
    sw   t0, O_CR(s0)
    jal  ra, wactf_poll_and_clear

    li   t0, 0x009E0000               # T1 out[0] (sigmoid(+0.5))
    li   t1, OV_T1
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0x00620000               # T1 out[1] (sigmoid(-0.5))
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # ================= THINK2: ACTF=1 ReLU (same Group A, same IVSAR/WVSAR)
    li   t0, OV_T2_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK2
    sw   t0, O_CR(s0)
    jal  ra, wactf_poll_and_clear

    li   t0, 0x00800000               # T2 out[0] = raw acc (+0.5, ReLU passthrough)
    li   t1, OV_T2
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0x00000000               # T2 out[1] = exactly 0 (ReLU of -0.5)
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # ================= THINK3: ACTF=2 tanh (same Group A) ==================
    li   t0, OV_T3_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK3
    sw   t0, O_CR(s0)
    jal  ra, wactf_poll_and_clear

    li   t0, 0x00700000               # T3 out[0] = tanh(+0.5) = 2*sigma(1.0)-1
    li   t1, OV_T3
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0xFF900000               # T3 out[1] = tanh(-0.5) -- SIGNED negative word
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # ================= configure Group B (WVSAR only -- X/IVSAR unchanged)
    li   t0, WVB_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wactf_fail

    # ================= THINK4: ACTF=3 clamp (Group B: acc0=+1.5 clamps, ===
    # ================= acc1=+0.125 in-range identity) ======================
    li   t0, OV_T4_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK4
    sw   t0, O_CR(s0)
    jal  ra, wactf_poll_and_clear

    li   t0, 0x00FFFFFF               # T4 out[0] = +rail (clamp(1.5))
    li   t1, OV_T4
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0x00200000               # T4 out[1] = 0.125 (identity, in-range)
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # ================= configure Group C (WVSAR only) ======================
    li   t0, WVC_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wactf_fail

    # ================= THINK5: ACTF=4 exp-approx (Group C: acc0=0 exactly,
    # ================= acc1=-0.5) ==========================================
    li   t0, OV_T5_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK5
    sw   t0, O_CR(s0)
    jal  ra, wactf_poll_and_clear

    li   t0, 0x01000000               # T5 out[0] = exp~(0) EXACTLY 1.0
    li   t1, OV_T5
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0x00C40000               # T5 out[1] = exp~(-0.5), in (0, 1.0)
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # ================= back to Group A (WVSAR only -- X/IVSAR unchanged) ===
    li   t0, WVA_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wactf_fail

    # ================= THINK6: ACTF=5 reserved -> MUST equal THINK1 =======
    li   t0, OV_T6_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK6
    sw   t0, O_CR(s0)
    jal  ra, wactf_poll_and_clear

    li   t0, 0x009E0000               # T6 out[0] == T1 out[0] (bit-identical, D6)
    li   t1, OV_T6
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0x00620000               # T6 out[1] == T1 out[1]
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # ================= THINK7: ACTF=2 AEN=0 -> master-enable proof; the ====
    # ================= vector-120 think-done IRQ leg rides THIS THINK ======
    # ================= (route OFF first -- deterministic, no delivery race)
    li   t0, TD_FLAG
    sw   x0, 0(t0)                  # exactly-once counter = 0
    li   t0, TD_ISVC
    sw   x0, 0(t0)

    li   t0, OV_T7_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wactf_fail

    li   t0, CR_THINK7_TDIE
    sw   t0, O_CR(s0)               # NPUCR = THINK|TDIE|ACTF=2|AEN=0|NI=0|NN=1

    li   t6, POLL_BUD
wactf_l7_wait_busy:
    lw   t0, O_CR(s0)
    srli t0, t0, 16
    andi t0, t0, 1                  # NPUCR bit16 = THINK (busy)
    beqz t0, wactf_l7_wait_flag
    addi t6, t6, -1
    bnez t6, wactf_l7_wait_busy
    j    wactf_fail

wactf_l7_wait_flag:
    lw   t1, O_SR(s0)
    andi t1, t1, 1                  # THINKDONE sets on NpuDone regardless of TDIE
    bnez t1, wactf_pendx
    addi t6, t6, -1
    bnez t6, wactf_l7_wait_flag
    j    wactf_fail

wactf_pendx:
    # RIDER: PENDX bit24 must be set (raw source pending; route still off ->
    # no delivery race on this poll)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    beqz t1, wactf_fail

    # enable the route -> meip -> dispatcher -> claim 120 -> handler
    li   t0, IRTR_ENX
    li   t1, TD_SRC_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wactf_fail

    li   t6, POLL_BUD
wactf_wait_deliv:
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, wactf_deliv_ok
    addi t6, t6, -1
    bnez t6, wactf_wait_deliv
    j    wactf_fail

wactf_deliv_ok:
    # exactly one delivery (in_service gateway)
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wactf_fail
    # RIDER: the handler recorded INSVCX bit24 while claimed
    li   t0, TD_ISVC
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    bne  t1, t2, wactf_fail
    # handler W1C'd NPUSR bit0 -> level dropped -> NPUSR reads 0
    lw   t1, O_SR(s0)
    bnez t1, wactf_fail
    # PENDX bit24 clear now too (raw source level dropped)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    bnez t1, wactf_fail

    # ================= exact Q7.24 raw-passthrough check (THINK7, AEN=0) ===
    # ================= -- must equal Group A's RAW accumulators, NOT the ===
    # ================= tanh output THINK3 computed at ACTF=2 ===============
    li   t0, 0x00800000               # T7 out[0] = raw acc (+0.5), NOT tanh(+0.5)=0x00700000
    li   t1, OV_T7
    lw   t2, 0(t1)
    bne  t2, t0, wactf_fail
    li   t0, 0xFF800000               # T7 out[1] = raw acc (-0.5), NOT tanh(-0.5)=0xFF900000
    lw   t2, 4(t1)
    bne  t2, t0, wactf_fail

    # settle window: let any (erroneous) second delivery happen (no new
    # THINK started, route still on), then confirm the counter stayed at 1
    li   t6, SETTLE_BUD
wactf_settle:
    addi t6, t6, -1
    bnez t6, wactf_settle
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wactf_fail

    li   t0, IRTR_ENX
    sw   x0, 0(t0)                  # un-route (clean)
    li   t0, NPU_BASE
    sw   x0, O_CR(t0)                # NPUCR back to reset default (TDIE off too)

    RVTEST_PASS

wactf_fail:
    RVTEST_FAIL

    # ---- wactf_poll_and_clear: start-independent helper used by THINK1-6
    # ---- (no TDIE) -- poll busy then THINKDONE, then W1C-clear NPUSR
    # ---- (verifying the clear lands) BEFORE the caller reads its output
    # ---- words, so THINKDONE can never leak into the next THINK in the
    # ---- sweep. Clobbers t0/t1/t6; the CALLER must already have written
    # ---- NPUCR (THINK=1) before calling. -----------------------------------
wactf_poll_and_clear:
    li   t6, POLL_BUD
wactf_pc_wait_busy:
    lw   t0, O_CR(s0)
    srli t0, t0, 16
    andi t0, t0, 1                  # NPUCR bit16 = THINK (busy)
    beqz t0, wactf_pc_wait_flag
    addi t6, t6, -1
    bnez t6, wactf_pc_wait_busy
    j    wactf_fail

wactf_pc_wait_flag:
    lw   t1, O_SR(s0)
    andi t1, t1, 1                  # THINKDONE sets on NpuDone regardless of TDIE
    bnez t1, wactf_pc_clear
    addi t6, t6, -1
    bnez t6, wactf_pc_wait_flag
    j    wactf_fail

wactf_pc_clear:
    li   t0, 1
    sw   t0, O_SR(s0)                # W1C
    lw   t1, O_SR(s0)
    bnez t1, wactf_fail
    jalr zero, 0(ra)

    # ---- NPU think-done handler (vector 120; M19 plain-ret meip ABI,
    # ---- shnpu.S/wnpuconv.S/wxnpu.S/wgemm.S's npu0_td_isr idiom). Reached
    # ---- via CLAIM=120 -> dispatcher jalr through IVT slot 120. Records
    # ---- the INSVCX in-handler proof, W1C-clears NPUSR bit0 (drops the
    # ---- level) BEFORE returning (the dispatcher COMPLETEs after), bumps
    # ---- the exactly-once counter. t0-t2 dispatcher-saved scratch; ra
    # ---- survives (ret). ---------------------------------------------------
    .section .text.init
npu0_actf_td_isr:
    li   t0, IRTR_INSVCX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2                 # isolate bit24 (source 120 in service)
    li   t0, TD_ISVC
    sw   t1, 0(t0)                  # mainline requires == TD_SRC_BIT
    li   t0, NPU_BASE
    li   t1, 1
    sw   t1, O_SR(t0)                # W1C bit0 -> THINKDONE clears, level drops
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    ret

    # ---- env meip dispatcher (.isr_meip @0x9100) + IVT slot 85 ----------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 120 = NPU0_TD (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85). Slot 120 @ .ivt+4*120 = 0x1E0. Slots
    # ---- 121-127 parked (shnpu.S's flash_prepend.sh zero-run merge-bug
    # ---- guard -- see this file's header). --------------------------------
    .section .ivt, "ax"
    .org 4*120
    jal  zero, npu0_actf_td_isr      # slot 120 = IRQB_NPU0_TD
    jal  zero, 0x0BB00               # slot 121 - reserved -> parked
    jal  zero, 0x0BB00               # slot 122 - reserved -> parked
    jal  zero, 0x0BB00               # slot 123 - reserved -> parked
    jal  zero, 0x0BB00               # slot 124 - reserved -> parked
    jal  zero, 0x0BB00               # slot 125 - reserved -> parked
    jal  zero, 0x0BB00               # slot 126 - reserved -> parked
    jal  zero, 0x0BB00               # slot 127 - reserved -> parked
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
