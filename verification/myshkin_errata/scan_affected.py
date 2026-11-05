#!/usr/bin/python3.6
"""Find the two defective encodings in the disassembly of an ELF, object or archive.

usage: scan_affected.py <file> [<file> ...]

Prints one line per hit and a per-file count. `xori rd,rs1,0x80` is defective for any rd;
`c.lui x0,nzimm` is a HINT the defective decoder traps on. objdump prints the raw encoding,
so the match is on bits, never on mnemonics.
"""
import re
import subprocess
import sys

ROW = re.compile(r'^\s*([0-9a-f]+):\s+([0-9a-f]{4,8})\s+(.*)$')


def affected(word, width):
    if width == 8:
        return (word & 0xFFF0707F) == 0x08004013
    return (word & 0xEF83) == 0x6001 and ((word >> 2) & 0x1F | (word >> 7) & 0x20) != 0


total = 0
for path in sys.argv[1:]:
    # -d reads executable sections only; a raw ROM image has none, so it is decoded whole.
    how = ['-D', '-b', 'binary', '-m', 'riscv:rv32'] if path.endswith('.bin') else ['-d']
    text = subprocess.check_output(
        ['riscv-none-elf-objdump'] + how + ['-M', 'no-aliases', path]).decode(errors='replace')
    hits = []
    member = ''
    for line in text.split('\n'):
        if ' file format ' in line:
            member = line.split(':')[0]
        match = ROW.match(line)
        if match and affected(int(match.group(2), 16), len(match.group(2))):
            hits.append((member, match.group(1), match.group(2), match.group(3).strip()))
    for hit in hits:
        print('  %s %s %s %s' % hit)
    print('%s: %d' % (path, len(hits)))
    total += len(hits)
print('total: %d' % total)
