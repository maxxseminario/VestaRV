# See LICENSE for license details.

# VestaRV: I3C0 interrupt-delivery smoke through the address-NACK path
# Hart 0 only, tiles parked. THE PINS ARE DELIBERATELY LEFT AT AF0, so sda_in and scl_in idle HIGH, meaning the bus is released, because MCU.vhd drives them to 1 when the alternate function is not selected. A launched SDR transfer to any address then samples the ACK bit high, which is a NACK, and that sets both the address-NACK flag and the transfer-complete flag together, so the transfer TERMINATES with two enabled interrupt sources: vector 86 from transfer-complete gated by TCIE, and vector 89 from the NACK gated by ERRIE. Both route through irq_router HhENU, meip, the MEIP_DISPATCHER and per-test IVT slots into plain-ret handlers that claim and complete, and the DONE check is order-independent.
# Register map: CR 0x6100 = I3CEN[0] BUSMODE[1] SDAPP[2] IBIEN[3] ODBR[15:8] PPBR[23:16] TCIE[24] ERRIE[25] DAAIE[26] IBIIE[27] RXFIE[28] TXEIE[29]; CMD 0x6104 = ADDR[6:0] RNW[7] REPSTART[8] STOPEN[9] and DLEN[23:16], with a lane-0 write launching the transfer; TX 0x6108; RX 0x610C; SR 0x6110 = BUSY[0] TCIF[1] RXFULL[2] TXEIF[3] ANACK[4] and the rest, all write-1-to-clear.
# Router row 0 uses HhENU at 0x7008, with source 86 at bit 22 and source 89 at bit 25. The IVT is a per-test tail that supersedes the env's meip arming: it arms slots 83, 84 and 85 and then places jumps into local plain-ret handlers at slots 86 and 89.
# SMCLK RULE: the serial core is smclk-domain, so SYS_CLK_CR must be zeroed first.

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
    jal  zero, 0x09100           # 85 meip  -> env dispatcher (.isr_meip)
    jal  zero, i3c0_tc_h         # 86 (0x8158)
    .org 0x164
    jal  zero, i3c0_nack_h       # 89 (0x8164)
    .previous

    # ---- env meip dispatcher (.isr_meip @0x9100) --------------------------
    MEIP_DISPATCHER()

    RVTEST_CODE_END              # unimp (traps) — never reached

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
