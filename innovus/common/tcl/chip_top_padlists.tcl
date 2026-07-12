################################################################################
# chip_top pad-ring side lists (Flavor A, Myshkin die-ring reference).
#
# DATA ONLY -- sourced by chip_top.innovus.tcl (placement) AND by
# check_padring_vs_castalia.tcl (the C0 diff-check against the generated
# platform/common/out/pnr/chip_top_padring.tcl). Keep it free of Innovus
# commands so plain tclsh can source it.
#
# These lists replicate the Myshkin tape-out DIE ring (55 die pads: analog
# bottom edge with 12 aio electrode pads, POC, duplicated core/IO supplies).
# The generated Castalia file describes the QFN-44 PACKAGE pin ring (43 pads)
# -- side assignments differ (the bond map absorbs the difference), which is
# why Flavor A keeps its own lists until the die-ring-vs-package-order
# question is settled (see check_padring_vs_castalia.tcl).
#
# Order within each list is placement order along the row (+x bottom/top,
# +y left/right).
################################################################################

set BOTTOM [list PAD_avss \
    PAD_aio_0 PAD_aio_1 PAD_aio_2 PAD_aio_3 PAD_aio_4 PAD_aio_5 \
    PAD_aio_6 PAD_aio_7 PAD_aio_8 PAD_aio_9 PAD_aio_10 PAD_aio_11 \
    PAD_avdd]

set TOP [list PAD_vssio_0 PAD_resetn \
    PAD_prt1_0 PAD_prt1_1 PAD_prt1_2 PAD_prt1_3 PAD_prt1_4 PAD_prt1_5 PAD_prt1_6 PAD_prt1_7 \
    PAD_vdd_0 \
    PAD_prt2_0 PAD_prt2_1 PAD_prt2_2 PAD_prt2_3 PAD_prt2_4 PAD_prt2_5 PAD_prt2_6 PAD_prt2_7 \
    PAD_vddio_0]

set LEFT [list PAD_vss_0 \
    PAD_prt3_0 PAD_prt3_1 PAD_prt3_2 PAD_prt3_3 PAD_prt3_4 PAD_prt3_5 PAD_prt3_6 PAD_prt3_7 \
    PAD_vddio_1 PAD_poc]

set RIGHT [list PAD_vss_1 \
    PAD_prt4_0 PAD_prt4_1 PAD_prt4_2 PAD_prt4_3 PAD_prt4_4 PAD_prt4_5 PAD_prt4_6 PAD_prt4_7 \
    PAD_vssio_1 PAD_vdd_1]
