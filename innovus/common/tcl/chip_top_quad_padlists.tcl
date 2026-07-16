################################################################################
# chip_top_quad pad-ring side lists -- Castalia-Quad (CQ) QFN64, Option A.
#
# CQ3b deliverable -- REPLACES the CQ3a "# TEMP PROVISIONAL" file of this name.
#
# DATA ONLY -- sourced by the CQ chip-top placement tcl (chip_top_quad.innovus
# .tcl, CQ4) AND by check_padring_vs_quad.py (the three-way doc<->padlists<->
# netlist consistency gate). Keep it free of Innovus commands so plain tclsh can
# source it.
#
# Full rationale + package pin numbers: ~/vesta_docs/castalia_quad/cq3b_pin_map.md.
# Netlist that instantiates these instances: in/chip_top_quad.v.
#
# Quadrant-symmetric 2-axis floorplan (hart0 top-left / hart1 top-right /
# hart2 bottom-left / hart3 bottom-right). Four 6-pad analog groups, one per
# quadrant, centered over the notch on the nearest horizontal die edge:
#   group = AVDD_h(PVDD2ANA) RE2_h RE_h WE_h CE_h AVSS_h(PVSS2ANA)   [read +x,
#   for a LEFT quadrant]; the RIGHT quadrant is the vertical-axis mirror.
# Electrode order: the sensitive high-Z sense pair (RE,RE2) sits at the AVDD/
# outer end, the aggressor CE + its AVSS return at the inner (central-digital)
# end, WE (low-Z virtual ground) shielding the sense pair from CE. AVSS/AVDD
# bracket every group as quiet guard rails. Mirror-CONSISTENT across BOTH axes
# (see the pin-map doc + ../analog/castalia_afe_impedance.md for the argument).
#
# Supplies placed symmetrically: 2x core VDD/VSS on the LEFT/RIGHT verticals
# (feed the core M7 ring directly), 2x IO VDDPST/VSSPST in the TOP/BOTTOM
# central digital stretches. resetn on LEFT (hart-0 boot proximity), POC on
# RIGHT. prt1[7:0] (P0 = hart-0 SPI-flash boot quartet + LFXT/HFXT/TRAP/BOOT)
# on the UPPER LEFT edge -- unregistered tile pins, kept short (M14 SDC budget).
#
# DROPPED (30 of 32 GPIO): prt3[0] = P2.0/GPIO16/T0CMP0 and prt3[4] =
# P2.4/GPIO20/T1CMP0 -- the shallowest alt-function loss (both are timer-compare
# OUTPUTS with 0 globally-unique functions, replicated across many AF-spread
# pins). No pad; their mcu0 port bits are tied/dangled in the netlist.
#
# Order within each list is placement order along the row:
#   +x for BOTTOM/TOP, +y for LEFT/RIGHT.  Corners are placed by the flow tcl,
#   not listed here (C0 precedent).
################################################################################

# ---- BOTTOM (South) edge, +x left->right : AFE2 | central-digital | AFE3 ----
set BOTTOM [list \
    PAD_avdd_2 PAD_re2_2 PAD_re_2 PAD_we_2 PAD_ce_2 PAD_avss_2 \
    PAD_vddpst_b PAD_prt4_6 PAD_prt4_7 PAD_vsspst_b \
    PAD_avss_3 PAD_ce_3 PAD_we_3 PAD_re_3 PAD_re2_3 PAD_avdd_3]

# ---- TOP (North) edge, +x left->right : AFE0 | central-digital | AFE1 -------
set TOP [list \
    PAD_avdd_0 PAD_re2_0 PAD_re_0 PAD_we_0 PAD_ce_0 PAD_avss_0 \
    PAD_vddpst_t PAD_prt4_4 PAD_prt4_5 PAD_vsspst_t \
    PAD_avss_1 PAD_ce_1 PAD_we_1 PAD_re_1 PAD_re2_1 PAD_avdd_1]

# ---- LEFT (West) edge, +y bottom->top --------------------------------------
# prt1[7:0] runs to the TOP of the edge (upper-left, hart-0 boot flash).
set LEFT [list \
    PAD_prt3_1 PAD_prt3_2 PAD_prt3_3 PAD_prt3_5 PAD_prt3_6 \
    PAD_vss_l PAD_vdd_l PAD_resetn \
    PAD_prt1_0 PAD_prt1_1 PAD_prt1_2 PAD_prt1_3 PAD_prt1_4 PAD_prt1_5 PAD_prt1_6 PAD_prt1_7]

# ---- RIGHT (East) edge, +y bottom->top -------------------------------------
set RIGHT [list \
    PAD_prt3_7 PAD_prt4_0 PAD_prt4_1 PAD_prt4_2 PAD_prt4_3 \
    PAD_vss_r PAD_vdd_r PAD_poc \
    PAD_prt2_0 PAD_prt2_1 PAD_prt2_2 PAD_prt2_3 PAD_prt2_4 PAD_prt2_5 PAD_prt2_6 PAD_prt2_7]
