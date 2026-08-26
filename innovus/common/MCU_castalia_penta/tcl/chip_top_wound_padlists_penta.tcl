# =============================================================================
# 2026-08-17: THE FORK IS NO LONGER PRE-D3. It now carries the five D3 JTAG pads
# and is 77 pads, not 72.
#
# WHY THE FORK EXISTED: at CP4b the penta WRAPPER was the pre-D3 revision and had
# no JTAG pad instances, so sourcing the shared 77-pad list FATAL'd (IMPTCM-162
# on PAD_TCK). Forking to a 72-pad list was correct THEN.
#
# WHY IT HAD TO CHANGE: in/MCU_castalia_penta.v was regenerated from the D3
# wrapper on 2026-08-16 (debug.enable became a shipped default, so the chip must
# expose a reachable TAP), and it now instantiates PAD_TCK/TMS/TDI/TDO/TRSTN.
# The pads therefore existed in the NETLIST while being absent from THIS LIST,
# so place_pad never placed them and they sat on top of already-placed pads.
# MEASURED, not inferred -- verifyGeometry on the cpr6 cut reported 42 OVERLAPs,
# every one of them a JTAG pad against a real pad:
#     PAD_TDO <-> PAD_VSSPST_1 , PAD_TMS <-> PAD_VSS_1 ,
#     PAD_TDI <-> PAD_P3_5/PAD_P3_4 , PAD_TCK <-> PAD_P2_4/PAD_P2_3
# (6 layers x 6 pairs + 6 cell-level markers). PAD_TRSTN was the only one that
# landed clear. A pad ring with pads stacked on pads is not a fixable-later
# detail; it is a broken ring.
#
# THE COST, and it is the one CP4b forked to avoid: place_pad CENTRES each
# side's contiguous block, so four new SOUTH pads and one new EAST pad
# RE-CENTRE those rows and MOVE EVERY ALREADY-PLACED PAD on them (-50 um on S,
# -12.5 um on E, ~45 pads). That is accepted deliberately here -- the penta cut
# is being re-implemented anyway (8 KiB TCM, new tile size), so there is no
# frozen placement left to preserve, and the alternative is a debug-ON chip
# whose TAP has no bonded pads. Placement order and pin numbering now match the
# shared list (BOTTOM 27-50, RIGHT 51-71) and the castalia-lqfp100 package model
# that bonds TCK/TMS/TDI/TDO at 47-50 and TRSTn at 51.
# =============================================================================
################################################################################
# chip_top_wound pad-ring side lists -- LQFP-100, CASTALIA-PENTA FORK.
#
# WHY THIS IS A FORK AND NOT THE SYMLINK (CP4b finding, 2026-08-13):
#   CP4a's R4 symlinked ../../MCU_castalia/tcl/chip_top_wound_padlists.tcl on
#   the Stage-J "sourced by name, not forked" rule. That rule holds only while
#   the two chips have the SAME PINOUT, and they no longer do:
#     * the shared file was edited on 2026-08-06 by the D3 debug work
#       (R-DD4(2)) to add FIVE JTAG pads -- PAD_TCK/TMS/TDI/TDO at the END of
#       BOTTOM and PAD_TRSTN at the HEAD of RIGHT, 72 pads -> 77;
#     * in/MCU_castalia_penta.v is deliberately based on the PRE-D3 wrapper
#       (CP4a R2) and instantiates NO JTAG pads, so the run FATALs on
#       `placeInstance PAD_TCK` (IMPTCM-162/-3, measured);
#     * place_side CENTRES each side's block, so 4 extra BOTTOM pads shift the
#       whole south row by -50 um and 1 extra RIGHT pad shifts the east row by
#       -12.5 um. Using the shared file would therefore ALSO have broken the
#       CP1 D9 invariance requirement against the MCU_castalia SIGNOFF DEF,
#       silently, on 45 pad instances.
#
# WHAT THIS FILE IS: the shared file with exactly those five entries removed --
# i.e. the 72-pad list the MCU_castalia signoff cut (2026-07-28/29) was built
# from. Verified: every pad placement here reproduces the signoff DEF
# (dbs/MCU_castalia.signoff.innovus.dat/MCU_castalia.def.gz) exactly; the
# in-flow CP4b TODO 5 assertion checks 13 of them across all four edges and
# the corners, and the CP4b post-run DEF diff checks all 72 + the 4 corners +
# the 2 ring cuts.
#
# NOTHING ELSE IS CHANGED. Do not "resync" this with the MCU_castalia copy: a
# penta chip that wants JTAG needs a D3-based wrapper first, and that is a
# CP6-class decision, not a padlist edit.
#
# --- original header, retained -------------------------------------------
# chip_top_wound pad-ring side lists - LQFP-100 (castalia-lqfp100 package
# model). PAD_P5_6/PAD_P5_7 are the PDDW16SDGZ_G pull-DOWN pads (DP-S3
# strap/PGOOD contract, BINDING: pin 69 = P5.7(GPIO47) = PGOOD, pin 68 =
# P5.6(GPIO46) = field/harvest strap - reserved, do not rebind).
# 72 pads: 48 GPIO + RESETN + POC + 3x{VDD,VSS,VDDPST,VSSPST} + AVDD/AVSS +
# ARSV0-7 (analog reserve band, north).
# RECONSTRUCTED 2026-07-27 from the as-built pad ring in
# dbs/chip_top_wound_quad.final.innovus.dat (DEF); extraction validated 4/4
# sides against chip_top_dp_padlists.tcl + the chip_top_dp.final DEF.
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
