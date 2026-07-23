# See LICENSE for license details.

#*****************************************************************************
# wnpuconv.S  (wound-config firmware smoke -- digperiphs P4.1 Stage S6)
#-----------------------------------------------------------------------------
# NPU CONV1D (MODE=1) firmware smoke, hart 0 only (single-hart directed; tiles
# stay parked -- no MP_STAGE_IMAGE, no mp_boot.h; the majority w* precedent,
# same shape as wtrng.S/wdma.S). Companion to shnpu.S (the shared-NPU MLP +
# vector-120 IRQ-leg precedent) and the S1-S5 npu_conv_design.md work: proves
# the CONV1D sequencer (D1/D2/D5) end-to-end through firmware, at the SAME
# MCU/silicon generics as the RTL bench (X_M=0, W_M=7, Y_M=7, N=24, RHO=2 --
# G7's Q0.24-in/Q7.24-weight-acc-out format), taking the SAME vector-120
# think-done IRQ shnpu.S's IRQ leg exercises (mirrored EXACTLY: PENDX rider
# with the route OFF first -- deterministic, no delivery race -- then enable
# ENX, INSVCX-in-handler rider, exactly-once, negctrl-lite settle, un-route).
#
# Case (npu_conv_design.md D6 smoke-sized; tiny, ~1 min of NpuClk):
#   K=4 Cin=2 Cout=2 Lout=4 S=1 D=1 BEN=1 AEN=0 MODE=1(conv)
#   L = (Lout-1)*S + (K-1)*D + 1 = 7
#   T = 1 + Cout*Lout*(5*Cin*K + 3*BEN + 1) + 2 = 355 NpuClk cycles (D6)
#
# Register interface (npu_conv_design.md D3/D7 -- MabMmrA widened 3->4 bits):
#   NPUCR   0x4A00 (+0)   ACTF[25:23] MODE[22:20] TDIE[19] BEN[18] AEN[17]
#                          THINK[16] NI[15:8]=K-1 NN[7:0]=Cout-1
#   IVSAR   0x4A04 (+4)   WVSAR 0x4A08 (+8)   OVSAR 0x4A0C (+C)  (12-bit
#                          staging-RAM WORD indices)
#   NPUSR   0x4A10 (+10)  bit0 THINKDONE, sticky W1C (M-series NPU IRQ leg)
#   NPUCFG1 0x4A14 (+14)  S[3:0] D[7:4] L[23:8] (Cin-1)[31:24]
#   NPUCFG2 0x4A18 (+18)  Lout[15:0]
#   NPUCFG3 0x4A1C (+1C)  AS-BUILT: no storage, reads 0 (design doc D3 note)
#   +0x20 (offset 8)      out of the 8-word decode ("when others"), reads 0
# This test's L2 readback doubles as the 4-bit MabMmrA decode smoke: reading
# BOTH the no-storage CFG3 register and the out-of-range offset 8 word proves
# the widened address decode landed cleanly on both known-zero corners.
#
# Staging-RAM layout (word index = (addr-0xC000)/4), clear of shnpu's
# 0xC100-0xC110 band and the bootrom's residual top-of-RAM stack words:
#   X_ADDR   = 0xC400 (word 0x100, IV_WORD): Cin*L = 14 words, channel-major
#              (in[c][t] at c*L+t)
#   W_ADDR   = 0xC500 (word 0x140, WV_WORD): Cout*(Cin*K+BEN) = 18 words,
#              filter-major, bias FIRST per filter (D2/D5 pinned order)
#   OUT_ADDR = 0xC600 (word 0x180, OV_WORD): Cout*Lout = 8 words, flat
#              f*Lout+j order
#
# Golden values: computed by ~/vestarv/verification/npu/gen_wnpuconv_golden.py
# (a throwaway script built entirely on the VALIDATED npu_fixed.py arithmetic
# core -- mac_step()'s exact fixed_pkg_c round-half-to-even + saturate
# replica -- reusing the same bias-first/c-outer/k-inner pinned order the D9
# bench's think_layer()/compute_conv() already implement). Input/weight
# magnitudes were deliberately chosen ~1e5-1e6 raw (real value ~0.006-0.06 in
# Q0.24/Q7.24 terms) so per-step rounding is NOT trivial: the golden script's
# trace shows all 72 MAC steps across the 8 outputs have a nonzero discarded
# remainder, and 38 of them actually round UP (resize_sfixed adds +1 -- e.g.
# the very first step, f=0/j=0's bias tap: floor=449999, remainder=16327216 >
# half=8388608 -> rounds up to 450000). A case that round-tripped exactly
# would prove nothing about the per-step round-to-nearest path; this one does.
#
# Scratch: private TCM 0xA000/0xA004 (single-hart directed -- the wrtc/wow/
# wi2ct/wqspi/wgpio/wi3c/wtrng precedent; no shared-window word needed, there
# is no second hart to rendezvous with).
#   TD_FLAG = 0xA000   (ISR exactly-once counter)
#   TD_ISVC = 0xA004   (handler's masked INSVCX readback)
#
# NPU is mclk-domain (like DMA0/TRNG0) -- NO SYS_CLK_CR write needed (that
# rule is only for the smclk peripherals: UART/I2C/...).
#
# IVT gotcha (shnpu.S precedent, unchanged for this test): this test's .ivt
# extension also stops at slot 120 (same vector, NPU0_TD) -- WITHOUT parking
# slots 121-127 the trailing zero-run to the fixed .text.init link address
# (0x8200) is only 7 zero words, one short of flash_prepend.sh's GAP_MIN(8)
# region-split threshold, and gets silently MERGED into one oversized segment
# (proven to corrupt the boot copy in simulation -- see shnpu.S's header for
# the full forensics). Slots 121-127 are parked here for the same reason.
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

#define IV_WORD      0x100          /* 0xC400 */
#define WV_WORD      0x140          /* 0xC500 */
#define OV_WORD      0x180          /* 0xC600 */

#define X_ADDR       0xC400
#define W_ADDR       0xC500
#define OUT_ADDR     0xC600

#define CFG1_VAL     0x01000711     /* S=1 | D=1<<4 | L=7<<8 | (Cin-1=1)<<24 */
#define CFG2_VAL     4              /* Lout */

#define MODE_CONV    0x00100000     /* NPUCR[22:20] = 1 (conv) */
#define TDIE         0x00080000     /* NPUCR bit19: think-done IRQ enable */
#define BEN_BIT      0x00040000     /* NPUCR bit18 */
#define THINK_BIT    0x00010000     /* NPUCR bit16 */
#define NI_FIELD     0x00000300     /* NI = K-1 = 3, at [15:8] */
#define NN_FIELD     0x00000001     /* NN = Cout-1 = 1, at [7:0] */
#define CR_CONV_THINK_TDIE (MODE_CONV | TDIE | BEN_BIT | THINK_BIT | NI_FIELD | NN_FIELD) /* 0x001D0301 */

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
    bnez t0, wnpuconv_fail          # NPUCR resets 0
    lw   t0, O_IVSAR(s0)
    bnez t0, wnpuconv_fail
    lw   t0, O_WVSAR(s0)
    bnez t0, wnpuconv_fail
    lw   t0, O_OVSAR(s0)
    bnez t0, wnpuconv_fail
    lw   t0, O_CFG1(s0)
    bnez t0, wnpuconv_fail
    lw   t0, O_CFG2(s0)
    bnez t0, wnpuconv_fail

    # NPUSR (0x4A10) is sticky W1C; clear unconditionally (no reset
    # precondition asserted -- mirrors shnpu's IRQ-leg discipline) and prove
    # the clear actually lands.
    li   t0, 1
    sw   t0, O_SR(s0)
    lw   t1, O_SR(s0)
    bnez t1, wnpuconv_fail

    # ================= L1: stage inputs + weights (shared NPU staging RAM) =
    li   s1, X_ADDR
    li   s2, W_ADDR
    li   s3, OUT_ADDR

    # inputs: Cin=2 channels x L=7, channel-major (in[c][t] at c*L+t)
    li   t0, 0x00030D40             # in[0][0] =  200000
    sw   t0, 0(s1)
    li   t0, 0xFFFAA8D0             # in[0][1] = -350000
    sw   t0, 4(s1)
    li   t0, 0x000B100B             # in[0][2] =  725003
    sw   t0, 8(s1)
    li   t0, 0xFFFDDD19             # in[0][3] = -140007
    sw   t0, 12(s1)
    li   t0, 0x000F423F             # in[0][4] =  999999
    sw   t0, 16(s1)
    li   t0, 0xFFFF3C9B             # in[0][5] =  -50021
    sw   t0, 20(s1)
    li   t0, 0x0009625B             # in[0][6] =  615003
    sw   t0, 24(s1)
    li   t0, 0xFFFBCDC8             # in[1][0] = -275000
    sw   t0, 28(s1)
    li   t0, 0x00061A81             # in[1][1] =  400001
    sw   t0, 32(s1)
    li   t0, 0xFFFE17B1             # in[1][2] = -125007
    sw   t0, 36(s1)
    li   t0, 0x00051615             # in[1][3] =  333333
    sw   t0, 40(s1)
    li   t0, 0xFFF3CAFF             # in[1][4] = -800001
    sw   t0, 44(s1)
    li   t0, 0x0004323D             # in[1][5] =  275005
    sw   t0, 48(s1)
    li   t0, 0xFFFF159D             # in[1][6] =  -60003
    sw   t0, 52(s1)

    # weights: Cout=2 filters, bias-first-per-filter, filter-major
    # ((Cin*K)+1 = 9 words/filter)
    li   t0, 0x0006DDD0             # w[f0].bias    =  450000
    sw   t0, 0(s2)
    li   t0, 0x0001D4C7             # w[f0][c0][k0] =  120007
    sw   t0, 4(s2)
    li   t0, 0xFFFC7D85             # w[f0][c0][k1] = -230011
    sw   t0, 8(s2)
    li   t0, 0x0004BAFD             # w[f0][c0][k2] =  310013
    sw   t0, 12(s2)
    li   t0, 0xFFF9BE5F             # w[f0][c0][k3] = -410017
    sw   t0, 16(s2)
    li   t0, 0xFFFDB5F3             # w[f0][c1][k0] = -150029
    sw   t0, 20(s2)
    li   t0, 0x0003F7BF             # w[f0][c1][k1] =  260031
    sw   t0, 24(s2)
    li   t0, 0xFFFA5A8B             # w[f0][c1][k2] = -370037
    sw   t0, 28(s2)
    li   t0, 0x00075329             # w[f0][c1][k3] =  480041
    sw   t0, 32(s2)
    li   t0, 0xFFF6D833             # w[f1].bias    = -600013
    sw   t0, 36(s2)
    li   t0, 0xFFFDDCED             # w[f1][c0][k0] = -140051
    sw   t0, 40(s2)
    li   t0, 0x0003D0C9             # w[f1][c0][k1] =  250057
    sw   t0, 44(s2)
    li   t0, 0xFFFA8183             # w[f1][c0][k2] = -360061
    sw   t0, 48(s2)
    li   t0, 0x00072C35             # w[f1][c0][k3] =  470069
    sw   t0, 52(s2)
    li   t0, 0x0001FC1F             # w[f1][c1][k0] =  130079
    sw   t0, 56(s2)
    li   t0, 0xFFFC562D             # w[f1][c1][k1] = -240083
    sw   t0, 60(s2)
    li   t0, 0x00055789             # w[f1][c1][k2] =  350089
    sw   t0, 64(s2)
    li   t0, 0xFFF8FABF             # w[f1][c1][k3] = -460097
    sw   t0, 68(s2)

    # zero the 8 output words -- must be overwritten by the run
    sw   x0, 0(s3)
    sw   x0, 4(s3)
    sw   x0, 8(s3)
    sw   x0, 12(s3)
    sw   x0, 16(s3)
    sw   x0, 20(s3)
    sw   x0, 24(s3)
    sw   x0, 28(s3)

    # ================= L2: configure + readback (4-bit decode smoke) =======
    li   t0, IV_WORD
    sw   t0, O_IVSAR(s0)
    lw   t1, O_IVSAR(s0)
    bne  t1, t0, wnpuconv_fail

    li   t0, WV_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wnpuconv_fail

    li   t0, OV_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wnpuconv_fail

    li   t0, CFG1_VAL
    sw   t0, O_CFG1(s0)
    lw   t1, O_CFG1(s0)
    bne  t1, t0, wnpuconv_fail

    li   t0, CFG2_VAL
    sw   t0, O_CFG2(s0)
    lw   t1, O_CFG2(s0)
    bne  t1, t0, wnpuconv_fail

    # NPUCFG3 (offset 7, AS-BUILT no storage) and offset 8 (out of the
    # 8-word decode) BOTH read 0 -- the widened MabMmrA(3:0) decode smoke.
    lw   t0, O_CFG3(s0)
    bnez t0, wnpuconv_fail
    lw   t0, O_OFF8(s0)
    bnez t0, wnpuconv_fail

    # ================= L3: THINK (MODE=CONV|TDIE, route OFF first) =========
    li   t0, TD_FLAG
    sw   x0, 0(t0)                  # exactly-once counter = 0
    li   t0, TD_ISVC
    sw   x0, 0(t0)

    li   t0, CR_CONV_THINK_TDIE
    sw   t0, O_CR(s0)               # NPUCR = MODE=1|TDIE|BEN|THINK|NI=3|NN=1

    li   t6, POLL_BUD
wnpuconv_wait_busy:
    lw   t0, O_CR(s0)
    srli t0, t0, 16
    andi t0, t0, 1                  # NPUCR bit16 = THINK (busy)
    beqz t0, wnpuconv_wait_flag
    addi t6, t6, -1
    bnez t6, wnpuconv_wait_busy
    j    wnpuconv_fail

wnpuconv_wait_flag:
    lw   t1, O_SR(s0)
    andi t1, t1, 1
    bnez t1, wnpuconv_pendx
    addi t6, t6, -1
    bnez t6, wnpuconv_wait_flag
    j    wnpuconv_fail

wnpuconv_pendx:
    # RIDER: PENDX bit24 must be set (raw source pending; route still off ->
    # no delivery race on this poll)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    beqz t1, wnpuconv_fail

    # enable the route -> meip -> dispatcher -> claim 120 -> handler
    li   t0, IRTR_ENX
    li   t1, TD_SRC_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wnpuconv_fail

    li   t6, POLL_BUD
wnpuconv_wait_deliv:
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, wnpuconv_deliv_ok
    addi t6, t6, -1
    bnez t6, wnpuconv_wait_deliv
    j    wnpuconv_fail

wnpuconv_deliv_ok:
    # exactly one delivery (in_service gateway)
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wnpuconv_fail
    # RIDER: the handler recorded INSVCX bit24 while claimed
    li   t0, TD_ISVC
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    bne  t1, t2, wnpuconv_fail
    # handler W1C'd NPUSR bit0 -> level dropped -> NPUSR reads 0
    lw   t1, O_SR(s0)
    bnez t1, wnpuconv_fail
    # PENDX bit24 clear now too (raw source level dropped)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    bnez t1, wnpuconv_fail

    # ================= L4: exact Q7.24 output check (all Cout*Lout=8) ======
    li   s4, OUT_ADDR
    li   t0, 0x000789B2             # out[f0][j0] =  494002
    lw   t1, 0(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0005B7F6             # out[f0][j1] =  374774
    lw   t1, 4(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0007C2BB             # out[f0][j2] =  508603
    lw   t1, 8(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x00060B8D             # out[f0][j3] =  396173
    lw   t1, 12(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF6249B             # out[f1][j0] = -645989
    lw   t1, 16(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF80AFB             # out[f1][j1] = -521477
    lw   t1, 20(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF5EA02             # out[f1][j2] = -660990
    lw   t1, 24(s4)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF7B227             # out[f1][j3] = -544217
    lw   t1, 28(s4)
    bne  t1, t0, wnpuconv_fail

    # ================= L5: negative-structure check -- operands survived ===
    li   t0, 0x00030D40
    lw   t1, 0(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFAA8D0
    lw   t1, 4(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x000B100B
    lw   t1, 8(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFDDD19
    lw   t1, 12(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x000F423F
    lw   t1, 16(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFF3C9B
    lw   t1, 20(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0009625B
    lw   t1, 24(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFBCDC8
    lw   t1, 28(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x00061A81
    lw   t1, 32(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFE17B1
    lw   t1, 36(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x00051615
    lw   t1, 40(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF3CAFF
    lw   t1, 44(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0004323D
    lw   t1, 48(s1)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFF159D
    lw   t1, 52(s1)
    bne  t1, t0, wnpuconv_fail

    li   t0, 0x0006DDD0
    lw   t1, 0(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0001D4C7
    lw   t1, 4(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFC7D85
    lw   t1, 8(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0004BAFD
    lw   t1, 12(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF9BE5F
    lw   t1, 16(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFDB5F3
    lw   t1, 20(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0003F7BF
    lw   t1, 24(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFA5A8B
    lw   t1, 28(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x00075329
    lw   t1, 32(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF6D833
    lw   t1, 36(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFDDCED
    lw   t1, 40(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0003D0C9
    lw   t1, 44(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFA8183
    lw   t1, 48(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x00072C35
    lw   t1, 52(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x0001FC1F
    lw   t1, 56(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFFC562D
    lw   t1, 60(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0x00055789
    lw   t1, 64(s2)
    bne  t1, t0, wnpuconv_fail
    li   t0, 0xFFF8FABF
    lw   t1, 68(s2)
    bne  t1, t0, wnpuconv_fail

    # settle window: let any (erroneous) second delivery happen (no new
    # THINK started, route still on), then confirm the counter stayed at 1
    li   t6, SETTLE_BUD
wnpuconv_settle:
    addi t6, t6, -1
    bnez t6, wnpuconv_settle
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wnpuconv_fail

    li   t0, IRTR_ENX
    sw   x0, 0(t0)                  # un-route (clean)
    li   t0, NPU_BASE
    sw   x0, O_CR(t0)                # NPUCR back to reset default (TDIE off too)

    RVTEST_PASS

wnpuconv_fail:
    RVTEST_FAIL

    # ---- NPU CONV think-done handler (vector 120; M19 plain-ret meip ABI,
    # ---- shnpu.S's npu0_td_isr idiom). Reached via CLAIM=120 -> dispatcher
    # ---- jalr through IVT slot 120. Records the INSVCX in-handler proof,
    # ---- W1C-clears NPUSR bit0 (drops the level) BEFORE returning (the
    # ---- dispatcher COMPLETEs after), bumps the exactly-once counter.
    # ---- t0-t2 dispatcher-saved scratch; ra survives (ret). ----------------
    .section .text.init
npu0_conv_td_isr:
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
    jal  zero, npu0_conv_td_isr      # slot 120 = IRQB_NPU0_TD
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
