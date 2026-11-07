// Shared plumbing for the rv32uscar tests. See README.md.
// A failing test stops with a0 = 0xDEADBEEF and the failing check id in t4.
#ifndef SCAR_H
#define SCAR_H

// Standard trap delivery: mtvec first, then clear mtrapctl.LEGACY. Needs -DCORE_ENABLE_TRAPCSR.
// s3 counts traps taken, s4 mcause, s5 mepc, s7 mtval, s6 the bytes the handler skips.
#define SCAR_TRAPS_ON(handler)  \
    li   s3, 0;                 \
    li   s6, 4;                 \
    la   t0, handler;           \
    csrw 0x305, t0;             \
    csrw 0x304, x0;             \
    csrw 0x300, x0;             \
    csrw 0x7C0, x0

// Back to legacy delivery, as the environment left it.
#define SCAR_TRAPS_OFF          \
    li   t0, 1;                 \
    csrw 0x7C0, t0;             \
    csrw 0x300, x0;             \
    csrw 0x305, x0

// Place after RVTEST_PASS, so only a hardware trap reaches it.
#define SCAR_HANDLER(handler)   \
    .align 2;                   \
handler:                        \
    csrr s4, 0x342;             \
    csrr s5, 0x341;             \
    csrr s7, 0x343;             \
    addi s3, s3, 1;             \
    add  t5, s5, s6;            \
    csrw 0x341, t5;             \
    mret

#endif
