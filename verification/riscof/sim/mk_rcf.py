#!/usr/bin/python3.6
"""ELF -> flash .rcf for the VestaRV bootrom, with the target hart patched in.

Two load modes. `flash`: everything goes through the bootrom's SPI load, about
24 us of sim time per word. `preload`: only the TCM launcher goes through flash;
the shared-RAM body is written to bankN.rcf, which the sim bakes into the bulk RAM
macros at elaboration. Execution is identical either way; sim time is not.

Stream: {0x10ADBEEF, start, end(exclusive), words...}* 0xCAFEBABE, one 32-bit
binary string per line. The 0x8000-0x81FF zero segment comes first, as in
verification/isa/flash_prepend.sh. Only the patched word differs between the
images of one test on different harts, so every hart runs the same bytes.
Usage: mk_rcf.py <elf> <out.rcf> <hart> [flash|preload]
"""
import os
import struct
import sys

LOAD_CMD = 0x10ADBEEF
EXEC_CMD = 0xCAFEBABE
GAP_BYTES = 32
BULK_BASE = 0x10000
BANK_BYTES = 0x4000
TCM_BASE = 0x8000
TCM_SHADOW = 0x1E000


def read_elf(path):
    d = open(path, 'rb').read()
    if d[:5] != b'\x7fELF\x01':
        sys.exit('mk_rcf: not ELF32: ' + path)
    shoff, = struct.unpack_from('<I', d, 32)
    shsz, shn = struct.unpack_from('<HH', d, 46)
    mem = {}
    syms = {}
    for i in range(shn):
        sh = struct.unpack_from('<10I', d, shoff + i * shsz)
        # Sections, not segments: a PT_LOAD also carries the ELF header bytes.
        if sh[2] & 2 and sh[3]:  # SHF_ALLOC with an address
            data = d[sh[4]:sh[4] + sh[5]] if sh[1] != 8 else b'\0' * sh[5]
            for k, b in enumerate(data):
                mem[sh[3] + k] = b
        if sh[1] == 2:  # SHT_SYMTAB
            stroff = struct.unpack_from('<10I', d, shoff + sh[6] * shsz)[4]
            for j in range(sh[5] // 16):
                nm, val = struct.unpack_from('<II', d, sh[4] + j * 16)
                e = d.index(b'\0', stroff + nm)
                syms[d[stroff + nm:e].decode()] = val
    return mem, syms


def main():
    elf, out, hart = sys.argv[1], sys.argv[2], int(sys.argv[3])
    mode = sys.argv[4] if len(sys.argv) > 4 else 'flash'
    mem, syms = read_elf(elf)
    addr = syms['vesta_target_hart']
    for k in range(4):
        mem[addr + k] = (hart >> (8 * k)) & 0xFF
    words = {}
    for a, b in mem.items():
        w = a & ~3
        words[w] = words.get(w, 0) | (b << (8 * (a & 3)))
    # Tiles load their TCM from this shadow through the bootrom loader.
    tcm_end = syms['vesta_tcm_end']
    for a in range(TCM_BASE, tcm_end, 4):
        words[TCM_SHADOW + a - TCM_BASE] = words.get(a, 0)
    if mode == 'preload':
        outdir = os.path.dirname(os.path.abspath(out))
        for bank in range(4):
            base = BULK_BASE + bank * BANK_BYTES
            with open(os.path.join(outdir, 'bank%d.rcf' % bank), 'w') as f:
                for a in range(base, base + BANK_BYTES, 4):
                    f.write('{:032b}\n'.format(words.get(a, 0)))
        words = {a: w for a, w in words.items() if a < BULK_BASE}
    segs = []
    for a in sorted(words):
        if segs and a - segs[-1][1] <= GAP_BYTES:
            segs[-1][1] = a + 4
        else:
            segs.append([a, a + 4])
    lines = [LOAD_CMD, 0x8000, 0x8200] + [0] * 128
    for s, e in segs:
        lines += [LOAD_CMD, s, e]
        lines += [words.get(a, 0) for a in range(s, e, 4)]
    lines.append(EXEC_CMD)
    with open(out, 'w') as f:
        for w in lines:
            f.write('{:032b}\n'.format(w))


if __name__ == '__main__':
    main()
