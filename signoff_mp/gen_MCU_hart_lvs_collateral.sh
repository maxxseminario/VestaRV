#!/bin/bash
# MCU_hart (2026-08-24): build the LVS collateral for the mcu_hart signoff
# block.  BLOCK-level clone of gen_MCU_castalia_penta_lvs_collateral.sh with the
# chip-only parts removed: there is no pad ring, so there is no pad patcher, and
# there is no orchestrator, so there is no orch_* assertion.
#
# WHAT IT PRODUCES (exactly what signoff_mp/Makefile's mcu_hart NETLIST/LABELS
# point at):
#   pvs/MCU_hart.lvs.v        block only, from this cut's own DB
#   pvs/MCU_hart.lvslabels    same session: <tile pieces> VDD_SW_H0 texts plus
#                             2 DERIVED VDD/VSS short sentinels
#   pvs/MCU_hart_full.lvs.v   = block + pvs/hart_tile.lvs.v
#
# WHY THE CONCATENATION (the F2a devlog): a netlist that BOXES hart_tile against
# a FLAT layout hits the 1M-net matcher threshold and aborts, and an empty tile
# stub reproduces the same NVN-7090.  The proven recipe appends the FULL tile
# netlist, no stub, and `module hart_tile` must be the LAST module in the file.
#
# ORDERING NOTE (the lvs.sh G0 staleness gate): lvs.sh FATALs when the labels
# file is older than the netlist it is given (= the _full file).  The innovus
# step writes the labels, then this script appends the tile netlist, so the
# labels would end up older by seconds.  The final `touch` restamps them; the
# pre-check refuses to restamp anything older than the netlist the SAME innovus
# run just wrote, so real cross-cut staleness still trips the gate.
#
# usage: ./gen_MCU_hart_lvs_collateral.sh [skip_netlist]
#
# Prereqs: source ~/vestarv/cdspaths.sh; the P&R run must have written
# ../innovus/common/MCU_hart/dbs/MCU_hart.signoff.innovus.dat and
# out/MCU_hart.xsim.v; pvs/hart_tile.lvs.v + pvs/hart_tile.lvslabels from the
# SAME tile cut the flow consumed.  BATCH ONLY -- one heavy run at a time.

set -u
cd "$(dirname "$0")"

SKIP=${1:-}
INN=../innovus/common/MCU_hart
PVS=pvs
TILE_NETLIST=$PVS/hart_tile.lvs.v
BASE=MCU_hart
TCL=tcl/${BASE}_lvs_netlist.tcl

die() { echo "HART_LVS FATAL: $*"; exit 1; }

case "$SKIP" in
    ""|skip_netlist) ;;
    *) die "usage: $0 [skip_netlist]" ;;
esac

# ---- shared tile-cut gates (A7 / G0) ----------------------------------------
[ -f "$TILE_NETLIST" ] || die "$TILE_NETLIST missing -- regen via tcl/hart_tile_lvs_netlist.tcl"
[ -f "$PVS/hart_tile.lvslabels" ] || die "$PVS/hart_tile.lvslabels missing (same tcl dumps it)"
# TILE-CUT PROVENANCE, BY CONTENT RATHER THAN BY MTIME (2026-08-25).
# The old gate asked whether $TILE_NETLIST was NEWER than the tile abstract.
# That is a proxy, and on the 2026-08-25 tile cut the proxy is simply wrong:
# tcl/relef.tcl re-emitted out/hart_tile.lef from the SAME final database
# minutes after the netlist was dumped, purely to restore the antenna model,
# so a same-cut netlist reads as older than a same-cut LEF.
# The replacement compares the thing that actually has to agree.
# out/hart_tile.xsim.v is written by the run that writes out/hart_tile.gds2,
# so it names the shipped cut's instances.
# If the tile LVS netlist carries the same instance set it is that cut's
# netlist, whatever the timestamps say, and if it does not then no mtime
# ordering could have made it safe.
TILE_XSIM=../innovus/common/hart_tile/out/hart_tile.xsim.v
TILE_GDS=../innovus/common/hart_tile/out/hart_tile.gds2
[ -f "$TILE_XSIM" ] || die "$TILE_XSIM missing -- cannot establish the tile cut"
[ ! "$TILE_XSIM" -ot "$TILE_GDS" ] || \
    die "$TILE_XSIM is older than $TILE_GDS -- the reference sim netlist is not the shipped cut"
python3 - "$TILE_NETLIST" "$TILE_XSIM" <<'PROV' || die "tile-cut provenance check failed"
import re, sys

def insts(path):
	txt = open(path, errors='replace').read()
	m = re.search(r'^module\s+hart_tile\s*\(', txt, re.M)
	if not m:
		print('PROV: no "module hart_tile" in ' + path)
		return None
	body = txt[m.start():txt.find('\nendmodule', m.start())]
	keep = set()
	for mm in re.finditer(r'^\s{1,4}([A-Za-z_][\w$]*)\s+([\\]?[^\s(]+)\s*\(', body, re.M):
		cell = mm.group(1)
		if cell in ('module', 'input', 'output', 'inout', 'wire', 'reg',
			    'assign', 'tri', 'supply0', 'supply1'):
			continue
		keep.add((cell, mm.group(2)))
	return keep

a = insts(sys.argv[1])
b = insts(sys.argv[2])
if a is None or b is None:
	sys.exit(1)
only_a = a - b
only_b = b - a
print('PROV: tile netlist %d insts, reference %d insts, %d/%d unique'
      % (len(a), len(b), len(only_a), len(only_b)))
if only_a or only_b:
	for x in sorted(only_a)[:5]:
		print('PROV:   only in the LVS netlist: %s %s' % x)
	for x in sorted(only_b)[:5]:
		print('PROV:   only in the reference  : %s %s' % x)
	print('PROV: the tile LVS netlist is NOT the shipped tile cut.')
	sys.exit(1)
print('PROV: tile-cut provenance PASS (instance sets identical)')
PROV
[ ! "$PVS/hart_tile.lvslabels" -ot "$TILE_NETLIST" ] || \
    die "$PVS/hart_tile.lvslabels is older than $TILE_NETLIST -- re-dump both from one cut"

netlist=$PVS/$BASE.lvs.v
labels=$PVS/$BASE.lvslabels
full=$PVS/${BASE}_full.lvs.v

CUTSEL="${CUTSEL:-signoff}"
[ -d "$INN/dbs/${BASE}.${CUTSEL}.innovus.dat" ] || \
    die "no $INN/dbs/${BASE}.${CUTSEL}.innovus.dat -- re-run P&R (or set CUTSEL)"
echo "==== $BASE : cut of record = ${BASE}.${CUTSEL} ===="

XSIM="$INN/out/${BASE}.xsim.v"
[ -f "$XSIM" ] || die "no $XSIM"
[ -f "$TCL" ] || die "no $TCL"

echo "==== $BASE : stage 1 -- netlist + same-cut labels + sentinels (innovus batch) ===="
if [ "$SKIP" != "skip_netlist" ]; then
    command -v innovus > /dev/null || die "innovus not on PATH -- source ~/vestarv/cdspaths.sh"
    mkdir -p "$INN/log"
    ( cd "$INN" && innovus -no_gui -batch \
        -log "log/${BASE}_lvs_regen" -overwrite \
        -files "../../../signoff_mp/$TCL" ) || die "$TCL rc"
fi
[ -s "$netlist" ] || die "$netlist missing/empty (the A7 sanity gate deletes a bad netlist)"
[ -s "$labels" ]  || die "$labels missing/empty -- lvs.sh would SILENTLY skip the VDD_SW injection"
[ ! "$labels" -ot "$netlist" ] || die "$labels older than $netlist -- not one session"

# 2026-08-25 SENTINEL CARRY: the tile dump ends in its own VDD:/VSS: short
# sentinels.  The top-level dump no longer aliases those per hart (they made
# spurious VSS_H1-vs-VSS shorts), so they are not counted as carried pieces.
tile_pieces=$(awk 'NF>=4 && $4!="VDD:" && $4!="VSS:"' "$PVS/hart_tile.lvslabels" | wc -l)
want=$(( tile_pieces + 2 ))
got=$(wc -l < "$labels")
[ "$got" -eq "$want" ] || die "$labels has $got labels, expected $want (1 x $tile_pieces tile pieces + 2 sentinels)"
# THE SENTINELS ARE THE POINT.  An empty shorts file without two CONFLICTING
# texts proves nothing (Stage J: a real PDB3A VDD-VSS ring short, invisible to
# Innovus, to the PG wrapper and to Calibre DRC, produced exactly that).  So
# assert both are present and that they are on DIFFERENT nets, here, before the
# verdict is ever read.
n_vdd_sent=$(grep -c '^131 .* VDD:$' "$labels" || true)
n_vss_sent=$(grep -c '^131 .* VSS:$' "$labels" || true)
[ "$n_vdd_sent" -eq 1 ] || die "$labels has $n_vdd_sent VDD: sentinel texts (want exactly 1) -- FIND_SHORTS would be text-blind"
[ "$n_vss_sent" -eq 1 ] || die "$labels has $n_vss_sent VSS: sentinel texts (want exactly 1) -- FIND_SHORTS would be text-blind"
echo "     $labels  $got labels ($tile_pieces tile pieces + 2 VDD/VSS short sentinels)"
grep -E '^131 .* (VDD|VSS):$' "$labels" | sed 's/^/       sentinel: /'

echo "==== $BASE : stage 2 -- append the full tile netlist (collision-safe) ===="
# The block fabric and the FROZEN tile collateral can define the same module
# name (genus uniquifies per run), which FATALs Pegasus with NVN-13300.
# cp5_fix_module_collisions.py does the concat and renames any collider in the
# TILE COPY only, never in the shared pvs/hart_tile.lvs.v.
python3 cp5_fix_module_collisions.py "$netlist" "$TILE_NETLIST" "$full" || die "module-collision concat"
grep -q "^module hart_tile" "$full" || die "$full has no hart_tile module -- concat failed"
[ "$(grep -c '^module hart_tile' "$full")" -eq 1 ] || \
    die "$full has more than one hart_tile module (a stub survived -- the F2a attempt-3 trap)"
echo "     $full  $(wc -c < "$full") bytes, $(grep -c '^module ' "$full") modules"

echo "==== $BASE : stage 3 -- restamp labels after the concat ===="
touch "$labels"
echo "==== $BASE : collateral ready ===="

echo
echo "Next (one heavy run at a time, shared licenses):"
echo "  cd ~/vestarv/signoff_mp && source ~/vestarv/cdspaths.sh"
echo "  make drc BLOCK=mcu_hart"
echo "  make ant BLOCK=mcu_hart"
echo "  make lvs BLOCK=mcu_hart"
echo "READ THE PEGASUS VERDICT LINE, NEVER THE .rc FILE."
