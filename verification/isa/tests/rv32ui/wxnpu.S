# See LICENSE for license details.

# VestaRV: NPU XNOR/popcount firmware smoke
# Hart 0 only, tiles parked; MODE = 2, taking the same vector-120 think-done IRQ leg as the rest of the family in the same order (PENDX rider with the route OFF first, then enable ENX, INSVCX in the handler, exactly-once, negctrl-lite settle, un-route). Case: K = 40, N = 4, THRESH = 0, NPUBEN = 0 and NPUAEN = 0, since XNOR does not reuse the bias or GET_WEIGHT branch, and NW = ceil(K/32) = 2 packed words per neuron, so NPUNI = 1.
# K = 40 IS DELIBERATE: 40 mod 32 = 8, so tail_mask = 0xFF and only the low 8 bits of each vector's word 1 are counted, leaving bits [31:8] of that word unused in both the shared activation and every neuron's weight. This test stages ADVERSARIAL nonzero garbage there, chosen so that a DUT which forgot to mask the XNOR RESULT and popcounted all 64 fetched bits flips neurons 1 and 3 from no-fire to fire. An unmasked tail therefore fails this test rather than silently passing it.
# Register bank: NPUCR 0x4A00 = ACTF[25:23] MODE[22:20] TDIE[19] BEN[18] AEN[17] THINK[16] NI[15:8] = NW-1 NN[7:0] = N-1; IVSAR 0x4A04, WVSAR 0x4A08, OVSAR 0x4A0C are 12-bit staging-RAM WORD indices; NPUSR 0x4A10 bit 0 THINKDONE is sticky W1C; NPUCFG1 0x4A14 carries the full signed 32-bit THRESH under XNOR; NPUCFG2 0x4A18 carries the exact K in bits [12:0]; NPUCFG3 0x4A1C has no storage and reads 0; offset +0x20 is outside the 8-word decode and reads 0. The L2 readback of those two known-zero corners is the 4-bit MabMmrA decode smoke.
# Staging RAM, word index = (addr - 0xC000)/4, clear of shnpu's 0xC100-0xC110 and wnpuconv's 0xC400/0xC500/0xC600 bands: X_ADDR 0xC700 holds NW = 2 words of the ONE shared activation vector, since XNOR has no per-neuron activation; W_ADDR 0xC740 holds N*NW = 8 words neuron-major, with neuron n's words at WVSAR + n*NW; OUT_ADDR 0xC780 holds N = 4 words, one per neuron.
# Golden values come from verification/npu/gen_wxnpu_golden.py, built on the frozen bench arithmetic with no floats and no MAC, pure bit-exact integer popcount. The four neurons land at +20, -20, +10 and -10 from agreement counts of 30, 10, 25 and 15 against a deterministic alternating 40-bit activation, a clean two-of-four fire mix well clear of THRESH = 0 on the correct masked semantics.
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

    # ---- env meip dispatcher (.isr_meip @0x9100) + IVT slot 85 ----------
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
