"""Single authority for the boot ROM's ISA string and its size-coupled flags.

Two independent build paths produce this image.
software/bootrom_mp/makefile is the bench recipe.
software/bootrom_mp/BUILD.bazel is the hermetic one.
Each used to carry its own copy of the -march string, so flipping one left the
other silently compiling a different instruction set while every gate stayed
green.

This file is that string, once.
BUILD.bazel loads it as Starlark.
The makefile reads the same two assignments back out with sed, and errors out
if it cannot, so there is no path where one side quietly keeps the old ISA.

Keep the two assignments below on one line each, in exactly this form.
The makefile's sed patterns are anchored to them.
"""

# The RISC-V ISA string the mask ROM is compiled and linked for.
# 2026-08-23: rv32i became rv32ic.
# The C extension is a pure encoding change, adding no architectural state and
# no new arithmetic, so it is safe for all five harts that reset into this one
# ROM.
# Harts 1 through 4 are rv32iac and lack M, DIV and Zb* (MemoryMap.vhd:1232),
# which is why this string must stay free of any extension that would emit
# those instructions.
BOOTROM_MARCH = "rv32ic"

# Compile and link flags that live here because they exist for image-size
# reasons and must be identical on both build paths.
# -fno-tree-loop-distribute-patterns declines gcc's transform of ordinary loops
# in rv4th.c into calls to memset and memmove.
# Neither routine is called by name anywhere in this program, so declining the
# transform is behaviour-preserving by construction and drops the libgcc string
# routines out of the image.
# The flag has to appear on the link line as well as the compile line, because
# with -flto the loop passes run during link-time codegen.
BOOTROM_SIZE_COPTS = ["-fno-tree-loop-distribute-patterns"]
