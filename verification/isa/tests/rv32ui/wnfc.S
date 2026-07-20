# See LICENSE for license details.

#*****************************************************************************
# wnfc.S  (wound-config firmware smoke — FW-2)
#-----------------------------------------------------------------------------
# NFC0 @0x6200 register + AFS-routing + enable-word plumbing smoke. NO IRQ:
# the NFC protocol engine is clock-dead in sim (nfc0_rf_clk = tb '0', no
# carrier — MCU.vhd:3786), so it can raise no interrupt. Single-hart directed.
#
# Proves, beyond wperiph's single CR read:
#  * CR   reset AUTOREAD[12]=1 (0x1000)
#  * SR   reset STATE[11:8]=OFF (=0); whole SR reads 0 at reset
#  * UID  (0x6208) 32-bit write/readback
#  * CFG  (0x620C) reset 0x000044 (ATQA), then write/readback (masked 23:0)
#  * TIM  (0x6210) reset 0x088004D4 (SUBCDIV/ETU/FDT real grid), then write/readback
#  * TXCTL(0x6220) firmware-response path write/readback (masked 9:0; INERT MVP)
#  * P6AFS (0x642C) reset = P6.0 -> AF1 (0x1) — NFC rf_clk routing default
#  * HhENU bits 30/31 (NFC 94/95) + HhENX bits 0/1 (NFC 96/97) write/readback
#    — proves the 4th per-hart enable word (HhENX) and the U/X straddle plumbing
#    WITHOUT expecting delivery (PEND/INSVC RO words cover 0-95 only).
#
# SMCLK RULE: the bus/CDC ref is SMCLK-domain; write SYS_CLK_CR=0 first.
#*****************************************************************************

#include "riscv_test.h"
#include "test_macros.h"

#define SYS_CLK_CR  0x4900
#define NFC_CR      0x6200
#define NFC_SR      0x6204
#define NFC_UID     0x6208
#define NFC_CFG     0x620C
#define NFC_TIM     0x6210
#define NFC_TXCTL   0x6220
#define P6AFS       0x642C        /* GPIO5 base 0x6400 + RegSlotPxAFS(11)*4 */
#define IRTR_ENU    0x7008
#define IRTR_ENX    0x700C

RVTEST_RV32U
RVTEST_CODE_BEGIN

    # SMCLK -> HFXT (harmless for register-only, kept per the smclk rule)
    li   t0, SYS_CLK_CR
    sw   x0, 0(t0)

    # 1. CR reset AUTOREAD[12] = 1
    li   a0, NFC_CR
    lw   t0, 0(a0)
    li   t1, 0x00001000
    and  t0, t0, t1
    bne  t0, t1, wnfc_fail

    # 2. SR reset STATE = OFF (whole SR reads 0 at reset)
    li   a0, NFC_SR
    lw   t0, 0(a0)
    bnez t0, wnfc_fail

    # 3. UID 32-bit write/readback
    li   a0, NFC_UID
    li   t1, 0xDEADBEEF
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wnfc_fail

    # 4. CFG reset 0x000044, then write/readback (24-bit)
    li   a0, NFC_CFG
    lw   t0, 0(a0)
    li   t1, 0x00000044
    bne  t0, t1, wnfc_fail
    li   t1, 0x00A55A44          # SAK=0xA5, ATQA=0x5A44
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wnfc_fail

    # 5. TIM reset 0x088004D4, then write/readback (32-bit)
    li   a0, NFC_TIM
    lw   t0, 0(a0)
    li   t1, 0x088004D4
    bne  t0, t1, wnfc_fail
    li   t1, 0x02001014          # SUBCDIV=2, ETU=0x10, FDT=0x1014 (bench grid)
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wnfc_fail

    # 6. TXCTL write/readback (masked 9:0)
    li   a0, NFC_TXCTL
    li   t1, 0x00000155          # TXLEN=0x55, TXAPPCRC(9)=0, TXGO(8)=1
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wnfc_fail

    # 7. P6AFS reset: P6.0 = AF1 (0x1) — NFC rf_clk routing default
    li   a0, P6AFS
    lw   t0, 0(a0)
    li   t1, 0x00000001
    bne  t0, t1, wnfc_fail

    # 8. HhENU bits 30/31 (NFC 94/95) write/readback
    li   a0, IRTR_ENU
    li   t1, 0xC0000000
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wnfc_fail

    # 9. HhENX bits 0/1 (NFC 96/97) write/readback (word masked to 17:0)
    li   a0, IRTR_ENX
    li   t1, 0x00000003
    sw   t1, 0(a0)
    lw   t0, 0(a0)
    bne  t0, t1, wnfc_fail

    RVTEST_PASS

wnfc_fail:
    RVTEST_FAIL

    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
