#!/bin/bash
# =============================================================================
# xrun_cosim.sh — V2 of the VestaRV Spike lockstep co-simulation program.
#
# Per test: locate/build the ELF, elaborate + run the TRACED RTL sim, run Spike
# on the same ELF, hand both streams to tools/cosim/compare.py, and report
# PASS / DIVERGE / HUNG / INFRA-FAIL.  Plus a parallel sweep over the eligible
# list (cosim_tests.txt).
#
#   ./xrun_cosim.sh                       # sweep cosim_tests.txt (105 tests)
#   ./xrun_cosim.sh xxxxxxrv32ui-p-add    # ONE test (pattern -> ../rcf/*PAT*.rcf)
#   MAX_PARALLEL=2 ./xrun_cosim.sh
#   TESTS_FILE=mini.txt ./xrun_cosim.sh   # sweep an alternate list file
#
# ─────────────────────────────────────────────────────────────────────────────
# THE PREFIX-COMPARE SOUNDNESS CONDITION (Fable's V2 ruling — binding)
#
#   A test is PASS if and ONLY IF BOTH of these hold:
#     (a) the RTL sim itself reported TEST PASSED via the a0 watch (0xCAFEBABE)
#     (b) tools/cosim/compare.py exited 0
#
# WHY: neither side of a V2 test terminates — both spin forever in RVTEST_PASS.
# The RTL trace ends when riscv_tb's a0 watch kills the sim; Spike ends when
# --instructions runs out. So the comparison is bounded at N = the RTL's OWN
# compared-record count (compare.py --count), which makes an unbounded exit 2
# impossible — but it also means a sim that HUNG or DIED EARLY would trivially
# "match" on its truncated prefix. The comparator therefore runs IN ADDITION to
# the testbench verdict, NEVER instead of it: a sim that hung (the 3-minute
# kill), died, or never reached the a0 watch is HUNG / INFRA-FAIL regardless of
# what the comparator says.
#
# `spike rc=0` is likewise NEVER treated as success (v0_report.md §10.3): Spike
# prints no line for a trapping instruction and exits 0 silently.
# ─────────────────────────────────────────────────────────────────────────────
#
# Environment knobs (all optional):
#   MAX_PARALLEL   parallel workers (default 4). Xcelium seats are a SHARED pool
#                  (5280@poseidon) — keep this modest.
#   TESTS_FILE     alternate sweep list (one rcf basename or path per line)
#   TEST_TIMEOUT   per-sim wall-clock kill, seconds (default 180 = the 1-minute
#                  rule's 3x "this is a finding" threshold; a traced sim is ~5 s)
#   NO_COMPILE=1   reuse the existing worker libraries (skip the fresh compile).
#                  DANGEROUS after any RTL change — the stale-snapshot trap.
#   KEEP=1         keep the bulky per-test trace + Spike log even on PASS
#   NO_BUILD=1     do not build missing ELFs (missing ELF -> INFRA-FAIL)
#   CHECK_IMAGE=0  skip the flash-image-vs-ELF provenance check (§ check_image)
#   SPIKE_SLACK    instructions granted to Spike beyond the RTL's own compared
#                  retire count (default 2000). Spike's --instructions is
#                  derived PER TEST as ncmp+SLACK rather than being a fixed 50k:
#                  measured, ncmp ranges 110 (rv32um-p-div) to 6224
#                  (rv32ua-p-lrsc), so a fixed bound is either short for the
#                  long tests or ~20x oversized for the short ones (105 tests x
#                  50k lines ~ 300 MB of Spike log for nothing). Derived+slack
#                  is >= the RTL length BY CONSTRUCTION, and exit 3 escalates
#                  the bound once to ncmp*4+100000 before it is believed.
#   SPIKE_MAX      hard cap on --instructions (default 4000000)
#   COSIM_HARTS    which harts to TRACE and COMPARE, whitespace-separated
#                  decimals from 0..3 (default "0" = hart 0 only, exactly the
#                  V3 behaviour). Hart 0 must always be present: it is the
#                  a0 gate and the launch-race reference. One elaboration +
#                  ONE simulation still serves every selected hart; the trace,
#                  the injection list, the reference run and the comparator
#                  verdict are PER (test,hart).
#   MULTIHART=1    shorthand for COSIM_HARTS="0 1 2 3" (V4). An explicitly set
#                  COSIM_HARTS WINS over it. Harts 1-3 are the tiles: they only
#                  ever execute the SHARED BOOT ROM before the test launches
#                  them, so they are ALWAYS compared boot-inclusive and always
#                  --stop-before-sleep (see compare_hart) — regardless of
#                  COSIM_BOOT, which keeps governing hart 0 alone. They are also
#                  ALWAYS bracketed: see bracket_on / Amendment A11.
#   PLANT_WIN      V4/A13 shared-and-writable window served by POKING reference
#                  RAM, `base:size` hex (default 0xC000:0x14000 = [0xC000,0x20000)
#                  for the base N=4 config). `auto` asks mk_inject.py to derive it
#                  from MemoryMap.vhd; `off` emits no plants at all (a negative
#                  control). Only meaningful where the bracket script exists —
#                  the P records ride it — i.e. harts != 0, or BRACKET_ISR=1.
#   HDL_ROOT       where MemoryMap.vhd lives, for PLANT_WIN=auto
#                  (default $ROOT/hdl/common).
#
# Artifacts (all under cosim_work/, which is inside the gitignored xcelium/):
#   cosim_work/w<N>/          per-worker Xcelium library (snapshot work.cs_run_w<N>)
#   cosim_work/traces/        <test>_h<HH>.trace         (RTL commit log, per hart)
#   cosim_work/spike/         <test>.h<HH>.spike.log     (reference commit log)
#   cosim_work/inject/        <test>.h<HH>.{inject,bracket}
#   cosim_work/logs/          <test>.{elab,sim}.log  +  <test>.h<HH>.{spike,cmp}.log
#   cosim_work/results.tsv    machine-parsable, one row per (test,HART)
#   cosim_work/launch_margin.tsv  per-TEST launch-race margin audit (§ audits)
#   cosim_work/summary.txt    human summary + banner
#
# NOTE on the per-hart artifact naming: hart 0 is NOT special-cased. Every
# per-hart file carries its own `h<HH>` (hart 0 included), because one naming
# rule for four harts is far less error-prone than three suffixed names plus a
# bare one — and the bare names are exactly what a stale-artifact bug would
# reuse. Per-TEST artifacts (elab/sim log, image log, make log) keep their old
# unsuffixed names: there is one elaboration and one simulation per test.
# =============================================================================

source ~/vestarv/cdspaths.sh

HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE" || exit 1
ROOT="$(cd "$HERE/../../.." && pwd)"

# ---------------------------------------------------------------------------
# K2 (spec item 5, gap G6): PER-RUN ARTIFACT KEYING.
#
# `cosim_work/` used to be ONE flat slot for every sweep, so a later sweep
# silently destroyed an earlier one's evidence. That is not a hypothetical:
#   * 2026-08-02 16:23 -- the multi-hart sweep overwrote the single-hart sweep's
#     summary.txt/results.tsv from 16:20, which is why the K0 harness probe had
#     to establish the four single-hart pins from the S-series documents plus a
#     two-commit file-list argument instead of from a surviving artifact;
#   * 2026-08-03 -- the same class twice more in one K2 session, once by the
#     harness and once by ME, restoring a snapshot into the live slot.
# It is the same failure the LEGACY-ARTIFACT QUARANTINE below already guards a
# different symptom of: a stale artifact parses cleanly and reads as evidence.
#
# THE SPLIT. `cosim_work/` (COSIM) keeps what is REUSABLE and is not evidence --
# the built `vesta_ref`, the per-worker Xcelium libraries, the generated
# tb_cosim.vhd / check_image.py, the legacy quarantine. Everything a run
# PRODUCES moves under `cosim_work/runs/<RUN_KEY>/`, so two sweeps of different
# shape can no longer see each other's files at all.
#
# THE KEY is mechanical and self-describing, never a hand-typed name:
#     <config>__h<harts-in-this-sweep>__<test-list-basename>
# e.g. `default__h1__cosim_tests` (the standing single-hart gate) and
#      `default__h4__cosim_sh_tests` (the standing multi-hart gate).
# COSIM_CONFIG_KEY is the axis the per-config harness fills in (K2 items 2/4);
# it defaults to `default`, which is exactly what today's runs are.
#
# BACKWARD COMPATIBILITY. `cosim_work/{summary.txt,results.tsv,
# launch_margin.tsv,traces,spike,logs}` still exist -- as SYMLINKS into the
# run that wrote them last. Every existing reader, document and triage recipe
# that names those paths keeps working and keeps meaning "the most recent
# sweep", while the run that produced any given file is now recoverable by key.
# ---------------------------------------------------------------------------
COSIM="$HERE/cosim_work"
COSIM_CONFIG_KEY="${COSIM_CONFIG_KEY:-default}"

TOOLS_COSIM="$ROOT/tools/cosim"
COMPARE_PY="$TOOLS_COSIM/compare.py"
ISA_DIR="$ROOT/verification/isa"
TESTS_LIST_DEFAULT="$HERE/cosim_tests.txt"

# ---------------------------------------------------------------------------
# K2/G7 (2026-08-03): THE TWO HALVES OF A ROW'S POLARITY ARE NOW SELECTABLE.
#
# Until G7 this gate was nailed to one image set (`../rcf`) and one RTL
# (`cell_list_behavioral.txt`, i.e. hdl/common at whatever polarity is checked
# in), and acceptance B had to REFUSE any knobs-on image set outright, because
# `ensure_elf` built the reference ELFs at the Makefile's default
# RISCV_GCC_OPTS -- so an ON image set would have been compared against OFF-arm
# reference code. G7 makes all three halves selectable AND checked:
#
#   COSIM_RCF_LINK   the 3-char link under xcelium/riscv_test/ naming the DUT
#                    image set. Default `rcf`. MUST be 3 characters: the
#                    riscv_tb TEST_FILE generic is a FIXED 29-char string
#                    ("../" + 3 + "/" + a 22-char padded basename), which is
#                    also why per-polarity image sets are named `k<XX>` rather
#                    than spelled out (verify_stage.rcf_mapping).
#   COSIM_CELL_LIST  the flow's compile list. Default this flow's own. A
#                    per-config row points it at its `verify_<chip>/`
#                    cell list, whose staged MemoryMap.vhd carries that row's
#                    CORE_ENABLE_* constants. Relative paths inside an
#                    overriding list are resolved against the LIST's OWN
#                    directory (the staged lists say `hdl/MemoryMap.vhd`),
#                    never against this flow's.
#   the reference    ELF polarity is NOT a third free variable: it is derived
#                    FROM the image set's `.imgset` stamp, so it agrees with
#                    the images by construction rather than by agreement.
#
# The check that ties them together is `polarity_of_*` + the guard below.
# ---------------------------------------------------------------------------
COSIM_RCF_LINK="${COSIM_RCF_LINK:-rcf}"
[ ${#COSIM_RCF_LINK} -eq 3 ] || { echo "FATAL: COSIM_RCF_LINK='$COSIM_RCF_LINK' is ${#COSIM_RCF_LINK} chars.
       It must be exactly 3 -- the riscv_tb TEST_FILE generic is a FIXED
       29-char string and this link is 3 of them." >&2; exit 1; }
RCF_DIR="$HERE/../$COSIM_RCF_LINK"
CELL_LIST="${COSIM_CELL_LIST:-$HERE/cell_list_behavioral.txt}"
CELL_LIST_DIR="$(cd "$(dirname "$CELL_LIST")" 2>/dev/null && pwd)" || CELL_LIST_DIR="$HERE"

MAX_PARALLEL=${MAX_PARALLEL:-4}
TEST_TIMEOUT=${TEST_TIMEOUT:-180}
SPIKE_SLACK=${SPIKE_SLACK:-2000}
SPIKE_MAX=${SPIKE_MAX:-4000000}
NO_COMPILE=${NO_COMPILE:-0}
NO_BUILD=${NO_BUILD:-0}
CHECK_IMAGE=${CHECK_IMAGE:-1}
KEEP=${KEEP:-0}

PY36=/usr/bin/python3.6           # invariant 6: never bare python3 (aoj_cal)
SPIKE_ENV="$HOME/local/spike_env.sh"

# ---------------------------------------------------------------------------
# K2 ACCEPTANCE B (2026-08-03): THE REFERENCE RECIPE IS NOW DERIVED.
#
# These four were the frozen V0 literals (v0_report.md §5-§7), and the comment
# above them said "Do not improve these". That instruction was RIGHT for the
# whole V/W/S era -- an unreviewed edit to the reference recipe silently changes
# what the gate means -- and it is now SUPERSEDED, not ignored: the recipe is
# derived from ONE resolved config by a tracked, unit-tested function
# (tools/cosim/oracle_isa.py, 58/58) and every value it produces was compared
# against the literal it replaces before the switch-on.
#
# EXACTLY TWO THINGS MOVE at this switch-on, and BOTH are applied to BOTH sides
# of the identity gate, so the gate's EQUALITY must still hold:
#   1. `_zicntr` joins the --isa string.  The RTL admits cycle/time/instret
#      UNCONDITIONALLY -- there is no ENABLE_COUNTERS generic in vesta.vhd at
#      all -- so the old string described a chip that does not exist.
#   2. vesta_ref is given --pmpregions, ending an asymmetry that was already
#      there: stock spike has been invoked with --pmpregions=0 since V2 while
#      vesta_ref ran at cfg_t's 16.  Harmless only while nothing compared
#      touched a PMP CSR; load-bearing the moment a PMP row is compared.
# SPIKE_MEM and BOOT_MEM are ALSO derived now, and they derive to the SAME
# literals on this config (the derivation is checked against them by the unit
# test) -- so they are not a third moving part here, but they stop being wrong
# on Argus, where the hardcoded SPIKE_MEM was short by 64 KiB.
#
# NO SILENT FALLBACK. If the derivation cannot run, this script DIES. A fallback
# to the old literals would reintroduce exactly the failure this closes: a run
# that looks like a config's gate while modelling a different chip.
# ---------------------------------------------------------------------------
ORACLE_ISA_PY="$ROOT/tools/cosim/oracle_isa.py"
COSIM_CONFIG="${COSIM_CONFIG:-$ROOT/platform/common/config/ChipConfig.resolved.json}"
[ -f "$ORACLE_ISA_PY" ] || { echo "FATAL: $ORACLE_ISA_PY missing" >&2; exit 1; }
[ -f "$COSIM_CONFIG" ] || { echo "FATAL: no resolved config at $COSIM_CONFIG
       Run \`make -C platform/common generate\` first, or set COSIM_CONFIG." >&2; exit 1; }
_ORACLE="$("$PY36" "$ORACLE_ISA_PY" "$COSIM_CONFIG" --hdl-root "$ROOT/hdl/common" --shell)" \
    || { echo "FATAL: oracle derivation failed for $COSIM_CONFIG" >&2; exit 1; }
eval "$_ORACLE"
: "${SPIKE_ISA:?oracle derivation produced no SPIKE_ISA}"
# K2b: the comparator's config-gated amendment set. The LINE must be present
# even when its value is EMPTY (which is what the default config derives) --
# an absent line means an oracle_isa.py that predates K2b, and running a
# knobs-on row against a comparator that was never told about the amendments
# produces a DIVERGENCE THAT LOOKS LIKE AN RTL BUG. Refuse instead.
printf '%s\n' "$_ORACLE" | grep -q '^COMPARE_AMEND=' \
    || { echo "FATAL: the oracle derivation emitted no COMPARE_AMEND line.
       $ORACLE_ISA_PY predates K2b (the config-gated comparator amendments).
       A knobs-on row run without them diverges on record SHAPE, which reads
       as a DUT defect. Refusing rather than guessing." >&2; exit 1; }
COMPARE_AMEND="${COMPARE_AMEND-}"
: "${SPIKE_MEM:?oracle derivation produced no SPIKE_MEM}"
: "${SPIKE_PRIV:?oracle derivation produced no SPIKE_PRIV}"
: "${SPIKE_PMPREGIONS:?oracle derivation produced no SPIKE_PMPREGIONS}"

# ---------------------------------------------------------------------------
# V3: THE REFERENCE MODEL IS PLUGGABLE.
#   REF_MODE=vesta_ref (default) -- tools/cosim/vesta_ref.cc, a simif_t harness
#     on the pinned, UNPATCHED libriscv. The only path that can do MMIO load
#     injection and pc=0x0 boot (stock spike's sim_t nails a Debug Module over
#     [0x0,0x1000) unconditionally, riscv/sim.cc:72).
#   REF_MODE=spike -- the V2 stock-binary path, kept as the A/B control.
# The IDENTITY GATE (Fable/user ruling 2026-07-30) runs once per sweep and
# proves the harness still reproduces stock spike byte-for-byte. A
# libriscv-interface drift must fail LOUDLY, never silently.
# ---------------------------------------------------------------------------
REF_MODE=${REF_MODE:-vesta_ref}
VESTA_REF="${VESTA_REF:-$COSIM/vesta_ref}"
MK_INJECT="$TOOLS_COSIM/mk_inject.py"
MMIO_WIN=${MMIO_WIN:-0x4000:0x4000}
IDENTITY_GATE=${IDENTITY_GATE:-1}
IDENTITY_N=${IDENTITY_N:-2000}
# Bounded on purpose: stock spike on a passing test never terminates and writes
# ~1.4 GB in 2 min. Bound with --instructions, NEVER `head -N` on the producer
# (SIGPIPE kills it and leaves a stale log -- the CLAUDE.md xrun_batch trap).
IDENTITY_ELF="${IDENTITY_ELF:-$ISA_DIR/build/rv32ui/rv32ui-p-add}"

# ---------------------------------------------------------------------------
# COSIM_BOOT=1 -- BOOTROM-INCLUSIVE lockstep (V3, drops the D3 entry-alignment
# shortcut). The reference executes the REAL boot ROM from pc=0x0 and the test
# image reaches the TCM the same way the RTL gets it: through the injected SPI0
# RXBUF read stream. No ELF is handed to the reference at all -- so
# check_image.py stays the ONLY thing tying the two sides' inputs together
# (ruling B2), and it keeps running.
# Only possible because vesta_ref implements simif_t itself: stock spike nails
# a Debug Module over [0x0,0x1000) unconditionally (riscv/sim.cc:72).
# ---------------------------------------------------------------------------
COSIM_BOOT=${COSIM_BOOT:-0}
BOOT_ROM="${BOOT_ROM:-$HOME/vestarv/software/bootrom_mp/bin/rom.rcf}"
# K2 acceptance B: BOOT_MEM is DERIVED above (from SH_AW) and this `:-` default
# is therefore dead on any run that reaches here. Kept as the documented shape
# and as the fallback for an explicit `BOOT_MEM=` override, NOT as a value the
# script chooses for itself.
BOOT_MEM=${BOOT_MEM:-0x0:0x20000}
BOOT_ENTRY=0x00000000
# Amendment A9 / ruling A2: the two known benign boot X-reads. '*' = the FIRST
# x-tainted record at that address; a second one is still refused.
# A10 CORRECTION (2026-07-31, WT). This was ':000000b0' from V3 until the
# bit-granular mask made it checkable, and it was WRONG: the RTL drives
# bit 0 of this GPIO0 PxIN read to 1 (`# XBITS ... data 00000002 000000b1`
# -- ONLY bit 1 is undriven), and 0xb0 overwrote that driven bit with 0.
# mk_inject now REFUSES it (amendment A10: A2 permits filling UNDRIVEN
# bits, not contradicting DRIVEN ones). 0xb1 preserves every driven bit
# and fills the one undriven bit with 0. Measured: the four single-hart
# pins are UNCHANGED by the correction (104/1, md5 21aa28ec..., 4,668,509,
# #38140), i.e. the fabricated bit was never consumed differently by the
# reference -- harmless, and silent for two phases.
BOOT_ALLOW_X_1=${BOOT_ALLOW_X_1:-'*:00004000:000000b1'}
BOOT_ALLOW_X_2=${BOOT_ALLOW_X_2:-'*:0000420c:00000000'}
XALLOW="${XALLOW:-$HERE/cosim_xallow.txt}"
ALLOWX_DIR="${ALLOWX_DIR:-$HERE/cosim_allowx}"

# ---------------------------------------------------------------------------
# BRACKET_ISR=1 -- legacy-interrupt lockstep by ISR BRACKETING (V3, v3_design.md
# §4.4a as amended by the 2026-07-30 ruling). The reference CANNOT model the
# legacy vectored trap (`iret` is a custom encoding; the IVT dispatch and the PC
# push are not instructions) and must NOT be taught it -- that would be
# hand-writing the DUT's trap semantics into the golden model, which D1 forbids.
# So the RTL's ISR window (T .. X iret) is bracketed OUT of the comparison, its
# non-MMIO stores are replayed into the reference's RAM, the `iret` LANDING is
# VERIFIED trace-internally, and only then is the reference's pc aligned to it.
# Default OFF: with it off every path is bit-identical to the V3 sweep.
# NOTE what this does NOT verify: the ISR BODY. See v3_report.md §1.
# ---------------------------------------------------------------------------
BRACKET_ISR=${BRACKET_ISR:-0}

# ---------------------------------------------------------------------------
# V4: BRACKETS ARE NOT OPTIONAL ON A TILE — and the asymmetry is structural.
#
# BRACKET_ISR keeps governing hart 0 exactly as in V3 (default 0 = the standing
# 105-test gate is bit-identical to V3). For HH != 00 the bracket is FORCED ON,
# because a launched tile's stream contains an un-modellable window BY
# CONSTRUCTION and not by configuration:
#   * the tile parks on `EXTINGUISH` (0x0000100b, `.insn r 0x0b,1,0`), a CUSTOM
#     opcode the reference CANNOT execute — it raises an illegal instruction and,
#     with mtvec=0, vectors to 0 and re-runs the boot ROM forever (A11);
#   * the wake is the legacy vectored msip trap (`iret`, IVT dispatch, the
#     hardware return-PC push): none of it is instructions the reference has, and
#     teaching it would be hand-writing the DUT's trap semantics into the golden
#     model, which D1 forbids;
#   * so the whole `X wfi_enter` .. `X iret` span must be bracketed OUT and the
#     reference realigned across it. Amendment A11 is exactly that window.
# There is therefore no meaningful "tile with brackets off" configuration: it
# would be a guaranteed DIVERGE on every tile cell. Hart 0 is different — it
# never parks, so V3's opt-in is still the right default there.
# bracket_on <2-hex-digit hart tag> -> exit 0 when the bracket path is active.
bracket_on() {
    [ "$BRACKET_ISR" = 1 ] && return 0
    [ "$1" != "00" ] && return 0
    return 1
}

# realign_on <2-hex-digit hart tag> -> exit 0 when the REALIGNMENT SCRIPT channel
# (mk_inject --bracket-out / vesta_ref --bracket) is active for this hart.
#
# THIS IS NOT THE SAME QUESTION AS bracket_on, and conflating them cost a real
# divergence. ISR bracketing (bracket_on) is about crossing a window the reference
# cannot execute. PLANTING (A13) is about a shared-window load whose value another
# hart produced. Hart 0 in an sh* test needs the SECOND without the first: it takes
# no traps, but it polls DONE[h] in the shared window, and a hart-0 reference with
# no plants reads its own stale RAM there. Measured, before this fix:
#   rv32ui-p-shboot h00 DIVERGE(1) at compared record #50154 --
#   `lw t2,0(s7)` from 00010124 (shboot DONE[1]): rtl=d00e0001 spike=00000000.
# That is v4_design.md §3.5 item 1 in the flesh, and §0 finding 3's "planting
# changes hart 0's configuration too" made concrete.
#
# Scoped to MULTI so the STANDING 105-test single-hart gate keeps its exact V3
# configuration: with COSIM_HARTS="0" no other hart is ever launched, so nothing
# can write the shared window behind hart 0's back and there is nothing to plant.
realign_on() {
    bracket_on "$1" && return 0
    [ "$MULTI" = 1 ] && [ "$PLANT_WIN" != off ] && return 0
    return 1
}

# ---------------------------------------------------------------------------
# V4/A13 PLANT WINDOW. A load whose address lies in the SHARED-AND-WRITABLE
# window is served by POKING the reference's own RAM immediately before the
# consuming retire (a `P` record on the --bracket-out script), never by an MMIO
# callback: `simif_t::reservable()` defaults to `addr_to_mem()`, so an `lr.w`
# into a callback region throws trap_load_access_fault and an `sc.w` throws
# trap_store_access_fault — and LR/SC on the shared window is the entire subject
# of shcount/shspin/shlrsc/shlock. Planting keeps the region real RAM.
# Default = the base-N=4 complement of {boot ROM, MMIO page, own TCM} inside
# --mem 0x0:0x20000, i.e. NPU staging RAM + shared bulk RAM = [0xC000,0x20000).
#   PLANT_WIN=auto  -> ask mk_inject.py to DERIVE it from MemoryMap.vhd (A13's
#                      "never hardcoded twice" rule; needs --hdl-root)
#   PLANT_WIN=off   -> no plants at all (V3 behaviour; a negative control)
# P records ride the --bracket-out script, so plants exist exactly where the
# bracket script does (bracket_on). That is also mk_inject's own constraint:
# --plant REQUIRES --bracket-out.
# ---------------------------------------------------------------------------
# DEFAULT IS `auto`, not a literal. A13's rule is "derived from MemoryMap.vhd,
# never hardcoded twice", and a literal here IS the second place: the Argus
# `4*NHARTS` ledger moves these addresses, so a stale literal would silently plant
# the wrong window (or nothing) rather than fail. mk_inject derives it from
# RamStartAddress + RamSize (MemoryMap.vhd) and SH_AW (MCU.vhd's constant,
# cross-checked against hart_tile.vhd's generic default), and PRINTS what it
# derived. Verified equal to the old literal on this config: 0000c000..0001ffff.
PLANT_WIN=${PLANT_WIN:-auto}
HDL_ROOT="${HDL_ROOT:-$ROOT/hdl/common}"

die() { echo "FATAL: $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# V4: WHICH HARTS. COSIM_HARTS (default "0") is the whole switch; MULTIHART=1 is
# a shorthand an explicitly-set COSIM_HARTS overrides. With COSIM_HARTS="0" every
# path below is the V3 path — same generics, same artifact set minus the h00
# suffixes, same statuses, same banner lines. That is deliberate: the 105-test
# default sweep is a STANDING GATE whose banner is compared across phases, so
# multi-hart support must be additive, never a rewrite of the single-hart flow.
# ---------------------------------------------------------------------------
MULTIHART=${MULTIHART:-0}
if [ -z "${COSIM_HARTS+x}" ]; then
    if [ "$MULTIHART" = 1 ]; then COSIM_HARTS="0 1 2 3"; else COSIM_HARTS="0"; fi
fi
# Normalise (collapse whitespace, sort ascending) so the cell order, the status
# keys and the banner are deterministic whatever order the user typed.
COSIM_HARTS="$(printf '%s\n' $COSIM_HARTS | sort -n | tr '\n' ' ')"
COSIM_HARTS="${COSIM_HARTS%" "}"
[ -n "$COSIM_HARTS" ] || die "COSIM_HARTS is empty (want a subset of '0 1 2 3', hart 0 mandatory)"
_seen0=0; _prev=""
for _h in $COSIM_HARTS; do
    case "$_h" in
        0|1|2|3) ;;
        *) die "COSIM_HARTS='$COSIM_HARTS': '$_h' is not a decimal hart id in 0..3
       (the N=4 build has exactly four harts: tb_cosim.uut.dut.hart{0,1,2,3}.core)" ;;
    esac
    [ "$_h" = "$_prev" ] && die "COSIM_HARTS='$COSIM_HARTS': hart $_h listed twice
       (a duplicate would double-count cells and clobber its own status row)"
    [ "$_h" = 0 ] && _seen0=1
    _prev="$_h"
done
[ "$_seen0" = 1 ] || die "COSIM_HARTS='$COSIM_HARTS' does not include hart 0.
       Hart 0 is mandatory: it is the a0 pass gate that every cell is checked
       against, and the launch-race audit reads its trace."
NHARTS_SEL=$(set -- $COSIM_HARTS; echo $#)
# MULTI is the ONE flag the rest of the file branches on for cosmetic changes
# (progress line, banner lists, the --hart/--hartid flags). MULTI=0 <=> V3.
if [ "$COSIM_HARTS" = "0" ]; then MULTI=0; else MULTI=1; fi
unset _seen0 _prev _h

# ---------------------------------------------------------------------------
# K2 item 5 / G6: the RUN KEY and the per-run artifact directory.
# Declared HERE, not up with COSIM, because two of its three components are only
# known once COSIM_HARTS is normalised and the test list is resolved.
# ---------------------------------------------------------------------------
_LIST_FOR_KEY="${TESTS_FILE:-$TESTS_LIST_DEFAULT}"
_LIST_BASE="$(basename "$_LIST_FOR_KEY")"; _LIST_BASE="${_LIST_BASE%.txt}"
# Anything that is not [A-Za-z0-9._-] becomes '_' so the key can never escape the
# directory or surprise the shell.
_LIST_BASE="$(printf '%s' "$_LIST_BASE" | tr -c 'A-Za-z0-9._-' '_')"
_CFG_KEY="$(printf '%s' "$COSIM_CONFIG_KEY" | tr -c 'A-Za-z0-9._-' '_')"
RUN_KEY="${RUN_KEY:-${_CFG_KEY}__h${NHARTS_SEL}__${_LIST_BASE}}"
RUN_DIR="$COSIM/runs/$RUN_KEY"
unset _LIST_FOR_KEY _LIST_BASE _CFG_KEY

TRACE_DIR="$RUN_DIR/traces"
SPIKE_DIR="$RUN_DIR/spike"
LOG_DIR="$RUN_DIR/logs"
STATUS_DIR="$RUN_DIR/.status"
RESULTS="$RUN_DIR/results.tsv"
SUMMARY="$RUN_DIR/summary.txt"
LAUNCH_DIR="$RUN_DIR/.launch"            # one file per test, collected below
LAUNCH_TSV="$RUN_DIR/launch_margin.tsv"
INJECT_DIR="$RUN_DIR/inject"

# ONE-TIME MIGRATION of the pre-K2 flat layout. Anything a previous sweep left
# at the root of cosim_work/ is MOVED (never deleted -- it is someone's evidence
# until a human says otherwise, the same rule the legacy-log quarantine below
# follows) into `runs/legacy-flat-pre-K2/`, and the move is announced. Without
# this the root would carry a mixture of real files from an unknown sweep and
# symlinks into a known one, which is a worse trap than the one being fixed.
migrate_flat_layout() {
    local dst="$COSIM/runs/legacy-flat-pre-K2" n=0 f
    for f in summary.txt results.tsv launch_margin.tsv traces spike logs inject \
             .status .launch; do
        # A symlink at the root is THIS mechanism's own output -- leave it.
        [ -e "$COSIM/$f" ] && [ ! -L "$COSIM/$f" ] || continue
        mkdir -p "$dst"
        mv "$COSIM/$f" "$dst/$f" 2>/dev/null && n=$((n+1))
    done
    [ "$n" -gt 0 ] && {
        echo "  MIGRATED $n pre-K2 flat artifact(s) from $COSIM to $dst"
        echo "            (K2 item 5: sweeps now write cosim_work/runs/<RUN_KEY>/;"
        echo "             nothing was deleted -- the old sweep's evidence is intact)"
    }
    return 0
}

# The root-level compatibility symlinks. Every document, triage recipe and
# reader that names cosim_work/summary.txt (etc.) keeps working and keeps
# meaning "the sweep that ran last"; the run that produced it is recoverable by
# key. Relative targets so the tree stays movable.
link_latest() {
    local f
    for f in summary.txt results.tsv launch_margin.tsv traces spike logs inject; do
        [ -L "$COSIM/$f" ] && rm -f "$COSIM/$f"
        [ -e "$COSIM/$f" ] && continue      # a real file survived migration: never clobber
        ln -sfn "runs/$RUN_KEY/$f" "$COSIM/$f"
    done
    return 0
}

# 2-hex-digit hart tag — the tracer's own filename convention (vesta_tracer.vhd
# writes <TRACE_FILE>_h<HH>.trace and stamps `hart=<HH>` in its header).
hh_of() { printf '%02x' "$1"; }

# ── readelf: the entry PC comes from the ELF header, per test ─────────────────
READELF="$(command -v riscv-none-elf-readelf 2>/dev/null)"
if [ -z "$READELF" ]; then
    for c in "$HOME"/riscv-toolchain/*/bin/riscv-none-elf-readelf; do
        [ -x "$c" ] && READELF="$c" && break
    done
fi
[ -x "$READELF" ] || die "riscv-none-elf-readelf not found (source cdspaths.sh?)"

# ── guards ────────────────────────────────────────────────────────────────────
[ -f "$CELL_LIST" ] || die "no cell list at $CELL_LIST"
grep -q 'vesta_tracer.vhd' "$CELL_LIST" \
    || die "$CELL_LIST has no vesta_tracer.vhd — the V1 tracer is
       not staged in this flow, so TRACE_ENABLE would silently do nothing."
if [ -f "$RCF_DIR/.nharts" ]; then
    NH="$(cat "$RCF_DIR/.nharts")"
    [ "$NH" = "4" ] || die "$COSIM_RCF_LINK/.nharts = $NH (expected 4). Rebuild with
       verification/isa/build_mp_images.sh 4 ../../xcelium/riscv_test/rcf"
fi
# K2 acceptance B: THE RESOLVED CONFIG IS A GLOBAL SLOT WITH NO LOCK.
# platform/common/config/ChipConfig.resolved.json holds whatever the LAST
# `make generate` wrote -- a `make verify CONFIG=argus` leaves Argus there, and
# the K0 inventory probe §6a recorded exactly that state arising by accident.
# Deriving the reference recipe from it therefore needs the file to be checked
# against the images this gate actually runs, not trusted. Two cross-checks,
# both cheap, both fatal:
CFG_NHARTS="$("$PY36" -c 'import json,sys; print(json.load(open(sys.argv[1]))["numHarts"])' \
              "$COSIM_CONFIG" 2>/dev/null)" || die "cannot read numHarts from $COSIM_CONFIG"
[ "$CFG_NHARTS" = "4" ] || die "the resolved config at
       $COSIM_CONFIG
       has numHarts=$CFG_NHARTS, but this gate runs the N=4 image set and is
       nailed to four harts. The reference recipe would describe a DIFFERENT
       CHIP from the one being simulated. Re-run \`make -C platform/common
       generate\` (no CONFIG=) to restore the default, or point COSIM_CONFIG at
       the right resolved config."
# ...and the IMAGE POLARITY, which G7 turns from a BLANKET REFUSAL into a MATCH
# TEST. The acceptance-B guard read: "this gate's reference ELFs are built at
# DEFAULT RISCV_GCC_OPTS, so it can only compare an image set built with NO
# -DCORE_ENABLE_*", and it refused every knobs-on row. That was the correct
# guard for a gate whose reference half could not follow the images. It can now:
# IMG_DEFINES below is read from the image set's own `.imgset` stamp and handed
# to `ensure_elf`, so the reference ELFs are built at the images' polarity BY
# CONSTRUCTION. What remains genuinely checkable -- and what the blanket refusal
# was standing in for -- is the OTHER pair:
#
#     the RTL this flow compiles   vs   the polarity the images were built at
#
# Those two are independent (one comes from CELL_LIST's MemoryMap.vhd, the other
# from the image build's -D list) and disagreeing is exactly the "OFF-arm
# software against ON-polarity hardware, and the failure mode is a PASS" defect
# that verify.sh's polarity gate closes for the suite. This is the same gate for
# the lockstep flow, with the same two sources of truth, and it is deliberately
# a READ-BACK of the staged file rather than a recomputation from the config: a
# generator that failed to emit a constant must be caught, not agreed with.
#
# NOTE the asymmetry that is NOT a defect: `.imgset` is absent from image sets
# built before K2/G3 (rcf_argus today). An absent stamp is treated as "no
# -DCORE_ENABLE_*", which is an ASSERTION about those sets, labelled as one
# here and measured for rcf/ at acceptance D (its shcboz image contains zero
# cbo.zero encodings).
IMG_DEFINES=""
IMG_ON=""
if [ -f "$RCF_DIR/.imgset" ]; then
    IMGSET_HAVE="$(cat "$RCF_DIR/.imgset")"
    IMG_DEFINES="${IMGSET_HAVE#*DEFINES=}"
    [ "$IMG_DEFINES" = "(none)" ] && IMG_DEFINES=""
else
    IMGSET_HAVE="NHARTS=4 DEFINES=(none)   [ASSERTED: no .imgset stamp in $COSIM_RCF_LINK/]"
fi
# knob-name view of the image side: "-DCORE_ENABLE_ZICBOZ" -> "ZICBOZ"
for _d in $IMG_DEFINES; do
    case "$_d" in -DCORE_ENABLE_*) IMG_ON="$IMG_ON ${_d#-DCORE_ENABLE_}" ;; esac
done
# ...and of the RTL side, read out of the MemoryMap.vhd this flow will compile.
MEMMAP_VHD="$(awk '/MemoryMap\.vhd[[:space:]]*$/ {print $0; exit}' "$CELL_LIST")"
[ -n "$MEMMAP_VHD" ] || die "no MemoryMap.vhd line in $CELL_LIST — cannot read the
       RTL's CORE_ENABLE_* polarity, so the image/RTL match cannot be checked."
case "$MEMMAP_VHD" in /*) ;; *) MEMMAP_VHD="$CELL_LIST_DIR/$MEMMAP_VHD" ;; esac
[ -f "$MEMMAP_VHD" ] || die "cell list names $MEMMAP_VHD, which does not exist"
# Same predicate as verify_stage.memorymap_on_knobs: `constant CORE_ENABLE_<K> :
# boolean := true`, VHDL comments stripped first, case-insensitive.
RTL_ON="$(sed 's/--.*//' "$MEMMAP_VHD" \
          | grep -ioE 'constant[[:space:]]+CORE_ENABLE_[A-Z0-9_]+[[:space:]]*:[[:space:]]*boolean[[:space:]]*:=[[:space:]]*true' \
          | sed -E 's/.*CORE_ENABLE_([A-Za-z0-9_]+).*/\1/' | tr 'a-z' 'A-Z' | sort -u | tr '\n' ' ')"
# The five base-ISA knobs are true in almost every build and no test #ifdefs on
# them (verify_stage.DEFINE_KNOBS says so, and says why): comparing them would
# make every row mismatch on MUL/DIV/ATOMICS/COMPRESSED/BITMANIP.
RTL_ON_CMP="$(for k in $RTL_ON; do
        case "$k" in MUL|DIV|ATOMICS|COMPRESSED|BITMANIP) ;; *) echo "$k" ;; esac
    done | sort -u | tr '\n' ' ')"
IMG_ON_CMP="$(for k in $IMG_ON; do echo "$k"; done | sort -u | tr '\n' ' ')"
if [ "$RTL_ON_CMP" != "$IMG_ON_CMP" ]; then
    die "POLARITY MISMATCH between the RTL this flow compiles and the images it runs.
       RTL   ($MEMMAP_VHD)
             ON = ${RTL_ON_CMP:-(none)}
       IMAGE ($COSIM_RCF_LINK/.imgset = '$IMGSET_HAVE')
             ON = ${IMG_ON_CMP:-(none)}
       These are the two halves of one switch. Comparing them apart means the
       DUT executes one arm of every #ifdef while the reference ELFs -- which
       are built at the IMAGE polarity -- execute the other. Refusing.
       A knobs-on lockstep row sets BOTH: COSIM_CELL_LIST=<verify_<chip>>/
       cell_list_behavioral.txt and COSIM_RCF_LINK=<that row's 3-char link>."
fi
[ -f "$SPIKE_ENV" ] || die "$SPIKE_ENV missing (V0 deliverable)"

# =============================================================================
# helpers
# =============================================================================

# strip the leading x-padding run (the Makefile's own rule, v2_test_set.md §1)
strip_pad() { local s="$1"; echo "${s#"${s%%[!x]*}"}"; }

# rcf basename -> suite directory under verification/isa/build
suite_of() { local s; s="$(strip_pad "$1")"; echo "${s%%-p-*}"; }

# PATTERN -> full rcf basename, exactly one ../rcf/*PAT*.rcf match.
# CLAUDE.md: the glob is *PAT*.rcf, so a pattern containing ".rcf" never
# matches — full basenames only.
resolve_rcf() {
    local pat="$1" m
    pat="${pat##*/}"; pat="${pat%.rcf}"
    mapfile -t m < <(cd "$RCF_DIR" && ls *"$pat"*.rcf 2>/dev/null)
    case ${#m[@]} in
        0) echo "NOMATCH"; return 1 ;;
        1) echo "${m[0]}"; return 0 ;;
        *) echo "AMBIGUOUS:${m[*]}"; return 1 ;;
    esac
}

# ── the flash-image / ELF provenance check ────────────────────────────────────
# The RTL runs ../rcf/<padded>.rcf (a flash_prepend'ed image); Spike runs
# verification/isa/build/<suite>/<test> (an ELF). Nothing in the tree ties those
# two to the same compile, so a STALE ../rcf image against a freshly built ELF
# would manufacture divergences across the whole sweep. This walks the flash
# image's [0x10adbeef,start,end,words...] segment blocks and checks every loaded
# word against the raw padded image the same make target regenerates from the
# ELF (build/<suite>/<test>.rcf, base 0x8000).
emit_check_image() {
    cat > "$COSIM/check_image.py" <<'PY'
import sys
CMD='00010000101011011011111011101111'   # 0x10adbeef
EXE='11001010111111101011101010111110'   # 0xcafebabe
def words(p):
    out=[]
    for L in open(p):
        L=L.strip()
        if L: out.append(L)
    return out
def main(flash,raw):
    f=words(flash); r=words(raw); i=0; checked=0; bad=[]
    # The bootrom copies each [cmd,start,end,words] block in order and blocks
    # OVERLAP by design: flash_prepend.sh emits a leading 0x8000-0x81FF
    # zero-fill block that the real IVT block then overwrites. So replay the
    # blocks into a memory image (later write wins) and compare THAT.
    mem={}
    while i < len(f):
        if f[i]==EXE: break
        if f[i]!=CMD:
            print('BADFORMAT line %d: %s'%(i+1,f[i])); return 2
        start=int(f[i+1],2); end=int(f[i+2],2); i+=3
        n=(end-start)//4
        for k in range(n):
            mem[start+4*k]=f[i+k]
        i+=n
    for addr in sorted(mem):
        j=(addr-0x8000)//4
        if j<0 or j>=len(r):
            bad.append((addr,'out-of-raw-range',mem[addr])); continue
        if r[j]!=mem[addr]:
            bad.append((addr,r[j],mem[addr]))
        checked+=1
    if bad:
        print('IMAGE-MISMATCH checked=%d bad=%d'%(checked,len(bad)))
        for a,e,g in bad[:8]:
            print('  addr=0x%08x raw=%s flash=%s'%(a,e,g))
        return 1
    print('IMAGE-OK words=%d'%checked)
    return 0
if __name__=='__main__':
    sys.exit(main(sys.argv[1],sys.argv[2]))
PY
}

# ── K2/G7: the reference ELF build polarity, and the cache that is blind to it
#
# `ensure_elf` used to invoke `make build/<suite>/<test>` with no
# RISCV_GCC_OPTS, i.e. the Makefile's default: no -DNHARTS, no -DCORE_ENABLE_*.
# For the default N=4 no-knob row that is right by accident. For any other row
# it means the reference executes the OTHER arm of every #ifdef from the DUT.
# The authority for the polarity is the IMAGE SET'S OWN STAMP -- not a
# re-derivation from a config -- because the images' stamp is the truth about
# the images, and the reference must follow the images.
REF_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles -DNHARTS=4"
[ -n "$IMG_DEFINES" ] && REF_GCC_OPTS="$REF_GCC_OPTS $IMG_DEFINES"
REF_IMGSET="NHARTS=4 DEFINES=${IMG_DEFINES:-(none)}"
#
# THE ELF CACHE IS POLARITY-BLIND, and that is a hazard with teeth. All ELFs
# live in ONE `verification/isa/build/` with no per-polarity keying, and
# `ensure_elf` rebuilds only what is MISSING -- so a build/ left behind by an
# ON-polarity `make verify` would be silently reused by an OFF-polarity gate.
# (Observed live: after `make verify CONFIG=castalia_umode.json`, build/ held
# ELFs compiled with -DCORE_ENABLE_TRAPCSR -DCORE_ENABLE_UMODE.) So the cache
# now carries a stamp, `build/.imgset`, written both here and by
# build_mp_images.sh (which rm -rf's build/ and refills it wholesale, so its
# stamp is exactly true). A stamp that disagrees -- or is ABSENT, which means
# the polarity is unknown -- forces a full rebuild. Fail-safe direction
# (method rule 15): an unknown cache is treated as a wrong one.
ELF_CACHE_STAMP="$ISA_DIR/build/.imgset"
sync_elf_cache() {
    local have=""
    [ -f "$ELF_CACHE_STAMP" ] && have="$(cat "$ELF_CACHE_STAMP")"
    if [ "$have" != "$REF_IMGSET" ]; then
        if [ -d "$ISA_DIR/build" ]; then
            echo "  ELF cache polarity: have '${have:-<unstamped>}' want '$REF_IMGSET'"
            echo "                      -> rm -rf verification/isa/build (full reference rebuild)"
            rm -rf "$ISA_DIR/build"
        fi
        mkdir -p "$ISA_DIR/build"
        printf '%s\n' "$REF_IMGSET" > "$ELF_CACHE_STAMP"
    fi
}

# ── ELF (and its raw rcf) for one test, built if missing ──────────────────────
# ONLY the single-target `make build/<suite>/<test>` form: `make <suite>-flash`
# riscv32-cleans and rebuilds all 80 images AND rewrites ../rcf (CLAUDE.md).
ensure_elf() {
    local suite="$1" test="$2" want_rcf="$3" out built=0
    local elf="$ISA_DIR/build/$suite/$test"
    local raw="$ISA_DIR/build/$suite/$test.rcf"
    local mlog="$LOG_DIR/$test.make.log"
    if [ ! -f "$elf" ]; then
        [ "$NO_BUILD" = 1 ] && { echo "MISSING"; return 1; }
        out="$(cd "$ISA_DIR" && make "build/$suite/$test" RISCV_GCC_OPTS="$REF_GCC_OPTS" 2>&1)"
        printf '%s\n' "$out" > "$mlog"
        [ -f "$elf" ] || { echo "BUILDFAIL"; return 1; }
        built=1
    fi
    # The .rcf is a SEPARATE target. The ELF recipe recurses into it when it
    # actually relinks, but an already-present ELF makes `make build/<s>/<t>`
    # a no-op and leaves no .rcf — which is exactly how rv32ua-p-lrsc arrived
    # with an ELF and no raw image. Ask for it explicitly.
    if [ "$want_rcf" = 1 ] && [ ! -f "$raw" ]; then
        [ "$NO_BUILD" = 1 ] && { echo "MISSING-RCF"; return 1; }
        out="$(cd "$ISA_DIR" && make "build/$suite/$test.rcf" RISCV_GCC_OPTS="$REF_GCC_OPTS" 2>&1)"
        printf '%s\n' "$out" >> "$mlog"
        [ -f "$raw" ] || { echo "RCFFAIL"; return 1; }
        built=1
    fi
    [ "$built" = 1 ] && { echo "BUILT"; return 0; }
    echo "PRESENT"; return 0
}

# ── one worker library: compiled ONCE, then re-elaborated per test ────────────
# Per-worker libs (rather than one shared lib) keep disk flat — every test
# overwrites the SAME work.cs_run_w<N> snapshot — and sidestep any question about
# concurrent writers to one .pak. Compile is ~1 s, so N of them is free.
setup_worker_lib() {
    # NOTE: two statements, deliberately. `local n="$1" wl="$COSIM/w$n"` expands
    # every argument BEFORE any assignment takes effect, so wl would come out as
    # ".../w" — one shared library for every worker.
    local n="$1"
    local wl="$COSIM/w$n"
    mkdir -p "$wl/xcelium.d/work" || return 1
    cat > "$wl/cds.lib" <<LIB
SOFTINCLUDE ${XCELIUM_HOME}/tools/xcelium/files/cds.lib
DEFINE work ./xcelium.d/work
LIB
    [ "$NO_COMPILE" = 1 ] && return 0
    rm -rf "$wl/xcelium.d/work"; mkdir -p "$wl/xcelium.d/work"
    local vl=() vh=() f
    for f in $(< "$CELL_LIST"); do
        case "$f" in \#*) continue ;; esac
        # K2/G7: a relative entry belongs to the LIST'S directory, not to this
        # flow's. The staged verify_<chip> lists say `hdl/MemoryMap.vhd`.
        case "$f" in /*) ;; *) f="$CELL_LIST_DIR/$f" ;; esac
        case "${f##*.}" in
            v)        vl+=("$f") ;;
            vhd|vhdl) vh+=("$f") ;;
        esac
    done
    if [ ${#vl[@]} -gt 0 ]; then
        xmvlog -cdslib "$wl/cds.lib" -WORK work "${vl[@]}" \
            > "$LOG_DIR/compile_vlog_w$n.log" 2>&1 || return 1
    fi
    xmvhdl -cdslib "$wl/cds.lib" -V200X -WORK work -CONTROLRELAX nlstex -RELAX \
        "${vh[@]}" "$COSIM/tb_cosim.vhd" \
        > "$LOG_DIR/compile_vhdl_w$n.log" 2>&1 || return 1
    return 0
}

# =============================================================================
# V4 THE TWO FREE AUDITS (v4_design.md §4.7). Both are cheap text passes over
# files that already exist, and NEITHER may abort a run: they classify, they
# never veto. They exist because the a0 contract cannot see either failure —
# a tile that never left the boot ROM still lets hart 0 write 0xCAFEBABE.
# awk has no hex literal parsing in POSIX and strtonum() is a gawk extension, so
# both passes carry their own h2d(). The trace's cycle field is token 3 and HEX;
# a record's kind is token 1; comment/diagnostic lines start with '#'.
# =============================================================================

# participation_of <trace>  ->  PARTICIPATED | PARKED-ONLY | NO-TRACE
# PARTICIPATED = at least one R record retired OUTSIDE the shared boot-ROM
# window [0,0x4000). PARKED-ONLY = every retire was ROM code, i.e. the hart
# booted, parked, and the test never launched it: real for harts 1-3 in every
# single-hart test, and a TEST-EFFICACY FINDING in a test whose whole point is
# contention. A PARKED-ONLY hart must never be read as coverage, which is why
# this lands in its own results column instead of being folded into the status.
# V4/C2 CORRECTION — the old discriminator (any retire at pc >= 0x4000) is WRONG
# for a LAUNCHED tile, and it was wrong in the direction that hides findings.
#
# Measured on rv32ui-p-shmem_mp hart 1: of 229 retires, exactly ONE has
# pc >= 0x4000 — `R 01 00000012 0000814c 00008067` — the IVT slot-83 jump, which
# lives in the private TCM at 0x814c. So merely TAKING the msip trap flipped the
# classification to PARTICIPATED on a tile that T1 proves never reaches
# `tile_body`. That is precisely the misreport the audit exists to prevent, and it
# contradicted C1's own PARKED-ONLY finding for this test.
#
# The right question is "did this hart retire any instruction of the TEST IMAGE",
# so the threshold is the ELF ENTRY (passed in, never hardcoded — the images'
# entry is where the loader lands the tile). Four classes now, because "launched
# but never arrived" is a genuinely distinct and reportable state:
#   PARTICIPATED  retired at pc >= entry -> it ran test-image code
#   LAUNCHED-ONLY retired outside the boot ROM but never reached the image: it
#                 took the loader trap and was still in the ISR at sim end (T1)
#   PARKED-ONLY   every retire was boot ROM: booted, parked, never launched
#   NO-TRACE      no retires at all (a hart held in reset / cold-gated)
# NEITHER PARKED-ONLY NOR LAUNCHED-ONLY MAY EVER BE READ AS COVERAGE.
# participation_of <trace> <entry-pc-hex>
participation_of() {
    [ -s "$1" ] || { echo "NO-TRACE"; return 0; }
    local ep="${2:-0x8200}"; ep="${ep#0x}"
    awk -v ep="$ep" '
      function h2d(s,  i,c,v,n) { n=0; s=tolower(s)
          for (i=1;i<=length(s);i++) { c=substr(s,i,1)
              v=index("0123456789abcdef",c)-1; if (v<0) return -1; n=n*16+v }
          return n }
      BEGIN { entry = h2d(ep); if (entry < 0) entry = 33280 }
      $1=="R" { n++; a=h2d($4)
                if (a >= entry) img++
                else if (a >= 16384) out++ }
      END { if (n+0 == 0) print "NO-TRACE"
            else if (img+0 > 0) print "PARTICIPATED"
            else if (out+0 > 0) print "LAUNCHED-ONLY"
            else print "PARKED-ONLY" }' "$1" 2>/dev/null || echo "NO-TRACE"
}

# launch_margin_audit <hart0-trace> <outfile>
# Writes one TAB row: <margin|n/a> <msip_cycle> <hart0_last_cycle> <msip_addr>.
# margin = (cycle of hart 0's LAST record) - (cycle of hart 0's LAST store of
# 00000001 to msip[1..3] = 0x5004/0x5008/0x500c), in clk_cpu cycles. That is the
# window a launched tile has to boot from the shared ROM, take its msip ISR and
# copy its image before hart 0 ends the sim; measured at ~1,011 cycles against a
# 32,768-cycle copy in shmem_mp (8.0 cycles/word x 4096, MEASURED), i.e. ~32x
# short -- finding T1 in ~/vesta_docs/lockstep/rtl_findings.md. n/a = launched nobody.
launch_margin_audit() {
    local tr="$1" out="$2"
    printf 'n/a\t-\t-\t-\n' > "$out" 2>/dev/null || return 0
    [ -s "$tr" ] || return 0
    awk '
      function h2d(s,  i,c,v,n) { n=0; s=tolower(s)
          for (i=1;i<=length(s);i++) { c=substr(s,i,1)
              v=index("0123456789abcdef",c)-1; if (v<0) return -1; n=n*16+v }
          return n }
      $1=="M" && $2=="00" && $4=="S" && $6=="4" && $7=="00000001" &&
        ($5=="00005004" || $5=="00005008" || $5=="0000500c") { ms=$3; ma=$5 }
      $1=="R" || $1=="M" || $1=="C" || $1=="T" || $1=="X" { last=$3 }
      END { if (ms == "" || last == "") { print "n/a\t-\t-\t-"; exit }
            printf "%d\t%s\t%s\t%s\n", h2d(last)-h2d(ms), ms, last, ma }' \
        "$tr" > "$out" 2>/dev/null
    [ -s "$out" ] || printf 'n/a\t-\t-\t-\n' > "$out" 2>/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# V4 CAPABILITY PROBE — run ONCE, before the workers fork, so every worker
# inherits the answer. The two V4 reference/comparator flags are NOT optional
# extras: without --stop-before-sleep a tile's stream runs into EXTINGUISH
# (0x0000100b, a custom opcode) and without --hartid the reference reads
# mhartid=0 on every hart. Either absence must fail LOUDLY per cell —
# a silent fallback would hand back a VACUOUS PASS on a hart that was never
# really compared. Note WHY this is a probe and not a try-and-see: argparse
# exits 2 on an unknown option, and 2 is the comparator's "RTL stream short".
# ---------------------------------------------------------------------------
#
# C2 EXTENSION: the probe now covers ALL THREE tools, in the same style and for
# the same reason. The new V4 mechanisms live on flags that did not exist when
# this runner was written, and two of them are silent when absent:
#   * mk_inject --plant : without it NO `P` records are emitted, so the
#     reference reads whatever its RAM happened to hold in the shared window and
#     the comparison of every shared load is VACUOUS. `mk_inject.py` exits 0 and
#     writes a perfectly well-formed list — nothing in the artifacts says the
#     plants are missing. That is exactly the vacuous-PASS shape this program
#     exists to refuse, so an absent --plant is an INFRA-FAIL naming the flag.
#   * mk_inject --bracket-out / vesta_ref --bracket : the channel the P/G/F
#     records ride on. --plant REQUIRES --bracket-out (mk_inject's own rule).
#   * compare.py --bracket-isr : A11's sleep bracket. Without it a tile's `T`
#     record is reported as a control-flow divergence, which is a DIVERGE, not a
#     silent pass — but it is still a wrong verdict, so it is refused too.
# The flag NAMES are probed, never assumed: the injector's window flag may be
# spelled `--plant <base:size>` or derived from MemoryMap.vhd (`--plant auto`),
# and both are the same `--plant` token in --help. If the token is absent the
# runner does NOT fall back to "no plants" — it fails the cell and says which
# flag it wanted.
CAP_CMP_HART=0; CAP_CMP_STOPSLEEP=0; CAP_CMP_BRACKET=0; CAP_CMP_AMEND=0
CAP_REF_HARTID=0
CAP_REF_BRACKET=0; CAP_MK_PLANT=0; CAP_MK_BRACKETOUT=0; CAP_MK_HDLROOT=0
probe_capabilities() {
    # compare.py --bracket-isr and the mk_inject/vesta_ref bracket channel are
    # needed by BRACKET_ISR=1 in single-hart mode too, so unlike the V3 probe
    # this one is not gated on $MULTI.
    local h=""
    [ -f "$COMPARE_PY" ] && h="$("$PY36" "$COMPARE_PY" --help 2>&1)"
    printf '%s' "$h" | grep -q -- '--hart HH' && CAP_CMP_HART=1
    printf '%s' "$h" | grep -q -- '--stop-before-sleep' && CAP_CMP_STOPSLEEP=1
    printf '%s' "$h" | grep -q -- '--bracket-isr' && CAP_CMP_BRACKET=1
    printf '%s' "$h" | grep -q -- '--amend' && CAP_CMP_AMEND=1
    local m=""
    [ -f "$MK_INJECT" ] && m="$("$PY36" "$MK_INJECT" --help 2>&1)"
    printf '%s' "$m" | grep -q -- '--plant' && CAP_MK_PLANT=1
    printf '%s' "$m" | grep -q -- '--bracket-out' && CAP_MK_BRACKETOUT=1
    printf '%s' "$m" | grep -q -- '--hdl-root' && CAP_MK_HDLROOT=1
    local r=""
    if [ "$REF_MODE" = vesta_ref ] && [ -x "$VESTA_REF" ]; then
        r="$( ( source "$SPIKE_ENV"; "$VESTA_REF" --help ) 2>&1 )"
        printf '%s' "$r" | grep -q -- '--hartid' && CAP_REF_HARTID=1
        printf '%s' "$r" | grep -q -- '--bracket' && CAP_REF_BRACKET=1
    fi
    return 0
}

# ── comparator invocation + exit-code mapping ─────────────────────────────────
# CLI contract (compare.py's own docstring / tools/cosim/README.md):
#   compare.py --rtl <trace> --spike <log> --entry <pc> [--max-records M]
#   0 match | 1 divergence | 2 RTL stream short | 3 Spike stream short
#   4 Amendment-A5 x-corrupted record (INVESTIGATE) | 5 parse/usage error
#
# TWO PASSES, and the first one is load-bearing. Both sides spin forever in
# RVTEST_PASS, so there is no natural end: Spike is given a GENEROUS
# --instructions bound (so "Spike short" keeps its real meaning — a trapping
# instruction makes Spike print nothing and exit rc=0) and the COMPARISON is
# instead bounded by the RTL's own compared-record count, which the comparator
# itself reports via `--count --quiet`. Without this the tail of every single
# test reads as exit 2 "RTL stream exhausted early" — measured: all 4 tests of
# the first mini-sweep came back DIVERGE(2) purely from the Spike slack.
#
# V4: $5 = the 2-digit hart tag ("00".."03"), empty/"00" in the V3 path. It does
# two things — it selects the hart from the stream (--hart, only in multi-hart
# mode, so the default invocation keeps EXACTLY the V3 command line) and it
# re-maps exit 2. See the exit-2 comment at the case below.
#
# Prints: "<status> <compared-records>" on one line.
run_compare() {
    local trace="$1" slog="$2" entry="$3" out="$4" hh="${5:-00}" rc m
    # Amendment A9 (ruling A2): the x-wildcard allowlist. Only supplied when the
    # file exists, so a missing file degrades to the strict A5 behaviour rather
    # than to a silent pass.
    local xa=()
    [ -f "$XALLOW" ] && xa=(--x-allow "$XALLOW")
    # K2b: the config-gated amendments, DERIVED from the resolved config by
    # oracle_isa.py. Empty on the default config, so the default gate's command
    # line is unchanged character for character.
    [ -n "$COMPARE_AMEND" ] && xa+=(--amend "$COMPARE_AMEND")
    # V4: forced on for a tile (see bracket_on) — Amendment A11's sleep window is
    # in a tile's stream by construction, not by configuration.
    bracket_on "$hh" && xa+=(--bracket-isr)
    # V4 per-hart flags. BOTH passes must get them: --count is what bounds the
    # second pass, so a --count over a differently-truncated stream would ask for
    # more records than the second pass is willing to compare.
    #
    # --stop-before-sleep AND --bracket-isr ARE MUTUALLY EXCLUSIVE, and getting
    # this wrong is SILENT. Truncation cuts the stream at the FIRST `X wfi_enter`;
    # the A11 sleep bracket instead carries the reference ACROSS the park and
    # keeps comparing everything after the `X iret`. With both on, truncation wins
    # and every Stage 2/3 tile would be compared over its 11-retire ROM park
    # prefix ALONE, reporting PASS on 12 records while the entire post-launch test
    # body — the whole point of the multi-hart phase — went uncompared. That is
    # exactly the vacuous-PASS shape this program exists to refuse.
    # So: bracket if we can (A11 covers a park that never closes too — the window
    # simply never terminates and its interior leaves the compared stream), and
    # truncate only as the fallback for a tile whose bracket path is off.
    if [ "$MULTI" = 1 ]; then
        xa+=(--hart "$hh")
        if [ "$hh" != "00" ] && ! bracket_on "$hh"; then
            xa+=(--stop-before-sleep)
        fi
    fi
    if [ ! -f "$COMPARE_PY" ]; then
        echo "compare.py not present at $COMPARE_PY" > "$out"
        echo "COMPARE-PENDING 0"; return 0
    fi
    m="$("$PY36" "$COMPARE_PY" --rtl "$trace" --spike "$slog" --entry "$entry" \
             "${xa[@]}" --count --quiet 2> "$out")"
    rc=$?
    if [ "$rc" -ne 0 ] || ! [ "$m" -ge 0 ] 2>/dev/null; then
        echo "INFRA-FAIL(compare-count-rc$rc) 0"; return 0
    fi
    "$PY36" "$COMPARE_PY" --rtl "$trace" --spike "$slog" --entry "$entry" \
        "${xa[@]}" --max-records "$m" > "$out" 2>&1
    rc=$?
    case "$rc" in
        0) echo "PASS $m" ;;
        1) echo "DIVERGE(1) $m" ;;
        # exit 2 = "RTL stream exhausted early". On hart 0 that is a finding.
        # On a TILE it is the normal shape of the sim's own ending: hart 0's a0
        # watch kills the simulation wherever the tile happens to be, so the
        # tile's trace is truncated MID-STREAM by construction. That is an
        # infrastructure limit of the observation, NOT a divergence and NOT a
        # pass — it gets its own name so it can never be read as either.
        2) if [ "$hh" != "00" ]; then echo "INFRA-FAIL(tile-stream-short) $m"
           else echo "DIVERGE(2-rtlshort) $m"; fi ;;
        3) echo "DIVERGE(3-spikeshort) $m" ;;
        4) echo "DIVERGE(4-xcorrupt) $m" ;;
        5) echo "INFRA-FAIL(compare-usage) $m" ;;
        *) echo "INFRA-FAIL(compare-rc$rc) $m" ;;
    esac
}

# ── one test, end to end ──────────────────────────────────────────────────────
# $1 = rcf basename (padded), $2 = worker index
# ---------------------------------------------------------------------------
# ref_invoke  <bound> <entry> <elf> <commitlog> <stdoutlog> <injectlist> <bracket>
#             [bootmode] [hartid]
#   Runs the configured reference model. Both back ends emit the SAME
#   --log-commits wire format, so tools/cosim/compare.py needs no change -- and
#   that equivalence is precisely what identity_gate defends.
#   V4: <bootmode> defaults to $COSIM_BOOT and <hartid> to 0, so an unchanged
#   7-argument call is the V3 call. The tile harts pass bootmode=1 explicitly
#   (they have nothing BUT boot ROM to compare) and their own hartid, which is
#   what makes the reference's `csrr t0,mhartid` take the tile_boot branch.
#   --hartid is only added in multi-hart mode: passing `--hartid 0` is a no-op
#   for the model, but NOT passing it keeps the single-hart command line
#   byte-identical to V3's, which the standing gate is entitled to.
# ---------------------------------------------------------------------------
ref_invoke() {
    local bound="$1" entry="$2" elf="$3" clog="$4" olog="$5" inj="$6" brk="$7"
    local boot="${8:-$COSIM_BOOT}" hid="${9:-0}"
    # V4: the bracket script also carries the A12 `G`, A13 `P` and A14 `F`
    # records, so it is passed whenever bracket_on says the mechanism is active
    # for this hart — forced on for HH != 00, BRACKET_ISR-gated on hart 0.
    local bkargs=()
    realign_on "$(hh_of "$hid")" && [ -f "$brk" ] && bkargs=(--bracket "$brk")
    local hidargs=(); [ "$MULTI" = 1 ] && hidargs=(--hartid "$hid")
    case "$REF_MODE" in
      spike)
        (
            source "$SPIKE_ENV"
            spike --isa="$SPIKE_ISA" --priv="$SPIKE_PRIV" --pmpregions="$SPIKE_PMPREGIONS" -m"$SPIKE_MEM" \
                  --disable-dtb --pc="$entry" --log-commits \
                  --instructions="$bound" --log="$clog" "$elf"
        ) > "$olog" 2>&1 ;;
      vesta_ref)
        (
            source "$SPIKE_ENV"
            if [ "$boot" = 1 ]; then
                # No --elf: the image arrives through the injected SPI stream.
                "$VESTA_REF" cosim --rom "$BOOT_ROM" --rom-base 0x0 \
                      --rom-format rcf --pc 0x0 \
                      --mem "$BOOT_MEM" --mmio "$MMIO_WIN" \
                      --isa "$SPIKE_ISA" --priv "$SPIKE_PRIV" --pmpregions "$SPIKE_PMPREGIONS" "${hidargs[@]}" \
                      --instructions "$bound" --inject "$inj" "${bkargs[@]}" --log "$clog"
            else
                "$VESTA_REF" cosim --elf "$elf" --pc "$entry" \
                      --mem "$SPIKE_MEM" --mmio "$MMIO_WIN" \
                      --isa "$SPIKE_ISA" --priv "$SPIKE_PRIV" --pmpregions "$SPIKE_PMPREGIONS" "${hidargs[@]}" \
                      --instructions "$bound" --inject "$inj" "${bkargs[@]}" --log "$clog"
            fi
        ) > "$olog" 2>&1 ;;
      *)
        echo "unknown REF_MODE=$REF_MODE" > "$olog"; return 90 ;;
    esac
}

# ---------------------------------------------------------------------------
# scrape_ref_census <reference stdout+stderr log>
#   Reads the A13/A14 censuses off vesta_ref's OWN summary line:
#     vesta_ref: cosim hartid=1 retires=… brackets=a/b brkstores=c gprs=d/e \
#                plants=f/g scfails=h/i …
#   Each census appears only when the realignment script actually carried that
#   record type, so a V3 (B/S-only) run yields "-" and its detail column is
#   unchanged. Sets ref_plants / ref_scfails / plant_un by dynamic scope (the
#   emit_result idiom), so it must NOT `local`-declare them.
#
#   plant_un > 0 is THE failure mode of the whole V4 design (A13 + v4_design.md
#   §3.5): a plant that never fired means the reference read STALE RAM at that
#   point, so every downstream compared record is asserting against a value the
#   RTL never produced. vesta_ref itself keeps exit 0 for it (it is a warning
#   there), which is precisely why the runner has to make it visible: it goes in
#   the detail column, in results.tsv, and in its own banner section.
# ---------------------------------------------------------------------------
scrape_ref_census() {
    local log="$1" a b
    ref_plants="-"; ref_scfails="-"; plant_un=0
    [ -s "$log" ] || return 0
    a="$(sed -n 's/.* plants=\([0-9]*\/[0-9]*\).*/\1/p' "$log" | tail -1)"
    [ -n "$a" ] && ref_plants="$a"
    b="$(sed -n 's/.* scfails=\([0-9]*\/[0-9]*\).*/\1/p' "$log" | tail -1)"
    [ -n "$b" ] && ref_scfails="$b"
    case "$ref_plants" in
        */*) a="${ref_plants%%/*}"; b="${ref_plants##*/}"
             [ "$b" -gt "$a" ] 2>/dev/null && plant_un=$(( b - a )) ;;
    esac
    # Belt and braces: vesta_ref also prints an explicit WARNING for an
    # unconsumed P/G/F tail. If the arithmetic above missed it (a future census
    # rename, say), the warning still trips the flag rather than passing quietly.
    if [ "$plant_un" = 0 ] && grep -q 'realignment tail UNCONSUMED' "$log"; then
        plant_un=1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# identity_gate -- THE STANDING GATE (once per sweep). `tail -n +6` drops stock
# spike's five reset-vector prologue lines (0x1000-0x1010); the harness starts
# at the entry pc with no prologue at all.
# ---------------------------------------------------------------------------
identity_gate() {
    [ "$REF_MODE" = vesta_ref ] || { echo "  identity gate : skipped (REF_MODE=$REF_MODE)"; return 0; }
    [ "$IDENTITY_GATE" = 1 ]    || { echo "  identity gate : DISABLED by IDENTITY_GATE=0"; return 0; }
    [ -x "$VESTA_REF" ]   || { echo "  identity gate : FAIL - no $VESTA_REF (run tools/cosim/build_vesta_ref.sh)"; return 1; }
    [ -f "$IDENTITY_ELF" ]|| { echo "  identity gate : FAIL - no $IDENTITY_ELF"; return 1; }
    local g="$LOG_DIR/identity"; mkdir -p "$g"
    local ient; ient="$("$READELF" -h "$IDENTITY_ELF" | awk '/Entry point address:/ {print $NF}')"
    (
        source "$SPIKE_ENV"
        spike --isa="$SPIKE_ISA" --priv="$SPIKE_PRIV" --pmpregions="$SPIKE_PMPREGIONS" -m"$SPIKE_MEM" \
              --log-commits --instructions=$(( IDENTITY_N + 5 )) \
              --log="$g/stock.log" "$IDENTITY_ELF"
        "$VESTA_REF" identity --elf "$IDENTITY_ELF" --pc "$ient" \
              --mem "$SPIKE_MEM" --isa "$SPIKE_ISA" --priv "$SPIKE_PRIV" \
              --pmpregions "$SPIKE_PMPREGIONS" \
              --instructions "$IDENTITY_N" --quiet --log "$g/ref.log"
    ) > "$g/gate.out" 2>&1
    tail -n +6 "$g/stock.log" | head -"$IDENTITY_N" > "$g/stock.cut"
    head -"$IDENTITY_N" "$g/ref.log" > "$g/ref.cut"
    local ls_ lr_; ls_=$(wc -l < "$g/stock.cut"); lr_=$(wc -l < "$g/ref.cut")
    if [ "$ls_" -ne "$IDENTITY_N" ] || [ "$lr_" -ne "$IDENTITY_N" ]; then
        echo "  identity gate : FAIL - short stream (stock=$ls_ ref=$lr_ want=$IDENTITY_N)"
        return 1
    fi
    local ms_ mr_
    ms_=$(md5sum < "$g/stock.cut" | cut -d' ' -f1)
    mr_=$(md5sum < "$g/ref.cut"   | cut -d' ' -f1)
    if [ "$ms_" != "$mr_" ]; then
        echo "  identity gate : *** FAIL *** vesta_ref no longer matches stock spike"
        echo "                  stock md5=$ms_  vesta_ref md5=$mr_"
        echo "                  libriscv-interface drift or a harness regression."
        return 1
    fi
    echo "  identity gate : PASS ($IDENTITY_N lines, md5 $ms_)"
    return 0
}

run_one() {
    local rcf_base="$1" wn="$2"
    local wl="$COSIM/w$wn"
    # PER-WORKER snapshot name. Not cosmetic: the HUNG path does
    # `pkill -9 -f work.<snap>`, and one shared name would make a hung test in
    # one worker kill every other worker's healthy sim.
    local snap="cs_run_w$wn"
    local name="${rcf_base%.rcf}"
    local test; test="$(strip_pad "$name")"
    local suite; suite="$(suite_of "$name")"
    local rcfpath="../$COSIM_RCF_LINK/$rcf_base"
    local elab_log="$LOG_DIR/$test.elab.log"
    local sim_log="$LOG_DIR/$test.sim.log"
    local trace_base="cosim_work/traces/$test"     # relative to CWD ($HERE)
    # PER-HART, assigned by compare_hart (dynamic scope, the idiom emit_result
    # already relies on): HH trace spk_log spk_out cmp_log inj brk part.
    local HH="00" part="-" trace="" spk_log="" spk_out="" cmp_log="" inj="" brk=""
    local status="" detail="-" a0="-" entry="-" nR=0 ncmp=0 nspk=0 ncmpr=0
    local t0 t1 el_ms=0 sim_ms=0 spk_ms=0 cmp_ms=0
    local elf="$ISA_DIR/build/$suite/$test"
    # §5(c): the testbench's own tile verdict, read once per test from the sim
    # log. tile_fail_any latches riscv_tb's "M12: a tile hart FAILED"; the
    # per-hart HART<h> lines are re-grepped inside compare_hart.
    local tile_fail_any=0

    # -- 0. TEST_FILE is a FIXED 29-char generic (CLAUDE.md) -------------------
    if [ ${#rcfpath} -ne 29 ]; then
        status="INFRA-FAIL(testfile-len${#rcfpath})"
        detail="TEST_FILE must be exactly 29 chars"
        emit_result_all; return
    fi
    [ -f "$RCF_DIR/$rcf_base" ] || {
        status="INFRA-FAIL(no-rcf)"; emit_result_all; return; }

    # -- 1. ELF ----------------------------------------------------------------
    local bstat; bstat="$(ensure_elf "$suite" "$test" "$CHECK_IMAGE")"
    case "$bstat" in
        PRESENT|BUILT) detail="elf=$bstat" ;;
        *) status="INFRA-FAIL(elf-$bstat)"; detail="make build/$suite/$test"
           emit_result_all; return ;;
    esac
    entry="$("$READELF" -h "$elf" | awk '/Entry point address:/ {print $NF}')"
    case "$entry" in
        0x*) ;;
        *) status="INFRA-FAIL(no-entry)"; detail="readelf gave '$entry'"
           emit_result_all; return ;;
    esac
    # The alignment PC for the comparison -- PER HART, so it is computed in
    # compare_hart (§3: the tiles are always pc-0-aligned). The ELF entry is
    # still derived above because the RTL side and check_image.py both need it.
    local cmp_entry="$entry"

    # -- 1b. image provenance: the RTL's image and Spike's ELF must be one cut -
    if [ "$CHECK_IMAGE" = 1 ]; then
        local ci
        if [ ! -f "$ISA_DIR/build/$suite/$test.rcf" ]; then
            status="INFRA-FAIL(no-raw-rcf)"
            detail="make build/$suite/$test.rcf produced nothing"
            emit_result_all; return
        fi
        ci="$("$PY36" "$COSIM/check_image.py" "$RCF_DIR/$rcf_base" \
                "$ISA_DIR/build/$suite/$test.rcf" 2>&1)"
        if [ $? -ne 0 ]; then
            printf '%s\n' "$ci" > "$LOG_DIR/$test.image.log"
            status="INFRA-FAIL(image-mismatch)"
            detail="$(printf '%s' "$ci" | head -1)"
            emit_result_all; return
        fi
        rm -f "$LOG_DIR/$test.image.log"    # never leave a stale mismatch log
    fi

    # -- 2. elaborate the TRACED design ---------------------------------------
    # V1 §5: the boolean generic MUST be the quoted form =>"true". Every other
    # spelling was measured and rejected — do not rediscover them.
    # ONE elaboration and ONE simulation serve every selected hart: the tracers
    # are independent instances writing <trace_base>_h<HH>.trace off the same
    # base, and a 4-traced sim was measured at 1.06-1.11x the untraced wall
    # clock with hart 0's stream byte-identical to the 1-traced run.
    local gen=(-generic "tb_cosim.uut:TEST_FILE=>\"$rcfpath\"")
    local h
    for h in $COSIM_HARTS; do
        gen+=(-generic "tb_cosim.uut.dut.hart${h}.core:TRACE_ENABLE=>\"true\"")
        gen+=(-generic "tb_cosim.uut.dut.hart${h}.core:TRACE_FILE=>\"$trace_base\"")
    done
    rm -f "$TRACE_DIR/${test}"_h??.trace "$sim_log"
    t0=$(date +%s%N)
    xmelab -cdslib "$wl/cds.lib" -ACCESS +r -SNAPSHOT "work.$snap" \
        "${gen[@]}" \
        "work.tb_cosim:behavioral" > "$elab_log" 2>&1
    local erc=$?
    t1=$(date +%s%N); el_ms=$(( (t1-t0)/1000000 ))
    if [ $erc -ne 0 ]; then
        status="INFRA-FAIL(elab-rc$erc)"; detail="see $elab_log"
        emit_result_all; return
    fi

    # -- 3. simulate (1-minute rule: a traced run is ~5 s; kill at TEST_TIMEOUT)
    t0=$(date +%s%N)
    timeout -k 5 "$TEST_TIMEOUT" \
        xmsim -cdslib "$wl/cds.lib" "work.$snap" -input batch_run.tcl \
              -licqueue -LOGFILE "$sim_log" > /dev/null 2>&1
    local src=$?
    t1=$(date +%s%N); sim_ms=$(( (t1-t0)/1000000 ))
    if [ $src -eq 124 ] || [ $src -eq 137 ]; then
        pkill -9 -f "work.$snap" 2>/dev/null
        status="HUNG"; detail="killed after ${TEST_TIMEOUT}s (rc=$src)"
        emit_result_all; return
    fi

    # The definitive stale-snapshot guard: the sim log must NAME this test.
    if ! grep -q "Starting test: $rcfpath" "$sim_log" 2>/dev/null; then
        status="INFRA-FAIL(wrong-test)"
        detail="sim log does not say 'Starting test: $rcfpath'"
        emit_result_all; return
    fi
    if   grep -q "TEST PASSED"    "$sim_log"; then a0=PASSED
    elif grep -q "TEST FAILED"    "$sim_log"; then a0=FAILED
    elif grep -q "TEST TIMED OUT" "$sim_log"; then a0=TIMEOUT
    else a0=NONE; fi
    # §5(c): riscv_tb latches a tile FAIL and reports it as a `failure`-severity
    # line. It is a REAL verdict about the chip, and it must invalidate EVERY
    # hart's cell -- including hart 0's, whose a0 can be 0xCAFEBABE while a tile
    # DEADBEEFed alongside it. (The companion "M12 NOTE: tile hart(s)
    # silent/parked" line is the EXPECTED single-hart shape and is not a fail.)
    grep -q "M12: a tile hart FAILED" "$sim_log" 2>/dev/null && tile_fail_any=1

    # -- 3b. THE TWO FREE AUDITS (per test, from hart 0's trace) ---------------
    # Advisory only: neither may abort or downgrade anything.
    mkdir -p "$LAUNCH_DIR" 2>/dev/null
    launch_margin_audit "$TRACE_DIR/${test}_h00.trace" "$LAUNCH_DIR/$test"

    # -- 4..6. PER (test,hart): trace -> inject -> reference -> comparator -----
    for h in $COSIM_HARTS; do
        compare_hart "$h"
    done
}

# ---------------------------------------------------------------------------
# compare_hart <hart-decimal> -- everything from "the trace and its provenance
# header" through the comparator verdict, for ONE hart of the test run_one just
# simulated. Reads AND WRITES run_one's locals by dynamic scope, which is the
# idiom emit_result already depends on; it must therefore NOT `local`-declare
# any of: HH part trace spk_log spk_out cmp_log inj brk cmp_entry status detail
# nR ncmp nspk ncmpr spk_ms cmp_ms.
#
# WHY THE MODES DIFFER PER HART (this looks like an inconsistency and is not):
# hart 0 boots the SPI flash image and jumps to the ELF entry, so its stream has
# a retire AT the entry PC and COSIM_BOOT can choose between aligning there (the
# V3 shortcut) or at pc 0 (boot-inclusive). A TILE never does: harts 1-3 reset
# to pc 0, run the SHARED BOOT ROM, park in WFI, and only ever leave the ROM if
# the test's own loader launches them. There is NO retire at the ELF entry in a
# tile's stream -- ever -- so an entry-aligned comparison of a tile is not a
# weaker comparison, it is an IMPOSSIBLE one (INFRA-FAIL(no-entry-retire) on
# every cell). Hence: tiles are unconditionally pc-0-aligned, unconditionally
# invoked in the --rom/--mem boot form, unconditionally given mk_inject's
# boot-mode --allow-x pair, and unconditionally --stop-before-sleep (their
# stream runs into EXTINGUISH = 0x0000100b, a custom opcode no reference can
# execute). COSIM_BOOT keeps governing hart 0 and hart 0 only.
# ---------------------------------------------------------------------------
compare_hart() {
    local hd="$1"
    HH="$(hh_of "$hd")"
    local boot="$COSIM_BOOT"
    [ "$HH" != "00" ] && boot=1
    cmp_entry="$entry"
    [ "$boot" = 1 ] && cmp_entry="$BOOT_ENTRY"
    trace="$TRACE_DIR/${test}_h${HH}.trace"
    spk_log="$SPIKE_DIR/$test.h${HH}.spike.log"
    spk_out="$LOG_DIR/$test.h${HH}.spike.log"
    cmp_log="$LOG_DIR/$test.h${HH}.cmp.log"
    inj="$INJECT_DIR/$test.h${HH}.inject"
    brk="$INJECT_DIR/$test.h${HH}.bracket"
    nR=0; ncmp=0; nspk=0; ncmpr=0; spk_ms=0; cmp_ms=0; status=""; detail="-"
    # V4/C2 reference censuses (A13/A14), scraped from the reference's own
    # summary line. "-" = this run carried no P/F records at all.
    ref_plants="-"; ref_scfails="-"; plant_un=0
    # Participation audit FIRST, so it is on the row whatever the verdict is:
    # a PARKED-ONLY hart is never coverage, even when its 12 ROM retires match.
    part="$(participation_of "$trace" "$entry")"

    # -- 4. the trace, and its provenance header (V1 §5) ----------------------
    if [ ! -s "$trace" ]; then
        status="INFRA-FAIL(no-trace)"
        detail="no $trace — TRACE_ENABLE override did not take for hart $hd (OFF snapshot ran? typo'd instance path?)"
        emit_result; return
    fi
    # THE ONLY TRIPWIRE for a typo'd -generic instance path: xmelab does not
    # error on an unknown override target, it silently ignores it. Both halves
    # are checked — TRACE_ENABLE=true proves the generic landed, hart=<HH>
    # proves it landed on the hart we think it did.
    if ! head -1 "$trace" | grep -q '^# vesta_tracer TRACE_ENABLE=true'; then
        status="INFRA-FAIL(no-trace-header)"
        detail="missing provenance header = stale/OFF snapshot"
        emit_result; return
    fi
    if ! head -1 "$trace" | grep -q "hart=${HH}\$"; then
        status="INFRA-FAIL(trace-hart-mismatch)"
        detail="$(head -1 "$trace") — header does not say hart=${HH}"
        emit_result; return
    fi
    nR=$(awk '$1=="R"{n++} END{print n+0}' "$trace")
    ncmp=$(awk -v ep="${cmp_entry#0x}" '
        BEGIN{ while (length(ep)<8) ep="0" ep }
        $1=="R"{ t++; if (!f && $4==ep) { f=1; s=t } }
        END{ if (f) print t-s+1; else print -1 }' "$trace")
    if [ "$ncmp" -lt 1 ]; then
        status="INFRA-FAIL(no-entry-retire)"
        detail="no R record at pc=$cmp_entry in $nR retires"
        emit_result; return
    fi

    # -- 4a. the V4 flags are PREREQUISITES, not niceties ----------------------
    # A missing flag must never degrade silently: without --stop-before-sleep a
    # tile's compared window runs into EXTINGUISH, and without --hartid the
    # reference reads mhartid=0 and takes hart 0's boot path on every hart. Both
    # produce a VACUOUS verdict on a hart that was never really compared, so
    # refuse the cell and name the flag.
    if [ "$MULTI" = 1 ] && [ -f "$COMPARE_PY" ] && [ "$CAP_CMP_HART" != 1 ]; then
        status="INFRA-FAIL(compare-no-hart-flag)"
        detail="$COMPARE_PY has no '--hart HH' flag; refusing to compare hart $HH without it"
        emit_result; return
    fi
    # A tile MUST cross its park window by one of the two mechanisms. Required
    # only when it is the one actually selected in run_compare: with bracket_on a
    # tile is carried ACROSS the park by A11 and never truncated, so demanding
    # --stop-before-sleep there would fail cells over a flag the run does not use.
    if [ "$HH" != "00" ] && ! bracket_on "$HH" && [ -f "$COMPARE_PY" ] \
       && [ "$CAP_CMP_STOPSLEEP" != 1 ]; then
        status="INFRA-FAIL(compare-no-stop-before-sleep)"
        detail="$COMPARE_PY has no '--stop-before-sleep' flag; refusing to compare tile hart $HH without it (its stream runs into EXTINGUISH 0000100b)"
        emit_result; return
    fi
    if [ "$MULTI" = 1 ] && [ "$REF_MODE" = vesta_ref ] && [ "$CAP_REF_HARTID" != 1 ]; then
        status="INFRA-FAIL(ref-no-hartid-flag)"
        detail="$VESTA_REF has no '--hartid' flag; refusing to run the reference for hart $HH with mhartid=0"
        emit_result; return
    fi
    # -- 4a(ii). C2: the BRACKET + PLANT channel, on all three tools ------------
    # Same rule, same reason: refuse, never degrade. The two `--plant` cases are
    # the dangerous ones because their absence is SILENT — mk_inject exits 0 and
    # emits a well-formed list with no P records in it, so the reference reads
    # stale RAM for every shared load and the cell "passes" vacuously.
    # K2b: the config asked for comparator amendments and the comparator does
    # not have them. Refuse, never degrade -- the absence is not silent (the row
    # would DIVERGE on record shape) but the verdict would be wrong, and a
    # record-shape divergence on a knobs-on row is exactly the shape a real DUT
    # defect takes.
    if [ -n "$COMPARE_AMEND" ] && [ -f "$COMPARE_PY" ] && [ "$CAP_CMP_AMEND" != 1 ]; then
        status="INFRA-FAIL(compare-no-amend)"
        detail="this config derives COMPARE_AMEND='$COMPARE_AMEND' and $COMPARE_PY has no '--amend' flag; refusing to compare a knobs-on row with the amendments absent"
        emit_result; return
    fi
    if bracket_on "$HH" && [ -f "$COMPARE_PY" ] && [ "$CAP_CMP_BRACKET" != 1 ]; then
        status="INFRA-FAIL(compare-no-bracket-isr)"
        detail="$COMPARE_PY has no '--bracket-isr' flag; refusing to compare hart $HH without it (Amendment A11: its stream contains an un-modellable sleep window by construction)"
        emit_result; return
    fi
    if realign_on "$HH" && [ "$REF_MODE" = vesta_ref ] && [ "$CAP_MK_BRACKETOUT" != 1 ]; then
        status="INFRA-FAIL(inject-no-bracket-out-flag)"
        detail="$MK_INJECT has no '--bracket-out' flag; refusing to bracket hart $HH without the realignment script (it also carries the A12 G / A13 P / A14 F records)"
        emit_result; return
    fi
    if realign_on "$HH" && [ "$REF_MODE" = vesta_ref ] && [ "$CAP_REF_BRACKET" != 1 ]; then
        status="INFRA-FAIL(ref-no-bracket-flag)"
        detail="$VESTA_REF has no '--bracket' flag; refusing to realign the reference for hart $HH without it"
        emit_result; return
    fi
    if realign_on "$HH" && [ "$REF_MODE" = vesta_ref ] && [ "$PLANT_WIN" != off ] \
       && [ "$CAP_MK_PLANT" != 1 ]; then
        status="INFRA-FAIL(inject-no-plant-flag)"
        detail="$MK_INJECT has no '--plant' flag; refusing to compare hart $HH with NO PLANTS EMITTED (A13: every shared-window load would read stale reference RAM and match vacuously). Set PLANT_WIN=off to state that intent explicitly."
        emit_result; return
    fi
    if realign_on "$HH" && [ "$REF_MODE" = vesta_ref ] && [ "$PLANT_WIN" = auto ] \
       && [ "$CAP_MK_HDLROOT" != 1 ]; then
        status="INFRA-FAIL(inject-no-hdl-root-flag)"
        detail="PLANT_WIN=auto needs $MK_INJECT '--hdl-root' to derive the window from MemoryMap.vhd, and the flag is absent"
        emit_result; return
    fi

    # -- 5. Spike (frozen V0 recipe) ------------------------------------------
    # --instructions is bounded by the RTL's OWN compared-retire count plus
    # SPIKE_SLACK. Rationale: both sides spin forever in RVTEST_PASS, so there
    # is no natural end; an unbounded run writes GB of log, and a bound smaller
    # than the RTL stream would hand the comparator a truncated reference (a
    # SILENT failure mode — v0_report.md §10.3). Deriving it from the RTL count
    # guarantees Spike is never the short side of a legitimate run.
    # V4/C1 REFINEMENT (Fable, v4_design.md §8.4): a TILE gets ZERO slack.
    # A tile's stream ends at its sleep point, and one retire past it the
    # reference executes EXTINGUISH (0x0000100b, a custom opcode) -> illegal
    # instruction -> with mtvec=0 it vectors to 0 and RE-RUNS THE BOOT ROM
    # FOREVER. Measured: --instructions 11 gives `traps=0` and a log ending
    # exactly at the last park retire; --instructions 12 gives `traps=1` and a
    # 12th line back at pc 0. The comparison is bounded by the RTL's own count
    # so those extra records cannot change a verdict -- but ~2000 junk post-trap
    # retires per tile per test are noise in exactly the logs a divergence
    # triage reads. Hart 0 keeps ncmp+SPIKE_SLACK verbatim.
    #
    # V4/C2: `ncmp` is the RTL's retire count, which for a BRACKETED hart is the
    # WRONG bound — it includes every ISR retire the reference does not execute
    # (24,594 of them per tile in shlrsc, against 105 reference retires). The
    # right number is mk_inject's own `ref_retires=`, and it is read back from the
    # inject log below (`bound_ref`), replacing this value. Computed here anyway
    # so the non-bracketed paths are untouched and so a failure to parse
    # ref_retires degrades to the old behaviour with a named warning rather than
    # to an unbounded run.
    local bound
    if [ "$HH" = "00" ]; then
        bound=$(( ncmp + SPIKE_SLACK ))
    else
        bound="$ncmp"
    fi
    [ "$bound" -gt "$SPIKE_MAX" ] && bound="$SPIKE_MAX"

    # -- 4b. V3: the ordered MMIO replay list (amendment A6) -------------------
    # Entry-aligned (hart 0, COSIM_BOOT=0 only), so pre-entry boot MMIO is
    # skipped -- the reference starts at the entry pc and never performs those
    # accesses. An x-tainted or # NODATA record makes mk_inject REFUSE (exit 5):
    # the reference must never be handed a fabricated bit (rulings A2 / A6).
    # PER HART: the list is built from THAT hart's own trace, so hart 0's
    # peripheral stream and a tile's shared-ROM stream never contaminate each
    # other -- and a tile takes the boot-mode args for the reason in the
    # compare_hart header.
    if [ "$REF_MODE" = vesta_ref ]; then
        mkdir -p "$INJECT_DIR"
        local mkargs=()
        if [ "$boot" = 1 ]; then
            mkargs=(--allow-x "$BOOT_ALLOW_X_1" --allow-x "$BOOT_ALLOW_X_2")
        else
            mkargs=(--entry "$entry")
        fi
        # Per-test injection-side x allowlist (ruling A2). Present only for the
        # tests that need it, each carrying its own written rationale; absent =
        # strict refusal, which is the default posture.
        [ -f "$ALLOWX_DIR/$test.allowx" ] && \
            mkargs+=(--allow-x-file "$ALLOWX_DIR/$test.allowx")
        # V4: the realignment script, and with it the A13 PLANT window. Both are
        # forced on for a tile (bracket_on) and BRACKET_ISR-gated on hart 0, so
        # the default single-hart invocation is byte-identical to V3's.
        if realign_on "$HH"; then
            mkargs+=(--bracket-out "$brk")
            if [ "$PLANT_WIN" != off ]; then
                mkargs+=(--plant "$PLANT_WIN")
                [ "$PLANT_WIN" = auto ] && mkargs+=(--hdl-root "$HDL_ROOT")
            fi
        fi
        # BASH TRAP: inside `if ! cmd; then`, $? is the status of the NEGATED
        # test (always 0), not the command's -- it reported "inject-rc0" once,
        # destroying the refusal code 5. Capture it separately.
        local irc=0
        "$PY36" "$MK_INJECT" --rtl "$trace" "${mkargs[@]}" \
                 --mmio "$MMIO_WIN" -o "$inj" > "$LOG_DIR/$test.h${HH}.inject.log" 2>&1 || irc=$?
        if [ "$irc" -ne 0 ]; then
            if [ "$irc" = 5 ]; then
                status="INFRA-FAIL(inject-refused)"
                detail="$(head -1 "$LOG_DIR/$test.h${HH}.inject.log")"
            else
                status="INFRA-FAIL(inject-rc$irc)"; detail="see $LOG_DIR/$test.h${HH}.inject.log"
            fi
            emit_result; return
        fi
        # ---- V4/C2: THE REFERENCE'S OWN RETIRE BUDGET ------------------------
        # For a bracketed hart the reference executes `ref_retires` instructions,
        # NOT the RTL's `ncmp`: every bracketed ISR retire is skipped by
        # construction (a shlrsc tile is 105 vs 24,699 — a 235x overshoot). Too
        # LARGE a bound is not merely noisy here: with zero slack the reference
        # would run past the RTL's stream end and, on a tile, trip the
        # `traps=0` assertion for a reason that has nothing to do with the sleep
        # point it is meant to detect. mk_inject prints the number precisely so
        # the runner need not re-derive it (one producer, one definition).
        if realign_on "$HH"; then
            local rr
            rr="$(sed -n 's/.*mk_inject: ref_retires=\([0-9]*\) .*/\1/p' \
                     "$LOG_DIR/$test.h${HH}.inject.log" | tail -1)"
            if [ -n "$rr" ] && [ "$rr" -ge 1 ] 2>/dev/null; then
                if [ "$HH" = "00" ]; then bound=$(( rr + SPIKE_SLACK )); else bound="$rr"; fi
                [ "$bound" -gt "$SPIKE_MAX" ] && bound="$SPIKE_MAX"
            else
                # Named, never silent: the bound falls back to the RTL count, so
                # the run still completes, but the log says the budget was guessed.
                echo "WARNING $test h$HH: no 'ref_retires=' in the inject log;" \
                     "reference bound falls back to the RTL retire count ($bound)" \
                     >> "$LOG_DIR/$test.h${HH}.inject.log"
            fi
        fi
    fi

    t0=$(date +%s%N)
    ref_invoke "$bound" "$entry" "$elf" "$spk_log" "$spk_out" "$inj" "$brk" "$boot" "$hd"
    local prc=$?
    t1=$(date +%s%N); spk_ms=$(( (t1-t0)/1000000 ))
    scrape_ref_census "$spk_out"
    if [ $prc -eq 7 ]; then
        # vesta_ref exit 7 = INJECT-MISMATCH or INJECT-EXHAUSTED. This is a REAL
        # finding, not infrastructure noise: either the two sides disagree about
        # WHICH loads are MMIO, or the reference took a path the RTL never took.
        # Triage it, never dismiss it.
        status="DIVERGE(7-inject)"
        detail="$(grep -m1 -E 'INJECT-(MISMATCH|EXHAUSTED)' "$spk_out" | head -1)"
        [ -n "$detail" ] || detail="exit 7, see $spk_out"
        emit_result; return
    fi
    if [ $prc -ne 0 ]; then
        status="INFRA-FAIL(ref-rc$prc)"; detail="see $spk_out"
        emit_result; return
    fi
    # v0 §7: an unaligned -m region is NOT rejected, it is silently realigned.
    if grep -qi 'has been realigned' "$spk_out"; then
        status="INFRA-FAIL(spike-realign)"; detail="-m$SPIKE_MEM realigned"
        emit_result; return
    fi
    if [ ! -s "$spk_log" ]; then
        status="INFRA-FAIL(spike-empty-log)"
        detail="rc=0 but no commit log (REF_MODE=$REF_MODE)"
        emit_result; return
    fi
    # V4/C1 REFINEMENT (Fable, v4_design.md §8.4): a TILE reference must report
    # traps=0. The reference is NEVER interrupted by design (V3: the legacy
    # vectored path is bracketed OUT, not modelled), and no --interrupt schedule
    # is wired in this runner, so for a correctly-bounded tile `traps` is exactly
    # 0 -- verified both ways at the boundary (11 retires -> traps=0,
    # 12 -> traps=1, the EXTINGUISH illegal-instruction trap). It is therefore
    # the cheapest possible tripwire for a bound that overran the sleep point,
    # which would otherwise show up only as post-trap junk in the log. Hart 0 is
    # exempt: it is not asserted here because its boot window has never been
    # characterised for trap-freedom, and a false alarm on the standing gate is
    # worse than a missing check on a hart whose stream is already compared in
    # full.
    if [ "$REF_MODE" = vesta_ref ] && [ "$HH" != "00" ]; then
        local ntraps; ntraps="$(sed -n 's/.*cosim hartid=[0-9]* retires=[0-9]* traps=\([0-9]*\) .*/\1/p' "$spk_out" | tail -1)"
        if [ -n "$ntraps" ] && [ "$ntraps" != "0" ]; then
            status="INFRA-FAIL(tile-ref-trapped)"
            detail="reference reported traps=$ntraps on hart $HH (bound=$bound overran the sleep point; see $spk_out)"
            emit_result; return
        fi
    fi
    nspk=$(wc -l < "$spk_log")

    # -- 6. the comparator owns the verdict -----------------------------------
    t0=$(date +%s%N)
    local cres; cres="$(run_compare "$trace" "$spk_log" "$cmp_entry" "$cmp_log" "$HH")"
    status="${cres%% *}"; ncmpr="${cres##* }"
    detail="spike_bound=$bound"

    # README "The exit-2 question": in the bounded flow exit 3 (Spike short) is
    # EITHER a real illegal-instruction/unmapped-access divergence OR simply too
    # small an --instructions bound. Those are not the same finding, so retry
    # ONCE with a much larger bound before reporting. If it still comes back 3,
    # the bound is not the cause.
    if [ "$status" = "DIVERGE(3-spikeshort)" ] && [ "$bound" -lt "$SPIKE_MAX" ]; then
        local big=$(( ncmp * 4 + 100000 ))
        [ "$big" -gt "$SPIKE_MAX" ] && big="$SPIKE_MAX"
        ref_invoke "$big" "$entry" "$elf" "$spk_log" "$spk_out" "$inj" "$brk" "$boot" "$hd"
        if [ $? -eq 0 ] && [ -s "$spk_log" ]; then
            scrape_ref_census "$spk_out"
            nspk=$(wc -l < "$spk_log")
            cres="$(run_compare "$trace" "$spk_log" "$cmp_entry" "$cmp_log" "$HH")"
            status="${cres%% *}"; ncmpr="${cres##* }"
            detail="spike_bound=$bound->$big(retried after exit 3)"
        fi
        # Fable's ruling: exit 3 that SURVIVES the bound escalation is not a
        # bound artifact, so it is reported as INFRA-FAIL and not as a clean
        # divergence. Keep the name explicit — per the README exit 3 is also the
        # normal shape of a real illegal-instruction / unmapped-access
        # divergence, so this class must still be triaged, not dismissed.
        [ "$status" = "DIVERGE(3-spikeshort)" ] && \
            status="INFRA-FAIL(spike-short-after-retry)"
    fi
    t1=$(date +%s%N); cmp_ms=$(( (t1-t0)/1000000 ))

    # ── THE PREFIX-COMPARE SOUNDNESS CONDITION (Fable's ruling, binding) ──────
    # V4 ruling, in the same spirit: a (test,hart) CELL is PASS if and ONLY IF
    #   (a) ITS comparator exited 0  (already the value of $status here)
    #   (b) hart 0's a0 watch reported TEST PASSED — the sim-level gate, which
    #       gates EVERY hart's cell, because there is exactly one simulation and
    #       one pass contract in it; and
    #   (c) the testbench reported NO tile FAIL: neither the chip-wide
    #       "M12: a tile hart FAILED" line nor, for HH in 01/02/03, that hart's
    #       own "HART<h> (tile) pass=… fail=true".
    # The comparison is bounded at N = the RTL's own compared-record count, so a
    # sim that stopped early would trivially "match" on its truncated prefix; the
    # comparator therefore runs IN ADDITION to the sim verdicts, never instead of
    # them. Every violation gets an explicit status NAMING the cause — a bare
    # PASS is never reachable from a broken sim.
    # (HUNG and every INFRA-FAIL already returned before this point.)
    if [ "$status" = "PASS" ] && [ "$a0" != "PASSED" ]; then
        status="INFRA-FAIL(prefix-unsound-a0=$a0)"
        detail="$detail; comparator matched the RTL prefix but the a0 watch did not report TEST PASSED (a truncated stream matches vacuously)"
    elif [ "$status" = "PASS" ] && [ "$tile_fail_any" = 1 ]; then
        status="INFRA-FAIL(tile-fail-M12)"
        detail="$detail; comparator matched but the sim log carries 'M12: a tile hart FAILED' — a tile DEADBEEFed alongside hart 0, so no cell of this test is sound"
    elif [ "$status" = "PASS" ] && [ "$HH" != "00" ] && \
         grep -q "HART${hd} (tile) pass=.* fail=true" "$sim_log" 2>/dev/null; then
        status="INFRA-FAIL(tile-fail-h${HH})"
        detail="$detail; comparator matched but riscv_tb reports HART${hd} (tile) fail=true"
    fi

    # -- 7. C2: the A13/A14 censuses go on the ROW, not just in a log ----------
    # `plants=<applied>/<total>` and `scfails=<applied>/<total>` are what a
    # triage needs to know whether a shared load was served at all, and the two
    # are counted-only by design (A14: ~29,000 F records for ONE hart of
    # `shcount`, so a per-application line would bury the log).
    if [ "$ref_plants" != "-" ] || [ "$ref_scfails" != "-" ]; then
        detail="$detail; plants=$ref_plants scfails=$ref_scfails"
    fi
    # An unconsumed PLANT tail is the single failure mode of the V4 design
    # (A13 / v4_design.md §3.5) — the reference read STALE RAM somewhere, so
    # anything it then compared equal proves nothing. vesta_ref keeps exit 0 for
    # it, so this is the only place it can become impossible to miss: it is
    # stamped on the row AND it downgrades a PASS, because a PASS whose reference
    # read stale RAM is exactly the vacuous PASS this program refuses.
    if [ "$plant_un" -gt 0 ]; then
        detail="$detail; PLANT-TAIL-UNCONSUMED=$plant_un (reference READ STALE RAM at/after the first unapplied index — see $spk_out)"
        [ "$status" = "PASS" ] && status="INFRA-FAIL(plant-tail-unconsumed)"
    fi
    emit_result
}

# Writes one machine-parsable row + one streamed human line for ONE (test,hart)
# CELL. Reads run_one's/compare_hart's locals by dynamic scope. On PASS that
# hart's bulky streams are dropped (unless KEEP=1); on ANY other verdict
# EVERYTHING is kept for triage (kickoff D5).
#
# RESULTS FORMAT (V4): columns 1-14 are V3's, unchanged in order AND meaning, so
# every existing consumer that reads by index keeps working. `hart` and
# `participation` are APPENDED as columns 15-16, and C2 appends `plants` and
# `scfails` as 17-18 — again APPENDED, so no existing column moves or changes
# meaning. Note el_ms/sim_ms are PER TEST (one elaborate, one simulate) and are
# therefore repeated on each of a test's cells — do not sum them across harts.
#
# The collect loop reads the appended fields BY OFFSET FROM THE END
# ($(NF-2)=participation, $(NF-1)=plants, $NF=scfails) for the same reason it
# always did: a `detail` that happened to contain a tab shifts every index from
# the front but nothing from the back.
emit_result() {
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$status" "$test" "$rcf_base" "$entry" "$a0" "$nR" "$ncmp" "$nspk" \
        "$ncmpr" "$el_ms" "$sim_ms" "$spk_ms" "$cmp_ms" "$detail" \
        "$HH" "$part" "${ref_plants:--}" "${ref_scfails:--}" \
        > "$STATUS_DIR/${test}#h${HH}"
    local n; n=$(ls "$STATUS_DIR" | wc -l)
    if [ "$MULTI" = 1 ]; then
        printf '  [%3d/%3d]  %-22s  %-28s  h%s %-13s a0=%-7s  cmp=%-6s spk=%-6s  %5sms\n' \
            "$n" "$TOTAL" "$status" "$test" "$HH" "$part" "$a0" "$ncmpr" "$nspk" \
            "$(( el_ms + sim_ms + spk_ms + cmp_ms ))"
    else
        printf '  [%3d/%3d]  %-22s  %-28s  a0=%-7s  cmp=%-6s spk=%-6s  %5sms\n' \
            "$n" "$TOTAL" "$status" "$test" "$a0" "$ncmpr" "$nspk" \
            "$(( el_ms + sim_ms + spk_ms + cmp_ms ))"
    fi
    case "$status" in
        PASS)
            if [ "$KEEP" != 1 ]; then
                rm -f "$TRACE_DIR/${test}_h${HH}.trace" \
                      "$SPIKE_DIR/$test.h${HH}.spike.log" \
                      "$INJECT_DIR/$test.h${HH}.inject" \
                      "$INJECT_DIR/$test.h${HH}.bracket" \
                      "$LOG_DIR/$test.h${HH}.inject.log"
            fi ;;
    esac
}

# A failure BEFORE the per-hart split (bad TEST_FILE, no rcf, no ELF, image
# mismatch, elab, HUNG, wrong test in the sim log) invalidates every selected
# hart of that test, so it emits ONE ROW PER CELL with the same status. Without
# this the [N/TOTAL] counter and the collect loop would both go looking for
# cells that no worker ever wrote. With COSIM_HARTS="0" it emits exactly the one
# row V3 emitted.
emit_result_all() {
    local __h
    for __h in $COSIM_HARTS; do
        HH="$(hh_of "$__h")"
        part="-"                 # nothing to audit: the sim did not get this far
        ref_plants="-"; ref_scfails="-"   # the reference never ran either
        emit_result
    done
}

# =============================================================================
# main
# =============================================================================
mkdir -p "$COSIM/runs" || die "cannot create $COSIM/runs"
migrate_flat_layout
mkdir -p "$TRACE_DIR" "$SPIKE_DIR" "$LOG_DIR" "$INJECT_DIR" || die "cannot create $RUN_DIR"
rm -rf "$STATUS_DIR"; mkdir -p "$STATUS_DIR"
rm -rf "$LAUNCH_DIR"; mkdir -p "$LAUNCH_DIR"
link_latest

# ---------------------------------------------------------------------------
# LEGACY-ARTIFACT QUARANTINE (V4/C2). Every per-hart artifact this runner writes
# carries an `.hNN.` infix -- hart 0 included, deliberately, because one naming
# rule for four harts is far less error-prone than three suffixed names plus a
# bare one. V3 wrote the BARE names (`<test>.cmp.log`, `<test>.spike.log`,
# `<test>.inject.log`), and those files are never touched again by this runner, so
# they sit in cosim_work/logs/ looking exactly like current evidence.
#
# WHY THIS GUARD EXISTS, from the incident that motivated it: during C2 I read
# `rv32ua-p-extzihpm.cmp.log` (a 04:17 leftover from the pre-V4 entry-aligned
# baseline) while triaging a run whose real output was
# `rv32ua-p-extzihpm.h00.cmp.log`, and briefly concluded that the standing gate's
# divergence index had MOVED from #38140 to #46 -- i.e. that a regression had
# landed. It had not: the two files are different alignments of different runs.
# A stale artifact that reads as a regression is worse than a missing one, and
# 218 of them were on disk.
#
# QUARANTINE, NOT DELETE: they are someone's evidence until a human says
# otherwise (D5 keeps divergence artifacts), so they are MOVED and COUNTED, never
# removed. LEGACY_QUARANTINE=0 turns the sweep off; the census still prints.
LEGACY_QUARANTINE=${LEGACY_QUARANTINE:-1}
quarantine_legacy_logs() {
    local q="$COSIM/legacy_v3_logs.quarantine" f n=0
    local stale=()
    for f in "$LOG_DIR"/*.cmp.log "$LOG_DIR"/*.spike.log "$LOG_DIR"/*.inject.log; do
        [ -f "$f" ] || continue
        case "$(basename "$f")" in *.h[0-9][0-9].*) continue ;; esac
        stale+=("$f")
    done
    [ ${#stale[@]} -eq 0 ] && return 0
    if [ "$LEGACY_QUARANTINE" != 1 ]; then
        echo "  legacy logs   : ${#stale[@]} V3-named artifact(s) WITHOUT an .hNN infix are"
        echo "                  present in $LOG_DIR and were NOT quarantined"
        echo "                  (LEGACY_QUARANTINE=0). They are NOT output of this run;"
        echo "                  a triage that reads one will draw a conclusion about the"
        echo "                  wrong run. Example: $(basename "${stale[0]}")"
        return 0
    fi
    mkdir -p "$q" 2>/dev/null || return 0
    for f in "${stale[@]}"; do mv "$f" "$q/" 2>/dev/null && n=$((n+1)); done
    echo "  legacy logs   : quarantined $n V3-named artifact(s) (no .hNN infix) -> $q"
    echo "                  They are pre-V4 leftovers, not output of this run. Kept, not"
    echo "                  deleted -- see the guard's comment for the misread they caused."
}
quarantine_legacy_logs

emit_check_image

# Multi-hart needs the boot-ROM reference form (pc 0) AND --hartid; stock spike
# can do neither (riscv/sim.cc:72 nails a Debug Module over [0x0,0x1000)). Refuse
# up front rather than manufacturing 3 tiles' worth of INFRA-FAIL.
if [ "$MULTI" = 1 ] && [ "$REF_MODE" != vesta_ref ]; then
    die "COSIM_HARTS='$COSIM_HARTS' selects a tile hart, which requires
       REF_MODE=vesta_ref: the tiles are compared boot-inclusive from pc 0 and
       need --hartid, and stock spike can do neither."
fi

# the ONE shared wrapper: TEST_FILE / TRACE_ENABLE / TRACE_FILE are all
# xmelab -generic hierarchical overrides, so the cell list compiles ONCE.
cat > "$COSIM/tb_cosim.vhd" <<'VHDL'
-- V2 lockstep co-sim wrapper (generated by xrun_cosim.sh — do not edit).
-- ONE top-level entity for the whole sweep; the per-test TEST_FILE and the
-- tracer's TRACE_ENABLE/TRACE_FILE all arrive as xmelab -generic hierarchical
-- overrides, so the cell list is compiled once and each test pays only
-- elaborate + simulate. The TEST_FILE default below is never used.
entity tb_cosim is end tb_cosim;
architecture behavioral of tb_cosim is begin
    uut: entity work.riscv_tb generic map (TEST_FILE => "../rcf/xxxrv32ui-p-simple.rcf");
end architecture;
VHDL

# ── resolve the test list ─────────────────────────────────────────────────────
TESTS=()
if [ $# -gt 0 ]; then
    MODE="single"
    for pat in "$@"; do
        r="$(resolve_rcf "$pat")" || die "pattern '$pat' -> $r
       (the glob is ../$COSIM_RCF_LINK/*PAT*.rcf — use FULL basenames, e.g. xxxxxxrv32ui-p-add)"
        TESTS+=("$r")
    done
else
    MODE="sweep"
    LIST="${TESTS_FILE:-$TESTS_LIST_DEFAULT}"
    [ -f "$LIST" ] || die "no test list at $LIST"
    while read -r line; do
        line="${line%%#*}"; line="$(echo "$line" | tr -d '[:space:]')"
        [ -z "$line" ] && continue
        TESTS+=("${line##*/}")
    done < "$LIST"
    [ ${#TESTS[@]} -gt 0 ] || die "$LIST yielded no tests"
fi
NTESTS=${#TESTS[@]}
# TOTAL counts CELLS, i.e. (test,hart) pairs — it is what [N/TOTAL] streams
# against and what the PASS-everything exit code compares to. With
# COSIM_HARTS="0" it is #tests, exactly as in V3. MAX_PARALLEL still throttles
# TESTS (one sim per test serves every hart), so it clamps against NTESTS.
TOTAL=$(( NTESTS * NHARTS_SEL ))
[ "$NTESTS" -lt "$MAX_PARALLEL" ] && MAX_PARALLEL="$NTESTS"

echo "=============================================================================="
echo " xrun_cosim.sh — VestaRV <-> Spike lockstep   ($MODE, $NTESTS test(s))"
echo "=============================================================================="
if [ "$REF_MODE" = vesta_ref ]; then
echo "  reference : vesta_ref (simif_t harness on pinned UNPATCHED libriscv)"
echo "              $VESTA_REF"
echo "              --isa=$SPIKE_ISA --priv=$SPIKE_PRIV --pmpregions=$SPIKE_PMPREGIONS"
echo "              --mem $SPIKE_MEM --mmio $MMIO_WIN"
echo "              --pc=<elf entry> --inject <per-test> --instructions=<rtl+$SPIKE_SLACK>"
else
echo "  reference : stock spike (V2 A/B control)"
echo "              --isa=$SPIKE_ISA --priv=$SPIKE_PRIV --pmpregions=$SPIKE_PMPREGIONS -m$SPIKE_MEM"
echo "              --disable-dtb --pc=<elf entry> --log-commits --instructions=<rtl+$SPIKE_SLACK>"
fi
echo "  amendments: ${COMPARE_AMEND:-(none — the default config gates them all off)}"
echo "  polarity  : RTL ON = ${RTL_ON_CMP:-(none)}   ($MEMMAP_VHD)"
echo "              IMG ON = ${IMG_ON_CMP:-(none)}   ($COSIM_RCF_LINK/.imgset = '$IMGSET_HAVE')"
echo "              ref ELFs built at RISCV_GCC_OPTS=$REF_GCC_OPTS"
echo "  images    : ../$COSIM_RCF_LINK   cell list: $CELL_LIST"
echo "  injector  : $MK_INJECT (ordered replay, amendment A6)"
echo "  comparator: $COMPARE_PY $( [ -f "$COMPARE_PY" ] && echo '(present)' || echo '(ABSENT -> COMPARE-PENDING)')"
echo "  workers   : MAX_PARALLEL=$MAX_PARALLEL   per-sim timeout ${TEST_TIMEOUT}s"
echo "  artifacts : $RUN_DIR"
echo "              run key RUN_KEY=$RUN_KEY  (config__harts__test-list; K2 item 5)"
echo "              cosim_work/{summary.txt,results.tsv,launch_margin.tsv,traces,"
echo "              spike,logs,inject} are SYMLINKS to the run that wrote them last"
probe_capabilities
if [ "$MULTI" = 1 ]; then
echo "  harts     : COSIM_HARTS='$COSIM_HARTS'  ->  $TOTAL cell(s) = $NTESTS test(s) x $NHARTS_SEL hart(s)"
echo "              one elaborate+simulate per test; trace/inject/reference/compare per (test,hart)"
echo "              harts != 0 are ALWAYS boot-inclusive (pc 0); they cross their park"
echo "              window by the A11 BRACKET, not by --stop-before-sleep (mutually exclusive)"
echo "              harts != 0 are ALWAYS bracketed (A11: the sleep window is in their"
echo "              stream by construction); hart 0 stays under BRACKET_ISR=$BRACKET_ISR"
echo "              flags: compare.py --hart $( [ "$CAP_CMP_HART" = 1 ] && echo ok || echo MISSING)" \
     "--stop-before-sleep $( [ "$CAP_CMP_STOPSLEEP" = 1 ] && echo ok || echo MISSING)" \
     " vesta_ref --hartid $( [ "$CAP_REF_HARTID" = 1 ] && echo ok || echo MISSING)"
fi
# Only when a SELECTED hart actually brackets — so the default single-hart
# invocation's banner shape is untouched.
if [ "$MULTI" = 1 ] || [ "$BRACKET_ISR" = 1 ]; then
echo "  brackets  : hart 0 BRACKET_ISR=$BRACKET_ISR; harts != 0 forced ON (A11)"
echo "              plant win: PLANT_WIN=$PLANT_WIN$( [ "$PLANT_WIN" = auto ] && echo "  (derived from $HDL_ROOT/MemoryMap.vhd)")"
echo "              flags: compare.py --amend $( [ "$CAP_CMP_AMEND" = 1 ] && echo ok || echo MISSING)" \
     "compare.py --bracket-isr $( [ "$CAP_CMP_BRACKET" = 1 ] && echo ok || echo MISSING)" \
     " mk_inject --bracket-out $( [ "$CAP_MK_BRACKETOUT" = 1 ] && echo ok || echo MISSING)" \
     "--plant $( [ "$CAP_MK_PLANT" = 1 ] && echo ok || echo MISSING)" \
     " vesta_ref --bracket $( [ "$CAP_REF_BRACKET" = 1 ] && echo ok || echo MISSING)"
fi
echo ""

# ── THE IDENTITY GATE (standing, per sweep) ──────────────────────────────────
# Fable/user ruling 2026-07-30: a libriscv-interface drift must fail LOUDLY.
# The whole D1 argument is that the harness adds no ISA semantics; this is what
# keeps that claim honest, so a failure aborts the sweep rather than warning.
mkdir -p "$LOG_DIR"
# K2/G7: the cache sync runs BEFORE the identity gate, not with the test
# staging, because the identity gate reads an ELF out of that same cache
# ($IDENTITY_ELF = build/rv32ui/rv32ui-p-add by default). Syncing afterwards
# would let the gate certify a reference binary against an ELF built at some
# other row's polarity -- the very confusion this stamp exists to end.
sync_elf_cache
if [ ! -f "$IDENTITY_ELF" ] && [ "$NO_BUILD" != 1 ]; then
    _ie_b="$(basename "$IDENTITY_ELF")"
    echo "  identity ELF absent after cache sync -> building it at this row's polarity"
    ensure_elf "$(suite_of "$_ie_b")" "$_ie_b" 0 >/dev/null
fi
if ! identity_gate; then
    echo ""
    echo "ABORTING: the reference model failed its identity gate. Nothing was run."
    echo "  Rebuild:  tools/cosim/build_vesta_ref.sh"
    echo "  Override (NOT for a real sweep):  IDENTITY_GATE=0  or  REF_MODE=spike"
    exit 1
fi
echo ""

# ── stage the ELFs SEQUENTIALLY (one make per test; parallel make in one tree
#    races on build/ intermediates) ────────────────────────────────────────────
if [ "$NO_BUILD" != 1 ]; then
    echo "=== [1/3] Staging ELFs (single-target make only) ==="
    nb=0; np=0; nf=0
    for rcf_base in "${TESTS[@]}"; do
        nm="${rcf_base%.rcf}"; t="$(strip_pad "$nm")"; s="$(suite_of "$nm")"
        st="$(ensure_elf "$s" "$t" "$CHECK_IMAGE")"
        case "$st" in
            PRESENT) np=$((np+1)) ;;
            BUILT)   nb=$((nb+1)); echo "    built  build/$s/$t" ;;
            *)       nf=$((nf+1)); echo "    FAILED build/$s/$t ($st)" ;;
        esac
    done
    echo "  present=$np built=$nb failed=$nf"
else
    echo "=== [1/3] NO_BUILD=1 — ELF staging skipped ==="
fi

# ── worker libraries ──────────────────────────────────────────────────────────
echo ""
if [ "$NO_COMPILE" = 1 ]; then
    echo "=== [2/3] NO_COMPILE=1 — reusing existing worker libraries ==="
    for i in $(seq 1 "$MAX_PARALLEL"); do setup_worker_lib "$i" || die "worker lib $i"; done
else
    echo "=== [2/3] Fresh compile into $MAX_PARALLEL worker library/-ies ==="
    for i in $(seq 1 "$MAX_PARALLEL"); do
        setup_worker_lib "$i" &
    done
    wait
    for i in $(seq 1 "$MAX_PARALLEL"); do
        [ -d "$COSIM/w$i/xcelium.d/work" ] || die "worker lib $i failed — see $LOG_DIR/compile_*_w$i.log"
        grep -qE '\*[EF],' "$LOG_DIR/compile_vhdl_w$i.log" 2>/dev/null \
            && die "compile errors in $LOG_DIR/compile_vhdl_w$i.log"
    done
    echo "  ok — $MAX_PARALLEL library/-ies compiled"
fi

# ── the sweep ─────────────────────────────────────────────────────────────────
echo ""
if [ "$MULTI" = 1 ]; then
echo "=== [3/3] Lockstep ($TOTAL cell(s) = $NTESTS test(s) x $NHARTS_SEL hart(s), $MAX_PARALLEL parallel) ==="
else
echo "=== [3/3] Lockstep ($TOTAL test(s), $MAX_PARALLEL parallel) ==="
fi
SWEEP_T0=$(date +%s)
# STATIC round-robin partition, one SEQUENTIAL worker per slot.
# This is deliberate, not laziness: each slot owns ONE library and ONE snapshot
# name (work.cs_run), so two tests must NEVER elaborate into the same slot
# concurrently — the second would overwrite the first's snapshot mid-flight,
# which is precisely the stale-snapshot trap. A "throttle on jobs -r | wc -l
# then hand out the next slot round-robin" loop does NOT guarantee the slot it
# hands out is the one that just freed, so it is wrong here. Tests are ~7 s
# each, so static partitioning costs nothing in balance.
worker_loop() {
    local wn="$1"; shift
    local t
    for t in "$@"; do run_one "$t" "$wn"; done
}
for i in $(seq 1 "$MAX_PARALLEL"); do
    slice=()
    idx=0
    for rcf_base in "${TESTS[@]}"; do
        if [ $(( idx % MAX_PARALLEL + 1 )) -eq "$i" ]; then slice+=("$rcf_base"); fi
        idx=$(( idx + 1 ))
    done
    [ ${#slice[@]} -eq 0 ] && continue
    worker_loop "$i" "${slice[@]}" &
done
wait
SWEEP_T1=$(date +%s)

# ── collect ───────────────────────────────────────────────────────────────────
{
  printf '# xrun_cosim.sh results — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  printf '# reference: REF_MODE=%s  isa=%s priv=%s pmpregions=%s mem=%s mmio=%s  instructions=<rtl+%s>\n' \
         "$REF_MODE" "$SPIKE_ISA" "$SPIKE_PRIV" "$SPIKE_PMPREGIONS" "$SPIKE_MEM" "$MMIO_WIN" "$SPIKE_SLACK"
  printf '# amendments: %s\n' "${COMPARE_AMEND:-(none)}"
  printf '# injector : %s (ordered MMIO replay, amendment A6; entry-aligned)\n' "$MK_INJECT"
  printf '# comparator: %s (two-pass: --count --quiet, then --max-records N)\n' "$COMPARE_PY"
  printf '# harts    : COSIM_HARTS=%s  -> ONE ROW PER (test,HART); %d test(s) x %d hart(s) = %d cell(s)\n' \
         "'$COSIM_HARTS'" "$NTESTS" "$NHARTS_SEL" "$TOTAL"
  echo '#             hart 00 follows COSIM_BOOT; harts 01-03 are ALWAYS boot-inclusive'
  echo '#             (pc 0, --rom bootrom) — a tile only ever executes shared ROM, so'
  echo '#             there is no retire at the ELF entry. They cross the park window by'
  echo '#             the A11 sleep BRACKET; --stop-before-sleep is the fallback for a'
  echo '#             tile whose bracket path is off, and the two are mutually exclusive'
  echo '#             (truncation would cut the stream at the park and hide the test body).'
  printf '# brackets : hart 00 under BRACKET_ISR=%s; harts != 00 FORCED ON (Amendment A11 —\n' "$BRACKET_ISR"
  echo '#             a launched tile parks on EXTINGUISH 0x0000100b and wakes through the'
  echo '#             legacy vectored trap, neither of which the reference can execute, so'
  echo '#             the sleep window is in its stream BY CONSTRUCTION, not by choice.'
  printf '# plants   : PLANT_WIN=%s (A13: shared-window loads served by POKING reference RAM,\n' "$PLANT_WIN"
  echo '#             not by an MMIO callback — a callback region would make lr.w/sc.w fault,'
  echo '#             and LR/SC on the shared window is the whole subject of shcount/shspin/'
  echo '#             shlrsc/shlock). P records ride the --bracket-out script.'
  echo '# LEGEND / THE PREFIX-COMPARE SOUNDNESS CONDITION (Fable ruling, binding):'
  echo '#   PASS       = the RTL sim reported TEST PASSED via the a0 watch (column a0)'
  echo '#                AND compare.py exited 0. BOTH are required: the compare is'
  echo '#                bounded at N = the RTL stream'"'"'s own compared-record count, so a'
  echo '#                sim that hung or died early would match vacuously on its prefix.'
  echo '#                V4 adds a THIRD requirement: no tile FAIL from the testbench'
  echo '#                (neither "M12: a tile hart FAILED" nor this hart'"'"'s own'
  echo '#                "HART<h> (tile) ... fail=true").'
  echo '#   DIVERGE(1) = a compared field differs / an RTL T (trap) record / the entry PC'
  echo '#                was never reached on one side.  Triage per kickoff D5.'
  echo '#   DIVERGE(4-xcorrupt) = Amendment-A5 x-tainted record in the compared window.'
  echo '#   HUNG       = the sim was killed at TEST_TIMEOUT (the 1-minute rule).'
  echo '#   INFRA-FAIL = anything that makes the verdict meaningless (no trace, no'
  echo '#                provenance header, wrong test in the sim log, image/ELF mismatch,'
  echo '#                elab/spike/compare failure, Spike still short after the bound'
  echo '#                escalation).  NEVER counted as PASS.  spike-short-after-retry may'
  echo '#                also be a REAL illegal-instruction divergence — triage it.'
  echo '#   INFRA-FAIL(tile-stream-short) = comparator exit 2 on a hart != 00. A tile'
  echo '#                trace ends wherever hart 0'"'"'s a0 watch stopped the SIM, i.e.'
  echo '#                mid-stream by construction, so exit 2 there is a limit of the'
  echo '#                observation — NOT DIVERGE(2-rtlshort), and never a PASS.'
  echo '#   INFRA-FAIL(tile-fail-M12 | tile-fail-hHH) = the testbench failed a tile hart.'
  echo '#   INFRA-FAIL(trace-hart-mismatch) = the trace header does not name this hart'
  echo '#                (a typo'"'"'d -generic instance path is otherwise SILENT).'
  echo '#   INFRA-FAIL(compare-no-hart-flag | compare-no-stop-before-sleep |'
  echo '#                compare-no-bracket-isr | inject-no-bracket-out-flag |'
  echo '#                inject-no-plant-flag | inject-no-hdl-root-flag |'
  echo '#                ref-no-hartid-flag | ref-no-bracket-flag) = a V4 prerequisite flag'
  echo '#                is absent from the comparator/injector/reference. Refused, never'
  echo '#                degraded: a silent fallback would report a vacuous PASS on a hart'
  echo '#                that was never compared. inject-no-plant-flag is the worst of them'
  echo '#                — with no --plant NO P records exist, mk_inject still exits 0, and'
  echo '#                every shared-window load would be compared against stale reference'
  echo '#                RAM. Say PLANT_WIN=off if that really is the intent.'
  echo '#   INFRA-FAIL(plant-tail-unconsumed) = the reference left A13 PLANT records NEVER'
  echo '#                APPLIED (see columns plants/scfails and the detail column). A plant'
  echo '#                that never fired means the reference READ STALE RAM at that point,'
  echo '#                which is THE failure mode of the V4 design (v4_design.md §3.5);'
  echo '#                vesta_ref keeps exit 0 for it, so it is downgraded here instead.'
  echo '# COLUMNS: 1-14 are V3'"'"'s, unchanged in order and meaning. 15 hart (2 hex digits)'
  echo '#          and 16 participation are APPENDED. PARTICIPATED = retired at pc >= the ELF'
  echo '#          entry, i.e. it ran TEST-IMAGE code. LAUNCHED-ONLY = took the loader trap'
  echo '#          but never reached the image (still in the bootrom ISR at sim end -- the'
  echo '#          T1 shape). PARKED-ONLY = every retire was boot ROM, never launched.'
  echo '#          NO-TRACE = no records. "-" = not audited. NEITHER LAUNCHED-ONLY NOR'
  echo '#          PARKED-ONLY IS COVERAGE. (The pre-C2 rule was "any retire at pc >= 0x4000",'
  echo '#          which the IVT slot jump at 0x814c alone satisfied -- it reported a stalled'
  echo '#          tile as PARTICIPATED.)'
  echo '#          17 plants and 18 scfails are APPENDED by V4/C2: the'
  echo '#          <applied>/<total> censuses vesta_ref prints for the A13 PLANT and A14'
  echo '#          forced-SC-failure records ("-" when the realignment script carried none,'
  echo '#          which is every V3-shaped run). applied < total = an UNCONSUMED TAIL, i.e.'
  echo '#          the reference read stale RAM — see INFRA-FAIL(plant-tail-unconsumed).'
  echo '#          A14 note, and it must be repeated wherever an SC result is reported: the'
  echo '#          SC success/failure DECISION is ASSERTED, not compared. What stays'
  echo '#          compared is the SC'"'"'s address, its rd, outcome/effect consistency, and'
  echo '#          everything downstream.'
  echo '#          elab_ms and sim_ms are PER TEST and repeat on each of its cells.'
  printf '#status\ttest\trcf\tentry\ta0\trtl_R_total\trtl_cmp_retires\tspike_lines\tcompared_records\telab_ms\tsim_ms\tspike_ms\tcmp_ms\tdetail\thart\tparticipation\tplants\tscfails\n'
} > "$RESULTS"

n_pass=0; n_div=0; n_hung=0; n_infra=0; n_pend=0; n_missing=0
n_part=0; n_parked=0; n_notrace=0; n_noaudit=0; n_launched=0
n_plantcells=0; n_planttail=0
div_list=(); hung_list=(); infra_list=(); pend_list=(); parked_list=(); launched_list=()
plant_lines=(); planttail_list=()
for rcf_base in "${TESTS[@]}"; do
    nm="${rcf_base%.rcf}"; t="$(strip_pad "$nm")"
  for hd in $COSIM_HARTS; do
    hh="$(hh_of "$hd")"
    cell="$t"; [ "$MULTI" = 1 ] && cell="$t#h$hh"
    if [ ! -f "$STATUS_DIR/$t#h$hh" ]; then
        n_missing=$((n_missing+1))
        printf 'NO-RESULT\t%s\t%s\t-\t-\t0\t0\t0\t0\t0\t0\t0\t0\tworker produced no status row\t%s\t-\t-\t-\n' \
            "$t" "$rcf_base" "$hh" >> "$RESULTS"
        infra_list+=("$cell(no-status)")
        n_noaudit=$((n_noaudit+1))
        continue
    fi
    cat "$STATUS_DIR/$t#h$hh" >> "$RESULTS"
    st="$(cut -f1 "$STATUS_DIR/$t#h$hh")"
    # The appended fields are read BY OFFSET FROM THE END (participation is now
    # third from last, plants second, scfails last): a `detail` that happened to
    # contain a tab would shift every index from the front but never the tail.
    pt="$(awk -F'\t' '{print $(NF-2)}' "$STATUS_DIR/$t#h$hh")"
    pl="$(awk -F'\t' '{print $(NF-1)}' "$STATUS_DIR/$t#h$hh")"
    sc="$(awk -F'\t' '{print $NF}' "$STATUS_DIR/$t#h$hh")"
    case "$st" in
        PASS)            n_pass=$((n_pass+1)) ;;
        DIVERGE*)        n_div=$((n_div+1));  div_list+=("$cell:$st") ;;
        HUNG)            n_hung=$((n_hung+1)); hung_list+=("$cell") ;;
        COMPARE-PENDING) n_pend=$((n_pend+1)); pend_list+=("$cell") ;;
        *)               n_infra=$((n_infra+1)); infra_list+=("$cell:$st") ;;
    esac
    # The participation census. A PARKED-ONLY cell can be a PASS (12 matching ROM
    # retires really did match) and STILL be zero coverage of the test body —
    # which is exactly why it is censused separately from the verdict.
    case "$pt" in
        PARTICIPATED)  n_part=$((n_part+1)) ;;
        LAUNCHED-ONLY) n_launched=$((n_launched+1)); launched_list+=("$cell") ;;
        PARKED-ONLY)   n_parked=$((n_parked+1)); parked_list+=("$cell") ;;
        NO-TRACE)      n_notrace=$((n_notrace+1)) ;;
        *)             n_noaudit=$((n_noaudit+1)) ;;
    esac
    # The A13/A14 census. Shown for every cell whose reference actually carried
    # P/F records, and an applied<total tail gets its own loud list: a plant that
    # never fired means the reference read STALE RAM, which is the one failure
    # mode of the V4 design.
    case "$pl" in
        */*)
            n_plantcells=$((n_plantcells+1))
            pa="${pl%%/*}"; pb="${pl##*/}"
            plant_lines+=("$(printf '%-30s plants=%-13s scfails=%s' \
                "$cell" "$pl" "$sc")")
            if [ "$pb" -gt "$pa" ] 2>/dev/null; then
                n_planttail=$((n_planttail+1))
                planttail_list+=("$cell: $(( pb - pa )) of $pb plant(s) NEVER APPLIED")
            fi ;;
    esac
  done
done
n_infra=$(( n_infra + n_missing ))

# ── the per-test launch-race margin table (audit 2) ───────────────────────────
# Its own file, NOT a results.tsv column: the margin is a property of the TEST
# (hart 0's msip stores versus hart 0's own last record), so replicating it on
# every cell of the test would invite it to be summed or averaged across harts,
# which is meaningless. results.tsv stays one grain (test,hart); this stays one
# grain (test).
{
  printf '# launch-race margin — %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
  echo '# margin = (cycle of hart 0'"'"'s LAST trace record) - (cycle of hart 0'"'"'s LAST'
  echo '#          store of 00000001 to msip[1..3] = 0x5004/0x5008/0x500c), in clk_cpu'
  echo '#          cycles. It is the whole window a launched tile has to boot from the'
  echo '#          shared ROM, take its msip ISR and copy its image before hart 0'"'"'s a0'
  echo '#          watch ends the sim. Compare against the loader cost (~5 cycles/word x'
  echo '#          LEN): shmem_mp measured 1,011 against 32,768 needed, i.e. ~32x short,'
  echo '#          and all three of its tiles never reached the test body at all.'
  echo '# n/a = this test issued no msip[1..3] launch store.'
  printf '#test\tmargin_clk_cpu\tmsip_store_cycle_hex\thart0_last_cycle_hex\tmsip_addr\n'
  for rcf_base in "${TESTS[@]}"; do
      nm="${rcf_base%.rcf}"; t="$(strip_pad "$nm")"
      if [ -s "$LAUNCH_DIR/$t" ]; then printf '%s\t%s' "$t" "$(cat "$LAUNCH_DIR/$t")"
      else printf '%s\tn/a\t-\t-\t-\n' "$t"; fi
  done
} > "$LAUNCH_TSV"
lm_lines=(); lm_na=0
for rcf_base in "${TESTS[@]}"; do
    nm="${rcf_base%.rcf}"; t="$(strip_pad "$nm")"
    lm="$(cut -f1 "$LAUNCH_DIR/$t" 2>/dev/null)"
    if [ -z "$lm" ] || [ "$lm" = "n/a" ]; then lm_na=$((lm_na+1)); continue; fi
    lm_lines+=("$(printf '%-28s margin=%-8s (msip@0x%s cyc=0x%s -> hart0 last cyc=0x%s)' \
        "$t" "$lm" "$(cut -f4 "$LAUNCH_DIR/$t")" "$(cut -f2 "$LAUNCH_DIR/$t")" \
        "$(cut -f3 "$LAUNCH_DIR/$t")")")
done

WALL=$(( SWEEP_T1 - SWEEP_T0 ))
{
echo "=============================================================================="
if [ "$MULTI" = 1 ]; then
echo " LOCKSTEP SWEEP RESULT   ($TOTAL cell(s) = $NTESTS x $NHARTS_SEL harts, MAX_PARALLEL=$MAX_PARALLEL, ${WALL}s wall)"
else
echo " LOCKSTEP SWEEP RESULT   ($TOTAL test(s), MAX_PARALLEL=$MAX_PARALLEL, ${WALL}s wall)"
fi
echo "=============================================================================="
printf '   PASS             %4d\n' "$n_pass"
printf '   DIVERGE          %4d\n' "$n_div"
printf '   HUNG             %4d\n' "$n_hung"
printf '   INFRA-FAIL       %4d\n' "$n_infra"
printf '   COMPARE-PENDING  %4d\n' "$n_pend"
echo "------------------------------------------------------------------------------"
if [ ${#div_list[@]} -gt 0 ]; then
    echo " DIVERGE (streams + comparator output KEPT for triage):"
    for x in "${div_list[@]}"; do echo "   $x"; done
fi
if [ ${#hung_list[@]} -gt 0 ]; then
    echo " HUNG (killed at ${TEST_TIMEOUT}s — the 1-minute rule):"
    for x in "${hung_list[@]}"; do echo "   $x"; done
fi
if [ ${#infra_list[@]} -gt 0 ]; then
    echo " INFRA-FAIL (NEVER counted as PASS):"
    for x in "${infra_list[@]}"; do echo "   $x"; done
fi
if [ ${#pend_list[@]} -gt 0 ]; then
    echo " COMPARE-PENDING: $COMPARE_PY absent — everything up to the compare ran."
fi
echo "------------------------------------------------------------------------------"
# V4: the hart set + the two audits. NOT verdicts — a PARKED-ONLY cell can be a
# perfectly good PASS and still be zero coverage of the test body, and a thin
# launch margin is a finding about the TEST, not about the chip.
echo " harts    : COSIM_HARTS='$COSIM_HARTS'   ($NTESTS test(s) x $NHARTS_SEL hart(s) = $TOTAL cell(s))"
printf ' particip.: PARTICIPATED %d / LAUNCHED-ONLY %d / PARKED-ONLY %d / NO-TRACE %d   (cells)\n' \
    "$n_part" "$n_launched" "$n_parked" "$n_notrace"
[ "$n_noaudit" -gt 0 ] && printf '            %d cell(s) not audited (failed before the sim produced a trace)\n' "$n_noaudit"
if [ ${#launched_list[@]} -gt 0 ] && [ "$MULTI" = 1 ]; then
    echo " LAUNCHED-ONLY (took the loader trap but NEVER reached the test image —"
    echo "                still inside the bootrom ISR at sim end; NOT coverage."
    echo "                This is the rtl_findings.md T1 shape: check the launch margin):"
    for x in "${launched_list[@]}"; do echo "   $x"; done
fi
if [ ${#parked_list[@]} -gt 0 ] && [ "$MULTI" = 1 ]; then
    echo " PARKED-ONLY (booted, parked, never launched at all — NOT coverage):"
    for x in "${parked_list[@]}"; do echo "   $x"; done
fi
if [ "$n_plantcells" -gt 0 ]; then
    # A14: say it wherever an SC result is reported. The forced-fail mechanism
    # makes the SC's success/failure DECISION asserted, not compared.
    printf ' plants   : %d cell(s) carried A13 PLANT records; %d with an UNCONSUMED TAIL\n' \
        "$n_plantcells" "$n_planttail"
    echo "            (scfails = A14 forced SC failures. The SC success/failure DECISION and"
    echo "             its rd are BOTH ASSERTED, not compared -- rd IS the oracle that decides"
    echo "             the forcing (A15: a globally-failed sc.w still emits an M S record, so"
    echo "             store-presence cannot serve), and comparing a value you forced is not"
    echo "             comparison. COMPARED: the SC's address, store-presence CONSISTENCY with"
    echo "             the asserted outcome, and every downstream effect.)"
    for x in "${plant_lines[@]}"; do echo "   $x"; done
fi
if [ ${#planttail_list[@]} -gt 0 ]; then
    echo " *** UNCONSUMED PLANT TAIL — THE V4 DESIGN'S ONE FAILURE MODE ***"
    echo "     A plant that never fired means the reference READ STALE RAM at that point, so"
    echo "     anything it then compared equal proves NOTHING. Triage before believing any"
    echo "     verdict on these cells (v4_design.md 3.5, RECORD_FORMAT A13):"
    for x in "${planttail_list[@]}"; do echo "   $x"; done
fi
if [ ${#lm_lines[@]} -gt 0 ]; then
    echo " LAUNCH-RACE MARGIN (clk_cpu cycles a launched tile actually got):"
    for x in "${lm_lines[@]}"; do echo "   $x"; done
fi
[ "$lm_na" -gt 0 ] && echo " LAUNCH-RACE MARGIN: $lm_na test(s) issued no msip[1..3] launch store (n/a)"
echo " results : $RESULTS"
echo " summary : $SUMMARY"
echo " traces  : $TRACE_DIR    spike logs: $SPIKE_DIR"
echo " launch  : $LAUNCH_TSV"
echo "=============================================================================="
} | tee "$SUMMARY"

# exit code: 0 only if every test PASSed
if [ "$n_pass" -eq "$TOTAL" ]; then exit 0; fi
if [ "$n_pend" -gt 0 ] && [ $(( n_pass + n_pend )) -eq "$TOTAL" ]; then exit 2; fi
exit 1
