#!/usr/bin/env python3
# check_mcu_vhd.py — MCU.vhd drop-in checker (RTL-generation track, Phase 2)
#
# Compares the generated out/hdl/MCU.vhd against the hand-written RTL
# hdl/common/MCU.vhd. The Phase-2 drop-in bar is BYTE-IDENTICAL apart from the
# generated-file comment header, so the default mode strips the leading comment
# block (and any blank lines that follow it) from both files and then requires
# an exact match. Exit 0 = drop-in compatible.
#
# --structural relaxes the comparison to whitespace-normalized, comment-stripped
# tokens — useful while iterating on the generator to separate "wrong logic"
# from "wrong formatting". A structural pass is NOT the drop-in bar.
#
# Usage (from platform/common/):
#   python3 python/check_mcu_vhd.py [--structural] [generated.vhd] [rtl.vhd]
#
# Python 3.6 compatible.

import difflib
import os
import sys


def stripHeader(lines):
	'''Remove the leading comment block and following blank lines.'''
	i = 0
	while i < len(lines) and (lines[i].lstrip().startswith('--') or lines[i].strip() == ''):
		# Stop as soon as we hit real code; the header is only comments/blanks
		# BEFORE the first non-comment line.
		i += 1
	# Everything before the first code line is header (comments + blanks)
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
	genPath = args[0] if len(args) > 0 else os.path.join(here, '..', 'out', 'hdl', 'MCU.vhd')
	rtlPath = args[1] if len(args) > 1 else os.path.join(here, '..', '..', '..', 'hdl', 'common', 'MCU.vhd')

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
		print('MCU.vhd check (' + label + '): IDENTICAL (' + str(len(rtl)) + ' lines) — drop-in compatible'
			+ ('' if not structural else ' at token level (run without --structural for the real bar)'))
		return 0

	diff = list(difflib.unified_diff(rtl, gen, fromfile='rtl/MCU.vhd', tofile='generated/MCU.vhd', lineterm=''))
	# Count differing lines (added/removed)
	changed = [d for d in diff if d.startswith('+') or d.startswith('-')]
	print('MCU.vhd check (' + label + '): DIFFERS — ' + str(len(changed)) + ' diff lines')
	maxShow = 80
	for d in diff[:maxShow]:
		# Make whitespace differences visible
		print(d.replace('\t', '\\t'))
	if len(diff) > maxShow:
		print('... (' + str(len(diff) - maxShow) + ' more diff lines suppressed)')
	return 1


if __name__ == '__main__':
	sys.exit(main())
