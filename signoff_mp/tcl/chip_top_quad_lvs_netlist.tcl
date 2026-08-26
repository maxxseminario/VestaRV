# CQ6: chip_top_quad LVS netlist WITH power/ground, from the CQ5 routed signoff
# DB. NEW quad-named copy of tcl/chip_lvs_netlist.tcl (C0) -- same recipe, only
# the DB path + topcell change. The CQ5 DB was already saved -tapeOut false so
# the restore does NOT FATAL on the 3 analog abstracts (no .mode patch needed).
#
# Physical cells KEPT (-phys): the tphn signal/supply/analog pad-ring instances
# (PDUW16SDGZ_G / PDB3A_G / PVDD*/PVSS*/PVDD2POC_G) -- subckt defs come from the
# tphn spice in lvs_include_chip. std-cell FILL family excluded (same list as
# C0). The tphn CORNER + IO FILLER (PCORNER_G/PFILLER*_G) are deviceless -- kept
# in source as empty stubs via pad_filler_stubs (C0 precedent).
set restore_db_file_check 0
setCheckMode -tapeOut false
restoreDesign /home/mseminario2/vestarv/innovus/common/chip_top_quad/dbs/chip_top_quad.signoff.innovus.dat chip_top_quad

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/chip_top_quad.lvs.v

exit
