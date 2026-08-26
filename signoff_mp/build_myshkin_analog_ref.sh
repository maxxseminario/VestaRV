#!/bin/bash
# Build the myshkin_analog OA reference library: the THREE hand-laid analog
# macros (GlitchFilter, OscillatorCurrentStarved, PowerOnResetCheng) under
# their CORRECT base cell names, carrying their REAL device-level layout.
#
# WHY THIS LIBRARY EXISTS (2026-08-24, LVS phantom-device forensics).
#
# The Innovus flows place these three blocks from LEF abstracts only
# (chips/myshkin/ic/abstracts/myshkin_abs/*: .lef + abstract.replay + cell_list,
# no GDS), and the streamOut -merge list carries ONLY the hardened tile + the
# tphn pads.  So the assembly GDS contains an EMPTY OUTLINE struct for each of
# the three.  The real geometry is meant to arrive later, at signoff strmin,
# by NAME resolution against a reference library -- see strmin_gds.sh's PG4
# gate, whose comment states the intent exactly: "the ONLY intended
# myshkin_tapeout resolutions are the 3 analog macros (their real layouts live
# there; the Innovus GDS carries abstracts)".
#
# That intent was only ever HALF met.  When the Myshkin tapeout GDS was
# streamed into myshkin_tapeout, the file contained BOTH twins of two of the
# three blocks -- the Innovus abstract shell AND the real hand layout -- and
# the second one to arrive was renamed by the collision rule:
#
#   struct 411  GlitchFilter               -> myshkin_tapeout/GlitchFilter
#   struct 5160 GlitchFilter_0             -> myshkin_tapeout/GlitchFilter_0
#   struct 413  OscillatorCurrentStarved   -> myshkin_tapeout/OscillatorCurrentStarved
#   struct 5122 OscillatorCurrentStarved_1 -> myshkin_tapeout/OscillatorCurrentStarved_1
#
# The cell that kept the BASE NAME -- the only name strmin can resolve against
# -- is the EMPTY SHELL for both.  Measured by streaming each master back out:
#
#   myshkin_tapeout/GlitchFilter                 2,048 B   4 structs, layer 32 only
#   myshkin_tapeout/GlitchFilter_0             120,832 B  14 structs, OD/PO/NP/PP, 32x GlitchFilterBiEdge
#   myshkin_tapeout/OscillatorCurrentStarved     6,144 B   metal only
#   myshkin_tapeout/OscillatorCurrentStarved_1 276,480 B  76 structs, real devices
#   myshkin_tapeout/PowerOnResetCheng          153,600 B  37 structs, real devices  <- no collision, base name is correct
#
# So every signoff LVS this project has ever run resolved GlitchFilter and
# OscillatorCurrentStarved to an empty outline, compared them against their
# full device-level CDLs, and counted the difference as an unmatched residual:
# 4 x 480 = 1,920 devices for GlitchFilter and 2 x ~220 = ~440 for the DCO.
# PowerOnResetCheng, which never collided, has been matching correctly all along
# -- which is the control that proves the mechanism.
#
# The fix is NOT to exclude the blocks from the compare.  The layout EXISTS.
# This library republishes it under the names resolution actually looks for.
#
# The masters are taken from myshkin_tapeout, not from the myshkin design
# library, because the design library is NOT self-contained: streaming
# myshkin/PowerOnResetCheng dies with
#   ERROR (XSTRM-341) ... Cannot open design myshkin/DelayCell0P5MA10TH/layout
# (the custom delay cell was never checked into it).  myshkin_tapeout carries
# the full flattened hierarchy for all three.
#
# usage: ./build_myshkin_analog_ref.sh          (rebuilds from scratch)
set -u
cd "$(dirname "$0")"

LIB=myshkin_analog
LAYERMAP=/opt/design_kits/TSMC65-PDK/tsmcN65/tsmcN65.layermap

for t in strmin strmout; do
    command -v "$t" > /dev/null || {
        echo "build_myshkin_analog_ref: '$t' not on PATH -- source ~/vestarv/cdspaths.sh first"; exit 1; }
done

work=$(mktemp -d ./.analogref.XXXXXX)
trap 'rm -rf "$work"' EXIT

# cell-in-target-lib  <-  struct-in-source-file
#   The rename is the whole point for the first two: the real layout lives on
#   the _0 / _1 collision name and must be republished on the base name.
#   Map records are 4-column "<libName> <cellName> <viewName> <structName>".
build_one() {
    local cell=$1 srcCell=$2
    echo "== $LIB/$cell  <-  myshkin_tapeout/$srcCell =="
    strmout -library myshkin_tapeout -topCell "$srcCell" -view layout \
        -strmFile "$work/$cell.gds" \
        -techlib tsmcN65 -layerMap "$LAYERMAP" \
        -convertPin geometryAndText \
        -noWarn "20 32 33 35 315" \
        -logFile "$work/$cell.strmout.log" > /dev/null
    if grep -qE "^ERROR" "$work/$cell.strmout.log"; then
        echo "---- FATAL: strmout of myshkin_tapeout/$srcCell failed ----"
        grep -E "^ERROR" "$work/$cell.strmout.log"; exit 1
    fi
    [ -s "$work/$cell.gds" ] || { echo "FATAL: empty GDS for $srcCell"; exit 1; }

    printf '%s %s layout %s\n' "$LIB" "$cell" "$srcCell" > "$work/$cell.cellmap"
    strmin \
        -library "$LIB" \
        -topCell "$srcCell" \
        -strmFile "$work/$cell.gds" \
        -layerMap strmin/gds2cds.map \
        -refLibList "$work/reflib.analog" \
        -techRefs tsmcN65 \
        -writeMode overwrite \
        -scaleTextHeight 0.025 \
        -skipUndefinedLPP \
        -cellMap "$work/$cell.cellmap" \
        -noWarn "75 84 107 174 316 363 81000 80043" \
        -logfile "strmin/$LIB.$cell.strmin.log" > /dev/null
    rc=$?
    if [ $rc -ne 0 ] || [ ! -f "strmin/$LIB.$cell.strmin.log" ]; then
        echo "---- FATAL: strmin did not run/complete (rc=$rc) ----"; exit 1
    fi
    if grep -q "ERROR" "strmin/$LIB.$cell.strmin.log"; then
        echo "---- STRMIN ERRORS ----"; grep "ERROR" "strmin/$LIB.$cell.strmin.log"; exit 1
    fi
    [ -d "$LIB/$cell/layout" ] || {
        echo "FATAL: strmin exited 0 but $LIB/$cell/layout was not created"; exit 1; }
}

# Std cells resolve to the kit lib rather than being duplicated here; the
# analog-private children (GlitchFilterBiEdge, DacR2R12, DelayCell0P5MA10TH,
# the pcell/via structs) translate into this library and stay self-contained.
printf 'tsmcN65\ntsmc65_sc_adv10\n' > "$work/reflib.analog"

rm -rf "$LIB"
build_one GlitchFilter             GlitchFilter_0
build_one OscillatorCurrentStarved OscillatorCurrentStarved_1
build_one PowerOnResetCheng        PowerOnResetCheng

# PROOF GATE: an empty-outline master is exactly the defect this library
# exists to repair, so refuse to publish one.  Stream each cell back out and
# require real DEVICE layers (3=OD, 6=PO) -- the shell has metal only.
echo "== proof gate: device layers present in every published master =="
for cell in GlitchFilter OscillatorCurrentStarved PowerOnResetCheng; do
    strmout -library "$LIB" -topCell "$cell" -view layout \
        -strmFile "$work/verify_$cell.gds" \
        -techlib tsmcN65 -layerMap "$LAYERMAP" \
        -convertPin geometryAndText -noWarn "20 32 33 35 315" \
        -logFile "$work/verify_$cell.log" > /dev/null
    python3 - "$work/verify_$cell.gds" "$cell" <<'PY' || exit 1
import struct,sys
path,cell=sys.argv[1],sys.argv[2]
data=open(path,'rb').read()
i=0;n=len(data);layers=set();nstruct=0
while i<n-4:
    rl,rt=struct.unpack('>HH',data[i:i+4])
    if rl<4: break
    t=rt>>8;lo=rt&0xff
    if t==0x06 and lo==0x06: nstruct+=1
    elif t==0x0d: layers.add(struct.unpack('>h',data[i+4:i+6])[0])
    i+=rl
dev={3,6}
ok=dev.issubset(layers)
print(f"    {cell:26s} structs={nstruct:3d}  OD/PO present={ok}")
if not ok:
    print(f"    FATAL: {cell} has NO device layers -- this is the empty-shell defect.")
    sys.exit(1)
PY
done
echo "build_myshkin_analog_ref: $LIB rebuilt and proven"
