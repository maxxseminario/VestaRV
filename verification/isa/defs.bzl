"""Bazel rules for the verification/isa RISC-V test images.

This is a faithful port of the verification/isa/Makefile compile_template plus
the build_mp_images.sh / flash_prepend.sh staging that the CI job "Bootrom +
ISA image builds" runs as `./build_mp_images.sh 4 rcf_ci`.

WHY THIS EXISTS.  The Makefile keys `$(build_dir)/<suite>/<test>` on the .S
alone.  The -march of the suite and the -DCORE_ENABLE_* / -DNHARTS polarity
arrive through RISCV_GCC_OPTS, which is NOT a prerequisite of anything, so a
rebuild at a different polarity reuses whatever ELF is already on disk.  That
is the trap build_mp_images.sh works around with `rm -rf build/` and the
build/.imgset stamp.  Here the march, the mabi, the define list and the linker
script are all arguments of the compile action, so they are part of the action
key: changing any one of them rebuilds exactly the images it affects, and
nothing else.

The pipeline per test, matching the Makefile step for step:
  gcc <march> <mabi> <opts> <defines> -I... -T<ld> test.S -o test.elf
  objdump <the Makefile's RISCV_OBJDUMP section list>          -> test.dump
  objcopy -O binary --gap-fill=0x00                            -> test.bin
  zero image of MEM_SIZE bytes, binary overlaid at BIN_OFFSET   -> test_padded.bin
  //tools/build:bin2rcf --expect-words 20480                   -> test.rcf
  //tools/build:rcf_flash --basename-len 22                    -> <x-pad>test.rcf

The unflashed .rcf carries the plain test name.  The flashed image carries the
x-padded 22-character name that riscv_tb's fixed 29-character TEST_FILE generic
requires, which is what pad_all_rcf and flash_prepend.sh produce on disk.
"""

# Makefile MEM_SIZE / BIN_OFFSET / WORD_COUNT.
MEM_SIZE_BYTES = 0x14000

BIN_OFFSET_BYTES = 0x0

IMAGE_WORDS = MEM_SIZE_BYTES // 4

# Makefile TARGET_RCF_NAMELEN, and flash_prepend.sh TARGET_BASENAME_LEN.
RCF_BASENAME_LEN = 22

# The flashed images go in their own output subdirectory.
# They must: a name already 22 characters long gets no x padding, so the flashed
# and unflashed files of such a test would otherwise be the same output path.
# On disk the Makefile has the same two names collide by construction, because
# flash_prepend.sh rewrites the image IN PLACE.
FLASH_SUBDIR = "flash/"

# Makefile RISCV_GCC_OPTS default.
# build_mp_images.sh reproduces exactly this list and appends its defines.
BASE_GCC_OPTS = [
    "-static",
    "-mcmodel=medany",
    "-fvisibility=hidden",
    "-nostdlib",
    "-nostartfiles",
]

# The CI configuration: `./build_mp_images.sh 4 rcf_ci` with EXTRA_GCC_DEFINES
# unset, i.e. the Castalia default polarity, where every CORE_ENABLE_* probe
# compiles its OFF arm.
CI_DEFINES = ["-DNHARTS=4"]

# Makefile RISCV_OBJDUMP section list, verbatim and in order.
_OBJDUMP_FLAGS = [
    "--disassemble-all",
    "--disassemble-zeroes",
]

_OBJDUMP_SECTIONS = [
    ".text",
    ".text.startup",
    ".text.init",
    ".ivt",
    ".data",
    ".tohost",
    ".bss",
    ".npu0_yhat",
    ".npu0_x",
    ".npu0_w",
    ".isr_sys_wdt",
    ".isr_gpio0_b0",
    ".isr_gpio0_b1",
    ".isr_gpio0_b2",
    ".isr_gpio0_b3",
    ".isr_gpio0_b4",
    ".isr_gpio0_b5",
    ".isr_gpio0_b6",
    ".isr_gpio0_b7",
    ".isr_spi0_tc",
    ".isr_spi0_te",
    ".isr_spi1_tc",
    ".isr_spi1_te",
    ".isr_uart0_rc",
    ".isr_uart0_te",
    ".isr_uart0_tc",
    ".isr_tim0_cap0",
    ".isr_tim0_cap1",
    ".isr_tim0_ovf",
    ".isr_tim0_cmp0",
    ".isr_tim0_cmp1",
    ".isr_tim0_cmp2",
    ".isr_tim1_cap0",
    ".isr_tim1_cap1",
    ".isr_tim1_ovf",
    ".isr_tim1_cmp0",
    ".isr_tim1_cmp1",
    ".isr_tim1_cmp2",
    ".isr_gpio1_b0",
    ".isr_gpio1_b1",
    ".isr_gpio1_b2",
    ".isr_gpio1_b3",
    ".isr_gpio1_b4",
    ".isr_gpio1_b5",
    ".isr_gpio1_b6",
    ".isr_gpio1_b7",
    ".isr_gpio2_b0",
    ".isr_gpio2_b1",
    ".isr_gpio2_b2",
    ".isr_gpio2_b3",
    ".isr_gpio2_b4",
    ".isr_gpio2_b5",
    ".isr_gpio2_b6",
    ".isr_gpio2_b7",
    ".isr_gpio3_b0",
    ".isr_gpio3_b1",
    ".isr_gpio3_b2",
    ".isr_gpio3_b3",
    ".isr_gpio3_b4",
    ".isr_gpio3_b5",
    ".isr_gpio3_b6",
    ".isr_gpio3_b7",
    ".isr_uart1_rc",
    ".isr_uart1_te",
    ".isr_uart1_tc",
    ".isr_afe0_rc",
    ".isr_afe0_ovf",
    ".isr_afe0_err",
    ".isr_sar0_rc",
    ".isr_sar0_ovf",
]

# Include directories, in the Makefile's order.
# The paths are execroot relative because a genrule runs at the execroot.
# The myshkin include dir carries the generated MemoryMap.h; no test in any
# suite instantiated here includes it (only tests/periph, tests/boot and the
# unbuilt extprobe_template.S do), so the flag is carried for fidelity and the
# directory is deliberately not declared as an input.
_INCLUDE_DIRS = [
    "verification/env/p",
    "verification/isa/macros/scalar",
    "platform/myshkin/gcc/lib/include",
]

# The default per-test linker script (Makefile LINK_LD).
DEFAULT_LD = "//verification:env/p/link.ld"

# The one per-test override the Makefile carries: rv32uc-p-rvc's .text.init is
# larger than the 8 KiB private TCM, so it executes from the shared bulk RAM.
SHARED_LD = "//verification:env/p/link_shared.ld"

_TOOLCHAIN = "@xpack_riscv_gcc//:toolchain"

def flashed_rcf_name(basename):
    """The x-padded 22-character image name pad_all_rcf produces.

    Args:
      basename: the test name, e.g. "rv32ui-p-simple".

    Returns:
      The padded file name, e.g. "xxxrv32ui-p-simple.rcf".
    """
    name = basename + ".rcf"
    pad = RCF_BASENAME_LEN - len(name)
    if pad < 0:
        pad = 0
    return ("x" * pad) + name

def riscv_isa_image(
        name,
        src,
        march,
        mabi = "ilp32",
        defines = [],
        ld_script = DEFAULT_LD,
        hdrs = [],
        gcc_opts = BASE_GCC_OPTS,
        basename = None,
        outdir = "",
        tags = [],
        visibility = None):
    """Build one ISA test image: .elf, .dump, .bin, padded .bin, .rcf, flashed .rcf.

    Args:
      name: target name prefix.  The rule targets are <name>_elf, <name>_dump,
        <name>_rcf and <name>_flashed; the output FILES keep the plain image
        names (<basename>.elf and so on), which is why the rules cannot be
        named after them.
      src: the test .S source label.
      march: the -march string for this suite, without the -march= prefix.
      mabi: the -mabi string, without the -mabi= prefix.
      defines: extra preprocessor flags, e.g. ["-DNHARTS=4"].  These are part of
        the compile action key, which is the whole point of this port.
      ld_script: label of the linker script to pass to -T.
      hdrs: additional sources the compile reads (headers, included .S files).
      gcc_opts: the RISCV_GCC_OPTS list.
      basename: output file base name; defaults to name.
      outdir: optional package-relative output subdirectory, with trailing slash.
        Use it to hold two configurations of the same test in one package.
      tags: tags applied to every generated target.
      visibility: visibility applied to every generated target.
    """
    if basename == None:
        basename = name

    elf = outdir + basename + ".elf"
    dump = outdir + basename + ".dump"
    binary = outdir + basename + ".bin"
    padded = outdir + basename + "_padded.bin"
    rcf = outdir + basename + ".rcf"
    flashed = outdir + FLASH_SUBDIR + flashed_rcf_name(basename)

    compile_srcs = [src] + hdrs + [ld_script]

    gcc_cmd = " ".join(
        ["$(location @xpack_riscv_gcc//:gcc)"] +
        ["-march=" + march, "-mabi=" + mabi] +
        gcc_opts +
        defines +
        ["-I" + d for d in _INCLUDE_DIRS] +
        [
            "-T$(location %s)" % ld_script,
            "$(location %s)" % src,
            "-o $@",
        ],
    )

    native.genrule(
        name = name + "_elf",
        srcs = compile_srcs,
        outs = [elf],
        cmd = gcc_cmd,
        tools = [
            "@xpack_riscv_gcc//:gcc",
            _TOOLCHAIN,
        ],
        tags = tags,
        visibility = visibility,
    )

    native.genrule(
        name = name + "_dump",
        srcs = [elf],
        outs = [dump],
        cmd = " ".join(
            ["$(location @xpack_riscv_gcc//:objdump)"] +
            _OBJDUMP_FLAGS +
            ["--section=" + s for s in _OBJDUMP_SECTIONS] +
            ["$(location %s)" % elf, "> $@"],
        ),
        tools = [
            "@xpack_riscv_gcc//:objdump",
            _TOOLCHAIN,
        ],
        tags = tags,
        visibility = visibility,
    )

    # objcopy, then the Makefile's dd pair: a zero image of MEM_SIZE bytes with
    # the binary overlaid at BIN_OFFSET, then the od+awk pipeline replaced by
    # the byte-verified //tools/build:bin2rcf.
    # The Makefile's dd overlay would silently grow the padded image past
    # MEM_SIZE for an oversized binary and only trip on the later line count,
    # so the size is checked before the overlay instead.
    native.genrule(
        name = name + "_rcf",
        srcs = [elf],
        outs = [binary, padded, rcf],
        cmd = "\n".join([
            "$(location @xpack_riscv_gcc//:objcopy) -O binary --gap-fill=0x00 $(location %s) $(location %s)" % (elf, binary),
            "sz=$$(wc -c < $(location %s))" % binary,
            "if [ $$sz -gt %d ]; then" % (MEM_SIZE_BYTES - BIN_OFFSET_BYTES),
            "  echo \"$(location %s): $$sz bytes does not fit the %d byte image at offset %d\" >&2" % (binary, MEM_SIZE_BYTES, BIN_OFFSET_BYTES),
            "  exit 1",
            "fi",
            "dd if=/dev/zero of=$(location %s) bs=%d count=1 2>/dev/null" % (padded, MEM_SIZE_BYTES),
            "dd if=$(location %s) of=$(location %s) bs=1 seek=%d conv=notrunc 2>/dev/null" % (binary, padded, BIN_OFFSET_BYTES),
            "$(location //tools/build:bin2rcf) $(location %s) $(location %s) --expect-words %d" % (padded, rcf, IMAGE_WORDS),
        ]),
        tools = [
            "@xpack_riscv_gcc//:objcopy",
            _TOOLCHAIN,
            "//tools/build:bin2rcf",
        ],
        tags = tags,
        visibility = visibility,
    )

    # flash_prepend.sh's transform, out of place, onto the padded name.
    native.genrule(
        name = name + "_flashed",
        srcs = [rcf],
        outs = [flashed],
        cmd = "$(location //tools/build:rcf_flash) $(location %s) $@ --basename-len %d" % (rcf, RCF_BASENAME_LEN),
        tools = ["//tools/build:rcf_flash"],
        tags = tags,
        visibility = visibility,
    )

def riscv_isa_suite(
        suite,
        march,
        tests,
        mabi = "ilp32",
        defines = CI_DEFINES,
        hdrs = [],
        ld_overrides = {},
        outdir = "",
        name_prefix = "",
        tags = [],
        visibility = None):
    """Instantiate a whole ISA suite plus its :<suite>_rcfs / :<suite>_flashed groups.

    Args:
      suite: suite directory name, e.g. "rv32ui".
      march: the suite's -march, matching its $(eval $(call compile_template,...)).
      tests: the suite's <suite>_sc_tests list from tests/<suite>/Makefrag.
      mabi: the suite's -mabi.
      defines: the polarity define list, e.g. CI_DEFINES.
      hdrs: shared compile inputs.
      ld_overrides: {test name: linker script label} for the per-test overrides.
      outdir: package-relative output subdirectory, with trailing slash.
      name_prefix: prefix on the bazel target names, for a second configuration.
      tags: tags applied to every generated target.
      visibility: visibility applied to every generated target.

    Returns:
      None.
    """
    rcfs = []
    flashed = []
    for test in tests:
        base = "%s-p-%s" % (suite, test)
        target = name_prefix + base
        riscv_isa_image(
            name = target,
            src = "tests/%s/%s.S" % (suite, test),
            march = march,
            mabi = mabi,
            defines = defines,
            ld_script = ld_overrides.get(test, DEFAULT_LD),
            hdrs = hdrs,
            basename = base,
            outdir = outdir,
            tags = tags,
            visibility = visibility,
        )
        rcfs.append(":" + outdir + base + ".rcf")
        flashed.append(":" + outdir + FLASH_SUBDIR + flashed_rcf_name(base))

    native.filegroup(
        name = name_prefix + suite + "_rcfs",
        srcs = rcfs,
        tags = tags,
        visibility = visibility,
    )

    native.filegroup(
        name = name_prefix + suite + "_flashed",
        srcs = flashed,
        tags = tags,
        visibility = visibility,
    )
