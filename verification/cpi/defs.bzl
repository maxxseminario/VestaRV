"""VestaRV: bazel rules for the verification/cpi measurement harness.

Images are built by the same pipeline and pinned toolchain //verification/isa uses, with the
march, mabi, options and linker script all arguments of the compile action: a CPI number is
worth recording only if its image is reproducible bit for bit. The RAM window, load offset and
word count are the ISA harness's, so the numbers describe the core, not a new memory model.
"""

load("@rules_python//python:defs.bzl", "py_test")

# The testbench's flat RAM window, matching verification/isa/defs.bzl.
MEM_SIZE_BYTES = 0x14000

IMAGE_WORDS = MEM_SIZE_BYTES // 4

_TOOLCHAIN = "@xpack_riscv_gcc//:toolchain"

# The Castalia default polarity, which is what the TRM documents.
# Zicsr is explicit because the micro-kernels read mcycle.
MARCH_C = "rv32imac_zicsr_zba_zbb_zbc_zbs"

# The same architecture with the C extension removed. gcc emits the identical
# instruction sequence for both, so the cycle difference between a pair of
# images is the straddling-fetch penalty and nothing else.
MARCH_NOC = "rv32ima_zicsr_zba_zbb_zbc_zbs"

_LD = "link_bmark.ld"

_BASE_OPTS = [
    "-mabi=ilp32",
    "-mcmodel=medany",
    "-nostdlib",
    "-nostartfiles",
]

# build_bmark.sh's option list, which is the riscv-tests benchmark Makefile's
# own set. -O2 is load bearing: the published CPI is for optimised code.
_BMARK_OPTS = [
    "-DPREALLOCATE=1",
    "-static",
    "-std=gnu99",
    "-O2",
    "-ffast-math",
    "-fno-common",
    "-fno-builtin-printf",
    "-fno-tree-loop-distribute-patterns",
    "-Wno-implicit-int",
    "-Wno-implicit-function-declaration",
]

_BMARK_INCLUDES = [
    "verification/env",
    "verification/benchmarks/common",
]

def _rcf_rules(name, elf, tags, visibility):
    """objcopy the ELF, pad it to the RAM window, and convert it to .rcf."""
    binary = name + ".bin"
    padded = name + "_padded.bin"
    rcf = name + ".rcf"

    native.genrule(
        name = name + "_rcf",
        srcs = [elf],
        outs = [binary, padded, rcf],
        cmd = "\n".join([
            "$(location @xpack_riscv_gcc//:objcopy) -O binary --gap-fill=0x00 $(location %s) $(location %s)" % (elf, binary),
            "sz=$$(wc -c < $(location %s))" % binary,
            "if [ $$sz -gt %d ]; then" % MEM_SIZE_BYTES,
            "  echo \"$(location %s): $$sz bytes does not fit the %d byte RAM window\" >&2" % (binary, MEM_SIZE_BYTES),
            "  exit 1",
            "fi",
            "dd if=/dev/zero of=$(location %s) bs=%d count=1 2>/dev/null" % (padded, MEM_SIZE_BYTES),
            "dd if=$(location %s) of=$(location %s) bs=1 conv=notrunc 2>/dev/null" % (binary, padded),
            "$(location //tools/build:bin2rcf) $(location %s) $(location %s) --expect-words %d" % (padded, rcf, IMAGE_WORDS),
        ]),
        tags = tags,
        tools = [
            "@xpack_riscv_gcc//:objcopy",
            _TOOLCHAIN,
            "//tools/build:bin2rcf",
        ],
        visibility = visibility,
    )
    return rcf

def cpi_micro_image(name, march = MARCH_C, tags = [], visibility = None):
    """Assemble one generated micro-kernel .S into a .rcf image and return its file name. `name` is
    the kernel base name, whose .S must be produced by the :micro_sources genrule.
    """
    elf = name + ".elf"
    src = "micro/" + name + ".S"

    native.genrule(
        name = name + "_elf",
        srcs = [src, _LD],
        outs = [elf],
        cmd = " ".join(
            ["$(location @xpack_riscv_gcc//:gcc)", "-march=" + march] +
            _BASE_OPTS +
            [
                "-T$(location %s)" % _LD,
                "$(location %s)" % src,
                "-o $@",
            ],
        ),
        tags = tags,
        tools = [
            "@xpack_riscv_gcc//:gcc",
            _TOOLCHAIN,
        ],
        visibility = visibility,
    )
    return _rcf_rules(name, elf, tags, visibility)

def cpi_bmark_image(name, benchmark, march = MARCH_C, tags = [], visibility = None):
    """Compile one riscv-tests benchmark against the CPI harness runtime and return the .rcf name.
    crt_bmark.S turns main()'s return value into the a0 sentinel the testbench watches, and
    bmark_stubs.c defines setStats() as the kernel-window marker store the testbench decodes.
    """
    elf = name + ".elf"
    srcs = "//verification:benchmark_%s_srcs" % benchmark
    hdrs = "//verification:benchmark_headers"

    native.genrule(
        name = name + "_elf",
        srcs = [
            "crt_bmark.S",
            "bmark_stubs.c",
            _LD,
            srcs,
            hdrs,
        ],
        outs = [elf],
        cmd = " ".join(
            ["$(location @xpack_riscv_gcc//:gcc)", "-march=" + march] +
            _BASE_OPTS +
            _BMARK_OPTS +
            ["-I" + d for d in _BMARK_INCLUDES] +
            ["-Iverification/benchmarks/" + benchmark] +
            [
                "-T$(location %s)" % _LD,
                "$(location crt_bmark.S)",
                "$(location bmark_stubs.c)",
                "$(locations %s)" % srcs,
                "-lgcc",
                "-o $@",
            ],
        ),
        tags = tags,
        tools = [
            "@xpack_riscv_gcc//:gcc",
            _TOOLCHAIN,
        ],
        visibility = visibility,
    )
    return _rcf_rules(name, elf, tags, visibility)

def cpi_test(
        name,
        image,
        vhdl_srcs,
        vhdl_paths,
        size = "medium",
        timeout = None,
        sim_timeout_s = 600,
        tags = [],
        visibility = None):
    """Run one image under vesta_cpi_tb and assert its counts against expected.json. `name` is the
    image base name, the expected.json key and the TEST_NAME generic. vhdl_paths travels as argv
    because GHDL analysis order is load bearing and a filegroup's DefaultInfo is unordered.
    """
    py_test(
        name = name,
        size = size,
        timeout = timeout,
        srcs = ["cpi_test.py"],
        args = [
            "--name",
            name,
            "--image",
            "$(rootpath %s)" % image,
            "--expected",
            "$(rootpath expected.json)",
            "--ghdl",
            "$(rootpath @ghdl//:ghdl)",
            "--sim-timeout",
            str(sim_timeout_s),
            "--",
        ] + vhdl_paths,
        data = [
            image,
            "expected.json",
            "vesta_cpi_tb.vhd",
            vhdl_srcs,
            "@ghdl//:ghdl",
            "@ghdl//:vhdl_libs_v08",
        ],
        main = "cpi_test.py",
        tags = tags,
        visibility = visibility,
    )
