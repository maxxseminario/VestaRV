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
    ('cosim_zihpm_tests.txt',
     None,
     'the K2b amendment-4 lockstep list (extzihpm) — EXPECTED TO DIVERGE at the '
     'first mhpmcounter read: that divergence is F1 under measurement for the '
     'first time, pre-registered by k0 §3.3 as the row\'s PASS condition'),
    ('cosim_trapcsr_tests.txt',
     None,
     'the K2b amendment-3 lockstep list (rocsrw + privecall) — EXPECTED TO '
     'DIVERGE, and tracked because the measurement is the deliverable: it is '
     'the record of F-K2b-2 (the custom CSR mtrapctl is illegal in the '
     'reference, so no TRAPCSR row can be clean)'),

    # K4, 2026-08-03. The R-DK1 matrix's own knob-bearing lists, same
    # CANONICAL-ONLY treatment and for the same reason. Nine of the sixteen
    # tier-B rows get one; the seven that do not are recorded with their
    # reason in pin_table.md rather than with an empty file here (an empty
    # TESTS_FILE is a trap, not a document): `zawrs` and `zihint` have no
    # ELIGIBLE single-hart knob-bearing cell (extzawrs reads counter CSRs,
    # does MMIO and executes `iret`; zihint's only gated test in the tree is
    # the multi-hart `shpause`), and the other five already have a list above.
    ('cosim_zabha_tests.txt',
     None,
     'the K4 row-B7 lockstep list (extzabha + the three ON-polarity-only '
     'rv32uzabha rows) — carries `mis`, whose INJECT-EXHAUSTED verdict is '
     'ledger K4-L1: the reference takes the misaligned-AMO exception this core '
     'deliberately does not implement. Read the row as 3 compared / 3 PASS / '
     '1 NOT COMPARABLE, never as 3/4'),
    ('cosim_zicond_tests.txt',
     None,
     'the K4 row-B1 lockstep list (extzicond ON arm + rv32uzicond-p-cz) — '
     'extzicond is in the standing cosim_tests.txt only in its OFF arm, which '
     'executes no czero encoding at all'),
    ('cosim_zcb_tests.txt',
     None,
     'the K4 row-B2 lockstep list (extzcb ON arm) — one cell, and that is the '
     'whole of the knob\'s surface in the tree'),
    ('cosim_zimop_tests.txt',
     None,
     'the K4 row-B3 lockstep list (extzimop) — its OFF arm is a terminal-trap '
     'POISON, so this list is the only way the ON arm is ever compared'),
    ('cosim_zacas_tests.txt',
     None,
     'the K4 row-B8 lockstep list (extzacas + rv32uzacas-p-casw); casbh is '
     'absent for a CONFIG reason — its sub-word forms need zabha too'),
    ('cosim_zcmp_tests.txt',
     None,
     'the K4 row-B10 lockstep list (extzcmp) — a real cm.push/cm.pop round '
     'trip; the sh* siblings are excluded pending an A13 plant audit'),
    ('cosim_zbkb_tests.txt',
     None,
     'the K4 row-B12 lockstep list (extzbkb + rv32ui-p-zbk\'s ZBKB arm) — zbk '
     'is in the standing list with ALL THREE of its arms preprocessed away, '
     'i.e. as a green cell covering nothing (R-K2-7 (2))'),
    ('cosim_zbkc_tests.txt',
     None,
     'the K4 row-B13 lockstep list (rv32ui-p-zbk\'s ZBKC arm) — its EXISTENCE '
     'corrects K4 P4.2, which recorded that zbkc has no knob-bearing test. '
     'Read its header for what the cell does NOT isolate'),
    ('cosim_zbkx_tests.txt',
     None,
     'the K4 row-B14 lockstep list (extzbkx + rv32ui-p-zbk\'s ZBKX arm)'),
    ('cosim_zkn_tests.txt',
     None,
     'the K4 row-B15 lockstep list — eight cells (three ext-probes whose OFF '
     'arms are POISONs + the five ON-polarity-only rv32uzkn* rows), the '
     'largest knob-bearing list in the programme'),

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
    #
    # RE-CUT TWICE ON 2026-08-23, both times deliberately, neither time drift.
    # First the ISA flip: the ROM is now built rv32ic with
    # -fno-tree-loop-distribute-patterns, .text 10,140 -> 7,376 bytes, so every
    # word of the image moved. Then the DEPTH change: memory.romSize went 16384
    # -> 8192 and rom0 became the 2048 x 32 rom2k_hvt_pg macro, so the padded
    # image is 8,192 bytes and this file is 2,048 lines, not 4,096. The tail
    # that went away was all zeros -- the first 2,048 lines are unchanged.
    # software/bootrom_mp/testdata/rom_rcf_golden.txt moved with it both times.
    ('bootrom_mp_rom.rcf',
     'software/bootrom_mp/bin/rom.rcf',
     'the boot ROM image the COSIM_BOOT reference and the behavioural ROM '
     'model both execute (.gitignore:83)'),

    # ---------------------------------------------------------------------
    # D1, 2026-08-05 (R-D1-2 (4), confirmed by R-D1-3 (3)). The debug-mode
    # acceptance instruments. They are gate files by the same argument as
    # everything above -- they are the standing acceptance of a shipped
    # feature, they live in the gitignored `xcelium/` tree, and a
    # `git clean -xdf` deletes every one of them -- with one difference worth
    # stating: they were written BLIND, before the RTL existed, by an agent
    # barred from ever reading it. That provenance is not reproducible, so a
    # lost copy could not be honestly rewritten, only re-derived from the
    # implementation it is supposed to be independent of.
    #
    # They are filed under `behavioral_mp/` per the K2 convention (flow-owned
    # files go in a directory named for their flow); the flat names above are
    # the pre-K2 originals and files that belong to no single flow.
    #
    # DELIBERATELY NOT HERE: `behavioral_mp/dbg_forcecheck.tcl`. It is not an
    # acceptance instrument -- its own header says so -- but the one-time
    # method validation that a `force` on a tile input tied to a literal in
    # MCU.vhd actually reaches the logic inside the tile (measured on `sleep`,
    # which has a large understood effect, because dbg_haltreq did not exist
    # yet). It remains on disk only. Named here rather than left silent: the
    # ruling's wording was the `dbg_*.tcl` glob, and this is the member of that
    # glob the approved commit-4 file set does not contain.
    ('behavioral_mp/xrun_dbg.sh',
     'xcelium/riscv_test/behavioral_mp/xrun_dbg.sh',
     'the D1 acceptance runner -- the ONLY runner elaborated `-access +rwc`, '
     'which is what lets a tcl harness FORCE the core-side debug request '
     'ports. Deliberately not xrun.sh: widening the standing suite\'s '
     'elaboration access would change its optimisation and its run-to-run '
     'identity for no benefit'),
    ('behavioral_mp/dbg_halt.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_halt.tcl',
     'instrument I4 -- halt entry/exit against three victims (SLEEPING, '
     'TRAP_STATE, EXECUTE), waiting on each victim\'s own cpu_state rather '
     'than on a calibrated delay'),
    ('behavioral_mp/dbg_step.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_step.tcl',
     'instrument I5 -- single-step, whose fine checks (STEP_ERR, '
     'SUBJ_COUNTER) are ordered ahead of the coarse liveness check per '
     'R-D1-3 (1)'),
    ('behavioral_mp/dbg_rst.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_rst.tcl',
     'instrument I6 -- halt-on-reset, checked STRUCTURALLY because a hart '
     'halted at reset would execute an uninitialised TCM; it carries no image '
     'of its own and rides whatever test hart 0 is running'),
    ('behavioral_mp/dbg_verdict.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_verdict.tcl',
     'the shared verdict reader -- riscv_tb reports only a0, and every D1 '
     'instrument encodes WHICH assertion failed in a1/a2/a3, so a FAIL that '
     'cannot be read is a FAIL that cannot be diagnosed'),
    # ---- D2 acceptance instruments (R-D1-2(4) extended by R-D2-2(6)) ----
    ('behavioral_mp/dbg_bfm.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_bfm.tcl',
     'the DMI bus-functional master library every D2 harness sources -- '
     'dm_read/dm_write/dm_poll_status(hold)/the trampoline force-plant; the '
     'ack-style handshake shape lives here'),
    ('behavioral_mp/dbg_dmi.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_dmi.tcl',
     'J2, the headline -- halt hart 2 through DMI while 0/1/3 run, resume, '
     'PHASE 4 = the re-armed-wire ordering (R1-R4); M7 flips its R3'),
    ('behavioral_mp/dbg_abs.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_abs.tcl',
     'J3 -- abstract GPR/CSR read+write incl. the dscratch-serviced pair, '
     'progbuf lw/sw (DD5 exercised), postexec, cmderr=EXCEPTION with the '
     'hart still halted'),
    ('behavioral_mp/dbg_grp.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_grp.tcl',
     'J4 -- halt groups: membership, broadcast to not-yet-halted members, '
     'non-members untouched; round clocked on the NON-member (a duration is '
     'not a discriminator)'),
    ('behavioral_mp/dbg_prv.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_prv.tcl',
     'J5 -- dcsr.prv under a U-mode victim (needs the castalia_debug row: '
     'debug.enable AND priv.umode, R-D2-2(2))'),
    ('behavioral_mp/dbg_dark.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_dark.tcl',
     'J6 -- the dark hart: unavail truth-telling against PWRCTRL, DM '
     'reachable while a tile is gated, power-up + held resethaltreq halts '
     'before first retire; both directions handshook (validation wave)'),
    ('behavioral_mp/dbg_conf.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_conf.tcl',
     'J1b -- the DMI register-map conformance list on the proven riscv_tb '
     'flow, 38 checks incl. K21a/b (no command starts while cmderr set)'),
    ('behavioral_mp/dbg_exc.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_exc.tcl',
     'D-A, the F-D2-0 detector -- a debug-mode synchronous exception '
     're-enters at DEBUG_ENTRY_ADDR, both delivery polarities, TRAP_STATE '
     'never entered, dpc/dcsr unchanged'),
    ('behavioral_mp/dbg_irq.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_irq.tcl',
     'D-B, the F-D2-1 detector -- no interrupt taken in debug mode, with a '
     'known-nonzero deliverability control on both polarities'),
    ('mp_test/run_dbg_dmi.sh',
     'xcelium/mp_test/run_dbg_dmi.sh',
     'J1 runner -- dbg_dmi_tb (the DMI port bench) on the real debug-ON '
     'MCU; rc-124 wall-clock arm separates complete-and-clean from '
     'mid-sequence (the bench line is the verdict, not the exit code)'),
    ('mp_test/run_dbg_iface.sh',
     'xcelium/mp_test/run_dbg_iface.sh',
     'I2 runner -- the D1 dbg_iface_tb port bench; was the one unprotected '
     'unit-bench runner (d2_probe finding 11), retro-registered at D2 C5'),

    # ---------------------------------------------------------------------
    # D3 (R-D3-5(3), 2026-08-06): THE FLOW FILES.  A DIFFERENT KIND OF ENTRY,
    # and the reason it belongs here is exactly the reason this whole
    # mechanism exists.  genus/ and innovus/common/ are BOTH gitignored
    # (.gitignore:5 and :14), so these five files -- the two SDC-bearing
    # genus tcls that declare the D3 TCK clock domain, the MCU_castalia
    # chip netlist with its JTAG pads, its dated pre-edit sidecar, and the
    # one real padlist copy -- cannot be committed on their own path and a
    # `git clean -xdf` deletes them outright.  They are INPUTS to the
    # close-of-programme re-cut (DD6): losing them silently would cost the
    # cut its pad wiring and its clock isolation, and nothing else in the
    # tree would notice.  Canonical copies + this table's rc-0 gate are the
    # protection the sim gates already have.
    # NOTE what this is NOT: it is not whole-tree protection for
    # innovus/common/ or genus/.  Five named files, chosen because D3
    # touched them; the general gap stays named residue in the DD package.
    ('flow/MCU_MP.genus.tcl',
     'genus/MCU_MP/tcl/MCU_MP.genus.tcl',
     'the FLAT assembly synthesis flow (feeds the gate-sim SDF). Carries the '
     'D3 clk_tck domain: create_clock -domain clk_tck_domain on hpin '
     'dtm0/tck -- an INSTANCE PIN, never a top-level port (the chip SDC '
     'generator deletes [get_ports] lines and FATALs on a survivor), guarded '
     'on the dtm0 hinst so a knob-OFF netlist declares no TCK clock at all'),
    ('flow/MCU_MP_hier.genus.tcl',
     'genus/MCU_MP/tcl/MCU_MP_hier.genus.tcl',
     'the HIERARCHICAL assembly synthesis flow (feeds Innovus). Same guarded '
     'clk_tck block, same hpin declaration -- this is the one whose product '
     'the chip SDC generator transforms, so a port-declared clock here would '
     'abort the chip flow'),
    ('flow/MCU_castalia.v',
     'innovus/common/MCU_castalia/in/MCU_castalia.v',
     'the MCU_castalia chip netlist WITH the five D3 JTAG pads (47=TCK '
     '48=TMS 49=TDI 50=TDO south, 51=TRSTn east; TCK/TRSTn PDDW16SDGZ_G '
     'pull-DOWN, TMS/TDI/TDO PDUW16SDGZ_G pull-UP -- a distinction LEF '
     'cannot express, so these cell names are the only record of it). '
     'Requires a debug-ON MCU: it is an input to the DD6 re-cut, not a '
     'netlist for the current signed-off cut'),
    ('flow/MCU_castalia.v.pre_d3',
     'innovus/common/MCU_castalia/in/MCU_castalia.v.pre_d3',
     'the PRE-EDIT netlist, byte-for-byte, preserved beside the edited one '
     '(the optS/.pre_c6 sidecar precedent). It is what the signed-off '
     'reference cut actually describes -- and the provenance rule is that '
     'the cut artifacts (DB/GDS/rpt) were NOT touched, so this file is the '
     'only thing that says which netlist they came from'),
    # ---------------------------------------------------------------------
    # D3 (2026-08-06): THE JTAG ACCEPTANCE SET. Blind-authored against the
    # frozen specs, demonstrated to FAIL before the transport existed, and
    # executed at N=4 AND N=18. They caught the sticky-FAILED RTL defect that
    # four of their own number could not see -- and the wall caught six
    # defects in the instruments themselves.
    ('behavioral_mp/dbg_tap.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tap.tcl',
     'the TCK-level TAP bus-functional model over the five JTAG pins -- the '
     '16-state graph, chain-length MEASUREMENT (flush with ones, count the '
     'shifts to a zero), and the TAP-backed dmi_xact that lets any D2 harness '
     'be REPLAYED over JTAG unmodified'),
    ('behavioral_mp/dbg_tapconf.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tapconf.tcl',
     'T2, 34 checks -- graph/IR/DR conformance from the pins alone: IDCODE '
     'out of Test-Logic-Reset with no IR load, measured chain lengths, the '
     'unsupported-IR-selects-BYPASS deviation, and TMS-high-x5 from all '
     'sixteen states graded individually'),
    ('behavioral_mp/dbg_tapdtm.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tapdtm.tcl',
     'T3, 43 checks -- dtmcs fields, BOTH sticky flavours, dmireset, '
     'dmihardreset with its discard clause and defined all-zero shadow, '
     'Capture-DR previous-result, and THE ONE-SHOT CLAUSE instrumented by '
     'COUNTING ACCEPTS (a duplicate accept is invisible to any '
     'result-reading check)'),
    ('behavioral_mp/dbg_tapreplay.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tapreplay.tcl',
     "T4 -- the whole-stack proof: dbg_conf.tcl's 38 checks executed BYTE FOR "
     'BYTE with the transport swapped underneath. This is the instrument '
     'that caught the sticky-FAILED defect (38/38 raw vs 14/38 over JTAG)'),
    ('behavioral_mp/dbg_taphalt.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_taphalt.tcl',
     'T5, 17 checks -- halt / abstract-read / resume of a RUNNING hart '
     'through the pads, every claim made twice (dmstatus AND the victims own '
     'counters), with an abstract mhartid read as the sharpest check in the '
     'set'),
    ('behavioral_mp/dbg_tapcoexist.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tapcoexist.tcl',
     'T6, 12 checks -- the OR-merge tripwire, the one instrument whose job is '
     'to fail when the MERGE is wrong rather than when the DTM is: both port '
     'groups resolve, the DTM is inert at its fail-safe defaults, and raw and '
     'TAP transactions interleave against one Debug Module'),
    ('behavioral_mp/xrun_dbg_verify.sh',
     'xcelium/riscv_test/behavioral_mp/xrun_dbg_verify.sh',
     'the runner that made N=18 harness proof possible at all -- it runs a '
     'tcl debug harness against a GENERATOR-STAGED knob-ON tree and DERIVES '
     "NHARTS from the image set's own stamp rather than guessing (a harness "
     'graded at the wrong N silently checks the wrong chip)'),
    ('mp_test/run_dbg_tap.sh',
     'xcelium/mp_test/run_dbg_tap.sh',
     'J3 runner -- dbg_tap_tb, the bench that NAMES the five JTAG formals in '
     'VHDL (so a missing port is an elaboration error) and is the only '
     'instrument that drives the TAP while the chip is held in system reset'),
    ('flow/chip_top_wound_padlists.tcl',
     'innovus/common/MCU_castalia/tcl/chip_top_wound_padlists.tcl',
     'the ONE REAL padlist copy (chip_top_wound_quad symlinks to it). '
     'BOTTOM gains TCK/TMS/TDI/TDO at pins 47-50, RIGHT gains TRSTn at the '
     'HEAD (the east edge runs 51-75, so 51 precedes 52). Nothing on the '
     'north edge -- ever: it is the PRCUT-isolated analog band'),

    # ---- D4: the trampoline-plant acceptance set (seven tcl legs) --------
    # Authored blind against the frozen spec and demonstrated to FAIL before
    # the implementation existed. dbg_tramp_lib carries the no-force guard,
    # which is CODE rather than a promise: it renames dbg_plant_trampoline to
    # a run-failing stub, so a D4 leg that plants by force fails its own run
    # instead of quietly proving nothing.
    ('behavioral_mp/dbg_tramp.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tramp.tcl',
     'THE PLANT DETECTOR, 7 checks -- reads all 40 entry-page words back '
     "through the DM's OWN visibility (a victim executing progbuf lw), never "
     'a tcl peek, because a plant that silently did nothing is invisible to '
     'every pre-D4 harness. Graded poison is words 1..39: word 0 is '
     'published-not-asserted under F-D4-1'),
    ('behavioral_mp/dbg_tramp_lib.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_tramp_lib.tcl',
     'the D4 library -- the DM-visibility readback, the page census, the '
     'in-band scan channel, and THE NO-FORCE GUARD (dbg_plant_trampoline is '
     'renamed away and replaced by a failing stub; the real proc survives '
     'only as the D4_CONTROL liveness arm, which banners itself as ungraded)'),
    ('behavioral_mp/dbg_trpact.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_trpact.tcl',
     '7 checks -- the dmactive 0->1 trigger ISOLATED: nothing is ever halted, '
     'so the page can only have been repaired by the attach plant, and a '
     'RUNNING hart s own loads are the observation. Carries the in-band '
     'poison leg (a hart store, because a forced word is read-only and could '
     'not be repaired by the mechanism under test)'),
    ('behavioral_mp/dbg_trprep.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_trprep.tcl',
     '8 checks -- dmactive -> 0 clears the plant-owed state, so a toggle is a '
     'REAL re-plant and not a no-op (the natural implementation, one more '
     'write-once latch beside epi_done, passes every other leg and fails only '
     'here). R6 prices the epi_done-joins-the-clear choice'),
    ('behavioral_mp/dbg_trpheal.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_trpheal.tcl',
     'THE ORDERING LEG, **12 checks** (re-shaped at validation T6; any '
     '"11/11" quotation is pre-T6 and stale). The discriminator now runs '
     'FIRST off a proven-clean page and the wedging phase LAST -- the only '
     'order that works on a page whose damage is shared and permanent. '
     'Separates "no on-halt re-plant" from "plant after the token" by VALUE '
     '(firstbad=word34) rather than by duration'),
    ('behavioral_mp/dbg_trpsess.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_trpsess.tcl',
     '11 checks -- a WHOLE DEBUG SESSION with zero dbg_plant_trampoline '
     'calls, the thing D2 and D3 could never do: attach, halt, abstract '
     'GPR/CSR round-trips, a progbuf lw/sw memory round-trip closed at both '
     'ends over DMI, resume -- then the same again on a ROM-PARKED tile that '
     'never executed a word of the image. N=4 and N=18'),
    ('behavioral_mp/dbg_trpdark.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_trpdark.tcl',
     'THE HALT-ON-RESET BACKBONE, 8 checks, N=4 AND N=18 -- neither I6 nor J6 '
     'had ever graded a halt into an UNPLANTED page. No plant, no tile-port '
     'force: the victim is power-cycled in band through PWRCTRL and must halt '
     'with ZERO retires, reach the entry page, and then EXECUTE REAL PLANTED '
     'CODE -- proven by an abstract round-trip that cannot complete unless '
     'the DM observed the trampoline s own TOK_HALTED'),

    # ---- D5: THE TRANSPORT (d5_spec 2, architecture ruled at R-D5-1(3)) ----
    # These four are the reason a debugger can reach this chip at all, and
    # every one of them lives in the gitignored `xcelium/` tree. Losing them
    # to a `git clean -xdf` would not cost a test -- it would cost the
    # transport, and with it the ability to re-run any D5 evidence.
    ('behavioral_mp/dbg_rbb_bridge.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_rbb_bridge.tcl',
     'THE BRIDGE. xmsim\'s OWN Tcl interpreter listens on the OpenOCD '
     'remote_bitbang TCP port and drives the five JTAG formals -- no '
     'co-process, no DPI. Honours eleven frozen protocol clauses, each '
     'annotated in the header with the measurement that bought it (never '
     '-buffering none, 24 us/char; chunked reads, 6.5x; a NONZERO run between '
     'pin-set bytes, because same-time forces COLLAPSE; lazy forcing; a '
     'heartbeat carrying pending_out, the ONLY discriminator between a benign '
     'wait-for-debugger and a deadlocked bridge). Event-driven on two '
     'channels; the second is PASSIVE-ONLY and whitelisted'),
    ('behavioral_mp/dbg_rbbsmoke.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_rbbsmoke.tcl',
     'the bridge\'s own smoke leg: stands the server up, serves ONE client, '
     'reports. Separates "the bridge works" from "the debugger stack works", '
     'which are two claims and the first has to be true first. Proves the '
     'PHASE -- a one-phase-late TDO sample returns the stream shifted by '
     'exactly one bit, which looks structured and blames the RTL'),
    ('behavioral_mp/dbg_sessrun.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_sessrun.tcl',
     'the graded session harness -- dbg_sessgrade.tcl with the bridge\'s '
     'service loop where its `run` calls are. Carries the DRIVER CONTRACT: '
     'the fixed snapshot labels a gdb script must send over the control '
     'channel, enforced by sess_grade_summary refusing to say passed while '
     'NOT-GRADED > 0, so a driver that skips an instant produces a named gap '
     'rather than a quiet green'),
    ('behavioral_mp/dbg_rbbunit.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_rbbunit.tcl',
     'unit proof for the bridge\'s decode shadow, in a STANDALONE tclsh -- no '
     'simulator, no license, no elaboration. 11 checks, every one asserting a '
     'KNOWN-NONZERO value. It caught two real bridge defects before the '
     'bridge touched the chip, the sharper being an int-vs-string compare '
     'that sized EVERY DR as BYPASS and would have pinned dmiresets at 0 -- '
     'the F1 false-reassurance class exactly'),

    # ---- D4: the debug-ON assembly flow (R-D4-5(2), the R-D3-5(3) shape) --
    # genus/ is gitignored, so the flow that produces the standing debug-ON
    # assembly pin AND the two generated inputs it reads are canonical here.
    # Before D4 those inputs lived in a FOREIGN /tmp SCRATCHPAD: the pin was
    # one reap from unreproducible.
    ('flow/asm_dbgon.tcl',
     'genus/MCU_MP/tcl/asm_dbgon.tcl',
     'the debug-ON assembly synthesis flow -- the only producer of the '
     'standing knob-ON pin (sequential 18,163 at the D4 close). Its header '
     'carries the regen recipe for the two staged inputs below and the '
     'three-constant acceptance test that tells a correct regeneration from '
     'a castalia_debug.json one'),
    ('flow/MCU_top_dbgon.gen.vhd',
     'genus/common/in/MCU_top_dbgon.gen.vhd',
     'the debug-ON MCU.vhd the pin is measured against: SHIPPED DEFAULT plus '
     'debug.enable and nothing else (R-D2-9(3) -- deliberate isolation, so '
     "the scored number carries no castalia_debug umode term). NOT config/"),
    ('flow/MemoryMap_dbgon.gen.vhd',
     'genus/common/in/MemoryMap_dbgon.gen.vhd',
     'its MemoryMap sibling. CORE_ENABLE_DEBUG true, CORE_ENABLE_TRAPCSR '
     'true, CORE_ENABLE_UMODE **false** -- the last of those is the shipped '
     'default and is the isolation, NOT staleness; a regeneration reading '
     'UMODE true used the wrong config and moves the pin'),

    # ---- D5: the seven blind-authored acceptance instruments ---------------
    # Authored against d5_spec.md by an agent barred from every fix, and every
    # one of them was SEEN TO FAIL before it was seen to pass. They live in
    # gitignored xcelium/, so until now a `git clean -xdf` deleted the entire
    # evidential basis of the phase while leaving the RTL it graded in place.
    ('behavioral_mp/dbg_dmreg.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_dmreg.tcl',
     'the section-1 RTL detector, 10 checks over the two DM edits (sbcs '
     'read/write, hartinfo null claim). Runs on the RAW dmi_* port, not the '
     'TAP, so the DTM sticky gate cannot turn one real failure into a cascade '
     'of transport artefacts. GRADES THE OP, NOT THE DATA: today\'s pre-fix '
     'sbcs read answers op=FAILED with the SAME 0x00000000 the correct answer '
     'carries, so a data-only leg ships a false pass on a chip gdb cannot '
     'attach to. 7 of 10 FAILED pre-fix, 10/10 after, at BOTH N'),
    ('behavioral_mp/dbg_sess_lib.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_sess_lib.tcl',
     'the session grader library. Every verdict is an ORDERING BETWEEN '
     'SNAPSHOTS, never a duration (method rule 17), and NOT-GRADED is counted '
     'separately and is never a pass. Also the word map for the d5sess image '
     '(PHASE/READY/LIVE0-2/MEMW/SEED at 0x10050-0x1007C) -- the liveness '
     'counters the reset-halt disposition rests on'),
    ('behavioral_mp/dbg_sessgrade.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_sessgrade.tcl',
     'the debugger-less FAIL leg and the wiring template for a real session. '
     'Its value is that it is SEEN TO FAIL by construction: with no debugger '
     'attached it measures graded=20 failed=18 NOT-GRADED=5 with exactly two '
     'PASSes, both declared in its header in advance as known-nonzero '
     'controls'),
    ('behavioral_mp/dbg_gateidc.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_gateidc.tcl',
     'the section-6 bounded TAP leg: tap_reset + one IDCODE scan + one dtmcs '
     'read, ~96 TCK, graded field by field. ONE FILE SERVES BOTH ARMS -- '
     'D5_GATE=1 changes what it says and never what it checks, which is what '
     'makes the behavioural run a control for the gate run. Carries the '
     'one-bit-shift trap (a TDO sampled one phase late returns the whole '
     'stream rotated, 0x1CA57EEF -> 0x0E52BF77, which looks structured and '
     'misdirects) and the tap_init-before-tap_reset lesson'),
    ('behavioral_mp/dbg_w2probe.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_w2probe.tcl',
     'the chip-side half of the dropped-resume (W2) landmine: 3 graded checks '
     'that are instrument-liveness preconditions, plus the classification. On '
     'a WORKING chip it measures abstractcs 0x02000101, cmderr BUSY(1), '
     'busy 0, hart resumed -- W2-SEEN. The gdb-side half measured ABSORB '
     'against it (D5 T6)'),
    ('behavioral_mp/dbg_pbsub.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_pbsub.tcl',
     'the F-D5-1 blind detector, 13 checks over the progbuf ebreak->jal '
     'substitution. VALUE AND cmderr ARE GRADED SEPARATELY because pre-fix '
     'the memory access WORKED and was then told it faulted (0xBE00: 0 -> '
     '0xD5B7EA11 with cmderr=3), so a data-only leg is green on the broken '
     'chip and a cmderr-only leg could be satisfied by silencing the report. '
     'B3 grades position-correctness WITHOUT encoding the implementer\'s '
     'arithmetic -- the two substituted jals must resolve to one common '
     'absolute target. 5 of 13 FAILED pre-fix ({A2,A4,B1,B2,B3}), 13/13 after'),
    ('behavioral_mp/dbg_s0coh.tcl',
     'xcelium/riscv_test/behavioral_mp/dbg_s0coh.tcl',
     'the F-D5-2 blind detector, 11 checks over the coherent-dscratch '
     'contract. Every value leg is checked against an INDEPENDENT SIMULATOR '
     'PEEK, never a readback through the path under test -- that path is the '
     'broken one. E1 is the leg that catches the natural wrong fix (serve the '
     'architectural s0/s1 directly, which greens everything else while '
     'shredding the debuggee\'s registers on every halt), and E2 exists '
     'because E1 passes pre-fix with a ZERO WITNESS. 5 of 11 FAILED pre-fix'),

    # ---- D5: the DD16 bounded gate leg (R-D5-10(1)) ------------------------
    # The flow that carries the standing "the TAP answers through real cells"
    # proof. Same reasoning as the D4 flow/ block above and the R-D3-5(3)
    # shape: xcelium/ is gitignored, so a `git clean -xdf` deletes a signed-off
    # proof and leaves nothing that says it ever existed.
    #
    # SCOPE, ruled deliberately: these are the files THIS PHASE CREATED. The
    # sibling genus_mp/ (debug-OFF) gate-sim flow has no rows either and is
    # equally exposed -- that gap is PRE-EXISTING and is named residue, not
    # D5's to sweep (beside the R-D3-5(3) innovus/common gap).
    ('genus_mp_dbgon/xrun_gatedbg.sh',
     'xcelium/riscv_test/genus_mp_dbgon/xrun_gatedbg.sh',
     'the gate-leg runner: a genus_mp sibling that elaborates the debug-ON '
     'assembly netlist with -access +rwc and its OWN SDF. Carries the '
     'pre-flight SDF guard AND a netlist-vs-SDF cut cross-check (a dbgon '
     'sdfcmd beside an OFF cell list is refused before xrun starts), and '
     'emits -sdfstats, which is what d5_sdf_live.py reads as its positive '
     'evidence'),
    ('genus_mp_dbgon/cell_list_genus_mp_dbgon.txt',
     'xcelium/riscv_test/genus_mp_dbgon/cell_list_genus_mp_dbgon.txt',
     'the leg\'s ORDER-SENSITIVE compile list. Identical to '
     'genus_mp/cell_list_genus_mp.txt except for the one line that matters: '
     'MCU_MP.genus.dbgon.v instead of MCU_MP.genus.v. The OFF netlist has no '
     'TAP in it at all'),
    ('genus_mp_dbgon/MCU_MP_dbgon.sdfcmd',
     'xcelium/riscv_test/genus_mp_dbgon/MCU_MP_dbgon.sdfcmd',
     'the back-annotation command file, MTM MAXIMUM, naming '
     'MCU_MP.genus.dbgon.sdf. THIS FILE IS WHERE THE WRONG-CUT MISTAKE IS '
     'DECIDED: annotating MCU_MP.genus.sdf produces a run that looks entirely '
     'healthy and cannot possibly have exercised a TAP. d5_sdf_live.py '
     '--expect-sdf catches it after the fact; this is the front door'),
    ('genus_mp_dbgon/riscv_tb_gate.vhd',
     'xcelium/riscv_test/genus_mp_dbgon/riscv_tb_gate.vhd',
     'the PRIVATE testbench copy, and the leg does not elaborate without it. '
     'genus_mp/riscv_tb_gate.vhd is byte-untouched and stays that way. '
     'MEASURED (D5 T6/T7, the M7 question): with the component left at a0_3, '
     'xmelab HARD-FAILS *E,CFEPLM on every unassociated Verilog INPUT (tck '
     'tms tdi trstn dmi_req_*), while unassociated OUTPUTS are only '
     '*W,CUFEPC -- so there is no elaborated design to force into. And once '
     'associated, the Verilog port nets REJECT the VHDL literal dbg_tap.tcl '
     'writes (*E,ILLNUM, silently, because every force there is '
     'catch-wrapped) and do not take 1\'b1 either, because the port is '
     'collapsed onto its VHDL driver. The five JTAG pins are therefore '
     'testbench-top VHDL signals and the leg runs with TAP_PFX ":"'),
    ('genus_mp_dbgon/cds.lib',
     'xcelium/riscv_test/genus_mp_dbgon/cds.lib',
     'the library mapping xrun reads out of the run directory. Two lines, and '
     'without it the leg compiles into whatever `work` the install defaults '
     'to'),
    ('genus_mp_dbgon/gate_m7probe.tcl',
     'xcelium/riscv_test/genus_mp_dbgon/gate_m7probe.tcl',
     'the M7 measurement, and the runner\'s header makes it mandatory BEFORE '
     'the leg. It exists because every force in dbg_tap.tcl is catch-wrapped, '
     'so a wrong path spelling or a wrong value literal does nothing, '
     'silently, and surfaces as IDCODE = 0x00000000 -- a harness failure that '
     'reads as a chip failure. It resolves, forces, then READS BACK, and its '
     'own first version is a recorded miss: it tried only the :dut-family '
     'prefixes and returned a confident verdict about paths the leg does not '
     'use'),
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
