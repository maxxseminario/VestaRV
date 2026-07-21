# See LICENSE for license details.

#*****************************************************************************
# wdma.S  (wound-config firmware smoke — digperiphs Stage E)
#-----------------------------------------------------------------------------
# DMA0 @0x6800 single-hart firmware smoke: a mem-to-mem CRC copy (polled, CRC
# constant checked) and the DMA0_ERR interrupt (vector 119) delivered through
# the REAL meip path (irq_router HhENX bit23 -> meip -> MEIP_DISPATCHER -> IVT
# slot 119 -> plain-ret handler -> CLAIM/COMPLETE). Companion to the multi-hart
# shdma.S (the DONE/vector-118 + deny-guard + NCH-agnostic legs live there);
# wdma is the ERROR-path + Stage-E rider companion. Hart 0 only; tiles parked.
#
# STAGE-E RIDER PROOF (irq_router RO words for sources 96-127):
#   * PENDX  @0x781C bit23 (source 119) — read with the ROUTE STILL OFF after
#     the LEN=0 reject sets CH0ERR: PEND reflects the RAW source level, not the
#     enable, so it is deterministic (no delivery yet). Then enable the route.
#   * INSVCX @0x782C bit23 — read INSIDE the handler (claimed, before W1C) and
#     require the claimed source's in_service bit is set.
#
# DMA register map (dma_spec.md / DMA.vhd AS-BUILT; RegSlotDMAx*):
#   CR 0x6800  SR 0x6804  C0SRC 0x6808  C0DST 0x680C  C0LEN 0x6810
#   C0CFG 0x6814  CRC 0x6848(slot18)
#   CR : DMAEN[0] CHnGO[4:1] CHnABORT[8:5] DONEIE[12] ERRIE[13]
#   SR : BUSY[0] CHnDONE[4:1] CHnERR[8:5] ACTIVECH[11:9]  (DONE/ERR W1C)
#   CFG: SINC[0] DINC[1] TRIG[5:2](0=mem2mem) PRIO[6] CRCEN[7]
#   irq_done (118) = (any CHnDONE) & DONEIE ; irq_err (119) = (any CHnERR) & ERRIE
#   CRC16-CDMA2000 (poly 0xC857, seed 0xFFFF, MSB-first, no reflect/xor), folded
#   over the transferred bytes b0..b3 per word (little-endian). DMA0 is mclk —
#   NO SYS_CLK_CR write is needed.
#
# LEDGER (CLAUDE.md shared-window rule; window free at N=4 AND N=18): this
# single-hart test reuses shdma.S's proven-free band [0x100E0..0x1011C]
# (shdma and wdma NEVER coexist — one image per sim, isolation), sub-range
# 0x100E0..0x10104. Below it (shmem_mp/shlrsc/shcount hammers) tops at 0x100D4;
# above it shboot/shspin DONE start at 0x10120. All < 0x10500 (loader rows) and
# < 0x10800 (bootrom zero range -> write-before-read holds).
#   SRC_BUF = 0x100E0 (4 words)  DST_BUF = 0x100F0 (4 words)
#   FLAG    = 0x10100 (ISR exactly-once counter)
#   ISVC    = 0x10104 (handler's masked INSVCX readback)
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define DMA_BASE    0x6800
#define O_CR        0x00
#define O_SR        0x04
#define O_C0SRC     0x08
#define O_C0DST     0x0C
#define O_C0LEN     0x10
#define O_C0CFG     0x14
#define O_CRC       0x48

#define DMAEN       (1 << 0)
#define CH0GO       (1 << 1)
#define DONEIE      (1 << 12)
#define ERRIE       (1 << 13)
#define GO_POLL     (DMAEN | CH0GO)                 /* 0x0003 */
#define GO_ERR      (DMAEN | ERRIE | CH0GO)         /* 0x2003 */

#define BUSY        (1 << 0)
#define CH0DONE     (1 << 1)
#define CH0ERR      (1 << 5)

#define CFG_SINC    (1 << 0)
#define CFG_DINC    (1 << 1)
#define CFG_CRCEN   (1 << 7)
#define CFG_M2MCRC  (CFG_SINC | CFG_DINC | CFG_CRCEN)   /* 0x83 */

#define CRC_SEED    0xFFFF
#define CRC_EXPECT  0x61C3                          /* shdma-derived, same payload */
#define DMA_LEN     4

#define IRTR_ENX    0x700C
#define IRTR_PENDX  0x781C
#define IRTR_INSVCX 0x782C
#define ENX_ERR     0x00800000                      /* bit23 = source 119 */
#define ERR_SRC_BIT 0x00800000                      /* PENDX/INSVCX bit23 = 119-96 */

#define SRC_BUF     0x100E0
#define DST_BUF     0x100F0
#define FLAG        0x10100
#define ISVC        0x10104

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0
    li   s0, DMA_BASE
    li   s1, SRC_BUF
    li   s2, DST_BUF

    # ================= L0: reset defaults ==============================
    lw   t0, O_CR(s0)
    bnez t0, wdma_fail               # DMA0CR resets 0
    lw   t0, O_SR(s0)
    bnez t0, wdma_fail               # DMA0SR resets 0
    lw   t0, O_CRC(s0)
    li   t1, CRC_SEED
    bne  t0, t1, wdma_fail           # DMA0CRC resets 0xFFFF

    # ================= L1: mem-to-mem + CRC copy (polled) ==============
    li   t0, 0x11223344
    sw   t0, 0(s1)
    li   t0, 0xAABBCCDD
    sw   t0, 4(s1)
    li   t0, 0x0F1E2D3C
    sw   t0, 8(s1)
    li   t0, 0x76543210
    sw   t0, 12(s1)
    li   t0, 0xE5E5E5E5
    sw   t0, 0(s2)
    sw   t0, 4(s2)
    sw   t0, 8(s2)
    sw   t0, 12(s2)

    sw   s1, O_C0SRC(s0)
    sw   s2, O_C0DST(s0)
    li   t0, DMA_LEN
    sw   t0, O_C0LEN(s0)
    li   t0, CFG_M2MCRC
    sw   t0, O_C0CFG(s0)
    li   t0, CRC_SEED
    sw   t0, O_CRC(s0)               # seed 0xFFFF before GO

    li   t0, GO_POLL
    sw   t0, O_CR(s0)                # GO (poll leg; DONEIE/ERRIE off)

    li   t6, 20000
1:  lw   t1, O_SR(s0)
    andi t2, t1, CH0DONE
    bnez t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    wdma_fail
2:  lw   t0, 0(s1);  lw t1, 0(s2);  bne t0, t1, wdma_fail
    lw   t0, 4(s1);  lw t1, 4(s2);  bne t0, t1, wdma_fail
    lw   t0, 8(s1);  lw t1, 8(s2);  bne t0, t1, wdma_fail
    lw   t0, 12(s1); lw t1, 12(s2); bne t0, t1, wdma_fail
    lw   t0, O_CRC(s0)
    li   t1, CRC_EXPECT
    bne  t0, t1, wdma_fail           # CRC == precomputed constant
    li   t0, CH0DONE
    sw   t0, O_SR(s0)                # W1C CH0DONE
    li   t6, 20000
3:  lw   t1, O_SR(s0)
    andi t1, t1, CH0DONE
    beqz t1, 4f
    addi t6, t6, -1
    bnez t6, 3b
    j    wdma_fail
4:

    # ================= L2: ERR IRQ (vector 119) via LEN=0 reject-at-GO ==
    li   t0, FLAG
    sw   x0, 0(t0)                   # exactly-once counter = 0
    li   t0, ISVC
    sw   x0, 0(t0)

    # program a valid SRC/DST but LEN=0 so ONLY the LEN=0 reject trips CH0ERR;
    # set ERRIE but keep the router route OFF -> CH0ERR sets, no meip yet.
    sw   s1, O_C0SRC(s0)
    sw   s2, O_C0DST(s0)
    sw   x0, O_C0LEN(s0)             # LEN = 0
    li   t0, CFG_SINC
    ori  t0, t0, CFG_DINC
    sw   t0, O_C0CFG(s0)
    li   t0, GO_ERR
    sw   t0, O_CR(s0)                # DMAEN | ERRIE | CH0GO -> reject-at-GO

    li   t6, 20000
5:  lw   t1, O_SR(s0)
    andi t2, t1, CH0ERR
    bnez t2, 6f
    addi t6, t6, -1
    bnez t6, 5b
    j    wdma_fail
6:  # RIDER: PENDX bit23 must be set (raw source pending, deterministic) ----
    li   t0, IRTR_PENDX
    lw   t1, 0(t0)
    li   t2, ERR_SRC_BIT
    and  t1, t1, t2
    beqz t1, wdma_fail

    # enable the route -> meip -> dispatcher -> claim 119 -> handler
    li   t0, IRTR_ENX
    li   t1, ENX_ERR
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wdma_fail

    li   t6, 20000
7:  li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bge  t1, t2, 8f
    addi t6, t6, -1
    bnez t6, 7b
    j    wdma_fail
8:  # exactly one delivery (in_service gateway)
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wdma_fail
    # RIDER: the handler recorded INSVCX bit23 while claimed
    li   t0, ISVC
    lw   t1, 0(t0)
    li   t2, ERR_SRC_BIT
    bne  t1, t2, wdma_fail
    # handler W1C'd CH0ERR -> irq_err dropped
    lw   t1, O_SR(s0)
    andi t1, t1, CH0ERR
    bnez t1, wdma_fail
    # let any (erroneous) second delivery happen, then confirm FLAG still 1
    li   t6, 2000
9:  addi t6, t6, -1
    bnez t6, 9b
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, wdma_fail
    li   t0, IRTR_ENX
    sw   x0, 0(t0)                   # un-route (clean)

    RVTEST_PASS

wdma_fail:
    RVTEST_FAIL

    # ---- DMA0_ERR handler (vector 119; M19 plain-ret meip ABI). Reached via
    # ---- CLAIM=119 -> dispatcher jalr through IVT slot 119. Records the
    # ---- INSVCX in-handler proof, clears the LEVEL (W1C CH0ERR) BEFORE
    # ---- returning (dispatcher COMPLETEs after), bumps the exactly-once FLAG.
    # ---- t0-t2 dispatcher-saved scratch; ra survives. s0-s2 untouched. ------
    .section .text.init
dma0_err_isr:
    li   t0, IRTR_INSVCX
    lw   t1, 0(t0)
    li   t2, ERR_SRC_BIT
    and  t1, t1, t2                  # isolate bit23 (source 119 in service)
    li   t0, ISVC
    sw   t1, 0(t0)                   # mainline requires == 0x800000
    li   t0, DMA_BASE
    li   t1, CH0ERR
    sw   t1, O_SR(t0)                # W1C CH0ERR -> irq_err level drops
    li   t0, FLAG
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    ret

    # ---- env meip dispatcher (.isr_meip @0xB100) + IVT slot 85 ----------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 119 = DMA0_ERR (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85). Slot 119 @ .ivt+4*119 = 0x1DC. --------
    .section .ivt, "ax"
    .org 4*119
    jal  zero, dma0_err_isr          # slot 119 = IRQB_DMA0_ERR
    .previous

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
