# crt0.S -- VestaRV course SDK C runtime entry.
#
# Boot contract (see ~/vestarv/CLAUDE.md): every hart boots the shared ROM.
# Hart 0 copies this flash image to TCM 0x8000 and jumps to 0x8200; the other
# 17 harts park in WFI in the ROM until launched. So on a single-hart course
# lab only hart 0 ever reaches _start. We still gate on mhartid defensively.
#
# The build march is rv32ima (NO zicsr): every CSR access is wrapped in
# .option push / .option arch, +zicsr / .option pop.
#
# Layout (see course.ld): the 512-byte IVT lives at 0x8000-0x81FF, _start at
# 0x8200. flash_prepend.sh keys off exactly this layout (it zero-fills the
# 0x8000-0x81FF vector window and loads the program that follows).

# ---- Interrupt Vector Table region: 0x8000-0x81FF -------------------------
# 128 word slots. Course labs use no interrupts, so every slot is parked at 0.
# Having real bytes here is also what makes the emitted binary start at 0x8000
# (the address flash_prepend.sh assumes), not at _start's 0x8200.
    .section .ivt, "a", @progbits
    .p2align 2
__ivt:
    .rept 128
    .word 0
    .endr

# ---- Runtime entry: 0x8200 ------------------------------------------------
    .section .text.init, "ax", @progbits
    .p2align 2
    .globl _start
_start:
    # Defensive hart gate: only hart 0 runs a single-hart course lab. Any tile
    # that somehow arrives here just parks (the bootrom normally keeps them in
    # WFI). CSR read needs zicsr enabled explicitly.
    .option push
    .option arch, +zicsr
    csrr t0, mhartid
    .option pop
    bnez t0, park

    # global pointer (for -msmall-data / gp-relative relaxation); norelax so the
    # la itself is not relaxed away before gp is valid.
    .option push
    .option norelax
    la   gp, __global_pointer$
    .option pop

    # Stack: top of the private TCM. sp must be valid before any IRQ (the
    # IRQ_SV hardware push writes sp-4); course labs keep it at 0xBFF0.
    li   sp, 0xBFF0

    # Zero .bss (word loop; __bss_start/__bss_end are 4-aligned by course.ld).
    la   t0, __bss_start
    la   t1, __bss_end
1:
    bgeu t0, t1, 2f
    sw   zero, 0(t0)
    addi t0, t0, 4
    j    1b
2:

    # Course labs run in place in the TCM (LMA == VMA), so there is no .data to
    # relocate. Hand control to the student program.
    mv   a0, zero
    mv   a1, zero
    call main

    # main() returned. Never fall through (RVTEST_CODE_END / unimp traps): spin.
3:
    j    3b

park:
    .option push
    .option arch, +zicsr
    # nothing to do; loop (a stray tile should already be WFI-parked in ROM)
    .option pop
4:
    j    4b
