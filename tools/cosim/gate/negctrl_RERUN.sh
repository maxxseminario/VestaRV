#!/bin/bash
# ===========================================================================
# THE MANDATORY STAGE-2 MISSING-PLANT NEGATIVE CONTROL — Fable's re-run recipe.
#
#   tools/cosim/gate/negctrl_RERUN.sh   (artifacts -> $NEGCTRL_WORKDIR, below)
#
# CANONICAL COPY, W5 2026-07-31. This script used to live ONLY in a session
# scratchpad outside the repo, which is how it rotted: it hard-coded the
# pre-A10 substitution `00004000:000000b0`, and W5 MEASURED that it no longer
# runs at all -- mk_inject exits 5 (EXIT_REFUSED) because 0xb0 contradicts
# bit 0, which the RTL actually drives. Corrected to 0xb1 then, and tracked
# here so a `git clean -xdf` cannot take the programme's central soundness
# control with it. A negative control that cannot execute is not a control.
#
# CPR8/R7 (2026-08-15): 0xb1 -> 0xa1 and --mem 0x0:0x20000 -> 0x0:0x40000, both
# following the promotion of the shipped chip to five harts. The x-substitution
# moved because P0.4 IS the tb's free-running 32.768 kHz `clk_lfxt` oscillator
# (riscv_tb.vhd:423), so bit 4 of that PxIN word is a CLOCK PHASE SAMPLE and the
# five-master arbiter round shifted this boot instruction across an LFXT edge --
# see the long note at xrun_cosim.sh's BOOT_ALLOW_X_1. The memory window moved
# because memory map v2 widened SH_AW 15 -> 16. THIS FILE ROTS THE SAME WAY IT
# rotted before if either is left stale, and the symptom is identical: rc=5,
# EXIT_REFUSED, a control that does not run.
# See tools/cosim/check_gate_files.py.
#
# Proves that a single absent A13 PLANT record cannot slip through as PASS: the
# reference reads STALE RAM at that load and the comparator says so. This is
# v4_design.md §3.5 item 1 and §7.3 item 1 — the phase's central soundness risk.
#
# WHY THIS PLANT. Ordinal 2062 is the FIRST plant in shboot hart 0's list whose
# value is nonzero: it serves `lw t2,0(s7)` from 0x00010124 (shboot DONE[1]) and
# carries `d00e0001`, the token HART 1 wrote. So the reference cannot possibly
# hold that value on its own — dropping the plant is guaranteed observable. A
# plant carrying 00000000 would be a WEAK control: the reference's RAM is already
# zero there (the bootrom zeroes 0x10000-0x107FF), so its absence changes nothing
# and the control would "pass" while proving nothing.
#
# READ THIS BEFORE BELIEVING ANY VERDICT (it nearly fooled the C2 run):
#   The bound MUST come from compare.py's own `--count` pass, exactly as
#   xrun_cosim.sh does it. A hand-typed --max-records that lands short of the
#   divergent record yields a FALSE PASS: with --max-records 50154 this very
#   control exits 0, because the divergence is AT compared record #50154 and the
#   bound stops one record before it. With the real count (86320) it exits 1.
# ===========================================================================
set -u
MP="$HOME/vestarv/xcelium/riscv_test/behavioral_mp"
# ARTIFACTS. This file is TRACKED, so it must not write beside itself. HERE is
# the scratch directory for the ~12 MB of brackets/spike logs the control
# produces; it defaults under the gitignored xcelium tree. Override with
# NEGCTRL_WORKDIR=<dir>.
HERE="${NEGCTRL_WORKDIR:-$MP/cosim_work/negctrl_plant}"
mkdir -p "$HERE" || exit 1
MK="$HOME/vestarv/tools/cosim/mk_inject.py"
CMP="$HOME/vestarv/tools/cosim/compare.py"
PY=/usr/bin/python3.6
DROP=2062

cd "$MP" || exit 1
TRACE="cosim_work/traces/rv32ui-p-shboot_h00.trace"
INJ="cosim_work/inject/rv32ui-p-shboot.h00.inject"

# ---- 0. THE TRACE. Regenerated automatically if absent, because a PASSING sweep
#         DELETES it (bulky artifacts are dropped unless KEEP=1), so the recipe
#         must not depend on a previous run having been made with KEEP=1.
#         Costs ~20 s (one elaborate + one 4-hart traced sim).
if [ ! -s "$TRACE" ]; then
    echo "### regenerating $TRACE (absent: a passing sweep drops it) ###"
    ( cd "$MP" && MULTIHART=1 COSIM_BOOT=1 BRACKET_ISR=1 MAX_PARALLEL=1 KEEP=1 \
        ./xrun_cosim.sh xxxrv32ui-p-shboot ) > "$HERE/regen.log" 2>&1
    grep -E '^  \[' "$HERE/regen.log" | sed 's/^/  /'
fi
[ -s "$TRACE" ] || { echo "FATAL: could not produce $TRACE; see $HERE/regen.log"; exit 1; }
[ -s "$INJ" ]   || { echo "FATAL: no $INJ; see $HERE/regen.log"; exit 1; }

run_ref() {   # run_ref <bracket> <commitlog> <stdoutlog>
    ( source ~/local/spike_env.sh
      ./cosim_work/vesta_ref cosim \
        --rom "$HOME/vestarv/software/bootrom_mp/bin/rom.rcf" \
        --rom-base 0x0 --rom-format rcf --pc 0x0 \
        --mem 0x0:0x40000 --mmio 0x4000:0x4000 \
        --isa rv32imac_zicsr_zba_zbb_zbs_zbc --priv m --hartid 0 \
        --instructions 70944 --inject "$3" --bracket "$1" --log "$2" ) > "$4" 2>&1
}

verdict() {   # verdict <commitlog> <cmplog> -> prints "exit=N"; TWO PASSES, always
    local m
    m=$("$PY" "$CMP" --rtl "$TRACE" --spike "$1" --entry 0x00000000 --hart 00 \
            --x-allow cosim_xallow.txt --count --quiet 2>/dev/null)
    "$PY" "$CMP" --rtl "$TRACE" --spike "$1" --entry 0x00000000 --hart 00 \
        --x-allow cosim_xallow.txt --max-records "$m" > "$2" 2>&1
    echo "exit=$? (bound m=$m from --count, NEVER hand-typed)"
}

echo "########## A. GOLD: the full plant set ##########"
"$PY" "$MK" --rtl "$TRACE" -o "$HERE/gold.inject" --bracket-out "$HERE/gold.bracket" \
    --mmio 0x4000:0x4000 --plant auto --hdl-root "$HOME/vestarv/hdl/common" \
    --allow-x '*:00004000:000000a1' --allow-x '*:0000420c:00000000' 2>&1 | grep -E 'plants=|plant window'
run_ref "$HERE/gold.bracket" "$HERE/gold.spike.log" "$HERE/gold.inject" "$HERE/gold.ref.out"
grep -oE 'plants=[0-9]+/[0-9]+' "$HERE/gold.ref.out"
echo -n "  GOLD verdict:  "; verdict "$HERE/gold.spike.log" "$HERE/gold.cmp.log"

echo
echo "########## B. PERTURBED: drop exactly one plant ##########"
"$PY" "$MK" --rtl "$TRACE" -o "$HERE/nc.inject" --bracket-out "$HERE/nc.bracket" \
    --mmio 0x4000:0x4000 --plant auto --hdl-root "$HOME/vestarv/hdl/common" \
    --drop-plant "$DROP" \
    --allow-x '*:00004000:000000a1' --allow-x '*:0000420c:00000000' 2>&1 \
    | grep -E 'NEGATIVE CONTROL LANDED|plants=|-> '

echo "  --- PROVE THE PERTURBATION LANDED (the house rule) ---"
g=$(grep -c '^P ' "$HERE/gold.bracket"); n=$(grep -c '^P ' "$HERE/nc.bracket")
echo "    P records: GOLD=$g  PERTURBED=$n  (want exactly one fewer)"
if [ "$n" -ne $(( g - 1 )) ]; then
    echo "    *** UNLANDED PERTURBATION — this program treats that as a spec violation."
    echo "        Do NOT believe the verdict below. (mk_inject also refuses when"
    echo "        --drop-plant exceeds the plant count, so check its exit code too.)"
    exit 1
fi
grep -m1 'NEGATIVE CONTROL --drop-plant' "$HERE/nc.bracket" | sed 's/^/    /'
echo "    LANDED: yes"

run_ref "$HERE/nc.bracket" "$HERE/nc.spike.log" "$HERE/nc.inject" "$HERE/nc.ref.out"
grep -oE 'plants=[0-9]+/[0-9]+' "$HERE/nc.ref.out"
echo -n "  PERTURBED verdict:  "; verdict "$HERE/nc.spike.log" "$HERE/nc.cmp.log"
grep -A4 'DIVERGENCE at' "$HERE/nc.cmp.log" | head -6 | sed 's/^/    /'

echo
echo "########## C. EXPECTED RESULT ##########"
cat <<'EOF'
  GOLD      : exit=0, plants=9281/9281
  PERTURBED : exit=1, plants=9280/9280, and the divergence is
                DIVERGENCE at compared record #50154
                  rtl   : R ... 000082fc 000ba383 07 d00e0001   ; lw t2,0(s7)
                  spike : R ... 000082fc 000ba383 07 00000000   ; lw t2,0(s7)
                  differs: rdval: rtl=d00e0001 spike=00000000
  Anything else -- and ESPECIALLY a PERTURBED exit=0 -- means the plant mechanism
  is not load-bearing and Stage 2/3 results must not be trusted.
  NOTE the sweep's own artifacts (cosim_work/traces, cosim_work/inject) are
  never modified: every bracket/inject/log this control writes goes to
  $NEGCTRL_WORKDIR, so there is nothing to restore and no way for the control
  to contaminate a later sweep.
EOF
