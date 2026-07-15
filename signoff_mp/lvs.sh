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
# usage: ./lvs.sh library cell lvsVerilog includeFile

set -u
cd "$(dirname "$0")"

lib=$1
cell=$2
vfile=$3
incfile=$4
ctlfile=${5:-}          # optional pegasus control file (e.g. lvs_black_box)

V2CDL=/opt/cadence/PVS201/tools/bin/v2cdl
DECK=/opt/design_kits/TSMC65-PDK/kit/PVS/LVS/pvs.lvs
WORK=pvs/$lib/$cell
mkdir -p "$WORK"

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

# PG4: bind the pmk secondary WELL ports on instance lines. The pmk CDL
# subckts carry VNW/VPW bulk ports, but those pins have NO LEF geometry, so
# saveNetlist's verilog never names them and v2cdl's $PINS leaves them
# defaulting to floating parent nets named VNW/VPW -> every pmk bulk reads
# "missing connection" against the layout (which correctly extracts the
# wells onto VDD/VSS through the PG4 FILLBIAS strap fabric). The DB's
# globalNetConnect rules declare exactly VNW=VDD, VPW=VSS -- make the CDL
# say the same. (Same spirit as the vdd!->VDD-fixed analog component CDLs.)
sed -i -E '/^X[^ ]+ +(HEADBUF|GPGBUF|GPGINV|A2ISO|O2ISO|HEAD[0-9])[A-Z0-9]*MA10TH +\$PINS/ s/$/ VNW=VDD VPW=VSS/' "$WORK/${lib}_${cell}.cdl"

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
if [ -f "pvs/${cell}.lvslabels" ]; then
    python3 gds_add_labels.py "$WORK/$cell.gds" "$cell" "pvs/${cell}.lvslabels" || exit 1
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
rep=$(ls -t "$WORK"/*.rep 2>/dev/null | head -1)
grep -E "Run Result|MISMATCH|MATCH" "$WORK"/pvs_lvs.log "$WORK"/pegasus_stdout.log $rep 2>/dev/null | head -5
