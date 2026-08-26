#!/bin/bash
# PG3 signoff LVS: post-route PG-aware verilog -> CDL (v2cdl), stitch macro
# CDLs, strmout the OA layout with pin text, run batch Pegasus LVS with the
# TSMC PVS deck. Adapted from the tapeout-proven Myshkin harness
# (chips/myshkin/ic/pvs/innovuslvs); differences:
#   * the verilog is generated with saveNetlist -includePowerGround (Castalia
#     has THREE power nets -- VDD, VDD_SW, VSS -- plus the pmk secondary pins
#     VDDG/VNW/VPW; Myshkin's single-rail netlist relied on globals)
#   * no alphabetize step (that was for -check_schematic vs an OA schematic;
#     v2cdl emits named $PINS connections, so instance pin ORDER is moot)
#   * include file is a parameter (tile vs MCU stitch different macro CDLs)
# Run from ~/vestarv/signoff_mp. BATCH ONLY (shared licenses).
#
# CQ8b PER-RUN ISOLATION (same shape as drc.sh): every invocation gets its OWN
# work dir  pvs/<lib>/<cell>/run_<pgid>_<epoch>/  so two concurrent sessions on
# the same lib/cell never clobber each other's CDL / labelled GDS / pegasus
# run_dir + reports mid-run. The report artifacts (*.rep, *.cls, *.sum,
# pvs_lvs.log, pegasus_stdout.log) are then published back to the legacy path
# pvs/<lib>/<cell>/ (mtime-preserving, atomic per file) so accept_*.sh
# (`ls -t pvs/<lib>/<cell>/*.rep`, `grep ... *.cls`) keep working unchanged.
# Cleanup is SCOPED BY PROCESS GROUP: re-exec under setsid ($$ == PGID),
# advertise the PGID -- external cleanup does `kill -TERM -<PGID>`, never a
# `pkill -f <pattern>` that could match a neighbour or the killer's own cmdline.
#
# usage: ./lvs.sh library cell lvsVerilog includeFile [controlFile]
#
# EXIT STATUS IS THE TOOL'S VERDICT, not the tool's exit code (2026-08-24):
#   0  MATCH        10  MISMATCH        11  no verdict line found
#   non-zero from pegasus itself is still propagated as-is (stale reports).
# Set LVS_VERDICT_ADVISORY=1 to force exit 0; the verdict is printed regardless.

set -u

# Re-exec once under setsid: fresh session / process group ($$ == PGID);
# `setsid -w` forwards the child's exit status so callers' `; rc=$?` is intact.
if [ -z "${_LVS_ISOLATED:-}" ]; then
    export _LVS_ISOLATED=1
    exec setsid -w "$0" "$@"
fi

cd "$(dirname "$0")"

lib=$1
cell=$2
vfile=$3
incfile=$4
ctlfile=${5:-}          # optional pegasus control file (e.g. lvs_black_box)

V2CDL=/opt/cadence/PVS201/tools/bin/v2cdl
DECK=/opt/design_kits/TSMC65-PDK/kit/PVS/LVS/pvs.lvs
PUB_DIR=pvs/$lib/$cell                    # legacy shared path (consumers read here)
WORK=$PUB_DIR/run_$$_$(date +%s)          # per-run isolated work dir
mkdir -p "$WORK"

# Advertise the process group so external cleanup is scoped to THIS run.
echo "$$" > "$WORK/run.pgid"
echo "=== lvs.sh isolated run ==================================================="
echo "    lib/cell : $lib / $cell"
echo "    WORK     : $WORK"
echo "    PGID     : $$   (scoped kill:  kill -TERM -$$ )"
echo "=========================================================================="
ln -sfn "$(basename "$WORK")" "$PUB_DIR/latest"

# Publish report artifacts back to the legacy path for accept_*.sh consumers.
# cp -p preserves mtimes so `ls -t *.rep | head -1` still resolves the newest;
# temp-name + mv = atomic per file (a same-cell concurrent publish is
# last-writer-wins on whole files, never a torn read).
publish_back() {
    mkdir -p "$PUB_DIR"
    shopt -s nullglob
    for f in "$WORK"/*.rep "$WORK"/*.rep.* "$WORK"/*.cls "$WORK"/*.sum \
             "$WORK"/pvs_lvs.log "$WORK"/pegasus_stdout.log; do
        b=$(basename "$f")
        cp -p "$f" "$PUB_DIR/.$b.$$" && mv -f "$PUB_DIR/.$b.$$" "$PUB_DIR/$b"
    done
    shopt -u nullglob
}

echo "== v2cdl =="
# NB (PG4 forensics): v2cdl's named-$PINS output omits some pin bindings
# (e.g. the ClkGate wrappers list only ClkIn/En) — this is a stable v2cdl
# convention, NOT data loss: rewriting `.En(1'b0)` to `.En(VSS)` in the
# verilog produced a byte-identical CDL, and the v11-era CDL has the same
# form while its compare matched. Omitted pins resolve inside Pegasus;
# do not chase the CDL text when devices mismatch — check the LAYOUT.
$V2CDL -v "$vfile" -o "$WORK/${lib}_${cell}.cdl" || exit 1

# CDL bus-bit convention is <n>; the verilog carries [n] (Myshkin precedent).
sed -i 's/\[\([0-9]*\)\]/\<\1\>/g' "$WORK/${lib}_${cell}.cdl"

# Bind the secondary WELL ports on EVERY std-cell instance line. The
# bulk-ported CDLs (tsmc65_hvt_sc_adv10.cdl and the pmk file, both named in
# the lvs_include_* lists) carry VNW/VPW bulk ports, but those pins have NO
# LEF geometry, so saveNetlist's verilog never names them and v2cdl's $PINS
# leaves them defaulting to floating parent nets named VNW/VPW -> every bulk
# reads "missing connection" against the layout (which correctly extracts the
# wells onto VDD/VSS through the PG4 FILLBIAS strap fabric). The DB's
# globalNetConnect rules declare exactly VNW=VDD, VPW=VSS -- make the CDL
# say the same. (Same spirit as the vdd!->VDD-fixed analog component CDLs.)
#
# 2026-08-25: this used to name only the pmk cells (HEADBUF|GPGBUF|GPGINV|
# A2ISO|O2ISO|HEAD[0-9]) because the base library came in through
# tsmc65_hvt_sc_adv10_no_bulk.cdl, which has no VNW/VPW ports at all and ties
# every bulk to the cell's OWN VDD/VSS port instead. In the header-gated rows
# the cell VDD port is VDD_SW, so that variant asserted n-well = VDD_SW while
# the layout has it on always-on VDD, and the compare emitted ~61k
# "B: VDD | ** missing connection **" terminal lines per power net at BOTH
# tile and chip level. The include files now name the bulk-ported CDL and the
# match below covers all *A10TH cells. Every A10TH subckt the designs
# instantiate has both ports; the only base-library cells without them are the
# FILL*TIE* physical fillers, which never reach the verilog netlist.
#
# The append lands on the line carrying $PINS even when the instance
# continues onto '+' lines: CDL concatenates continuations, and v2cdl emits
# NAMED connections, so position does not matter.
sed -i -E '/^X[^ ]+ +[A-Za-z0-9_]*A10TH +\$PINS/ s/$/ VNW=VDD VPW=VSS/' "$WORK/${lib}_${cell}.cdl"

# Macro/std-cell subckt definitions
printf '.INCLUDE %s\n' "$(readlink -f "$incfile")" | cat - "$WORK/${lib}_${cell}.cdl" > "$WORK/.tmp" && mv "$WORK/.tmp" "$WORK/${lib}_${cell}.cdl"

echo "== strmout (with pin text) =="
strmout -library "$lib" -topCell "$cell" -view layout \
    -strmFile "$WORK/$cell.gds" \
    -techlib tsmcN65 \
    -layerMap /opt/design_kits/TSMC65-PDK/tsmcN65/tsmcN65.layermap \
    -convertPin geometryAndText \
    -noWarn "20 32 33 35 315" \
    -logFile "$WORK/strmout.log" > /dev/null
# NB: match real XSTRM error records only -- "Translation completed. '0'
# error(s)" contains the word "error" and a bare grep -i aborts a good run.
grep -E "^ERROR" "$WORK/strmout.log" && exit 1

# PG4: switched-rail virtual-connect labels. VDD_SW is 471 layout pieces
# joined only through the header switches — without a name hook LVS sees
# 471 nets vs one schematic net and every cell on an unmatched piece
# mismatches (PG3's "ClkGate/tie islands on VDD_SW"). The deck runs
# VIRTUAL_CONNECT -COLON YES + metal text ATTACH, so one "VDD_SW:" text
# per piece (layer 131 = M1 text) unifies them. Labels file is emitted by
# the netlist-gen step; skipped silently if absent (e.g. bare macros).
# Labels file defaults to pvs/<cell>.lvslabels; override with LVSLABELS= (Argus
# A6: the chip topcell is "chip_top" for BOTH Castalia C0 and Argus -- distinct
# only by the target lib -- so Argus passes LVSLABELS=pvs/chip_top_argus.lvslabels
# to avoid reading C0's pvs/chip_top.lvslabels).
LABELS=${LVSLABELS:-pvs/${cell}.lvslabels}
if [ -f "$LABELS" ]; then
    # G0 STALENESS GATE (2026-07-22): the labels/netlist/GDS triple must come
    # from the SAME cut (the A7 re-P&R-invalidates rule EXTENDED TO LABELS).
    # The tracked *_lvs_netlist.tcl recipes write the netlist FIRST, then dump
    # the labels, so labels older than the netlist = a re-harden regenerated
    # the netlist but not the labels (the Stage-F G0 near-miss: 10-day-stale
    # piece centers riding a fresh cut). Content HAPPENED to be identical that
    # time — the gate makes the discipline structural, not lucky.
    # Override for deliberate forensics: LVS_ALLOW_STALE_LABELS=1.
    if [ "$LABELS" -ot "$vfile" ] && [ -z "${LVS_ALLOW_STALE_LABELS:-}" ]; then
        echo "FATAL: $LABELS is OLDER than $vfile — labels/netlist are from different cuts."
        echo "       Re-dump the labels from the SAME signoff DB (the block's *_lvs_netlist.tcl"
        echo "       does netlist+labels together), or set LVS_ALLOW_STALE_LABELS=1 to override."
        exit 3
    fi
    python3 gds_add_labels.py "$WORK/$cell.gds" "$cell" "$LABELS" || exit 1
fi
# HIERARCHICAL chip LVS (chip_top / chip_top_argus): hart_tile is a boxed hcell,
# so its switched-rail VDD_SW must be virtual-connected INSIDE the tile struct
# (one struct definition covers all 4/18 tile refs). tile-relative coords, name
# "VDD_SW" (matches the source tile net directly -- no cpoint). Guarded to chip
# wrappers so the flat MCU/tile runs (which flatten the tile) are untouched.
case "$cell" in
  chip_top*)
    if [ -f "pvs/hart_tile_vddsw.lvslabels" ]; then
        python3 gds_add_labels.py "$WORK/$cell.gds" "hart_tile" "pvs/hart_tile_vddsw.lvslabels" || exit 1
    fi ;;
esac

echo "== pegasus -lvs =="
CTL=""
if [ -n "$ctlfile" ]; then CTL="-control $(readlink -f "$ctlfile")"; fi
pegasus -lvs -check_schematic $CTL \
    -gds "$WORK/$cell.gds" -layout_top_cell "$cell" \
    -source_top_cell "$cell" -source_cdl "$WORK/${lib}_${cell}.cdl" \
    -run_dir "$WORK" \
    "$DECK" > "$WORK/pegasus_stdout.log" 2>&1
rc=$?
echo "pegasus rc=$rc"
# PG4 STALE-READBACK GATE (LVS flavor): a control-file parse error aborts
# pegasus (rc=3) BEFORE any report is rewritten — the old lvs.rep.cls then
# reads as a plausible "result" (two cpoint experiments served identical
# stale numbers before this gate). Never mask the rc.
if [ $rc -ne 0 ]; then
    echo "FATAL: pegasus rc=$rc — reports in $WORK are STALE, do not read them"
    exit $rc
fi
# Publish the (fresh, rc=0) reports to the legacy path for downstream consumers.
publish_back
rep=$(ls -t "$WORK"/*.rep 2>/dev/null | head -1)
echo "Reports (isolated) : $WORK"
echo "Reports (published): $PUB_DIR"

# =============================================================================
# THE VERDICT.  READ THIS, NEVER THE .rc FILE.
#
# 2026-08-24.  Until now this script exited with pegasus's own rc, which is 0
# on MISMATCH -- pegasus ran fine, it simply reported a mismatch.  Every driver
# above it recorded that 0 (signoff_mp/*_lvs.rc all read "RC=0"), and the whole
# project read those files as "LVS passed" for months.  The tool's RESULT and
# the tool's EXIT STATUS are different facts, and this is where they get
# separated: the exit status below is the tool's RESULT.
#
#   0   MATCH
#   10  MISMATCH          (pegasus rc was still 0)
#   11  no verdict found  (do not guess: treat as a failed run)
#
# Callers that must not fail on a mismatch can set LVS_VERDICT_ADVISORY=1, but
# the verdict is printed either way and the reason has to be a real one.
# =============================================================================
verdict=""
for f in "$WORK"/*.cls "$WORK"/pegasus_stdout.log "$WORK"/pvs_lvs.log; do
    [ -f "$f" ] || continue
    v=$(grep -aoE "Run Result[[:space:]]*:[[:space:]]*[A-Z]+" "$f" 2>/dev/null | head -1 | awk '{print $NF}')
    if [ -n "$v" ]; then verdict=$v; break; fi
done

# SENTINEL ARMING.  An EMPTY shorts file proves NOTHING unless the labelled GDS
# carried two CONFLICTING power texts: in Stage J a real PDB3A VDD-VSS ring
# short -- invisible to Innovus, to the PG wrapper and to Calibre DRC -- came
# back with an empty shorts file because there were no sentinels to see it.
# So the shorts count is only ever reported together with whether it was armed.
sent="NOT ARMED"
if [ -f "$LABELS" ]; then
    # NB no `|| echo 0`: grep -c already prints 0 and merely EXITS 1 when it
    # finds nothing, so an `|| echo 0` appends a second line and the numeric
    # test below then dies with "integer expression expected".
    nv=$(grep -c -E "[[:space:]]VDD:[[:space:]]*$" "$LABELS" 2>/dev/null)
    ng=$(grep -c -E "[[:space:]]VSS:[[:space:]]*$" "$LABELS" 2>/dev/null)
    nv=${nv:-0}; ng=${ng:-0}
    if [ "$nv" -ge 1 ] && [ "$ng" -ge 1 ]; then
        sent="ARMED ($nv VDD:, $ng VSS: texts in $LABELS)"
    else
        sent="NOT ARMED ($nv VDD:, $ng VSS: texts in $LABELS -- FIND_SHORTS is TEXT-BLIND)"
    fi
else
    sent="NOT ARMED (no labels file $LABELS -- FIND_SHORTS is TEXT-BLIND)"
fi

shorts_file=$(ls -t "$WORK"/*.shorts 2>/dev/null | head -1)
if [ -n "$shorts_file" ]; then
    shorts_n=$(wc -l < "$shorts_file")
    shorts_txt="$shorts_n line(s) in $(basename "$shorts_file")"
else
    shorts_txt="no shorts file emitted"
fi

echo "=========================================================================="
echo "    LVS VERDICT   : ${verdict:-<none found>}     ($lib / $cell)"
echo "    pegasus rc    : $rc   <-- NOT the verdict; 0 even on MISMATCH"
echo "    shorts        : $shorts_txt"
echo "    sentinels     : $sent"
echo "    report        : ${rep:-<none>}"
echo "=========================================================================="
grep -aE "Run Result|Cells which mismatch|Cells matched" "$WORK"/*.cls 2>/dev/null | head -5

case "$verdict" in
    MATCH)
        vrc=0 ;;
    MISMATCH)
        echo "LVS MISMATCH -- read $PUB_DIR/lvs.rep.cls, not any .rc file."
        vrc=10 ;;
    *)
        echo "LVS: NO VERDICT LINE FOUND in the reports. Treating as a failed run;"
        echo "     an unreadable verdict must never be reported as a pass."
        vrc=11 ;;
esac

if [ -n "${LVS_VERDICT_ADVISORY:-}" ]; then
    echo "LVS_VERDICT_ADVISORY set -- exiting 0 despite verdict '$verdict' (rc would have been $vrc)"
    exit 0
fi
exit $vrc
