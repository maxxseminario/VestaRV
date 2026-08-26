# CQ5 finalize: restore the routed signoff DB, DELETE the analog-window route
# blocks (the tile PG finger pins sit under them by construction -> they show as
# the ~244 "SHORT: Pin vs Routing Blockage" transient class; C0 deletes them),
# re-verify to PROVE the 244 clear, re-save the clean routed DB, and dump the
# full-chip PNG + per-quadrant zooms. Run headless under xvfb:
#   source cdspaths.sh && xvfb-run -a innovus -overwrite -log log/cq5_finalize -files tcl/cq5_finalize.tcl
source ../shared/constants.tcl
source ../shared/procedures.tcl
setCheckMode -tapeOut false
restoreDesign $DATABASE_DIR/chip_top_quad.signoff.innovus.dat chip_top_quad
puts "### CQ5FIN ### restore done"

# --- BEFORE: confirm the transient class is present in the as-saved DB ---
verifyGeometry -error 20000 -warning 20000 -report $REPORT_DIR/chip_top_quad.verifyGeometry.finalize_before.rpt

# Remove the analog-window (+seal) ROUTE blocks; the window HARD PLACE
# blockages survive (only route blks are deleted) so the notch stays cell-free.
deleteAllRouteBlks
# Re-establish the seal-band keep-outs (die -155..2845, seal 20um) so the routed
# DB keeps the reserved outer band; NOT the analog-window route blocks.
set SEAL_OFF 20.0
set DIE_LLX -155.0 ; set DIE_LLY -155.0 ; set DIE_URX 2845.0 ; set DIE_URY 2845.0
foreach f [list \
    [list $DIE_LLX $DIE_LLY $DIE_URX [expr {$DIE_LLY + $SEAL_OFF}]] \
    [list $DIE_LLX [expr {$DIE_URY - $SEAL_OFF}] $DIE_URX $DIE_URY] \
    [list $DIE_LLX $DIE_LLY [expr {$DIE_LLX + $SEAL_OFF}] $DIE_URY] \
    [list [expr {$DIE_URX - $SEAL_OFF}] $DIE_LLY $DIE_URX $DIE_URY]] {
    lassign $f x0 y0 x1 y1
    catch {createRouteBlk -box $x0 $y0 $x1 $y1 -layer {1 2 3 4 5 6 7 8} -name SEALRB_[incr sc]}
}
puts "### CQ5FIN ### window route blocks deleted, seal restored"

# --- AFTER: the 244 transient shorts must be gone ---
verifyGeometry -error 20000 -warning 20000 -report $REPORT_DIR/chip_top_quad.verifyGeometry.finalize_after.rpt
verifyConnectivity -nets {VDD VSS} -type special -error 200000 \
    -report $REPORT_DIR/chip_top_quad.verifyConnectivity.finalize.rpt
verifyConnectivity -type regular -error 200000 \
    -report $REPORT_DIR/chip_top_quad.verifyConnectivity.regular.finalize.rpt

# Re-save the clean routed DB (tapeOut check already off).
saveDesign $DATABASE_DIR/chip_top_quad.signoff.innovus -def -netlist -rc -tcon
puts "### CQ5FIN ### clean routed DB re-saved"

# --- Full-chip PNG + per-quadrant zooms (GUI under xvfb) ---
if {![catch {fit}]} {
    catch { redraw ; dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.full.gif }
    catch { zoomBox 1900 -50 2800 1150 ; redraw ; dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.hart3_R180.gif }
    catch { zoomBox -50 1550 800 2750 ; redraw ; dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.hart0_R0.gif }
    catch { zoomBox -50 950 2750 1750 ; redraw ; dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.center_band.gif }
    catch { fit ; redraw }
    puts "### CQ5FIN ### routed GIFs dumped"
}
puts "### CQ5FIN ### done"
exit
