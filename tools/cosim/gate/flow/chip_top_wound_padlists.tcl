################################################################################
# chip_top_wound pad-ring side lists — LQFP-100 (castalia-lqfp100 package
# model). SHARED by the chip_top_wound_quad flow (WQ-DELTA 3: sourced, not
# forked) — the wound LQFP-100 emission is the pinout authority for both wound
# chips. PAD_P5_6/PAD_P5_7 are the PDDW16SDGZ_G pull-DOWN pads (DP-S3
# strap/PGOOD contract, BINDING: pin 69 = P5.7(GPIO47) = PGOOD, pin 68 =
# P5.6(GPIO46) = field/harvest strap — reserved, do not rebind).
# 72 pads: 48 GPIO + RESETN + POC + 3x{VDD,VSS,VDDPST,VSSPST} + AVDD/AVSS +
# ARSV0-7 (analog reserve band, north). Same side lists as chip_top_dp
# (castalia_dp.json emission); the wound deltas (OW DQ on P4.7 AF2, EVFAB0)
# are AF-plane changes only and do not touch pad instances.
#
# RECONSTRUCTED 2026-07-27 from the as-built pad ring in
# dbs/chip_top_wound_quad.final.innovus.dat (DEF), after the original file was
# lost in the non-quad-flow cleanup. Extraction method validated exactly
# (4/4 sides) against chip_top_dp_padlists.tcl + the chip_top_dp.final DEF;
# the wound_quad ring is pad-for-pad identical to the dp lists.
#
# D3 (2026-08-06, R-DD4(2)): FIVE JTAG pads added -- 47=TCK 48=TMS 49=TDI
# 50=TDO at the END of BOTTOM (the S edge runs pins 26-50 left to right, and
# the list stopped at 46) and 51=TRSTn at the HEAD of RIGHT (the E edge runs
# 51-75 bottom to top, so 51 precedes 52). All five were declared NC balls
# with no pad instance. Cell types live in in/MCU_castalia.v, not here:
# TCK/TRSTn are PDDW16SDGZ_G, TMS/TDI/TDO are PDUW16SDGZ_G. 72 pads -> 77.
# NOTHING is added to TOP -- the north edge is the PRCUT-isolated analog band
# and has no digital IO supply at all.
# place_side/place_pad are unchanged and need no edit: they consume these
# lists and CENTRE each side's block, so the S and E rows re-centre by
# themselves (-50 um / -12.5 um) at the next cut.
################################################################################

set LEFT [list \
    PAD_P1_7 \
    PAD_P1_6 \
    PAD_P1_5 \
    PAD_P1_4 \
    PAD_P1_3 \
    PAD_P1_2 \
    PAD_P1_1 \
    PAD_P1_0 \
    PAD_VSSPST_0 \
    PAD_VDDPST_0 \
    PAD_P0_7 \
    PAD_P0_6 \
    PAD_P0_5 \
    PAD_P0_4 \
    PAD_P0_3 \
    PAD_P0_2 \
    PAD_P0_1 \
    PAD_P0_0 \
    PAD_VSS_0 \
    PAD_VDD_0 \
    PAD_POC \
    PAD_RESETN \
]
# pins: 22 21 20 19 18 17 16 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1

set BOTTOM [list \
    PAD_P2_0 \
    PAD_P2_1 \
    PAD_P2_2 \
    PAD_P2_3 \
    PAD_P2_4 \
    PAD_P2_5 \
    PAD_P2_6 \
    PAD_P2_7 \
    PAD_VDD_1 \
    PAD_VSS_1 \
    PAD_P3_0 \
    PAD_P3_1 \
    PAD_P3_2 \
    PAD_P3_3 \
    PAD_P3_4 \
    PAD_P3_5 \
    PAD_P3_6 \
    PAD_P3_7 \
    PAD_VDDPST_1 \
    PAD_VSSPST_1 \
    PAD_TCK \
    PAD_TMS \
    PAD_TDI \
    PAD_TDO \
]
# pins: 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50

set RIGHT [list \
    PAD_TRSTN \
    PAD_P4_0 \
    PAD_P4_1 \
    PAD_P4_2 \
    PAD_P4_3 \
    PAD_P4_4 \
    PAD_P4_5 \
    PAD_P4_6 \
    PAD_P4_7 \
    PAD_VDD_2 \
    PAD_VSS_2 \
    PAD_P5_0 \
    PAD_P5_1 \
    PAD_P5_2 \
    PAD_P5_3 \
    PAD_P5_4 \
    PAD_P5_5 \
    PAD_P5_6 \
    PAD_P5_7 \
    PAD_VDDPST_2 \
    PAD_VSSPST_2 \
]
# pins: 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71

set TOP [list \
    PAD_ARSV7 \
    PAD_ARSV6 \
    PAD_ARSV5 \
    PAD_ARSV4 \
    PAD_ARSV3 \
    PAD_ARSV2 \
    PAD_ARSV1 \
    PAD_ARSV0 \
    PAD_AVSS \
    PAD_AVDD \
]
# pins: 85 84 83 82 81 80 79 78 77 76
