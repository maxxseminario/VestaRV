# Overlay BUILD file for @xpack_riscv_gcc (xPack riscv-none-elf-gcc 13.2.0-2).
# The firmware rules call gcc/objcopy/objdump directly (matching the
# makefiles they replace) rather than through a registered cc_toolchain, so
# this file only exposes filegroups.

package(default_visibility = ["//visibility:public"])

# Everything the compiler driver needs at runtime: the driver binaries, the
# internal tools (cc1, collect2, lto1), the target headers and multilibs, and
# the inner-triplet binutils that gcc invokes for assembling and linking.
# share/ (docs, locales) and the bundled gdb/python are excluded as dead
# weight for build actions.
filegroup(
    name = "toolchain",
    srcs = glob(
        [
            "bin/**",
            "lib/**",
            "lib64/**",
            "libexec/**",
            "riscv-none-elf/**",
        ],
        exclude = [
            "bin/riscv-none-elf-gdb*",
            "libexec/gcc/**/liblto_plugin.la",
        ],
    ),
)

filegroup(
    name = "gcc",
    srcs = ["bin/riscv-none-elf-gcc"],
)

filegroup(
    name = "objcopy",
    srcs = ["bin/riscv-none-elf-objcopy"],
)

filegroup(
    name = "objdump",
    srcs = ["bin/riscv-none-elf-objdump"],
)

filegroup(
    name = "size",
    srcs = ["bin/riscv-none-elf-size"],
)

filegroup(
    name = "as",
    srcs = ["bin/riscv-none-elf-as"],
)
