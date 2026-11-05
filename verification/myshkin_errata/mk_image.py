#!/usr/bin/python3.6
"""ELF to one 32-bit hex word per line, word 0 at 0x8000. usage: mk_image.py <elf> <hex>"""
import struct
import subprocess
import sys

elf, out = sys.argv[1:3]
img = bytearray(0x2000)
heads = subprocess.check_output(['riscv-none-elf-objdump', '-h', elf]).decode().split('\n')
for sec in ('.text', '.ldata'):
    subprocess.check_call(['riscv-none-elf-objcopy', '-O', 'binary', '-j', sec, elf, 's.bin'])
    rows = [l.split() for l in heads if len(l.split()) > 3 and l.split()[1] == sec]
    if not rows:
        continue
    row = rows[0]
    vma = int(row[3], 16)
    data = open('s.bin', 'rb').read()
    img[vma - 0x8000:vma - 0x8000 + len(data)] = data
words = struct.unpack('<%dI' % (len(img) // 4), bytes(img))
open(out, 'w').write(''.join('%08X\n' % w for w in words))
