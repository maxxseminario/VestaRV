# See LICENSE for license details.

# VestaRV scar: a CSR read-modify-write under a stall returned the value it wrote
# The write repeated across the stall, so rd read back the new value. Myshkin hit it executing from flash.
# The checks run from shared RAM because the defect needs the core stalled on the CSR instruction; the TCM never stalls it, which makes the TCM case the control.
# ON-ONLY: mscratch exists only with the trap CSRs. An OFF build fails with t4 = 0.

#include "riscv_test.h"
#include "test_macros.h"
#include "scar.h"

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

#define SH_CODE    0x103C0
#define MSCRATCH   0x340

#ifdef CORE_ENABLE_TRAPCSR
    .option push
    .option arch, +zicsr

    li   t4, 1
    li   t1, 0x00ABCD00
    li   a3, 0x11110000
    csrw MSCRATCH, a3
    csrrw t2, MSCRATCH, t1
    bne  t2, a3, scar_fail

    # Six words of csr-then-return into shared RAM.
    la   a4, payload
    li   a5, SH_CODE
    li   a6, 6
copy:
    lw   a7, 0(a4)
    sw   a7, 0(a5)
    addi a4, a4, 4
    addi a5, a5, 4
    addi a6, a6, -1
    bnez a6, copy

    li   s2, SH_CODE
    li   t4, 2
    csrw MSCRATCH, a3
    li   t2, 0
    jalr ra, 0(s2)                  # csrrw t2, mscratch, t1
    bne  t2, a3, scar_fail
    li   t4, 3
    csrr a7, MSCRATCH
    bne  a7, t1, scar_fail

    li   t4, 4
    csrw MSCRATCH, a3
    li   t2, 0
    jalr ra, 8(s2)                  # csrrs t2, mscratch, t1
    bne  t2, a3, scar_fail
    li   t4, 5
    csrr a7, MSCRATCH
    or   a6, a3, t1
    bne  a7, a6, scar_fail

    li   t4, 6
    csrw MSCRATCH, a6
    li   t2, 0
    jalr ra, 16(s2)                 # csrrc t2, mscratch, t1
    bne  t2, a6, scar_fail

    RVTEST_PASS

    .align 2
payload:
    csrrw t2, MSCRATCH, t1
    jalr  x0, 0(ra)
    csrrs t2, MSCRATCH, t1
    jalr  x0, 0(ra)
    csrrc t2, MSCRATCH, t1
    jalr  x0, 0(ra)

    .option pop
#else
    li   t4, 0
    j    scar_fail
#endif

scar_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # RVTEST_CODE_END is unimp, which traps: never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
  TEST_DATA
RVTEST_DATA_END
