# Argus A6: regenerate the ARGUS hart_tile LVS netlist (WITH power/ground) from
# the M19c-rehardened Argus tile signoff DB, AND dump the VDD_SW M1 follow-pin
# piece centers as gds_add_labels-style virtual-connect texts. Standalone batch:
#   cd ~/vestarv/signoff_mp && innovus -no_gui -batch -files tcl/hart_tile_argus_lvs_netlist.tcl
#
# Same recipe / option rationale as tcl/hart_tile_lvs_netlist.tcl (the Castalia
# tile) -- see there. Deltas: the ARGUS tile DB + argus-namespaced outputs. The
# tile topcell is "hart_tile" (the Argus tile is the SAME hart_tile entity,
# separately hardened for the compact 405x685 Argus grid). Tile mode is
# UNPATCHED (no analog abstracts -> no -tapeOut fatal; the tile tcl does not set
# restore_db_file_check 0, so do NOT touch the tile mode -- C0 stale-tile lesson).

restoreDesign /home/mseminario2/vestarv/innovus/common/hart_tile_argus/dbs/hart_tile_argus.signoff.innovus.dat hart_tile

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/hart_tile_argus.lvs.v

# --- VDD_SW M1 piece-center dump (the C0 "VDD_SW-dump recipe") --------------
# VDD_SW is the switched rail: many M1 follow-pin islands joined only through
# the header switches. One "VDD_SW:" text (M1 text = GDS layer 131) per piece
# lets the deck's VIRTUAL_CONNECT -COLON YES unify them at LVS. Coords are
# TILE-LOCAL; the 18-tile chip label generator transforms them per placement.
set fp [open /home/mseminario2/vestarv/signoff_mp/pvs/hart_tile_argus.lvslabels w]
set netp [dbGet top.nets.name VDD_SW -p]
if {$netp == 0} { puts "### VDDSW ### FATAL: no VDD_SW net in tile"; exit 1 }
array set lyrcnt {}
set cnt 0
foreach sw [dbGet ${netp}.sWires] {
    set lyr [dbGet ${sw}.layer.name]
    if {[info exists lyrcnt($lyr)]} { incr lyrcnt($lyr) } else { set lyrcnt($lyr) 1 }
    if {$lyr ne "M1"} { continue }
    set box [join [dbGet ${sw}.box]]
    set x1 [lindex $box 0]; set y1 [lindex $box 1]
    set x2 [lindex $box 2]; set y2 [lindex $box 3]
    set cx [expr {($x1 + $x2) / 2.0}]
    set cy [expr {($y1 + $y2) / 2.0}]
    puts $fp [format "131 %.3f %.3f VDD_SW:" $cx $cy]
    incr cnt
}
close $fp
puts "### VDDSW ### M1 pieces dumped: $cnt"
puts "### VDDSW ### sWire layer histogram: [array get lyrcnt]"
puts "### VDDSW ### tile fPlan.box:  [dbGet top.fPlan.box]"
puts "### VDDSW ### tile fPlan.coreBox: [dbGet top.fPlan.coreBox]"

exit
