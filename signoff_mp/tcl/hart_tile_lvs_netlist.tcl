# PG3: regenerate the hart_tile LVS netlist (WITH power/ground) from the
# signoff DB. Standalone batch run:
#   cd ~/vestarv/signoff_mp && innovus -no_gui -batch -files tcl/hart_tile_lvs_netlist.tcl
#
# The flow's saveNetlist writes xsim.v only (no PG pins -- saveNetlist
# default). LVS needs VDD / VSS / VDD_SW / VDDG / VNW / VPW visible, so:
#   -includePowerGround  : emit PG nets + pin connections
#   -phys                : include physical-only insts (HEADBUF switches,
#                          FILLBIAS well taps, GPGBUF repeaters, well straps)
#                          -- these ARE the power-gating structure under test
#   -excludeCellInst     : plain tapless FILL* fillers (no devices worth
#                          netlisting; Myshkin tapeout precedent) PLUS
#                          FILLBIASA10TH: its CDL subckt is EMPTY (pure well
#                          straps, zero devices), so 7072 source instances can
#                          never match anything -- Pegasus reports every one
#                          as an unmatched instance. Their well-tie function
#                          is checked geometrically (softchk/LUP), not by LVS.
#                          The ANTENNA diodes are KEPT (real devices).
#   -excludeLeafCell     : leaf .SUBCKT definitions come from the kit CDLs at
#                          LVS time, not from verilog stubs
# -flat is NOT used: the tile is already a single level below leaf cells, and
# flat explodes the ram0 macro reference we want boxed.

restoreDesign /home/mseminario2/vestarv/innovus_mp/dbs/hart_tile.signoff.innovus.dat hart_tile

saveNetlist \
    -excludeLeafCell \
    -includePowerGround \
    -phys \
    -excludeCellInst "FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH FILLBIASA10TH" \
    /home/mseminario2/vestarv/signoff_mp/pvs/hart_tile.lvs.v

exit
