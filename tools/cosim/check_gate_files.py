#!/usr/bin/python3.6
# check_gate_files.py — lockstep-gate infrastructure drift checker.
#
# WHY THIS EXISTS
# ---------------
# The two standing lockstep gates and the 136-test behavioural suite are driven
# by scripts and lists that live under `xcelium/`, and `.gitignore:312`'s bare
# `xcelium/` rule (a deliberate 2026-07-18 decision) means git tracks NONE of
# them. A `git clean -xdf` deletes the entire gate apparatus. That is not
# theoretical: at W5 (2026-07-31) the pass measured TWO live consequences of it —
#
#   * amendment A10's correction to the boot x-wildcard substitution
#     (`00004000:000000b0` -> `...b1`, a value that had been silently
#     overwriting a bit the RTL actually drives since V3) existed ONLY on disk,
#     in `xrun_cosim.sh`; and
#   * the V4 missing-plant negative control, `RERUN.sh`, lived only in a session
#     scratchpad OUTSIDE the repo, still carried the pre-A10 value, and had
#     therefore stopped executing entirely (mk_inject EXIT_REFUSED, rc=5).
#
# This is the same canonical-copy-plus-verifier idiom the project already uses
# for the generated `MCU.vhd` (`platform/common/python/check_mcu_vhd.py`): the
# tracked copy under `tools/cosim/gate/` is the record, the copy under
# `xcelium/` is what actually runs, and THIS SCRIPT MAKES A DIVERGENCE LOUD.
# `.gitignore` is deliberately NOT touched — a plain negation cannot work, since
# git will not re-include a file whose parent directory is excluded.
#
# EXIT CODES
#   0  every canonical copy matches its live copy (or has no live counterpart)
#   1  DRIFT — at least one pair differs; a unified diff is printed
#   2  a file is missing on one side
#
# USAGE (from anywhere; paths are resolved from this file's location)
#   /usr/bin/python3.6 tools/cosim/check_gate_files.py            # check
#   /usr/bin/python3.6 tools/cosim/check_gate_files.py --update   # live -> canonical
#   /usr/bin/python3.6 tools/cosim/check_gate_files.py --restore  # canonical -> live
#
#   --update  records an INTENTIONAL change to a gate file. Run it, then COMMIT
#             the canonical copy in the same commit as whatever motivated the
#             change. It is the only sanctioned way to move the record.
#   --restore is what a fresh clone (or a post-`git clean` tree) needs. It
#             refuses to overwrite a live file that differs unless --force is
#             also given, so it cannot silently discard an uncommitted fix — the
#             exact accident this checker exists to catch.
#
# Never `python3` (kickoff invariant 6): `python3` on this host may be Calibre's
# aoj_cal wrapper, which re-evals its arguments and strips quotes.
#
# Python 3.6 compatible.

import difflib
import os
import shutil
import stat
import sys


# canonical basename -> live path, relative to the repo root.
# The live side of every entry is inside the gitignored `xcelium/` tree; an
# entry whose live path is None is canonical-only (nothing runs it in place).
GATE_FILES = [
    ('xrun_cosim.sh',
     'xcelium/riscv_test/behavioral_mp/xrun_cosim.sh',
     'the lockstep gate runner — BOTH standing gates, the participation and '
     'launch-margin audits, and the A9/A10 boot allowlist values'),
    ('xrun_parallel.sh',
     'xcelium/riscv_test/behavioral_mp/xrun_parallel.sh',
     'the 136-test behavioural suite runner (its TEST_FILES list IS the suite)'),
    ('cosim_tests.txt',
     'xcelium/riscv_test/behavioral_mp/cosim_tests.txt',
     'the single-hart gate list (105 tests)'),
    ('cosim_sh_tests.txt',
     'xcelium/riscv_test/behavioral_mp/cosim_sh_tests.txt',
     'the multi-hart gate list (17 sh* tests x 4 harts = 68 cells)'),
    ('cosim_xallow.txt',
     'xcelium/riscv_test/behavioral_mp/cosim_xallow.txt',
     'the amendment A9 x-wildcard allowlist AND its written rationale'),
    ('negctrl_RERUN.sh',
     None,
     'the V4 missing-plant negative control — runs from the tracked copy'),
]


def repoRoot():
	here = os.path.dirname(os.path.abspath(__file__))
	return os.path.abspath(os.path.join(here, '..', '..'))


def gateDir():
	return os.path.join(repoRoot(), 'tools', 'cosim', 'gate')


def readLines(path):
	with open(path, 'r', newline='') as f:
		return f.read().split('\n')


def copyPreservingMode(src, dst):
	shutil.copyfile(src, dst)
	srcMode = os.stat(src).st_mode
	if srcMode & stat.S_IXUSR:
		os.chmod(dst, os.stat(dst).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def main():
	argv = sys.argv[1:]
	update = '--update' in argv
	restore = '--restore' in argv
	force = '--force' in argv
	maxShow = 60

	if update and restore:
		print('check_gate_files: --update and --restore are mutually exclusive')
		return 2

	root = repoRoot()
	canonDir = gateDir()
	if not os.path.isdir(canonDir):
		print('MISSING canonical directory: ' + canonDir)
		return 2

	drift = []
	missing = []
	matched = 0
	canonicalOnly = 0

	for name, liveRel, what in GATE_FILES:
		canonPath = os.path.join(canonDir, name)
		if not os.path.isfile(canonPath):
			print('MISSING canonical copy: ' + canonPath + '   (' + what + ')')
			missing.append(name)
			continue

		if liveRel is None:
			canonicalOnly += 1
			print('  canonical-only  ' + name + '   (' + what + ')')
			continue

		livePath = os.path.join(root, liveRel)

		if restore:
			if os.path.isfile(livePath) and readLines(livePath) != readLines(canonPath) and not force:
				print('REFUSING to overwrite a DIFFERING live copy: ' + liveRel)
				print('  The live file is not the canonical one. If the live version is the')
				print('  correct one, run --update to record it. If you really mean to discard')
				print('  it, re-run --restore --force.')
				drift.append(name)
				continue
			copyPreservingMode(canonPath, livePath)
			print('  restored  ' + liveRel)
			matched += 1
			continue

		if not os.path.isfile(livePath):
			print('MISSING live copy: ' + livePath)
			print('  (' + what + ')')
			print('  A fresh clone or a `git clean -xdf` produces exactly this. Recover with:')
			print('    /usr/bin/python3.6 tools/cosim/check_gate_files.py --restore')
			missing.append(name)
			continue

		canon = readLines(canonPath)
		live = readLines(livePath)

		if canon == live:
			matched += 1
			continue

		if update:
			copyPreservingMode(livePath, canonPath)
			print('  UPDATED canonical copy from live: ' + name)
			print('    COMMIT tools/cosim/gate/' + name + ' with the change that motivated it.')
			matched += 1
			continue

		drift.append(name)
		diff = list(difflib.unified_diff(
			canon, live,
			fromfile='tools/cosim/gate/' + name + '  (canonical, tracked)',
			tofile=liveRel + '  (live, gitignored)',
			lineterm=''))
		changed = [d for d in diff
		           if (d.startswith('+') and not d.startswith('+++'))
		           or (d.startswith('-') and not d.startswith('---'))]
		print('')
		print('DRIFT: ' + name + '  — ' + str(len(changed)) + ' differing line(s)')
		print('  ' + what)
		for d in diff[:maxShow]:
			print('  ' + d.replace('\t', '\\t'))
		if len(diff) > maxShow:
			print('  ... (' + str(len(diff) - maxShow) + ' more diff lines suppressed)')

	print('')
	if missing:
		print('check_gate_files: MISSING ' + str(len(missing)) + ' file(s): ' + ', '.join(missing))
		return 2
	if drift:
		print('=' * 78)
		print('check_gate_files: DRIFT in ' + str(len(drift)) + ' gate file(s): ' + ', '.join(drift))
		print('')
		print('  The live gate infrastructure no longer matches the tracked record.')
		print('  This is NOT a formatting nit: these files decide which tests run, what')
		print('  the reference model is fed, and what the comparator forgives. A drifted')
		print('  copy means the pinned gate numbers in CLAUDE.md describe a different')
		print('  experiment from the one on disk.')
		print('')
		print('  If the LIVE version is correct (you changed a gate deliberately):')
		print('    /usr/bin/python3.6 tools/cosim/check_gate_files.py --update')
		print('    git add tools/cosim/gate/ && commit it WITH the change that caused it.')
		print('  If the CANONICAL version is correct (the live tree drifted or was cleaned):')
		print('    /usr/bin/python3.6 tools/cosim/check_gate_files.py --restore')
		print('=' * 78)
		return 1

	print('check_gate_files: OK — ' + str(matched) + ' gate file(s) match the tracked record'
	      + (', ' + str(canonicalOnly) + ' canonical-only' if canonicalOnly else ''))
	return 0


if __name__ == '__main__':
	sys.exit(main())
