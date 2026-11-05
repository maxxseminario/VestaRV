#!/usr/bin/python3.6
"""Wrap a 32-bit-per-line binary .rcf ROM image in an ELF so scan_affected.py can read it.

usage: rcf_to_elf.py <rom.rcf> <out.elf>
"""
import struct
import subprocess
import sys

rcf, elf = sys.argv[1:3]
words = [int(line.strip(), 2) for line in open(rcf) if line.strip()]
last = max(i for i, word in enumerate(words) if word) + 1
open(elf + '.bin', 'wb').write(struct.pack('<%dI' % last, *words[:last]))
subprocess.check_call(['riscv-none-elf-objcopy', '-I', 'binary', '-O', 'elf32-littleriscv',
                       '--rename-section', '.data=.text,code', elf + '.bin', elf])
print('%s: %d used words; word 13 %08x, word 30 %08x' % (rcf, last, words[13], words[30]))
