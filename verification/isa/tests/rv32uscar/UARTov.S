# See LICENSE for license details.

# VestaRV scar: the UART overflow flag was unreliable
# The receiver checked TCIF instead of its own receive flag, so OVF stayed clear on a real overrun and set falsely on a good byte.
# riscv_tb cross-wires UART0 and UART1 for an image named UART, so UART0 can receive without transmitting.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

#define SYS0    0x4900
#define GPIO1   0x4100
#define UART0   0x4400
#define UART1   0x4500
#define USR     0x4
#define URX     0xC
#define UTX     0x10
#define TCIF    1
#define RCIF    4
#define OVF     8

// Bounded poll on a status bit: a bench or clock fault fails, never hangs.
#define WAIT_BIT(id, base, bit, lbl)    \
    li   t4, id;                        \
    li   t2, 200000;                    \
lbl:                                    \
    addi t2, t2, -1;                    \
    beqz t2, scar_fail;                 \
    lw   t0, USR(base);                 \
    andi t0, t0, bit;                   \
    beqz t0, lbl

#define SETTLE(lbl, n)                  \
    li   t1, n;                         \
lbl:                                    \
    addi t1, t1, -1;                    \
    bnez t1, lbl

    li   s3, SYS0
    sw   zero, 0(s3)                    # SMCLK from HFXT
    li   s4, UART0
    li   s5, UART1
    li   s6, GPIO1
    li   t0, 0xF0
    sw   t0, 0x24(s6)                   # GPIO1 PxSEL: the UART pins
    li   t0, 1
    sw   t0, 8(s4)
    sw   t0, 8(s5)
    li   t0, 0x20
    sw   t0, 0(s4)
    sw   t0, 0(s5)
    li   t0, 3
    sw   t0, USR(s4)
    sw   t0, USR(s5)

    # A real overrun: two frames into UART0, the first left unread.
    li   t0, 0x5A
    sw   t0, UTX(s5)
    WAIT_BIT(1, s4, RCIF, w1)
    li   t0, 3
    sw   t0, USR(s5)
    li   t0, 0xA6
    sw   t0, UTX(s5)
    WAIT_BIT(2, s5, TCIF, w2)
    SETTLE(st1, 400)
    li   t4, 3
    lw   t0, USR(s4)
    andi t0, t0, OVF
    beqz t0, scar_fail
    lw   t0, URX(s4)

    # A false overrun: UART0 transmits and keeps TCIF, then receives one frame into an empty buffer.
    li   t0, 3
    sw   t0, USR(s4)
    li   t0, 0x33
    sw   t0, UTX(s4)
    WAIT_BIT(4, s4, TCIF, w4)
    SETTLE(st2, 400)
    lw   t0, URX(s5)
    li   t0, 0x44
    sw   t0, UTX(s5)
    WAIT_BIT(5, s4, RCIF, w5)
    SETTLE(st3, 40)
    li   t4, 6
    lw   t0, USR(s4)
    andi t0, t0, OVF
    bnez t0, scar_fail

    li   t4, 7                          # control: the byte arrived
    lw   t0, URX(s4)
    li   t1, 0x44
    bne  t0, t1, scar_fail

    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
