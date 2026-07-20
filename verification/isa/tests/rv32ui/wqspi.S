# See LICENSE for license details.

#*****************************************************************************
# wqspi.S  (wound-config firmware smoke — FW-2)
#-----------------------------------------------------------------------------
# QSPI0 @0x4C00 IRQ-DELIVERY integration smoke. Single-hart directed (hart 0;
# tiles stay parked — no MP_LAUNCH, no mp_boot.h). Proves the CPU can launch a
# QSPI transaction on the clk_baud serial core and that its two IRQ sources
# (vec 55 TCIF, vec 56 RXFULL) route through irq_router (HhENM) -> meip ->
# env MEIP_DISPATCHER -> IVT -> plain-ret handlers -> CLAIM/COMPLETE.
#
# There is NO external flash: qspi_io_in is tb-driven '0' (MCU.vhd:3705-08),
# so a READ transaction lands RX == 0x00 deterministically and sets RXFULL +
# TCIF together (QSPI.vhd:552-556). We route P5.2-5 to AF1 (P5AFS) so the read
# also exercises the GPIO4 alt-function input mux (io_in still '0').
#
# QSPI register map (qspi_spec.md driver note; MemoryMap RegSlotQSPIx*):
#   CR 0x4C00  CMD 0x4C04  ADR 0x4C08  TX 0x4C0C  RX 0x4C10  SR 0x4C14
#   CR : EN[0] CMDW[2:1] ADRW[4:3] DATW[6:5] CPOL[7] CPHA[8] AWID[10:9]
#        DUMMY[15:11] CSSEL[18:16] BR[26:19] TCIE[27] RXFIE[28]
#   CMD: opcode[7:0] DLEN[9:8] DIR[10]  (lane-0 write LAUNCHES)
#   SR : BUSY[0] TXEIF[1] RXFULL[2] TCIF[3]  (flags W1C)
#   irq_tc  (55) = TCIF & TCIE ;  irq_rxf (56) = RXFULL & RXFIE  (QSPI.vhd:219-220)
#
# Router row 0 (hart 0, LIVE): HhENM @0x7004, sources 55/56 -> bits 23/24.
# IVT: env DEFINE_IVT already points slot 55 -> .isr_afe_shared (0xBC00) and
# slot 56 -> .isr_eis (0xBD00); we drop our plain-ret handlers there and arm
# the meip slot 85 with IVT_ARM_MEIP(). Zero env change.
#
# SMCLK RULE: the serial core is SMCLK-domain; the bootrom parks SMCLK on LFXT,
# so write SYS_CLK_CR=0 (HFXT) first (else ~32 kHz frames blow the poll budget).
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SYS_CLK_CR  0x4900
#define QSPI_CR     0x4C00
#define QSPI_CMD    0x4C04
#define QSPI_ADR    0x4C08
#define QSPI_RX     0x4C10
#define QSPI_SR     0x4C14
#define P5AFS       0x632C        /* GPIO4 base 0x6300 + RegSlotPxAFS(11)*4 */
#define IRTR_ENM    0x7004        /* HhENM, hart-0 row */

/* CR: EN | BR=1<<19 | TCIE(27) | RXFIE(28); single-lane, AWID=0, DUMMY=0 */
#define QSPI_CR_VAL 0x18080001
/* CMD: opcode 0x0B | DLEN=01 (8-bit, <<8) | DIR=READ (1<<10) -> LAUNCH */
#define QSPI_CMD_VAL 0x0000050B
#define ENM_QSPI    0x01800000    /* bits 23,24 = sources 55,56 */
#define P5AFS_QSPI  0x00111100    /* pins P5.2-5 nibble = AF1 (001) */

#define DONE_TC     0xA000        /* private-TCM handler flags (single hart) */
#define DONE_RXF    0xA004

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0               # valid stack before any IRQ (IRQ_SV pushes PC)

    # clear handler DONE flags
    li   s0, DONE_TC
    li   s1, DONE_RXF
    sw   x0, 0(s0)
    sw   x0, 0(s1)

    # SMCLK -> HFXT (bootrom left it on LFXT)
    li   t0, SYS_CLK_CR
    sw   x0, 0(t0)

    # P5.2-5 -> AF1 (route QSPI IO input mux; io_in still tb '0')
    li   t0, P5AFS
    li   t1, P5AFS_QSPI
    sw   t1, 0(t0)
    lw   t2, 0(t0)
    bne  t2, t1, wqspi_fail

    # enable sources 55/56 in hart-0 router row (HhENM) + readback
    li   s2, IRTR_ENM
    li   t1, ENM_QSPI
    sw   t1, 0(s2)
    lw   t2, 0(s2)
    bne  t2, t1, wqspi_fail

    # program CR (enable + IE), address, then CMD LAST (launch)
    li   t0, QSPI_CR
    li   t1, QSPI_CR_VAL
    sw   t1, 0(t0)
    li   t0, QSPI_ADR
    sw   x0, 0(t0)
    li   t0, QSPI_CMD
    li   t1, QSPI_CMD_VAL
    sw   t1, 0(t0)               # LAUNCH

    # wait for BOTH IRQs delivered (handler DONE flags), bounded
    li   s3, 20000
wqspi_poll:
    lw   t0, 0(s0)               # DONE_TC
    beqz t0, wqspi_dec
    lw   t1, 0(s1)               # DONE_RXF
    beqz t1, wqspi_dec
    j    wqspi_check
wqspi_dec:
    addi s3, s3, -1
    bnez s3, wqspi_poll
    j    wqspi_fail

wqspi_check:
    # RX must be 0x00 (no flash), read is side-effect-free
    li   t0, QSPI_RX
    lw   t1, 0(t0)
    bnez t1, wqspi_fail

    # SR TCIF+RXFULL must be cleared by the handlers (W1C retire)
    li   t0, QSPI_SR
    lw   t1, 0(t0)
    andi t1, t1, 0xC             # bits 2(RXFULL),3(TCIF)
    bnez t1, wqspi_fail

    RVTEST_PASS

wqspi_fail:
    RVTEST_FAIL

    # ---- QSPI TC handler (vec 55) — DEFINE_IVT slot 55 -> 0xBC00.
    # Plain-ret ABI: clear the LEVEL (TCIF W1C) before returning; only
    # t0/t1 (dispatcher-saved scratch) touched; ra survives. ----------------
    .section .isr_afe_shared, "ax"
qspi_tc_h:
    li   t0, QSPI_SR
    li   t1, 0x8                 # W1C TCIF (bit 3) -> drop irq_tc level
    sw   t1, 0(t0)
    li   t0, DONE_TC
    li   t1, 0x000000C1
    sw   t1, 0(t0)
    ret
    .previous

    # ---- QSPI RXFULL handler (vec 56) — DEFINE_IVT slot 56 -> 0xBD00 -------
    .section .isr_eis, "ax"
qspi_rxf_h:
    li   t0, QSPI_SR
    li   t1, 0x4                 # W1C RXFULL (bit 2) -> drop irq_rxf level
    sw   t1, 0(t0)
    li   t0, DONE_RXF
    li   t1, 0x000000C2
    sw   t1, 0(t0)
    ret
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) + arm IVT slot 85 --------
    MEIP_DISPATCHER()
    IVT_ARM_MEIP()

    RVTEST_CODE_END              # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
