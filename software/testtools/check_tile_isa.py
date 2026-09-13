#!/usr/bin/env python3
"""Assert that every firmware image more than one hart executes stays inside the
tile ISA subset the chip configuration declares.

WHY THIS EXISTS. Castalia is asymmetric: hart 0 is the soft orchestrator and
carries the full chip ISA, harts 1..N-1 are four instances of one hardened
hart_tile macro built rv32iac. The generator states that in exactly one place
(ChipGenerator.py emits a TILE_ENABLE_<X> constant for every knob under isa.*
and priv.*, and MCU.vhd hands the tile instances those rather than the
CORE_ENABLE_* set hart 0 takes; a minimal tile drops M, Zb, every Z-series
extension, U-mode and PMP, and keeps A, C and the trap CSRs), and it publishes
it as derived.hartClasses in
config/ChipConfig.resolved.json. Nothing connected that statement to the
firmware. A shared image compiled -march=rv32imac assembles a `mul` without a
word, and the first evidence is an illegal-instruction trap on a tile, in
silicon, months later.

WHAT IT GRADES. The linked ELF, not the source and not the flags: flags are the
cause, the ELF is the fact. Every image in SHARED_IMAGES is disassembled and
every instruction in it must be one the narrowest hart class implements. An
instruction from an extension that class dropped is named with its address and
the extension it came from; an instruction this script cannot place in the
declared subset at all is named as unknown, which is the fail-closed half.

WHAT IT DOES NOT GRADE. Images that run on hart 0 alone. They are listed in
HART0_ONLY_IMAGES with the reason each one never reaches a tile, so the
exemption is reviewable rather than implicit, and a name may not appear in both
tables.

The tile subset is read from the resolved configuration, never hardcoded: a
build whose tiles keep the full ISA (isa.minimalTiles false, or a one-hart chip)
degenerates to a single hart class and this gate accepts it.

Plain runner, no pytest: exit 0 is a pass.
"""

import argparse
import json
import os
import re
import subprocess
import sys


# ---------------------------------------------------------------------------
# The image tables.
# ---------------------------------------------------------------------------

# Images more than one hart executes. The BUILD file passes one --elf per entry;
# a missing one, or an --elf naming something absent here, fails the run, so the
# two sides cannot drift.
SHARED_IMAGES = {
    "bootrom_mp":
        "the mask ROM. Every hart resets to 0x0 and fetches it through the "
        "arbiter; software/bootrom_mp/src/start.S dispatches on mhartid and "
        "parks harts 1..N-1 in the tile path, which is ROM code they execute.",
    "dbg_trampoline":
        "the debug entry page. MCU.vhd gives every hart_tile instance "
        "DEBUG_ENTRY_ADDR => x\"00010780\" and ENABLE_DEBUG => "
        "CORE_ENABLE_DEBUG, so whichever hart the Debug Module halts executes "
        "this trampoline, tiles included.",
}

# Images hart 0 alone executes, with the reason each one never reaches a tile.
HART0_ONLY_IMAGES = {
    "blinky":
        "myshkin_app family: an SPI-flash image the boot ROM loads into hart "
        "0's TCM and enters at PROG_BASE_ADDR. Its sources name neither "
        "mhartid nor msip, so it never ignites a tile and the tiles stay "
        "parked in the ROM.",
    "gpiotoggle": "myshkin_app family, hart 0 only. Same reason as blinky.",
    "looptest": "myshkin_app family, hart 0 only. Same reason as blinky.",
    "slowblink": "myshkin_app family, hart 0 only. Same reason as blinky.",
    "traptest": "myshkin_app family, hart 0 only. Same reason as blinky.",
}

# Sections objdump lists under "Disassembly of section" that hold data rather
# than instructions. objdump disassembles anything flagged CODE, and a string
# table flagged "ax" is still a string table.
NON_CODE_SECTIONS = {
    ".vestarv_doc":
        "the VestaRV identification string. software/bootrom_mp/src/start.S "
        "declares it .section .vestarv_doc, \"ax\", so objdump disassembles "
        "ASCII text; nothing branches into it.",
}

# Raw encodings binutils cannot name, with the reason each is legal on a tile.
# Keyed by the hex word objdump prints, so a DIFFERENT encoding printed the
# same way (".word") is still a failure.
ENCODING_ALLOWLIST = {
    "0x7b200073":
        "dret. Debug-mode return, implemented on every hart under "
        "CORE_ENABLE_DEBUG; binutils 13.2 prints it as .word because the ELF "
        "carries no debug-extension attribute.",
    "0xffffffff":
        "a DELIBERATE illegal instruction. software/bootrom_mp/src/start.S "
        "force_trap emits .word 0xFFFFFFFF to drive the core into the "
        "terminal trap state, which is the point of the label.",
}

# The vesta custom-0 opcode. IRET / EXTINGUISH / IGNITE are .insn r 0x0b
# encodings (software/bootrom_mp/src/start.S), decoded by every hart
# independently of the ISA knobs: they are the tile park and ignite mechanism,
# so a tile is exactly the hart that must execute them.
CUSTOM0_OPCODE = 0x0B


# ---------------------------------------------------------------------------
# Mnemonic tables, in the spellings binutils prints under -M no-aliases.
# ---------------------------------------------------------------------------

# RV32I, plus the three things this core family always builds and no isa.* knob
# removes: Zicsr (the CSR instructions), Zifencei, and the M-mode system
# instructions. README.md's "Always built" list.
BASE = frozenset("""
lui auipc jal jalr
beq bne blt bge bltu bgeu
lb lh lw lbu lhu sb sh sw
addi slti sltiu xori ori andi slli srli srai
add sub sll slt sltu xor srl sra or and
fence fence.tso pause fence.i
ecall ebreak mret wfi unimp
csrrw csrrs csrrc csrrwi csrrsi csrrci
""".split())

# RV32M.
EXT_M = frozenset("mul mulh mulhsu mulhu div divu rem remu".split())

# RV32A. The .aq / .rl / .aqrl ordering suffixes are stripped before lookup.
EXT_A = frozenset("""
lr.w sc.w amoswap.w amoadd.w amoxor.w amoand.w amoor.w
amomin.w amomax.w amominu.w amomaxu.w
""".split())

# RV32C. c.slli64 / c.srli64 / c.srai64 are the shamt-zero HINT encodings
# binutils names after their RV128 meaning; on RV32C they are hints, and they
# turn up in padding rather than in generated code.
EXT_C = frozenset("""
c.addi4spn c.lw c.sw c.nop c.addi c.jal c.li c.addi16sp c.lui
c.srli c.srai c.andi c.sub c.xor c.or c.and c.j c.beqz c.bnez
c.slli c.lwsp c.jr c.jalr c.mv c.add c.swsp c.ebreak c.unimp
c.slli64 c.srli64 c.srai64
""".split())

# Zba / Zbb / Zbc / Zbs, and the pseudo-mnemonics binutils prints for them.
# Same list as verification/isa/tests_image_contract.py, which grades the ISA
# regression images for the same asymmetry from the objdump listings.
EXT_ZB = frozenset("""
sh1add sh2add sh3add slli.uw add.uw zext.w
andn orn xnor clz ctz cpop max maxu min minu sext.b sext.h zext.h
rol ror rori orc.b rev8
clmul clmulh clmulr
bclr bclri bext bexti binv binvi bset bseti
""".split())

# march token -> the mnemonics it adds. A token mapped to an empty set adds
# CSRs or state but no instruction encoding.
EXT_MNEMONICS = {
    "i": BASE,
    "m": EXT_M,
    "a": EXT_A,
    "c": EXT_C,
    "zba": EXT_ZB,
    "zbb": EXT_ZB,
    "zbc": EXT_ZB,
    "zbs": EXT_ZB,
    "zicntr": frozenset(),
    "zihpm": frozenset(),
}


def parseMarch(isaString):
    """rv32iac / rv32imac_zba_zbb_zbs_zbc -> the set of march tokens."""
    s = isaString.strip().lower()
    if not s.startswith("rv32"):
        raise ValueError("not an rv32 march string: %r" % isaString)
    parts = s[len("rv32"):].split("_")
    tokens = set(parts[0])
    for p in parts[1:]:
        if p:
            tokens.add(p)
    return tokens


# ---------------------------------------------------------------------------
# Disassembly.
# ---------------------------------------------------------------------------

_SECTION = re.compile(r"^Disassembly of section (\S+):")
_INSN = re.compile(r"^\s*([0-9a-fA-F]+):\t([0-9a-fA-F ]+)\t(\S+)")
_ORDERING_SUFFIX = re.compile(r"\.(aqrl|aq|rl)$")


def disassemble(objdump, elf):
    out = subprocess.check_output(
        [objdump, "-d", "-M", "no-aliases", "--disassemble-zeroes", elf],
        universal_newlines=True)
    section = None
    rows = []
    for line in out.splitlines():
        m = _SECTION.match(line)
        if m:
            section = m.group(1)
            continue
        if section is None or section in NON_CODE_SECTIONS:
            continue
        m = _INSN.match(line)
        if m:
            rows.append((section, int(m.group(1), 16),
                         m.group(2).strip(), m.group(3)))
    return rows


def checkImage(name, elf, objdump, allowed, denied):
    """Returns a list of human-readable failure lines for one image."""
    bad = []
    rows = disassemble(objdump, elf)
    if not rows:
        return ["%s: disassembled to no instructions at all (%s). A gate that "
                "grades nothing is not a gate." % (name, elf)]
    for (section, addr, raw, mnemonic) in rows:
        try:
            word = int(raw.replace(" ", ""), 16)
        except ValueError:
            word = None
        # Data and undecodable words. Allowed only by exact encoding, with a
        # reason, so an unexpected one is still a failure.
        if mnemonic in (".word", ".short", ".byte", ".insn", "(bad)"):
            if word is not None and (word & 0x7F) == CUSTOM0_OPCODE:
                continue
            key = "0x%08x" % word if word is not None else raw
            if key in ENCODING_ALLOWLIST:
                continue
            bad.append(
                "%s: %s+0x%x: %s %s is not a named instruction and is not in "
                "ENCODING_ALLOWLIST" % (name, section, addr, mnemonic, key))
            continue
        base = _ORDERING_SUFFIX.sub("", mnemonic) if mnemonic.startswith(
            ("lr.", "sc.", "amo")) else mnemonic
        if base in allowed:
            continue
        if base in denied:
            bad.append(
                "%s: %s+0x%x: `%s` (raw %s) is from the %s extension, which "
                "the tile hart class does not implement"
                % (name, section, addr, mnemonic, raw, denied[base].upper()))
        else:
            bad.append(
                "%s: %s+0x%x: `%s` (raw %s) is outside the declared tile ISA "
                "subset and this gate has no table for it"
                % (name, section, addr, mnemonic, raw))
    return bad


# ---------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--resolved", required=True,
                    help="config/ChipConfig.resolved.json (derived.hartClasses)")
    ap.add_argument("--objdump", required=True, help="riscv-none-elf-objdump")
    ap.add_argument("--elf", action="append", default=[], metavar="NAME=PATH",
                    help="one shared image, named as in SHARED_IMAGES")
    args = ap.parse_args(argv)

    overlap = sorted(set(SHARED_IMAGES) & set(HART0_ONLY_IMAGES))
    if overlap:
        print("check_tile_isa: FAIL - %s is listed both as shared and as hart-0 "
              "only. One image, one answer." % ", ".join(overlap))
        return 1

    with open(args.resolved) as f:
        resolved = json.load(f)
    classes = (resolved.get("derived") or {}).get("hartClasses") or []
    if not classes:
        print("check_tile_isa: FAIL - %s carries no derived.hartClasses. Run "
              "`make -C platform/common generate`." % args.resolved)
        return 1

    fullTokens = parseMarch(classes[0]["isaString"])
    tileTokens = parseMarch(classes[-1]["isaString"])

    unknown = sorted(t for t in tileTokens if t not in EXT_MNEMONICS)
    if unknown:
        print("check_tile_isa: FAIL - the tile hart class declares %s, and this "
              "gate has no mnemonic table for: %s. Add one to EXT_MNEMONICS "
              "(an empty set if the extension adds no instruction encoding); "
              "refusing to grade an ISA it cannot enumerate."
              % (classes[-1]["isaString"], ", ".join(unknown)))
        return 1

    allowed = set()
    for t in tileTokens:
        allowed |= EXT_MNEMONICS[t]
    denied = {}
    for t in sorted(fullTokens - tileTokens):
        for m in EXT_MNEMONICS.get(t, frozenset()):
            denied[m] = t

    elves = {}
    for spec in args.elf:
        if "=" not in spec:
            print("check_tile_isa: FAIL - --elf wants NAME=PATH, got %r" % spec)
            return 1
        name, path = spec.split("=", 1)
        if name not in SHARED_IMAGES:
            print("check_tile_isa: FAIL - --elf names %r, which is not in "
                  "SHARED_IMAGES. Add it there with the reason every hart runs "
                  "it, or move it to HART0_ONLY_IMAGES." % name)
            return 1
        elves[name] = path
    missing = sorted(set(SHARED_IMAGES) - set(elves))
    if missing:
        print("check_tile_isa: FAIL - SHARED_IMAGES lists %s but the test was "
              "handed no ELF for them." % ", ".join(missing))
        return 1

    print("check_tile_isa: hart classes from %s" % args.resolved)
    for hc in classes:
        print("  %-14s harts %-6s %s" % (hc.get("name"), hc.get("harts"),
                                         hc.get("isaString")))
    print("  tile subset: %s" % " ".join(sorted(tileTokens)))
    print("  dropped on the tiles: %s"
          % (" ".join(sorted(fullTokens - tileTokens)) or "(nothing)"))

    bad = []
    for name in sorted(elves):
        path = elves[name]
        if not os.path.isfile(path):
            bad.append("%s: no such ELF: %s" % (name, path))
            continue
        rows = checkImage(name, path, args.objdump, allowed, denied)
        bad.extend(rows)
        if not rows:
            print("  OK  %-14s %s" % (name, path))
    for name in sorted(HART0_ONLY_IMAGES):
        print("  --  %-14s exempt: hart 0 only" % name)

    if bad:
        print("")
        print("check_tile_isa: FAIL - %d instruction(s) outside the tile ISA "
              "subset %s:" % (len(bad), classes[-1]["isaString"]))
        for line in bad:
            print("  " + line)
        print("")
        print("Fix the -march of the image that emitted it (the shared images "
              "are pinned to the tile subset on purpose), or, if the image "
              "really does run on hart 0 alone, move it to "
              "HART0_ONLY_IMAGES with the reason.")
        return 1

    print("check_tile_isa: OK - %d shared image(s) stay inside %s"
          % (len(elves), classes[-1]["isaString"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
