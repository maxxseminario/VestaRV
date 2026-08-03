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
#
# `.gitignore` NEGATIONS, and exactly when they work (amended at K2). For the
# `xcelium/` files a negation is IMPOSSIBLE: `.gitignore:312` excludes the
# DIRECTORY, and git will not re-include a file whose parent directory is
# excluded — that is why this whole canonical-copy idiom exists. But the rule is
# about directory exclusions, not about ignoring in general, and K2 hit the
# other case: `.gitignore:53 *.rcf` is a FILE-NAME rule, so the canonical boot
# ROM copy under `tools/cosim/gate/` was silently unaddable while this checker
# happily reported OK. One negation (`!tools/cosim/gate/*.rcf`) fixes that, and
# it is the only one. If you add a canonical copy whose name matches any
# file-name rule, CHECK `git status --ignored tools/cosim/gate/` — a canonical
# copy git is not tracking is worse than no canonical copy, because the checker
# passes.
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


# canonical name -> live path -> what it is.
#
# The canonical name is a path RELATIVE TO tools/cosim/gate/. The original six
# entries are flat basenames and stay that way (moving them would rewrite the
# record for no gain); everything K2 adds is filed under a directory named for
# the flow it belongs to, because the basenames collide across flows
# (`cell_list_behavioral.txt` exists in three of them, `cds.lib` in two).
#
# The live side is normally relative to the repo root and inside the gitignored
# `xcelium/` tree. Two exceptions, both deliberate:
#   * a live path of None is canonical-only (nothing runs it in place);
#   * a live path beginning `~/` is OUTSIDE the repository. `~/local/spike_env.sh`
#     is the only one: `xrun_cosim.sh` `die`s without it, it is 20 lines, and
#     nothing anywhere checked it until K2.
#
# WHAT IS DELIBERATELY *NOT* HERE, so the omissions are a decision and not an
# oversight (harness probe §3.6 tiers A-E):
#   * `verification/isa/rcf/**` + `rcf_argus/**` -- 496 generated images. They
#     are the DUT-side input of every gate and they ARE destroyed by
#     `git clean -xdf`, but they are build products, not source. What was
#     actually missing was the record of the exact `RISCV_GCC_OPTS` they were
#     built with; K2/G3 fixes that with a per-image-set `.imgset` stamp, which
#     is the right shape of answer.
#   * `cosim_work/vesta_ref` -- a compiled binary, rebuildable from the tracked
#     `vesta_ref.cc` + `build_vesta_ref.sh` against a pinned Spike.
#   * `~/local/bin/{spike,dtc}` and the conda env -- third-party installs.
#   * `cds.lib`, in EITHER behavioural flow (R-K2-3, 2026-08-03). It looks like
#     Tier A and it is not: both runners REGENERATE it unconditionally before
#     they use it --
#         xrun_parallel.sh:233   cat > "$BEHAVIORAL_DIR/cds.lib" <<LIB
#                                SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
#     (the Argus runner does the same at its line 204). This record protects what
#     CANNOT be regenerated; a machine-derived file that the consumer rewrites on
#     every run does not qualify, and keeping it would also have committed this
#     host's absolute Xcelium install path to a public repository.
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

    # K2b, 2026-08-03. The per-config KNOB-BEARING lockstep lists. They are
    # CANONICAL-ONLY on purpose: a live gitignored copy is what put the other
    # lists at risk in the first place, and nothing needs one here — the
    # runner takes an absolute TESTS_FILE, so these are read from the tracked
    # path directly and cannot drift from it.
    ('cosim_zfinx_tests.txt',
     None,
     'the K2b amendment-1 lockstep list (16 rv32uzf + extzfinx) — the '
     'ON-POLARITY-ONLY tests that make a Zfinx row COVERAGE and not just a '
     'plumbing control (R-K2-7 (2))'),
    ('cosim_zicboz_tests.txt',
     None,
     'the K2b amendment-2 lockstep list (extzicboz + shcboz) — the two tests '
     'that actually EXECUTE cbo.zero, incl. shcboz\'s two misaligned-rs1 cases'),
    ('cosim_zcmt_tests.txt',
     None,
     'the K2b amendment-2 lockstep list (extzcmt + shcmt) — the only two tests '
     'in the tree that execute a table jump (extjvt\'s ON arm executes none)'),

    # ---------------------------------------------------------------------
    # K2 (G10), 2026-08-03. Everything below was named by the K0 harness probe
    # §3.6 (tiers A-C) and the K0 inventory probe §5.5 (the six ON-polarity
    # test lists) as load-bearing, gitignored, and unprotected.
    # ---------------------------------------------------------------------

    # Tier A — WITHOUT THESE, `make verify` AND THE 136-TEST SUITE CANNOT RUN
    # AT ALL ON A FRESH CLONE. The first entry is the one that matters most:
    # verify_stage.py reads it as BASE_CELL_LIST and, until K2, its own error
    # string claimed it was "tracked in git -- checkout?". It never was.
    ('behavioral_mp/cell_list_behavioral.txt',
     'xcelium/riscv_test/behavioral_mp/cell_list_behavioral.txt',
     'the ORDER-SENSITIVE HDL compile list of the 136-suite AND the base list '
     '`make verify` derives every staged per-config cell list from'),
    ('disable_x_warnings.tcl',
     'xcelium/disable_x_warnings.tcl',
     '-input by every runner including the generated one '
     '(verify/xrun_parallel.template.sh)'),
    ('behavioral_mp/batch_run.tcl',
     'xcelium/riscv_test/behavioral_mp/batch_run.tcl',
     'the batch sim driver the 136-suite runs each snapshot under'),
    ('behavioral_mp/smoke.txt',
     'xcelium/riscv_test/behavioral_mp/smoke.txt',
     'the 29-test smoke list CLAUDE.md documents as TESTS_FILE=smoke.txt'),
    ('behavioral_mp/xrun.sh',
     'xcelium/riscv_test/behavioral_mp/xrun.sh',
     'single-test GUI driver (CLAUDE.md "Test flows")'),
    ('behavioral_mp/xrun_batch.sh',
     'xcelium/riscv_test/behavioral_mp/xrun_batch.sh',
     'single-test headless driver — the F10 detector recipe drives it directly'),
    ('behavioral_mp/xrun_gui.sh',
     'xcelium/riscv_test/behavioral_mp/xrun_gui.sh',
     'GUI on an already-elaborated snapshot'),
    ('behavioral_mp/trap_watch.tcl',
     'xcelium/riscv_test/behavioral_mp/trap_watch.tcl',
     'the trap_flag watcher the OFF-polarity ext* probes are judged by'),

    # Tier B — the Argus 115/115 standing gate is ENTIRELY untracked.
    ('behavioral_mp_argus/xrun_parallel.sh',
     'xcelium/riscv_test/behavioral_mp_argus/xrun_parallel.sh',
     'the Argus N=18 gate runner (its TEST_FILES list IS the 115)'),
    ('behavioral_mp_argus/cell_list_behavioral.txt',
     'xcelium/riscv_test/behavioral_mp_argus/cell_list_behavioral.txt',
     'the Argus compile list — it is what pins the gate to the pre-P-series '
     'hdl/argus/ snapshot (inventory probe §1.5)'),
    ('behavioral_mp_argus/smoke_argus.txt',
     'xcelium/riscv_test/behavioral_mp_argus/smoke_argus.txt',
     'the Argus smoke subset'),
    ('behavioral_mp_argus/batch_run.tcl',
     'xcelium/riscv_test/behavioral_mp_argus/batch_run.tcl',
     'the Argus batch sim driver'),

    # Tier C — the ONLY knobs-on flows that exist, i.e. K2's own prior art.
    # Both are expected to be RETIRED by generated stage dirs later in the K
    # programme; until that is a deliberate act, a `git clean` must not do it.
    ('behavioral_mp_umode/cell_list_behavioral.txt',
     'xcelium/riscv_test/behavioral_mp_umode/cell_list_behavioral.txt',
     'the F10 TRAPCSR+UMODE build — one line differs from behavioral_mp'),
    ('behavioral_mp_umode/umode_hdl_MemoryMap.vhd',
     'xcelium/riscv_test/behavioral_mp_umode/umode_hdl/MemoryMap.vhd',
     'the F10 knobs-on MemoryMap (CORE_ENABLE_TRAPCSR/UMODE true) — the ENTIRE '
     'hardware half of a knobs-on build is this one substituted file'),
    ('behavioral_mp_umode/xrun.sh',
     'xcelium/riscv_test/behavioral_mp_umode/xrun.sh',
     'the F10 flow GUI driver'),
    ('behavioral_mp_umode/xrun_batch.sh',
     'xcelium/riscv_test/behavioral_mp_umode/xrun_batch.sh',
     'the F10 flow headless driver — the rocsrw detector recipe'),
    ('behavioral_mp_stripped/cell_list_stripped.txt',
     'xcelium/riscv_test/behavioral_mp_stripped/cell_list_stripped.txt',
     'the extensions-OFF build — the negative-control polarity of every ext* probe'),
    ('behavioral_mp_stripped/stripped_hdl_MemoryMap.vhd',
     'xcelium/riscv_test/behavioral_mp_stripped/stripped_hdl/MemoryMap.vhd',
     'the extensions-OFF MemoryMap'),
    ('behavioral_mp_stripped/stripped_hdl_MCU.vhd',
     'xcelium/riscv_test/behavioral_mp_stripped/stripped_hdl/MCU.vhd',
     'the extensions-OFF MCU'),
    ('behavioral_mp_stripped/run_extoff.sh',
     'xcelium/riscv_test/behavioral_mp_stripped/run_extoff.sh',
     'the OFF-polarity harness: it reports TRAP_OK where the suite reports PASS'),
    ('behavioral_mp_stripped/trap_watch.tcl',
     'xcelium/riscv_test/behavioral_mp_stripped/trap_watch.tcl',
     'the OFF-polarity trap watcher'),

    # The six ON-polarity test lists (inventory probe §5.5). These are the
    # accumulated selection knowledge of the X and P series — which tests prove
    # which knob — and every one of them is a plain text file nothing protected.
    ('behavioral_mp/on_directed.txt',
     'xcelium/riscv_test/behavioral_mp/on_directed.txt',
     'the 26 X-series ON-polarity directed rows (Zfinx/Zabha/Zacas/Zkn)'),
    ('behavioral_mp/p3_gate.txt',
     'xcelium/riscv_test/behavioral_mp/p3_gate.txt',
     'the P3 privileged-architecture gate list (16)'),
    ('behavioral_mp/p3_final.txt',
     'xcelium/riscv_test/behavioral_mp/p3_final.txt',
     'the P3 final priv* list (9)'),
    ('behavioral_mp/p3_smoke2.txt',
     'xcelium/riscv_test/behavioral_mp/p3_smoke2.txt',
     'the P3 second smoke (18) — the X2/X3 sh* + ext* knobs-on set'),
    ('behavioral_mp/exttests.txt',
     'xcelium/riscv_test/behavioral_mp/exttests.txt',
     'the adaptive core-feature probe list (8) and its written both-polarity rule'),
    ('behavioral_mp/zabha3.txt',
     'xcelium/riscv_test/behavioral_mp/zabha3.txt',
     'the X2 Zabha 3-test list — HISTORICAL: it names the short-alias images the '
     'K2 basename rename made unnecessary (tests/rv32uzabha/Makefrag)'),

    # Tier E — outside the repository, and nothing checked it before K2.
    ('spike_env.sh',
     '~/local/spike_env.sh',
     'xrun_cosim.sh DIEs without this file; it is 20 lines and lives outside '
     'the repo, so neither git nor this checker saw it until now'),

    # The boot ROM image both sides of COSIM_BOOT lockstep execute. Regenerable
    # from tracked source (`software/bootrom_mp/`), but it is the exact byte
    # stream the reference runs from pc=0, the behavioural ROM model reads by
    # hardcoded path, and the four pins are measured against — so a silent
    # change to it is a silent change to the gate.
    ('bootrom_mp_rom.rcf',
     'software/bootrom_mp/bin/rom.rcf',
     'the boot ROM image the COSIM_BOOT reference and the behavioural ROM '
     'model both execute (.gitignore:83)'),
]


def repoRoot():
	here = os.path.dirname(os.path.abspath(__file__))
	return os.path.abspath(os.path.join(here, '..', '..'))


def gateDir():
	return os.path.join(repoRoot(), 'tools', 'cosim', 'gate')


def readLines(path):
	with open(path, 'r', newline='') as f:
		return f.read().split('\n')


def livePath(root, liveRel):
	"""Resolve a live path. `~/...` escapes the repository on purpose (Tier E);
	everything else is relative to the repo root."""
	if liveRel.startswith('~'):
		return os.path.expanduser(liveRel)
	return os.path.join(root, liveRel)


def copyPreservingMode(src, dst):
	d = os.path.dirname(dst)
	if d and not os.path.isdir(d):
		os.makedirs(d)
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
			# --update ADOPTS a newly-declared entry: this is how a file joins
			# GATE_FILES. Without it, adding a row to the table above could only
			# ever report MISSING and the record could never be created.
			if update and liveRel is not None and os.path.isfile(livePath(root, liveRel)):
				copyPreservingMode(livePath(root, liveRel), canonPath)
				print('  ADOPTED canonical copy from live: ' + name)
				print('    COMMIT tools/cosim/gate/' + name + ' with the change that motivated it.')
				matched += 1
				continue
			print('MISSING canonical copy: ' + canonPath + '   (' + what + ')')
			missing.append(name)
			continue

		if liveRel is None:
			canonicalOnly += 1
			print('  canonical-only  ' + name + '   (' + what + ')')
			continue

		liveAbs = livePath(root, liveRel)

		if restore:
			if os.path.isfile(liveAbs) and readLines(liveAbs) != readLines(canonPath) and not force:
				print('REFUSING to overwrite a DIFFERING live copy: ' + liveRel)
				print('  The live file is not the canonical one. If the live version is the')
				print('  correct one, run --update to record it. If you really mean to discard')
				print('  it, re-run --restore --force.')
				drift.append(name)
				continue
			copyPreservingMode(canonPath, liveAbs)
			print('  restored  ' + liveRel)
			matched += 1
			continue

		if not os.path.isfile(liveAbs):
			print('MISSING live copy: ' + liveAbs)
			print('  (' + what + ')')
			print('  A fresh clone or a `git clean -xdf` produces exactly this. Recover with:')
			print('    /usr/bin/python3.6 tools/cosim/check_gate_files.py --restore')
			missing.append(name)
			continue

		canon = readLines(canonPath)
		live = readLines(liveAbs)

		if canon == live:
			matched += 1
			continue

		if update:
			copyPreservingMode(liveAbs, canonPath)
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
