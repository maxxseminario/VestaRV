// Minimal reproduction: a CSR read-modify-write returns the POST-write value when
// the fetch of the next instruction stalls on the arbiter.
//
// The same three instructions run twice, once fetched from TCM and once from shared
// bulk RAM, and every rd and CSR result goes into the signature. Spike gives the
// architectural answer for both. Build it like an arch test (see README.md).
#include "model_test.h"

#define PROBE(tag)                                                       \
    li   t0, 0x00005678;                                                 \
    csrw mscratch, t0;                                                   \
    li   t1, 0x00001234;                                                 \
    csrrw t2, mscratch, t1;             /* rd must read 0x5678 */        \
    sw   t2, 0(s0);                                                      \
    csrr t3, mscratch;                  /* must read 0x1234 */           \
    sw   t3, 4(s0);                                                      \
    li   t0, 0x00005678;                                                 \
    csrw mscratch, t0;                                                   \
    csrrs t2, mscratch, t1;             /* rd must read 0x5678 */        \
    sw   t2, 8(s0);                                                      \
    csrr t3, mscratch;                  /* must read 0x567C */           \
    sw   t3, 12(s0);                                                     \
    li   t0, 0x00005678;                                                 \
    csrw mscratch, t0;                                                   \
    csrrc t2, mscratch, t1;             /* rd must read 0x5678 */        \
    sw   t2, 16(s0);                                                     \
    csrr t3, mscratch;                  /* must read 0x4448 */           \
    sw   t3, 20(s0);                                                     \
    addi s0, s0, 24;

    .section .text.init
    .globl rvtest_entry_point
rvtest_entry_point:
    RVMODEL_BOOT
    la   s0, begin_signature
    la   ra, 1f
    la   t0, tcm_probe
    jr   t0                             // first probe, fetched from TCM
1:
    PROBE(shared)                       // second probe, fetched from shared RAM
    RVMODEL_HALT

    .pushsection .vesta_tcm_text, "ax", @progbits
tcm_probe:
    PROBE(tcm)
    ret
    .popsection

    .data
    .align 4
RVMODEL_DATA_BEGIN
    .fill 12, 4, 0xdeadbeef
RVMODEL_DATA_END
