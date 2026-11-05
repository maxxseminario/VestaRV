// Directed check of the fixes the arch tests do not reach: misaligned LR, SC and AMO,
// compressed misaligned accesses, that a trapped access leaves rd and memory alone, and
// the xori and c.lui decode fixes. Every word is compared with Spike.
//
// The handler signs each trap with mcause and mtval as an offset from the data block, so
// the signature does not depend on where the two link maps put it. It steps over the
// instruction by its own length.
#include "model_test.h"

#define SENT 0x5A5A5A5A

// Run one faulting instruction with rd preloaded, then record rd.
#define FAULT(...)                                                       \
    li   a0, SENT;                                                       \
    __VA_ARGS__;                                                              \
    sw   a0, 0(s0);                                                      \
    addi s0, s0, 4;

    .section .text.init
    .globl rvtest_entry_point
rvtest_entry_point:
    RVMODEL_BOOT
    la   t0, handler
    csrw mtvec, t0
    la   s0, begin_signature
    la   s1, data_block

    // Controls: aligned word accesses do not trap.
    lw   a1, 0(s1)
    sw   a1, 0(s0)
    addi s0, s0, 4
    lr.w a1, (s1)
    sw   a1, 0(s0)
    addi s0, s0, 4
    li   a2, 1
    amoadd.w a1, a2, (s1)
    sw   a1, 0(s0)
    addi s0, s0, 4
    li   a2, -1
    amoadd.w a1, a2, (s1)

    // Plain 32-bit forms.
    FAULT(lw a0, 1(s1))
    FAULT(lw a0, 2(s1))
    FAULT(lw a0, 3(s1))
    FAULT(lh a0, 1(s1))
    FAULT(lh a0, 3(s1))
    FAULT(lhu a0, 1(s1))
    li   a2, 0x12345678
    FAULT(sw a2, 1(s1))
    FAULT(sw a2, 2(s1))
    FAULT(sh a2, 1(s1))
    FAULT(sh a2, 3(s1))

    // Byte accesses never trap, at any offset.
    lbu  a1, 1(s1)
    sw   a1, 0(s0)
    addi s0, s0, 4
    lbu  a1, 3(s1)
    sw   a1, 0(s0)
    addi s0, s0, 4

    // Atomics. s2 is the data block plus 1, s3 plus 2.
    addi s2, s1, 1
    addi s3, s1, 2
    FAULT(lr.w a0, (s2))
    FAULT(lr.w a0, (s3))
    FAULT(sc.w a0, a2, (s2))
    FAULT(amoadd.w a0, a2, (s2))
    FAULT(amoswap.w a0, a2, (s3))
    FAULT(amoor.w a0, a2, (s3))

    // Compressed forms, base register inside x8-x15.
    mv   a3, s2
    FAULT(c.lw a0, 0(a3))
    FAULT(c.sw a2, 0(a3))

    // A misaligned stack pointer through the sp-relative compressed forms.
    mv   s4, sp
    mv   sp, s3
    FAULT(c.lwsp a0, 0(sp))
    FAULT(c.swsp a2, 0(sp))
    mv   sp, s4

    // Memory untouched by every trapped store and AMO above.
    lw   a1, 0(s1)
    sw   a1, 0(s0)
    addi s0, s0, 4
    lw   a1, 4(s1)
    sw   a1, 0(s0)
    addi s0, s0, 4

    // xori with the immediate that used to decode as zext.h, then its neighbours.
    li   a1, 0xFFF7FFFF
    xori a4, a1, 0x80
    sw   a4, 0(s0)
    addi s0, s0, 4
    xori a4, a1, 0x7F
    sw   a4, 0(s0)
    addi s0, s0, 4
    xori a4, a1, 0x81
    sw   a4, 0(s0)
    addi s0, s0, 4

    // jalr clears bit 0 of its target. auipc then shows whether the PC stayed odd.
    la   a4, odd_target
    addi a4, a4, 1
    jalr a5, 0(a4)
    .align 2
odd_target:
    auipc a4, 0
    andi a4, a4, 3
    sw   a4, 0(s0)
    addi s0, s0, 4
    andi a5, a5, 1
    sw   a5, 0(s0)
    addi s0, s0, 4

    // c.lui x0 is a HINT: no trap, and no write to anything.
    csrr a4, mcause
    .option push
    .option norelax
    .hword 0x6005                       // c.lui x0, 1
    .hword 0x7FFD                       // c.lui x0, 0x1F (negative nzimm)
    .option pop
    csrr a5, mcause
    sub  a4, a5, a4
    sw   a4, 0(s0)
    addi s0, s0, 4
    RVMODEL_HALT

    .align 2
handler:
    csrr t0, mcause
    sw   t0, 0(s0)
    csrr t0, mtval
    sub  t0, t0, s1
    sw   t0, 4(s0)
    addi s0, s0, 8
    csrr t0, mepc
    lhu  t1, 0(t0)
    andi t1, t1, 3
    li   t2, 3
    bne  t1, t2, 1f
    addi t0, t0, 2
1:  addi t0, t0, 2
    csrw mepc, t0
    mret

    .data
    .align 4
data_block:
    .word 0x11223344, 0x55667788, 0, 0

RVMODEL_DATA_BEGIN
    .fill 96, 4, 0xdeadbeef
RVMODEL_DATA_END
