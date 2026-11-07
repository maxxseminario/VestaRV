# See LICENSE for license details.

# VestaRV scar: the watchdog never fired
# The edge detector refreshed its previous value before comparing, so prev always equalled current and the flag never set.
# On this chip a timeout with IE set and no routed interrupt resets the chip, so the test runs twice. The first pass arms the watchdog and waits; the reset re-boots into the same image; the second pass finds WDTRF set, which only power-on reset clears, and passes.
# With the defect nothing fires and the first pass runs out of time at check 2. The running counter is the control: it worked on Myshkin too.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

#define SYS0        0x4900
#define WDT_UNLOCK  0x5f3759df
#define WDTPASS     0x30
#define WDTCR       0x34
#define WDTSR       0x38
#define WDTVAL      0x3C
#define WDTRF       1
#define WDT_ARM     0x9A            /* EN, divider 6, IE: unrouted, so a timeout resets */

    li   s3, SYS0
    lw   t0, WDTSR(s3)
    andi t0, t0, WDTRF
    bnez t0, fired                  # the second pass

    sw   zero, 0(s3)                # SMCLK from HFXT: the boot ROM leaves it on LFXT
    li   t0, WDT_UNLOCK
    sw   t0, WDTPASS(s3)
    li   t0, WDT_ARM
    sw   t0, WDTCR(s3)

    li   t4, 1
    li   t1, 8
spin:
    addi t1, t1, -1
    bnez t1, spin
    lw   t0, WDTVAL(s3)
    beqz t0, scar_fail              # the counter runs

    li   t4, 2
    li   t1, 20000
wait_wdt:
    addi t1, t1, -1
    bnez t1, wait_wdt
    li   t0, WDT_UNLOCK             # still here: it never fired
    sw   t0, WDTPASS(s3)
    sw   zero, WDTCR(s3)
    j    scar_fail

fired:
    li   t0, WDTRF
    sw   t0, WDTSR(s3)              # W1C
    li   t4, 3
    lw   t0, WDTSR(s3)
    andi t0, t0, WDTRF
    bnez t0, scar_fail

    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
