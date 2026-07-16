# TEMP PROVISIONAL (CQ3a geometry run) -- NOT the real CQ pinout.
################################################################################
# chip_top_quad pad-ring side lists -- CQ3a geometry-run provisional.
#
# WHY THIS FILE EXISTS (read before touching):
#   The REAL Castalia-Quad pinout is tcl/chip_top_quad_padlists.tcl (CQ3b's
#   deliverable: QFN64, 64 pad instances -- 24 per-quadrant analog
#   AVDD/AVSS/WE/RE/RE2/CE_h, split IO VDDPST/VSSPST, split core VDD/VSS, POC,
#   resetn, 30 GPIO). That padlist references pad instances that only exist in
#   CQ3b's matching 64-pad in/chip_top_quad.v -- which is NOT yet staged.
#
#   CQ3a (this WP) validates the QUADRANT FLOORPLAN + POWER GEOMETRY (ring
#   closure on both analog-window edges, followpin phase on the MX/R180 tiles,
#   tile/SRAM/ROM PG hookup). That verification is INDEPENDENT of which specific
#   pad sits where -- the pads are perimeter LEF macros; the PG ring/stripe/
#   detour/followpin evidence does not depend on pad instance names. So the
#   geometry run uses the EXISTING C0 netlist prototype (in/chip_top_quad.v ==
#   C0 chip_top.v: 12 aio + resetn + 32 GPIO + the C0 supply set) with the
#   C0-COMPATIBLE side lists below.
#
#   INTEGRATION (CQ5): when CQ3b's 64-pad netlist lands, set
#     set PADLISTS chip_top_quad_padlists.tcl
#   at the top of chip_top_quad.innovus.tcl AND switch init_verilog to CQ3b's
#   64-pad in/chip_top_quad.v. Nothing else in the PG plan changes.
#
# Analog electrodes SPLIT top/bottom (6+6) to sit over the quadrant windows on
# both horizontal edges; the Option-A ring is continuous by abutment regardless
# of side order. All 56 chip_top_quad.v prototype pads placed exactly once.
# Order = placement order along the row (+x bottom/top, +y left/right).
################################################################################

# TOP edge: analog over the two top notches (aio 0-5) + resetn/prt1 + core VDD.
set TOP [list \
    PAD_avdd \
    PAD_aio_0 PAD_aio_1 PAD_aio_2 \
    PAD_vddio_0 PAD_resetn \
    PAD_prt1_0 PAD_prt1_1 PAD_prt1_2 PAD_prt1_3 PAD_prt1_4 PAD_prt1_5 PAD_prt1_6 PAD_prt1_7 \
    PAD_vdd_0 \
    PAD_aio_3 PAD_aio_4 PAD_aio_5 \
    PAD_vssio_0]

# BOTTOM edge: analog over the two bottom notches (aio 6-11) + prt2 + core VDD.
set BOTTOM [list \
    PAD_avss \
    PAD_aio_6 PAD_aio_7 PAD_aio_8 \
    PAD_vss_0 \
    PAD_prt2_0 PAD_prt2_1 PAD_prt2_2 PAD_prt2_3 PAD_prt2_4 PAD_prt2_5 PAD_prt2_6 PAD_prt2_7 \
    PAD_vdd_1 \
    PAD_aio_9 PAD_aio_10 PAD_aio_11]

# LEFT edge: prt3 (hart-0 flash-AF neighbourhood, CQ1 #5) + IO supply + POC.
set LEFT [list PAD_vss_1 \
    PAD_prt3_0 PAD_prt3_1 PAD_prt3_2 PAD_prt3_3 PAD_prt3_4 PAD_prt3_5 PAD_prt3_6 PAD_prt3_7 \
    PAD_vddio_1 PAD_poc]

# RIGHT edge: prt4 + IO ground return.
set RIGHT [list PAD_vssio_1 \
    PAD_prt4_0 PAD_prt4_1 PAD_prt4_2 PAD_prt4_3 PAD_prt4_4 PAD_prt4_5 PAD_prt4_6 PAD_prt4_7]
