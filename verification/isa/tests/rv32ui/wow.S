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
# TB CONTRACT: DQ reads a STRONG '0' with no loopback device on the line, so
# every reset always samples PRESENCE (DQ low) and any read bit/byte returns
# 0x00. This test exploits that: reset+presence -> TC IRQ; read-byte ->
# RX == 0x00 + TC IRQ again. (Because DQ is stuck low, the RTL also sets
# SR.SHORT and SR.PRES; with ERRIE off, SHORT does not contribute to the irq
# — only TC does.)
#
# !! TB DEPENDENCY (Stage H re-pin, 2026-07-26) !! Up to Stage E the DQ pad was
# P6.6 and riscv_tb hard-drove `prt6_in <= (others => '0')` (GPIO4/5 ports have
# NO pad cells in the tb), which IS where the strong-'0' contract came from.
# P4.7 is a REAL pad (PDUW16SDGZ_G in riscv_tb's pad_prt4_gen), so the level on
# prt4(7) now comes from the pad bus: with nothing driving it the vendor model
# floats (C = x) and only creeps to a weak '1' PullTime = 100 us after each
# release — unusable as a 1-Wire line. riscv_tb must therefore give prt4(7) a
# bench level, the way it already does for the open-drain I2C0 pads
# (`prt4(0) <= 'H'; prt4(1) <= 'H';`): a weak `prt4(7) <= 'L';` reproduces the
# stuck-low contract above verbatim (and yields to any strong driver), whereas
# a weak 'H' would turn this into a no-device bus and the expectations below
# would have to become NOPRES + RX == 0xFF.
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
# DQ ROUTING (Stage H re-pin): OW0's DQ is P4.7 / GPIO31 (DTP3) on alt plane
# AF2 — the pin-mux-v2 replaced-spread-slot mechanism, DQ having taken over the
# redundant T0CMP1 output-spread copy in that slot. ow0_dq_in = prt4_in(7) ONLY
# when P4.7 selects AF2, otherwise it idles '1', so this test MUST route the
# pin (RstValP4AFS = 0 -> every pin is AF0 out of reset). PxAFS is 4 BITS PER
# PIN (a nibble, like wqspi's P5AFS=0x00111100); P4.7 is nibble 7 = bits 31:28,
# so AF2 = 0x2000_0000 (the GPIO repacks it into the 3-bit p4_afs field the mux
# reads). The test also sets PxSEL bit 7 so the pad's out/dir come from the AF2
# plane (open-drain: out fixed 0, dir pulls low) — the INPUT mux ignores PxSEL,
# but a real DQ has to be drivable. P4.7's pull is enabled at reset
# (RstValP4REN = 0x80 when OneWire is configured); PxOUT stays 0.
# Register file: GPIO3 is at 0x4D00, so PxSEL = 0x4D24 and PxAFS = 0x4D2C
# (the headers spell these P3SEL/P3AFS — header register numbering is 0-based
# while the pin/port naming is 1-based).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define OW_CR       0x6700
#define OW_CMD      0x6704
#define OW_RX       0x670C
#define OW_DIV      0x6710
#define OW_SR       0x6714
#define P4SEL       0x4D24            /* GPIO3 base 0x4D00 + RegSlotPxSEL(9)*4  */
#define P4AFS       0x4D2C            /* GPIO3 base 0x4D00 + RegSlotPxAFS(11)*4 */
#define P4SEL_OW    0x00000080        /* P4.7 in alternate-function mode        */
#define P4AFS_OW    0x20000000        /* P4.7 nibble (bits31:28) = 2 -> AF2     */
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
    # route P4.7 -> AF2 so the bench DQ reaches the engine, and put the pin in
    # alternate-function mode so the AF2 plane owns the pad's open-drain drive
    li   a0, P4AFS
    li   t1, P4AFS_OW
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wow_fail
    li   a0, P4SEL
    li   t1, P4SEL_OW
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
