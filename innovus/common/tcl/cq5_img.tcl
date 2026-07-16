# CQ5 routed-design image dump -- restores the ROUTED signoff DB and dumps a
# full-chip PNG/GIF (+ per-quadrant zooms) for orchestrator eyeball review.
# The signoff DB is saved with tapeOut check mode OFF (CQ5 continuation), so it
# restores cleanly. Run headless under xvfb-run:
#   source cdspaths.sh && xvfb-run -a innovus -overwrite -log log/cq5_img -files tcl/cq5_img.tcl
source tcl/constants.tcl
source $SCRIPT_DIR/procedures.tcl
restoreDesign $DATABASE_DIR/chip_top_quad.signoff.innovus.dat chip_top_quad

# full chip
fit
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.full.gif

# bottom-right flipped tile (hart3 R180) -- mirrored PG straps + routing
zoomBox 1900 -50 2800 1150
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.hart3_R180.gif

# top-left tile (hart0 R0) + top analog window
zoomBox -50 1550 800 2750
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.hart0_R0.gif

# center band (shared RAM row + ROM + arbiter/AFE fabric + closure rungs)
zoomBox -50 950 2750 1750
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.routed.center_band.gif

fit
redraw
exit
