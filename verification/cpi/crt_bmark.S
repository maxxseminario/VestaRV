/* Bare-metal startup for the CPI benchmark harness.
   The core exports pass/fail only through x10 (a0), so main's return value is translated to the riscv-tests sentinels the testbench watches: 0 becomes 0xCAFEBABE, anything else 0xDEADBEEF.
   _start must land at 0x8200, which is the PC_RST_VAL the testbench gives the core; the link script pins .text.init there. */

/* The image must BEGIN at 0x8000, because rcf word 0 is memory[0x8000].
   Without an allocated section there, objcopy -O binary starts the file at .text.init and the whole image loads 0x200 bytes low.
   verification/isa's link.ld gets this for free from its real .ivt; this stub is the same trick with nothing in it. */
    .section ".ivt","a",@progbits
    .word 0

    .section ".text.init","ax",@progbits
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    la      sp, _stack_top

    /* Zero .bss before any C runs. */
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:

    li      a0, 0
    li      a1, 0
    call    main

    beqz    a0, pass
    li      a0, 0xDEADBEEF
    j       halt
pass:
    li      a0, 0xCAFEBABE
halt:
    j       halt
