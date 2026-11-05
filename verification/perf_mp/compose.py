#!/usr/bin/env python3
"""Turn one or more bare-metal ELFs into the SPI-flash .rcf stream the Castalia boot ROM loads.

Stream format (software/bootrom_mp/src/start.S): any number of segments
    0x10adbeef, start, end(not inclusive), words...
then 0xcafebabe to execute. The ROM accepts 0x8000 <= addr and end <= 0x1FFFC.

Usage: compose.py out.rcf a.elf [b.elf@0x18000:0x8000 ...]
  a.elf                        load every PT_LOAD at its own address
  b.elf@STAGE:BASE             sections linked in [BASE, BASE+0x2000) (the TCM window) are loaded at
                               STAGE + (addr-BASE) instead: a tile image the bootrom loader copies later
Extra raw words: --word ADDR=VALUE (loaded after everything else).
"""
import struct
import sys

CMD = 0x10ADBEEF
EXEC = 0xCAFEBABE
TCM_SIZE = 0x2000


def segments(path):
    d = open(path, "rb").read()
    assert d[:4] == b"\x7fELF" and d[4] == 1, path
    phoff, = struct.unpack_from("<I", d, 28)
    phentsize, phnum = struct.unpack_from("<HH", d, 42)
    out = []
    for i in range(phnum):
        p_type, p_off, p_vaddr, p_paddr, p_filesz, p_memsz, _, _ = struct.unpack_from(
            "<8I", d, phoff + i * phentsize)
        if p_type == 1 and p_filesz:
            out.append((p_paddr, d[p_off:p_off + p_filesz]))
    return out


def main(argv):
    out = argv[0]
    mem = {}
    words = []
    specs = []
    for a in argv[1:]:
        if a.startswith("--word="):
            k, v = a[7:].split("=")
            words.append((int(k, 0), int(v, 0)))
        else:
            specs.append(a)
    for s in specs:
        stage = base = None
        if "@" in s:
            s, loc = s.split("@")
            stage, base = [int(x, 0) for x in loc.split(":")]
        for addr, blob in segments(s):
            for i, b in enumerate(blob):
                a = addr + i
                if stage is not None and base <= a < base + TCM_SIZE:
                    a = stage + (a - base)
                if a in mem and mem[a] != b:
                    raise SystemExit("overlap with different content at 0x%x (%s)" % (a, s))
                mem[a] = b
    for a, v in words:
        for i in range(4):
            mem[a + i] = (v >> (8 * i)) & 0xFF
    assert mem, "empty image"
    wordaddrs = sorted(set(a & ~3 for a in mem))
    regions = []
    for w in wordaddrs:
        if regions and w - regions[-1][1] <= 8 * 4:   # bridge short gaps
            regions[-1][1] = w + 4
        else:
            regions.append([w, w + 4])
    stream = []
    for lo, hi in regions:
        assert lo >= 0x8000 and hi <= 0x1FFFC, hex(hi)
        stream += [CMD, lo, hi]
        for a in range(lo, hi, 4):
            stream.append(sum(mem.get(a + i, 0) << (8 * i) for i in range(4)))
    stream.append(EXEC)
    with open(out, "w") as f:
        for w in stream:
            f.write("{:032b}\n".format(w))
    print("%s: %d regions, %d words: %s" % (out, len(regions), len(stream),
          " ".join("%x-%x" % (a, b) for a, b in regions)))


if __name__ == "__main__":
    main(sys.argv[1:])
