################################################################################
#             CASTALIA-PENTA CHIP FLOW -- CP4b, FLOORPLAN COMPLETE
#
# CP4b (2026-08-13) filled in all five `CP4b TODO` items the CP4a scaffold left
# open. Summary of what CP4b added, in file order:
#   T1/T2  orchestrator TCM placeInstance (2355.3 , 1153.8) R0 + halo 4 + cutRow
#          + orchgap0 east sliver keep-out, and a soft createRegion on
#          mcu0/hart0 over the flank [2188.8,1051.2]-[2679.3,1638.9]; every
#          coordinate 0.9 um-snapped AND asserted to be on that grid.
#   T5     invariance assertion against the MCU_castalia SIGNOFF DEF -- 30
#          reference placements (4 tiles, 5 SRAMs, ROM, analog row, pad
#          sentinels) checked from the DB before the PG build, FATAL on any move.
#   T4     PG coverage assertions for the flank + the new macro, plus a
#          switched-rail/PD negative check (must be 0 -- CP1 D2 always-on).
#   T3     clk_cpu0 skew-group existence gate + explicit target_skew after
#          create_ccopt_clock_tree_spec.
#   T2b    post-place hart0 containment census (soft region -> measure it).
#
# This file is a VERBATIM COPY of ../../MCU_castalia/tcl/MCU_castalia.innovus.tcl
# (the signed-off 4-hart tape-out cut) with FOUR mechanical retargets and ONE
# open floorplan task. The reference block is untouched and stays the reference.
#
# THE FOUR RETARGETS ALREADY APPLIED (CP4a):
#   R1  set DESIGN_NAME / set BASENAME -> MCU_castalia_penta
#   R2  init_verilog  -> in/MCU_castalia_penta.v  +  in/MCU_PENTA_hier.pnr.v
#       (the penta chip wrapper -- see its own banner for why it is based on
#        MCU_castalia.v.pre_d3, not the current D3-JTAG one -- and the penta
#        P&R netlist produced by ../prep_top_netlist_penta.sh)
#   R3  init_mmmc_file -> tcl/viewdefinition_MCU_castalia_penta.tcl
#       (identical library sets; only the SDC file name differs. The
#        orchestrator needs NO new library entry: it is SOFT std cells + one
#        sram1p16k_hvt_pg, both already in the kit. Only the four HARDENED
#        tiles need the hart_tile ETM.)
#   R4  tcl/chip_top_wound_padlists.tcl is a SYMLINK to the MCU_castalia copy
#       (the "sourced by name, not forked" Stage-J decision -- the LQFP-100
#        pinout is the same chip; edit only the MCU_castalia copy).
#
# THE FIVE ITEMS CP4a LEFT OPEN -- ALL CLOSED BY CP4b, kept here verbatim as
# the specification each implementation site is measured against. Where the
# text below says "is CP4b's job", read "was, and the site that closed it is
# flagged `CP4b TODO <n>` in place". The orchestrator is ~64.5 k um^2 of std
# cell (CP4a genus census; the "~72 k" below was the CP1 D9 estimate) plus ONE
# 319.65 x 383.085 um sram1p16k_hvt_pg TCM.
#
#   CP4b TODO 1  Place mcu0/hart0/tile/ram0 (the orchestrator TCM macro) in the
#                RIGHT BAND FLANK, the CP1 D9 frozen target:
#                   x in [~2188, 2689], y in [1051, 1639]
#                   macro 319.65 x 383.085, addHaloToBlock 4 4 4 4
#                   every coordinate snapped to the 0.9 um VIA7 phase grid
#                   (use the wq_snap09_up / wq_snap09_dn helpers already
#                   defined above -- A6 manufactured 75,768 VIA7 shorts by
#                   shifting a row 0.5 um, a non-multiple)
#                followed by cutRow (+ a gap keep-out if it ends up adjacent to
#                anything), exactly as the shared-RAM row does.
#   CP4b TODO 2  Constrain hart0's std cells to the same flank so the placer
#                cannot smear the orchestrator across the whole band
#                (createRegion / createFence on mcu0/hart0, guideline region
#                over the free rectangle beside the TCM: ~0.16 mm^2 of logic
#                area is available there and the orchestrator wants ~0.12-0.13).
#   CP4b TODO 3  CTS: the orchestrator's gated core clock is a REAL chip-level
#                clock in this cut (clk_cpu0, on mcu0/hart0/tile/core/clk_cpu --
#                see ../gen_MCU_castalia_penta_sdc.sh, which FATALs if it is
#                missing). Give it a skew group / CTS spec like the other
#                centre-band clocks. It does NOT exist for harts 1-4: those
#                pins are inside the hardened macro, behind the ETM.
#   CP4b TODO 4  PG: the orchestrator is ALWAYS-ON (CP1 D2) -- plain VDD/VSS,
#                NO power switches, NO isolation, NO PD_* domain. It must NOT
#                be wired into any switched rail. Check the band's follow-pin /
#                stripe coverage reaches the new flank cells and that the new
#                macro's rails land on the 0.9 um phase grid.
#   CP4b TODO 5  Re-verify: the SRAM row, ROM, analog row, four corner tiles,
#                notches and padring must come out BIT-IDENTICAL in placement
#                to the MCU_castalia cut. CP1 D9: only the centre band changes.
#
# The die (3000x3000), the ring, the four corner tile placements and the whole
# PG recipe below are unchanged from the reference cut and must stay so.
################################################################################
################################################################################
# Innovus script -- MCU_castalia: the CONNECTED 3x3mm WOUND-PATCH SoC on
# the QUADRANT-SYMMETRIC Castalia-Quad floorplan, in the LQFP-100 pad ring.
#
# CONSTRUCTION RULE (read this before editing anything below):
#   GEOMETRY / FLOORPLAN / PG RECIPE  <=  tcl/chip_top_quad.innovus.tcl  (CQ3a+CQ5)
#   RING / NETLIST / NAMES / GUARDS   <=  tcl/chip_top_wound.innovus.tcl (Stage I)
# Neither source file was modified. Every deliberate delta is flagged in place
# with "WQ-DELTA <n>" and enumerated in the block at the bottom of this header.
#
# WHAT THIS IS: the wound SoC (QSPI / I3C / NFC / OneWire / I2C-target / TRNG /
# EVFAB / 4-ch DMA / PWRCTRL harvested-boot) re-cut on the proven symmetric
# quad die instead of the Stage-I rectangular-in-square die. FLAT chip run:
# MCU_castalia instantiates the tphn pads and `MCU mcu0`, and the whole
# MCU_WOUND hierarchy is placed and routed IN this design (the four hart tiles
# stay hardened LEF macros + per-corner ETMs). There is NO block P&R in this
# path -- the wound control plane places directly into the quad CENTER BAND.
#
# FRAME: the QUAD frame verbatim -- DESIGN 2690 x 2690, symmetric die
# (-155,-155)-(2845,2845) = exactly 3000 x 3000, interior span 2690, margins 0.
# NOT the Stage-I wound chip's asymmetric (-155.5,-650)-(2844.5,2350) frame:
# that one exists only because the MCU_WOUND *block* cut is 2689 x 1700 and had
# to be centred in the square interior. Here the assembly IS the interior.
#
# FLOORPLAN FIT: the wound control plane is ~61.6k non-tile instances /
# ~234.8k um2 of std cell (2.4x / 2.1x the DP block -- nfc0 alone is ~87.5k
# um2). Placeable area on this floorplan = the center band (2690 x 588 minus
# the SRAM row / ROM / analog macros, ~0.95 mm2) PLUS both tile-row channels
# (x in [680,2010] x 1050, twice = 2.79 mm2) = ~3.7 mm2 -> ~6% utilisation.
# Roomy; congestion, not area, is the thing to watch on the first cut.
#
# PREREQUISITES (all present on disk as of 2026-07-27 except this run's own
# products):
#   1. genus/out/MCU_WOUND_hier.genus.{v,sdc}      (Jul 26 17:57)
#   2. ./prep_top_netlist_wound.sh -> in/MCU_WOUND_hier.pnr.v (Jul 26 19:09)
#      -- consumed UNCHANGED; this chip does not need its own block prep.
#      ./prep_top_netlist_MCU_castalia.sh does the POST-run xsim strip.
#   3. ./gen_MCU_castalia_sdc.sh -> in/MCU_castalia.sdc
#   4. ../hart_tile/out/hart_tile.{lef,gds2,etm_ss.lib,etm_ff.lib}  (Jul 21/22 M19c cut)
#
# NAME-COLLISION: mcu0's cell is named MCU == the Myshkin tape-out cell. That is
# handled ONLY at signoff strmin (signoff_mp/strmin_gds.sh, topcell != MCU
# branch: it pins the internal MCU cell and the P*_G tphn pad family) -- NEVER
# stream this chip with a raw strmin.
#
# --------------------------- WQ-DELTA LIST ----------------------------------
#  1. Header / provenance / prerequisites (this block).
#  2. DESIGN_NAME + BASENAME = MCU_castalia; init_verilog =
#     in/MCU_castalia.v + in/MCU_WOUND_hier.pnr.v; init_mmmc_file =
#     tcl/viewdefinition_MCU_castalia.tcl.
#  3. PADLISTS: the EXISTING tcl/chip_top_wound_padlists.tcl is SOURCED, not
#     forked -- the LQFP-100 pinout is identical (same 72 pads, same order,
#     same PDDW16SDGZ_G on PAD_P5_6/PAD_P5_7). chip-top-flow rule: share the
#     padlist unless the pinout differs.
#  4. irq_gf3 added to the center-band analog row at (1070,1070) N, continuing
#     the 50 um pitch (the wound/DP netlists have 4 GlitchFilters; the C0-era
#     MCU_MP netlist the quad flow was written against had 3).
#  5. cq8a fix (a): vertical M7 stripe start_offset shifted +9.0 um.
#  6. cq8a fix (b): the two under-window M8 closure-rail spans and the
#     [STRIPE_Y0,STRIPE_Y1] mesh band snapped to the 0.9 um VIA7 array pitch.
#  7. cq8a fix (c): irq_gf halo 4 -> 20 um on ALL FOUR glitch filters.
#  8. cq8a note (d): the M3.S.2/M5.S.2 ECO coordinates recorded, NOT re-applied.
#  14. PRCUT_G ring-break bracket at x=1195/1470 isolating the north analog
#      band (Stage J LVS forensics: PDB3A_G guard strap = real metal1 VDD-VSS
#      short at the ARSV0/AVSS abutment; see the WQ-DELTA 14 block).
#  15. PAD_VSS_1 strap-to-stripe M7 weld, RE-DERIVED 2026-08-17: the original
#      hard-coded rect was invalidated by three floorplan moves at once and
#      shipped as a floating shape (2 ANTENNA + 2 IMPVFC-94 dangling wires in
#      the cpr6 cut). It is now measured from the DB at run time and gated on
#      an opposite-net clearance check; see the WQ-DELTA 15 block.
#  9. TRNG0 ring-oscillator preserve gate (dbSet dontTouch) before placement --
#     from the wound flow, with `mcu0/u_ro/*` added as the FIRST pattern (the
#     hier netlist puts TrngRoEnsemble u_ro at MCU level, a SIBLING of trng0,
#     not inside it -- the wound chip flow's own open risk).
# 10. PG-fabric baseline + global count guards before EVERY saveDesign
#     (CLAUDE.md bare-`editDelete` class). The quad flow writes three DBs, so
#     the wound flow's two-guard pattern is generalised into a proc.
# 11. Explicit ${BASENAME}_post{CTS,Route}_full.power pair (dashboard).
# 12. streamOut added (the quad flow deliberately had none -- CQ6 owned GDS).
#     Merge list = ../hart_tile/out/hart_tile.gds2 + the tphn 8lm pad GDS ONLY. NEVER add a
#     block/assembly GDS: this is a FLAT run, the MCU geometry is native to the
#     chip struct, and merging one injects a duplicate `MCU` struct plus a
#     second differently-seeded MCU_VIA* family = the PG4 struct-hijack class.
# 13. timer ClockMuxGlitchFree gating-check disables annotated (see the site).
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

# WQ-DELTA 2
#
# CPR6 (2026-08-15): DESIGN_NAME is the CELL and must NOT move -- it is the GDS
# struct name, the LVS topcell, the strmin cellMap key and what the chip wrapper
# instantiates. BASENAME is only the FILE stem, so it carries the cut tag: this
# run writes dbs/MCU_castalia_penta.cpr6.*.innovus{,.dat}, out/
# MCU_castalia_penta.cpr6.{gds2,sdf,xsim.v} and rpt/MCU_castalia_penta.cpr6.*,
# leaving every CP4b/CP5 artifact on disk untouched as the reference cut. Do
# NOT "tidy" this back to one name without first moving the CP-era products --
# the one-cut collateral rule (a netlist, its SDF, its GDS and its LVS labels
# must all come from ONE cut) is enforced by the file names here.
set DESIGN_NAME MCU_castalia_penta
# CPR8 (2026-08-25): the ANALOG M7/M8 PG KEEPOUT cut -- WQ-DELTA 16 below, and
# NOTHING ELSE.  Same in/ netlist, same SDC, same hardened tile, same ROM as
# cpr6, so the only variable between cpr6 and cpr8 is the mesh plan and the
# VDD-VSS short is attributable to it alone.  The cpr6 products are left in
# out/ and dbs/ untouched as the A/B baseline.
set BASENAME    MCU_castalia_penta.cpr8

# WQ-DELTA 3: SHARED padlist file (not a fork). The wound LQFP-100 emission is
# the pinout authority for both wound chips; PAD_P5_6/PAD_P5_7 are the
# PDDW16SDGZ_G pull-DOWN pads (DP-S3 strap/PGOOD contract, BINDING).
#   CP4b OVERRIDE of R4: the shared file gained five D3 JTAG pads on 2026-08-06
#   (PAD_TCK/TMS/TDI/TDO + PAD_TRSTN). The penta wrapper is PRE-D3 and has no
#   JTAG pad instances, so the shared list FATALs (IMPTCM-162 on PAD_TCK) AND
#   would re-centre the south/east rows by -50/-12.5 um, moving 45 pads off the
#   MCU_castalia signoff placement. Forked to the 72-pad pre-D3 list; see that
#   file's header. The symlink to the shared file is retired in this block.
set PADLISTS chip_top_wound_padlists_penta.tcl

# Full square interior (the quadrant assembly fills the whole ring interior)
set DESIGN_WIDTH  2690
set DESIGN_HEIGHT 2690

set POWER_RING_PATH_WIDTH	10.0
set POWER_RING_PATH_SPACING	4.0
set POWER_STRIPE_PATH_WIDTH		5.0
set POWER_STRIPE_PATH_SPACING	4.0
set POWER_STRIPE_SET_TO_SET		[expr {$STD_CELL_HEIGHT * 25}]

set CORE_SPACING	1
set CORE_WIDTH		[expr {$DESIGN_WIDTH - ($CORE_SPACING * 2)}]
set CORE_HEIGHT		[expr {$DESIGN_HEIGHT - ($CORE_SPACING * 2)}]

# ---- Chip frame: fixed 3x3mm ring, 2690x2690 interior; assembly fills it ----
set PAD_RING  135.0   ;# tphn pad depth
set SEAL_OFF   20.0   ;# die edge -> pad outer edge (seal-ring band, M15)
set PADW       25.0   ;# signal/supply pad width along the row
set RING_BAND [expr {$PAD_RING + $SEAL_OFF}]              ;# 155
set INT_SPAN  2690.0                                      ;# ring interior (3000 - 2*155)
# margin 0: assembly == interior (square-in-square, Argus-style). With
# DESIGN == INT_SPAN the per-axis centering offsets collapse to 0, so the
# rectangular-in-square per-edge math of the Stage-I wound chip degenerates to
# the single PAD_NEAR/PAD_FAR pair used here.
set MARGIN_X  [expr {($INT_SPAN - $DESIGN_WIDTH)  / 2.0}] ;# 0
set MARGIN_Y  [expr {($INT_SPAN - $DESIGN_HEIGHT) / 2.0}] ;# 0
set IN_LLX [expr {-$MARGIN_X}]                            ;# 0
set IN_LLY [expr {-$MARGIN_Y}]                            ;# 0
set IN_URX [expr {$DESIGN_WIDTH  + $MARGIN_X}]            ;# 2690
set IN_URY [expr {$DESIGN_HEIGHT + $MARGIN_Y}]            ;# 2690
# die box = interior grown by the ring band -> exactly 3000x3000, symmetric:
set DIE_LLX [expr {$IN_LLX - $RING_BAND}]                 ;# -155
set DIE_LLY [expr {$IN_LLY - $RING_BAND}]                 ;# -155
set DIE_URX [expr {$IN_URX + $RING_BAND}]                 ;# 2845
set DIE_URY [expr {$IN_URY + $RING_BAND}]                 ;# 2845
# pad-row placement lines (bbox LL point per edge); square -> per-axis symmetric:
set PAD_NEAR_X [expr {$IN_LLX - $PAD_RING}]               ;# -135
set PAD_FAR_X  $IN_URX                                    ;# 2690
set PAD_NEAR_Y [expr {$IN_LLY - $PAD_RING}]               ;# -135
set PAD_FAR_Y  $IN_URY                                    ;# 2690

# ---- 0.9 um VIA7 stacked-via array pitch snap helpers (A6 VIA-PHASE-RULE) ---
# Every deliberate PG-geometry offset in this script is a multiple of 0.9 um,
# and every PG band edge is snapped INBOARD onto that grid, so the assembly PG
# via arrays and the tiles' own arrays stay in phase (A6 manufactured
# VIA7.S.1/S.2 x 75,768 by shifting a tile row 0.5 um -- a non-multiple).
set VIA7_PITCH 0.9
proc wq_snap09_up {v} { global VIA7_PITCH ; return [expr {ceil($v / $VIA7_PITCH) * $VIA7_PITCH}] }
proc wq_snap09_dn {v} { global VIA7_PITCH ; return [expr {floor($v / $VIA7_PITCH) * $VIA7_PITCH}] }

tic

################################################################################
# Design import: chip wrapper (pads + mcu0) FIRST, then the MCU_WOUND hier
# netlist it instantiates (WQ-DELTA 2).
################################################################################
set init_verilog             "$INPUT_DIR/MCU_castalia_penta.v in/MCU_PENTA_hier.pnr.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_MCU_castalia_penta.tcl"

# tphn pad LEF (M15): 8lm variant matches the M1-M8 tech LEF (9lm adds M9/VIA8
# -> unknown-layer spam on streamOut); tpfn is the WRONG family.
set IO_PAD_LEF "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tphn65gpgv2od3_sl_210a/mt_2/8lm/lef/tphn65gpgv2od3_sl_8lm.lef"

set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					$IP_DIR/rom_hvt_pg/rom_hvt_pg.lef \
					$IP_DIR/sram1p16k_hvt_pg/sram1p16k_hvt_pg.vclef \
					$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg.vclef \
					$IC_DIR/abstracts/myshkin_abs/GlitchFilter/GlitchFilter.lef \
					$IC_DIR/abstracts/myshkin_abs/PowerOnResetCheng/PowerOnResetCheng.lef \
					$IC_DIR/abstracts/myshkin_abs/OscillatorCurrentStarved/OscillatorCurrentStarved.lef \
					../hart_tile/out/hart_tile.lef \
					$IO_PAD_LEF"

set init_design_uniquify 1
init_design

# Tile timing enters via the ETM .lib (viewdefinition_MCU_castalia.tcl:
# ../hart_tile/out/hart_tile.etm_{ss,ff}.lib) -- the tile is a timed macro exactly like the
# SRAMs/ROM. The pad cells + the 3 analog abstracts enter LEF-only
# (timing-less; IMPVL-366 rule -- no dummy libs).

setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

setFillerMode \
    -corePrefix FILLER \
    -core {FILLTIE128A10TH FILLTIE64A10TH FILLTIE32A10TH FILLTIE16A10TH FILLTIE8A10TH FILLTIE4A10TH FILLTIE2A10TH FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

clearGlobalNets
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {} -autoTie -verbose
# THE 8 KiB TCM'S SPLIT RAILS, AT CHIP LEVEL (2026-08-17). sram1p8k_hvt_pg
# exposes VDDPE / VDDCE / VSSE where sram1p16k_hvt_pg exposed plain VDD / VSS.
# The tile flow was updated for this; THIS FILE WAS NOT, and the omission did
# not fail quietly -- it took the whole power network down:
#   Warning: pg term VDDPE of inst mcu0/hart0/tile/ram0 is not connect to
#            global special net.              (also VDDCE, VSSE)
#   **ERROR: (IMPSR-2403): All of the PG terms are not connected to PG nets.
# ALL THREE sroute PASSES ABORTED on that error, so the chip got no macro
# straps and no pad straps -- rpt/*.pgcheck.rpt reads VDD sWires=0 VSS sWires=0
# on all four hardened tiles. A chip whose PG was never routed.
#
# WHY IT IS VISIBLE HERE AT ALL: the four corner tiles are hardened macros and
# their TCMs are sealed inside the LEF abstract, but hart0 is the SOFT
# orchestrator, so ITS TCM is a real instance at chip level -- mcu0/hart0/tile/
# ram0 -- and it is the one instance whose split rails this file must bind.
#
# It also flattered the DRC number, which is the treacherous part: with no tile
# or pad straps there is far less metal in the design to violate anything, so
# the run reported FEWER violations while being profoundly more broken. Any
# DRC comparison across this fix must be re-measured, not carried over.
globalNetConnect VDD -type pgpin -pin VDDPE -inst * -module {} -autoTie -verbose
globalNetConnect VDD -type pgpin -pin VDDCE -inst * -module {} -autoTie -verbose
globalNetConnect VSS -type pgpin -pin VSSE  -inst * -module {} -autoTie -verbose

################################################################################
# Floorplan: die (-155,-155)-(2845,2845) = 3000x3000, core box (1,1)-(2689,2689).
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -b $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY \
       $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY \
       $CORE_SPACING $CORE_SPACING [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]

################################################################################
# Pad ring (square frame; one PAD_NEAR/PAD_FAR per axis via the square symmetry)
################################################################################
proc place_pad {inst side i n} {
    global PAD_NEAR_X PAD_FAR_X PAD_NEAR_Y PAD_FAR_Y IN_LLX IN_LLY INT_SPAN PADW
    set block [expr {$n * $PADW}]
    set off   [expr {($INT_SPAN - $block) / 2.0}]
    switch -- $side {
        bottom { placeInstance $inst [expr {$IN_LLX + $off + $i*$PADW}] $PAD_NEAR_Y R0   -fixed }
        top    { placeInstance $inst [expr {$IN_LLX + $off + $i*$PADW}] $PAD_FAR_Y  R180 -fixed }
        left   { placeInstance $inst $PAD_NEAR_X [expr {$IN_LLY + $off + $i*$PADW}] R270 -fixed }
        right  { placeInstance $inst $PAD_FAR_X  [expr {$IN_LLY + $off + $i*$PADW}] R90  -fixed }
        default { error "bad side $side" }
    }
}
proc place_side {side padlist} {
    set n [llength $padlist]
    set i 0
    foreach inst $padlist {
        place_pad $inst $side $i $n
        incr i
    }
    puts "### UNL STATUS ### : placed $n pads on $side edge"
}

placeInstance PAD_CORNER_BL $PAD_NEAR_X $PAD_NEAR_Y R0   -fixed
placeInstance PAD_CORNER_BR $PAD_FAR_X  $PAD_NEAR_Y R90  -fixed
placeInstance PAD_CORNER_TR $PAD_FAR_X  $PAD_FAR_Y  R180 -fixed
placeInstance PAD_CORNER_TL $PAD_NEAR_X $PAD_FAR_Y  R270 -fixed

# WQ-DELTA 14 -- PRCUT_G ring-break bracket around the north analog band.
# ROOT CAUSE (Stage J LVS forensics, 2026-07-27): PDB3A_G's internal guard-ring
# strap (GDS HBG527_PREPDB3A_GR, cell-local x=0 edge) hard-bridges the pad
# ring's n-well guard band (tied to core VDD by the PVDD1DGZ pads) to the
# p-sub guard band (tied to core VSS) -- a REAL metal1 VDD-VSS short at the
# PAD_ARSV0/PAD_AVSS abutment (x=1420, north row), proven by a Pegasus
# dual-injected-text FIND_SHORTS path (2,478 shapes, all hard CONNECT-rule
# hops, articulation shape SN915). Innovus verifyGeometry/Connectivity and
# Calibre DRC are all structurally blind to it (the G0 class).
# The proven Myshkin/C0/quad rings use the AVSS..PDB3A..AVDD BRACKET motif so
# their electrode pads never abut the live digital bands; the G2 LQFP-100
# model's band order (AVDD,AVSS,ARSV0-7) violates that -- chip_top_dp and the
# Stage-I chip_top_wound INHERIT this short (reported separately, not fixed
# here). Fix on this chip: bracket the whole analog band [1220,1470] with
# PRCUT_G cells (25x135, geometrically EMPTY = every abutment bus and both
# guard bands break by absence). Placed in the flanking PFILLER space so NO
# bonded pad moves (pins 76-85 keep their positions); orientation matches the
# top row (R180/S). Placed BEFORE addIoFiller so the filler pass fills around
# them. North row has no digital signal pads and all VDDPST/VSSPST pairs are
# on W/S/E, so the digital ring's C-loop keeps every segment supplied; the
# analog island keeps its own TAVDD/TAVSS via PAD_AVDD/PAD_AVSS.
placeInstance RING_CUT_W 1195.0 $PAD_FAR_Y R180 -fixed
placeInstance RING_CUT_E 1470.0 $PAD_FAR_Y R180 -fixed
puts "### UNL STATUS ### : PRCUT_G ring-break bracket placed at x=1195/1470 (north analog island isolated)"

# WQ-DELTA 3: the SHARED wound padlist file (LEFT 22 / BOTTOM 20 / RIGHT 20 /
# TOP 10 = 72 pads, LQFP-100 emission order).
source $SCRIPT_DIR/$PADLISTS
place_side bottom $BOTTOM
place_side top    $TOP
place_side left   $LEFT
place_side right  $RIGHT

if {[catch {
    addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL
} r]} {
    puts "### UNL WARN ### : addIoFiller failed ($r) -- retrying after addIoRow"
    if {[catch {addIoRow} r2]} { puts "### UNL WARN ### : addIoRow also failed: $r2" }
    catch {addIoFiller -cell {PFILLER20_G PFILLER10_G PFILLER5_G PFILLER1_G PFILLER05_G PFILLER0005_G} -prefix IOFILL}
}
puts "### UNL STATUS ### : pad ring + IO fillers placed"

# Seal-ring band keep-out (place + route)
proc seal_keepouts {} {
    global DIE_LLX DIE_LLY DIE_URX DIE_URY SEAL_OFF
    set frames [list \
        [list $DIE_LLX $DIE_LLY $DIE_URX [expr {$DIE_LLY + $SEAL_OFF}]] \
        [list $DIE_LLX [expr {$DIE_URY - $SEAL_OFF}] $DIE_URX $DIE_URY] \
        [list $DIE_LLX $DIE_LLY [expr {$DIE_LLX + $SEAL_OFF}] $DIE_URY] \
        [list [expr {$DIE_URX - $SEAL_OFF}] $DIE_LLY $DIE_URX $DIE_URY]]
    set i 0
    foreach f $frames {
        lassign $f x0 y0 x1 y1
        catch {createPlaceBlockage -box $x0 $y0 $x1 $y1 -name SEALRING_$i}
        catch {createRouteBlk -box $x0 $y0 $x1 $y1 -layer {1 2 3 4 5 6 7 8} -name SEALRINGRB_$i}
        incr i
    }
}
seal_keepouts
puts "### UNL STATUS ### : seal-ring band reserved"

################################################################################
# Quadrant tile row: 4x U-shaped hart_tile, one per corner, 2-axis symmetric.
#   mcu0/hart1 top-left  R0   @(20,1639)   notch faces TOP edge
#   mcu0/hart2 top-right MY   @(2010,1639) notch faces TOP edge
#   mcu0/hart3 bot-left  MX   @(20,1)      notch faces BOTTOM edge
#   mcu0/hart4 bot-right R180 @(2010,1)    notch faces BOTTOM edge
# x_right = 2690-20-660 = 2010; y_top = 2690-1-1050 = 1639 (both odd -> ON the
# y=1,3,5 row grid; bottom origin 1 also odd -> both rows on-grid). 10um halos.
# Verbatim from tcl/chip_top_quad.innovus.tcl and confirmed against the CQ3a
# as-built DEF (out/chip_top_quad.floorplan_pg.def, 2000 dbu/um:
#   hart1 (40000,3278000) N / hart2 (4020000,3278000) FN /
#   hart3 (40000,2000) FS  / hart4 (4020000,2000) S).
################################################################################
# TILE GEOMETRY UPDATED 2026-08-17 to the re-hardened 8 KiB / minimal-ISA tile.
# These five numbers are a TRANSCRIPTION of innovus/common/hart_tile's floorplan
# constants and are only correct while they match it:
#     hart_tile DESIGN_WIDTH  660  -> TILE_W        660   (unchanged)
#     hart_tile DESIGN_HEIGHT 880  -> TILE_H        880   (was 1050)
#     hart_tile FINGER_W       75  -> TILE_NOTCH_X0  75   (was 80)
#                                     TILE_NOTCH_X1 585   (660-75; was 580)
#     hart_tile BASE_H        340  -> TILE_NOTCH_Y0 340   (was 600)
# The tile shrank in Y only (the 8 KiB macro is 174.41 um shorter than the 16 KiB
# one) and its analog cutout grew, so TILE_YT moves 1639 -> 1809 and the four
# reserved analog windows grow from 500x451 to 510x541.
# TILE_YT PARITY STILL HOLDS, which the row grid requires: 2690-1-880 = 1809, odd,
# so the top tiles still sit on the y=1,3,5 grid exactly as the 1639 comment above
# demands. Changing TILE_H to an odd-parity-breaking value would silently shift
# every top-row tile off-grid.
# NOTE the PG recipe below is characterised against the OLD 500x451 window set
# (CQ6/CQ8a baseline); the windows necessarily change with the tile, so PG/DRC
# numbers carried from that baseline are no longer automatically valid.
set TILE_W        660
set TILE_H        880
set TILE_NOTCH_X0 75
set TILE_NOTCH_X1 585
set TILE_NOTCH_Y0 340   ;# tile-local notch-floor height (from the tile base)
set TILE_X0       20
set TILE_XR       [expr {$DESIGN_WIDTH - $TILE_X0 - $TILE_W}]        ;# 2010
set TILE_YT       [expr {$DESIGN_HEIGHT - $CORE_SPACING - $TILE_H}]  ;# 1639
set TILE_YB       $CORE_SPACING                                      ;# 1

# {inst x y orient face}
set QTILES [list \
    [list mcu0/hart1 $TILE_X0 $TILE_YT R0   top] \
    [list mcu0/hart2 $TILE_XR $TILE_YT MY   top] \
    [list mcu0/hart3 $TILE_X0 $TILE_YB MX   bottom] \
    [list mcu0/hart4 $TILE_XR $TILE_YB R180 bottom]]

foreach t $QTILES {
    lassign $t inst tx ty orient face
    placeInstance $inst $tx $ty $orient
    addHaloToBlock 10 10 10 10 $inst
}
printStatus "Placed 4 quadrant tiles (2-axis symmetric; hart3/4 Y-mirrored)"

# --- Analog notch windows: per tile, keep-out from the notch floor to the
# nearest horizontal die edge. Hard placement blockage + all-layer route
# blockage + row cut. Notch x is centered (80 == 660-580) so orientation-
# invariant in x; the face flips the y extent.
#
# WOUND NOTE: the wound SoC carries NO analog IP -- these four 500x451 windows
# are RESERVED-EMPTY here. They are kept, verbatim and unconditional, because
# the whole PG recipe below (ring skip top+bottom, center-band M8 closure,
# under-window rails, sroute area caps) is characterised against exactly this
# window set on the CQ6/CQ8a baseline. Removing them would invalidate that
# baseline and every DRC/PG number carried over from it; the empty windows cost
# 4 x 0.225 mm2 of placeable area that this ~6%-utilised floorplan does not
# need. Any future wound analog (or the CA re-cut) drops straight in. ---
set WINDOW_BOXES {}
set TOP_NF  0      ;# min notch-floor y of the TOP tiles (top windows' lower edge)
set BOT_NF  0      ;# max notch-floor y of the BOTTOM tiles (bottom windows' upper edge)
set h 0
foreach t $QTILES {
    lassign $t inst tx ty orient face
    set WX0 [expr {$tx + $TILE_NOTCH_X0}]
    set WX1 [expr {$tx + $TILE_NOTCH_X1}]
    if {$face eq "top"} {
        set WY0 [expr {$ty + $TILE_NOTCH_Y0}]        ;# notch floor
        set WY1 $DESIGN_HEIGHT
        set TOP_NF $WY0
    } else {
        set WY0 0
        set WY1 [expr {$ty + ($TILE_H - $TILE_NOTCH_Y0)}] ;# notch floor (flipped)
        set BOT_NF $WY1
    }
    lappend WINDOW_BOXES [list $WX0 $WY0 $WX1 $WY1]
    createPlaceBlockage -type hard -name analog_win$h -box [list $WX0 $WY0 $WX1 $WY1]
    createRouteBlk -name analog_win_rt$h -box [list $WX0 $WY0 $WX1 $WY1] -layer {1 2 3 4 5 6 7 8}
    cutRow -area [list $WX0 $WY0 $WX1 $WY1]
    incr h
}
cutRow

# ---- WQ-DELTA 6 (cq8a fix b, part 1): mesh band snapped to the VIA7 pitch ----
# Quad baseline: STRIPE_Y0 = BOT_NF+39 = 490.0 , STRIPE_Y1 = TOP_NF-39 = 2200.0
# (39 um inboard of the notch-floor lines, the C0 idiom -- clear of the tiles'
# notch-floor PG-pin ring band, still inboard of the windows).
# Snapped INBOARD onto the 0.9 um VIA7 stacked-via array grid so no PG band
# edge -- and therefore no generated via array or weld -- starts at a sub-pitch
# phase:
#   490.0 -> ceil(490.0/0.9)=545  -> 490.5   (+0.5, inboard)
#   2200.0 -> floor(2200.0/0.9)=2444 -> 2199.6 (-0.4, inboard)
# Both moves are INBOARD, so the "never crosses a window" invariant is
# strengthened, not weakened.
set STRIPE_Y0_RAW [expr {$BOT_NF + 39}]
set STRIPE_Y1_RAW [expr {$TOP_NF - 39}]
set STRIPE_Y0 [wq_snap09_up $STRIPE_Y0_RAW]
set STRIPE_Y1 [wq_snap09_dn $STRIPE_Y1_RAW]
puts "### UNL STATUS ### : 4 analog windows -- top notch-floor=$TOP_NF bottom notch-floor=$BOT_NF"
puts "### UNL STATUS ### : stripe band raw=[list $STRIPE_Y0_RAW $STRIPE_Y1_RAW] -> 0.9um-snapped=[list $STRIPE_Y0 $STRIPE_Y1]"
printStatus "Reserved 4 analog notch windows (500x451; two top-edge, two bottom-edge; RESERVED-EMPTY on wound)"

# NB: unlike C0/the Stage-I wound chip there is NO full-width top_band blockage
# -- the ~1330um vertical channels between the left/right tiles (x in
# [680,2010]) in BOTH tile rows and the full center band are placeable
# shared-fabric area. That is where the wound control plane lands.

################################################################################
# Center band macros (y in [1051,1639], between the tile rows).
#   Shared RAM row: shbank0-3 + npuram0 (five 319.65x383.085 sram), centered.
#   ROM (R90/W) + POR + 2x DCO + 4x IRQ glitch filter in the band flanks /
#   lower strip. Coordinates verbatim from the quad flow and confirmed against
#   out/chip_top_quad.floorplan_pg.def (SRAM row y=1153.455, rom0 (40,1266.735)
#   W, por (700,1070), dco0 (760,1070), dco1 (840,1070), irq_gf0/1/2
#   (920/970/1020, 1070)).
################################################################################
set BAND_Y0 [expr {$TILE_YB + $TILE_H}]            ;# 1051
set BAND_Y1 $TILE_YT                               ;# 1639
set BAND_MID [expr {($BAND_Y0 + $BAND_Y1) / 2.0}]  ;# 1345

set SRAM16K_WIDTH  319.650
set SRAM16K_HEIGHT 383.085
# THE ORCHESTRATOR'S TCM IS NOT ONE OF THESE ANY MORE (2026-08-17). The five
# macros in the shared-RAM row (shbank0-3 + npuram0) are still sram1p16k, but
# hart 0's private TCM followed the tiles down to the 8 KiB sram1p8k_hvt_pg --
# SAME WIDTH, 174.41 um shorter. Sharing SRAM16K_HEIGHT with it silently
# reserved a 383.085-tall footprint for a 208.675-tall macro: a 174 um halo of
# dead centre-band area, plus a sliver/overlap census computed off the wrong
# extent. Separate constants so the two cannot drift into each other again.
set ORCH_TCM_WIDTH  319.650
set ORCH_TCM_HEIGHT 208.675
set SH_GAP   20
set SH_SPAN  [expr {5 * $SRAM16K_WIDTH + 4 * $SH_GAP}]      ;# 1678.25
set SH_X0    [expr {($DESIGN_WIDTH - $SH_SPAN) / 2.0}]      ;# 505.875
set SH_Y     [expr {$BAND_MID - $SRAM16K_HEIGHT / 2.0}]     ;# 1153.4575 (band-centered)
set i 0
foreach m {mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0} {
    placeInstance $m [expr {$SH_X0 + $i * ($SRAM16K_WIDTH + $SH_GAP)}] $SH_Y R0
    addHaloToBlock 4 4 4 4 $m
    incr i
}
cutRow
# inter-RAM gap keep-outs (wire-only slivers, C0 idiom)
for {set g 0} {$g < 4} {incr g} {
    set gx0 [expr {$SH_X0 + ($g + 1) * $SRAM16K_WIDTH + $g * $SH_GAP}]
    createPlaceBlockage -type hard -name ramgap$g \
        -box [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
    cutRow -area [list $gx0 [expr {$SH_Y - 4}] [expr {$gx0 + $SH_GAP}] [expr {$SH_Y + $SRAM16K_HEIGHT + 4}]]
}

# ROM (R90/W -> 325.055 wide x 156.525 tall) in the left band flank (x < SRAM x0).
set ROM_X 40
set ROM_Y [expr {$BAND_MID - 156.525 / 2.0}]     ;# 1266.7375 (band-centered)
placeInstance mcu0/rom0 $ROM_X $ROM_Y R90
addHaloToBlock 9 4 4 9 mcu0/rom0

# POR / DCO / IRQ-glitch-filter abstracts: small; in the lower band strip
# (y in [1070,1089], below the SRAM row) across the roomy channel x-range.
#
# ---- WQ-DELTA 7 (cq8a fix c): irq_gf halo 4 -> 20 um on ALL FOUR ------------
# CQ8a class DM2.S.2 x2 ("Space to M2 >= 0.3 um"), measured from the CQ8a
# chipdrc results db (signoff_mp/calibre/cq8a_iso/chip_top_quad/chipdrc/
# results/chipdrc.db):
#     p1  x[935.414,935.986]  y[1076.790,1076.975]
#     p2  x[1035.414,1035.986] y[1076.790,1076.975]
# GlitchFilter LEF SIZE = 31.195 x 18.87, so irq_gf0 occupies x[920,951.195]
# and irq_gf2 x[1020,1051.195], both y[1070,1088.870]: BOTH results sit at the
# IDENTICAL macro-local offset (15.414..15.986 , 6.790..6.975) -- i.e. the same
# GlitchFilter-INTERNAL dummy-M2 feature vs adjacent center-band M2. There is
# no chip-level fill step that can regenerate macro-internal geometry (CQ8a),
# so the only floorplan-stage lever is to keep band metal away from the macro.
# Halo 4 -> 20 um on all four filters (max(20, quad 4 + 10) = 20). At the 50 um
# placement pitch the 18.805 um inter-macro gaps are fully blocked -- they were
# never usable for placement anyway -- and band routing is pushed >= 20 um out,
# 66x the 0.3 um rule. irq_gf1 (970) shows no violation today; it gets the same
# halo so the row is uniform and a re-route cannot move the class onto it.
set GF_HALO 20
set AMY 1070
placeInstance mcu0/por     700 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/por
placeInstance mcu0/dco0    760 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/dco0
placeInstance mcu0/dco1    840 $AMY R0 ; addHaloToBlock 4 4 4 4 mcu0/dco1
placeInstance mcu0/irq_gf0 920 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf0
placeInstance mcu0/irq_gf1 970 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf1
placeInstance mcu0/irq_gf2 1020 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf2
# ---- WQ-DELTA 4: irq_gf3 --------------------------------------------------
# The wound (and DP) netlists instantiate FOUR GlitchFilters at MCU level --
# verified in genus/out/MCU_WOUND_hier.genus.v and in the P&R input
# in/MCU_WOUND_hier.pnr.v (`GlitchFilter irq_gf0..irq_gf3`, module MCU) -> the
# chip-level paths are mcu0/irq_gf0..3. tcl/chip_top_quad.innovus.tcl places
# only three because it was written against the older C0 MCU_MP netlist. 1070
# continues the 50 um pitch; the macro then occupies x[1070,1101.195], entirely
# inside the jogging block-pin sroute area below (that pass is FULL-WIDTH here,
# [0, BOT_NF, DESIGN_WIDTH, TOP_NF] -- unlike the Stage-I wound chip, whose
# narrow {440 460 1085 515} backstop had to be widened by hand for irq_gf3).
placeInstance mcu0/irq_gf3 1070 $AMY R0 ; addHaloToBlock $GF_HALO $GF_HALO $GF_HALO $GF_HALO mcu0/irq_gf3
cutRow
printStatus "Placed shared RAM row + ROM + POR/DCO/4x glitch-filter in the center band"

################################################################################
# CP4b TODO 1 + 2 -- THE ORCHESTRATOR (hart0 since the CPR6 renumber). IMPLEMENTED (CP4b, 2026-08-13).
#
#   INSTANCE PATHS (verified CP4a against the emitted netlist, not guessed;
#   re-verified CP4b against in/MCU_PENTA_hier.pnr.v):
#       macro     mcu0/hart0/tile/ram0        (sram1p16k_hvt_pg, the square cut)
#       subtree   mcu0/hart0                  (module orch_tile -> orch_hart_tile
#                                              -> orch_vesta/orch_adddec/...)
#       clock pin mcu0/hart0/tile/core/clk_cpu
#   The `tile/` level is orch_tile.vhd's single `tile : entity work.hart_tile`
#   instance. The MODULE names below hart0 are all `orch_`-prefixed (CP1 D6);
#   the INSTANCE names are the tile's, unchanged.
#
#   FROZEN TARGET (CP1 D9): right band flank, x in [~2188, 2689], y in
#   [1051, 1639] == [$BAND_Y0, $BAND_Y1]. The shared-RAM row's east edge is
#   [expr {$SH_X0 + $SH_SPAN}] = 2184.125 and npuram0 carries a 4 um halo, so
#   the flank's west edge (2188.8 after the snap) clears the halo by 0.675 um
#   and the macro itself by 4.675 um -- a real gap, no abutment.
#
#   GEOMETRY, all 0.9 um-snapped (measured from the MCU_castalia signoff DEF,
#   dbs/MCU_castalia.signoff.innovus.dat/MCU_castalia.def.gz, 2000 dbu/um):
#     flank    x [2188.8 , 2679.3]  y [1051.2 , 1638.9]   = 0.2883 mm^2
#              (row segments in the band stop at x = 2680.02; the right core
#               ring is M7 at x [2662,2672] u [2676,2686] -- the sram1p16k LEF
#               has NO metal above M4 (checked: M1..M4 only), so the macro may
#               legally sit under the ring, exactly as the SRAM row sits under
#               the M7/M8 mesh.)
#     TCM      x [2355.3 , 2674.95] y [1153.8 , 1536.885] = 0.1225 mm^2
#              + halo 4 -> x [2351.3 , 2678.95] y [1149.8 , 1540.885]
#     free     ~0.16 mm^2 in ONE contiguous L (west strip 162.5 x 587.7 um,
#              plus the two 98 um-tall strips over/under the macro). hart0 is
#              15,568 insts / 64.5 k um^2 of std cell (CP4a genus census), so
#              the region runs at ~43 % density -- roomy, and a soft region
#              cannot then wedge the legalizer.
#
#   WHY THE MACRO IS FLUSH EAST: it keeps the free logic area CONTIGUOUS on the
#   west side, i.e. facing the arbiter / shared-RAM row that every hart0 shared
#   access has to reach. The east leftover is a 1.07 um row sliver, blocked
#   below (the ramgap$g idiom) rather than left for the legalizer to fill.
#
#   ALWAYS-ON (CP1 D2): nothing here creates a power domain, a switch, or an
#   isolation rule -- this design has no chip-level power intent at all, and the
#   two globalNetConnect lines at the top bind EVERY pgpin (`-inst *`) to plain
#   VDD/VSS. hart0's cells and its TCM are therefore on the same unswitched
#   rails as the rest of the centre band by construction. See the PG coverage
#   assertions in the pgcheck block below (CP4b TODO 4).
################################################################################
set ORCH_HALO     4
set ORCH_FLANK_X0 [wq_snap09_up 2188.0]     ;# 2188.8
set ORCH_FLANK_X1 [wq_snap09_dn 2680.0]     ;# 2679.3
set ORCH_FLANK_Y0 [wq_snap09_up $BAND_Y0]   ;# 1051.2
set ORCH_FLANK_Y1 [wq_snap09_dn $BAND_Y1]   ;# 1638.9

# TCM macro: flush against the EAST edge of the flank (halo included), band-
# centred in y like the shared-RAM row.
set ORCH_SRAM_X [wq_snap09_dn [expr {$ORCH_FLANK_X1 - $ORCH_HALO - $ORCH_TCM_WIDTH}]]
set ORCH_SRAM_Y [wq_snap09_up [expr {$BAND_MID - $ORCH_TCM_HEIGHT / 2.0}]]
puts "### UNL STATUS ### : orchestrator flank = [list $ORCH_FLANK_X0 $ORCH_FLANK_Y0 $ORCH_FLANK_X1 $ORCH_FLANK_Y1] (all 0.9um-snapped)"
puts "### UNL STATUS ### : orchestrator TCM  = ($ORCH_SRAM_X,$ORCH_SRAM_Y) R0 -> x\[$ORCH_SRAM_X,[expr {$ORCH_SRAM_X + $ORCH_TCM_WIDTH}]\] y\[$ORCH_SRAM_Y,[expr {$ORCH_SRAM_Y + $ORCH_TCM_HEIGHT}]\] , halo $ORCH_HALO"
# phase assertion: a non-multiple of 0.9 here is the A6 failure mode
foreach {__n __v} [list ORCH_FLANK_X0 $ORCH_FLANK_X0 ORCH_FLANK_X1 $ORCH_FLANK_X1 \
                        ORCH_FLANK_Y0 $ORCH_FLANK_Y0 ORCH_FLANK_Y1 $ORCH_FLANK_Y1 \
                        ORCH_SRAM_X   $ORCH_SRAM_X   ORCH_SRAM_Y   $ORCH_SRAM_Y] {
    set __r [expr {abs($__v / $VIA7_PITCH - round($__v / $VIA7_PITCH))}]
    if {$__r > 1e-6} {
        puts "FATAL (VIA-PHASE RULE): $__n = $__v is not a multiple of $VIA7_PITCH um."
        exit 1
    }
}
# clearance assertion against the shared-RAM row (CP1 D9: do not abut)
set __sh_east [expr {$SH_X0 + $SH_SPAN}]
if {$ORCH_FLANK_X0 <= [expr {$__sh_east + 4}]} {
    puts "FATAL (CP4b TODO 1): orchestrator flank x0 $ORCH_FLANK_X0 abuts the shared-RAM row (east edge $__sh_east + 4 um halo)."
    exit 1
}
puts "### UNL STATUS ### : shared-RAM row east edge $__sh_east (+4 halo) -> flank x0 $ORCH_FLANK_X0 : gap [expr {$ORCH_FLANK_X0 - $__sh_east - 4}] um"

placeInstance mcu0/hart0/tile/ram0 $ORCH_SRAM_X $ORCH_SRAM_Y R0
addHaloToBlock $ORCH_HALO $ORCH_HALO $ORCH_HALO $ORCH_HALO mcu0/hart0/tile/ram0
cutRow

# east sliver keep-out between the TCM halo and the row ends (ramgap idiom).
set ORCH_SLIVER_X0 [expr {$ORCH_SRAM_X + $ORCH_TCM_WIDTH + $ORCH_HALO}]
set ORCH_SLIVER_X1 [expr {$DESIGN_WIDTH - 8}]
createPlaceBlockage -type hard -name orchgap0 \
    -box [list $ORCH_SLIVER_X0 $ORCH_FLANK_Y0 $ORCH_SLIVER_X1 $ORCH_FLANK_Y1]
cutRow -area [list $ORCH_SLIVER_X0 $ORCH_FLANK_Y0 $ORCH_SLIVER_X1 $ORCH_FLANK_Y1]
puts "### UNL STATUS ### : orchgap0 sliver keep-out x\[$ORCH_SLIVER_X0,$ORCH_SLIVER_X1\]"

# --- CP4b TODO 2: keep hart0's std cells in the same flank -------------------
# SOFT region (not an exclusive fence): the MCU_ARGUS/chip_top_argus irtr0
# precedent, with the same createGuide fallback. A hard fence would ALSO evict
# the ~287 wound-plane cells the reference cut placed in this rectangle and
# leaves the legalizer no escape valve; a region gives the placer a strong pull
# with a safety margin, and the post-place containment census below measures
# what it actually did rather than trusting the directive.
if {[catch {createRegion mcu0/hart0 $ORCH_FLANK_X0 $ORCH_FLANK_Y0 $ORCH_FLANK_X1 $ORCH_FLANK_Y1} __r]} {
    puts "### UNL WARN ### : createRegion mcu0/hart0 failed ($__r), falling back to createGuide"
    createGuide mcu0/hart0 $ORCH_FLANK_X0 $ORCH_FLANK_Y0 $ORCH_FLANK_X1 $ORCH_FLANK_Y1
}
set ORCH_REGION_AREA [expr {($ORCH_FLANK_X1 - $ORCH_FLANK_X0) * ($ORCH_FLANK_Y1 - $ORCH_FLANK_Y0)}]
set ORCH_MACRO_AREA  [expr {($SRAM16K_WIDTH + 2*$ORCH_HALO) * ($SRAM16K_HEIGHT + 2*$ORCH_HALO)}]
puts "### UNL STATUS ### : hart0 region area [format %.0f $ORCH_REGION_AREA] um2 - TCM+halo [format %.0f $ORCH_MACRO_AREA] um2 = [format %.0f [expr {$ORCH_REGION_AREA - $ORCH_MACRO_AREA}]] um2 free for ~64500 um2 of std cell"
printStatus "Placed the orchestrator TCM + region in the right band flank"

################################################################################
# CP4b TODO 5 -- INVARIANCE ASSERTION (CP1 D9: only the centre band changes).
#
# Every reference number below was read out of the MCU_castalia SIGNOFF DEF
# (dbs/MCU_castalia.signoff.innovus.dat/MCU_castalia.def.gz, 2000 dbu/um), not
# recomputed from this script's own expressions -- otherwise the check would
# only prove the script agrees with itself. Innovus snaps placements to the
# manufacturing grid (e.g. SH_Y = 1153.4575 -> 1153.455 in the DEF), so the
# tolerance is one grid step, not zero.
#
# This runs BEFORE the PG build: a floorplan divergence must abort in seconds,
# not after a 40 minute route.
################################################################################
proc __cp_ll {inst} {
    set ip ""
    catch { set ip [dbGet -p top.insts.name $inst -e] }
    if {$ip eq "0x0" || $ip eq ""} { return {} }
    set b {}
    catch { set b [dbGet $ip.box] }
    if {[llength $b] == 1} { set b [lindex $b 0] }
    if {[llength $b] != 4} { return {} }
    return [list [lindex $b 0] [lindex $b 1]]
}
# {inst want_x want_y}  -- lower-left of the placed bbox, um
# THE TWO TOP-TILE ROWS WERE RE-BASELINED 2026-08-17, and the weakening is
# stated rather than hidden. Every other row below is still a number READ OUT OF
# the MCU_castalia signoff DEF, which is what makes this check independent of the
# script. These two cannot be: that DEF was written with a 1050-tall tile, and
# the tile is now 880 tall (8 KiB TCM, deeper analog cutout), so the top tiles
# legitimately sit at 2690 - 1 - 880 = 1809 instead of 1639. For these two rows
# the assertion therefore only proves the script agrees with itself, and it stays
# in the table for the OTHER property it still has: that hart1 and hart2 remain
# X-symmetric, on the odd row grid, and do not drift again once re-baselined.
# The bottom tiles at y=1 are UNAFFECTED by the tile height and are still true
# DEF-sourced references -- which is why they were not touched.
# Re-derive both numbers from a fresh signoff DEF when this cut is signed off.
    # THESE THREE MOVED ON 2026-08-17, LEGITIMATELY, and the guard caught it --
    # which is the guard working, not failing. The penta wrapper gained the five
    # D3 JTAG pads (debug.enable is a shipped default, so the TAP must be bonded),
    # and place_pad CENTRES each side's contiguous block, so four new SOUTH pads
    # and one new EAST pad re-centre those two rows. The shifts are EXACTLY the
    # centring arithmetic, which is why they are accepted rather than chased:
    #     south  4 new pads x 25 um pitch / 2 =  50.0  ->  PAD_P2_0 1095.0 -> 1045.0
    #     east   1 new pad  x 25 um pitch / 2 =  12.5  ->  PAD_P4_0 1095.0 -> 1107.5
    #                                                      PAD_P5_7 1520.0 -> 1532.5
    # NOTHING ELSE IN THIS TABLE MOVED: west, north, the four corners and both
    # ring cuts all still match the MCU_castalia signoff DEF to 0.006 um, so
    # CP1 D9 ("only the centre band changes") still holds for everything the
    # JTAG addition does not touch. Do NOT relax CP_TOL to paper over a future
    # move -- update a value only when the arithmetic explains it, as here.
set CP_INVARIANTS {
    {mcu0/hart1        20.000   1809.000}
    {mcu0/hart2      2010.000   1809.000}
    {mcu0/hart3        20.000      1.000}
    {mcu0/hart4      2010.000      1.000}
    {mcu0/shbank0     505.875   1153.455}
    {mcu0/shbank1     845.525   1153.455}
    {mcu0/shbank2    1185.175   1153.455}
    {mcu0/shbank3    1524.825   1153.455}
    {mcu0/npuram0    1864.475   1153.455}
    {mcu0/rom0         40.000   1266.735}
    {mcu0/por         700.000   1070.000}
    {mcu0/dco0        760.000   1070.000}
    {mcu0/dco1        840.000   1070.000}
    {mcu0/irq_gf0     920.000   1070.000}
    {mcu0/irq_gf1     970.000   1070.000}
    {mcu0/irq_gf2    1020.000   1070.000}
    {mcu0/irq_gf3    1070.000   1070.000}
    {PAD_CORNER_BL   -135.000   -135.000}
    {PAD_CORNER_BR   2690.000   -135.000}
    {PAD_CORNER_TR   2690.000   2690.000}
    {PAD_CORNER_TL   -135.000   2690.000}
    {RING_CUT_W      1195.000   2690.000}
    {RING_CUT_E      1470.000   2690.000}
    {PAD_RESETN      -135.000   1595.000}
    {PAD_P0_0        -135.000   1495.000}
    {PAD_P2_0        1045.000   -135.000}
    {PAD_P4_0        2690.000   1107.500}
    {PAD_P5_7        2690.000   1532.500}
    {PAD_ARSV0       1395.000   2690.000}
    {PAD_AVDD        1445.000   2690.000}
}
set CP_TOL 0.006
set cp_bad 0 ; set cp_ok 0
foreach row $CP_INVARIANTS {
    lassign $row __i __wx __wy
    set ll [__cp_ll $__i]
    if {$ll eq {}} {
        puts "FATAL (CP4b TODO 5): reference instance $__i NOT FOUND in the penta design."
        incr cp_bad ; continue
    }
    lassign $ll __gx __gy
    if {abs($__gx - $__wx) > $CP_TOL || abs($__gy - $__wy) > $CP_TOL} {
        puts "FATAL (CP4b TODO 5): $__i placed at ($__gx,$__gy) -- MCU_castalia signoff DEF says ($__wx,$__wy)."
        incr cp_bad
    } else { incr cp_ok }
}
puts "### UNL STATUS ### : invariance vs MCU_castalia signoff DEF -- $cp_ok/[llength $CP_INVARIANTS] placements identical (tol $CP_TOL um), $cp_bad divergent"
if {$cp_bad > 0} {
    puts "FATAL (CP4b TODO 5): the penta floorplan MOVED reference geometry. CP1 D9 forbids it."
    exit 1
}

puts "### UNL STATUS ### : no top-level pin shapes (ports ride pad PAD terminals)"

################################################################################
# Power. Analog windows on BOTH horizontal edges -> the core ring skips BOTH
# top and bottom die segments; left/right M7 verticals carry the loop. The
# hart_tile OBS blocks BOTH M7 and M8, so a full-width M8 rail CANNOT cross the
# tile rows at the notch-floor lines: the loop CLOSES through the tile-free
# CENTER BAND (y in [1051,1639]), where every full-width horizontal M8 mesh
# stripe welds both M7 side legs (a ladder of rungs = a robustly closed grid).
# The horizontal M8 mesh is confined to the window-free y-band
# [STRIPE_Y0,STRIPE_Y1]; vertical M7 is confined to the same band (capped by
# the closure rungs, no floating stubs in the tile rows). Two dedicated M8
# rails just inboard of the windows add partial under-window closure.
# All verbatim from the quad flow except the two WQ-DELTA sites below.
################################################################################
################################################################################
# WQ-DELTA 16 -- ANALOG M7/M8 PG KEEPOUT (2026-08-25).
#
# THE DEFECT THIS REMOVES.  MCU_castalia_penta's signoff LVS reported a REAL
# VDD-VSS short:
#
#     SHORT 1. VSS: - VDD: in MCU_castalia_penta
#       "VSS:" at (1345.000, 1111.000) on layer metal1_text
#       "VDD:" at (1345.000, 1113.000) on layer metal1_text
#
# It is not newly created, it is newly VISIBLE.  Until 2026-08-24 GlitchFilter
# and OscillatorCurrentStarved streamed into signoff as EMPTY SHELLS: the
# Myshkin tapeout GDS carried both twins of each cell and the collision rule
# parked the REAL layout on <cell>_0 / <cell>_1, leaving the base name -- the
# only name strmin can resolve -- holding the abstract outline.  The
# myshkin_analog reference library republished the real layout on the correct
# base names, and the short appeared.  See
# .devlog/2026-08-24-analog-macro-empty-master-lvs.md.
#
# WHERE IT RUNS.  The FIND_SHORTS path bottoms out at y = 1069.880, the analog
# row origin, on four metal7 polygons 4-5 um wide spanning DCO#0's full height.
# Those are TOP-LEVEL PG STRIPES crossing the macro site, not the macro's own
# metal: the DCO's power pins are M5 ONLY
#
#     PIN VSS  USE GROUND  PORT LAYER M5 ; RECT 3.43 1.865 54.97 2.365 ;
#     PIN VDD  USE POWER   PORT LAYER M5 ; RECT 0.12 3.09  58.29 3.59  ;
#
# while its LEF declares 12 M7 and 20 M8 OBSTRUCTIONS.  The PG grid was drawn
# straight over geometry it was told to avoid.
#
# WHY A CROSSING SHORTS.  The vertical M7 addStripe pass below runs with
# -stacked_via_bottom_layer M1 and -block_ring_bottom_layer_limit M1, so where a
# stripe crosses a macro it punches a via stack down toward M1.  Over an EMPTY
# OUTLINE that stack hit nothing and the flow looked clean for years.  Over the
# REAL DCO layout the same stack lands in the macro's guts and bridges its
# internal nets, which is how a VDD stripe and a VSS stripe end up on one net.
#
# THE RULE APPLIED, and it is a rule rather than a special case: HONOUR THE
# OBSTRUCTIONS EACH MACRO ACTUALLY DECLARES.  Measured from the three abstracts
# this floorplan places:
#
#     OscillatorCurrentStarved  pins M5 only;  OBS 12 x M7, 20 x M8, 102 x VIA7
#     GlitchFilter              pins M3 only;  OBS stops at M3 / VIA2
#     PowerOnResetCheng         pins M3 only;  OBS stops at M3 / VIA2
#
# So the mesh is kept OFF the two DCOs and LEFT CROSSING the POR and the four
# irq_gf GlitchFilters.  That asymmetry is deliberate and is what the LEFs ask
# for: those two declare nothing above M3 and the crossing IS their power
# delivery.  The DCO takes its power on M5 from the jogging block-pin sroute
# pass further down, whose layerChangeRange { M1(1) M8(8) } already spans M5.
#
# MCU_hart is the control: a parallel single-hart block over the SAME restored
# analog geometry, short-free, and short-free specifically because it applies
# this rule (.devlog/2026-08-24-mcu-hart-signoff-run.md).
#
# 3.0 um: enough to also clear the 1.5 um that M7.S.4 / M8.S.3 demand next to
# anything wider than the 4.5 um wide-metal threshold (the stripes here are
# 5.0 um, so they ARE wide metal).
#
# BLAST RADIUS, predicted from the geometry before running (all measured, none
# assumed).  Vertical M7 stripes sit at x = 59 + 50k and x = 68 + 50k, 5.0 wide;
# horizontal M8 rungs at y = 584.5 + 50k and y = 593.5 + 50k.  Placed DCO bboxes
# are (760.0,1070.0)-(818.17,1107.145) and (840.0,1070.0)-(898.17,1107.145), so
# the keepouts are (757.0,1067.0)-(821.17,1110.145) and
# (837.0,1067.0)-(901.17,1110.145).  That clips:
#     6 vertical M7 stripes  -- x 759,768,809,818 over dco0 ; 859,868 over dco1
#                               each loses 43.145 um of a 1529.1 um span (2.8%)
#     2 horizontal M8 rungs  -- y 1084.5 and 1093.5, each losing 2 x 64.17 um
#                               of a 2690 um span (4.8%), out of ~61 rungs
# No signal-routing cost at all: lines 1531/1532 already put a FULL-DIE-FRAME
# route blockage on layers 7 and 8, so signal nets never used M7/M8 in this
# block.  The keepout is therefore PG-only by construction.
#
# BELT AND BRACES, because these are two different mechanisms: the route
# blockage stops addStripe generating the shapes, and the sweep after the last
# addStripe deletes anything that got through anyway.  The sweep follows the
# sWire/sVia asymmetry this file already learned once at WQ-DELTA 15: wires
# carry a box and filter on it, but sViaInst objects have NO box_* fields at
# all, only a placement point, so a box filter on them matches NOTHING SILENTLY
# and leaves every via array behind.  Vias filter on pt_x / pt_y.
################################################################################
set ANALOG_PG_KEEPOUT 3.0
set DCO_INSTS {mcu0/dco0 mcu0/dco1}
set DCO_BOXES {}
foreach m $DCO_INSTS {
    # inst_bbox is not defined until the pgcheck section, so read the placed
    # box directly here (same dbGet, inlined).
    set ip [dbGet -p top.insts.name $m -e]
    if {$ip eq "" || $ip eq "0x0"} {
        puts "FATAL (WQ-DELTA 16): DCO instance $m not found when building the M7/M8 keepout"
        exit 1
    }
    set bb [dbGet $ip.box]
    if {[llength $bb] == 1} { set bb [lindex $bb 0] }
    if {[llength $bb] != 4} {
        puts "FATAL (WQ-DELTA 16): could not read a placed bbox for DCO instance $m"
        exit 1
    }
    lassign $bb bx0 by0 bx1 by1
    set kx0 [expr {$bx0 - $ANALOG_PG_KEEPOUT}]
    set ky0 [expr {$by0 - $ANALOG_PG_KEEPOUT}]
    set kx1 [expr {$bx1 + $ANALOG_PG_KEEPOUT}]
    set ky1 [expr {$by1 + $ANALOG_PG_KEEPOUT}]
    lappend DCO_BOXES [list $kx0 $ky0 $kx1 $ky1]
    createRouteBlk -name pgkeep_[string map {/ _} $m] -box [list $kx0 $ky0 $kx1 $ky1] -layer {7 8}
    puts "### UNL STATUS ### : M7/M8 PG keepout over $m = ($kx0,$ky0) .. ($kx1,$ky1)  (macro bbox + $ANALOG_PG_KEEPOUT um)"
}
puts "### UNL STATUS ### : [llength $DCO_BOXES] DCO M7/M8 keepout(s) armed before addStripe"

printStatus "Adding power ring (left/right M7; top+bottom skipped for analog windows)"
addRing \
    -nets {VDD VSS} \
    -type core_rings \
    -follow io \
    -skip_side {top bottom} \
    -layer {top M8 bottom M8 left M7 right M7} \
    -width $POWER_RING_PATH_WIDTH \
    -spacing $POWER_RING_PATH_SPACING \
    -offset $POWER_RING_PATH_SPACING \
    -center 0 -extend_corner {} -threshold 0 -jog_distance 0 \
    -snap_wire_center_to_grid None

# Horizontal M8 mesh + closure detours, confined to the window-free band.
setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M7 \
    -extend_to_closest_target ring
addStripe \
    -layer M8 \
    -nets {VDD VSS} \
    -direction horizontal \
    -start_from bottom \
    -area [list 0 $STRIPE_Y0 $DESIGN_WIDTH $STRIPE_Y1] \
    -set_to_set_distance $POWER_STRIPE_SET_TO_SET \
    -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_STRIPE_PATH_WIDTH \
    -block_ring_bottom_layer_limit M1 \
    -start_offset $POWER_STRIPE_PATH_SPACING \
    -stop_offset $POWER_STRIPE_PATH_SPACING

################################################################################
# WQ-DELTA 5 -- cq8a fix (a): vertical M7 stripe x-PHASE SHIFT (+9.0 um)
#
# CLASS: M7.S.3 x1 + the x=355 member of M7.S.4 (the A6 VIA-PHASE-RULE extended
# to stripe-vs-macro-pin phase, CQ8a war story 1). Numbers, all measured:
#
# 1) rom0 geometry. LEF SIZE 156.525 BY 325.055; placed (40, 1266.7375) R90/W
#    -> oriented bbox 325.055 x 156.525 = x[40, 365.055], y[1266.7375,1423.2625]
#    (DEF-confirmed: `- mcu0/rom0 rom_hvt_pg + FIXED (80000 2533470) W`,
#    2000 dbu/um).
#    IMPORTANT: rom_hvt_pg.lef contains ZERO M7 geometry (grep M7 -> 0 hits).
#    Its PG pins are FULL-WIDTH M4 bands `RECT 0.0 y0 156.525 y1`. Under W the
#    local-y band maps to a chip-x band:  x = 40 + (325.055 - y_local).
#    The seven bands nearest the ROM's right edge:
#        VSS local[12.965,13.765] -> chip x[351.290,352.090]
#        VDD local[11.565,12.365] -> chip x[352.690,353.490]
#        VSS local[10.165,10.965] -> chip x[354.090,354.890]
#        VDD local[ 8.765, 9.565] -> chip x[355.490,356.290]
#        VSS local[ 7.365, 8.165] -> chip x[356.890,357.690]
#        VSS local[ 4.565, 5.365] -> chip x[359.690,360.490]
#        VDD local[ 3.165, 3.965] -> chip x[361.090,361.890]
#    => the ROM PG comb occupies chip x 351.290 .. 361.890 (0.8 um bands on a
#    1.4 um pitch). The "ROM M7 pin" of the CQ8a note is the router-generated
#    M7 riser that follows these x positions.
#
# 2) Measured violations (signoff_mp/calibre/cq8a_iso/chip_top_quad/chipdrc/
#    results/chipdrc.db; the reported rectangle is the SPACE region):
#        M7.S.3 (space >= 0.5)  x[355.000,355.490] y[1244.000,1249.000] = 0.490
#        M7.S.4 (space >= 1.5)  same rect  (p7)
#        M7.S.4 (space >= 1.5)  x[357.690,359.000] y[1253.000,1258.000] = 1.310
#    Each gap is bounded on one side by a ROM comb-band edge (355.490 = the VDD
#    band's left edge; 357.690 = the VSS band's right edge) and on the other by
#    a mesh M7 edge at x = 355.000 / 359.000. The two y spans are exactly the
#    horizontal M8 stripe pair rows, so the mesh side is a stripe-grid-phased
#    shape: shifting the vertical M7 grid moves it.
#
# 3) Required clearance. The 5 um-wide PG stripes are "wide metal" for
#    M7.S.4 (line width > 4.5 um, parallel run > 4.5 um) => 1.5 um. Forbidden
#    mesh-edge window = comb +/- 1.5 = x[349.790, 363.390].
#
# 4) Chosen shift: +9.0 um = 10 x 0.9 um (the VIA7 stacked-via array pitch, so
#    the A6 via-phase invariant holds).
#        355.000 -> 364.000 : clearance to comb right edge 361.890 = 2.110 um
#                             (>= 1.5, margin 0.610 ; >= 0.5, margin 1.610)
#        359.000 -> 368.000 : clearance = 6.110 um
#    Both are OUTSIDE [349.790,363.390]. A smaller shift cannot work: the
#    forbidden window (13.6 um) is wider than the 4.0 um separation of the two
#    offending edges, so the pair must clear the comb together.
#
# RESIDUAL RISK (be honest on the first cut): the x=355.000/359.000 edges could
# not be attributed to a specific generator without a GDS window scan, because
# the ROM abstract has no M7 to reason from. If the first chipdrc still shows
# M7.S.3/M7.S.4 near x 351..363, run
#   signoff_mp/gds_via_window.py on out/MCU_castalia.gds2 around
#   (355,1246) and (359,1255)
# BEFORE touching this number again -- and rule out a translation phantom
# first (the PG4 discipline).
################################################################################
set M7_PHASE_SHIFT 9.0    ;# 10 x VIA7_PITCH (0.9 um) -- see the block above
set M7_START_OFFSET [expr {$POWER_STRIPE_SET_TO_SET + $M7_PHASE_SHIFT}]
puts "### UNL STATUS ### : vertical M7 start_offset $POWER_STRIPE_SET_TO_SET -> $M7_START_OFFSET (cq8a fix a, +$M7_PHASE_SHIFT = [expr {int($M7_PHASE_SHIFT/$VIA7_PITCH)}] x $VIA7_PITCH um VIA7 pitch)"

# Vertical M7 mesh: confined to the SAME [STRIPE_Y0,STRIPE_Y1] band so the
# verticals are capped by the closure rails. bottom back to M1 -> owns
# macro-pin (M4) + follow-pin (M1) stacks on its centerlines.
setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M1 \
    -extend_to_closest_target ring
addStripe \
    -layer M7 \
    -nets {VDD VSS} \
    -direction vertical \
    -start_from bottom \
    -area [list 0 $STRIPE_Y0 $DESIGN_WIDTH $STRIPE_Y1] \
    -set_to_set_distance $POWER_STRIPE_SET_TO_SET \
    -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_STRIPE_PATH_WIDTH \
    -block_ring_bottom_layer_limit M1 \
    -start_offset $M7_START_OFFSET \
    -stop_offset $POWER_STRIPE_PATH_SPACING

################################################################################
# --- Partial under-window M8 rails at the two notch-floor lines ---
# Extra strapping in the tile-free CHANNEL + margins just inboard of the
# top/bottom windows (they break over the tiles, which block M8 -- the loop
# closure itself runs through the center band). remove_floating=FALSE so the
# surviving segments stay; extend_to_closest_target ring welds them to the side
# legs where they reach.
#
# WQ-DELTA 6 -- cq8a fix (b), part 2: WELD-STUB GUARD.
# CLASS: VIA7.W.1 x2 ("Width (maximum = minimum) = 0.36"). Measured cuts
# (same chipdrc.db): 0.36 x 0.51 at
#     x[2164.070,2164.430]  y[1046.320,1046.830]
#     x[2164.070,2164.430]  y[1643.170,1643.680]
# i.e. legal 0.36 in x, MALFORMED 0.51 in y -- a stacked-via generation stub.
#
# HONEST LOCATION FINDING (differs from the staging brief's premise): those two
# cuts do NOT lie in these under-window rails. x = 2164.25 is inside the RIGHT
# tile column (hart2/hart4 span x[2010,2670]); y = 1046.575 is 4.425 um BELOW
# the bottom tiles' top edge (1051) and y = 1643.425 is 4.425 um ABOVE the top
# tiles' bottom edge (1639) -- the exact mirror pair, i.e. the TILE PG-pin weld
# band at the two center-band-facing tile edges. The under-window rails live at
# y ~[457,481] and ~[2199,2237], hundreds of um away.
#
# WHAT IS DONE HERE: every band edge that drives a weld/via generation in this
# script is snapped INBOARD onto the 0.9 um VIA7 array grid, so no PG span can
# start or stop at a sub-pitch phase and leave a 0.4 um weld stub:
#     top rail    raw y[2199.000,2237.000] -> [2199.600,2236.500]
#     bottom rail raw y[ 453.000, 491.000] -> [ 453.600, 490.500]
#     mesh band   raw y[ 490.000,2200.000] -> [ 490.500,2199.600]  (above)
# All four moves are inboard, so no rail creeps toward a window.
#
# WHAT IS **NOT** CLAIMED: this snap is a hygiene guard; it is NOT proven to
# remove the two measured VIA7.W.1 cuts, which sit at the tile PG weld band.
# FIRST-CUT ACTION: if chipdrc still reports VIA7.W.1, dump the source GDS
# around (2164.25,1046.575) with signoff_mp/gds_via_window.py and histogram the
# cuts with signoff_mp/via7_map.py -- verifyGeometry does NOT check same-net
# cut spacing/shape across two via structs, so "vG GREEN" says nothing here.
################################################################################
set UWR_TOP_Y0 [wq_snap09_up [expr {$TOP_NF - 40}]]   ;# 2199.000 -> 2199.600
set UWR_TOP_Y1 [wq_snap09_dn [expr {$TOP_NF -  2}]]   ;# 2237.000 -> 2236.500
set UWR_BOT_Y0 [wq_snap09_up [expr {$BOT_NF +  2}]]   ;#  453.000 ->  453.600
set UWR_BOT_Y1 [wq_snap09_dn [expr {$BOT_NF + 40}]]   ;#  491.000 ->  490.500
puts "### UNL STATUS ### : under-window rails 0.9um-snapped -- top=[list $UWR_TOP_Y0 $UWR_TOP_Y1] bottom=[list $UWR_BOT_Y0 $UWR_BOT_Y1]"

setAddStripeMode \
    -remove_floating_stripe_over_block false \
    -trim_antenna_back_to_shape core_ring \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M7 \
    -extend_to_closest_target ring
# top closure rail (VDD+VSS pair) just below the top windows
addStripe \
    -layer M8 -nets {VDD VSS} -direction horizontal -start_from top \
    -area [list 0 $UWR_TOP_Y0 $DESIGN_WIDTH $UWR_TOP_Y1] \
    -set_to_set_distance 800 -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_RING_PATH_WIDTH \
    -start_offset $POWER_STRIPE_PATH_SPACING -stop_offset $POWER_STRIPE_PATH_SPACING
# bottom closure rail (VDD+VSS pair) just above the bottom windows
addStripe \
    -layer M8 -nets {VDD VSS} -direction horizontal -start_from bottom \
    -area [list 0 $UWR_BOT_Y0 $DESIGN_WIDTH $UWR_BOT_Y1] \
    -set_to_set_distance 800 -spacing $POWER_STRIPE_PATH_SPACING \
    -width $POWER_RING_PATH_WIDTH \
    -start_offset $POWER_STRIPE_PATH_SPACING -stop_offset $POWER_STRIPE_PATH_SPACING
puts "### UNL STATUS ### : added top+bottom M8 closure detours under the windows"

################################################################################
# WQ-DELTA 8 -- cq8a note (d): the M3.S.2 / M5.S.2 cut-blockage redo is
# DELIBERATELY NOT re-applied.
#
# CQ8a's sanctioned ECO (cut blockage + `ecoRoute -fix_drc` on the CQ6 signoff
# DB) closed exactly two center-band classes with zero collateral:
#     M3.S.2 x2  at (1012, 895)
#     M5.S.2 x1  at (1012, 935)
# Those were ROUTER artifacts at coordinates specific to the quad's C0-era
# std-cell route. This chip has a DIFFERENT netlist (the wound control plane,
# 2.4x the instances), a different placement and a fresh route, so re-applying
# a blockage at (1012,89x) would be cargo-culting a coordinate. NB those two
# classes are ALREADY absent from the cq8a chipdrc.db read above -- that db is
# the POST-ECO cut (1946 -> 1943), which is why the numbers quoted in the fix
# blocks above cover only the four classes the ECO could not fix.
# FIRST-CUT ACTION: grep the first chipdrc for M3.S.2 / M5.S.2. If the class
# recurs anywhere, the CQ8a v2 recipe (cut blockage + ecoRoute -fix_drc, and
# NO filler churn -- deleteFiller/addFiller on a routed DB manufactured ~400
# min-area results in CQ8a v1) is the proven fix.
################################################################################

################################################################################
# WQ-DELTA 16 (part 2) -- DCO KEEPOUT SWEEP.
# Delete any VDD/VSS M7/M8 SPECIAL shape or via that still overlaps a DCO
# keepout box after every addStripe pass above.  The route blockages armed
# before addRing should have prevented every one of these; this is the second,
# INDEPENDENT mechanism, because a silent VDD-VSS short over an analog macro is
# precisely the defect that hid behind empty outlines for years and it is worth
# two guards.  A sweep count of ZERO is the INTENDED outcome, not a null result:
# it means the blockage did the job and there was nothing left to clean up.
# NB the sWire/sVia asymmetry (WQ-DELTA 15 / RING_NUKE lesson): wires carry a
# box and filter on it, but sViaInst objects have NO box_* fields at all, only a
# placement point, so a box filter on them matches NOTHING SILENTLY.
################################################################################
proc __pg_in_any_box {x y boxes} {
    foreach b $boxes {
        lassign $b bx0 by0 bx1 by1
        if {$x >= $bx0 && $x <= $bx1 && $y >= $by0 && $y <= $by1} { return 1 }
    }
    return 0
}
set __pgswept 0
foreach __n {VDD VSS} {
    set __net [dbGet -p top.nets.name $__n -e]
    if {$__net eq "" || $__net eq "0x0"} { continue }
    foreach __w [dbGet $__net.sWires] {
        set __lay ""
        catch { set __lay [dbGet $__w.layer.name] }
        if {$__lay ne "M7" && $__lay ne "M8"} { continue }
        set __b {}
        catch { set __b [dbGet $__w.box] }
        if {[llength $__b] == 1} { set __b [lindex $__b 0] }
        if {[llength $__b] != 4} { continue }
        lassign $__b __x0 __y0 __x1 __y1
        # OVERLAP, not containment: a stripe crossing the site only clips it.
        set __hit 0
        foreach __bx $DCO_BOXES {
            lassign $__bx __kx0 __ky0 __kx1 __ky1
            if {$__x1 > $__kx0 && $__x0 < $__kx1 && $__y1 > $__ky0 && $__y0 < $__ky1} {
                set __hit 1
                break
            }
        }
        if {$__hit} { dbDeleteObj $__w; incr __pgswept }
    }
    foreach __v [dbGet $__net.sVias] {
        set __px 0 ; set __py 0
        catch { set __px [dbGet $__v.pt_x] }
        catch { set __py [dbGet $__v.pt_y] }
        if {[__pg_in_any_box $__px $__py $DCO_BOXES]} { dbDeleteObj $__v; incr __pgswept }
    }
}
puts "### UNL STATUS ### : DCO keepout sweep removed $__pgswept M7/M8 PG shape(s)/via(s)"

editTrim -all
setCheckMode -globalNet true -io true -route true -tapeOut true

printStatus "Routing power rails (followpin + block-pin)"
setSrouteMode -corePinMaxViaScale "100 10"
# blockPin+corePin, capped to the window-free band [BOT_NF,TOP_NF]: connects
# every std-cell follow-pin in the band AND every macro/tile BASE PG pin (both
# tile rows' bases are inside [451,2239]; useLef = orientation-aware, so the
# MX/R180 flipped-tile pins strap correctly).
sroute \
    -nets { VSS VDD } \
    -allowLayerChange 0 \
    -allowJogging 0 \
    -connect {blockPin corePin} \
    -blockPin useLef \
    -area [list 0 $BOT_NF $DESIGN_WIDTH $TOP_NF] \
    -corePinWidth 0.3

# JOGGING block-pin pass over the whole window-free band -- the tile + analog
# macro PG strap workhorse. FULL WIDTH, so it covers the entire analog row
# including irq_gf3 at x[1070,1101.195] (no hand-widened x-window is needed
# here, unlike the Stage-I wound chip's {440 460 1085 515} backstop).
printStatus "Routing tile + macro PG pins (jogging block-pin workhorse pass)"
sroute \
    -nets { VSS VDD } \
    -connect { blockPin } \
    -blockPin useLef \
    -allowLayerChange 1 \
    -allowJogging 1 \
    -layerChangeRange { M1(1) M8(8) } \
    -area [list 0 $BOT_NF $DESIGN_WIDTH $TOP_NF]

# Pad-supply hookup: the core-domain supply pads (PVDD1DGZ_G.VDD /
# PVSS1DGZ_G.VSS, bound to VDD/VSS by the globalNetConnect -inst * above) tie
# to the core ring. ACCEPTANCE = the "sroute ... created N wires" log line
# (trust the COUNT, not the absence of an error -- PG2-F1) + the signoff
# verifyConnectivity -connectPadSpecialPorts gate.
sroute \
    -nets { VSS VDD } \
    -connect { padPin } \
    -allowJogging 1 \
    -allowLayerChange 1 \
    -layerChangeRange { M1(1) M8(8) } \
    -area [list $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY]
puts "### UNL STATUS ### : pad-supply sroute (padPin) done"

# WQ-DELTA 15 -- PAD_VSS_1 strap-to-stripe M7 weld.  MEASURED AT RUN TIME, NOT
# HARD-CODED.  This block used to be one literal rect:
#
#     add_shape -net VSS -layer M7 -rect {1318.9 503.8 1326.1 509.2} ...
#
# aimed at the 2026-07-27 MCU_castalia signoff floorplan, where the padPin
# sroute gave PAD_VSS_1 an M2 riser at x=1324.6 whose via stack topped out on
# M7 at y[503.8,509.2], 1.6 um to the RIGHT of the vertical VSS M7 stripe
# x[1318,1323] whose floor was then y=503.5.  The comment claimed the numbers
# were safe "because addStripe and the pad-pin x are floorplan-fixed".
#
# THEY ARE NOT.  THREE INDEPENDENT FLOORPLAN MOVES INVALIDATED THAT RECT, AND
# IT SHIPPED IN THE cpr6 SIGNOFF CUT AS A FLOATING SHAPE: 2 ANTENNA markers
# (rpt/*.verifyGeometry.tcm8k_fixed.rpt) and IMPVFC-94 "dangling Wire at
# (1318.900,506.500) / (1326.100,506.500) on layer M7"
# (rpt/*.cpr6.verifyConnectivity.{pg,signoff}.rpt).  ALL FOUR NUMBERS BELOW ARE
# MEASURED off dbs/MCU_castalia_penta.cpr6.signoff.innovus.dat with
# tcl/MCU_castalia_penta_weld_probe.tcl (restore + dbGet, read-only), NOT
# recomputed from this script:
#
#   MOVE 1 -- THE STRIPE FLOOR ROSE 90 um.  TILE_H went 1050 -> 880 for the
#     8 KiB TCM re-harden, so BOT_NF = 1 + (TILE_H - TILE_NOTCH_Y0) went
#     451 -> 541 and STRIPE_Y0 = snap09up(BOT_NF+39) went 490.5 -> 580.5.
#     The vertical M7 mesh is trimmed back to the lowest horizontal M8 rail
#     (trim_antenna_back_to_shape core_ring), so the MEASURED VSS M7 verticals
#     are now y[593.5,2098.5] -- x{...,1268,1318,1368,...} x 5 um wide, 50 um
#     pitch, unchanged in x.  The old rect's y[503.8,509.2] is therefore
#     84.3 um BELOW EVERY M7 STRIPE IN THE DESIGN: its LEFT end could not have
#     landed on the stripe at ANY x.  This move, not the JTAG one, is what
#     killed the left end.
#
#   MOVE 2 -- THE PAD MOVED -50 um.  The five D3 JTAG pads joined BOTTOM and
#     place_pad centres each side's block, so PAD_VSS_1 measures
#     box x[1270.0,1295.0] y[-135.0,0.0] (was x[1320,1345]).  -50 um is
#     exactly one M7 stripe pitch, so the pad's relation to the MESH is
#     unchanged (its nearest VSS vertical is now x[1268,1273] instead of
#     x[1318,1323]) -- but the rect, which is not on the pitch, was left
#     44.6 um east of where the strap would rise.
#
#   MOVE 3 -- AND THERE IS NO STRAP TO WELD TO AT ALL.  Measured: the lowest
#     VSS special metal in the WHOLE DESIGN is the orphan rect itself
#     (M7 y=503.8); the next is M8 at y=593.5 and M2 at y=681.05.  NOTHING
#     exists between the pad's top edge (y=0) and y=503.8.  ROOT CAUSE, from
#     log/MCU_castalia_penta.log: ALL THREE sroute passes above aborted with
#         **ERROR: (IMPSR-2403): All of the PG terms are not connected to PG nets
#     after "pg term VSSE / VDDPE / VDDCE of inst mcu0/hart0/tile/ram0 is not
#     connect to global special net".  The 8 KiB orchestrator TCM
#     (sram1p8k_hvt_pg) exposes SPLIT rails VSSE/VDDPE/VDDCE where the 16 KiB
#     part exposed plain VSS/VDD, and the chip-level globalNetConnect at the
#     top of this file still binds only pins literally named VDD/VSS.  sroute
#     bails before creating a single wire, so this cut has NO follow pins, NO
#     macro PG straps (pgcheck: all four tiles "VDD sWires=0  VSS sWires=0")
#     and NO pad straps.  A weld cannot manufacture a strap; THAT defect must
#     be fixed at the globalNetConnect, not here.
#
# WHY NOT JUST MOVE THE RECT -50 um: because the strap it is supposed to touch
# does not exist, and because the stripe it is supposed to touch is 84 um away
# in y.  A rect long enough to bridge that would be ~90 um of hand-drawn M7
# running south from the mesh floor -- a power ROUTE, not a weld -- and the
# nearest opposite-net metal is only 4.9 um away in x (VDD M7 verticals
# x[1259,1264] and x[1309,1314], y[584.5,2089.5]), so a mis-aimed one shorts
# VDD to VSS.  This block therefore MEASURES its two anchors every run and
# welds only what it can actually see, with an explicit opposite-net
# clearance gate.  If either anchor is missing it emits NOTHING and says so:
# an honest, visible pad-hookup open beats a floating rect that reads as
# 2 ANTENNA DRCs and hides the same open.
proc wq15_box {ptr} {
    set b {}
    catch { set b [dbGet $ptr.box] }
    if {[llength $b] == 1} { set b [lindex $b 0] }
    return $b
}
proc wq15_boxes {net layer} {
    set out {}
    set np [dbGet -p top.nets.name $net -e]
    if {$np eq "" || $np eq "0x0"} { return {} }
    foreach w [dbGet $np.sWires -e] {
        set l ""
        catch { set l [dbGet $w.layer.name -e] }
        if {$l ne $layer} { continue }
        set b [wq15_box $w]
        if {[llength $b] != 4} { continue }
        lappend out $b
    }
    return $out
}

set WQ15_PAD         PAD_VSS_1
set WQ15_NET         VSS
set WQ15_OPP         VDD
set WQ15_LAYER       M7
set WQ15_OPP_SPACING 1.5    ;# M7 wide-metal opposite-net rule (the old comment's number)
set WQ15_MAX_SPAN    25.0   ;# a weld is a weld; anything longer is a power route -> refuse
set WQ15_MIN_BAND    0.4    ;# minimum y-overlap that can carry an M7 weld
set WQ15_XWIN        30.0   ;# how far either side of the pad a strap landing may sit
set WQ15_MESH_MINH  100.0   ;# taller than this on M7 == a mesh stripe, not a landing pad
set WQ15_FLOOR_TOL  10.0    ;# how far ABOVE the stripe floor a strap landing may still sit

set wq15_reason ""
set wq15_added  0
set wq15_nowork 0   ;# 1 = measured OK and no weld is NEEDED (not a failure)
set wq15_padp [dbGet -p top.insts.name $WQ15_PAD -e]
if {$wq15_padp eq "" || $wq15_padp eq "0x0"} {
    set wq15_reason "instance $WQ15_PAD not found (pad list changed?)"
} else {
    lassign [wq15_box $wq15_padp] wq15_px0 wq15_py0 wq15_px1 wq15_py1
    set wq15_pcx [expr {($wq15_px0 + $wq15_px1) / 2.0}]
    set wq15_m7  [wq15_boxes $WQ15_NET $WQ15_LAYER]

    # (a) nearest vertical mesh stripe to the pad centre + the mesh floor
    set wq15_stripe {} ; set wq15_bestd 1.0e9 ; set wq15_floor 1.0e9
    foreach b $wq15_m7 {
        lassign $b bx0 by0 bx1 by1
        if {($by1 - $by0) < $WQ15_MESH_MINH} { continue }
        if {($bx1 - $bx0) > 20.0}            { continue }
        if {$by0 < $wq15_floor} { set wq15_floor $by0 }
        set d [expr {abs(($bx0 + $bx1) / 2.0 - $wq15_pcx)}]
        if {$d < $wq15_bestd} { set wq15_bestd $d ; set wq15_stripe $b }
    }
    # (b) the pad strap's landing on the same layer: the SOUTHERNMOST non-mesh
    #     shape sitting at (or below) the chosen stripe's own floor, inside a
    #     pad-width window in x.  This is the object the old literal called
    #     "the strap's via6 landing" -- the strap climbs from the pad, so its
    #     end cap is the lowest same-net M7 shape in that column.  NOTE the
    #     tolerance: in the pre-JTAG cut the landing (y[503.8,509.2]) sat just
    #     ABOVE the stripe floor (503.5), so "strictly below the floor" would
    #     have rejected the very object this weld exists to catch.
    set wq15_sfloor $wq15_floor
    if {$wq15_stripe ne {}} { set wq15_sfloor [lindex $wq15_stripe 1] }
    set wq15_anchor {} ; set wq15_low 1.0e9
    foreach b $wq15_m7 {
        lassign $b bx0 by0 bx1 by1
        if {($by1 - $by0) >= $WQ15_MESH_MINH}            { continue }
        if {$by0 > ($wq15_sfloor + $WQ15_FLOOR_TOL)}     { continue }
        if {$bx1 < ($wq15_px0 - $WQ15_XWIN)}             { continue }
        if {$bx0 > ($wq15_px1 + $WQ15_XWIN)}             { continue }
        if {$by0 < $wq15_low} { set wq15_low $by0 ; set wq15_anchor $b }
    }
    set wq15_sdesc "NONE" ; if {$wq15_stripe ne {}} { set wq15_sdesc $wq15_stripe }
    set wq15_adesc "NONE" ; if {$wq15_anchor ne {}} { set wq15_adesc $wq15_anchor }
    puts "### UNL STATUS ### : WQ15 measured -- $WQ15_PAD box [wq15_box $wq15_padp] ; nearest $WQ15_NET $WQ15_LAYER stripe $wq15_sdesc ; $WQ15_LAYER mesh floor $wq15_floor ; strap landing $wq15_adesc"

    if {$wq15_stripe eq {}} {
        set wq15_reason "no vertical $WQ15_NET $WQ15_LAYER mesh stripe found -- the PG mesh is gone, not mis-aimed"
    } elseif {$wq15_anchor eq {}} {
        set wq15_reason "no $WQ15_NET $WQ15_LAYER strap landing at/below the stripe floor ($wq15_sfloor, tol $WQ15_FLOOR_TOL) within [expr {$WQ15_XWIN}] um of $WQ15_PAD x\[$wq15_px0,$wq15_px1\] -- the padPin sroute produced NOTHING (check the log for IMPSR-2403 / unbound VSSE|VDDPE|VDDCE on mcu0/hart0/tile/ram0). A weld cannot substitute for a strap."
    } else {
        lassign $wq15_stripe sx0 sy0 sx1 sy1
        lassign $wq15_anchor ax0 ay0 ax1 ay1
        set wq15_wy0 [expr {max($sy0, $ay0)}]
        set wq15_wy1 [expr {min($sy1, $ay1)}]
        set wq15_gap [expr {max($sx0 - $ax1, $ax0 - $sx1)}]
        set wq15_wx0 [expr {min($sx0, $ax0)}]
        set wq15_wx1 [expr {max($sx1, $ax1)}]
        if {$wq15_gap <= 0.0} {
            set wq15_nowork 1
            set wq15_reason "strap landing x\[$ax0,$ax1\] ALREADY overlaps stripe x\[$sx0,$sx1\] -- the padPin sroute reached the mesh on its own, no weld needed"
        } elseif {($wq15_wy1 - $wq15_wy0) < $WQ15_MIN_BAND} {
            set wq15_reason "strap landing y\[$ay0,$ay1\] and stripe y\[$sy0,$sy1\] do not overlap in y (band [format %.3f [expr {$wq15_wy1 - $wq15_wy0}]] um < $WQ15_MIN_BAND) -- they are separated along the stripe, not across it, so a weld is the WRONG TOOL: fix the strap/mesh reach instead"
        } elseif {($wq15_wx1 - $wq15_wx0) > $WQ15_MAX_SPAN} {
            set wq15_reason "weld would span [format %.3f [expr {$wq15_wx1 - $wq15_wx0}]] um (> $WQ15_MAX_SPAN) -- that is a power route, not a weld; refusing"
        } else {
            # opposite-net clearance gate: nothing on the same layer may come
            # within WQ15_OPP_SPACING of the proposed rect.  This is the guard
            # that makes a long/mis-aimed weld impossible rather than unlikely.
            # SCOPE, stated so it is not mistaken for more than it is: it walks
            # the opposite net's M7 sWires only.  That is complete HERE because
            # this runs pre-placement, so the only M7 in the design is the PG
            # fabric, and every VDD via7 M7 enclosure sits inside its own 5 um
            # stripe (measured).  It would NOT be complete if this block were
            # ever moved after routeDesign.
            set wq15_viol {} ; set wq15_near 1.0e9
            foreach b [wq15_boxes $WQ15_OPP $WQ15_LAYER] {
                lassign $b ox0 oy0 ox1 oy1
                set dx [expr {max($ox0 - $wq15_wx1, $wq15_wx0 - $ox1)}]
                set dy [expr {max($oy0 - $wq15_wy1, $wq15_wy0 - $oy1)}]
                if {$dx > 0.0 && $dy > 0.0} { set d [expr {sqrt($dx*$dx + $dy*$dy)}] } \
                elseif {$dx > 0.0}          { set d $dx } \
                elseif {$dy > 0.0}          { set d $dy } \
                else                        { set d 0.0 }
                if {$d < $wq15_near} { set wq15_near $d }
                if {$d < $WQ15_OPP_SPACING} { lappend wq15_viol $b }
            }
            if {[llength $wq15_viol] > 0} {
                set wq15_reason "REFUSED -- proposed rect \[$wq15_wx0 $wq15_wy0 $wq15_wx1 $wq15_wy1\] comes within $WQ15_OPP_SPACING um of $WQ15_OPP $WQ15_LAYER at [lindex $wq15_viol 0] (nearest [format %.3f $wq15_near] um). A weld that touches the opposite rail is a VDD-VSS SHORT."
            } else {
                add_shape -net $WQ15_NET -layer $WQ15_LAYER \
                    -rect [list $wq15_wx0 $wq15_wy0 $wq15_wx1 $wq15_wy1] \
                    -shape STRIPE -status ROUTED
                set wq15_added 1
                puts "### UNL STATUS ### : WQ15 weld added -- $WQ15_NET $WQ15_LAYER x\[$wq15_wx0,$wq15_wx1\] y\[$wq15_wy0,$wq15_wy1\] (x-gap bridged [format %.3f $wq15_gap] um ; nearest $WQ15_OPP $WQ15_LAYER [format %.3f $wq15_near] um, rule $WQ15_OPP_SPACING)"
            }
        }
    }
}
if {$wq15_nowork} {
    puts "### UNL STATUS ### : WQ15 no weld needed -- $wq15_reason"
} elseif {!$wq15_added} {
    puts "### UNL WARN ### : WQ15 weld NOT added -- $wq15_reason"
    puts "### UNL WARN ### : $WQ15_PAD's core-side supply hookup is therefore OPEN. That is deliberate: an open is visible to verifyConnectivity and to LVS-by-inspection, whereas the old floating literal rect hid the SAME open behind 2 ANTENNA markers + 2 IMPVFC-94 dangling wires."
}

################################################################################
# WQ-DELTA 10: PG-fabric baseline + reusable global count guard.
# CLAUDE.md's editDelete class: a bare `editDelete` wipes EVERY wire and special
# wire in the design, and dbDeleteObj returns rc=0 while cutting via structs.
# Record the size of the PG fabric now -- complete, and before any signal
# routing exists -- and gate on it before EVERY saveDesign (this flow writes
# three DBs plus the final one, vs the Stage-I wound chip's two).
# NB `dbGet ... -e` returns the literal 0x0 on an empty result; llength of that
# is 1, so it is normalized here.
################################################################################
proc __wq_count {path} {
	set r [dbGet $path -e]
	if {$r eq "0x0" || $r eq ""} { return 0 }
	return [llength $r]
}
set PG_SWIRES_BASE [__wq_count top.nets.sWires]
set PG_INSTS_BASE  [__wq_count top.insts.name]
puts "### UNL STATUS ### : PG baseline -- $PG_INSTS_BASE insts, $PG_SWIRES_BASE special wires"
if {$PG_SWIRES_BASE == 0 || $PG_INSTS_BASE == 0} {
	puts "FATAL (count guard): PG fabric or instance list is EMPTY after power build."
	exit 1
}

# $tag is printed with the census. `top.wires` is NOT a dbGet path -- signal
# wires live under top.nets.wires (same for sWires); getting that wrong is how a
# corpse passes for a design. `want_wires` is 0 before routing exists.
proc __wq_guard {tag {want_wires 1}} {
	global PG_SWIRES_BASE PG_INSTS_BASE
	set gi [__wq_count top.insts.name]
	set gs [__wq_count top.nets.sWires]
	set gw [__wq_count top.nets.wires]
	# TRNG rings, re-censused BY NAME (not by saved pointers: dbGet on a pointer
	# whose object was deleted can error rather than return 0x0).
	set gr 0
	foreach __pat {mcu0/u_ro/* mcu0/trng0/u_ro/* mcu0/*u_ro/* mcu0/*u_ro*} {
		set __r [dbGet top.insts.name $__pat -e]
		if {$__r eq "0x0" || $__r eq ""} { continue }
		set __n [llength $__r]
		if {$__n > $gr} { set gr $__n }
	}
	puts "### UNL STATUS ### : census \[$tag\] -- insts $gi (base $PG_INSTS_BASE), sWires $gs (base $PG_SWIRES_BASE), wires $gw, TRNG ring cells $gr"
	if {$gi == 0 || $gs == 0} {
		puts "FATAL (count guard) \[$tag\]: insts/sWires collapsed -- refusing to saveDesign a gutted database."
		exit 1
	}
	if {$want_wires && $gw == 0} {
		puts "FATAL (count guard) \[$tag\]: signal-wire count is ZERO after routing."
		exit 1
	}
	if {$gs < [expr {$PG_SWIRES_BASE / 2}]} {
		puts "FATAL (count guard) \[$tag\]: special-wire count $gs is less than half the post-power baseline $PG_SWIRES_BASE -- PG fabric was destroyed."
		exit 1
	}
	if {$gr > 0 && $gr < 210} {
		puts "WARNING (TRNG RO) \[$tag\]: census $gr ring cells (< 210) -- entropy path may have been optimized."
	}
}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

################################################################################
# DB-level PG verification (PG2-F1 rule: prove hookup from the DB, not the log).
# Written to rpt/MCU_castalia.pgcheck.rpt and echoed to the log.
################################################################################
set fh [open $REPORT_DIR/$BASENAME.pgcheck.rpt w]
proc pgputs {fh s} { puts $fh $s; puts "### PGCHK ### $s" }

proc box_isect {a b} {
    lassign $a ax0 ay0 ax1 ay1
    lassign $b bx0 by0 bx1 by1
    return [expr {$ax0 <= $bx1 && $bx0 <= $ax1 && $ay0 <= $by1 && $by0 <= $ay1}]
}
proc swires_over {netname bbox} {
    set n 0
    set netp [dbGet -p top.nets.name $netname]
    foreach w [dbGet $netp.sWires] {
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        if {[box_isect $b $bbox]} { incr n }
    }
    return $n
}
proc inst_bbox {inst} {
    set ip [dbGet -p top.insts.name $inst]
    if {$ip eq "0x0" || $ip eq ""} { return {} }
    set b [dbGet $ip.box]
    if {[llength $b] == 1} { set b [lindex $b 0] }
    return $b
}

pgputs $fh "== MCU_castalia PG verification (CQ3a method) =="
pgputs $fh "DESIGN box: 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT   TOP_NF=$TOP_NF BOT_NF=$BOT_NF  stripe band=[list $STRIPE_Y0 $STRIPE_Y1]"
pgputs $fh "cq8a fixes: M7 start_offset=$M7_START_OFFSET (+$M7_PHASE_SHIFT) ; under-window rails top=[list $UWR_TOP_Y0 $UWR_TOP_Y1] bot=[list $UWR_BOT_Y0 $UWR_BOT_Y1] ; irq_gf halo=$GF_HALO"

set BAND_LO $BAND_Y0 ; set BAND_HI $BAND_Y1
foreach net {VDD VSS} {
    set netp [dbGet -p top.nets.name $net]
    set best_band 0 ; set best_top 0 ; set best_bot 0
    set m8 0 ; set m7 0
    foreach w [dbGet $netp.sWires] {
        set l "?"; catch { set l [dbGet $w.layer.name] }
        if {$l eq "M8"} { incr m8 } elseif {$l eq "M7"} { incr m7 } else { continue }
        if {$l ne "M8"} { continue }
        set b {}; catch { set b [dbGet $w.box] }
        if {[llength $b] == 1} { set b [lindex $b 0] }
        if {[llength $b] != 4} { continue }
        lassign $b x0 y0 x1 y1
        if {![string is double -strict $x0] || ![string is double -strict $y0]} { continue }
        set span [expr {$x1 - $x0}]
        set yc   [expr {($y0 + $y1) / 2.0}]
        if {$yc >= $BAND_LO && $yc <= $BAND_HI && $span > $best_band} { set best_band $span }
        if {$yc >= [expr {$STRIPE_Y1 - 60}] && $span > $best_top} { set best_top $span }
        if {$yc <= [expr {$STRIPE_Y0 + 60}] && $span > $best_bot} { set best_bot $span }
    }
    pgputs $fh "ring-closure $net : CENTER-BAND full-width M8 span=[format %.1f $best_band]um (=the closure, target ~$DESIGN_WIDTH) ; under-window partials TOP=[format %.1f $best_top] BOT=[format %.1f $best_bot]"
    pgputs $fh "mesh $net : M8 sWires=$m8  M7 sWires=$m7"
}

# Flipped-tile + macro physical PG straps. The MX/R180 (bottom, Y-mirrored)
# tiles are the physical problem class -- if their PG pins strap, VDD>0 AND
# VSS>0 here.
foreach t $QTILES {
    lassign $t inst tx ty orient face
    set bb [inst_bbox $inst]
    if {$bb eq {}} { pgputs $fh "tile $inst : INSTANCE NOT FOUND"; continue }
    pgputs $fh "tile $inst ($orient,$face) bbox=$bb : VDD sWires=[swires_over VDD $bb]  VSS sWires=[swires_over VSS $bb]"
}
foreach inst {mcu0/shbank0 mcu0/shbank1 mcu0/shbank2 mcu0/shbank3 mcu0/npuram0 mcu0/rom0 mcu0/por mcu0/dco0 mcu0/dco1 mcu0/irq_gf0 mcu0/irq_gf1 mcu0/irq_gf2 mcu0/irq_gf3 mcu0/hart0/tile/ram0} {
    set bb [inst_bbox $inst]
    if {$bb eq {}} { pgputs $fh "macro $inst : NOT FOUND"; continue }
    pgputs $fh "macro $inst bbox=$bb : VDD sWires=[swires_over VDD $bb] VSS sWires=[swires_over VSS $bb]"
}

################################################################################
# CP4b TODO 4 -- ORCHESTRATOR PG COVERAGE (always-on plain VDD/VSS).
# The design carries NO power intent: `globalNetConnect ... -inst *` binds every
# pgpin in the netlist, hart0 included, to the unswitched VDD/VSS. What has to
# be PROVEN from the DB (PG2-F1 rule: never from the log) is that the band's
# follow-pin + stripe fabric actually REACHES the new flank and the new macro --
# the sroute corePin/blockPin passes above are area-capped to
# [0,$BOT_NF,$DESIGN_WIDTH,$TOP_NF] and the flank sits inside that, but "should"
# is what PG2-F1 shipped three times.
################################################################################
set ORCH_FLANK_BOX [list $ORCH_FLANK_X0 $ORCH_FLANK_Y0 $ORCH_FLANK_X1 $ORCH_FLANK_Y1]
set orch_vdd [swires_over VDD $ORCH_FLANK_BOX]
set orch_vss [swires_over VSS $ORCH_FLANK_BOX]
pgputs $fh "orch flank $ORCH_FLANK_BOX : VDD sWires=$orch_vdd  VSS sWires=$orch_vss"
set orch_mbb [inst_bbox mcu0/hart0/tile/ram0]
if {$orch_mbb eq {}} {
    pgputs $fh "orch TCM : INSTANCE NOT FOUND"
    puts "FATAL (CP4b TODO 4): mcu0/hart0/tile/ram0 not in the design."
    exit 1
}
set orch_mvdd [swires_over VDD $orch_mbb]
set orch_mvss [swires_over VSS $orch_mbb]
pgputs $fh "orch TCM bbox=$orch_mbb : VDD sWires=$orch_mvdd VSS sWires=$orch_mvss"
# power-intent negative check: this flow must contain NO switched rail at all.
set __pgnets {}
catch { set __pgnets [dbGet top.nets.name -e] }
set __sw 0
foreach __n $__pgnets { if {[string match "*VDD_SW*" $__n] || [string match "*PD_*" $__n]} { incr __sw } }
pgputs $fh "orch power intent : switched/PD-class nets in the design = $__sw (want 0 -- CP1 D2 always-on)"
if {$__sw != 0} {
    puts "FATAL (CP4b TODO 4): $__sw switched-rail/PD nets present -- the orchestrator must be ALWAYS-ON."
    exit 1
}
if {$orch_vdd == 0 || $orch_vss == 0 || $orch_mvdd == 0 || $orch_mvss == 0} {
    puts "FATAL (CP4b TODO 4): PG fabric does not reach the orchestrator flank/TCM (VDD $orch_vdd/$orch_mvdd VSS $orch_vss/$orch_mvss)."
    exit 1
}
close $fh
puts "### UNL STATUS ### : PG verification written to $REPORT_DIR/$BASENAME.pgcheck.rpt"

verifyConnectivity \
    -nets {VDD VSS} \
    -type special \
    -error 100000 \
    -report $REPORT_DIR/$BASENAME.verifyConnectivity.pg.rpt

# Parse the special-net opens and test whether any lie inside the FLIPPED
# bottom-tile bboxes (hart3/hart4) or the macro bboxes -> authoritative
# "the PG pin is physically connected" evidence.
set fh2 [open $REPORT_DIR/$BASENAME.pgcheck.rpt a]
set checkboxes {}
foreach t $QTILES { lassign $t inst tx ty orient face; lappend checkboxes [list $inst [inst_bbox $inst]] }
foreach inst {mcu0/shbank0 mcu0/npuram0 mcu0/rom0 mcu0/irq_gf3 mcu0/hart0/tile/ram0} { lappend checkboxes [list $inst [inst_bbox $inst]] }
array set opencnt {}
foreach cb $checkboxes { set opencnt([lindex $cb 0]) 0 }
set total_opens 0
if {[catch {open $REPORT_DIR/$BASENAME.verifyConnectivity.pg.rpt r} vf] == 0} {
    foreach line [split [read $vf] "\n"] {
        if {[regexp {opens at \(([-0-9.]+), *([-0-9.]+)\) *\(([-0-9.]+), *([-0-9.]+)\)} $line -> ax ay bx by]} {
            incr total_opens
            set ob [list $ax $ay $bx $by]
            foreach cb $checkboxes {
                if {[lindex $cb 1] ne {} && [box_isect $ob [lindex $cb 1]]} {
                    incr opencnt([lindex $cb 0])
                }
            }
        }
    }
    close $vf
}
pgputs $fh2 "-- special-net opens: total=$total_opens (pad-ring/slack cosmetic class expected; C0 baseline 703)"
foreach cb $checkboxes {
    pgputs $fh2 "   opens inside [lindex $cb 0] bbox = $opencnt([lindex $cb 0])   (0 = PG pins strapped)"
}
close $fh2

# verifyGeometry with the analog-window + seal ROUTE blockages removed, to
# isolate REAL shorts from the transient tile-finger-pin-vs-window-blk class.
# PLACE blockages stay. Re-created after.
deleteAllRouteBlks
verifyGeometry \
    -error 10000 -warning 10000 \
    -report $REPORT_DIR/$BASENAME.verifyGeometry.noblk.rpt
# restore the route keep-outs into the saved DB
seal_keepouts
set h 0
foreach t $QTILES {
    lassign $t inst tx ty orient face
    lassign [lindex $WINDOW_BOXES $h] WX0 WY0 WX1 WY1
    createRouteBlk -name analog_win_rt$h -box [list $WX0 $WY0 $WX1 $WY1] -layer {1 2 3 4 5 6 7 8}
    incr h
}
# Reserve M7/M8 for power during signal routing -- FULL DIE frame (keeps signal
# routing off M7/M8 over the pad band too).
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 7
createRouteBlk -box $DIE_LLX $DIE_LLY $DIE_URX $DIE_URY -layer 8

################################################################################
# Save the floorplan+PG DB + a DEF for external PG inspection.
################################################################################
__wq_guard "floorplan_pg" 0
saveDesign $DATABASE_DIR/$BASENAME.floorplan_pg.innovus -def -netlist
defOut -floorplan -routing $OUTPUT_DIR/$BASENAME.floorplan_pg.def
puts "### UNL STATUS ### : saved DB + DEF (floorplan+PG stage)"

################################################################################
# ======================= PLACE / CTS / ROUTE / SIGNOFF ======================
# One continuous session (a saved-DB restore FATALs in tapeOut check mode
# against the timing-less pad cells -- CQ4/A7 finding). Gated by RUN_PNR so a
# floorplan-only reproduction is still possible (innovus ... -files <this> with
# RUN_PNR pre-set to 0). Entering here the route blockages present = seal band
# + 4 analog windows + die-frame M7 + die-frame M8.
################################################################################
if {![info exists RUN_PNR]} { set RUN_PNR 1 }
if {$RUN_PNR} {
    printStatus "entering placement"

    # WQ-DELTA 13: spurious clock-gating checks on the TIMER ClockMuxGlitchFree
    # select legs. Gate names are genus-mapped and netlist-dependent, so the
    # catch-skip keeps the flow alive (the disable only suppresses a false
    # gating-check; it never gates route/verify/sim).
    # WOUND NOTE: `g11710` DOES exist in genus/out/MCU_WOUND_hier.genus.v (3
    # hits), one of them inside module TIMER_1 -- so ONE of the two entries
    # below should resolve on this netlist and the other will print SKIPPED.
    # (The Stage-I chip_top_wound header says "0 hits"; that was measured on
    # the FLAT genus/out/MCU_WOUND.genus.v, a different mapping.) After the
    # first postRoute hold signoff, read the real violating endpoint out of
    # $BASENAME.report_timing.hold.signoff.rpt and replace this list.
    set_interactive_constraint_modes [all_constraint_modes -active]
    foreach g {mcu0/timer0/g11710 mcu0/timer1/g11710} {
        if {[catch {set_disable_clock_gating_check $g} r]} {
            puts "### UNL WARN ### : gating-check disable SKIPPED for $g: $r"
        } else {
            puts "### UNL STATUS ### : gating-check disabled on $g"
        }
    }
    set_interactive_constraint_modes {}

    ############################################################################
    # WQ-DELTA 9: TRNG0 ring-oscillator ensemble preserve gate.
    #
    # The wound SoC carries a REAL ring-oscillator ensemble (TrngRoEnsemble
    # `u_ro`): 8 rings of prime stage counts {13,17,19,23,29,31,37,41} = 202
    # preserved inverters + 8 NAND enables = 210 cells that are DELIBERATE
    # COMBINATIONAL LOOPS. The SDC carries set_dont_touch, but that is a
    # TIMING-side attribute; the DB attribute is what stops place_opt / ccopt /
    # optDesign resizing, cloning or deleting a ring stage -- and THIS IS A FLAT
    # RUN, so every one of those engines sees the rings. Set it the
    # hart_tile.innovus.tcl way: `dbSet <inst>.dontTouch true`, NOT setAttribute
    # (-dont_touch is not an option in 20.12, IMPTCM-48).
    #
    # PATTERN NOTE (delta vs the Stage-I chip_top_wound flow): in
    # genus/out/MCU_WOUND_hier.genus.v the ensemble is instantiated at MCU level
    # as a SIBLING of trng0 (`TrngRoEnsemble u_ro`, inside `module MCU`), NOT
    # inside trng0 -- so the correct chip path is mcu0/u_ro/*. That pattern is
    # tried FIRST here; the Stage-I patterns are kept after it as a union so a
    # genus regroup cannot break the gate. FATAL only on a ZERO total.
    ############################################################################
    set RO_SEEN [list]
    set RO_N 0
    foreach __pat {mcu0/u_ro/* mcu0/trng0/u_ro/* mcu0/*u_ro/* mcu0/*u_ro*} {
        foreach __ri [dbGet -p top.insts.name $__pat -e] {
            if {$__ri eq "0x0" || $__ri eq ""} { continue }
            if {[lsearch -exact $RO_SEEN $__ri] >= 0} { continue }
            lappend RO_SEEN $__ri
            dbSet $__ri.dontTouch true
            incr RO_N
        }
    }
    puts "### UNL STATUS ### : TRNG RO preserve -- dontTouch set on $RO_N u_ro instances (want >= 210)"
    if {$RO_N == 0} {
        puts "FATAL (TRNG RO): no u_ro instances found under mcu0 -- the ring ensemble is absent or renamed."
        exit 1
    }
    if {$RO_N < 210} {
        puts "WARNING (TRNG RO): only $RO_N ring cells found (expect 202 inverters + 8 NAND enables = 210) -- verify against the genus post-map census before trusting entropy."
    }

    addWellTap \
        -cell FILLTIE2A10TH \
        -cellInterval 24 \
        -fixedGap \
        -checkerBoard \
        -prefix WELLTAP

    ############################################################################
    # CPR6: THE ORCHESTRATOR ram0 CLOCK MUX'S SPURIOUS ClockMuxGlitchFree CHECK,
    # AT CHIP LEVEL. This is the hart_tile flow's CPR5 fix
    # (hart_tile.innovus.tcl `cpr5_disable_ram_clk_mux_check`), ported to the
    # SOFT orchestrator -- the one copy of the tile RTL that Innovus places and
    # clock-trees itself, and therefore the one copy the tile's own fix cannot
    # reach.
    #
    # MEASURED COST OF NOT DOING IT (the first CPR6 P&R, 2026-08-15, whole run
    # on record): ccopt built the orchestrator's clk_cpu0 tree with insertion
    # delay 0.006 -> 3.548 ns, i.e. SKEW 3.542 ns against the CP5 reference cut's
    # 0.053 ns on the same clock -- the mux is read as a clock gate, so the
    # tx_sel logic is dragged into the clock tree. Downstream: postRoute hold
    # WNS -19.953 ns / TNS -2749 ns over 2316 paths (53 of them the gating check
    # itself at -19.953, i.e. half the 40 ns period; the other 2263 reg2reg at
    # up to -2.141 ns, the skew cashing out), and postCTS setup 74 violating
    # where the CP5 reference had ZERO. The CP-era cut never saw this because
    # its orchestrator predates CPR2's external TCM port and had no ram0 mux.
    #
    # WHY THE CHECK IS SPURIOUS is hart_tile.vhd's argument, unchanged by where
    # the cells sit: tx_ext_clk is low except for one pulse at the edge leaving
    # TX_READ, and clk_mem(1) is low across both switch instants because the
    # core's clk_cpu has been gated off since the lead cycle. A mux whose two
    # inputs are both low at the switch instant cannot glitch.
    #
    # Gate names are SYNTH-RUN DEPENDENT, so they are DERIVED from the DB (the
    # Argus timer disable silently no-op'd for a whole spin when a re-synth
    # renamed the hardcoded gate). Anchor = ram0's CLK PIN, never a net name.
    ############################################################################
    proc cpr6_disable_orch_ram_clk_mux_check {inst tag fatal} {
        set __ram0 [dbGet -p top.insts.name $inst]
        if {$__ram0 == 0x0} {
            puts "FATAL (CPR6): $inst is not in the design -- the orchestrator TCM is missing."
            exit 1
        }
        set __rc 0x0
        foreach __t [dbGet $__ram0.instTerms] {
            if {[dbGet $__t.name] eq "$inst/CLK"} { set __rc [dbGet $__t.net] }
        }
        if {$__rc == 0x0} {
            puts "FATAL (CPR6): $inst/CLK has no net -- the CPR2 ram0 clock mux is missing from this netlist."
            exit 1
        }
        set __g {}
        foreach __t [dbGet $__rc.instTerms] {
            set __i [dbGet $__t.inst]
            set __hit 0
            foreach __nn [dbGet $__i.instTerms.net.name] {
                if {[string match *tx_sel* $__nn]} { set __hit 1 }
            }
            if {$__hit} { lappend __g [dbGet $__i.name] }
        }
        # one hop back through the mux's OWN internal nets -- never through the
        # SELECT net itself, whose fanout is the whole 6-pin mux and the tx FSM
        foreach __gg $__g {
            set __ii [dbGet -p top.insts.name $__gg]
            if {$__ii == 0x0} { continue }
            foreach __t [dbGet $__ii.instTerms] {
                set __n2 [dbGet $__t.net]
                if {$__n2 == 0x0} { continue }
                if {[string match *tx_sel* [dbGet $__n2.name]]} { continue }
                if {$__n2 == $__rc} { continue }
                foreach __t2 [dbGet $__n2.instTerms] {
                    set __i2 [dbGet $__t2.inst]
                    set __hit2 0
                    foreach __nn [dbGet $__i2.instTerms.net.name] {
                        if {[string match *tx_sel* $__nn]} { set __hit2 1 }
                    }
                    if {$__hit2} { lappend __g [dbGet $__i2.name] }
                }
            }
        }
        set __g [lsort -unique $__g]
        puts "### UNL STATUS ### : CPR6 orch ram_clk mux gates ($tag): $__g"
        if {[llength $__g] < 1 || [llength $__g] > 6} {
            if {$fatal} {
                puts "FATAL (CPR6): ram_clk mux derivation found [llength $__g] gates (expect 2 -- the tx_sel NAND and the OAI driving ram_clk)."
                exit 1
            }
            puts "### UNL STATUS ### : CPR6 re-apply ($tag) found [llength $__g] gates -- skipped; the pre-place disable stands and the tx_sel DLY gate is the proof."
            return
        }
        set_interactive_constraint_modes [all_constraint_modes -active]
        foreach __m $__g {
            if {[catch {set_disable_clock_gating_check $__m} __r]} {
                puts "### UNL STATUS ### : CPR6 gating-check disable SKIPPED for $__m ($tag): $__r"
            } else {
                puts "### UNL STATUS ### : CPR6 gating-check disabled on $__m ($tag)"
            }
        }
        set_interactive_constraint_modes {}
    }
    cpr6_disable_orch_ram_clk_mux_check mcu0/hart0/tile/ram0 preplace 1

    place_opt_design
    printStatus "placement done"

    ############################################################################
    # CP4b TODO 2 (verification half): orchestrator containment census.
    # createRegion is a SOFT constraint, so measure what the placer actually
    # did instead of trusting the directive. Anything outside the flank is
    # reported; a gross smear (< 50 % contained) is fatal, because it means the
    # region was ignored and the orchestrator is spread over the whole band.
    ############################################################################
    set orch_in 0 ; set orch_out 0 ; set orch_ox0 1e9 ; set orch_oy0 1e9 ; set orch_ox1 -1e9 ; set orch_oy1 -1e9
    foreach __ip [dbGet -p top.insts.name mcu0/hart0/* -e] {
        if {$__ip eq "0x0" || $__ip eq ""} { continue }
        set __b [dbGet $__ip.box]
        if {[llength $__b] == 1} { set __b [lindex $__b 0] }
        if {[llength $__b] != 4} { continue }
        lassign $__b __x0 __y0 __x1 __y1
        if {$__x0 < $orch_ox0} {set orch_ox0 $__x0} ; if {$__y0 < $orch_oy0} {set orch_oy0 $__y0}
        if {$__x1 > $orch_ox1} {set orch_ox1 $__x1} ; if {$__y1 > $orch_oy1} {set orch_oy1 $__y1}
        if {$__x0 >= [expr {$ORCH_FLANK_X0 - 0.5}] && $__x1 <= [expr {$ORCH_FLANK_X1 + 0.5}] &&
            $__y0 >= [expr {$ORCH_FLANK_Y0 - 0.5}] && $__y1 <= [expr {$ORCH_FLANK_Y1 + 0.5}]} {
            incr orch_in
        } else { incr orch_out }
    }
    set orch_tot [expr {$orch_in + $orch_out}]
    set orch_pct 0.0
    if {$orch_tot > 0} { set orch_pct [expr {100.0 * $orch_in / $orch_tot}] }
    puts "### UNL STATUS ### : hart0 containment -- $orch_in inside / $orch_out outside the flank ([format %.2f $orch_pct] %), placed bbox = [list $orch_ox0 $orch_oy0 $orch_ox1 $orch_oy1]"
    if {$orch_tot == 0} {
        puts "FATAL (CP4b TODO 2): no mcu0/hart0/* instances found after placement."
        exit 1
    }
    if {$orch_pct < 50.0} {
        puts "FATAL (CP4b TODO 2): only [format %.2f $orch_pct] % of the orchestrator landed in its region -- the placer smeared hart0 across the band."
        exit 1
    }
    if {$orch_pct < 95.0} {
        puts "### UNL WARN ### : [format %.2f $orch_pct] % containment (< 95) -- region pull was weak; check congestion before signing this cut off."
    }

    __wq_guard "place" 0
    saveDesign $DATABASE_DIR/$BASENAME.place.innovus -def -netlist

    ############################################################################
    # Clock tree synthesis -- balances into the four tile clk pins
    ############################################################################
    add_ndr -name CTS_2W2S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.42}
    add_ndr -name CTS_2W1S -width {M2:M6 0.4} -generate_via -spacing {M2:M6 0.21}

    create_route_type -name top_rule   -non_default_rule CTS_2W2S -top_preferred_layer M6 -bottom_preferred_layer M5 -shield_net VSS -bottom_shield_layer M5
    create_route_type -name trunk_rule -non_default_rule CTS_2W2S -top_preferred_layer M4 -bottom_preferred_layer M3 -shield_net VSS -bottom_shield_layer M3
    create_route_type -name leaf_rule  -non_default_rule CTS_2W1S -top_preferred_layer M3 -bottom_preferred_layer M2

    set_ccopt_property -net_type top   route_type top_rule
    set_ccopt_property -net_type trunk route_type trunk_rule
    set_ccopt_property -net_type leaf  route_type leaf_rule
    set_ccopt_property routing_top_min_fanout 10000

    set_ccopt_property buffer_cells   {BUFX0P7BA10TH BUFX0P8BA10TH BUFX11BA10TH BUFX13BA10TH BUFX16BA10TH BUFX1BA10TH BUFX1P2BA10TH BUFX1P4BA10TH BUFX1P7BA10TH BUFX2BA10TH BUFX2P5BA10TH BUFX3BA10TH BUFX3P5BA10TH BUFX4BA10TH BUFX5BA10TH BUFX6BA10TH BUFX7P5BA10TH BUFX9BA10TH}
    set_ccopt_property inverter_cells {INVX0P5BA10TH INVX0P6BA10TH INVX0P7BA10TH INVX0P8BA10TH INVX11BA10TH INVX13BA10TH INVX16BA10TH INVX1BA10TH INVX1P2BA10TH INVX1P4BA10TH INVX1P7BA10TH INVX2BA10TH INVX2P5BA10TH INVX3BA10TH INVX3P5BA10TH INVX4BA10TH INVX5BA10TH INVX6BA10TH INVX7P5BA10TH INVX9BA10TH}
    set_ccopt_property delay_cells    {DLY2X0P5MA10TH DLY4X0P5MA10TH}
    set_ccopt_property use_inverters true
    set_ccopt_property target_max_trans 400ps

    create_ccopt_clock_tree_spec

    ############################################################################
    # CP4b TODO 3 -- the ORCHESTRATOR CLOCK (clk_cpu0).
    #
    # clk_cpu0 is the only chip-level core clock in this design: harts 1-4 take
    # their clk_cpu inside the hardened hart_tile macro, behind the ETM, so ccopt
    # never sees those pins. hart0 is soft, so its gated core clock is a REAL
    # tree here and must be balanced like any other centre-band clock --
    # in/MCU_castalia_penta.sdc line 19:
    #   create_generated_clock -name "clk_cpu0" -divide_by 1
    #     -source [get_pins mcu0/system0/mclk_out]
    #     [get_pins mcu0/hart0/tile/core/clk_cpu]
    #
    # create_ccopt_clock_tree_spec derives the skew groups from the SDC, so the
    # job here is (a) PROVE it derived one for clk_cpu0 -- a missing tree means
    # the orchestrator would run off an unbuffered, unbalanced net -- and (b)
    # give it an explicit skew target. The existence check is skipped (loudly)
    # if the query command itself is unavailable, so a version difference can
    # never fake a pass or fake a failure.
    ############################################################################
    set __sg_query_ok 1
    set __allsg {}
    if {[catch {set __allsg [get_ccopt_skew_groups]} __e]} {
        set __sg_query_ok 0
        puts "### UNL WARN ### : get_ccopt_skew_groups unavailable ($__e) -- clk_cpu0 skew-group check SKIPPED, read rpt/*.report_ccopt_skew_groups.postcts instead."
    }
    if {$__sg_query_ok} {
        set ORCH_SG [lsearch -all -inline $__allsg *clk_cpu0*]
        puts "### UNL STATUS ### : ccopt skew groups = [llength $__allsg] total ; clk_cpu0 groups = $ORCH_SG"
        if {[llength $ORCH_SG] == 0} {
            puts "FATAL (CP4b TODO 3): ccopt derived NO skew group for clk_cpu0 -- the orchestrator clock is not in the clock tree spec."
            puts "  all skew groups: $__allsg"
            exit 1
        }
        foreach __sg $ORCH_SG {
            if {[catch {set_ccopt_property -skew_group $__sg target_skew 0.150} __e2]} {
                puts "### UNL WARN ### : target_skew set SKIPPED for skew group $__sg: $__e2"
            } else {
                puts "### UNL STATUS ### : clk_cpu0 skew group $__sg -- target_skew 0.150 ns"
            }
        }
    }

    ccopt_design
    # CPR6 re-apply (belt and braces): by now CTS has cloned and RENAMED both
    # the select net (tx_sel -> FE_PHC<n>_tx_sel) and the clock net, so the
    # derivation is glob-based and may legitimately land on buffered copies --
    # hence fatal=0. The BINDING proof that the pre-place disable took is the
    # tx_sel DLY-cell gate after optDesign -postRoute, below.
    cpr6_disable_orch_ram_clk_mux_check mcu0/hart0/tile/ram0 postcts 0
    optDesign -postCTS -hold
    # WQ-DELTA 11: full report_power (leakage + dynamic, statistical activity)
    # beside the leakage-only report optDesign writes implicitly. BASENAME-
    # prefixed so no other chip_top* flow can clobber it.
    # Consumed by tools/python/gen_power_dashboard.py.
    catch {report_power -outfile $REPORT_DIR/${BASENAME}_postCTS_full.power}
    timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$BASENAME.timeDesign.postcts
    report_ccopt_clock_trees -file $REPORT_DIR/$BASENAME.report_ccopt_clock_trees.postcts
    report_ccopt_skew_groups -file $REPORT_DIR/$BASENAME.report_ccopt_skew_groups.postcts
    printStatus "CTS done"

    ############################################################################
    # Signal routing
    ############################################################################
    printStatus "running nanoroute"
    setNanoRouteMode \
        -routeTopRoutingLayer 7 \
        -envNumberFailLimit 10 \
        -droutePostRouteSwapVia multiCut \
        -drouteUseMultiCutViaEffort medium \
        -routeAllowPowerGroundPin true \
        -drouteFixAntenna true \
        -routeAntennaCellName "ANTENNA2A10TH" \
        -routeInsertAntennaDiode true \
        -routeInsertDiodeForClockNets true \
        -routeIgnoreAntennaTopCellPin false \
        -routeFixTopLayerAntenna false \
        -drouteAntennaEcoListFile $REPORT_DIR/$BASENAME.routeDesign.diodes.txt \
        -dbSkipAnalog true \
        -drouteEndIteration default
    routeDesign

    optDesign -postRoute -setup -hold
    # SI-aware hold cleanup (M14-proven; 'optDesign -postRoute -si -hold' is
    # OBSOLETE in 20.12 -- IMPOPT-7016 -- so use SIAware delaycal + plain hold).
    setDelayCalMode -SIAware true
    setOptMode -holdTargetSlack 0.01
    optDesign -postRoute -hold
    setOptMode -holdTargetSlack 0

    ############################################################################
    # CPR6 ACCEPTANCE GATE for the orchestrator ram_clk mux disable above (the
    # hart_tile CPR5 gate, ported). If the spurious ClockMuxGlitchFree hold
    # check is still live, the hold fixer answers it with a DLY chain on tx_sel
    # -- and that delay line is not merely wasted area: tx_sel is the ram0 mux
    # SELECT, and delaying it inside a 40 ns period moves the switch instant far
    # enough to invalidate the lead/lag argument the TCM port's correctness
    # rests on. Zero cells is the bar; anything else means the disable did not
    # take and the cut is not trustworthy.
    ############################################################################
    set __txdly [dbGet -p top.insts.name *tx_sel*]
    set __ntxdly 0
    if {$__txdly != 0x0} {
        foreach __d $__txdly {
            if {[string match *DLY* [dbGet $__d.cell.name]]} { incr __ntxdly }
        }
    }
    puts "### UNL STATUS ### : CPR6 orch tx_sel hold-fix delay cells = $__ntxdly (want 0)"
    if {$__ntxdly > 0} {
        puts "FATAL (CPR6): $__ntxdly hold-fix delay cells on the orchestrator's tx_sel -- the"
        puts "              ram_clk mux gating-check disable did NOT take. Aborting before signoff."
        exit 1
    }

    # WQ-DELTA 11: full post-route power (see the postCTS note)
    catch {report_power -outfile $REPORT_DIR/${BASENAME}_postRoute_full.power}

    verifyGeometry \
        -error 10000 \
        -warning 10000 \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute.rpt
    ecoRoute -fix_drc
    verifyGeometry \
        -error 10000 \
        -warning 10000 \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.postroute2.rpt

    deleteAllRouteBlks
    # deleteAllRouteBlks stripped the seal-band keep-outs too; restore ONLY the
    # seal band (C0/CQ5 precedent). Do NOT restore the analog-window ROUTE
    # blocks: the tiles' redundant PG finger pins sit under the notch windows by
    # construction, so a restored window route-block makes verifyGeometry report
    # them as "SHORT: Pin vs Routing Blockage" (the ~244 transient class). The
    # window HARD PLACE blockages survive deleteAllRouteBlks (only route blks are
    # removed) so the notch stays cell-free, and nothing was ever routed into the
    # window (the route block was present through nanoroute).
    seal_keepouts
    addFiller

    # REPAIR WHAT FILLER INSERTION BREAKS (2026-08-17). addFiller runs AFTER the
    # last `ecoRoute -fix_drc` (line ~1672), so until now NOTHING repaired a
    # filler dropped onto existing routing -- the collision went straight into the
    # signoff report. Innovus says so itself in the log, and the message was
    # present and ignored: "Filler mode add_fillers_with_drc is default true ...
    # which may add fillers with violations. Please check the violations for
    # FILLER_incr* fillers and fix them".
    #
    # IT DID NOT BITE UNTIL THE TILE SHRANK, which is why the ordering survived
    # this long. Halving the TCM took the tiles from 660x1050 to 660x880 and grew
    # the centre band by 340 um (~915,000 um2 of new empty area); filler insertion
    # grew with it (+66k instances) and so did the collisions. MEASURED on the
    # cpr6 cut: 598 SHORTs, 594 of them on M1 and 483 involving a FILLER cell, ALL
    # in the core interior (x 534-2598, y 591-1809) and NONE near the pad ring --
    # i.e. squarely the filler class, not the pad-ring bug fixed in the padlist.
    # The old 16 KiB cut had ZERO shorts.
    #
    # Repair rather than avoid: `setFillerMode -add_fillers_with_drc false` is the
    # other option innovus offers, but it prevents the violation by LEAVING GAPS,
    # and gaps in this design are not free -- the M17b dead-rail work and the
    # FILLBIAS well-tap continuity both depend on the filler rows being solid.
    ecoRoute -fix_drc
    verifyGeometry \
        -error 100000 \
        -warning 100000 \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.postfiller.rpt

    ############################################################################
    # Signoff checks + reports
    ############################################################################
    printStatus "verifyConnectivity (signoff)"
    verifyConnectivity \
        -error 100000 \
        -connectPadSpecialPorts \
        -report $REPORT_DIR/$BASENAME.verifyConnectivity.signoff.rpt

    printStatus "verifyGeometry (signoff)"
    # -error/-warning 10000 ADDED 2026-08-17, matching every other verifyGeometry
    # call in this file. Without them this call took the DEFAULT LIMIT OF 1000 and
    # TRUNCATED: innovus printed IMPVFG-103 ("Number of violations exceeds the
    # Error Limit [1000]") as a WARNING among ~600k others, and the signoff report
    # -- the one a reader opens to judge the chip -- said "Total Violations : 1000
    # Viols." as though 1000 were the answer. It is a ceiling, not a measurement,
    # and two different runs both reporting exactly 1000 is what gives it away.
    # The uncapped postroute pass on the same routed design reported 4240.
    verifyGeometry \
        -error 10000 \
        -warning 10000 \
        -antenna \
        -report $REPORT_DIR/$BASENAME.verifyGeometry.signoff.rpt

    setDelayCalMode -SIAware false
    setAnalysisMode -analysisType onChipVariation -cppr both
    printStatus "timeDesign signoff"
    # NB the flow's `timeDesign -si -signoff` Quantus extraction is BROKEN
    # install-wide (EXTGRMP-341 + qrc segfault, silently continued) -- the
    # numbers it prints are postRoute-TQuantus state. Compare within one view,
    # never across cuts. Replicated as-is, deliberately not "fixed" (G1/G2).
    timeDesign \
        -si \
        -signoff \
        -outdir $REPORT_DIR/$BASENAME.timeDesign.signoff.rpt

    report_clock_timing \
        -type skew \
        -nworst 10 > $REPORT_DIR/$BASENAME.report_clock_timing.skew.signoff.rpt

    setAnalysisMode -checkType hold -skew true
    report_timing > $REPORT_DIR/$BASENAME.report_timing.hold.signoff.rpt
    setAnalysisMode -checkType setup -skew true
    report_timing > $REPORT_DIR/$BASENAME.report_timing.setup.signoff.rpt

    reportGateCount -level 2 -outfile $REPORT_DIR/$BASENAME.reportGateCount.signoff.rpt
    summaryReport   -noHtml   -outfile $REPORT_DIR/$BASENAME.summaryReport.signoff.rpt

    # Reset tapeOut check mode BEFORE saving so the routed DB restores cleanly
    # (the floorplan_pg DB carried -tapeOut true and FATALed on restore -- CQ4).
    setCheckMode -tapeOut false
    __wq_guard "signoff" 1
    saveDesign $DATABASE_DIR/$BASENAME.signoff.innovus -def -netlist -rc -tcon

    ############################################################################
    # WQ-DELTA 12: output files.
    #
    # MERGE LIST -- DO NOT ADD out/MCU_WOUND.gds2 (or any assembly GDS) HERE.
    # This is a FLAT run: the whole MCU_WOUND hierarchy is placed and routed IN
    # this design, so its geometry is native to the MCU_castalia struct.
    # The only foreign geometry is the hardened tile (a LEF macro here) and the
    # tphn pads (LEF-only cells). Merging a block GDS would inject a duplicate
    # `MCU` struct plus a second, differently-seeded MCU_VIA* family -- exactly
    # the PG4 same-name struct-hijack class the signoff strmin cellMap exists to
    # prevent. Identical to the DP / C0 / Argus / quad / wound chip flows, all
    # of which merge tile + pads only.
    ############################################################################
    streamOut \
        $OUTPUT_DIR/$BASENAME.gds2 \
        -libName WorkLib \
        -structureName $DESIGN_NAME \
        -stripes 1 \
        -units 1000 \
        -mode ALL \
        -merge [list ../hart_tile/out/hart_tile.gds2 \
                     /opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/gds/tphn65gpgv2od3_sl_210a/mt_2/8lm/tphn65gpgv2od3_sl.gds] \
        -mapFile ../shared/innovus2gds.map

    printStatus "writing SDF (top level)"
    write_sdf $OUTPUT_DIR/$BASENAME.sdf

    printStatus "writing verilog for Xcelium (top level; hart_tile as leaf refs)"
    saveNetlist \
        $OUTPUT_DIR/$BASENAME.xsim.v \
        -excludeCellInst ANTENNA2A10TH

    # Second guard: addFiller / streamOut / saveNetlist ran since the last one.
    __wq_guard "final" 1
    saveDesign $DATABASE_DIR/$BASENAME.final.innovus -def -netlist -rc -tcon

    puts "### UNL STATUS ### : P&R complete -- routed DB + GDS + SDF + xsim netlist saved"
}

# Layout images for orchestrator eyeball -- only when a GUI/display is up (run
# the flow WITHOUT -no_gui under Xvfb). Guarded so the headless signoff run just
# skips them. No DB restore needed (design is live -> no tapeOut-mode replay).
if {![catch {fit}]} {
    catch { redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.full.gif }
    catch { zoomBox 1900 -50 2800 1150 ; redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.hart4_R180.gif }
    catch { zoomBox -50 1550 800 2750 ; redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.hart1_R0.gif }
    catch { zoomBox -50 950 2750 1750 ; redraw ; dumpToGIF $OUTPUT_DIR/$BASENAME.center_band.gif }
    catch { fit ; redraw }
    puts "### UNL STATUS ### : layout GIFs dumped"
}
toc
printStatus "MCU_castalia (wound-patch SoC on the quad floorplan, LQFP-100) complete"
exit
