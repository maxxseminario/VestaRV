#!/bin/bash
# =============================================================================
# view_tile.sh -- open a HARDENED hart_tile in the Innovus GUI, for LOOKING at.
#
# WHY THIS EXISTS: `make hart_tile.innovus.gui` (innovus/common/Makefile) does
# NOT open the finished tile -- it RE-RUNS the entire harden with the window up,
# ~10-40 minutes, and overwrites out/ and dbs/ when it gets there. That target is
# for watching a run come up or debugging one mid-flight. To simply LOOK at the
# result, restore the saved database instead: seconds, and read-only in practice.
#
# THE .dat DIRECTORIES CONTAIN ABSOLUTE SYMLINKS, so a database only restores
# from where it was written. Do not move or copy dbs/ elsewhere and expect a
# restore to work -- run this script in place.
#
# Usage:
#   ./view_tile.sh                 # the final DB (post-route, post-ETM)
#   ./view_tile.sh signoff         # the signoff DB
#   ./view_tile.sh <name>          # any dbs/hart_tile.<name>.innovus.dat
#   ./view_tile.sh -l              # list what is available
#
# Needs an X display (a VNC session is fine: echo $DISPLAY).
# =============================================================================
set -uo pipefail
cd "$(dirname "$0")"

if [ "${1:-}" = "-l" ]; then
	echo "Available hart_tile databases in dbs/:"
	for d in dbs/hart_tile.*.innovus.dat; do
		[ -d "$d" ] || continue
		n=$(basename "$d"); n=${n#hart_tile.}; n=${n%.innovus.dat}
		printf "  %-22s %s\n" "$n" "$(stat -c %y "$d" | cut -d. -f1)"
	done
	exit 0
fi

TAG="${1:-final}"
DB="dbs/hart_tile.${TAG}.innovus.dat"

if [ ! -d "$DB" ]; then
	echo "ERROR: $DB not found."
	echo "Run './view_tile.sh -l' to list the databases that exist."
	exit 1
fi

if [ -z "${DISPLAY:-}" ]; then
	echo "ERROR: DISPLAY is unset -- the Innovus GUI needs an X display."
	echo "Start the VNC session (~/vnc-start.bash), then re-run."
	exit 1
fi

mkdir -p .tmp log
cat > .tmp/view_tile.tcl <<EOF
# Restore only -- this session writes nothing. Deliberately no saveDesign, no
# streamOut, no verify: a viewing session must not be able to modify a signoff
# database by accident.
restoreDesign $DB hart_tile
puts ""
puts "### hart_tile restored from $DB"
puts "### die: [dbGet top.fPlan.box]"
puts "### insts: [llength [dbGet top.insts]]   nets: [llength [dbGet top.nets]]"
puts ""
puts "### Useful: Windows>Layout, or type  fit  /  zoomIn  /  zoomOut"
puts "### The TCM macro is instance 'ram0' -- selectInst ram0 ; fit"
puts ""
EOF

echo "Opening $DB in the Innovus GUI (DISPLAY=$DISPLAY)..."
echo "(this restores the finished tile; it does not re-run the flow)"
source ../../../cdspaths.sh
exec innovus -overwrite -log log/view_tile -files .tmp/view_tile.tcl
