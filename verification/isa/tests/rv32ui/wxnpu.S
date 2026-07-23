# See LICENSE for license details.

#*****************************************************************************
# wxnpu.S  (wound-config firmware smoke -- digperiphs P4.2 Stage S5)
#-----------------------------------------------------------------------------
# NPU XNOR/popcount (MODE=2) firmware smoke, hart 0 only (single-hart
# directed; tiles stay parked -- no MP_STAGE_IMAGE, no mp_boot.h; the SAME
# majority w* precedent shape as wnpuconv.S/wtrng.S/wdma.S). Companion to
# shnpu.S (the shared-NPU MLP + vector-120 IRQ-leg precedent) and wnpuconv.S
# (the CONV1D firmware smoke this file mirrors structurally): proves the XNOR
# datapath/sequencer (npu_xnor_design.md D1-D6) end-to-end through firmware,
# exercising the SAME vector-120 think-done IRQ leg shnpu.S/wnpuconv.S both
# take (mirrored EXACTLY: PENDX rider with the route OFF first -- deterministic,
# no delivery race -- then enable ENX, INSVCX-in-handler rider, exactly-once,
# negctrl-lite settle, un-route).
#
# Case (npu_xnor_design.md D10-S5's own suggested shape):
#   K=40  N=4  THRESH=0  MODE=2 (xnor)  NPUBEN=0  NPUAEN=0 (D6 firmware
#   contract -- GX2: NPUBEN must stay 0 in XNOR, the bias/GET_WEIGHT branch
#   is not reused by this mode)
#   NW = ceil(K/32) = 2 packed words/neuron (NPUNI = NW-1 = 1)
#   K=40 is DELIBERATE (D3/GX1's tail-mask enforcement, D10-S5's own words):
#   40 mod 32 = 8 -> tail_mask = 0xFF, so only the LOW 8 bits of each
#   vector's word 1 are counted; bits [31:8] of word 1 (both the shared
#   activation AND every neuron's weight) are UNUSED/garbage-eligible. This
#   test stages ADVERSARIAL, nonzero garbage there -- computed by
#   ~/vestarv/verification/npu/gen_wxnpu_golden.py to be load-bearing: an
#   UNMASKED variant of the DUT (one that forgot D3's "mask the XNOR RESULT"
#   rule and popcounted all 64 fetched bits before subtracting K) flips
#   neurons 1 and 3's fire/no-fire decision relative to the correctly-masked
#   golden result (see that script's "unmasked-differs proof" section) -- a
#   DUT with an unmasked tail would FAIL this test, not silently pass it.
#
# Register interface (npu_xnor_design.md D5/D7 -- ZERO entity changes; the
# SAME 8-word MMR bank wnpuconv.S exercises, per-mode reinterpretation only):
#   NPUCR   0x4A00 (+0)   ACTF[25:23] MODE[22:20] TDIE[19] BEN[18] AEN[17]
#                          THINK[16] NI[15:8]=NW-1 NN[7:0]=N-1
#   IVSAR   0x4A04 (+4)   WVSAR 0x4A08 (+8)   OVSAR 0x4A0C (+C)  (12-bit
#                          staging-RAM WORD indices)
#   NPUSR   0x4A10 (+10)  bit0 THINKDONE, sticky W1C (M-series NPU IRQ leg)
#   NPUCFG1 0x4A14 (+14)  XNOR reinterpretation (D5): full signed 32-bit
#                          THRESH (conv reads this as S/D/L/Cin-1 packed)
#   NPUCFG2 0x4A18 (+18)  XNOR reinterpretation (D5): exact K in bits[12:0]
#                          (conv reads this as Lout[15:0])
#   NPUCFG3 0x4A1C (+1C)  AS-BUILT: no storage, reads 0 (unchanged, D7)
#   +0x20 (offset 8)      out of the 8-word decode ("when others"), reads 0
# This test's L2 readback doubles as the same 4-bit MabMmrA decode smoke
# wnpuconv.S's header documents (CFG3 + offset-8 both known-zero corners) --
# the entity is untouched (D7), so the decode behaves identically per mode.
#
# Staging-RAM layout (word index = (addr-0xC000)/4), clear of shnpu's
# 0xC100-0xC110 band and wnpuconv's 0xC400/0xC500/0xC600 bands:
#   X_ADDR   = 0xC700 (word 0x1C0, IV_WORD): NW=2 words, the ONE shared
#              activation vector (XNOR has no per-neuron activation -- every
#              neuron XNORs against the same staged bits)
#   W_ADDR   = 0xC740 (word 0x1D0, WV_WORD): N*NW = 8 words, neuron-major
#              (neuron n's NW words contiguous, at WVSAR + n*NW)
#   OUT_ADDR = 0xC780 (word 0x1E0, OV_WORD): N = 4 words, one per neuron
#
# Golden values: computed by ~/vestarv/verification/npu/gen_wxnpu_golden.py
# (a throwaway script built entirely on the FROZEN D9 bench arithmetic
# reused straight from verification/npu/gen_xnor_vectors.py's popcount_xnor/
# xnor_layer -- no floats, no MAC, pure bit-exact integer popcount, per the
# family's house rule). The four neurons land at values +20/-20/+10/-10
# (agreement counts 30/10/25/15 against a deterministic alternating 40-bit
# activation), a clean 2/4 fire mix well clear of THRESH=0 on the CORRECT
# (masked) semantics; the adversarial tail garbage (neuron 3's weight tail
# deliberately matches the activation's tail bit-for-bit, maximizing the
# popcount inflation an unmasked DUT would see there) is what makes neurons
# 1 and 3 flip to FIRE in the unmasked-bug simulation -- see that script's
# output for the exact proof.
#
# Scratch: private TCM 0xA000/0xA004 (single-hart directed -- the wnpuconv/
# wrtc/wow/wi2ct/wqspi/wgpio/wi3c/wtrng precedent; no shared-window word
# needed, there is no second hart to rendezvous with).
#   TD_FLAG = 0xA000   (ISR exactly-once counter)
#   TD_ISVC = 0xA004   (handler's masked INSVCX readback)
#
# NPU is mclk-domain (like DMA0/TRNG0) -- NO SYS_CLK_CR write needed (that
# rule is only for the smclk peripherals: UART/I2C/...).
#
# IVT gotcha (shnpu.S/wnpuconv.S precedent, unchanged for this test): this
# test's .ivt extension also stops at slot 120 (same vector, NPU0_TD) --
# WITHOUT parking slots 121-127 the trailing zero-run to the fixed
# .text.init link address (0x8200) is only 7 zero words, one short of
# flash_prepend.sh's GAP_MIN(8) region-split threshold, and gets silently
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

#define IV_WORD      0x1C0          /* 0xC700 */
#define WV_WORD      0x1D0          /* 0xC740 */
#define OV_WORD      0x1E0          /* 0xC780 */

#define X_ADDR       0xC700
#define W_ADDR       0xC740
#define OUT_ADDR     0xC780

#define CFG1_VAL     0                /* THRESH (full signed 32-bit) */
#define CFG2_VAL     40               /* K, exact bit count, NPUCFG2[12:0] */

#define MODE_XNOR    0x00200000     /* NPUCR[22:20] = 2 (xnor) */
#define TDIE         0x00080000     /* NPUCR bit19: think-done IRQ enable */
#define THINK_BIT    0x00010000     /* NPUCR bit16 */
#define NI_FIELD     0x00000100     /* NI = NW-1 = 1, at [15:8] */
#define NN_FIELD     0x00000003     /* NN = N-1 = 3, at [7:0] */
#define CR_XNOR_THINK_TDIE (MODE_XNOR | TDIE | THINK_BIT | NI_FIELD | NN_FIELD) /* 0x00290103 */
                                    /* BEN=0/AEN=0 (D6/GX2 firmware contract) */

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
    bnez t0, wxnpu_fail             # NPUCR resets 0
    lw   t0, O_IVSAR(s0)
    bnez t0, wxnpu_fail
    lw   t0, O_WVSAR(s0)
    bnez t0, wxnpu_fail
    lw   t0, O_OVSAR(s0)
    bnez t0, wxnpu_fail
    lw   t0, O_CFG1(s0)
    bnez t0, wxnpu_fail
    lw   t0, O_CFG2(s0)
    bnez t0, wxnpu_fail

    # NPUSR (0x4A10) is sticky W1C; clear unconditionally (no reset
    # precondition asserted -- mirrors shnpu/wnpuconv's IRQ-leg discipline)
    # and prove the clear actually lands.
    li   t0, 1
    sw   t0, O_SR(s0)
    lw   t1, O_SR(s0)
    bnez t1, wxnpu_fail

    # ================= L1: stage activation + weights (shared NPU staging =
    # ================= RAM) =================================================
    li   s1, X_ADDR
    li   s2, W_ADDR
    li   s3, OUT_ADDR

    # shared activation: NW=2 packed words, LSB-first over 40 counted bits
    # (word1's bits[31:8] are ADVERSARIAL tail garbage -- see the header)
    li   t0, 0xAAAAAAAA              # a_words[0]
    sw   t0, 0(s1)
    li   t0, 0xABCD12AA               # a_words[1] (bits[7:0]=0xAA counted; [31:8]=0xABCD12 garbage)
    sw   t0, 4(s1)

    # weights: N=4 neurons, NW=2 words/neuron, neuron-major
    # (neuron n's tail garbage per gen_wxnpu_golden.py's W_TAIL_GARBAGE table)
    li   t0, 0x6AAAAAAA               # w[0][0]
    sw   t0, 0(s2)
    li   t0, 0x5A5A5A55               # w[0][1] (unrelated tail garbage)
    sw   t0, 4(s2)
    li   t0, 0x555556AA               # w[1][0]
    sw   t0, 8(s2)
    li   t0, 0x0F0F0F55               # w[1][1] (unrelated tail garbage)
    sw   t0, 12(s2)
    li   t0, 0x54AAAAAA               # w[2][0]
    sw   t0, 16(s2)
    li   t0, 0xDEADBE55               # w[2][1] (unrelated tail garbage)
    sw   t0, 20(s2)
    li   t0, 0x55552AAA               # w[3][0]
    sw   t0, 24(s2)
    li   t0, 0xABCD1255               # w[3][1] (MATCHES a's tail exactly -- the flip-proof neuron)
    sw   t0, 28(s2)

    # zero the 4 output words -- must be overwritten by the run
    sw   x0, 0(s3)
    sw   x0, 4(s3)
    sw   x0, 8(s3)
    sw   x0, 12(s3)

    # ================= L2: configure + readback (4-bit decode smoke) =======
    li   t0, IV_WORD
    sw   t0, O_IVSAR(s0)
    lw   t1, O_IVSAR(s0)
    bne  t1, t0, wxnpu_fail

    li   t0, WV_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wxnpu_fail

    li   t0, OV_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wxnpu_fail

    li   t0, CFG1_VAL
    sw   t0, O_CFG1(s0)
    lw   t1, O_CFG1(s0)
    bne  t1, t0, wxnpu_fail

    li   t0, CFG2_VAL
    sw   t0, O_CFG2(s0)
    lw   t1, O_CFG2(s0)
    bne  t1, t0, wxnpu_fail

    # NPUCFG3 (offset 7, AS-BUILT no storage) and offset 8 (out of the
    # 8-word decode) BOTH read 0 -- the widened MabMmrA(3:0) decode smoke
    # (unchanged by mode -- D7 entity is ZERO changes).
    lw   t0, O_CFG3(s0)
    bnez t0, wxnpu_fail
    lw   t0, O_OFF8(s0)
    bnez t0, wxnpu_fail

    # ================= L3: THINK (MODE=XNOR|TDIE, route OFF first) =========
    li   t0, TD_FLAG
    sw   x0, 0(t0)                  # exactly-once counter = 0
    li   t0, TD_ISVC
    sw   x0, 0(t0)

    li   t0, CR_XNOR_THINK_TDIE
    sw   t0, O_CR(s0)               # NPUCR = MODE=2|TDIE|THINK|NI=1|NN=3, BEN=0/AEN=0

    li   t6, POLL_BUD
wxnpu_wait_busy:
    lw   t0, O_CR(s0)
    srli t0, t0, 16
    andi t0, t0, 1                  # NPUCR bit16 = THINK (busy)
    beqz t0, wxnpu_wait_flag
    addi t6, t6, -1
    bnez t6, wxnpu_wait_busy
    j    wxnpu_fail

wxnpu_wait_flag:
    lw   t1, O_SR(s0)
    andi t1, t1, 1
    bnez t1, wxnpu_pendx
    addi t6, t6, -1
    bnez t6, wxnpu_wait_flag
    j    wxnpu_fail

wxnpu_pendx:
    # RIDER: PENDX bit24 must be set (raw source pending; route still off ->
    # no delivery race on this poll)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    beqz t1, wxnpu_fail

    # enable the route -> meip -> dispatcher -> claim 120 -> handler
    li   t0, IRTR_ENX
    li   t1, TD_SRC_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wxnpu_fail

    li   t6, POLL_BUD
wxnpu_wait_deliv:
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, wxnpu_deliv_ok
    addi t6, t6, -1
    bnez t6, wxnpu_wait_deliv
    j    wxnpu_fail

wxnpu_deliv_ok:
    # exactly one delivery (in_service gateway)
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wxnpu_fail
    # RIDER: the handler recorded INSVCX bit24 while claimed
    li   t0, TD_ISVC
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    bne  t1, t2, wxnpu_fail
    # handler W1C'd NPUSR bit0 -> level dropped -> NPUSR reads 0
    lw   t1, O_SR(s0)
    bnez t1, wxnpu_fail
    # PENDX bit24 clear now too (raw source level dropped)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    bnez t1, wxnpu_fail

    # ================= L4: exact +-1.0 output check (all N=4 neurons) ======
    li   s4, OUT_ADDR
    li   t0, 0x01000000              # neuron 0: value=+20 -> FIRE
    lw   t1, 0(s4)
    bne  t1, t0, wxnpu_fail
    li   t0, 0xFF000000              # neuron 1: value=-20 -> no-fire
    lw   t1, 4(s4)
    bne  t1, t0, wxnpu_fail
    li   t0, 0x01000000              # neuron 2: value=+10 -> FIRE
    lw   t1, 8(s4)
    bne  t1, t0, wxnpu_fail
    li   t0, 0xFF000000              # neuron 3: value=-10 -> no-fire (the flip-proof neuron)
    lw   t1, 12(s4)
    bne  t1, t0, wxnpu_fail

    # ================= L5: negative-structure check -- operands survived ===
    li   t0, 0xAAAAAAAA
    lw   t1, 0(s1)
    bne  t1, t0, wxnpu_fail
    li   t0, 0xABCD12AA
    lw   t1, 4(s1)
    bne  t1, t0, wxnpu_fail

    li   t0, 0x6AAAAAAA
    lw   t1, 0(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0x5A5A5A55
    lw   t1, 4(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0x555556AA
    lw   t1, 8(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0x0F0F0F55
    lw   t1, 12(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0x54AAAAAA
    lw   t1, 16(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0xDEADBE55
    lw   t1, 20(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0x55552AAA
    lw   t1, 24(s2)
    bne  t1, t0, wxnpu_fail
    li   t0, 0xABCD1255
    lw   t1, 28(s2)
    bne  t1, t0, wxnpu_fail

    # settle window: let any (erroneous) second delivery happen (no new
    # THINK started, route still on), then confirm the counter stayed at 1
    li   t6, SETTLE_BUD
wxnpu_settle:
    addi t6, t6, -1
    bnez t6, wxnpu_settle
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wxnpu_fail

    li   t0, IRTR_ENX
    sw   x0, 0(t0)                  # un-route (clean)
    li   t0, NPU_BASE
    sw   x0, O_CR(t0)                # NPUCR back to reset default (TDIE off too)

    RVTEST_PASS

wxnpu_fail:
    RVTEST_FAIL

    # ---- NPU XNOR think-done handler (vector 120; M19 plain-ret meip ABI,
    # ---- shnpu.S/wnpuconv.S's npu0_td_isr idiom). Reached via CLAIM=120 ->
    # ---- dispatcher jalr through IVT slot 120. Records the INSVCX
    # ---- in-handler proof, W1C-clears NPUSR bit0 (drops the level) BEFORE
    # ---- returning (the dispatcher COMPLETEs after), bumps the
    # ---- exactly-once counter. t0-t2 dispatcher-saved scratch; ra survives
    # ---- (ret). --------------------------------------------------------
    .section .text.init
npu0_xnor_td_isr:
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
    jal  zero, npu0_xnor_td_isr      # slot 120 = IRQB_NPU0_TD
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
