// VestaRV DUT model header for riscv-arch-test (RISCOF).
// The test body runs on ONE hart of the multi-hart chip (hart 0 or a tile),
// picked per image by the vesta_target_hart word in vesta_stub.S. The body is
// linked into shared bulk RAM so the same ELF runs unchanged on every hart.
#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#if XLEN == 64
  #define ALIGNMENT 3
#else
  #define ALIGNMENT 2
#endif

// Done mailbox in the bootrom-zeroed ledger; shared with vesta_stub.S.
#define VESTA_DONE_ADDR 0x10010
#define VESTA_DONE_VAL  0x600DF00D

// mtrapctl (custom CSR 0x7C0) resets LEGACY=1: IVT delivery with a terminal
// TRAP_STATE on exceptions. Standard mtvec delivery needs LEGACY=0.
// GPRs are zeroed because a tile enters from the bootrom loader with registers
// undefined, while the reference models start from zero.
#define RVMODEL_BOOT                                                     \
    csrwi 0x7C0, 0;                                                      \
    li x1, 0;  li x2, 0;  li x3, 0;  li x4, 0;  li x5, 0;  li x6, 0;     \
    li x7, 0;  li x8, 0;  li x9, 0;  li x10, 0; li x11, 0; li x12, 0;    \
    li x13, 0; li x14, 0; li x15, 0; li x16, 0; li x17, 0; li x18, 0;    \
    li x19, 0; li x20, 0; li x21, 0; li x22, 0; li x23, 0; li x24, 0;    \
    li x25, 0; li x26, 0; li x27, 0; li x28, 0; li x29, 0; li x30, 0;    \
    li x31, 0;

// Publish completion. Hart 0 then enters the dump itself; a tile sleeps with
// the custom extinguish so its spin does not load the arbiter during the dump.
#define RVMODEL_HALT                                                     \
    li   t0, VESTA_DONE_ADDR;                                            \
    li   t1, VESTA_DONE_VAL;                                             \
    sw   t1, 0(t0);                                                      \
    csrr t0, mhartid;                                                    \
    bnez t0, 88881f;                                                     \
    la   t0, vesta_dump;                                                 \
    jr   t0;                                                             \
88881:                                                                   \
    .insn r 0x0b, 1, 0, x0, x0, x0;                                      \
    j    88881b;

#define RVMODEL_DATA_BEGIN                                               \
    .align ALIGNMENT;                                                    \
    .global begin_signature; begin_signature:

#define RVMODEL_DATA_END                                                 \
    .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H
