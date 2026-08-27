"""Bare metal rv32 firmware rules built on the hermetic xPack riscv-none-elf toolchain.

These macros replace the hand written makefiles under software/. Every step is
a genrule that calls the same driver the makefile called, with the same flags
in the same order, so the produced images stay byte comparable against the
bench artifacts.

The toolchain is not a registered cc_toolchain. The makefiles invoke the gcc
driver directly and the firmware links against a hand written linker script,
so a plain genrule reproduces the recipe with far less machinery.

Include paths and -L directories are given as repository root relative
directories, because that is where bazel places source files in the sandbox.

Link flags are handed in as an ordered list rather than assembled by the
macro, because library order is load bearing for a static link: the bootrom
makefile puts -lgcc before the objects while other images put it after.
These placeholders are expanded in each entry:
  {march}     the -march= flag
  {mabi}      the -mabi= flag, or the empty string when mabi is None
  {ld_script} the linker script path in the sandbox
  {map}       the declared .map output path
"""

load("@rules_python//python:defs.bzl", "py_test")

GCC = "@xpack_riscv_gcc//:gcc"
OBJCOPY = "@xpack_riscv_gcc//:objcopy"
OBJDUMP = "@xpack_riscv_gcc//:objdump"
SIZE = "@xpack_riscv_gcc//:size"
TOOLCHAIN = "@xpack_riscv_gcc//:toolchain"

# Tools every firmware genrule needs. The whole tree must travel with the
# driver because gcc reaches for cc1, lto1, collect2, ld and the multilibs.
FIRMWARE_TOOLS = [GCC, OBJCOPY, OBJDUMP, TOOLCHAIN]

# Resolves the driver paths and the sysroot include directory that the
# makefiles pass explicitly as GCC_INC_DIR.
PRELUDE = """set -euo pipefail
CC="$(location %s)"
OBJCOPY="$(location %s)"
OBJDUMP="$(location %s)"
TOOLCHAIN_ROOT="$$(cd "$$(dirname "$$CC")/.." && pwd)"
GCC_INC_DIR="$$TOOLCHAIN_ROOT/riscv-none-elf/include"
""" % (GCC, OBJCOPY, OBJDUMP)

DEFAULT_LINK_FLAGS = [
    "{march}",
    "{mabi}",
    "-nostartfiles",
    "-nostdlib",
    "-Wl,-T,{ld_script}",
]

def flash_padded_name(stem, basename_len = 22):
    """Returns the x padded flash image basename.

    verification/isa/flash_prepend.sh renames each image so its basename is
    exactly basename_len characters, padding with leading 'x'. The VHDL bench
    reads TEST_FILE : string(1 to 29), which is "../rcf/" plus this name, so
    the length is a hard contract rather than cosmetics.
    """
    base = stem + ".rcf"
    if len(base) > basename_len:
        fail("flash image basename %r is %d chars, over the %d char contract" %
             (base, len(base), basename_len))
    return ("x" * (basename_len - len(base))) + base

PLATFORM_HEADERS = "//platform/myshkin/gcc/lib:platform_headers"
PLATFORM_LINKER_FRAGMENTS = "//platform/myshkin/gcc/lib:linker_fragments"
PLATFORM_INCLUDE_DIR = "platform/myshkin/gcc/lib/include"
PLATFORM_LINKER_DIR = "platform/myshkin/gcc/lib/linker"
TOOLS_LINKER_DIR = "tools/build/linker-scripts"

def _quoted_execpaths(labels):
    return " ".join(['"$(execpath %s)"' % l for l in labels])

def _expand(flags, march, mabi, ld_script, map_file):
    out = []
    for f in flags:
        f = f.replace("{march}", "-march=" + march)
        f = f.replace("{mabi}", ("-mabi=" + mabi) if mabi else "")
        f = f.replace("{ld_script}", "$(location %s)" % ld_script)
        if map_file:
            f = f.replace("{map}", "$(location %s)" % map_file)
        if f:
            out.append(f)
    return out

def rv32_firmware(
        name,
        srcs,
        march,
        ld_script,
        pad_bytes,
        defines = [],
        copts = [],
        mabi = None,
        hdrs = [],
        includes = [],
        ld_srcs = [],
        link_flags = DEFAULT_LINK_FLAGS,
        link_flags_post = [],
        gcc_inc = False,
        obj_suffix = ".o",
        dump_flags = ["-D"],
        emit_hex = True,
        emit_map = True,
        rcf_name = None,
        flash = True,
        flash_basename_len = 22,
        visibility = None,
        tags = []):
    """Compiles, links and images one bare metal rv32 program.

    Emits :NAME_elf, :NAME_bin, :NAME_hex, :NAME_dump, :NAME_rcf and, when
    flash is True, :NAME_flashed_rcf carrying the SPI load/execute header.

    Args:
      name: target base name; also the output file stem.
      srcs: sources in link order. The first entry must be the startup file,
        because the linker script places the first input at the reset vector.
      march: the -march string, for example "rv32i".
      ld_script: label of the linker script.
      pad_bytes: size of the zero filled image the RCF is cut from.
      defines: preprocessor defines, without the -D.
      copts: extra compile only flags, appended after the include flags.
      mabi: the -mabi string, or None to leave the driver default.
      hdrs: header files the sources include.
      includes: repository root relative include directories.
      ld_srcs: extra files the linker script pulls in, such as memory.x.
      link_flags: ordered flags placed before the objects on the link line.
      link_flags_post: ordered flags placed after the objects, for libraries
        that must resolve against them.
      gcc_inc: pass -I on the toolchain's own riscv-none-elf/include.
      obj_suffix: suffix appended to each object file name.
      dump_flags: objdump flags for the disassembly listing.
      emit_hex: also emit the Intel hex image.
      emit_map: declare a .map output; {map} then expands to its path.
      rcf_name: output file name for the raw RCF, default NAME.rcf.
      flash: also emit the flash headered image.
      flash_basename_len: the padded basename contract length.
      visibility: forwarded to every emitted target.
      tags: forwarded to every emitted target.
    """
    if pad_bytes % 4 != 0:
        fail("pad_bytes %d is not a multiple of 4" % pad_bytes)

    cflags = ["-march=" + march]
    if mabi:
        cflags.append("-mabi=" + mabi)
    cflags += ["-D" + d for d in defines]
    if gcc_inc:
        cflags.append('-I "$$GCC_INC_DIR"')
    cflags += ["-I" + i for i in includes]
    cflags += copts

    elf = name + ".elf"
    map_file = name + ".map" if emit_map else None
    link_srcs = srcs + hdrs + [ld_script] + ld_srcs

    elf_outs = [elf]
    if map_file:
        elf_outs.append(map_file)

    pre = _expand(link_flags, march, mabi, ld_script, map_file)
    post = _expand(link_flags_post, march, mabi, ld_script, map_file)

    # Compile each translation unit on its own, exactly as the makefiles do,
    # then link the objects in the order they were listed.
    compile_and_link = PRELUDE + """
OBJ_DIR="$$(mktemp -d)"
OBJS=""
for f in {srcs}; do
  o="$$OBJ_DIR/$$(basename "$$f"){objsuffix}"
  "$$CC" -c {cflags} "$$f" -o "$$o"
  OBJS="$$OBJS $$o"
done
"$$CC" {pre} $$OBJS {post} -o "$(location {elf})"
rm -rf "$$OBJ_DIR"
""".format(
        srcs = _quoted_execpaths(srcs),
        objsuffix = obj_suffix,
        cflags = " ".join(cflags),
        pre = " ".join(pre),
        post = " ".join(post),
        elf = elf,
    )

    native.genrule(
        name = name + "_elf",
        srcs = link_srcs,
        outs = elf_outs,
        cmd = compile_and_link,
        tools = FIRMWARE_TOOLS,
        visibility = visibility,
        tags = tags,
    )

    native.genrule(
        name = name + "_bin",
        srcs = [elf],
        outs = [name + ".bin"],
        cmd = PRELUDE + '"$$OBJCOPY" -O binary --gap-fill=0x00 "$<" "$@"\n',
        tools = FIRMWARE_TOOLS,
        visibility = visibility,
        tags = tags,
    )

    if emit_hex:
        native.genrule(
            name = name + "_hex",
            srcs = [elf],
            outs = [name + ".hex"],
            cmd = PRELUDE + '"$$OBJCOPY" -O ihex "$<" "$@"\n',
            tools = FIRMWARE_TOOLS,
            visibility = visibility,
            tags = tags,
        )

    native.genrule(
        name = name + "_dump",
        srcs = [elf],
        outs = [name + ".dump"],
        cmd = PRELUDE + '"$$OBJDUMP" %s "$<" > "$@"\n' % " ".join(dump_flags),
        tools = FIRMWARE_TOOLS,
        visibility = visibility,
        tags = tags,
    )

    rcf = rcf_name if rcf_name else (name + ".rcf")
    words = pad_bytes // 4

    # The makefiles cut a zero filled image of the whole memory window and
    # overlay the program at offset zero, so trailing words read as zero.
    native.genrule(
        name = name + "_rcf",
        srcs = [name + ".bin"],
        outs = [rcf],
        cmd = ("set -euo pipefail\n" +
               'PAD="$$(mktemp)"\n' +
               'dd if=/dev/zero of="$$PAD" bs={pad} count=1 2>/dev/null\n' +
               'dd if="$<" of="$$PAD" bs=1 conv=notrunc 2>/dev/null\n' +
               '"$(location //tools/build:bin2rcf)" "$$PAD" "$@" --expect-words {words}\n' +
               'rm -f "$$PAD"\n').format(pad = pad_bytes, words = words),
        tools = ["//tools/build:bin2rcf"],
        visibility = visibility,
        tags = tags,
    )

    if flash:
        flashed = flash_padded_name(name, flash_basename_len)
        native.genrule(
            name = name + "_flashed_rcf",
            srcs = [rcf],
            outs = [flashed],
            cmd = ("set -euo pipefail\n" +
                   '"$(location //tools/build:rcf_flash)" "$<" "$@" ' +
                   "--basename-len {n}\n").format(n = flash_basename_len),
            tools = ["//tools/build:rcf_flash"],
            visibility = visibility,
            tags = tags,
        )

def myshkin_app(name, srcs = None, hdrs = [], copts = [], visibility = None):
    """One application from the blinky family: blinky and its five siblings.

    The six makefiles under software/ are the same file with a different
    TARGET, so they collapse to one macro.

    Those makefiles carry a wildcard fallback: memory.x, periph.x and the
    headers come from platform/myshkin/gcc/lib when that directory exists, and
    from tools/build/linker-scripts when it does not. It does exist and it is
    tracked, so only the platform branch has ever been taken. That branch is
    hard coded here instead of replayed, because a build graph must not depend
    on whether a directory happens to be present.

    The makefiles also pass -I./include, but none of the six packages has an
    include directory, so nothing is dropped by leaving it out.

    Args:
      name: the makefile TARGET, and the image stem.
      srcs: sources in link order, default src/start.S then src/main.c.
      hdrs: extra headers the sources include.
      copts: extra compile only flags.
      visibility: forwarded to every emitted target.
    """
    rv32_firmware(
        name = name,
        srcs = srcs if srcs else ["src/start.S", "src/main.c"],
        march = "rv32ima",
        mabi = "ilp32",
        copts = ["-Wall", "-O2", "-g", "-ffreestanding", "-nostdlib"] + copts,
        hdrs = hdrs + [PLATFORM_HEADERS, "//software/commune:chip_headers"],
        includes = [PLATFORM_INCLUDE_DIR, "software/commune/include"],
        ld_script = "//tools/build:linker-scripts/MCU.ld",
        ld_srcs = [PLATFORM_LINKER_FRAGMENTS, "//tools/build:linker_scripts"],
        link_flags = [
            "{march}",
            "{mabi}",
            "-T{ld_script}",
            "-nostartfiles",
            "-nostdlib",
            "-Wl,-Map={map}",
            "-L" + PLATFORM_LINKER_DIR,
            "-L" + TOOLS_LINKER_DIR,
        ],
        link_flags_post = [],
        # 0x14000 byte RAM window, zero filled, 20480 words.
        pad_bytes = 0x14000,
        visibility = visibility,
    )

def firmware_image_test(name, image, golden):
    """Locks a built firmware image against a tracked golden copy.

    The goldens are plain text so a diff is readable in review, and they are
    named .txt because *.rcf is gitignored repository wide.

    Args:
      name: test target name.
      image: label of the generated image file.
      golden: label of the tracked golden text file.
    """
    py_test(
        name = name,
        size = "small",
        srcs = ["//software/testtools:compare_text.py"],
        main = "//software/testtools:compare_text.py",
        args = [
            "$(location %s)" % image,
            "$(location %s)" % golden,
            "--label",
            name,
        ],
        data = [image, golden],
    )
