# See LICENSE for license details.

# VestaRV: directed detectors for the five core defects fixed in 952c06ea
# Hart 0 only, tiles parked. One check per defect, each with a control, so a regression names itself through t4:
#   1-3    xori with immediate 0x80 decoded as zext.h
#   4-6    jalr left bit 0 of the target set
#   7-9    c.lui x0, nzimm trapped instead of retiring as a HINT
#   10-27  misaligned data access did not trap with cause 4 or 6 and mtval = address
#   28-33  a CSR read-modify-write repeated across a stall, so rd read back the new value
# The CSR checks run from shared RAM because the defect needs the core stalled on the CSR instruction; the TCM never stalls it.
# ON-ONLY: needs standard trap delivery, so the row carries trapCsr. An OFF build fails immediately with t4 = 0.

#include "riscv_test.h"
#include "test_macros.h"

#define SH_CODE    0x103C0
#define MSCRATCH   0x340

# One misaligned access. It must trap once, with this cause, at this pc, reporting this address.
#define MA_TRAP(id, cause, addr_reg, ...)   \
    li   t4, id;                            \
    la   s0, 9f;                            \
    addi s8, s8, 1;                         \
9:  __VA_ARGS__;                            \
    bne  s3, s8, cf_fail;                   \
    li   t3, cause;                         \
    bne  s4, t3, cf_fail;                   \
    bne  s5, s0, cf_fail;                   \
    bne  s7, addr_reg, cf_fail

.option norvc
.option norelax

RVTEST_RV32U
RVTEST_CODE_BEGIN

    li   t0, 1234
    li   t1, 4321
    add  t2, t0, t1
    li   t3, 5555
    bne  t2, t3, cf_fail

#ifdef CORE_ENABLE_TRAPCSR

    .option push
    .option arch, +zicsr

    li   sp, 0xBFF0
    li   s3, 0                      # traps taken
    li   s8, 0                      # traps expected
    li   s6, 4                      # bytes the handler skips

    # Standard delivery: mtvec first, then clear mtrapctl.LEGACY.
    la   t0, cf_handler
    csrw 0x305, t0
    csrw 0x304, x0
    csrw 0x300, x0
    csrw 0x7C0, x0

    # ---- xori: 0x81 is the control, 0x80 is the encoding zext.h claimed ----
    li   t4, 1
    li   a1, 0xFFF7FFFF
    xori a2, a1, 0x81
    li   a3, 0xFFF7FF7E
    bne  a2, a3, cf_fail
    li   t4, 2
    xori a2, a1, 0x80
    li   a3, 0xFFF7FF7F
    bne  a2, a3, cf_fail
    li   t4, 3
    li   a1, 0x12345678
    xori a2, a1, 0x80
    li   a3, 0x123456F8
    bne  a2, a3, cf_fail

    # ---- jalr: bit 0 of the target is cleared, whichever operand set it ----
    li   t4, 4
    la   a4, cf_jt1
    addi a4, a4, 1
    jalr a5, 0(a4)
cf_ret1:
    j    cf_fail
    .align 2
cf_jt1:
    auipc a6, 0
    andi a7, a6, 3
    bnez a7, cf_fail
    li   t4, 5
    la   a6, cf_ret1                # the link is the return address, not the target
    bne  a5, a6, cf_fail
    li   t4, 6
    la   a4, cf_jt2
    jalr a5, 1(a4)
    j    cf_fail
    .align 2
cf_jt2:
    auipc a6, 0
    andi a7, a6, 3
    bnez a7, cf_fail
    la   a4, cf_jt2_done            # leave on a clean PC
    jr   a4
    .align 2
cf_jt2_done:

    # ---- c.lui x0, nzimm is a HINT; nzimm = 0 stays reserved ----
    li   s6, 2
    li   t4, 7
    li   a1, 0x55
    .2byte 0x6005                   # c.lui x0, 1
    .2byte 0x0001                   # c.nop
    bne  s3, s8, cf_fail
    li   t4, 8
    li   a2, 0x55
    bne  a1, a2, cf_fail
    li   t4, 9
    addi s8, s8, 1
    .2byte 0x6001                   # c.lui x0, 0: reserved, must trap
    .2byte 0x0001
    bne  s3, s8, cf_fail
    li   t3, 2
    bne  s4, t3, cf_fail
    li   s6, 4

    # ---- misaligned data. Aligned and byte accesses are the controls. ----
    la   s1, cf_data
    li   t4, 10
    lw   a2, 0(s1)
    li   a3, 0x11223344
    bne  a2, a3, cf_fail
    lbu  a2, 1(s1)
    li   a3, 0x33
    bne  a2, a3, cf_fail
    lhu  a2, 2(s1)
    li   a3, 0x1122
    bne  a2, a3, cf_fail
    bne  s3, s8, cf_fail

    li   a2, 0x0BADF00D             # a trapped load must leave rd alone
    addi s2, s1, 1
    MA_TRAP(11, 4, s2, lw a2, 1(s1))
    addi s2, s1, 2
    MA_TRAP(12, 4, s2, lw a2, 2(s1))
    addi s2, s1, 3
    MA_TRAP(13, 4, s2, lw a2, 3(s1))
    addi s2, s1, 1
    MA_TRAP(14, 4, s2, lh a2, 1(s1))
    addi s2, s1, 3
    MA_TRAP(15, 4, s2, lhu a2, 3(s1))
    li   t4, 16
    li   a3, 0x0BADF00D
    bne  a2, a3, cf_fail

    li   a3, 0xAABBCCDD
    addi s1, s1, 8                  # the zeroed words
    addi s2, s1, 1
    MA_TRAP(17, 6, s2, sw a3, 1(s1))
    addi s2, s1, 2
    MA_TRAP(18, 6, s2, sw a3, 2(s1))
    addi s2, s1, 3
    MA_TRAP(19, 6, s2, sw a3, 3(s1))
    addi s2, s1, 1
    MA_TRAP(20, 6, s2, sh a3, 1(s1))
    addi s2, s1, 3
    MA_TRAP(21, 6, s2, sh a3, 3(s1))
    li   t4, 22                     # a trapped store writes nothing
    lw   a2, 0(s1)
    bnez a2, cf_fail
    li   t4, 23
    lw   a2, 4(s1)
    bnez a2, cf_fail

    addi s2, s1, 2
    MA_TRAP(24, 4, s2, lr.w a2, (s2))
    MA_TRAP(25, 6, s2, sc.w a2, a3, (s2))
    MA_TRAP(26, 6, s2, amoadd.w a2, a3, (s2))
    li   t4, 27
    lw   a2, 0(s1)
    bnez a2, cf_fail

    # ---- CSR read-modify-write. TCM first as the control, then stalled. ----
    li   t4, 28
    li   t1, 0x00ABCD00
    li   a3, 0x11110000
    csrw MSCRATCH, a3
    csrrw t2, MSCRATCH, t1
    bne  t2, a3, cf_fail

    # Copy the payload into shared RAM, six words of csr-then-return.
    la   a4, cf_payload
    li   a5, SH_CODE
    li   a6, 6
cf_copy:
    lw   a7, 0(a4)
    sw   a7, 0(a5)
    addi a4, a4, 4
    addi a5, a5, 4
    addi a6, a6, -1
    bnez a6, cf_copy

    li   s2, SH_CODE
    li   t4, 29
    csrw MSCRATCH, a3
    li   t2, 0
    jalr ra, 0(s2)                  # csrrw t2, mscratch, t1
    bne  t2, a3, cf_fail
    li   t4, 30
    csrr a7, MSCRATCH
    bne  a7, t1, cf_fail

    li   t4, 31
    csrw MSCRATCH, a3
    li   t2, 0
    jalr ra, 8(s2)                  # csrrs t2, mscratch, t1
    bne  t2, a3, cf_fail
    li   t4, 32
    csrr a7, MSCRATCH
    or   a6, a3, t1
    bne  a7, a6, cf_fail

    li   t4, 33
    csrw MSCRATCH, a6
    li   t2, 0
    jalr ra, 16(s2)                 # csrrc t2, mscratch, t1
    bne  t2, a6, cf_fail

    # Back to legacy delivery, as the environment left it.
    li   t0, 1
    csrw 0x7C0, t0
    csrw 0x300, x0
    csrw 0x305, x0

    RVTEST_PASS

    # Reached only by a hardware trap, never by fall-through.
    .align 2
cf_handler:
    csrr s4, 0x342                  # mcause
    csrr s5, 0x341                  # mepc
    csrr s7, 0x343                  # mtval
    addi s3, s3, 1
    add  t5, s5, s6
    csrw 0x341, t5
    mret

    .align 2
cf_payload:
    csrrw t2, MSCRATCH, t1
    jalr  x0, 0(ra)
    csrrs t2, MSCRATCH, t1
    jalr  x0, 0(ra)
    csrrc t2, MSCRATCH, t1
    jalr  x0, 0(ra)

    .option pop

#else
    li   t4, 0
    j    cf_fail
#endif

cf_fail:
    RVTEST_FAIL                     # a0 = 0xDEADBEEF, t4 = failing check

    # NOTE: RVTEST_CODE_END is 'unimp' (traps!) in this env, never fall through.
    RVTEST_CODE_END

  .data
RVTEST_DATA_BEGIN
    .align 3
cf_data:
    .word 0x11223344
    .word 0x55667788
    .word 0
    .word 0
  TEST_DATA
RVTEST_DATA_END
