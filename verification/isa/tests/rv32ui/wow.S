# See LICENSE for license details.

#*****************************************************************************
# wow.S  (wound-config firmware smoke — digperiphs Stage E)
#-----------------------------------------------------------------------------
# OW0 @0x6700 Dallas/Maxim 1-Wire master IRQ-delivery smoke. Single-hart
# directed (hart 0; tiles parked). Proves the CPU can launch 1-Wire
# transactions and that the transaction-complete IRQ (vector 117) routes
# through irq_router (HhENX bit21) -> meip -> MEIP_DISPATCHER -> IVT ->
# plain-ret handler -> CLAIM/COMPLETE.
#
# TB CONTRACT: DQ is driven a STRONG '0' in both the behavioral and gate
# testbenches (there is NO loopback device). So every reset always samples
# PRESENCE (DQ low), and any read bit/byte returns 0x00. This test exploits
# that: reset+presence -> TC IRQ; read-byte -> RX == 0x00 + TC IRQ again.
# (Because DQ is stuck low, the RTL also sets SR.SHORT and SR.PRES; with
# ERRIE off, SHORT does not contribute to the irq — only TC does.)
#
# OW register map (onewire_spec.md / OneWire.vhd AS-BUILT; RegSlotOWx*):
#   CR 0x6700  CMD 0x6704  TX 0x6708  RX 0x670C  DIV 0x6710  SR 0x6714
#   CR : OWEN[0] ODS[1](overdrive) SPUEN[2](stub) TCIE[3] ERRIE[4]
#   CMD: OP[2:0] BITVAL[8]  (lane-0 write LAUNCHES when OWEN=1 & !BUSY)
#        OP: RESET=0 WRBIT=1 RDBIT=2 WRBYTE=3 RDBYTE=4
#   SR : BUSY[0](ro) TCIF[1](W1C) PRES[2](ro) NOPRES[3](W1C) SHORT[4](W1C)
#   DIV: tick = (DIV+1) clk; reset 0 = fastest.  irq_ow (117) = TCIF & TCIE
#
# OW0 is mclk-domain (register file on ClkMem, engine on free-running mclk) —
# NO SYS_CLK_CR write is needed. ODS=1 + DIV=0 keeps the whole reset+presence
# and read-byte well under a few hundred us of sim time.
#
# DQ ROUTING: ow0_dq_in = prt6_in(6) ONLY when P6.6 is AF1 (MCU.vhd:4106),
# otherwise it idles '1'. RstValP6AFS=0x1 sets only P6.0 to AF1 — P6.6 is AF0
# out of reset — so this test MUST route P6.6 to AF1 (like wqspi routes P5AFS)
# for the tb's strong-'0' DQ (prt6_in=(others=>'0'), riscv_tb:292) to reach
# the engine and yield PRESENCE. (Without it DQ idles high -> NO presence.)
# PxAFS is 4 BITS PER PIN (a nibble, matching wqspi's P5AFS=0x00111100); P6.6
# is nibble 6 = bits 27:24, so AF1 = 0x0100_0000 (register bit24, which the
# GPIO repacks to the 3-bit p6_afs field the mux reads).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define OW_CR       0x6700
#define OW_CMD      0x6704
#define OW_RX       0x670C
#define OW_DIV      0x6710
#define OW_SR       0x6714
#define P6AFS       0x642C            /* GPIO5 base 0x6400 + RegSlotPxAFS(11)*4 */
#define P6AFS_OW    0x01000001        /* P6.6 nibble (bits27:24)=AF1; keep P6.0 AF1 */
#define IRTR_ENX    0x700C

/* CR: OWEN(0) | ODS(1) | TCIE(3) — leave ERRIE off (irq via TC only) */
#define OW_CR_VAL   0x0000000B
#define OP_RESET    0x0
#define OP_RDBYTE   0x4
#define ENX_OW      0x00200000        /* bit21 = source 117 */
#define SR_TCIF     0x2
#define SR_PRES     0x4
#define SR_SHORT    0x10
#define SR_TC_CLR   0x12              /* W1C TCIF(1) + SHORT(4) */

#define TC_CNT      0xA000            /* private-TCM handler TC counter */

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0

    li   s0, TC_CNT
    sw   x0, 0(s0)

    # ================= L0: reset defaults ==============================
    li   a0, OW_CR
    lw   t0, 0(a0)
    bnez t0, wow_fail                # CR resets 0
    li   a0, OW_SR
    lw   t0, 0(a0)
    bnez t0, wow_fail                # SR resets 0 (BUSY/TCIF/PRES/... all 0)

    # ================= L1: configure + route ==========================
    # route P6.6 -> AF1 so the tb's strong-'0' DQ reaches the engine
    li   a0, P6AFS
    li   t1, P6AFS_OW
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wow_fail
    li   a0, OW_DIV
    sw   x0, 0(a0)                   # DIV = 0 (fastest; also the reset value)
    li   a0, OW_CR
    li   t1, OW_CR_VAL
    sw   t1, 0(a0)                   # OWEN|ODS|TCIE

    li   t0, IRTR_ENX
    li   t1, ENX_OW
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wow_fail            # HhENX bit21 readback

    # ================= L2: RESET+presence -> TC IRQ (#1) ===============
    li   a0, OW_CMD
    li   t1, OP_RESET
    sw   t1, 0(a0)                   # LAUNCH reset+presence cycle

    li   s3, 20000
wow_p1:
    lw   t0, 0(s0)                   # TC_CNT
    li   t1, 1
    bge  t0, t1, wow_chk1
    addi s3, s3, -1
    bnez s3, wow_p1
    j    wow_fail
wow_chk1:
    # presence WAS detected (DQ low at sample -> SR.PRES sticky set)
    li   a1, OW_SR
    lw   t0, 0(a1)
    andi t0, t0, SR_PRES
    beqz t0, wow_fail

    # ================= L3: READ-BYTE -> RX==0x00 + TC IRQ (#2) =========
    li   a0, OW_CMD
    li   t1, OP_RDBYTE
    sw   t1, 0(a0)                   # LAUNCH read-byte

    li   s3, 20000
wow_p2:
    lw   t0, 0(s0)                   # TC_CNT
    li   t1, 2
    bge  t0, t1, wow_chk2
    addi s3, s3, -1
    bnez s3, wow_p2
    j    wow_fail
wow_chk2:
    li   a0, OW_RX
    lw   t0, 0(a0)                   # DQ stuck low -> all 8 bits 0
    bnez t0, wow_fail

    RVTEST_PASS

wow_fail:
    RVTEST_FAIL

    # ---- OW0 TC handler (vec 117, plain-ret) — clear the LEVEL (W1C TCIF,
    # ---- and SHORT which the stuck-low bench also sets) before returning,
    # ---- bump the TC counter. t0/t1 dispatcher-saved; ra survives. --------
    .section .text.init
ow0_tc_h:
    li   t0, OW_SR
    li   t1, SR_TC_CLR
    sw   t1, 0(t0)                   # W1C TCIF (+SHORT) -> drop irq_ow level
    li   t0, TC_CNT
    lw   t1, 0(t0)
    addi t1, t1, 1
    sw   t1, 0(t0)
    ret

    # ---- per-test IVT tail: arm 83/84/85 then slot 117 -------------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00               # 83 msip  -> park
    jal  zero, 0x0BB00               # 84 mtip  -> park
    jal  zero, 0x0B100               # 85 meip  -> env dispatcher (.isr_meip)
    .org 4*117                       # slot 117 @ 0x1D4
    jal  zero, ow0_tc_h              # 117 = IRQB_OW0
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
