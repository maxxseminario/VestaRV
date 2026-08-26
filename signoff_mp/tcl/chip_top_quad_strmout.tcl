# CQ6 signoff: streamOut a GDS from the CQ5 routed DB
# (dbs/chip_top_quad.signoff.innovus.dat). Modeled BYTE-FOR-BYTE on C0's
# chip_top.innovus.tcl streamOut (merge the hart_tile GDS + the 8lm tphn pad
# GDS so the chip GDS is self-contained pad geometry). CQ5 deliberately did NOT
# streamOut (NO GDS at CQ5 -- "CQ6 owns GDS"), so this is the CQ6 first step.
#
# The routed DB was saved with setCheckMode -tapeOut false, so the restore does
# NOT FATAL on the timing-less analog abstracts (CQ4/C0 finding). Absolute paths
# so it can run from any cwd (run from innovus/common so out/ lands there).
#
# usage: innovus -no_gui -batch -files tcl/chip_top_quad_strmout.tcl
set CO   /home/mseminario2/vestarv/innovus/common/chip_top_quad
set restore_db_file_check 0
setCheckMode -tapeOut false
restoreDesign $CO/dbs/chip_top_quad.signoff.innovus.dat chip_top_quad

streamOut \
    $CO/out/chip_top_quad.gds2 \
    -libName WorkLib \
    -structureName chip_top_quad \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -merge [list $CO/out/hart_tile.gds2 \
                 /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
    -mapFile $CO/../shared/innovus2gds.map
puts "### CQ6 STATUS ### : streamOut chip_top_quad.gds2 complete"
exit
