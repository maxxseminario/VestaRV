#!/usr/bin/env python3
# check_riscv_tb_vhd.py — riscv_tb.vhd drop-in checker (Argus A3, tb-generation)
#
# Compares the generated out/hdl/riscv_tb.vhd (from tb_vhd.py) against the
# hand-written RTL hdl/common/tb/riscv_tb.vhd. Like check_mcu_vhd.py the bar is
# BYTE-IDENTICAL apart from the generated-file comment header, so the default
# mode strips the leading comment block (and following blanks) from both files
# then requires an exact match. Exit 0 = drop-in compatible (proves the tb
# generator is a no-op at numHarts=4).
#
# --structural relaxes to whitespace-normalized, comment-stripped tokens (a
# diagnostic aid, NOT the drop-in bar).
#
# Usage (from platform/common/):
#   python3 python/check_riscv_tb_vhd.py [--structural] [generated.vhd] [rtl.vhd]
#
# Python 3.6 compatible.

import difflib
import os
import sys


def stripHeader(lines):
	'''Remove the leading comment block and following blank lines.'''
	i = 0
	while i < len(lines) and (lines[i].lstrip().startswith('--') or lines[i].strip() == ''):
		i += 1
	return lines[i:]


def normalizeStructural(lines):
	'''Whitespace-normalized, comment-stripped, blank-line-free view.'''
	out = []
	for line in lines:
		commentIndex = line.find('--')
		if commentIndex >= 0:
			line = line[:commentIndex]
		line = ' '.join(line.split())
		if line != '':
			out.append(line)
	return out


def main():
	args = [a for a in sys.argv[1:] if not a.startswith('-')]
	structural = '--structural' in sys.argv[1:]

	here = os.path.dirname(os.path.abspath(__file__))
	genPath = args[0] if len(args) > 0 else os.path.join(here, '..', 'out', 'hdl', 'riscv_tb.vhd')
	rtlPath = args[1] if len(args) > 1 else os.path.join(here, '..', '..', '..', 'hdl', 'common', 'tb', 'riscv_tb.vhd')

	for p in (genPath, rtlPath):
		if not os.path.isfile(p):
			print('MISSING FILE: ' + p)
			return 2

	with open(genPath, 'r', newline='') as f:
		gen = f.read().split('\n')
	with open(rtlPath, 'r', newline='') as f:
		rtl = f.read().split('\n')

	gen = stripHeader(gen)
	rtl = stripHeader(rtl)

	if structural:
		gen = normalizeStructural(gen)
		rtl = normalizeStructural(rtl)
		label = 'STRUCTURAL'
	else:
		label = 'STRICT'

	if gen == rtl:
		print('riscv_tb.vhd check (' + label + '): IDENTICAL (' + str(len(rtl)) + ' lines) — drop-in compatible'
			+ ('' if not structural else ' at token level (run without --structural for the real bar)'))
		return 0

	diff = list(difflib.unified_diff(rtl, gen, fromfile='rtl/riscv_tb.vhd', tofile='generated/riscv_tb.vhd', lineterm=''))
	changed = [d for d in diff if d.startswith('+') or d.startswith('-')]
	print('riscv_tb.vhd check (' + label + '): DIFFERS — ' + str(len(changed)) + ' diff lines')
	maxShow = 80
	for d in diff[:maxShow]:
		print(d.replace('\t', '\\t'))
	if len(diff) > maxShow:
		print('... (' + str(len(diff) - maxShow) + ' more diff lines suppressed)')
	return 1


if __name__ == '__main__':
	sys.exit(main())
