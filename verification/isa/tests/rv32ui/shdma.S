# See LICENSE for license details.

#*****************************************************************************
# shdma.S  (digperiphs Phase 3 -- DMA controller integration proof, ritual
#           step 6)
#-----------------------------------------------------------------------------
# HART-0 DIRECTED test of the DMA0 controller inside the full MCU. DMA0 exists
# ONLY in dma-enabled configs (castalia_dma NCH=2, wound NCH=4), so this test
# runs via `make verify CONFIG=...` and is gated by the `dma` tag in
# verify_stage.py -- it is NOT in the default behavioral_mp suite.
#
# This is a PLAIN single-hart test: hart 0 runs the whole exercise while harts
# 1-3 stay parked in the bootrom (like irqctx.S / shmem.S -- no MP_STAGE /
# MP_LAUNCH; the tb reports "tile hart(s) silent/parked", expected). DMA0 is
# reached through the arbiter at 0x6800 (mutex-page sub-slot 8, design doc D5).
# It is an mclk block (register file on gated ClkMem), so NO SYS_CLK_CR=0 is
# needed (that rule is for smclk peripherals; this touches none).
#
# LEGS (check-heavy; each leg ends in a bounded poll that trips inside the
# 100ms tb watchdog -- budgets 20000, shirq/shperiph precedent):
#   L0 reset defaults : DMA0CR=0, DMA0SR=0, DMA0CRC=0xFFFF (D5).
#   L1 mem-to-mem+CRC : CH0 SINC/DINC/CRCEN copy of a 4-word buffer; GO then
#      IMMEDIATELY read SR and require BUSY=1 -- the D8 same-cycle blind-window
#      guarantee (BUSY = engine_busy OR go_pending, no assert gap); poll
#      CHnDONE; DST==SRC; DMA0CRC == a PRECOMPUTED CRC16-CDMA2000 constant;
#      W1C CHnDONE.
#   L2 IRQ delivery   : route vector 118 (source 118) to hart 0, DONEIE=1,
#      copy again, `extinguish` (WFI-park); the DMA-done meip (IVT slot 85 ->
#      MEIP_DISPATCHER -> CLAIM 118 -> jalr IVT slot 118 -> plain-ret handler
#      that W1Cs CHnDONE + increments FLAG + ignites -> ret -> dispatcher
#      COMPLETE(118) -> iret) wakes hart 0; FLAG must be EXACTLY 1
#      (exactly-once via the router's in_service gateway); re-check after a
#      delay that no second delivery bumped it.
#   L3 error model    : CH0 GO with LEN=0 -> CHnERR sets (reject-at-GO, D13),
#      no BUSY hang; W1C clears it.
#   L4 deny-guard     : CH0 SRC=0x6000 (mutex window) -> the engine SUPPRESSES
#      the read, CHnERR + abort, NO master txn (D12/A5); PROVE the mutex was
#      never claimed (a hart lw of 0x6000 returns 0 = was free), then RESTORE
#      (release). W1C.
#   L5 NCH-agnostic   : CH2/CH3 SR bits (CHnDONE/CHnERR) and register slots read
#      0 -- valid at BOTH NCH=2 (absent, D6) and NCH=4 (real but never armed).
#
# LEDGER DERIVATION (CLAUDE.md shared-window ledger; window free at N=4 AND
# N=18 -- though dma configs are 4-hart Castalia only, both shapes checked per
# the ritual). Claimed WINDOW = 0x100E0-0x1011C (16 words), used sub-range
# 0x100E0-0x10100. Below it: shmem_mp/shcount hammer 0x10090+4*hartid tops at
# 0x1009C (N=4) / 0x100D4 (N=18); shlrsc tile hammer 0x10040+4*h tops at
# 0x1004C / 0x10084; shcount counter 0x10080 -- ALL < 0x100E0. Above it: shboot
# DONE 0x10120+4*h (first 0x10124) and shspin DONE/LOCK at 0x10120+ -- ALL
# >= 0x10120 > 0x1011C. So [0x100E0,0x1011C] is free at both shapes; < 0x10500
# (loader rows) and < 0x10800 (bootrom zero range -> write-before-read holds).
#     SRC_BUF = 0x100E0  (4 words)   DST_BUF = 0x100F0  (4 words)
#     FLAG    = 0x10100  (ISR exactly-once counter)
#
# CRC DERIVATION: CRC16-CDMA2000 (poly 0xC857, seed 0xFFFF, MSB-first, NO
# reflection, NO final XOR -- CRC16.vhd VERBATIM), folded over the transferred
# words' bytes b0->b3 (little-endian first, D14). Over SRC = {0x11223344,
# 0xAABBCCDD, 0x0F1E2D3C, 0x76543210} the byte stream is
# 44 33 22 11 DD CC BB AA 3C 2D 1E 0F 10 32 54 76 -> CRC = 0x61C3. Computed
# offline by scratchpad/dma_crc.py (a script file, not `python3 -c` -- the
# aoj_cal quote-strip gotcha). The byte-asymmetric words prove the fold order.
#
# EN WORD/BIT for source 118 (irq_router row layout, M19 + irq_router.vhd):
# per-hart row stride 0x10 = 4 enable words {ENL,ENM,ENU,ENX} at +0/4/8/C;
# NUM_EN_WORDS = ceil(119/32) = 4. Source 118 -> word 118/32 = 3 (ENX), bit
# 118 mod 32 = 22. Hart-0 row 0 (LIVE): H0ENX @ 0x7000+0x10*0+0xC = 0x700C,
# value 1<<22 = 0x00400000.
#
# NOTE: RVTEST_CODE_END is 'unimp' (traps) in this env -- every path ends in a
# spin; the test never falls through.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

# ---- DMA0 register file (base 0x6800; slot n @ +4n, D5) --------------------
#define DMA_BASE   0x6800
#define O_CR       0x00        /* DMA0CR   */
#define O_SR       0x04        /* DMA0SR   */
#define O_C0SRC    0x08        /* DMA0C0SRC */
#define O_C0DST    0x0C        /* DMA0C0DST */
#define O_C0LEN    0x10        /* DMA0C0LEN */
#define O_C0CFG    0x14        /* DMA0C0CFG */
#define O_C2SRC    0x28        /* DMA0C2SRC */
#define O_C2DST    0x2C        /* DMA0C2DST */
#define O_C3SRC    0x38        /* DMA0C3SRC */
#define O_C3DST    0x3C        /* DMA0C3DST */
#define O_CRC      0x48        /* DMA0CRC (slot 18) */

# ---- DMA0CR bits ----------------------------------------------------------
#define DMAEN      (1 << 0)
#define CH0GO      (1 << 1)
#define DONEIE     (1 << 12)
#define GO_POLL    (DMAEN | CH0GO)             /* 0x0003  */
#define GO_IRQ     (DMAEN | DONEIE | CH0GO)    /* 0x1003  */

# ---- DMA0SR bits ----------------------------------------------------------
#define BUSY       (1 << 0)
#define CH0DONE    (1 << 1)
#define CH0ERR     (1 << 5)
#define CH23_BITS  ((1<<3)|(1<<4)|(1<<7)|(1<<8))   /* CH2/CH3 DONE+ERR = 0x198 */

# ---- DMA0C0CFG bits -------------------------------------------------------
#define CFG_SINC   (1 << 0)
#define CFG_DINC   (1 << 1)
#define CFG_CRCEN  (1 << 7)
#define CFG_M2MCRC (CFG_SINC | CFG_DINC | CFG_CRCEN)   /* 0x83 */
#define CFG_M2M    (CFG_SINC | CFG_DINC)               /* 0x03 */

# ---- fabric constants -----------------------------------------------------
#define CRC_SEED   0xFFFF
#define CRC_EXPECT 0x61C3
#define MUTEX0     0x6000                 /* mutex-bank sub-slot 0 (deny window) */
#define IRTR_H0ENX 0x700C                 /* hart-0 router enable word 3 (ENX)   */
#define SRC118_BIT 0x00400000             /* source 118 -> ENX bit 22            */
#define DMA_LEN    4

# ---- shared-window words (derived above) ----------------------------------
#define SRC_BUF    0x100E0
#define DST_BUF    0x100F0
#define FLAG       0x10100

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0            # private TCM top; IRQ_SV pushes PC at sp-4
    li   s0, DMA_BASE          # DMA0 register base (0x6800, through the arbiter)
    li   s1, SRC_BUF
    li   s2, DST_BUF

    # ================= L0: reset defaults (D5) ==========================
    lw   t0, O_CR(s0)
    bnez t0, shdma_fail        # DMA0CR resets 0
    lw   t0, O_SR(s0)
    bnez t0, shdma_fail        # DMA0SR resets 0 (BUSY/DONE/ERR/ACTIVECH all 0)
    lw   t0, O_CRC(s0)
    li   t1, CRC_SEED
    bne  t0, t1, shdma_fail    # DMA0CRC resets 0xFFFF

    # ================= L1: mem-to-mem + CRC copy (polled) ================
    # fill SRC (byte-asymmetric -> proves CRC fold order) + poison DST
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

    # program CH0: SRC/DST/LEN/CFG + seed the CRC accumulator
    sw   s1, O_C0SRC(s0)
    sw   s2, O_C0DST(s0)
    li   t0, DMA_LEN
    sw   t0, O_C0LEN(s0)
    li   t0, CFG_M2MCRC        # SINC | DINC | CRCEN, TRIG=0 (software mem2mem)
    sw   t0, O_C0CFG(s0)
    li   t0, CRC_SEED
    sw   t0, O_CRC(s0)         # DMA0CRC = 0xFFFF (seed before GO, D14)

    # GO, then IMMEDIATELY read SR -- BUSY MUST be 1 the same cycle (D8)
    li   t0, GO_POLL
    sw   t0, O_CR(s0)          # CR = DMAEN | CH0GO
    lw   t1, O_SR(s0)          # the very next txn: same-cycle blind-window read
    andi t1, t1, BUSY
    beqz t1, shdma_fail        # BUSY==0 => the D8 blind window regressed

    # bounded-poll CHnDONE
    li   t6, 20000
1:  lw   t1, O_SR(s0)
    andi t2, t1, CH0DONE
    bnez t2, 2f
    addi t6, t6, -1
    bnez t6, 1b
    j    shdma_fail
2:  # DST == SRC (proves the copy landed over the poison)
    lw   t0, 0(s1);  lw t1, 0(s2);  bne t0, t1, shdma_fail
    lw   t0, 4(s1);  lw t1, 4(s2);  bne t0, t1, shdma_fail
    lw   t0, 8(s1);  lw t1, 8(s2);  bne t0, t1, shdma_fail
    lw   t0, 12(s1); lw t1, 12(s2); bne t0, t1, shdma_fail
    # DMA0CRC == precomputed constant (byte order + fold proven, D14)
    lw   t0, O_CRC(s0)
    li   t1, CRC_EXPECT
    bne  t0, t1, shdma_fail
    # W1C CH0DONE, poll until cleared (the clr crosses ClkMem->clk, ~2-3 clk)
    li   t0, CH0DONE
    sw   t0, O_SR(s0)
    li   t6, 20000
3:  lw   t1, O_SR(s0)
    andi t1, t1, CH0DONE
    beqz t1, 4f
    addi t6, t6, -1
    bnez t6, 3b
    j    shdma_fail
4:

    # ================= L2: IRQ delivery via vector 118 ==================
    li   t0, FLAG
    sw   x0, 0(t0)             # exactly-once counter = 0

    # route source 118 to hart 0 (H0ENX bit 22) + prove the write landed
    li   t0, IRTR_H0ENX
    li   t1, SRC118_BIT
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, shdma_fail

    # re-poison DST so this copy is proven fresh
    li   t0, 0xC3C3C3C3
    sw   t0, 0(s2)
    sw   t0, 4(s2)
    sw   t0, 8(s2)
    sw   t0, 12(s2)

    # program CH0 (no CRC this leg), arm with DONEIE, then WFI-park
    sw   s1, O_C0SRC(s0)
    sw   s2, O_C0DST(s0)
    li   t0, DMA_LEN
    sw   t0, O_C0LEN(s0)
    li   t0, CFG_M2M
    sw   t0, O_C0CFG(s0)
    li   t0, GO_IRQ
    sw   t0, O_CR(s0)          # CR = DMAEN | DONEIE | CH0GO
    # RACE (shirq "sleep-before-IRQ"): the DMA cannot raise CHnDONE for ~30+
    # clk (go_tgl sync + 4 word read/write txn pairs through the arbiter),
    # while `extinguish` is the very next instruction -- extinguish wins, so
    # the meip arrives after sleep and wakes hart 0 through the dispatcher.
    extinguish

    # ---- resume here after the dispatcher's iret -----------------------
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, shdma_fail    # exactly one delivery (in_service gateway)
    lw   t1, O_SR(s0)          # handler W1C'd CH0DONE -> irq_done dropped
    andi t1, t1, CH0DONE
    bnez t1, shdma_fail
    # the IRQ-leg copy really ran
    lw   t0, 0(s1);  lw t1, 0(s2);  bne t0, t1, shdma_fail
    lw   t0, 12(s1); lw t1, 12(s2); bne t0, t1, shdma_fail
    # let any (erroneous) second delivery happen, then confirm FLAG still 1
    li   t6, 2000
5:  addi t6, t6, -1
    bnez t6, 5b
    li   t0, FLAG
    lw   t1, 0(t0)
    li   t2, 1
    bne  t1, t2, shdma_fail
    # un-route source 118 (clean; nothing should re-pend)
    li   t0, IRTR_H0ENX
    sw   x0, 0(t0)

    # ================= L3: error model -- LEN=0 reject-at-GO =============
    sw   s1, O_C0SRC(s0)       # valid SRC/DST so ONLY LEN=0 trips the error
    sw   s2, O_C0DST(s0)
    sw   x0, O_C0LEN(s0)       # LEN = 0
    li   t0, CFG_M2M
    sw   t0, O_C0CFG(s0)
    li   t0, GO_POLL           # DONEIE cleared -> no meip; ERRIE never set
    sw   t0, O_CR(s0)
    # CHnERR must set (reject-at-GO, D13); channel never runs
    li   t6, 20000
6:  lw   t1, O_SR(s0)
    andi t2, t1, CH0ERR
    bnez t2, 7f
    addi t6, t6, -1
    bnez t6, 6b
    j    shdma_fail
7:  # no BUSY hang: BUSY (go_pending pulse only) must drop back to 0
    li   t6, 20000
8:  lw   t1, O_SR(s0)
    andi t2, t1, BUSY
    beqz t2, 9f
    addi t6, t6, -1
    bnez t6, 8b
    j    shdma_fail
9:  # W1C CH0ERR, poll until cleared
    li   t0, CH0ERR
    sw   t0, O_SR(s0)
    li   t6, 20000
10: lw   t1, O_SR(s0)
    andi t1, t1, CH0ERR
    beqz t1, 11f
    addi t6, t6, -1
    bnez t6, 10b
    j    shdma_fail
11:

    # ================= L4: deny-guard (mutex read-side-effect) ===========
    li   t0, MUTEX0
    sw   t0, O_C0SRC(s0)       # SRC = 0x6000 -> deny-guard hit at M_IDLE
    sw   s2, O_C0DST(s0)
    li   t0, 1
    sw   t0, O_C0LEN(s0)       # LEN=1 so the channel ARMS and reaches the guard
    li   t0, CFG_M2M
    sw   t0, O_C0CFG(s0)
    li   t0, GO_POLL
    sw   t0, O_CR(s0)
    # the denied read is SUPPRESSED: CHnERR + abort, NO master txn issued
    li   t6, 20000
12: lw   t1, O_SR(s0)
    andi t2, t1, CH0ERR
    bnez t2, 13f
    addi t6, t6, -1
    bnez t6, 12b
    j    shdma_fail
13: # busy must drop (channel aborted, D12)
    li   t6, 20000
14: lw   t1, O_SR(s0)
    andi t2, t1, BUSY
    beqz t2, 15f
    addi t6, t6, -1
    bnez t6, 14b
    j    shdma_fail
15: # PROVE no mutex side effect: mutex 0 is still FREE. A hart lw of 0x6000
    # is itself an atomic claim -- 0 => was free (the DMA never issued the
    # denied read). Nonzero => the guard failed and something claimed it.
    li   t0, MUTEX0
    lw   t1, 0(t0)
    bnez t1, shdma_fail
    sw   x0, 0(t0)             # release mutex 0 (restore the free state)
    # W1C CH0ERR, poll until cleared
    li   t0, CH0ERR
    sw   t0, O_SR(s0)
    li   t6, 20000
16: lw   t1, O_SR(s0)
    andi t1, t1, CH0ERR
    beqz t1, 17f
    addi t6, t6, -1
    bnez t6, 16b
    j    shdma_fail
17:

    # ================= L5: NCH-agnostic CH2/CH3 read 0 ==================
    # valid at NCH=2 (absent -> read 0, D6) AND NCH=4 (real but never armed).
    lw   t1, O_SR(s0)
    li   t0, CH23_BITS
    and  t1, t1, t0
    bnez t1, shdma_fail        # CH2/CH3 DONE/ERR bits must be 0
    lw   t1, O_C2SRC(s0)
    bnez t1, shdma_fail
    lw   t1, O_C2DST(s0)
    bnez t1, shdma_fail
    lw   t1, O_C3SRC(s0)
    bnez t1, shdma_fail
    lw   t1, O_C3DST(s0)
    bnez t1, shdma_fail

    RVTEST_PASS                # a0 = 0xCAFEBABE, spin

shdma_fail:
    RVTEST_FAIL                # a0 = 0xDEADBEEF, spin

    # ---- DMA0_DONE handler (vector 118; M19 plain-ret meip ABI). Reached
    # ---- via CLAIM=118 -> dispatcher jalr through IVT slot 118. Clears the
    # ---- LEVEL (W1C CHnDONE) BEFORE returning (dispatcher COMPLETEs after),
    # ---- bumps the exactly-once FLAG, and ignites (hart 0 was asleep, so the
    # ---- dispatcher's iret must resume MAINLINE, not sleep). t0/t1/t2 are
    # ---- dispatcher-saved scratch; ra survives (ret). s0-s2 untouched. ------
dma_done_isr:
    li   t0, DMA_BASE
    li   t1, CH0DONE
    sw   t1, O_SR(t0)          # W1C CH0DONE -> irq_done level drops
    li   t0, FLAG
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)             # FLAG++ (exactly-once counter)
    ignite                     # clear sleep_cpu; iret then resumes mainline
    ret

    # ---- env meip dispatcher (.isr_meip @0xB100) + IVT slot 85 ----------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    # ---- extend the IVT to slot 118 = DMA0_DONE (DEFINE_IVT stops at 82,
    # ---- IVT_ARM_MEIP fills 83-85; slots 86-117 stay parked/zero, never
    # ---- routed). Slot 118 @ .ivt+4*118 = 0x1D8 -> jal preserves the
    # ---- dispatcher's ra so the handler rets cleanly. ----------------------
    .section .ivt, "ax"
    .org 4*118
    jal  zero, dma_done_isr    # slot 118 = IRQB_DMA0_DONE
    .previous

    # NOTE: RVTEST_CODE_END is 'unimp' in this env (traps!) -- never fall
    # through; every path above ends in a spin.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
