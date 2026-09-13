#!/usr/bin/env python3
# VestaRV: riscv_tb.vhd drop-in checker.
# Compares the generated out/hdl/riscv_tb.vhd against hdl/common/tb/riscv_tb.vhd. As in
# check_mcu_vhd.py the bar is byte-identical apart from the generated-file comment header,
# which proves the testbench generator is a no-op at numHarts=4. --structural relaxes to
# whitespace-normalized, comment-stripped tokens, a diagnostic aid and not the bar.
# Python 3.6 compatible.

import difflib
import os
import sys


def stripHeader(lines):
	'''Remove the leading comment block and the blank lines after it. Both VHDL comment styles are
	recognized: the generated header is a /* ... */ block, older masters wrote a run of -- lines.
	'''
	i = 0
	inBlock = False
	while i < len(lines):
		stripped = lines[i].strip()
		if inBlock:
			if '*/' in stripped:
				inBlock = False
			i += 1
			continue
		if stripped == '' or stripped.startswith('--'):
			i += 1
			continue
		if stripped.startswith('/*'):
			if '*/' not in stripped[2:]:
				inBlock = True
			i += 1
			continue
		break
	return lines[i:]


def stripBlockComments(lines):
	'''Drop every /* ... */ span (they may run across lines).'''
	out = []
	inBlock = False
	for line in lines:
		if inBlock:
			end = line.find('*/')
			if end < 0:
				out.append('')
				continue
			line = line[end + 2:]
			inBlock = False
		start = line.find('/*')
		while start >= 0:
			end = line.find('*/', start + 2)
			if end < 0:
				line = line[:start]
				inBlock = True
				break
			line = line[:start] + line[end + 2:]
			start = line.find('/*')
		out.append(line)
	return out


def normalizeStructural(lines):
	'''Whitespace-normalized, comment-stripped, blank-line-free view.'''
	out = []
	for line in stripBlockComments(lines):
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
