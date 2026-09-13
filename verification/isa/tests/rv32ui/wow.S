# See LICENSE for license details.

# VestaRV: 1-Wire master interrupt smoke
# Hart 0 only, tiles parked. OW0 sits at 0x6700 and the transaction-complete interrupt is vector 117, routed through irq_router HhENX bit 21 to meip, the MEIP_DISPATCHER, the IVT and a plain-ret handler that claims and completes.
# TB CONTRACT: with no loopback device on the line DQ reads a strong '0', so every reset samples PRESENCE and any read returns 0x00. The test exploits that: reset gives presence and a TC interrupt, and a read-byte gives RX == 0x00 and another. DQ stuck low also sets SR.SHORT and SR.PRES, but with ERRIE off only TC contributes to the IRQ.
# THE BENCH MUST DRIVE prt4(7). P4.7 is a real pad, so with nothing driving it the vendor model floats and only creeps to a weak '1' 100 us after each release, which is unusable as a 1-Wire line. riscv_tb must give it a weak `prt4(7) <= 'L';`, the way it already does for the open-drain I2C0 pads, which reproduces the stuck-low contract and still yields to any strong driver. A weak 'H' would make this a no-device bus and the expectations here would have to become NOPRES and RX == 0xFF.
# Register map: CR 0x6700 = OWEN[0] ODS[1] SPUEN[2] TCIE[3] ERRIE[4]; CMD 0x6704 = OP[2:0] BITVAL[8], and a lane-0 write LAUNCHES when OWEN is set and BUSY is clear, with OP 0 RESET, 1 WRBIT, 2 RDBIT, 3 WRBYTE, 4 RDBYTE; TX 0x6708; RX 0x670C; DIV 0x6710, where a tick is (DIV+1) clocks and reset 0 is fastest; SR 0x6714 = BUSY[0] ro, TCIF[1] W1C, PRES[2] ro, NOPRES[3] W1C, SHORT[4] W1C. irq_ow is TCIF AND TCIE. OW0 is mclk-domain, so no SYS_CLK_CR write is needed, and ODS = 1 with DIV = 0 keeps the whole sequence well under a few hundred microseconds of sim time.
# DQ ROUTING IS NOT AUTOMATIC: OW0's DQ is P4.7 on alt plane AF2, and ow0_dq_in follows prt4_in(7) ONLY while P4.7 selects AF2, otherwise it idles '1'. Since P4AFS resets to 0, every pin is AF0 and this test MUST route the pin. PxAFS IS FOUR BITS PER PIN, so P4.7 is nibble 7 at bits 31:28 and AF2 is 0x20000000. The test also sets PxSEL bit 7 so the pad's out and dir come from the AF2 plane, open-drain with out fixed 0 and dir pulling low; the input mux ignores PxSEL, but a real DQ has to be drivable. P4.7's pull is enabled at reset and PxOUT stays 0. GPIO3 is at 0x4D00, so PxSEL is 0x4D24 and PxAFS is 0x4D2C; the headers spell these P3SEL and P3AFS, because header register numbering is 0-based while the pin and port naming is 1-based.

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
    jal  zero, 0x09100               # 85 meip  -> env dispatcher (.isr_meip)
    .org 4*117                       # slot 117 @ 0x1D4
    jal  zero, ow0_tc_h              # 117 = IRQB_OW0
    .previous

    # ---- env meip dispatcher (.isr_meip @0x9100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END                  # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
