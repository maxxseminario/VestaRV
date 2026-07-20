# See LICENSE for license details.

#*****************************************************************************
# wi3c.S  (wound-config firmware smoke — FW-2)
#-----------------------------------------------------------------------------
# I3C0 @0x6100 IRQ-DELIVERY integration smoke via the deterministic idle-high
# address-NACK path. Single-hart directed (hart 0; tiles parked).
#
# P5.6/7 (I3C SDA/SCL) are KEPT AT AF0 (P5AFS reset = 0x0) so sda_in/scl_in
# idle HIGH = bus released (MCU.vhd:3710-11 -> '1' when not AF1). A launched SDR
# transfer to any address then samples the ACK bit HIGH = NACK (I3C.vhd:700),
# which sets ANACK + TCIF together (I3C.vhd:725-726). So the transfer TERMINATES
# with two enabled IRQ sources:
#   vec 86 (TC)   = TCIF  & TCIE  (I3C.vhd:1273, CR[24])
#   vec 89 (NACK) = ANACK & ERRIE (I3C.vhd:1276, CR[25])
# Both route through irq_router HhENU -> meip -> MEIP_DISPATCHER -> per-test IVT
# slots 86/89 -> plain-ret handlers -> CLAIM/COMPLETE. Order-independent DONE.
#
# I3C register map (i3c_spec.md; MemoryMap):
#   CR 0x6100  CMD 0x6104  TX 0x6108  RX 0x610C  SR 0x6110
#   CR : I3CEN[0] BUSMODE[1] SDAPP[2] IBIEN[3] ODBR[15:8] PPBR[23:16]
#        TCIE[24] ERRIE[25] DAAIE[26] IBIIE[27] RXFIE[28] TXEIE[29]
#   CMD: ADDR[6:0] RNW[7] REPSTART[8] STOPEN[9] ... DLEN[23:16]  (lane-0 LAUNCH)
#   SR : BUSY[0] TCIF[1] RXFULL[2] TXEIF[3] ANACK[4] ...  (W1C)
#
# Router row 0: HhENU @0x7008; sources 86->bit22, 89->bit25.
# IVT: per-test .ivt tail (supersedes IVT_ARM_MEIP) — .org 0x14C arms 83/84/85,
# then .org to slots 86 and 89 with jal into local plain-ret handlers.
#
# SMCLK RULE: serial core is SMCLK-domain; write SYS_CLK_CR=0 first.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SYS_CLK_CR  0x4900
#define I3C_CR      0x6100
#define I3C_CMD     0x6104
#define I3C_SR      0x6110
#define IRTR_ENU    0x7008        /* HhENU, hart-0 row */

/* CR: I3CEN | SDAPP(2) | ODBR=2<<8 | PPBR=2<<16 | TCIE(24) | ERRIE(25) */
#define I3C_CR_VAL  0x03020205
/* CMD: ADDR=0x50 | STOPEN(1<<9) | DLEN=1<<16 -> LAUNCH (write to unowned addr) */
#define I3C_CMD_VAL 0x00010250
#define ENU_I3C     0x02400000    /* bit22 (86 TC) + bit25 (89 NACK) */

#define DONE_TC     0xA000
#define DONE_NACK   0xA004

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   sp, 0xBFF0

    li   s0, DONE_TC
    li   s1, DONE_NACK
    sw   x0, 0(s0)
    sw   x0, 0(s1)

    # SMCLK -> HFXT
    li   t0, SYS_CLK_CR
    sw   x0, 0(t0)

    # enable sources 86/89 in hart-0 router row (HhENU) + readback
    li   s2, IRTR_ENU
    li   t1, ENU_I3C
    sw   t1, 0(s2)
    lw   t2, 0(s2)
    bne  t2, t1, wi3c_fail

    # program CR (enable + SDAPP + IE), then CMD LAST (launch)
    li   t0, I3C_CR
    li   t1, I3C_CR_VAL
    sw   t1, 0(t0)
    li   t0, I3C_CMD
    li   t1, I3C_CMD_VAL
    sw   t1, 0(t0)               # LAUNCH -> address NACK -> TCIF + ANACK

    # wait for BOTH IRQs delivered, bounded
    li   s3, 20000
wi3c_poll:
    lw   t0, 0(s0)               # DONE_TC
    beqz t0, wi3c_dec
    lw   t1, 0(s1)               # DONE_NACK
    beqz t1, wi3c_dec
    j    wi3c_pass
wi3c_dec:
    addi s3, s3, -1
    bnez s3, wi3c_poll
    j    wi3c_fail

wi3c_pass:
    RVTEST_PASS

wi3c_fail:
    RVTEST_FAIL

    # ---- I3C TC handler (vec 86, plain-ret) — clear TCIF (W1C bit1) --------
    .section .text.init
i3c0_tc_h:
    li   t0, I3C_SR
    li   t1, 0x2                 # W1C TCIF -> drop irq_tc level
    sw   t1, 0(t0)
    li   t0, DONE_TC
    li   t1, 0x00000086
    sw   t1, 0(t0)
    ret

    # ---- I3C NACK handler (vec 89, plain-ret) — clear ANACK (W1C bit4) -----
i3c0_nack_h:
    li   t0, I3C_SR
    li   t1, 0x10                # W1C ANACK -> drop irq_nack level
    sw   t1, 0(t0)
    li   t0, DONE_NACK
    li   t1, 0x00000089
    sw   t1, 0(t0)
    ret

    # ---- per-test IVT tail: arm 83/84/85 then slots 86 & 89 ---------------
    .section .ivt, "ax"
    .org 0x14C
    jal  zero, 0x0BB00           # 83 msip  -> park
    jal  zero, 0x0BB00           # 84 mtip  -> park
    jal  zero, 0x0B100           # 85 meip  -> env dispatcher (.isr_meip)
    jal  zero, i3c0_tc_h         # 86 (0x8158)
    .org 0x164
    jal  zero, i3c0_nack_h       # 89 (0x8164)
    .previous

    # ---- env meip dispatcher (.isr_meip @0xB100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END              # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
