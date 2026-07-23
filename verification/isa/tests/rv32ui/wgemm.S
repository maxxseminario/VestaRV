# See LICENSE for license details.

#*****************************************************************************
# wgemm.S  (wound-config firmware smoke -- digperiphs P4.3 Stage S5)
#-----------------------------------------------------------------------------
# NPU GEMM (MODE=3) firmware smoke, hart 0 only (single-hart directed; tiles
# stay parked -- no MP_STAGE_IMAGE, no mp_boot.h; the SAME majority w*
# precedent shape as wnpuconv.S/wxnpu.S). Companion to shnpu.S (the shared-NPU
# MLP + vector-120 IRQ-leg precedent), wnpuconv.S (CONV1D) and wxnpu.S
# (XNOR/popcount): proves the GEMM sequencer (npu_gemm_design.md D1-D12)
# end-to-end through firmware, at the SAME MCU/silicon generics as the RTL
# bench (X_M=0, W_M=7, Y_M=7, N=24, RHO=2), taking the SAME vector-120
# think-done IRQ leg the family precedent takes (mirrored EXACTLY: PENDX
# rider with the route OFF first -- deterministic, no delivery race -- then
# enable ENX, INSVCX-in-handler rider, exactly-once, negctrl-lite settle,
# un-route).
#
# TWO CHAINED GEMMs (design-doc ADJUDICATION ADDENDUM A2 -- the chaining leg
# is REQUIRED and layer 1 MUST run AEN=1: chaining C->A needs |C|<1, and the
# sigmoid's zero-extended Q0.24 output words chain exactly):
#
#   Layer 1 (chaining source): M1=2 K1=3 N1=4 BEN=0 AEN=1 (sigmoid, ACTF=0)
#     A1 row-major (Q0.24), B1 column-major (Q7.24) -> C1 (Q0.24 sigmoid out)
#     T1 = 1 + M1*N1*(5*K1+1) + 2 = 1 + 8*16 + 2 = 131 NpuClk cycles
#
#   Layer 2 (chained, ZERO REPACK): A2 = C1 IN PLACE -- IVSAR2 = OVSAR1, the
#     D2 row-major zero-repack proof (no firmware copy of C1 into a new
#     region). M2=2 K2=4(=N1) N2=2 BEN=0 AEN=0. B2 column-major (Q7.24) at
#     its own WVSAR2 -> C2 (Q7.24 passthrough). Takes the vector-120
#     think-done IRQ (NPUCR.TDIE) leg.
#     T2 = 1 + M2*N2*(5*K2+1) + 2 = 1 + 4*21 + 2 = 87 NpuClk cycles
#
# Golden values: computed by ~/vestarv/verification/npu/gen_wgemm_golden.py
# (a throwaway script built entirely on the VALIDATED npu_fixed.py arithmetic
# core -- think_layer(), reused verbatim per npu_gemm_design.md D10, once per
# output row per layer; never reimplements the MAC/sigmoid arithmetic). A1/B1
# magnitudes were chosen so every layer-1 pre-activation accumulator lands
# well inside the sigmoid's active band (|acc| < 4) with a genuine mix of
# positive and negative accumulators (verified by that script's trace/
# self-check) -- all 8 pre-activation accs land at |acc| ~= 0.0003-0.0006,
# i.e. deep in-range, not near the +-4 boundary; that script also asserts
# every C1 word satisfies the Q0.24 |C|<1 chaining-legal range before
# printing anything (the D2 zero-repack proof).
#
# Register interface (npu_gemm_design.md D5/D7 -- ZERO entity changes; the
# SAME 8-word MMR bank wnpuconv.S/wxnpu.S exercise, per-mode reinterpretation
# only):
#   NPUCR   0x4A00 (+0)   ACTF[25:23] MODE[22:20] TDIE[19] BEN[18] AEN[17]
#                          THINK[16] NI[15:8]=K-1 NN[7:0]=N-1
#   IVSAR   0x4A04 (+4)   WVSAR 0x4A08 (+8)   OVSAR 0x4A0C (+C)  (12-bit
#                          staging-RAM WORD indices)
#   NPUSR   0x4A10 (+10)  bit0 THINKDONE, sticky W1C (sets on NpuDone
#                          regardless of TDIE -- TDIE only gates delivery)
#   NPUCFG1 0x4A14 (+14)  GEMM reinterpretation (D5): (M-1) in bits[7:0]
#                          (conv reads S/D/L/Cin-1 packed; xnor reads THRESH)
#   NPUCFG2 0x4A18 (+18)  GEMM ignores this register entirely (D9) -- write/
#                          readback smoked once below purely as a generic MMR
#                          storage proof (conv reads Lout, xnor reads K here)
#   NPUCFG3 0x4A1C (+1C)  AS-BUILT: no storage, reads 0 (unchanged, D7)
#   +0x20 (offset 8)      out of the 8-word decode ("when others"), reads 0
# This test's L2/L5 readbacks double as the same 4-bit MabMmrA decode smoke
# wnpuconv.S/wxnpu.S's headers document (CFG3 + offset-8 both known-zero
# corners) -- the entity is untouched (D7), so the decode behaves identically
# per mode.
#
# Staging-RAM layout (word index = (addr-0xC000)/4), clear of shnpu's
# 0xC100-0xC110 band, wnpuconv's 0xC400/0xC500/0xC600 bands, and wxnpu's
# 0xC700/0xC740/0xC780 bands:
#   IV1_ADDR = 0xC800 (word 0x200): M1*K1=6 words, A1 row-major (A1[m][k] at
#              m*K1+k) -- ALSO layer 2's IVSAR (IV2_ADDR), see below
#   WV1_ADDR = 0xC840 (word 0x210): K1*N1=12 words, B1 column-major
#              (w_list[n*K1+k] = B1[k][n])
#   OV1_ADDR = 0xC880 (word 0x220): M1*N1=8 words, C1 row-major (C1[m][n] at
#              m*N1+n) -- this SAME region is layer 2's IVSAR (IV2_ADDR =
#              OV1_ADDR, the D2 zero-repack chaining proof: layer 2 reads
#              A2[m][k] from exactly where layer 1 wrote C1[m][n], M2*K2 ==
#              M1*N1 == 8, no firmware copy)
#   WV2_ADDR = 0xC8C0 (word 0x230): K2*N2=8 words, B2 column-major
#              (w_list[n*K2+k] = B2[k][n])
#   OV2_ADDR = 0xC900 (word 0x240): M2*N2=4 words, C2 row-major (C2[m][n] at
#              m*N2+n)
#
# Scratch: private TCM 0xA000/0xA004 (single-hart directed -- the wnpuconv/
# wxnpu/wrtc/wow/wi2ct/wqspi/wgpio/wi3c/wtrng precedent; no shared-window word
# needed, there is no second hart to rendezvous with).
#   TD_FLAG = 0xA000   (ISR exactly-once counter)
#   TD_ISVC = 0xA004   (handler's masked INSVCX readback)
#
# NPU is mclk-domain (like DMA0/TRNG0) -- NO SYS_CLK_CR write needed (that
# rule is only for the smclk peripherals: UART/I2C/...).
#
# IVT gotcha (shnpu.S/wnpuconv.S/wxnpu.S precedent, unchanged for this test):
# this test's .ivt extension also stops at slot 120 (same vector, NPU0_TD) --
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

#define IV1_WORD     0x200          /* 0xC800 */
#define WV1_WORD     0x210          /* 0xC840 */
#define OV1_WORD     0x220          /* 0xC880 (== IV2_WORD, chained) */
#define WV2_WORD     0x230          /* 0xC8C0 */
#define OV2_WORD     0x240          /* 0xC900 */

#define IV1_ADDR     0xC800
#define WV1_ADDR     0xC840
#define OV1_ADDR     0xC880
#define IV2_ADDR     0xC880         /* == OV1_ADDR: zero-repack chaining */
#define WV2_ADDR     0xC8C0
#define OV2_ADDR     0xC900

#define CFG1_L1_VAL  1               /* M1-1 = 1 (M1=2) */
#define CFG1_L2_VAL  1               /* M2-1 = 1 (M2=2) */
#define CFG2_SMOKE   0x1357          /* GEMM ignores CFG2 (D9); readback-only */

#define MODE_GEMM    0x00300000     /* NPUCR[22:20] = 3 (gemm) */
#define TDIE         0x00080000     /* NPUCR bit19: think-done IRQ enable */
#define AEN_BIT      0x00020000     /* NPUCR bit17 */
#define THINK_BIT    0x00010000     /* NPUCR bit16 */

#define NI1_FIELD    0x00000200     /* NI = K1-1 = 2, at [15:8] */
#define NN1_FIELD    0x00000003     /* NN = N1-1 = 3, at [7:0] */
#define CR_L1_CONFIG (MODE_GEMM | AEN_BIT | NI1_FIELD | NN1_FIELD)      /* 0x00320203 */
#define CR_L1_THINK  (CR_L1_CONFIG | THINK_BIT)                         /* 0x00330203 */

#define NI2_FIELD    0x00000300     /* NI = K2-1 = 3, at [15:8] */
#define NN2_FIELD    0x00000001     /* NN = N2-1 = 1, at [7:0] */
#define CR_L2_CONFIG (MODE_GEMM | NI2_FIELD | NN2_FIELD)                /* 0x00300301 */
#define CR_L2_THINK_TDIE (CR_L2_CONFIG | TDIE | THINK_BIT)              /* 0x00390301 */

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
    bnez t0, wgemm_fail             # NPUCR resets 0
    lw   t0, O_IVSAR(s0)
    bnez t0, wgemm_fail
    lw   t0, O_WVSAR(s0)
    bnez t0, wgemm_fail
    lw   t0, O_OVSAR(s0)
    bnez t0, wgemm_fail
    lw   t0, O_CFG1(s0)
    bnez t0, wgemm_fail
    lw   t0, O_CFG2(s0)
    bnez t0, wgemm_fail

    # NPUSR (0x4A10) is sticky W1C; clear unconditionally (no reset
    # precondition asserted -- mirrors shnpu/wnpuconv/wxnpu's IRQ-leg
    # discipline) and prove the clear actually lands.
    li   t0, 1
    sw   t0, O_SR(s0)
    lw   t1, O_SR(s0)
    bnez t1, wgemm_fail

    # ================= L1: stage layer-1/layer-2 operands (shared NPU =====
    # ================= staging RAM) =========================================
    li   s1, IV1_ADDR
    li   s2, WV1_ADDR
    li   s3, OV1_ADDR
    li   s4, WV2_ADDR
    li   s5, OV2_ADDR

    # A1: M1=2 rows x K1=3, row-major (A1[m][k] at m*K1+k)
    li   t0, 0x000249F0              # A1[0][0] =  150000
    sw   t0, 0(s1)
    li   t0, 0xFFFCA4A0              # A1[0][1] = -220000
    sw   t0, 4(s1)
    li   t0, 0x00015F90              # A1[0][2] =   90000
    sw   t0, 8(s1)
    li   t0, 0xFFFE0430              # A1[1][0] = -130000
    sw   t0, 12(s1)
    li   t0, 0x0002BF20              # A1[1][1] =  180000
    sw   t0, 16(s1)
    li   t0, 0xFFFEEE90              # A1[1][2] =  -70000
    sw   t0, 20(s1)

    # B1: K1=3 x N1=4, COLUMN-MAJOR (w_list[n*K1+k] = B1[k][n])
    li   t0, 0x00061A80              # B1[0][0] =  400000  (w_list[0])
    sw   t0, 0(s2)
    li   t0, 0xFFFAF6F0              # B1[1][0] = -330000  (w_list[1])
    sw   t0, 4(s2)
    li   t0, 0x00046CD0              # B1[2][0] =  290000  (w_list[2])
    sw   t0, 8(s2)
    li   t0, 0xFFFAA8D0              # B1[0][1] = -350000  (w_list[3])
    sw   t0, 12(s2)
    li   t0, 0x0004BAF0              # B1[1][1] =  310000  (w_list[4])
    sw   t0, 16(s2)
    li   t0, 0xFFFBE150              # B1[2][1] = -270000  (w_list[5])
    sw   t0, 20(s2)
    li   t0, 0x000493E0              # B1[0][2] =  300000  (w_list[6])
    sw   t0, 24(s2)
    li   t0, 0xFFFBBA40              # B1[1][2] = -280000  (w_list[7])
    sw   t0, 28(s2)
    li   t0, 0x0003D090              # B1[2][2] =  250000  (w_list[8])
    sw   t0, 32(s2)
    li   t0, 0xFFFC0860              # B1[0][3] = -260000  (w_list[9])
    sw   t0, 36(s2)
    li   t0, 0x0003A980              # B1[1][3] =  240000  (w_list[10])
    sw   t0, 40(s2)
    li   t0, 0xFFFC7D90              # B1[2][3] = -230000  (w_list[11])
    sw   t0, 44(s2)

    # C1/A2 region: M1*N1=8 words -- zero (must be overwritten by layer-1's
    # THINK, then consumed unmodified as layer-2's A2)
    sw   x0, 0(s3)
    sw   x0, 4(s3)
    sw   x0, 8(s3)
    sw   x0, 12(s3)
    sw   x0, 16(s3)
    sw   x0, 20(s3)
    sw   x0, 24(s3)
    sw   x0, 28(s3)

    # B2: K2=4 x N2=2, COLUMN-MAJOR (w_list[n*K2+k] = B2[k][n])
    li   t0, 0x0007A120              # B2[0][0] =  500000  (w_list[0])
    sw   t0, 0(s4)
    li   t0, 0xFFF99760              # B2[1][0] = -420000  (w_list[1])
    sw   t0, 4(s4)
    li   t0, 0x00057E40              # B2[2][0] =  360000  (w_list[2])
    sw   t0, 8(s4)
    li   t0, 0xFFFB4510              # B2[3][0] = -310000  (w_list[3])
    sw   t0, 12(s4)
    li   t0, 0xFFF92230              # B2[0][1] = -450000  (w_list[4])
    sw   t0, 16(s4)
    li   t0, 0x0005CC60              # B2[1][1] =  380000  (w_list[5])
    sw   t0, 20(s4)
    li   t0, 0xFFFACFE0              # B2[2][1] = -340000  (w_list[6])
    sw   t0, 24(s4)
    li   t0, 0x00046CD0              # B2[3][1] =  290000  (w_list[7])
    sw   t0, 28(s4)

    # C2 region: M2*N2=4 words -- zero (must be overwritten by layer-2's THINK)
    sw   x0, 0(s5)
    sw   x0, 4(s5)
    sw   x0, 8(s5)
    sw   x0, 12(s5)

    # ================= L2: configure layer 1 + readback (4-bit decode smoke) =
    li   t0, CFG1_L1_VAL
    sw   t0, O_CFG1(s0)
    lw   t1, O_CFG1(s0)
    bne  t1, t0, wgemm_fail

    li   t0, CFG2_SMOKE
    sw   t0, O_CFG2(s0)
    lw   t1, O_CFG2(s0)
    bne  t1, t0, wgemm_fail

    li   t0, IV1_WORD
    sw   t0, O_IVSAR(s0)
    lw   t1, O_IVSAR(s0)
    bne  t1, t0, wgemm_fail

    li   t0, WV1_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wgemm_fail

    li   t0, OV1_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wgemm_fail

    # NPUCFG3 (offset 7, AS-BUILT no storage) and offset 8 (out of the
    # 8-word decode) BOTH read 0 -- the widened MabMmrA(3:0) decode smoke
    # (unchanged by mode -- D7 entity is ZERO changes).
    lw   t0, O_CFG3(s0)
    bnez t0, wgemm_fail
    lw   t0, O_OFF8(s0)
    bnez t0, wgemm_fail

    # ================= L3: THINK layer 1 (MODE=GEMM|AEN, no TDIE) ==========
    li   t0, CR_L1_THINK
    sw   t0, O_CR(s0)               # NPUCR = MODE=3|AEN|THINK|NI=2|NN=3, BEN=0

    li   t6, POLL_BUD
wgemm_l1_wait_busy:
    lw   t0, O_CR(s0)
    srli t0, t0, 16
    andi t0, t0, 1                  # NPUCR bit16 = THINK (busy)
    beqz t0, wgemm_l1_wait_flag
    addi t6, t6, -1
    bnez t6, wgemm_l1_wait_busy
    j    wgemm_fail

wgemm_l1_wait_flag:
    lw   t1, O_SR(s0)
    andi t1, t1, 1                  # THINKDONE sets on NpuDone regardless of TDIE
    bnez t1, wgemm_l1_done
    addi t6, t6, -1
    bnez t6, wgemm_l1_wait_flag
    j    wgemm_fail

wgemm_l1_done:
    # no TDIE for layer 1 -- W1C the flag now so it cannot leak into layer 2's
    # IRQ leg
    li   t0, 1
    sw   t0, O_SR(s0)
    lw   t1, O_SR(s0)
    bnez t1, wgemm_fail

    # ================= L4: exact Q0.24 sigmoid output check (C1, all 8) ====
    li   t0, 0x0080093D              # C1[0][0] = 8390973
    lw   t1, 0(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF790              # C1[0][1] = 8386448
    lw   t1, 4(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x00800784              # C1[0][2] = 8390532
    lw   t1, 8(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF974              # C1[0][3] = 8386932
    lw   t1, 12(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF856              # C1[1][0] = 8386646
    lw   t1, 16(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x008006FF              # C1[1][1] = 8390399
    lw   t1, 20(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF9C7              # C1[1][2] = 8387015
    lw   t1, 24(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0080056C              # C1[1][3] = 8389996
    lw   t1, 28(s3)
    bne  t1, t0, wgemm_fail

    # ================= L5: configure layer 2 + readback (chained, zero =====
    # ================= repack: IVSAR2 = OVSAR1) =============================
    li   t0, CFG1_L2_VAL
    sw   t0, O_CFG1(s0)
    lw   t1, O_CFG1(s0)
    bne  t1, t0, wgemm_fail

    li   t0, OV1_WORD                # IVSAR2 = OVSAR1 (== IV2_WORD): the D2
    sw   t0, O_IVSAR(s0)             # zero-repack chaining proof, no copy
    lw   t1, O_IVSAR(s0)
    bne  t1, t0, wgemm_fail

    li   t0, WV2_WORD
    sw   t0, O_WVSAR(s0)
    lw   t1, O_WVSAR(s0)
    bne  t1, t0, wgemm_fail

    li   t0, OV2_WORD
    sw   t0, O_OVSAR(s0)
    lw   t1, O_OVSAR(s0)
    bne  t1, t0, wgemm_fail

    # ================= L6: THINK layer 2 (MODE=GEMM|TDIE, route OFF first) =
    li   t0, TD_FLAG
    sw   x0, 0(t0)                  # exactly-once counter = 0
    li   t0, TD_ISVC
    sw   x0, 0(t0)

    li   t0, CR_L2_THINK_TDIE
    sw   t0, O_CR(s0)               # NPUCR = MODE=3|TDIE|THINK|NI=3|NN=1, BEN=0/AEN=0

    li   t6, POLL_BUD
wgemm_l2_wait_busy:
    lw   t0, O_CR(s0)
    srli t0, t0, 16
    andi t0, t0, 1                  # NPUCR bit16 = THINK (busy)
    beqz t0, wgemm_l2_wait_flag
    addi t6, t6, -1
    bnez t6, wgemm_l2_wait_busy
    j    wgemm_fail

wgemm_l2_wait_flag:
    lw   t1, O_SR(s0)
    andi t1, t1, 1
    bnez t1, wgemm_pendx
    addi t6, t6, -1
    bnez t6, wgemm_l2_wait_flag
    j    wgemm_fail

wgemm_pendx:
    # RIDER: PENDX bit24 must be set (raw source pending; route still off ->
    # no delivery race on this poll)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    beqz t1, wgemm_fail

    # enable the route -> meip -> dispatcher -> claim 120 -> handler
    li   t0, IRTR_ENX
    li   t1, TD_SRC_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wgemm_fail

    li   t6, POLL_BUD
wgemm_wait_deliv:
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, wgemm_deliv_ok
    addi t6, t6, -1
    bnez t6, wgemm_wait_deliv
    j    wgemm_fail

wgemm_deliv_ok:
    # exactly one delivery (in_service gateway)
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wgemm_fail
    # RIDER: the handler recorded INSVCX bit24 while claimed
    li   t0, TD_ISVC
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    bne  t1, t2, wgemm_fail
    # handler W1C'd NPUSR bit0 -> level dropped -> NPUSR reads 0
    lw   t1, O_SR(s0)
    bnez t1, wgemm_fail
    # PENDX bit24 clear now too (raw source level dropped)
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, TD_SRC_BIT
    and  t1, t1, t2
    bnez t1, wgemm_fail

    # ================= L7: exact Q7.24 output check (C2, all M2*N2=4) ======
    li   t0, 0x0000FEAC              # C2[0][0] =  65196
    lw   t1, 0(s5)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFF14EC              # C2[0][1] = -60180
    lw   t1, 4(s5)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0000FD45              # C2[1][0] =  64837
    lw   t1, 8(s5)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFF1636              # C2[1][1] = -59850
    lw   t1, 12(s5)
    bne  t1, t0, wgemm_fail

    # ================= L8: negative-structure check -- operands (and the ====
    # ================= chained C1/A2 region) survived layer 2 unmodified ====
    li   t0, 0x000249F0
    lw   t1, 0(s1)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFCA4A0
    lw   t1, 4(s1)
    bne  t1, t0, wgemm_fail
    li   t0, 0x00015F90
    lw   t1, 8(s1)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFE0430
    lw   t1, 12(s1)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0002BF20
    lw   t1, 16(s1)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFEEE90
    lw   t1, 20(s1)
    bne  t1, t0, wgemm_fail

    li   t0, 0x00061A80
    lw   t1, 0(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFAF6F0
    lw   t1, 4(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0x00046CD0
    lw   t1, 8(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFAA8D0
    lw   t1, 12(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0004BAF0
    lw   t1, 16(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFBE150
    lw   t1, 20(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0x000493E0
    lw   t1, 24(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFBBA40
    lw   t1, 28(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0003D090
    lw   t1, 32(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFC0860
    lw   t1, 36(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0003A980
    lw   t1, 40(s2)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFC7D90
    lw   t1, 44(s2)
    bne  t1, t0, wgemm_fail

    li   t0, 0x0007A120
    lw   t1, 0(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFF99760
    lw   t1, 4(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0x00057E40
    lw   t1, 8(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFB4510
    lw   t1, 12(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFF92230
    lw   t1, 16(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0005CC60
    lw   t1, 20(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0xFFFACFE0
    lw   t1, 24(s4)
    bne  t1, t0, wgemm_fail
    li   t0, 0x00046CD0
    lw   t1, 28(s4)
    bne  t1, t0, wgemm_fail

    # C1/A2 region must be BIT-IDENTICAL to the L4 check -- layer 2 only
    # READS this region (as A2), it never writes it (OVSAR2 != IVSAR2 here)
    li   t0, 0x0080093D
    lw   t1, 0(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF790
    lw   t1, 4(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x00800784
    lw   t1, 8(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF974
    lw   t1, 12(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF856
    lw   t1, 16(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x008006FF
    lw   t1, 20(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x007FF9C7
    lw   t1, 24(s3)
    bne  t1, t0, wgemm_fail
    li   t0, 0x0080056C
    lw   t1, 28(s3)
    bne  t1, t0, wgemm_fail

    # settle window: let any (erroneous) second delivery happen (no new
    # THINK started, route still on), then confirm the counter stayed at 1
    li   t6, SETTLE_BUD
wgemm_settle:
    addi t6, t6, -1
    bnez t6, wgemm_settle
    li   t0, TD_FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wgemm_fail

    li   t0, IRTR_ENX
    sw   x0, 0(t0)                  # un-route (clean)
    li   t0, NPU_BASE
    sw   x0, O_CR(t0)                # NPUCR back to reset default (TDIE off too)

    RVTEST_PASS

wgemm_fail:
    RVTEST_FAIL

    # ---- NPU GEMM think-done handler (vector 120; M19 plain-ret meip ABI,
    # ---- shnpu.S/wnpuconv.S/wxnpu.S's npu0_td_isr idiom). Reached via
    # ---- CLAIM=120 -> dispatcher jalr through IVT slot 120. Records the
    # ---- INSVCX in-handler proof, W1C-clears NPUSR bit0 (drops the level)
    # ---- BEFORE returning (the dispatcher COMPLETEs after), bumps the
    # ---- exactly-once counter. t0-t2 dispatcher-saved scratch; ra survives
    # ---- (ret). --------------------------------------------------------
    .section .text.init
npu0_gemm_td_isr:
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
    jal  zero, npu0_gemm_td_isr      # slot 120 = IRQB_NPU0_TD
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
