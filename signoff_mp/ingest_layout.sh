#!/bin/bash
# Signoff layout ingest: normalize ANY layout format to GDS, then (re)stream it
# into a signoff OA library via the GUARDED strmin (strmin_gds.sh -- the Myshkin
# name-collision cellMap + XSTRM-287 gate live there; NEVER bypass it).
#
# This is the format-agnostic front door used by the signoff Makefile:
#   .gds/.gds2/.gdsii/.gds.gz  -> used directly (gz: decompressed to a temp)
#   .oas/.oasis                -> converted to GDS via calibredrv (Tcl SCRIPT
#                                 FILE, not -a args: the aoj_cal wrapper strips
#                                 quotes from inline args, same disease as the
#                                 CLAUDE.md python3 -c gotcha)
#
# The target lib is REBUILT from scratch on every ingest (rm -rf + strmin):
# stale-lib reuse across cuts is exactly the PG4/A6 phantom-geometry disease.
# A stamp file records the source path+mtime so the Makefile can skip re-ingest
# when nothing changed.
#
# usage: ./ingest_layout.sh <targetLib> <topCell> <layoutFile>
set -u
cd "$(dirname "$0")"

lib=$1; cell=$2; layout=$3
[ -f "$layout" ] || { echo "ingest: no such layout file: $layout"; exit 1; }
src_abs=$(readlink -f "$layout")
src_mtime=$(stat -c %Y "$src_abs")
stamp="$lib/.ingest_stamp"

# Skip when the lib was built from this exact file+mtime (Makefile fast path).
if [ -f "$stamp" ] && [ "$(cat "$stamp")" = "$src_abs $src_mtime" ]; then
    echo "ingest: $lib is current (source $src_abs unchanged) -- skipping"
    exit 0
fi

work=$(mktemp -d ./.ingest.XXXXXX)
trap 'rm -rf "$work"' EXIT
gds="$src_abs"

case "$layout" in
    *.oas|*.oasis)
        echo "ingest: converting OASIS -> GDS (calibredrv)"
        cat > "$work/conv.tcl" <<EOF
set L [layout create "$src_abs"]
\$L gdsout "$work/converted.gds"
exit
EOF
        calibredrv "$work/conv.tcl" > "$work/conv.log" 2>&1
        rc=$?
        if [ $rc -ne 0 ] || [ ! -s "$work/converted.gds" ]; then
            echo "ingest: calibredrv conversion FAILED (rc=$rc):"
            tail -10 "$work/conv.log"; exit 1
        fi
        gds="$work/converted.gds"
        ;;
    *.gds.gz|*.gds2.gz)
        echo "ingest: decompressing gzipped GDS"
        gunzip -c "$src_abs" > "$work/unzipped.gds" || exit 1
        gds="$work/unzipped.gds"
        ;;
    *.gds|*.gds2|*.gdsii)
        ;;
    *)
        echo "ingest: unknown layout extension on $layout (want .gds/.gds2/.gdsii[.gz]/.oas/.oasis)"
        exit 1
        ;;
esac

# Tools must exist BEFORE we rm the old lib (a no-env run must not destroy it).
for t in strmin calibredrv; do
    command -v "$t" > /dev/null || {
        echo "ingest: '$t' not on PATH -- source ~/vestarv/cdspaths.sh first"; exit 1; }
done

# Fresh lib every ingest -- never merge a new cut into an old lib.
rm -rf "$lib"
./strmin_gds.sh "$lib" "$cell" "$gds" || { echo "ingest: guarded strmin FAILED"; exit 1; }
# The lib dir is the real product -- verify it exists before stamping.
[ -d "$lib" ] || { echo "ingest: strmin exited 0 but no lib dir '$lib' -- refusing to stamp"; exit 1; }
echo "$src_abs $src_mtime" > "$stamp"
echo "ingest: $lib/$cell rebuilt from $src_abs"
