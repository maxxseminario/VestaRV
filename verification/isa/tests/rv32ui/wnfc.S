# See LICENSE for license details.

# VestaRV: NFC0 register, pin-routing and enable-word smoke
# Hart 0 only. NFC0 sits at 0x6200. THERE IS NO INTERRUPT LEG, because the NFC protocol engine is clock-dead in simulation, its RF clock being tied low with no carrier, so it can raise nothing.
# It proves, beyond a single control-register read: CR's reset AUTOREAD bit; SR's reset state field reading OFF, with the whole register reading 0; a 32-bit write and readback of UID at 0x6208; CFG at 0x620C resetting to its ATQA value and then write and readback masked to bits 23:0; TIM at 0x6210 resetting to the real sub-carrier, ETU and frame-delay grid and then write and readback; TXCTL at 0x6220 write and readback masked to bits 9:0, the firmware-response path, which is inert in this version; and the pin alternate-function register resetting so the RF clock pin selects AF1.
# It also writes and reads back HhENU bits 30 and 31 and HhENX bits 0 and 1, the NFC sources 94 to 97, WHICH PROVES THE FOURTH PER-HART ENABLE WORD AND THE STRADDLE ACROSS THE TWO WORDS WITHOUT EXPECTING DELIVERY, since the pending and in-service read-only words cover sources 0 to 95 only.
# SMCLK RULE: the bus and CDC reference is smclk-domain, so SYS_CLK_CR must be zeroed first.

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
