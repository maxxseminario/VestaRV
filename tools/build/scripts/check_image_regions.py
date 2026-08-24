#!/usr/bin/env python3
"""Check that every allocated section of a linked firmware image lies inside a
memory region the CURRENT chip memory map declares.

WHY THIS EXISTS.
A firmware image is linked through a linker script, and a linker script is a
hand-maintained description of the chip.
When the chip's memory shrinks and the linker script does not, the link still
succeeds and the image is still byte-reproducible, but it addresses memory the
part does not have.
That is what happened to the boot ROM: tools/build/linker-scripts/memory.x was
frozen on 2026/04/20 describing a 16 KiB TCM, the real TCM halved to 8 KiB on
2026-08-16, and flashboot's .noinit ran 16,060 bytes past the end of RAM for
over a week without a single red gate.

So this check never reads a linker script for its bar.
It reads the machine-readable memory map the chip generator emits, and it reads
the section headers of the actual ELF.
A linker script that lies cannot fool it, because the linker script is not an
input to the comparison.

WHAT COUNTS AS A VIOLATION.
An allocated section (SHF_ALLOC) of nonzero size whose address range
[addr, addr + size) is not fully contained in one declared region.
  * NOBITS sections count.  .bss and .noinit occupy no file space but they
    occupy address space at run time, which is precisely the resource that ran
    out.  The defect that motivated this check is a NOBITS section.
  * Zero-size sections do not count.  The blinky-family images carry dozens of
    empty placeholder sections (.__interrupt_vector_N, .NN0SRAM, the AFE
    histogram windows) that a linker leaves at whatever address the script
    named; they address nothing and are not a runtime hazard.
  * Non-allocated sections do not count.  .comment, .debug_*, .symtab and the
    .riscv.attributes note are file metadata, never loaded.
  * A section in the NPU staging RAM or the shared RAM window is NOT an
    overrun.  Those are declared regions and images place things there on
    purpose (dbg_trampoline lives at 0x10780).  The bar is "inside SOME
    declared region", not "inside the TCM".

WHERE THE REGIONS COME FROM.
platform/common/config/MemoryMap.json is authoritative for ROM, the peripheral
window and the TCM.  It does not name the two arbitrated windows, so NPU_RAM
and SHARED_RAM are read out of the generated linker fragment
platform/common/out/linker-scripts/memory.x, which the same generator writes
from the same configuration in the same run.
The two are cross-checked before either is used: memory.x's ROM and TCM windows
must agree with the JSON to the byte.  A doctored memory.x therefore fails here
rather than widening the bar it is supposed to enforce.

Plain runner, no test framework: exit 0 passes, non zero fails.
That is the repository convention for python checks here.
"""

import argparse
import json
import re
import struct
import sys

SHF_ALLOC = 0x2
SHT_NOBITS = 8

# The discard window every MCU.ld image throws unwanted output at. It is not
# memory, it is a bit bucket, so a section landing there is not an overrun.
DISCARD_REGION = "UNUSED"


class Region(object):
    """One declared memory window, inclusive of both ends."""

    def __init__(self, name, start, end, note):
        self.name = name
        self.start = start
        self.end = end
        self.note = note

    def contains(self, addr, size):
        return addr >= self.start and (addr + size - 1) <= self.end

    def __str__(self):
        return "%-12s 0x%08X-0x%08X (%d bytes)%s" % (
            self.name, self.start, self.end, self.end - self.start + 1,
            ("  " + self.note) if self.note else "")


class Section(object):
    """One ELF section header, reduced to what this check needs."""

    def __init__(self, name, addr, size, flags, sectionType):
        self.name = name
        self.addr = addr
        self.size = size
        self.flags = flags
        self.sectionType = sectionType

    @property
    def allocated(self):
        return bool(self.flags & SHF_ALLOC)

    @property
    def nobits(self):
        return self.sectionType == SHT_NOBITS

    @property
    def end(self):
        return self.addr + self.size - 1


def readSections(path):
    """Every section header of a 32-bit little-endian RISC-V ELF.

    The section headers are parsed here rather than shelled out to readelf so
    the check has no toolchain dependency and can run in any sandbox.
    """
    with open(path, "rb") as f:
        data = f.read()

    if data[:4] != b"\x7fELF":
        raise ValueError("%s is not an ELF file" % path)
    if data[4] != 1:
        raise ValueError("%s is not ELF32; this check handles rv32 images" % path)
    if data[5] != 1:
        raise ValueError("%s is not little-endian" % path)

    # e_shoff, e_shentsize, e_shnum, e_shstrndx from the ELF32 header.
    shoff = struct.unpack_from("<I", data, 0x20)[0]
    shentsize = struct.unpack_from("<H", data, 0x2E)[0]
    shnum = struct.unpack_from("<H", data, 0x30)[0]
    shstrndx = struct.unpack_from("<H", data, 0x32)[0]

    raw = []
    for i in range(shnum):
        base = shoff + i * shentsize
        nameOff, sectionType, flags, addr, off, size = struct.unpack_from(
            "<IIIIII", data, base)
        raw.append((nameOff, sectionType, flags, addr, size))

    # The section-name string table's file offset lives in its own header.
    base = shoff + shstrndx * shentsize
    strOff = struct.unpack_from("<I", data, base + 0x10)[0]
    strSize = struct.unpack_from("<I", data, base + 0x14)[0]
    strTab = data[strOff:strOff + strSize]

    sections = []
    for nameOff, sectionType, flags, addr, size in raw:
        end = strTab.find(b"\x00", nameOff)
        name = strTab[nameOff:end].decode("utf-8", "replace")
        sections.append(Section(name, addr, size, flags, sectionType))
    return sections


MEMORY_LINE = re.compile(
    r"^\s*(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(\([^)]*\))?\s*:\s*"
    r"ORIGIN\s*=\s*(?P<origin>0[xX][0-9A-Fa-f]+|\d+)\s*,\s*"
    r"LENGTH\s*=\s*(?P<length>0[xX][0-9A-Fa-f]+|\d+)")


def readGeneratedMemoryX(path):
    """The MEMORY{} block of a generated memory.x, as {name: (origin, length)}."""
    out = {}
    inBlock = False
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            stripped = line.strip()
            if not inBlock:
                if stripped.startswith("MEMORY"):
                    inBlock = True
                continue
            if stripped.startswith("}"):
                break
            m = MEMORY_LINE.match(line)
            if m:
                out[m.group("name")] = (int(m.group("origin"), 0),
                                        int(m.group("length"), 0))
    if not out:
        raise ValueError("no MEMORY{} entries parsed out of %s" % path)
    return out


def buildRegions(mapJsonPath, memoryXPath):
    """The declared regions, and the cross-check that the two sources agree.

    Returns (regions, complaints). A non-empty complaints list is a failure in
    its own right: it means the generated linker fragment no longer describes
    the same chip as the generated memory map, so neither can be trusted as the
    bar for anything.
    """
    with open(mapJsonPath, "r", encoding="utf-8") as f:
        chip = json.load(f)
    mem = readGeneratedMemoryX(memoryXPath)
    complaints = []

    romStart = chip["RomStartAddress"]
    romEnd = chip["RomEndAddress"]
    ramStart = chip["RamStartAddress"]
    ramEnd = chip["RamEndAddress"]
    perStart = chip["PeripheralMemoryStartAddress"]
    perEnd = chip["PeripheralMemoryEndAddress"]

    # The JSON is authoritative. memory.x has to agree with it or the pair is
    # not describing one chip.
    if "ROM" in mem:
        o, l = mem["ROM"]
        if (o, o + l - 1) != (romStart, romEnd):
            complaints.append(
                "memory.x ROM is 0x%X-0x%X but MemoryMap.json says 0x%X-0x%X"
                % (o, o + l - 1, romStart, romEnd))
    else:
        complaints.append("memory.x declares no ROM region")

    # The TCM is one contiguous block in the JSON. memory.x carves it into a
    # vectors window plus a RAM window plus the per-vector slots, so the check
    # is that the carve-up starts and ends where the JSON's TCM does.
    tcmPieces = [mem[n] for n in ("vectors", "RAM") if n in mem]
    if len(tcmPieces) == 2:
        lo = min(o for o, _ in tcmPieces)
        hi = max(o + l - 1 for o, l in tcmPieces)
        if (lo, hi) != (ramStart, ramEnd):
            complaints.append(
                "memory.x vectors+RAM span 0x%X-0x%X but MemoryMap.json TCM is "
                "0x%X-0x%X" % (lo, hi, ramStart, ramEnd))
    else:
        complaints.append("memory.x declares no vectors and RAM pair")

    regions = [
        Region("ROM", romStart, romEnd, "MemoryMap.json RomStartAddress/RomEndAddress"),
        Region("PERIPHERAL", perStart, perEnd, "MemoryMap.json peripheral window"),
        Region("TCM", ramStart, ramEnd,
               "MemoryMap.json RamStartAddress/RamEndAddress; vectors and RAM "
               "are sub-windows of it"),
    ]

    # The two arbitrated windows the JSON does not name.
    for name in ("NPU_RAM", "SHARED_RAM", DISCARD_REGION):
        if name in mem:
            o, l = mem[name]
            note = "generated memory.x"
            if name == DISCARD_REGION:
                note = "generated memory.x; the linker's discard window, not memory"
            regions.append(Region(name, o, o + l - 1, note))

    regions.sort(key=lambda r: r.start)
    return regions, complaints


def checkImage(path, regions):
    """One image's section headers and the subset that does not fit."""
    sections = readSections(path)
    bad = []
    for s in sections:
        if not s.allocated or s.size == 0:
            continue
        if any(r.contains(s.addr, s.size) for r in regions):
            continue
        bad.append(s)
    return sections, bad


def describeViolation(s, regions):
    """Why one section does not fit, in bytes, naming the region it belongs to."""
    # The region it most plausibly meant: the one whose start it is inside, or
    # failing that the nearest region below it.
    home = None
    for r in regions:
        if r.start <= s.addr <= r.end:
            home = r
            break
    lines = []
    kind = "NOBITS" if s.nobits else "PROGBITS"
    lines.append(
        "    %-24s %-8s 0x%08X-0x%08X  %d bytes"
        % (s.name, kind, s.addr, s.end, s.size))
    if home is not None:
        over = s.end - home.end
        lines.append(
            "        starts inside %s (0x%08X-0x%08X) and runs %d bytes past "
            "its end" % (home.name, home.start, home.end, over))
    else:
        lines.append(
            "        starts at 0x%08X, which is not inside any declared region"
            % s.addr)
        nearest = None
        for r in regions:
            if r.end < s.addr and (nearest is None or r.end > nearest.end):
                nearest = r
        if nearest is not None:
            lines.append(
                "        nearest region below is %s, ending 0x%08X, %d bytes "
                "lower" % (nearest.name, nearest.end, s.addr - nearest.end))
    if s.nobits:
        lines.append(
            "        NOBITS: no file space, but it occupies this address range "
            "at run time")
    return lines


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--memory-map-json", required=True,
                   help="the generated config/MemoryMap.json")
    p.add_argument("--memory-x", required=True,
                   help="the generated out/linker-scripts/memory.x")
    p.add_argument("--min-images", type=int, default=1,
                   help="fail if fewer images than this were examined; a "
                        "sweep that silently shrinks is not a sweep")
    p.add_argument("--require-nobits", action="store_true",
                   help="fail unless at least one allocated NOBITS section was "
                        "examined; the control that proves the check really "
                        "does look at .bss/.noinit, which is the section class "
                        "the motivating defect lived in")
    p.add_argument("--verbose", action="store_true")
    p.add_argument("images", nargs="+", metavar="IMAGE",
                   help="linked ELF images; a $(rootpaths) expansion of a "
                        "filegroup lands here as one path per element")
    args = p.parse_args()

    regions, complaints = buildRegions(args.memory_map_json, args.memory_x)

    print("Declared memory regions (the chip, not any linker script):")
    for r in regions:
        print("  " + str(r))
    print("")

    if complaints:
        print("FAIL: the generated memory map and the generated linker fragment")
        print("do not describe the same chip, so neither can be a bar:")
        for c in complaints:
            print("  * " + c)
        return 1

    images = sorted(set(args.images))
    if len(images) < args.min_images:
        print("FAIL: was handed %d image(s), expected at least %d."
              % (len(images), args.min_images))
        print("The image set this check sweeps shrank. Either targets were "
              "removed or the data list stopped resolving; a check that "
              "quietly stops looking is worse than no check.")
        return 1

    failures = []
    nobitsSeen = 0
    for path in images:
        label = path
        sections, bad = checkImage(path, regions)
        allocated = [s for s in sections if s.allocated and s.size > 0]
        nobitsSeen += len([s for s in allocated if s.nobits])
        if bad:
            failures.append((label, bad))
            print("FAIL %s  (%d allocated sections, %d out of bounds)"
                  % (label, len(allocated), len(bad)))
            for s in bad:
                for line in describeViolation(s, regions):
                    print(line)
        else:
            print("ok   %s  (%d allocated sections, all in bounds)"
                  % (label, len(allocated)))
            if args.verbose:
                for s in allocated:
                    home = next(r.name for r in regions
                                if r.contains(s.addr, s.size))
                    print("    %-24s 0x%08X-0x%08X  %-10s in %s"
                          % (s.name, s.addr, s.end,
                             "NOBITS" if s.nobits else "PROGBITS", home))

    print("")
    if args.require_nobits and nobitsSeen == 0:
        print("FAIL: not one allocated NOBITS section was examined.")
        print("The motivating defect was a NOBITS section (.noinit), so a "
              "sweep that sees none is not exercising the case it exists for.")
        return 1

    if failures:
        total = sum(len(b) for _, b in failures)
        print("FAIL: %d of %d images place %d allocated section(s) outside every"
              % (len(failures), len(images), total))
        print("region the current chip memory map declares.")
        print("")
        print("An image that links cleanly and reproduces byte for byte can still")
        print("address memory the part does not have: the linker script is a")
        print("description of the chip, and descriptions go stale.  Fix the image")
        print("or the linker script it links through, not this check.")
        return 1

    print("PASS: all %d image(s) fit the regions the current chip memory map "
          "declares." % len(images))
    return 0


if __name__ == "__main__":
    sys.exit(main())
