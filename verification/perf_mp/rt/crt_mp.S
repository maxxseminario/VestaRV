/* verification/perf_mp C-benchmark startup, one copy per hart class.
   Hart 0 enters from the boot ROM through the published BOOT_ENTRY_VEC, tiles from the ROM loader (ROM already copied
   their TCM image and the loader rows were written by the flash image). Every hart lands on _start in shared text.

   Run protocol: RUNMASK (word at 0x108F0) names the harts that run the benchmark. Hart 0 ignites the tiles in the mask;
   each hart raises READY[h]; hart 0 waits for all, then raises GO, so concurrent runs start within a few cycles.
   A finished hart writes DONE[h] = 1 + (main != 0) and pokes msip[0]; hart 0 waits in WFI with MIE clear, so waiting
   costs ZERO arbiter traffic. A tile then parks in extinguish for the same reason. */
    .equ RUNMASK, 0x108F0
    .equ READY,   0x1E000
    .equ GO,      0x1E040
    .equ DONE,    0x1E060
    .equ MSIP,    0x5000

    .section .text.init, "ax"
    .globl _start
_start:
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop
    la      sp, _stack_top
    csrr    s0, mhartid

#ifdef STACK_FILL
    /* high-water mark: paint the free TCM between .bss and sp */
    la      t0, __tcm_end
    li      t2, 0x5AFE5AFE
    addi    t1, sp, -64
3:  bgeu    t0, t1, 4f
    sw      t2, 0(t0)
    addi    t0, t0, 4
    j       3b
4:
#endif
    li      s1, RUNMASK
    lw      s1, 0(s1)
    bnez    s0, tile_side

    /* hart 0: clear the protocol words, ignite tiles */
    li      t0, READY
    li      t1, 0x80
5:  addi    t1, t1, -4
    add     t2, t0, t1
    sw      zero, 0(t2)
    bnez    t1, 5b
    li      t0, 1
6:  srl     t1, s1, t0
    andi    t1, t1, 1
    beqz    t1, 7f
    slli    t2, t0, 2
    li      t3, MSIP
    add     t2, t2, t3
    li      t3, 1
    sw      t3, 0(t2)
7:  addi    t0, t0, 1
    li      t1, 5
    bltu    t0, t1, 6b

    /* wait for every tile in the mask */
    li      t0, 1
8:  srl     t1, s1, t0
    andi    t1, t1, 1
    beqz    t1, 9f
    slli    t2, t0, 2
    li      t3, READY
    add     t2, t2, t3
10: lw      t3, 0(t2)
    beqz    t3, 10b
9:  addi    t0, t0, 1
    li      t1, 5
    bltu    t0, t1, 8b
    li      t0, GO
    li      t1, 1
    sw      t1, 0(t0)
    andi    t1, s1, 1
    beqz    t1, hart0_wait
    j       run

tile_side:
    slli    t0, s0, 2
    li      t1, READY
    add     t0, t0, t1
    li      t1, 1
    sw      t1, 0(t0)
    li      t0, GO
11: lw      t1, 0(t0)
    beqz    t1, 11b

run:
    /* After GO, so a tile's zeroing of its shared .shbss cannot race another tile's staged image. */
    la      t0, __bss_start
    la      t1, __bss_end
1:  bgeu    t0, t1, 2f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       1b
2:  la      t0, __shbss_start
    la      t1, __shbss_end
3:  bgeu    t0, t1, 4f
    sw      zero, 0(t0)
    addi    t0, t0, 4
    j       3b
4:
    li      a0, 0
    li      a1, 0
    call    main
    snez    a0, a0
    addi    a0, a0, 1
    slli    t0, s0, 2
    li      t1, DONE
    add     t0, t0, t1
    sw      a0, 0(t0)
    beqz    s0, hart0_wait
    li      t0, MSIP
    li      t1, 1
    sw      t1, 0(t0)
    li      a0, 0xCAFEBABE
12: .insn r 0x0b, 1, 0, x0, x0, x0
    j       12b

hart0_wait:
    /* standard mode, MSIE only, MIE clear: WFI resumes on the pending level and never traps */
    csrw    0x7C0, x0
    li      t0, 8
    csrw    0x304, t0
13: li      t0, MSIP
    sw      zero, 0(t0)
    li      s2, 0           /* failures */
    li      t0, 0
14: srl     t1, s1, t0
    andi    t1, t1, 1
    beqz    t1, 15f
    slli    t2, t0, 2
    li      t3, DONE
    add     t2, t2, t3
    lw      t3, 0(t2)
    beqz    t3, 16f
    addi    t3, t3, -1
    or      s2, s2, t3
15: addi    t0, t0, 1
    li      t1, 5
    bltu    t0, t1, 14b
    bnez    s2, fail
    li      a0, 0xCAFEBABE
    j       .
fail:
    li      a0, 0xDEADBEEF
    j       .
16: wfi
    j       13b
