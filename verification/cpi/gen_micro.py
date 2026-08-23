#!/usr/bin/env python3
"""Emit the per-instruction-class micro-kernels of the CPI harness.

Each kernel runs ITERS passes over a loop body holding NOPS copies of the
instruction under test, with the setStats() window opened around the whole
loop. Running the same kernel at NOPS>0 and at NOPS=0 and subtracting removes
the loop's own decrement and backward branch, so what is left is the marginal
cost of the NOPS copies alone: delta-cycles / delta-instructions is
cycles-per-instruction for that class, undiluted by the loop.

The operands are chosen so that no kernel is a dependency chain, because what
is being measured is issue cost on this core rather than a scheduling effect.

WORD ALIGNMENT IS LOAD BEARING. Every loop body starts with `.p2align 2`. The
core fetches one 32-bit word per bus cycle, so a 32-bit instruction that
straddles a word boundary takes the split-fetch path and costs one extra
cycle. Without the directive the body can land on a 2-byte boundary and EVERY
32-bit instruction in it pays that penalty, which silently doubles the
measured cost of whatever is under test (measured: the first cut of the
control-transfer kernels read 2.0 cycles for a taken branch purely from this).
The straddling-fetch cost is measured on its own, by the RV32IMAC-versus-
RV32IMA benchmark pair and by the two STRADDLE_BODIES kernels, and must not be
charged to the instruction class here.

THE TWO STRADDLE KERNELS ARE THE DELIBERATE EXCEPTION. straddleseq and
straddlebr are built to straddle, because with the fetch-ahead shipped the
straddling penalty is no longer a single number and the TRM has to state the
two cases separately. Their `.p2align 2` is doing the opposite job: it fixes
the block's base so that the offsets INSIDE it, and therefore which member
straddles, are exact rather than a property of wherever the assembler happened
to place the loop.

Usage: gen_micro.py <outdir>
"""

import os
import sys

# ITERS is per kernel so that the two 36-cycle classes do not dominate the
# runtime of the default test set. Everything else runs at the same 2000, and
# the delta-instruction count of a pair is then always 64 * ITERS, which is
# the self-check the analysis applies.
DEFAULT_ITERS = 2000
DIVIDER_ITERS = 250

NOPS = 64

# One instruction per entry, so delta-instructions is exactly NOPS * ITERS.
#
# DELIBERATELY ABSENT, and not a silent drop: the first cut of this generator
# also carried `br_t` (beq to .+4) and `jal` (jal x0, .+4). Both are taken
# transfers architecturally, but .+4 IS the fall-through address, so the next
# fetch address is the same either way and neither kernel exercised the
# redirect path at all. They are superseded by the REDIRECT bodies below,
# whose targets skip an instruction that consequently never retires.
SINGLE_OPS = {
    "alu32": "add  a4, a1, a2",
    "alu16": "c.add a4, a1",
    "lw": "lw   a4, 0(s0)",
    "sw": "sw   a4, 0(s0)",
    "lb": "lb   a4, 0(s0)",
    "sb": "sb   a4, 0(s0)",
    "mul": "mul  a4, a1, a2",
    "div": "div  a4, a1, a2",
    "rem": "rem  a4, a1, a2",
    "br_nt": "beq  a1, a2, 9f",
    "csrr": "csrr a4, mcycle",
    "shift": "sll  a4, a1, a2",
    "zbb": "andn a4, a1, a2",
}

# Control transfers whose target genuinely differs from PC+4. The skipped
# `add` never retires, which is what makes these a real redirect measurement.
REDIRECT_BODIES = {
    "brtaken": "    beq     a1, a1, 8f\n    add     a4, a1, a2\n8:",
    "jaltaken": "    jal     x0, 8f\n    add     a4, a1, a2\n8:",
    "jalrtaken": "    la      a5, 8f\n    jalr    x0, 0(a5)\n    add     a4, a1, a2\n8:",
    "brnotaken": "    bne     a1, a1, 8f\n    add     a4, a1, a2\n8:",
}

# The two kernels that straddle ON PURPOSE, and the only ones that do.
#
# Everything above is word-aligned so that no class is charged a fetch cost
# that is not its own. These two exist to measure that cost directly, because
# with ENABLE_IF_AHEAD shipped it is no longer one number: a straddling 32-bit
# instruction reached SEQUENTIALLY is absorbed by the fetch-ahead, and one
# reached by a TAKEN control transfer is not, since the fetch-ahead arms only
# on a sequential advance and a redirect leaves the core holding nothing.
#
# Both blocks are 12 bytes long and start word-aligned, so `.p2align 2` at the
# top of the body fixes every offset inside them and the repetition is exact.
#
# straddleseq: c.add at +0, add at +2 (straddles +4), add at +6 (straddles
# +8), c.add at +10. Four instructions, both 32-bit ones straddling, every one
# of them reached by a sequential advance. The whole block is the measurement:
# 1.000 cycles per instruction means the straddles cost nothing.
#
# straddlebr: beq at +0 jumping over the c.add at +4 to land on the add at +6,
# which straddles +8, with a c.add at +10 to return the next block to a word
# boundary. Three instructions retire. Each costs one cycle on its own --- the
# taken branch by the brtaken kernel, the add by alu32, the c.add by alu16 ---
# so the block would cost 3 cycles if the redirect target were aligned, and
# what it measures above 3 is the residual straddling penalty.
STRADDLE_BODIES = {
    "straddleseq": (
        "    c.add   a4, a1\n"
        "    add     a5, a1, a2\n"
        "    add     a5, a1, a2\n"
        "    c.add   a4, a1"
    ),
    "straddlebr": (
        "    beq     a1, a1, 8f\n"
        "    c.add   a4, a1\n"
        "8:  add     a5, a1, a2\n"
        "    c.add   a4, a1"
    ),
}

# Linearity control: the same body at two NOPS counts. Their difference must
# be exactly (32 - 16) * ITERS cycles for a one-cycle class, which proves the
# residual left in a NOPS/0 pair is per-iteration loop overhead and not a
# per-op cost that the subtraction failed to remove.
LINEARITY_NOPS = (32, 16)

_PROLOGUE = """/* Auto-generated by verification/cpi/gen_micro.py.
   Micro-kernel "{name}", NOPS={nops}, ITERS={iters}.
   Pair this with the NOPS=0 kernel of the same class and subtract to get the
   marginal cycles and instructions of the instruction under test. */

    /* The image must BEGIN at 0x8000, because rcf word 0 is memory[0x8000].
       Without an allocated section there, objcopy -O binary starts the file
       at .text.init and the whole image loads 0x200 bytes low. */
    .section ".ivt","a",@progbits
    .word 0

    .section ".text.init","ax",@progbits
    .globl _start
_start:
    la      sp, _stack_top
    la      s0, scratch

    li      a1, 3
    li      a2, 5
    li      a3, 7
    li      a4, 0
    li      t1, 0x4000          /* setStats() port the testbench decodes */

    li      s1, {iters}
    li      t2, 1
    sw      t2, 0(t1)           /* open the measured window */

1:
    /* Word-align the body. An unaligned body puts every 32-bit instruction on
       the split-fetch path at +1 cycle each, and that cost would be charged
       to the class under test. See the module docstring. */
    .p2align 2
"""

_EPILOGUE = """    .endr
9:
    addi    s1, s1, -1
    /* The loop's OWN backward branch has to be word aligned for the same
       reason the body does. A body of 64 four-byte instructions puts the
       branch target out of c.bnez's +/- 256 byte reach, so the assembler
       widens it to a 32-bit bne; landing that at a 2-byte offset puts the
       loop control itself on the split-fetch path and charges one extra
       cycle per iteration to the class under test. The pad instruction
       retires in both members of a pair, so it subtracts out. */
    .p2align 2
    bnez    s1, 1b

    li      t2, 2
    sw      t2, 0(t1)           /* close the measured window */

    li      a0, 0xCAFEBABE
2:  j       2b

    .section ".bss"
    .align  4
scratch:
    .space  256
"""


def _kernel(name, body, nops, iters):
    return (
        _PROLOGUE.format(name=name, nops=nops, iters=iters)
        + "    .rept %d\n" % nops
        + body
        + "\n"
        + _EPILOGUE
    )


def kernel_sources():
    """Return {basename: assembly text} for every micro-kernel."""
    out = {}
    for name, op in SINGLE_OPS.items():
        iters = DIVIDER_ITERS if name in ("div", "rem") else DEFAULT_ITERS
        for nops in (NOPS, 0):
            out["micro_%s_%d" % (name, nops)] = _kernel(
                name, "    " + op, nops, iters
            )
    for name, body in REDIRECT_BODIES.items():
        for nops in (NOPS, 0):
            out["micro_%s_%d" % (name, nops)] = _kernel(
                name, body, nops, DEFAULT_ITERS
            )
    for name, body in STRADDLE_BODIES.items():
        for nops in (NOPS, 0):
            out["micro_%s_%d" % (name, nops)] = _kernel(
                name, body, nops, DEFAULT_ITERS
            )
    for nops in LINEARITY_NOPS:
        out["micro_alu32lin_%d" % nops] = _kernel(
            "alu32lin", "    add     a4, a1, a2", nops, DEFAULT_ITERS
        )
    return out


def main():
    outdir = sys.argv[1]
    os.makedirs(outdir, exist_ok=True)
    for base, text in sorted(kernel_sources().items()):
        with open(os.path.join(outdir, base + ".S"), "w", newline="\n") as f:
            f.write(text)


if __name__ == "__main__":
    main()
