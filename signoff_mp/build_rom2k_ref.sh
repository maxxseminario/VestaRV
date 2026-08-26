#!/bin/bash
# Build the rom2k_hvt_pg OA reference library from the IP kit GDS.
#
# WHY THIS LIBRARY EXISTS (2026-08-24, MCU_hart signoff).
#
# rom2k_hvt_pg is the 2048x32 boot ROM the 8 KiB ROM flip introduced on
# 2026-08-23.  It had NO OA REFERENCE LIBRARY ANYWHERE: signoff_mp/cds.lib did
# not define it, the Myshkin ~/chips/myshkin/ic/cds.lib that file INCLUDEs
# defines only rom_hvt_pg (the OLD 16 KiB plate), and strmin/reflib.list listed
# rom_hvt_pg alone.
#
# The signoff path does not consume the Innovus GDS directly.  drc.sh flattens
# OA -> GDS with strmout, and its own comment says what that step is for:
# "ref-lib cell layouts get merged here; this is what fills in std-cell/macro
# internals the Innovus GDS doesn't carry".  So a macro missing from every ref
# lib streams in as an EMPTY MASTER -- strmin_gds.sh's header states exactly
# that failure mode, and says it happens SILENTLY unless the log is read.
#
# The damage runs both ways:
#   * DRC goes FLATTERINGLY CLEAN on the ROM, because the geometry being
#     checked simply is not there -- including the 0.800 um M4 PG comb on a
#     1.400 um pitch that is the densest pin field on the die.
#   * LVS CANNOT MATCH, because all four lvs_include_* files gained the full
#     2,298,016-byte rom2k_hvt_pg.cdl on 2026-08-24.  That puts every ROM
#     device on the SCHEMATIC side while the LAYOUT side has an empty box.
#     Adding the CDL without adding this library converts a loud
#     "ERROR (NVN-13010): Cell rom2k_hvt_pg is not defined" abort into a
#     silent whole-block mismatch, which is strictly worse.
#
# This is NOT specific to MCU_hart: every flow that has flipped to the 8 KiB
# ROM inherits it.
#
# Modelled on build_myshkin_analog_ref.sh, but simpler: the source is a vendor
# GDS file rather than a strmout from a colliding tapeout library, so there is
# no cellMap rename to undo.
set -u

LIB=rom2k_hvt_pg
CELL=rom2k_hvt_pg
SRC=/home/mseminario2/chips/myshkin/ip/rom2k_hvt_pg/rom2k_hvt_pg.gds2
LAYERMAP=/opt/design_kits/TSMC65-PDK/tsmcN65/tsmcN65.layermap

die() { echo "ROM2KREF FATAL: $*"; exit 1; }

for t in strmin strmout; do
    command -v $t > /dev/null || die "$t not on PATH -- source ~/vestarv/cdspaths.sh"
done
[ -s "$SRC" ] || die "source GDS missing or empty: $SRC"
grep -qE "^DEFINE $LIB " cds.lib || die "cds.lib does not DEFINE $LIB -- add it first"
grep -qxF "$LIB" strmin/reflib.list || die "strmin/reflib.list does not list $LIB"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# The ROM is a self-contained hard macro: its children are its own bit-cell and
# decode structs, so only the tech lib is needed to resolve layers.
printf 'tsmcN65\n' > "$work/reflib.rom"

echo "==== $LIB : strmin from $SRC ===="
rm -rf "$LIB"
strmin \
    -library "$LIB" \
    -topCell "$CELL" \
    -strmFile "$SRC" \
    -layerMap strmin/gds2cds.map \
    -refLibList "$work/reflib.rom" \
    -techRefs tsmcN65 \
    -writeMode overwrite \
    -scaleTextHeight 0.025 \
    -skipUndefinedLPP \
    -noWarn "75 84 107 174 316 363 81000 80043" \
    -logfile "strmin/$LIB.strmin.log" > /dev/null
rc=$?
[ $rc -eq 0 ] && [ -f "strmin/$LIB.strmin.log" ] || die "strmin did not run/complete (rc=$rc)"
if grep -q "ERROR" "strmin/$LIB.strmin.log"; then
    echo "---- STRMIN ERRORS ----"; grep "ERROR" "strmin/$LIB.strmin.log"; exit 1
fi
[ -d "$LIB/$CELL/layout" ] || die "strmin exited 0 but $LIB/$CELL/layout was not created"

# PROOF GATE.  An empty-outline master is the exact defect this library repairs,
# so refuse to publish one: stream the cell back out and require real DEVICE
# layers (3 = OD, 6 = PO).  A shell carries metal and nothing else.
echo "==== $LIB : proof gate -- device layers present in the published master ===="
strmout -library "$LIB" -topCell "$CELL" -view layout \
    -strmFile "$work/verify.gds" \
    -techlib tsmcN65 -layerMap "$LAYERMAP" \
    -convertPin geometryAndText -noWarn "20 32 33 35 315" \
    -logFile "$work/verify.log" > /dev/null
[ -s "$work/verify.gds" ] || die "proof gate: strmout produced no GDS"
python3 - "$work/verify.gds" <<'PY' || exit 1
import struct,sys
data=open(sys.argv[1],'rb').read()
i=0;n=len(data);layers=set();nstruct=0
while i < n-4:
    rl,rt=struct.unpack('>HH',data[i:i+4])
    if rl<4: break
    if rt>>8 == 0x05: nstruct+=1
    if rt>>8 == 0x0d and rl>=6:
        layers.add(struct.unpack('>h',data[i+4:i+6])[0])
    i+=rl
print("   structs=%d  layers=%s" % (nstruct, sorted(layers)))
need={3,6}
missing=need-layers
if missing:
    print("   PROOF GATE FAILED: no device layers %s -- this is an EMPTY SHELL" % sorted(missing))
    sys.exit(1)
print("   PROOF GATE PASSED: OD and PO present, %d structs" % nstruct)
PY
echo "==== $LIB : published ===="
