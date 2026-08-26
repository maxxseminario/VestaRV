################################################################################
# chip_top pad-ring side lists — myshkin-qfn44 heritage ring (tphn pads).
# SHARED data file: sourced by the chip_top_argus flows
# (chip_top_argus.innovus.tcl / chip_top_argus_a7fp*.tcl line ~255); the
# retired Castalia C0 chip_top flow sourced the same lists.
# Lists are in place_side geometric order (+y for left/right, +x for
# bottom/top); pin numbers per pad are in the platform emission
# (platform/common/out/pnr/chip_top_padring.tcl, myshkin-qfn44 model).
#
# RECONSTRUCTED 2026-07-27 from the as-built ring in
# dbs/chip_top_argus.final.innovus.dat (chip_top.def.gz), after the original
# was lost in the non-quad Castalia cleanup. Extraction method validated
# exactly (4/4 sides) against chip_top_dp_padlists.tcl + the chip_top_dp.final
# DEF before use here.
################################################################################

set LEFT [list \
    PAD_vss_0 \
    PAD_prt3_0 \
    PAD_prt3_1 \
    PAD_prt3_2 \
    PAD_prt3_3 \
    PAD_prt3_4 \
    PAD_prt3_5 \
    PAD_prt3_6 \
    PAD_prt3_7 \
    PAD_vddio_1 \
    PAD_poc \
]

set BOTTOM [list \
    PAD_avss \
    PAD_aio_0 \
    PAD_aio_1 \
    PAD_aio_2 \
    PAD_aio_3 \
    PAD_aio_4 \
    PAD_aio_5 \
    PAD_aio_6 \
    PAD_aio_7 \
    PAD_aio_8 \
    PAD_aio_9 \
    PAD_aio_10 \
    PAD_aio_11 \
    PAD_avdd \
]

set RIGHT [list \
    PAD_vss_1 \
    PAD_prt4_0 \
    PAD_prt4_1 \
    PAD_prt4_2 \
    PAD_prt4_3 \
    PAD_prt4_4 \
    PAD_prt4_5 \
    PAD_prt4_6 \
    PAD_prt4_7 \
    PAD_vssio_1 \
    PAD_vdd_1 \
]

set TOP [list \
    PAD_vssio_0 \
    PAD_resetn \
    PAD_prt1_0 \
    PAD_prt1_1 \
    PAD_prt1_2 \
    PAD_prt1_3 \
    PAD_prt1_4 \
    PAD_prt1_5 \
    PAD_prt1_6 \
    PAD_prt1_7 \
    PAD_vdd_0 \
    PAD_prt2_0 \
    PAD_prt2_1 \
    PAD_prt2_2 \
    PAD_prt2_3 \
    PAD_prt2_4 \
    PAD_prt2_5 \
    PAD_prt2_6 \
    PAD_prt2_7 \
    PAD_vddio_0 \
]

