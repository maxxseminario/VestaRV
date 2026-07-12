#!/bin/bash
# =============================================================================
# xrun.sh — compile + elaborate + simulate ONE test against the A5 CONNECTED-CHIP post-P&R
# gate netlist (18-tile MCU_ARGUS assembly + hardened hart_tile_argus) with
# hierarchical SDF timing, in SimVision (GUI).
#
#   ./xrun.sh                  # default test: simple
#   ./xrun.sh shboot           # partial match on ../rca/*.rcf
#
# Headless twin: ./xrun_batch.sh [test]  (-> xrun.log)
#
# DUT = innovus/common/out/{MCU_ARGUS.xsim.clean.v + hart_tile_argus.xsim.v}, SDF
# via chip_argus.sdfcmd (top + 18 tile scopes, MAXIMUM). Argus images live
# in ../rca (A3: 29-char TEST_FILE, x-padded basenames). Tiles boot from the
# shared ROM like silicon — the local rom_hvt_pg_verilog.rcf is the CURRENT
# software/bootrom_mp/bin/rom.rcf (the ROM verilog model $readmemb's it from
# cwd; re-copy after any bootrom rebuild). The only deposit is the shared-bank
# zero-init (make_ram_deposit.py, shbank0-7; no NPU in Argus).
#
# -nonotifier (M9b): timing-check VIOLATIONS still print but no longer X the
# violating flop via the cell's notifier reg (async reset release trips
# reset-time $hold checks whose notifier-X poisons boot state). SDF delays
# stay annotated and enforced.
# Gate sims are MUCH slower than behavioral — the 1-MINUTE RULE DOES NOT APPLY.
# =============================================================================

source ~/vestarv/cdspaths.sh
cd "$(dirname "$0")"

PAT="${1:-simple}"
if [ "$XRUN_MODE" = "batch" ]; then MODE=""; else MODE="-gui"; fi

mapfile -t MATCHES < <(cd ../rca && ls *"$PAT"*.rcf 2>/dev/null)
case ${#MATCHES[@]} in
    0) echo "No ../rca/*${PAT}*.rcf found."; exit 1 ;;
    1) RCF="../rca/${MATCHES[0]}" ;;
    *) echo "Ambiguous '$PAT':"; printf '  %s\n' "${MATCHES[@]}"; exit 1 ;;
esac
if [ ${#RCF} -ne 29 ]; then
    echo "ERROR: '$RCF' is ${#RCF} chars; TEST_FILE must be exactly 29."
    exit 1
fi
echo "Running Argus gate-level test: $RCF  (mode: ${MODE:-batch})"

mkdir -p log
python3 make_ram_deposit.py ":dut:chip:mcu0" \
    > log/preload.tcl || { echo "preload generation failed"; exit 1; }

# Driver tcl: preload before the first fetch, re-assert during the second
# reset pulse (tb: resetn 0..40ns, second pulse 280-380ns), then free-run.
if [ "$XRUN_MODE" = "batch" ]; then
# Chunked free-run (CLAUDE.md chunked-tcl rule): xmsim buffers output, so a
# monolithic 'run' gives NO liveness signal for hours (the first shboot
# attempt died silently at 92.4 ms sim-time with a truncated log). 5 ms
# chunks + flushed marker lines make progress and death points visible.
cat > log/gate_run.tcl <<EOF
run 1 ns
source log/preload.tcl
run 299 ns
source log/preload.tcl
set done 0
for {set i 1} {\$i <= 50} {incr i} {
    run 5 ms
    puts "### GATE-CHUNK \$i (~[expr {\$i * 5}] ms sim-time)"
    # A5: early exit once the tb latched pass/fail -- the final report
    # severity failure only PAUSES batch xmsim back to this driver, and the
    # remaining schedule would burn ~1 min/chunk of dead wall time.
    catch { if {[string match -nocase "*true*" [value {:a0_reached_pass}]] || [string match -nocase "*true*" [value {:a0_reached_fail}]]} { set done 1 } }
    if {\$done} { puts "### EARLY-EXIT after chunk \$i (pass/fail latched)"; flush stdout; break }
    # shboot/shwfi diagnosis: DONE[1..17] = 0x10120+4h = shbank0 words 72-88 =
    # rows 2-3 (32 words/row). Dump raw rows; decode offline.
    if {[catch {puts "### DONE-ROW2 [value {:dut:chip:mcu0:shbank0:mem[2]}]"} e]} { puts "### DONE-PROBE-ERR2 \$e" }
    if {[catch {puts "### DONE-ROW3 [value {:dut:chip:mcu0:shbank0:mem[3]}]"} e]} { puts "### DONE-PROBE-ERR3 \$e" }
    flush stdout
}
if {!\$done} { run }
exit
EOF
else
cat > log/gate_run.tcl <<EOF
run 1 ns
source log/preload.tcl
run 299 ns
source log/preload.tcl
puts "shared macros zeroed; 'run' to continue"
EOF
fi

LIB_PATH="xcelium.d"
[ -d $LIB_PATH ] && rm -r $LIB_PATH

hdlFiles="$(< cell_list_chip_argus.txt)"

xrun \
    $hdlFiles \
    -top riscv_tb \
    -generic "TEST_FILE=>\"$RCF\"" \
    -sdf_cmd_file chip_argus.sdfcmd \
    -sdfstats log/sdf_stats.log \
    -v200x \
    -work work \
    -ALLOWREDEFINITION \
    $MODE \
    -access +rwc \
    -controlrelax nlstex \
    -relax \
    -nonotifier \
    -input ../../disable_x_warnings.tcl \
    -input log/gate_run.tcl
