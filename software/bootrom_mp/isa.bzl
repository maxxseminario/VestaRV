"""VestaRV: the single authority for the boot ROM's ISA string and its size-coupled flags.

The bench makefile and the hermetic BUILD.bazel both build this image and each used to carry
its own -march string. BUILD.bazel loads this as Starlark; the makefile reads the same two
assignments back with sed and errors out if it cannot. Keep both assignments on one line each
in exactly this form: the makefile's sed patterns are anchored to them.
"""

# The RISC-V ISA string the mask ROM is compiled and linked for.
# The C extension is a pure encoding change, adding no architectural state and
# no new arithmetic, so it is safe for all five harts that reset into this one
# ROM.
# Harts 1 through 4 are rv32iac: no M, no Zb*, and no Z-series extension at all.
# The generator publishes that as derived.hartClasses in
# config/ChipConfig.resolved.json and emits it as the TILE_ENABLE_* constants in
# MemoryMap.vhd, one per knob under isa.* and priv.*.
# This string must therefore stay free of any extension outside rv32iac. rv32ic is narrower still (the ROM needs no atomics), which is
# inside the tile subset rather than at it.
# //software/testtools:tile_isa_test grades the linked ELF against that subset,
# so a widened string here goes red before it reaches a tile.
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
