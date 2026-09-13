"""VestaRV: bare-metal rv32 firmware rules on the hermetic xPack riscv-none-elf toolchain.

Every step is a genrule calling the same driver with the same flags in the same order as the
makefiles it replaces, so images stay byte comparable. Not a registered cc_toolchain. Include
and -L paths are repository-root relative, which is where bazel places sources. Link flags are
an ordered list because library order is load bearing: the bootrom puts -lgcc before objects.
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
    """The x-padded flash image basename. flash_prepend.sh pads each image's basename to exactly
    basename_len characters, and the VHDL bench reads TEST_FILE : string(1 to 29), which is
    "../rcf/" plus this name, so the length is a hard contract rather than cosmetics.
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
    """Compile, link and image one bare-metal rv32 program, emitting :NAME_elf, _bin, _hex, _dump,
    _rcf and, when flash is True, _flashed_rcf. srcs are in link order and the first must be the
    startup file; link_flags go before the objects and link_flags_post after them.
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
    """One application from the blinky family, the six makefiles under software/ being the same file
    with a different TARGET. Their wildcard fallback is hard coded to the platform branch here,
    because a build graph must not depend on whether a directory happens to be present.
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
    """Lock a built firmware image against a tracked golden copy. The goldens are plain text so a
    diff is readable in review, and they are named .txt because *.rcf is gitignored repository
    wide.
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
