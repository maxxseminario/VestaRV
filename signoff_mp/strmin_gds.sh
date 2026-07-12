#!/bin/bash
# PG3 signoff: stream an Innovus GDS into an OA work library in THIS workspace.
# Adapted from the frozen Myshkin harness (chips/myshkin/ic/strmin/strmin.sh) --
# the tapeout-proven recipe; do not "improve" the noWarn list without reading
# that script's history. Run from ~/vestarv/signoff_mp (cds.lib lives here).
#
# usage: ./strmin_gds.sh targetLib topCell gdsFile
# e.g.:  ./strmin_gds.sh hart_tile_mp hart_tile ../innovus_mp/out/hart_tile.gds2

set -u
cd "$(dirname "$0")"

targetLib=$1
topcell=$2
gdsFile=$3

# LESSON (Myshkin): refs resolve through reflib.list; a cell missing from every
# ref lib streams in as an EMPTY master silently unless you read the log.
# Always grep the log for unresolved/undefined refs after a run (done below).
noWarn="75 84 107 174 316 363 81000 80043"

# LESSON (PG4, the FOURTH GDS-phantom class -- this one ADDS geometry): the
# Castalia assembly and Myshkin's tapeout share the design name "MCU", so both
# streamOuts auto-name their custom via structs MCU_VIA<n>. Name-based ref-lib
# resolution then silently REPLACED Castalia's MCU_VIA83 (a 22-cut VIA5 array)
# with myshkin_tapeout/MCU_VIA83 (a 36-cut VIA7 array with 5x5.6 M7/M8 pads)
# at all 248 placements: manufactured a phantom VDD-VSS short (pad overlapping
# an opposite-net M8 row), the VIA7.W.1/S.2 930x2 + M8.S.3 x93 "headline" DRC
# classes, and ~30k phantom LVS device mismatches -- across PG3 AND PG4 cuts
# (PG3's "M8-pass M8->M4 stack" forensics were reading Myshkin's via cell).
# The via numbering is seed-dependent, so ANY MCU_VIA<n> may collide on any
# re-cut: the cell map renames them all to MCU_MP_VIA* (never a Myshkin name)
# so they TRANSLATE instead of resolving. -wildCardInCellMap is a FLAG (an
# argument after it is treated as an option and dies XSTRM-102). Map records
# are 4-column "<libName> <cellName> <viewName> <structName>" -- a 2-column
# form is IGNORED with a one-line XSTRM-28 (and greps for XSTRM-28 match
# XSTRM-287 too; anchor with a colon). Regenerated per run: the lib column
# must be THIS run's target library.
printf '%s MCU_MP_VIA* layout MCU_VIA*\n' "$targetLib" > strmin/via_rename.cellmap
# ... and pin the TOP CELL into the target lib: into a FRESH library, strmin
# resolves even the root against reflib.list first — a topcell named like a
# Myshkin cell ("MCU") gets REFERENCED from myshkin_tapeout instead of
# translated (caught by the gate on the first mcu_trial_lib import; the
# MCU_MP_signoff runs never hit it because the cell already existed there).
printf '%s %s layout %s\n' "$targetLib" "$topcell" "$topcell" >> strmin/via_rename.cellmap
strmin \
    -library "$targetLib" \
    -topCell "$topcell" \
    -strmFile "$gdsFile" \
    -layerMap "strmin/gds2cds.map" \
    -refLibList "strmin/reflib.list" \
    -techRefs "tsmcN65" \
    -writeMode overwrite \
    -scaleTextHeight 0.025 \
    -skipUndefinedLPP \
    -cellMap "strmin/via_rename.cellmap" \
    -wildCardInCellMap \
    -noWarn "$noWarn" \
    -logfile "strmin/$targetLib.$topcell.strmin.log" > /dev/null

sed -n -e '/INFO (XSTRM-234):/,$p' "strmin/$targetLib.$topcell.strmin.log"
# LESSON: a failed translation (e.g. wrong -topCell: the MCU_MP.gds2 top
# structure is "MCU", the DESIGN_NAME, not the file basename) reports
# XSTRM-273 "Translation failed", NOT XSTRM-234 -- scan for hard errors first.
if grep -q "ERROR" "strmin/$targetLib.$topcell.strmin.log"; then
    echo "---- STRMIN ERRORS ----"
    grep "ERROR" "strmin/$targetLib.$topcell.strmin.log"
    exit 1
fi
echo "---- unresolved-reference scan ----"
grep -i "unresolved\|undefined\|could not find\|missing master" \
    "strmin/$targetLib.$topcell.strmin.log" || echo "none"

# PG4 hard gate: no DESIGN-generated struct may resolve to a myshkin_tapeout
# master. The ONLY intended myshkin_tapeout resolutions are the 3 analog
# macros (their real layouts live there; the Innovus GDS carries abstracts).
swaps=$(grep "XSTRM-287" "strmin/$targetLib.$topcell.strmin.log" \
        | grep "myshkin_tapeout" \
        | grep -vE "'(GlitchFilter|PowerOnResetCheng|OscillatorCurrentStarved)'")
if [ -n "$swaps" ]; then
    echo "---- FATAL (PG4 gate): unexpected myshkin_tapeout master swap ----"
    echo "$swaps"
    exit 1
fi
