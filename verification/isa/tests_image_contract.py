#!/usr/bin/env python3
"""Assert the RCF image contract on a sample of the generated ISA images.

There is no tracked golden for these images: .gitignore ignores *.rcf globally
and re-includes only tools/cosim/gate/*.rcf, whose single member is the MP
bootrom image, not an ISA test image.  Byte identity against the on-disk
verification/isa/rcf/ set is therefore a hand measurement.  What is testable
here without an untracked input is the contract every consumer depends on, and
it is the contract a stale or double-staged image breaks first:

  * an unflashed image is exactly WORD_COUNT lines of 32 '0'/'1' characters
    (the Makefile's `wc -l` guard, MEM_SIZE 0x14000 / 4),
  * a flashed image starts with the 0x10adbeef command word, then the 0x8000
    and 0x8200 vector-area bounds, then 128 zero words,
  * a flashed image ends with the 0xcafebabe execute word,
  * a flashed image carries exactly ONE vector-area header; a second one is
    the K5 double-prepend that traps at 0x8200 with instr_curr = 0,
  * the flashed file name is exactly 22 characters, the TARGET_RCF_NAMELEN the
    29-character TEST_FILE generic of riscv_tb requires.

It also carries the TILE ISA gate, which is about the chip and not the staging.
Harts 1-4 are the hardened hart_tile macro at rv32iac: MCU.vhd:3290-3294 passes
TILE_ENABLE_MUL / TILE_ENABLE_DIV / TILE_ENABLE_BITMANIP as false, and
MemoryMap.vhd:1235-1237 states the same contract.  The images are assembled
-march=rv32imc / rv32imac all the same, so gas accepts a `mul` or a `bseti` in
tile-executed code without a word and the first evidence is an
illegal-instruction trap on a tile inside a licensed regression.  The gate reads
the objdump listings of the three suites whose tests ignite tiles (rv32ui,
rv32ua, rv32uc) and rejects every M and Zb mnemonic in them.

It is deliberately stricter than "tile sections only".  Tile code and hart-0
code share one .text in these sources -- shexec.S puts `orchestrator` AFTER
`tile_entry`, and shboot.S hand-rolls the launch with no tile-named label at all
-- so there is no section, and no symbol convention, that separates them
mechanically.  Whole-image is the boundary that can actually be checked, and it
costs nothing: rv32ui/rv32ua/rv32uc are the base-integer and atomics suites, and
exactly two sites in 176 images use M or Zb today.  Both are allowlisted below
by image, symbol and mnemonic, with the reason.  rv32um and rv32uzb* are NOT in
the checked set: those suites exist to exercise the extensions and hart 0 runs
them alone.

Plain runner, no pytest: exit 0 is a pass.
"""

import os
import re
import sys

WORD_COUNT = 0x14000 // 4
RCF_BASENAME_LEN = 22

CMD_LOAD = format(0x10ADBEEF, "032b")
CMD_EXEC = format(0xCAFEBABE, "032b")
VEC_START = format(0x8000, "032b")
VEC_END = format(0x8200, "032b")
ZERO = "0" * 32


# RV32M, in the mnemonics binutils prints.
_M_MNEMONICS = frozenset("mul mulh mulhsu mulhu div divu rem remu".split())

# Zba / Zbb / Zbc / Zbs, plus the pseudo-mnemonics binutils prints for them
# (zext.w for add.uw rd,rs,x0; rev8; orc.b).  Names only, no aliasing subtlety:
# a mnemonic in this set is an instruction the tiles do not implement.
_ZB_MNEMONICS = frozenset((
    "sh1add sh2add sh3add slli.uw add.uw zext.w "
    "andn orn xnor clz ctz cpop max maxu min minu sext.b sext.h zext.h "
    "rol ror rori rorw orc.b rev8 "
    "clmul clmulh clmulr "
    "bclr bclri bext bexti binv binvi bset bseti"
).split())

# Whole images whose PURPOSE is an M or Zb instruction, and which never launch
# a tile.  The no-tile half is RE-PROVED: an image listed here that grows a tile
# entry symbol fails, because the exemption's premise would be gone.
_MZB_ALLOWED_IMAGES = {
    "rv32ua-p-extmul":
        "adaptive M-extension probe: dispatches on misa.M and, in a build "
        "without M, the MUL must take the illegal-instruction trap. Hart 0 "
        "only, no MP_LAUNCH.",
    "rv32ua-p-extdiv":
        "the divide half of the same probe (extdiv.S:4-11).",
}

# (image, symbol, mnemonic) sites in images that DO launch tiles, proven
# hart-0-only.  The checker re-proves that half by requiring the site to sit
# below the image's tile entry.  A site that stops matching is a hard error, so
# a deleted or moved one cannot rot here unnoticed.
_MZB_ALLOWED_SITES = {
    # fk51mp.S:233-244 reads back reserved shamt[5]=1 shift-immediate words and
    # compares them against what the assembler emits for bseti/binvi of the same
    # seed, under an explicit `.option arch, +zbs`.  It is the reference half of
    # the comparison, executed by hart 0 in fk_watch; the tiles enter at
    # fk_tile_entry, above it.
    ("rv32ua-p-fk51mp", "fk_watch", "bset"),
    ("rv32ua-p-fk51mp", "fk_watch", "binv"),
    # packalias.S probes the packh/zext.h encoding overlap from hart 0's
    # test_entry, before any tile is launched.
    ("rv32ua-p-packalias", "test_entry", "zext.h"),
}

# `   8460:	287a1293          	bset	t0,s4,0x7`
_INSN_RE = re.compile(r"^\s+([0-9a-f]+):	[0-9a-f ]+	(\S+)")
_SYM_RE = re.compile(r"^([0-9a-f]+) <(.+)>:")


def collect_dumps():
    """Every objdump listing in the runfiles, as {image name: path}."""
    dumps = {}
    for root, _dirs, files in os.walk("."):
        norm = root.replace(os.sep, "/")
        if "/verification/isa" not in norm and not norm.endswith("verification/isa"):
            continue
        for f in sorted(files):
            if f.endswith(".dump"):
                dumps[f[:-len(".dump")]] = os.path.join(root, f)
    return dumps


def scan_dump(path):
    """Return (M/Zb sites, lowest tile entry address or None).

    A site is (address, mnemonic, enclosing symbol).
    """
    sites = []
    sym = "?"
    tile_addr = None
    with open(path) as f:
        for line in f:
            m = _SYM_RE.match(line)
            if m:
                sym = m.group(2)
                if "tile" in sym.lower() and tile_addr is None:
                    tile_addr = int(m.group(1), 16)
                continue
            i = _INSN_RE.match(line)
            if i and (i.group(2) in _M_MNEMONICS or i.group(2) in _ZB_MNEMONICS):
                sites.append((int(i.group(1), 16), i.group(2), sym))
    return sites, tile_addr


def check_tile_isa(dumps, fails):
    """No M or Zb mnemonic in the tile-igniting suites, allowlist aside."""
    seen_sites = set()
    seen_images = set()
    for image in sorted(dumps):
        sites, tile_addr = scan_dump(dumps[image])
        if image in _MZB_ALLOWED_IMAGES:
            if sites:
                seen_images.add(image)
            if tile_addr is not None:
                fails.append(
                    "%s is allowlisted whole because it launches no tile, but "
                    "it now has a tile entry at 0x%x" % (image, tile_addr))
            continue
        for addr, mnemonic, sym in sites:
            key = (image, sym, mnemonic)
            if key not in _MZB_ALLOWED_SITES:
                fails.append(
                    "%s: %s at 0x%x in <%s> -- harts 1-4 are rv32iac "
                    "(MCU.vhd:3290-3294); move it below the tile entry and "
                    "allowlist it, or drop it" % (image, mnemonic, addr, sym))
                continue
            seen_sites.add(key)
            if tile_addr is not None and addr >= tile_addr:
                fails.append(
                    "%s: allowlisted %s at 0x%x in <%s> is AT OR ABOVE the tile "
                    "entry 0x%x, so it is no longer hart-0-only"
                    % (image, mnemonic, addr, sym, tile_addr))
    for key in sorted(_MZB_ALLOWED_SITES - seen_sites):
        fails.append("stale allowlist entry, no longer present: %s" % (key,))
    for image in sorted(set(_MZB_ALLOWED_IMAGES) - seen_images):
        fails.append("stale whole-image allowlist entry, no M or Zb left in: %s"
                     % image)


def collect():
    """Find the sampled images in the runfiles tree.

    Returns:
      (unflashed, flashed) lists of paths.
    """
    unflashed = []
    flashed = []
    for root, _dirs, files in os.walk("."):
        norm = root.replace(os.sep, "/")
        # The images live under the package directory of the runfiles tree;
        # the flashed ones sit in its flash/ subdirectory.
        if "/verification/isa" not in norm and not norm.endswith("verification/isa"):
            continue
        for f in sorted(files):
            if not f.endswith(".rcf"):
                continue
            path = os.path.join(root, f)
            if norm.endswith("/flash"):
                flashed.append(path)
            else:
                unflashed.append(path)
    return sorted(unflashed), sorted(flashed)


def check_unflashed(path, fails):
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]
    if len(lines) != WORD_COUNT:
        fails.append("%s: %d words, expected %d" % (path, len(lines), WORD_COUNT))
        return
    for i, ln in enumerate(lines):
        if len(ln) != 32 or ln.strip("01") != "":
            fails.append("%s: line %d is not 32 binary digits: %r" % (path, i + 1, ln))
            return
    if lines[0] == CMD_LOAD:
        fails.append("%s: unflashed image already carries the flash header" % path)


def check_flashed(path, fails):
    base = os.path.basename(path)
    if len(base) != RCF_BASENAME_LEN:
        fails.append("%s: name is %d chars, contract needs %d" % (base, len(base), RCF_BASENAME_LEN))
    with open(path) as f:
        lines = [ln.rstrip("\n") for ln in f]
    if len(lines) < 132:
        fails.append("%s: only %d lines, too short to hold the header" % (path, len(lines)))
        return
    if lines[0] != CMD_LOAD or lines[1] != VEC_START or lines[2] != VEC_END:
        fails.append("%s: vector-area header is %r" % (path, lines[0:3]))
    for i in range(3, 131):
        if lines[i] != ZERO:
            fails.append("%s: vector-area word %d is not zero" % (path, i - 3))
            break
    if lines[-1] != CMD_EXEC:
        fails.append("%s: last word is %r, expected the execute word" % (path, lines[-1]))
    # A second vector-area header means the image took the flash prepend twice.
    for i in range(1, len(lines) - 2):
        if lines[i] == CMD_LOAD and lines[i + 1] == VEC_START and lines[i + 2] == VEC_END:
            fails.append("%s: a second vector-area header at line %d" % (path, i + 1))
            break


def main():
    unflashed, flashed = collect()
    if not unflashed or not flashed:
        print("FAIL: found %d unflashed and %d flashed images in the runfiles"
              % (len(unflashed), len(flashed)))
        return 1

    dumps = collect_dumps()
    if not dumps:
        print("FAIL: no objdump listings in the runfiles; the tile ISA gate "
              "cannot run and must not pass silently")
        return 1

    fails = []
    for p in unflashed:
        check_unflashed(p, fails)
    for p in flashed:
        check_flashed(p, fails)
    check_tile_isa(dumps, fails)

    if fails:
        for f in fails:
            print("FAIL: %s" % f)
        return 1

    print("OK: %d unflashed and %d flashed images meet the RCF contract; "
          "%d disassemblies carry no M or Zb outside %d allowlisted hart-0 "
          "sites and %d allowlisted probe images"
          % (len(unflashed), len(flashed), len(dumps),
             len(_MZB_ALLOWED_SITES), len(_MZB_ALLOWED_IMAGES)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
