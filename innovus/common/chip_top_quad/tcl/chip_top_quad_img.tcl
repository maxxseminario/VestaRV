# CQ3a layout image dump -- restores the floorplan+PG DB and dumps GIFs for
# orchestrator eyeball review. Run under xvfb-run (headless).
source ../shared/constants.tcl
source ../shared/procedures.tcl
restoreDesign $DATABASE_DIR/chip_top_quad.floorplan_pg.innovus.dat chip_top_quad

# full chip
fit
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.full.gif

# zoom: bottom-right flipped tile (hart3 R180) -- show the mirrored PG straps
zoomBox 1900 -50 2800 1150
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.hart3_R180.gif

# zoom: top-left tile (hart0 R0) + top analog window
zoomBox -50 1550 800 2750
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.hart0_R0.gif

# zoom: center band (shared RAM row + ROM + closure rungs)
zoomBox -50 950 2750 1750
redraw
dumpToGIF $OUTPUT_DIR/chip_top_quad.center_band.gif

exit
