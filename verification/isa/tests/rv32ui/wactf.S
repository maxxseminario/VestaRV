# See LICENSE for license details.

#*****************************************************************************
# wactf.S  (wound-config firmware smoke -- digperiphs P4.4 Stage S5)
#-----------------------------------------------------------------------------
# NPU ACTF activation mux (MODE=0, legacy MLP) firmware smoke, hart 0 only
# (single-hart directed; tiles stay parked -- no MP_STAGE_IMAGE, no
# mp_boot.h; the SAME majority w* precedent shape as wnpuconv.S/wxnpu.S/
# wgemm.S). Companion to shnpu.S (the shared-NPU MLP + vector-120 IRQ-leg
# precedent) and wgemm.S (the two-layer GEMM firmware smoke this file mirrors
# structurally): proves the ACTF activation mux (npu_actf_design.md D1-D9)
# end-to-end through firmware, at the SAME MCU/silicon generics as the RTL
# bench (X_M=0, W_M=7, Y_M=7, N=24, RHO=2), taking the SAME vector-120
# think-done IRQ leg the family precedent takes (mirrored EXACTLY: PENDX
# rider with the route OFF first -- deterministic, no delivery race -- then
# enable ENX, INSVCX-in-handler rider, exactly-once, negctrl-lite settle,
# un-route) on the LAST THINK.
#
# ONE staged MLP layer (NI=0 -> 1 input, NN=1 -> 2 neurons, BEN=0), reused
# across a SWEEP of SEVEN THINKs -- only OVSAR (and, for the two groups that
# need a different accumulator magnitude, WVSAR) is re-pointed between
# THINKs so results never overwrite each other (design-doc D12):
#
#   Group A (X=0.5, W_A0=+1.0/W_A1=-1.0 -> acc0=+0.5/acc1=-0.5, BOTH deep
#   inside the sigmoid/tanh linear band |acc|<2, mixed sign):
#     THINK1  ACTF=0 AEN=1  sigmoid            (legacy compatibility anchor)
#     THINK2  ACTF=1 AEN=1  ReLU               (+ passes raw, - -> 0)
#     THINK3  ACTF=2 AEN=1  tanh = 2*sigma(2x)-1 (- must sign-extend negative)
#     THINK6  ACTF=5 AEN=1  reserved -> MUST equal THINK1's sigmoid words (D6)
#     THINK7  ACTF=2 AEN=0  master-enable proof -> raw Q7.24 passthrough (D1)
#
#   Group B (X=0.5, W_B0=+3.0/W_B1=+0.25 -> acc0=+1.5/acc1=+0.125):
#     THINK4  ACTF=3 AEN=1  clamp/hardtanh -- acc0 >= +1.0 clamps to the
#             +rail 0x00FFFFFF; acc1 (in-range) is the identity (D4)
#
#   Group C (X=0.5, W_C0=0.0/W_C1=-1.0 -> acc0=0 exactly/acc1=-0.5):
#     THINK5  ACTF=4 AEN=1  exp-approx = 2*sigma(x) -- acc0=0 -> EXACTLY
#             0x01000000 (1.0, the softmax boundary); acc1<0 -> word in
#             (0, 1.0) (D5)
#
# Golden values: computed by ~/vestarv/verification/npu/gen_wactf_golden.py
# (a throwaway script built entirely on the VALIDATED npu_fixed.py arithmetic
# core -- think_layer()/activate(), reused verbatim per npu_actf_design.md
# D9, never reimplements the MAC/sigmoid/activation arithmetic). That script
# self-checks: THINK1 accs are mixed-sign and |acc|<2 and equal a direct
# sigmoid() call; THINK2 ReLU(+)=passthrough, ReLU(-)=0 (!= sigmoid(-));
# THINK3 tanh(-) is NEGATIVE and sign-extends negative in the full 32-bit
# word (GA3); THINK4 acc0 is exactly 1.5 and clamps to 0x00FFFFFF (!= the
# raw acc), acc1 is the in-range identity; THINK5 acc0 is exactly 0 and
# exp~(0) == 1<<24 == 0x01000000 exactly, acc1<0 gives a word in (0,
# 0x01000000); THINK6 words == THINK1 words bit-for-bit; THINK7 == the raw
# Group-A accumulators and != THINK3's tanh output (master-enable proof).
#
# Register interface (npu_actf_design.md D8 -- ZERO entity changes; the SAME
# 8-word MMR bank wnpuconv.S/wxnpu.S/wgemm.S exercise; MLP (MODE=0) simply
# does not consume NPUCFG1/NPUCFG2, exactly like GEMM ignoring NPUCFG2 --
# storage/readback is generic and mode-independent):
#   NPUCR   0x4A00 (+0)   ACTF[25:23] MODE[22:20]=0(MLP) TDIE[19] BEN[18]=0
#                          AEN[17] THINK[16] NI[15:8]=0(1 input) NN[7:0]=1
#                          (2 neurons)
#   IVSAR   0x4A04 (+4)   WVSAR 0x4A08 (+8)   OVSAR 0x4A0C (+C)  (12-bit
#                          staging-RAM WORD indices)
#   NPUSR   0x4A10 (+10)  bit0 THINKDONE, sticky W1C (sets on NpuDone
#                          regardless of TDIE -- TDIE only gates delivery)
#   NPUCFG1 0x4A14 (+14)  MLP: unconsumed (D8) -- write/readback smoked once
#                          below purely as a generic MMR storage proof
#   NPUCFG2 0x4A18 (+18)  MLP: unconsumed (D8) -- same generic storage proof
#   NPUCFG3 0x4A1C (+1C)  AS-BUILT: no storage, reads 0 (unchanged)
#   +0x20 (offset 8)      out of the 8-word decode ("when others"), reads 0
# This test's L2 readback doubles as the same 4-bit MabMmrA decode smoke
# wnpuconv.S/wxnpu.S/wgemm.S's headers document (CFG3 + offset-8 both
# known-zero corners) -- the entity is untouched (D8), so the decode
# behaves identically per mode. L3 adds the NEW ACTF-field readback smoke
# (npu_actf_design.md D12): NPUCR bits[25:23] round-trip for a THINK=0 write
# exactly like every other stored NPUCR field.
#
# Staging-RAM layout (word index = (addr-0xC000)/4), clear of shnpu's
# 0xC100-0xC110 band, wnpuconv's 0xC400/0xC500/0xC600 bands, wxnpu's
# 0xC700/0xC740/0xC780 bands, and wgemm's 0xC800-0xC904 bands:
#   X_ADDR    = 0xCA00 (word 0x280): the ONE shared input (all 3 groups)
#   WVA_ADDR  = 0xCA10 (word 0x284): W_A0 @+0, W_A1 @+4 (Group A, 2 words)
#   WVB_ADDR  = 0xCA20 (word 0x288): W_B0 @+0, W_B1 @+4 (Group B, 2 words)
#   WVC_ADDR  = 0xCA30 (word 0x28C): W_C0 @+0, W_C1 @+4 (Group C, 2 words)
#   OV_T1..OV_T7 = 0xCA40/48/50/58/60/68/70 (word 0x290/292/294/296/298/
#                  29A/29C): 2 words each (one per neuron), one region per
#                  THINK so no result is ever overwritten by a later THINK
#
# Scratch: private TCM 0xA000/0xA004 (single-hart directed -- the
# wnpuconv/wxnpu/wgemm/wrtc/wow/wi2ct/wqspi/wgpio/wi3c/wtrng precedent; no
# shared-window word needed, there is no second hart to rendezvous with).
#   TD_FLAG = 0xA000   (ISR exactly-once counter)
#   TD_ISVC = 0xA004   (handler's masked INSVCX readback)
#
# NPU is mclk-domain (like DMA0/TRNG0) -- NO SYS_CLK_CR write needed (that
# rule is only for the smclk peripherals: UART/I2C/...).
#
# IVT gotcha (shnpu.S/wnpuconv.S/wxnpu.S/wgemm.S precedent, unchanged for
# this test): this test's .ivt extension also stops at slot 120 (same
# vector, NPU0_TD) -- WITHOUT parking slots 121-127 the trailing zero-run to
# the fixed .text.init link address (0x8200) is only 7 zero words, one short
# of flash_prepend.sh's GAP_MIN(8) region-split threshold, and gets silently
# MERGED into one oversized segment (proven to corrupt the boot copy in
# simulation -- see shnpu.S's header for the full forensics). Slots 121-127
# are parked here for the same reason.
#*****************************************************************************

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

    # ---- env meip dispatcher (.isr_meip @0xB100) + IVT slot 85 ----------
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
