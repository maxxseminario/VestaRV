# VestaRV: chip_top_wound pad-ring side lists for the castalia-lqfp100 package
# model. The chip_top_wound_quad flow sources this file rather than forking it,
# so the wound LQFP-100 emission is the pinout authority for both wound chips.
# 77 pads: 48 GPIO, RESETN, POC, 3x{VDD,VSS,VDDPST,VSSPST}, AVDD/AVSS, ARSV0-7
# in the north analog reserve band, and five JTAG pads. Same side lists as
# chip_top_dp: the wound deltas are AF-plane changes and touch no pad instance.
#
# Binding contracts a reader must not undo.
#   PAD_P5_6 and PAD_P5_7 are PDDW16SDGZ_G pull-down pads. Pin 69 = P5.7(GPIO47)
#     = PGOOD, pin 68 = P5.6(GPIO46) = field/harvest strap. Reserved.
#   JTAG: 47=TCK 48=TMS 49=TDI 50=TDO end BOTTOM, which runs pins 26-50 left to
#     right; 51=TRSTn heads RIGHT, which runs 51-75 bottom to top. Cell types are
#     in in/MCU_castalia.v, not here: TCK and TRSTn are PDDW16SDGZ_G, TMS, TDI
#     and TDO are PDUW16SDGZ_G.
#   Nothing is added to TOP. The north edge is the PRCUT-isolated analog band and
#     has no digital IO supply.
# place_side and place_pad need no edit when a side grows: they centre each
# side's block, so the rows re-centre by themselves at the next cut.

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
