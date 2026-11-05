// VestaRV RISCOF launcher and signature dumper, resident in hart 0's TCM.
//
// Hart 0 enters at 0x8200 from the bootrom, clear of the shared-RAM test body,
// so its polling fetches never touch the arbiter. It starts the test on
// vesta_target_hart, waits for the done mailbox, then reads the signature back
// through its own load path and streams it out on a0, the one register the chip
// exposes to the testbench. Layout of the stream (see sim/gen_tb.py):
//   MAGIC0 MAGIC1 MAGIC2  (word count)  then per word i:
//   0xA000_0000 | (i & 0xFFF) << 16 | low half
//   0xB000_0000 | (i & 0xFFF) << 16 | high half
//   and finally 0xCAFEBABE.
// Every value differs from its predecessor, so each is one a0 event and the
// bench can check the order. Only the tagged sequence after the magic is
// trusted: a0 carries arbitrary test data while a test runs on hart 0.

#define VESTA_DONE_ADDR 0x10010
#define VESTA_DONE_VAL  0x600DF00D
#define MB_BASE         0x10500      // bootrom loader rows {SRC,LEN,ENTRY}
#define MSIP_BASE       0x5000       // CLINT msip[h]
#define POLL_DELAY      200
#define TCM_SHADOW      0x1E000      // mk_rcf.py writes a copy of 0x8000.. here

    .option norvc
    .section .vesta_stub, "ax", @progbits
    .globl _start
_start:
    la   t0, vesta_target_hart
    lw   s1, 0(t0)
    la   s2, rvtest_entry_point
    bnez s1, launch_tile
    jr   s2                          // hart 0 is the target

launch_tile:
    slli t0, s1, 4
    li   t1, MB_BASE
    add  t0, t0, t1
    li   t1, TCM_SHADOW
    sw   t1, 0(t0)                   // SRC: shadow of this TCM image
    la   t1, vesta_tcm_end
    li   t2, 0x8000
    sub  t1, t1, t2
    srli t1, t1, 2
    sw   t1, 4(t0)                   // LEN: the tile copies it to its own TCM
    sw   s2, 8(t0)                   // ENTRY
    slli t0, s1, 2
    li   t1, MSIP_BASE
    add  t0, t0, t1
    li   t1, 1
    sw   t1, 0(t0)                   // ignite

    li   s3, VESTA_DONE_ADDR
    li   s4, VESTA_DONE_VAL
wait_done:
    li   t0, POLL_DELAY
1:  addi t0, t0, -1
    bnez t0, 1b
    lw   t1, 0(s3)
    bne  t1, s4, wait_done

    .globl vesta_dump
vesta_dump:
    la   s2, begin_signature
    la   s3, end_signature
    // Each stream value is written to a0 by exactly one instruction: a `li` of a
    // wide constant would put its lui half on the stream first.
    li   t0, 0x51C0DE00
    li   t1, 0x51C0DE01
    li   t2, 0x51C0DE02
    sub  t3, s3, s2
    srli t3, t3, 2                   // word count
    li   t4, 0xCAFEBABE
    mv   a0, t0
    mv   a0, t1
    mv   a0, t2
    mv   a0, t3
    li   s4, 0                       // word index
    li   s5, 0xA0000000
    li   s6, 0xB0000000
    li   s7, 0x0FFF0000
dump_loop:
    bgeu s2, s3, dump_end
    lw   t0, 0(s2)
    slli t1, s4, 16
    and  t1, t1, s7
    slli t2, t0, 16
    srli t2, t2, 16                  // low half
    or   t2, t2, t1
    or   t2, t2, s5
    srli t3, t0, 16                  // high half
    or   t3, t3, t1
    or   t3, t3, s6
    mv   a0, t2
    mv   a0, t3
    addi s2, s2, 4
    addi s4, s4, 1
    j    dump_loop
dump_end:
    mv   a0, t4
2:  j    2b

    .section .vesta_cfg, "a", @progbits
    .globl vesta_target_hart
vesta_target_hart:
    .word 0
