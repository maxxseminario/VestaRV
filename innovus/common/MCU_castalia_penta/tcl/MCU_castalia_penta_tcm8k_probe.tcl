################################################################################
# TCM8K PROBE -- READ-ONLY on the 2026-08-17 CPR6 cut (8 KiB TCM, debug+JTAG).
#
# Three questions the existing reports cannot answer, one restore, NO edits:
#
#  (a) WHAT IS THE REAL POST-ROUTE DRC?  Nothing on disk says.  The only
#      UNCAPPED post-route number (4240) is measured with the DIE-WIDE M7/M8
#      route blockages of tcl line ~1301 still in place, so it is dominated by
#      `... & Routing Blockage` OVERLAP/SHORT artifacts against a keep-out the
#      flow installs ON PURPOSE.  The blockage-free `.noblk` number (202) is
#      measured BEFORE routeDesign, so it is a pre-route figure.  And the
#      signoff pass TRUNCATED at the default limit of 1000 (IMPVFG-103).  Here
#      the blockages come out and the limit goes up, so the number means
#      something.
#
#  (b) IS THE CPR7 ANTENNA REALLY GONE?  The signoff report says `Antenna : 0`,
#      but that report was the truncated one, so its silence is not evidence.
#      Re-checked here with -antenna and a real limit.
#
#  (c) ARE THE 8 KiB TCM's SPLIT PG RAILS ACTUALLY BOUND?  THIS IS THE POINT OF
#      THE SCRIPT.  sram1p8k_hvt_pg exposes VDDPE / VDDCE / VSSE where
#      sram1p16k_hvt_pg exposed plain VDD / VSS, the tile's globalNetConnect was
#      rewritten for it, and that binding now exists FIVE TIMES in this chip and
#      has never been checked by LVS.  PG2-F1 is the precedent and it is exact:
#      a macro whose power was never bound shipped in GDS three times, Innovus
#      returned rc=0 each time, and only foundry LVS ever saw it.  An unbound
#      supply here is a dead chip, so it is worth knowing BEFORE Calibre.
#
# READ-ONLY: no saveDesign, no streamOut, no edits that outlive the session.
# (deleteAllRouteBlks mutates the in-memory DB only -- nothing is written back.)
#
# Run: cd ~/vestarv/innovus/common/MCU_castalia_penta && source ~/vestarv/cdspaths.sh
#      innovus -no_gui -batch -log log/MCU_castalia_penta_tcm8k_probe -overwrite \
#              -files tcl/MCU_castalia_penta_tcm8k_probe.tcl
################################################################################
source ../shared/constants.tcl

set DESIGN_NAME MCU_castalia_penta
set BASENAME    MCU_castalia_penta
set CUTDB       ${BASENAME}.cpr6.signoff
set REPORT_DIR  rpt

if {![file isdirectory $DATABASE_DIR/${CUTDB}.innovus.dat]} {
    puts "### T8K ### FATAL: no $DATABASE_DIR/${CUTDB}.innovus.dat"
    exit 1
}
restoreDesign $DATABASE_DIR/${CUTDB}.innovus.dat $DESIGN_NAME
setCheckMode -tapeOut false
puts "### T8K ### restored cut = $CUTDB"

################################################################################
# (c) FIRST, because it is the one that can kill the chip.
# For every TCM macro instance, list its PG pins and the net each is bound to.
# An 8 KiB macro must show VDDPE + VDDCE on a VDD-class net and VSSE on a
# VSS-class net.  Anything unbound (empty net) is the PG2-F1 signature.
################################################################################
puts "### T8K ### ---- TCM PG BINDING ----"
set __bad 0
set __seen 0
foreach __i [dbGet -p top.insts.cell.name sram1p*] {
    set __iname [dbGet $__i.name]
    set __cell  [dbGet $__i.cell.name]
    incr __seen
    foreach __t [dbGet $__i.instTerms -e] {
        set __pin [dbGet $__t.cellTerm.name -e]
        if {$__pin eq "" || $__pin eq "0x0"} { continue }
        set __use [dbGet $__t.cellTerm.isPGType -e]
        if {$__use ne "1"} { continue }
        set __net [dbGet $__t.net.name -e]
        if {$__net eq "" || $__net eq "0x0"} {
            puts "### T8K ### UNBOUND  $__iname ($__cell) pin $__pin -> (no net)"
            incr __bad
        } else {
            puts "### T8K ### bound    $__iname ($__cell) pin $__pin -> $__net"
        }
    }
}
puts "### T8K ### TCM macro instances seen = $__seen ; unbound PG pins = $__bad"
if {$__seen == 0} {
    puts "### T8K ### FATAL: no sram1p* instances found -- the query is wrong, not the chip."
    exit 1
}
if {$__bad > 0} {
    puts "### T8K ### *** PG2-F1 CLASS: $__bad unbound TCM supply pin(s). ***"
}

################################################################################
# (a)+(b) DRC, with the deliberate keep-outs removed and a limit that does not
# truncate.  In-memory only; this DB is never saved.
################################################################################
puts "### T8K ### ---- DRC (route blockages removed, limit 100000) ----"
deleteAllRouteBlks
verifyGeometry \
    -error 100000 \
    -warning 100000 \
    -antenna \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.tcm8k_fixed.rpt

puts "### T8K ### probe complete -- see $REPORT_DIR/$BASENAME.verifyGeometry.tcm8k_fixed.rpt"
exit
