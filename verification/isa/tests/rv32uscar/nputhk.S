# See LICENSE for license details.

# VestaRV scar: NPUTHINK always read 0
# The bit was missing from the NPUCR readback. On Myshkin that was harmless, because the CPU stops while the NPU runs; on Castalia it does not stop, and THINK is the completion signal.
# The run is made long enough to be seen: a one-neuron run ends before the first poll, and passes with the bit stuck at 0.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

#define NPU        0x4A00
#define NPUIVSAR   0x4
#define NPUWVSAR   0x8
#define NPUOVSAR   0xC
#define NPU_LONG   0x10000 | (0x3F << 8) | 0x0F     /* THINK, 64 inputs, 16 neurons */

    li   s2, NPU
    li   t0, 0x40
    sw   t0, NPUIVSAR(s2)
    li   t0, 0x100
    sw   t0, NPUWVSAR(s2)
    li   t0, 0x800
    sw   t0, NPUOVSAR(s2)

    li   t0, NPU_LONG
    sw   t0, 0(s2)

    # THINK reads back 1 while the run lasts.
    li   t4, 1
    li   t2, 64
    li   a1, 0
see_think:
    lw   t0, 0(s2)
    srli t0, t0, 16
    andi t0, t0, 1
    or   a1, a1, t0
    addi t2, t2, -1
    bnez t2, see_think
    beqz a1, scar_fail

    # And falls when the run ends.
    li   t4, 2
    li   t2, 200000
wait_done:
    addi t2, t2, -1
    beqz t2, scar_fail
    lw   t0, 0(s2)
    srli t0, t0, 16
    andi t0, t0, 1
    bnez t0, wait_done

    sw   zero, 0(s2)
    RVTEST_PASS

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
