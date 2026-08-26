################################################################################
# Innovus script -- hart_tile TILE HARDEN (M14 physical flow; M16 U-shape rework)
#
# Derived from the frozen Myshkin ~/vestarv/innovus/tcl/MCU.innovus.tcl, cut
# down to a single-tile block harden and made BATCH-SAFE (no suspend, no GUI
# refresh calls). One hart_tile = vesta core + adddec + one sram1p8k TCM,
# with the M13 depth-1 registered boundary. All four MCU_MP hart instances
# place THIS one hardened block 4x at top level.
#
# Floorplan: 'U'-SHAPED rectilinear die (setObjFPlanPolygon). The base of the
# U holds the mux-8 sram1p8k TCM (319.65 x
# 208.675, bottom-centre) plus all the tile logic; the top-center NOTCH
# is a keep-out reserved for a per-tile analog potentiostat signal chain,
# dropped in at Virtuoso chip assembly. Notch budget (educated guess, 65nm):
#   potentiostat control amp + electrode drivers   ~100 x 150
#   TIA + multi-decade current-mirror gain ranging ~200 x 150
#   bias generators + DAC arrays (BIAS_DB*/ADJ)    ~150 x 150
#   SAR ADC (10b) + dsADC front half               ~250 x 250
#   guard rings / decap / analog routing margin    remainder
#   => 500 x 450 um = 0.225 mm^2 cutout (M17: deepened +100 um for a roomier
#      potentiostat drop-in; SARADC/AFE shared peripherals are gone entirely,
#      so NO digital signal ever leaves for this window -- it is pure analog
#      reserve, wired only at Virtuoso chip assembly).
# The two fingers of the U (80 um wide each) exist to close the tile power
# ring around the notch -- ring band = offset 4 + 2x(width 10) + spacing 4 =
# 28 um per boundary, leaving a ~24 um tap/decap column per finger. They are
# deliberately no wider: their only other job is abutting the analog block.
#
# Tile outline (die coords, 660 x 1050 bbox):
#   (0,0)-(660,0)-(660,1050)-(580,1050)-(580,600)-(80,600)-(80,1050)-(0,1050)
#
# All tile pins on the BOTTOM edge (M4): at Castalia top level the four
# tiles sit in a row at the TOP of the chip (notches opening onto the
# analog pad edge), control plane below them.
#
# Outputs (out/): hart_tile.{gds2,sdf,xsim.v,lef} + hart_tile.ilm/ (ILM) and
# hart_tile.etm_{ss,ff}.lib (per-corner ETM, both-views-active recipe --
# these feed viewdefinition_top.tcl at the assembly level).
################################################################################

source ../shared/constants.tcl
source ../shared/procedures.tcl

# ---------------------------------------------------------------------------
# logPuts -- a `puts` THAT ACTUALLY REACHES log/hart_tile.log.  (2026-08-25)
#
# In Innovus, bare `puts` writes to the CONSOLE ONLY.  The session log is
# written by the tool's own `Puts`, which is what ../shared/procedures.tcl
# selects into $PUTS_STRING and what printStatus's four-hash lines go through.
#
# THIS IS NOT COSMETIC AND IT HAS ALREADY COST TWO INVESTIGATIONS.  Every
# `FATAL (...)` in this file was a bare `puts`, so a run that ABORTED on a
# gate left a log with no FATAL anywhere in it -- and `innovus/common/Makefile`
# judges the run by grepping that log.  When the 2026-08-17 01:50 attempt died
# on PG4/F2b, the only surviving evidence was the NAME of the database it
# saved on the way out (dbs/pg4rep_fail.innovus); the reason existed nowhere on
# disk.  The same trap ate the CPR5 G0 acceptance banner, which computed
# "total 5 non-antenna violations" on the shipped cut and said so to a console
# nobody kept, while a real LVS short went to tape.
#
# Rule for this file from here on: a message a human is meant to ACT on goes
# through logPuts or printStatus.  Bare `puts` is for chatter.
# ---------------------------------------------------------------------------
proc logPuts {text} {
	global PUTS_STRING
	$PUTS_STRING $text
}

set DESIGN_NAME hart_tile

# U-shape geometry. BASE_H sizes the row budget.
#
# SHRUNK 2026-08-16 (USER: "make each tile as small as possible"), and the whole
# shrink is in Y. The 8 KiB TCM macro sram1p8k_hvt_pg is 319.65 x 208.675 against
# the 16 KiB sram1p16k_hvt_pg's 319.65 x 383.085 -- SAME WIDTH, 174.41 um shorter
# -- so the base can lose height and nothing about the X axis moves.
#   DESIGN_HEIGHT 1050 -> 880, so BASE_H 600 -> 430 (NOTCH_D unchanged).
#   tile area  660x1050 - 500x450 = 468,000 um2  ->  660x880 - 500x450 = 355,800 um2
#   i.e. -24.0%, on top of the -29.7% the macro swap already took off the CELL
#   area (measured: 188,667 -> 132,657 um2 at genus).
# 920 WAS TRIED AND HARD-FAILS -- do not "back off to 920" without reading this.
# At 920 the PG4/F1 gate passes (all GPGBUF AO supplies via'd) and F2b links
# repeaters 3 and 2, then dies: "no clear link y to any main strap column for
# repeater pgaorep_1 (6 candidates tried)". The SLEEP-chain AO repeater strapping
# is a per-repeater search over candidate link rows, so it is congestion- and
# height-sensitive in a way that is not monotonic: 880 finds links for all four
# repeaters, 880-with-a-2x-macro-halo fails F1, and 920 fails F2b. Backing the
# height off is therefore NOT reliably the safer direction.
# 880 IS THE HEIGHT THAT COMPLETES. It closes timing
# (setup 0.140 / hold 0.009, antenna clean) but lands 20 signoff-DRC violations
# where the 16 KiB tile had ZERO -- one cell straddling a VDD special wire, two
# tcm_q vias on the macro's top edge, and a tail of M1/M2 router artifacts. None
# is structural, but closing them is an open-ended rip+ecoRoute hunt at ~40 min
# a pass. 920 gives the router back 40 um of height and keeps most of the win.
# The 880 floorplan is recoverable from this file's history if the tiles are
# revisited (they are expected to change again).
# WIDTH IS NOT TOUCHED, deliberately: 660 = NOTCH_W 500 + 2*FINGER_W 80 exactly,
# so the width is pinned by the analog notch contract, not by the digital logic.
# Utilisation after the shrink: ~66k um2 of std cells into ~289k um2 of rows
# (base 660x430 less the halo'd 66.7k macro, plus the two 80x450 fingers) = ~23%,
# still MORE relaxed than the 19% this tile closed at before -- the shrink spends
# the macro's slack, not the router's.
set DESIGN_WIDTH  660
set DESIGN_HEIGHT 880
# NOTCH_D 450 -> 580 (2026-08-17, USER: drive the analog cutout DEEPER into the
# digital tile so the logic band is barely taller than the SRAM). BASE_H falls to
# 300 -- 1.44x the 208.675 um macro -- and the tile becomes an L: SRAM in the
# bottom-left, all hart logic in the band to its RIGHT.
#   analog cutout  500x450 = 225,000 um2  ->  500x580 = 290,000 um2  (+28.9%)
#   tile silicon   355,800 um2            ->  290,800 um2            (-18.3%)
#                                         (-37.9% against the original 16 KiB tile)
# Placement budget: base 660x300 less the 66,704 um2 macro = 131,296 um2 of rows
# for ~43,222 um2 of minimal-ISA logic = ~33% utilisation. That is the tightest
# this tile has ever been placed (it has closed at 19-23%), which is why BASE_H
# is 300 and not the ~230 that "as tall as the SRAM" would literally give: the
# power-switch checkerboard, the well taps and the PG stripes all need row space,
# and this floorplan has already shown it fails LOUDLY (PG4/F1, F2b) when the
# repeaters run out of room. Tighten further only with a run to prove it.
# 580 -> 540 (BASE_H 300 -> 340) after a measured failure, not a guess: at
# BASE_H=300 the SLEEP-chain AO repeaters land at x~117 and x~269, i.e. directly
# OVER the bottom-left macro (x 85-405), so their VDDG straps must find a clear
# M2 window in the 81 um band between the macro top (218.675) and the notch
# floor. There is none -- PG4/F2b aborted with 9 candidate columns and no usable
# link y for pgaorep_2. 340 widens that band to 121 um. The logic band is still
# only 1.63x the macro height, so the L-shape intent stands.
# 540 -> 560 (BASE_H 340 -> 320). THE BINDING CONSTRAINT IS THE AO REPEATER BAND,
# measured across three runs: the SLEEP-chain repeaters land ABOVE the bottom-left
# macro and their VDDG straps need a clear M2 window there. macro top is 218.675,
# so the band is BASE_H-218.675 --
#   BASE_H 300 (81 um)  FAILS  PG4/F2b, even with the refined 0.25 um link search
#   BASE_H 340 (121 um) PASSES all four repeaters link
# 320 (101 um) is the untested middle and is what this round probes. If it fails,
# 340 is the known floor for this PG architecture -- going below it needs the
# repeaters kept OFF the band above the macro, which is a PG redesign, not a
# floorplan tweak.
# 560 -> 540: BASE_H 320 (101 um band) ALSO FAILS -- three of four repeaters
# linked and pgaorep_0 got no VDDG strap piece at all. With 300 (81 um) failing
# too, 340 is now the MEASURED FLOOR for this PG architecture, bracketed on both
# sides. Deeper needs the repeaters kept off the band above the macro.
set NOTCH_D       540
# 80 -> 75 (2026-08-17 round 2). FINGER_W sets NOTCH_W implicitly
# (NOTCH_W = DESIGN_WIDTH - 2*FINGER_W), so narrowing the legs is the ONLY way to
# widen the analog cutout without changing the tile width. 75 is the FLOOR, not a
# preference: the PG3/PG4 M7.S.4 column that feeds the left finger occupies
# x 45-70 and must stay inside the finger.
set FINGER_W      75

# DERIVED, not a literal (2026-08-17). The notch is carved from NOTCH_X0=FINGER_W
# to NOTCH_X1=DESIGN_WIDTH-FINGER_W, so its width has ALWAYS been
# DESIGN_WIDTH-2*FINGER_W; NOTCH_W was a second, independent number used only in
# the printStatus line. Narrowing the fingers to 75 made them disagree and the run
# cheerfully reported "notch (500 x 560)" while carving 510 -- a log that lies
# about the geometry it just built. Derived here so it cannot drift again.
set NOTCH_W       [expr {$DESIGN_WIDTH - 2 * $FINGER_W}]
set BASE_H        [expr {$DESIGN_HEIGHT - $NOTCH_D}]

# Power ring / stripe geometry (Myshkin values).
set POWER_RING_PATH_WIDTH	10.0
set POWER_RING_PATH_SPACING	4.0
set POWER_STRIPE_PATH_WIDTH		5.0
set POWER_STRIPE_PATH_SPACING	4.0
set POWER_STRIPE_SET_TO_SET		[expr {$STD_CELL_HEIGHT * 25}]

set CORE_SPACING	1
set CORE_WIDTH		[expr {$DESIGN_WIDTH - ($CORE_SPACING * 2)}]
set CORE_HEIGHT		[expr {$DESIGN_HEIGHT - ($CORE_SPACING * 2)}]

tic

################################################################################
# Design import and setup
################################################################################
set init_verilog             "$GENUS_DIR/out/$DESIGN_NAME.genus.v"
set init_top_cell            "$DESIGN_NAME"
set init_pwr_net             "VDD"
set init_gnd_net             "VSS"
set init_mmmc_file           "$SCRIPT_DIR/viewdefinition_tile.tcl"

# PG4/PG2-F1 (2026-07-10): the pmk LEF is a patched LOCAL copy. The 2007 kit
# LEF gives the 58 secondary pins (VDDG/VSSG/VNW/VPW) no USE POWER/GROUND
# class, so `globalNetConnect -type pgpin` matches nothing (IMPDB-1221),
# the M17 `-type net` workaround never connected a pin in ANY run
# (IMPDB-1223 -- wrong verb), and `sroute -connect secondaryPowerPin`
# routed nothing (IMPSR-503): VDD_SW shipped SOURCELESS in every harden
# M17..PG3 (dead chip as-built). dbSet term.pgType is rejected
# (IMPDBTCL-216) -- the LEF itself must carry the class. The copy is
# byte-identical to the kit except the 58 added USE lines (+ header).
set init_lef_file	"$STD_CELL_DIR/lef/tsmc_cln65_a10_6X1Z_tech.lef  \
					$STD_CELL_DIR/lef/tsmc65_hvt_sc_adv10_macro.lef \
					../../../std_cells/lef/tsmc65hvt_adv10pmk_macro.USEfix.lef \
					$IP_DIR/sram1p8k_hvt_pg/sram1p8k_hvt_pg.vclef"

################################################################################
# G0 IN-FLOW REPAIR, loaded here so its SELF-TEST runs before the 40 minutes.
#
# tcl/g0_repair.tcl derives the router-vs-cell-OBS M1 merge sites from this
# cut's own verifyGeometry report and from the cell masters' OBS sections in
# the very LEF files listed above, so it needs that list and it needs to be
# checked against something known before the run commits to anything.
# g0r_selftest replays the three archived hand-repaired sites (2026-08-15
# tie_0_cell7, 2026-08-25 tie_0_cell6, 2026-08-25 g11129__6161 and
# registers_reg[30][17]) through the derivation and compares the blockage boxes
# it produces with the boxes those ECOs actually created.
#
# IT IS FATAL ON PURPOSE, and it is fatal HERE rather than at signoff.  A
# derivation that has silently stopped working would otherwise present as
# "0 G0 sites found" at the end of a 40 minute run, which is the exact shape of
# every failure this flow has shipped: a quiet pass that never examined
# anything.  Ten seconds of arithmetic against a frozen answer removes that
# reading entirely.
################################################################################
set G0R_LEF_FILES $init_lef_file
source tcl/g0_repair.tcl
if {![g0r_selftest]} {
	logPuts "FATAL (G0REPAIR): the G0 derivation does not reproduce the three archived repairs."
	logPuts "                  Either the standard-cell LEF changed under it or tcl/g0_repair.tcl is broken."
	logPuts "                  A run started now could only report '0 sites found', which would be a lie."
	exit 1
}

################################################################################
# PG CLEARANCE (2026-08-26).  See tcl/pg_clearance.tcl for the class it closes.
#
# Everything below the post-route verifyGeometry in this file lays power metal
# and power vias beside routing that is already finished, and until this file
# existed not one of those passes measured the space it was leaving.
# The 2026-08-26 via-split cut shipped an M1.S.1 because of it.
#
# The numbers come from signoff_mp/decks/blockdrc.rul at run time, not from a
# constant in a script, and the arithmetic is proved against the two sites that
# cut actually shipped BEFORE the run is allowed to depend on it.
# A derivation that has quietly stopped working would otherwise present as
# "0 sites blocked" forty minutes later, which reads exactly like success.
################################################################################
source tcl/pg_clearance.tcl
if {[pgc_deck_load ../../../signoff_mp/decks/blockdrc.rul] < 100} {
	logPuts "FATAL (PGCLEAR): signoff_mp/decks/blockdrc.rul yielded almost no VARIABLE names."
	logPuts "                 Every post-route clearance check would then be measuring against"
	logPuts "                 nothing and reporting a pass. Aborting."
	exit 1
}
if {![pgc_selftest]} {
	logPuts "FATAL (PGCLEAR): the clearance arithmetic does not reproduce the two 2026-08-26 sites."
	logPuts "                 Either the deck moved under it or tcl/pg_clearance.tcl is broken."
	exit 1
}

set init_design_uniquify 1
init_design

################################################################################
# M17 power intent: the tile CPF (PD_GATED default/shutoff=pd_sleep + PD_AO
# for the ports/iso cells; VDD = always-on, VDD_SW = the switched follow-pin
# net produced by the HEADBUF header fabric). Genus already INSERTED the
# A2ISO clamps (iso_* instances) — Innovus re-reads the same intent for the
# domain/net/switch data and must RECOGNIZE the existing cells, not
# re-insert.
################################################################################
read_power_intent -cpf ../../../cpf/hart_tile.cpf
commit_power_intent
printStatus "Power intent committed (PD_GATED/PD_AO, switched net VDD_SW)"

# CPR5 NEGATIVE RESULT, recorded so nobody re-tries it: adding
# `-bottomRoutingLayer 2` here does NOT remove the G0 router-vs-cell-OBS
# class. MEASURED 2026-08-15 (harden #6 vs #4): the run came out
# BYTE-IDENTICAL (gds 29,498,474 / sdf 19,288,138 / xsim.v 2,739,086 /
# lef 217,938), 15,212 M1 signal wires still present, and the two offending
# shapes unchanged to the nanometre. The M1 that merges with a neighbouring
# cell's internal strap is PIN-ACCESS metal, which the bottom-routing-layer
# mode does not govern. (On setNanoRouteMode the same option is worse than
# useless: ccopt has already routed the clock nets on M1, so it is rejected
# with NRDB-955 and aborts the run mid-route.) See the G0-class repair step
# after optDesign -postRoute for what actually addresses it.
setDesignMode -process 65 -flowEffort standard -powerEffort low
printStatus "Preparing 8 CPU cores..."
setMultiCpuUsage -acquireLicense 8 -localCpu 8

# M17: NO FILLTIE fillers — a rail-tied well tap inside a gated row
# back-feeds the dead VDD_SW rail through the n-well (see the addWellTap
# note). Well-tap duty is carried entirely by the FILLBIAS addWellTap pass;
# fillers are the plain (tapless) FILL cells only.
setFillerMode \
    -corePrefix FILLER \
    -core {FILL128A10TH FILL64A10TH FILL32A10TH FILL16A10TH FILL8A10TH FILL4A10TH FILL2A10TH FILL1A10TH}

setAnalysisMode -analysisType onChipVariation -cppr both

# M17 domain-aware global nets. Follow-pin rails: PD_GATED rows carry the
# SWITCHED net VDD_SW; the PD_AO band carries always-on VDD. ram0 (the TCM)
# stays in PD_GATED logically but its VDD pin ties to the ALWAYS-ON net —
# it self-gates through its native PGEN (pd_sleep is mirrored onto tcm_pgen
# at MCU level), so it needs no share of the switch fabric. Secondary pins:
# every pmk VDDG (HEADBUF supply-in, GPG always-on buffers) ties to VDD;
# the FILLBIAS well taps bias the gated region's wells from the AO rails
# (VNW->VDD, VPW->VSS) so a sleeping row's n-well never back-feeds the dead
# VDD_SW rail through a rail-tied tap (the FILLTIE hazard). PG4 NOTE: the
# FILLBIAS network IS the only well bias — HEADBUF16's CDL bulks tie to
# VNW/VPW (not VDDG), and headers expose no VNW/VPW LEF pin; the old claim
# that "the header cells' body ties hold the well at VDD" was wrong.
clearGlobalNets
# NOTE -powerDomain is a SCOPE and cannot combine with -inst (IMPSYC-957)
globalNetConnect VDD_SW -type pgpin -pin VDD  -powerDomain PD_GATED -autoTie -verbose
globalNetConnect VDD    -type pgpin -pin VDD  -powerDomain PD_AO    -verbose
# THE TCM'S SUPPLIES ARE SPLIT AND ARM-NAMED, and they are NOT VDD/VSS. The
# 16 KiB sram1p16k_hvt_pg exposed one VDD and one VSS; the 8 KiB sram1p8k_hvt_pg
# exposes THREE pins -- VDDPE (periphery), VDDCE (array) and VSSE. Carrying the
# old single-pin rules across the macro swap is not a cosmetic slip: it FAILED
# THE HARDEN OUTRIGHT with IMPDB-1500 ("no such pg pin 'VDD' found in instance
# 'ram0'"), which is the loud version of the PG2-F1 class -- a macro whose power
# was never actually bound, shipped in GDS.
# BOTH VDD pins go to the ALWAYS-ON rail, which is what the 16 KiB macro's single
# VDD did: the TCM takes no share of the switch fabric because it SELF-GATES
# through its native PGEN (pd_sleep is mirrored onto tcm_pgen at MCU level).
# Splitting VDDCE onto VDD_SW would hand the array's retention to the switch
# fabric and defeat that.
globalNetConnect VDD    -type pgpin -pin VDDPE -singleInstance ram0 -override -verbose
globalNetConnect VDD    -type pgpin -pin VDDCE -singleInstance ram0 -override -verbose
globalNetConnect VSS    -type pgpin -pin VSSE  -singleInstance ram0 -override -verbose
globalNetConnect VSS    -type pgpin -pin VSS  -inst * -module {} -autoTie -verbose
# (the pmk secondary pins — VDDG/VNW/VPW — are connected AFTER the switch
# and well-tap cells exist; a rule with zero matching pins is IMPDB-1221)

################################################################################
# Floorplan: U-shaped rectilinear die -- rect first, then carve the notch.
# TCM macro in the bottom-left of the base, pins on the bottom edge.
################################################################################
floorPlan \
    -site TSMC65ADV10TSITE \
    -s $CORE_WIDTH $CORE_HEIGHT $CORE_SPACING $CORE_SPACING $CORE_SPACING $CORE_SPACING

# Carve the top-center analog notch: 8-vertex U polygon (die coords).
# Without EnableRectilinearDesign, setObjFPlanPolygon on the top cell is
# REJECTED (IMPSYT-40516) and the die silently stays rectangular.
setPreference EnableRectilinearDesign 1
set NOTCH_X0 $FINGER_W
set NOTCH_X1 [expr {$DESIGN_WIDTH - $FINGER_W}]
set U_POLY "0 0 $DESIGN_WIDTH 0 $DESIGN_WIDTH $DESIGN_HEIGHT $NOTCH_X1 $DESIGN_HEIGHT $NOTCH_X1 $BASE_H $NOTCH_X0 $BASE_H $NOTCH_X0 $DESIGN_HEIGHT 0 $DESIGN_HEIGHT"
eval "setObjFPlanPolygon Cell $DESIGN_NAME $U_POLY"
initCoreRow
# Defensive: no rows may survive inside the notch (analog keep-out).
cutRow -area [list $NOTCH_X0 $BASE_H $NOTCH_X1 $DESIGN_HEIGHT]
# (M17b: the two switchless-row placement blockages live AFTER the power-
# switch/well-tap passes, NOT here — a blockage visible to addPowerSwitch
# shifts its checkerboard phase and the uncovered rows MOVE. See below.)
printStatus "Carved U-shape notch ($NOTCH_W x $NOTCH_D) at top center"

# The TCM macro's footprint. Named for the ROLE, not the size, since 2026-08-16:
# the old SRAM16K_* names became a lie the moment the 8 KiB macro went in, and a
# constant whose name states the wrong size is how a floorplan silently keeps a
# stale halo. Values are sram1p8k_hvt_pg's LEF SIZE.
set SRAM_TCM_WIDTH		319.650
set SRAM_TCM_HEIGHT		208.675

# TCM IN THE BOTTOM-LEFT (2026-08-17, USER), not centred as M17 left it. The
# point of the L-shape is that ALL hart logic sits to the RIGHT of the macro in
# one band, which a centred macro makes impossible (it splits the rows into two
# useless slivers).
# X IS 85, NOT 0, AND THE 85 IS LOAD-BEARING: the PG3/PG4 M7.S.4 structures own
# x 45-70 (the stripe band) and x 63.5-68.5 (the merge patch) from y=0 up to
# BASE_H-30.25 -- that is the PG column feeding the LEFT analog finger, and it
# must run the full height of the base. A macro at x=10 would sit straight on
# top of it. 85 clears the column by 15 um and still leaves the widest possible
# logic band to the right (x 404.65-660, i.e. 255 um).
# The macro tops out at y=218.675 against a notch floor of BASE_H=300, so it
# clears by 81 um.
# 85 -> 75 (round 2, USER: further left). 75 IS THE MEASURED FLOOR. Probing the
# hardened database for PG metal in the left strip of the base gives:
#     M4/VSS  rightmost x = 83.95
# i.e. the via stack feeding the left analog finger already reaches 83.95, and it
# needs standard-cell rails under it, which cannot exist inside a macro footprint.
# 75 puts the macro's left edge 5 um clear of the M7.S.4 column's x=70 edge and
# lets that stack pull in with it. Going further left means MOVING that PG column,
# which would break the 50 um M7 stripe grid phase it sits on and re-open the
# Calibre-validated M7.S.4 fix -- a PG redesign, not a placement change.
set TCM_X	75.0
set TCM_Y	10
placeInstance ram0 $TCM_X $TCM_Y MX
# HALO STAYS 1x STD_CELL_HEIGHT. Widening it to 2x was TRIED, to chase the two
# tcm_q via shorts on the macro's top edge, and it must not be re-tried without
# reading this: the halo is a GLOBAL placement perturbation, not a local keep-out.
# At 2x the SLEEP-chain repeater count fell from 4 to 2 and pgaorep_0 landed at
# (354.2,225.0) where BOTH M2 strap bands collide, so its VDDG could not be
# strapped at all -- the PG4/F1 gate aborted the run ("dead AO repeaters re-break
# the SLEEP chain"). Cost: a whole harden, to fix 2 violations and create a fatal.
# The via shorts want a LOCAL fix (an M4 route blockage over the macro edge), not
# a halo that moves every cell in the tile.
addHaloToBlock \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    [expr {$STD_CELL_HEIGHT * 1}] \
    ram0
cutRow
printStatus "Placed TCM macro"

# All tile pins spread along the BOTTOM edge on M4 (vertical-preferred):
# the Castalia floorplan puts the tile row at the chip top, control plane
# below, so every digital connection leaves through the base of the U.
set ALL_PINS [dbGet top.terms.name]
logPuts "Assigning [llength $ALL_PINS] pins to the bottom edge"
editPin -pin $ALL_PINS -side Bottom -layer 4 -spreadType side -spacing 1 -fixOverlap 1
printStatus "Placed tile pins"

# M17: NO PD_AO fence — PD_AO holds only the boundary PORTS (isolation is
# explicit RTL AND-clamps on the MCU side of the boundary, and the TCM
# macro is AO by pin connection). Every row in the tile is PD_GATED =
# VDD_SW rails; the always-on presence inside the tile is just the VDD
# ring/stripe grid, the switches' VDDG pins, and the FILLBIAS well bias.

################################################################################
# Power: rectilinear ring following the U boundary (incl. both fingers) +
# stripes on M7/M8 (reserved for power via route blockages)
################################################################################
printStatus "Adding power ring/stripes"
addRing \
    -nets {VDD VSS} \
    -type core_rings \
    -follow io \
    -layer {top M8 bottom M8 left M7 right M7} \
    -width $POWER_RING_PATH_WIDTH \
    -spacing $POWER_RING_PATH_SPACING \
    -offset $POWER_RING_PATH_SPACING \
    -center 0 -extend_corner {} -threshold 0 -jog_distance 0 \
    -snap_wire_center_to_grid None

# No keep-out blockage needed for the notch: it is OUTSIDE the rectilinear
# die boundary, so place/route/stripe engines cannot touch it (a routeBlk
# there is even rejected -- IMPFP-184, "cut against design boundary").

setAddStripeMode \
    -remove_floating_stripe_over_block true \
    -trim_antenna_back_to_shape core_ring \
	-stacked_via_top_layer M8 \
    -extend_to_closest_target ring
addStripe \
	-layer M8 \
	-nets {VDD VSS} \
	-direction horizontal \
	-start_from left \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset $POWER_STRIPE_SET_TO_SET \
	-stop_offset $POWER_STRIPE_PATH_SPACING
# PG3 M7.S.4 fix, part 1 of 2: FIRST vertical stripe pair only, one pitch
# left-shifted by 0.5 um (VDD 50.5-55.5, VSS 59.5-64.5; the VSS stripe then
# clears the U-notch inner VDD ring leg at x=66 by the required 1.5 um).
# -start_offset semantics flip between core-relative and area-relative
# depending on -area, so the block is SELF-CHECKING: place, probe the DB,
# retry the other convention, and hard-exit unless column 1 sits exactly at
# 50.5/59.5 (acceptance-gate style -- a silently mis-placed stripe is worse
# than an aborted run). See the M7.S.4 lesson block below for the history.
proc pg3_col1_count {lo hi} {
    set n 0
    foreach sw [dbGet -p2 top.nets.sWires.layer.name M7] {
        set llx [dbGet $sw.box_llx]
        if {$llx >= $lo && $llx <= $hi} { incr n }
    }
    return $n
}
addStripe \
	-layer M7 \
	-nets {VDD VSS} \
	-direction vertical \
	-start_from bottom \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset 5.5 \
	-stop_offset $POWER_STRIPE_PATH_SPACING \
	-area [list 45.0 0.0 70.0 [expr {$BASE_H - 30.25}]]
# NB probe window must EXCLUDE the notch ring legs (llx 52 and 66) -- only
# the new stripe pair's own positions count as success.
# (2026-08-16: the -area top was the literal 569.75, which is BASE_H-30.25 --
#  the notch-floor-relative extent of this finger column, not an absolute.
#  It now tracks BASE_H so the shrink cannot strand the band mid-air.)
if {[pg3_col1_count 50.0 51.2] == 0} {
    printStatus "PG3 M7.S.4: area-relative start_offset placed nothing; retrying core-relative (49.5)"
    addStripe \
	-layer M7 \
	-nets {VDD VSS} \
	-direction vertical \
	-start_from bottom \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset [expr {$POWER_STRIPE_SET_TO_SET - 0.5}] \
	-stop_offset $POWER_STRIPE_PATH_SPACING \
	-area [list 45.0 0.0 70.0 [expr {$BASE_H - 30.25}]]
}
# NB >=1 not ==1: a stripe may come back SEGMENTED as several sWires at the
# same llx (the pair above returned 5 wires) -- ABSENCE is the failure mode.
if {[pg3_col1_count 50.4 50.6] < 1 || [pg3_col1_count 59.4 59.6] < 1} {
    logPuts "### UNL STATUS #### : PG3 M7.S.4 GATE FAILED -- column-1 stripes not at 50.5/59.5"
    exit 99
}

# PG3 M7.S.4 fix, part 2 of 2: the ORIGINAL full-grid pass, starting one
# pitch later so column 1 comes only from the shifted pass above.
addStripe \
	-layer M7 \
	-nets {VDD VSS} \
	-direction vertical \
	-extend_to design_boundary \
	-start_from bottom \
	-set_to_set_distance $POWER_STRIPE_SET_TO_SET \
	-spacing $POWER_STRIPE_PATH_SPACING \
	-width $POWER_STRIPE_PATH_WIDTH \
	-block_ring_bottom_layer_limit M1 \
	-start_offset [expr {$POWER_STRIPE_SET_TO_SET + 50.0}] \
	-stop_offset $POWER_STRIPE_PATH_SPACING

editTrim -all

# PG3 signoff-DRC fix (foundry deck M7.S.4, wide-metal union-projection
# spacing >= 1.5): the FIRST vertical VSS stripe (x 60-65) ends up only
# 1.0 um left of the U-notch ring's inner VDD leg (x 66-76, the left-finger
# band = 80 - offset 4 - width 10). The deck's SIZE-UNDEROVER derivation
# merges that stripe with the notch VSS leg (52-62, 2.25 um away) into ONE
# effective wide shape whose edge faces the VDD leg over its whole run ->
# spacing 1.0 < 1.5 fires. Innovus verifyGeometry can NEVER see this (the
# tech LEF has no union-projection rule) -- found by Calibre blockdrc (PG3).
# LESSONS (each variant tried and thrown out):
#  * shifting the WHOLE stripe grid was recorded here as unsafe because the
#    right-finger mirror (VSS ring leg 598-608 vs full-height VSS stripe
#    610-615, gap 2.0) fails the same rule once the grid moves left by more
#    than 0.5.  THAT PARTICULAR REASON NO LONGER APPLIES: it was measured when
#    FINGER_W was 80, FINGER_W is 75 now, so the right-finger VSS ring leg sits
#    at 603-613 and the full-height VSS stripe at 610-615 OVERLAPS it by 3.0 um
#    instead of clearing it by 2.0.  There is no 2.0 um channel left there for
#    the rule to fire in.  Re-measured on the 2026-08-25 cut's own LEF.
#  * SHIFTING THE GRID IS STILL NOT SAFE, and 2026-08-26 measured why, in a
#    full harden.  Re-phasing the grid by -2.0 um (start_offset 100 -> 98) to
#    land the right-finger VDD column on the notch ring leg's outer edge at
#    x=599 does close the M6.S.4/M7.S.4 riser channel, and it does so for the
#    WRONG REASON: at 599 the engine stops building the M6 jog altogether, so
#    the finger loses its VDD M6 riser column (tile-wide VDD M6 sWires 1 -> 0)
#    and the channel is empty rather than bridged.  The same run also moved
#    enough placement to manufacture a hard SHORT the in-flow ecoRoute could
#    not close (core/controller_inst/md/n_29 vs the VDD_SW row rail at
#    613.5,153.1) plus two M1 SPACING markers, so the G0 gate refused to emit
#    any collateral.  The attempt is kept as tcl/hart_tile.innovus.tcl.pgphase_
#    attempt.  It bought nothing in DRC count either: wm_merge already holds
#    M6.S.4/M7.S.4 at 0 on the shipped cut;
#  * manual surgery (editDelete + add_shape a narrower stripe) LOSES the
#    engine's stacked vias and cannot get them back -- editPowerVia no-ops
#    here (IMPSR-554: the tile's top ROUTING layer is M4, so its -top_layer
#    clamps below the PG layers) -> whole-die VSS opens + dangling wire at
#    the re-added stripe. Caught by the acceptance verifyConnectivity.
# Working form: let addStripe place the first column itself, 0.5 um left
# (VDD 50.5-55.5, VSS 59.5-64.5 -> 1.5 to the ring leg), by splitting the
# one addStripe into an -area pass for column 1 (start_offset 49.5) and the
# original pass starting one pitch later (start_offset +50). Engine-placed
# shapes keep engine-placed stacked vias -- nothing manual to re-stitch.

setCheckMode -globalNet true -io true -route true -tapeOut true

################################################################################
# M17: the MTCMOS header fabric. HEADBUF16M columns inside PD_GATED — only
# the HEADBUF cells have SLEEPOUT and can daisy-chain (plain HEADs cannot,
# M17 recon), and the chain IS the rush-current stagger (~60-90 ps/stage;
# the databook has no explicit inrush rule — pwr_ctrl's T_RAIL=256 mclk
# wake settle covers the whole chain with orders of magnitude to spare).
# VDDG pin (always-on IN) strapped to the VDD grid by the secondary sroute
# below; VDD pin (switched OUT) abuts the row rails = VDD_SW.
################################################################################
printStatus "Inserting MTCMOS header switch columns (HEADBUF16MA10TH)"
# -area is REQUIRED here: PD_GATED is the DEFAULT domain (no fence box), and
# without an explicit area the column engine dies on the empty domain box
# ("can't use non-numeric string as operand of *" — M17 lesson). Columns
# every 80 um with a switch in EVERY row: VDD_SW is a follow-pin-only net
# (no stripe grid), so a row with no switch has a FLOATING rail — IMPPSO-306
# flagged exactly that under -skipRows (the M16 floating-rail lesson, power-
# switch edition). ~2000 HEADBUF16 ≈ 17k um² in a 271k um² row budget.
# -skipRows is REQUIRED (omitting it is the "non-numeric operand" abort —
# the option has no sane default in this build); 0 = a switch in every row.
# -checkerBoard true is LOAD-BEARING (M17b post-mortem, both directions):
#  * WITH it, the stagger leaves exactly two rows switchless — the bottom
#    row (1,1) and the right U-leg top row (581,1047). IMPPSO-306 warns, the
#    run rolls on, and place_opt parked 52 live cells (bnd_irq_* boundary
#    flops, hart_id inverters) on the dead VDD_SW rail. Those two rows are
#    now hard-blocked at floorplan time (see dead_row blockages above) so
#    they stay EMPTY — dead rail, nothing on it.
#  * WITHOUT it (full-density, switch in every row), the DRC drowns: ~1000
#    M1 pin-frame abutment shorts (FILLER/WELLTAP/HEADBUF pmk frames overlap
#    different-net M1 when vertically stacked in consecutive rows) + ~4500
#    IMPVFC-92/94 connectivity problems. Proven by three runs; the stagger
#    is exactly what keeps the pmk frames apart. NB the option is a bare
#    FLAG in this build: `-checkerBoard false` is the same non-numeric-
#    operand abort as a missing -skipRows.
# Acceptance for any future rerun: every IMPPSO-306 row must lie inside a
# dead_row blockage box.
addPowerSwitch -column -powerDomain PD_GATED \
	-globalSwitchCellName {HEADBUF16MA10TH} \
	-area [list $CORE_SPACING $CORE_SPACING [expr {$DESIGN_WIDTH - $CORE_SPACING}] [expr {$DESIGN_HEIGHT - $CORE_SPACING}]] \
	-leftOffset 30 \
	-horizontalPitch 80 \
	-skipRows 0 \
	-checkerBoard true \
	-enableNetIn pd_sleep \
	-enableNetOut pd_sleep_chain_out

# addPowerSwitch FAILS SOFT (IMPPSO-109 and the script rolls on) — a
# zero-switch tile would sail to signoff with an unpowered VDD_SW net and
# only die at the assembly gate sim. Refuse to continue without a fabric.
set NSW [llength [dbGet -p top.insts.cell.name HEADBUF16MA10TH]]
logPuts "### UNL STATUS ### : $NSW HEADBUF16MA10TH power switches inserted"
if {$NSW == 0} {
	logPuts "FATAL (M17): addPowerSwitch inserted ZERO switches — aborting"
	exit 1
}

# M17: well taps move UP here (they lived in the placement section as
# FILLTIE) so their bias pins exist before the secondary sroute. FILLBIAS
# instead of FILLTIE: a rail-tied tap in a gated row ties the n-well — held
# at VDD by the header cells' body ties — to the dead VDD_SW rail and
# back-feeds it through the well, defeating the shutoff.
addWellTap \
    -cell FILLBIASA10TH \
    -cellInterval 24 \
    -fixedGap \
    -checkerBoard \
    -prefix WELLTAP

# (M17b: the two switchless-row placement blockages live IMMEDIATELY BEFORE
# place_opt_design — see there. Not here: visible to sroute they suppress
# the blocked rows' follow-pin rails and strand the well-tap VDD frames.)

# pmk secondary pins, now that the switch + tap instances exist.
# PG4/PG2-F1 LESSON (this exact spot shipped a dead chip three times):
#  * `-type net` here was the M17 "lesson 6" workaround for IMPDB-1221 --
#    but -type net re-parents a NET and NEVER binds pins: it printed
#    IMPDB-1223 in every run while `catch` saw rc=0 (Innovus errors are
#    not tcl errors) and the flow sailed on with all 1027 header VDDG,
#    4 GPGBUF and 7072 FILLBIAS well-bias pins bound to NO net (PG2-F1).
#  * `-type pgpin` is the correct verb and works now BECAUSE the local
#    USEfix pmk LEF (see init_lef_file) gives these pins their USE class.
# The F1 acceptance gate right below fails the run if the binding ever
# silently regresses -- do NOT weaken it.
globalNetConnect VDD -type pgpin -pin VDDG -inst * -module {} -verbose
globalNetConnect VDD -type pgpin -pin VNW  -inst * -module {} -verbose
globalNetConnect VSS -type pgpin -pin VPW  -inst * -module {} -verbose

# PG4 NOTE on gating the LOGICAL binding: it CANNOT be checked here. GNC
# pin bindings live as rules until much later — instTerms/pgNets for PG
# pins are empty even across a save/restore at this point (bring-up
# proven: the rules had just connected 7078 VNW pins while every query
# form read empty). The VDDG rule reporting "0 new" is EXPECTED: the
# switch VDDG pins are claimed by addPowerSwitch itself (CPF
# create_power_switch_rule -external_power_net VDD, per-inst GNC calls in
# the log). The F1 gate is therefore GEOMETRIC, after the secondary
# sroute below — metal is the only truth available in-flow, and metal is
# what PG2-F1 was actually missing.

printStatus "Routing power rails"
setSrouteMode -corePinMaxViaScale "100 10"
# M17: three follow-pin nets now — VDD_SW rails in PD_GATED rows, VDD rails
# in the PD_AO band, VSS everywhere. The M7/M8 stripe grid stays VDD/VSS
# (always-on): VDD stripes drop onto VDD rails and the switches' VDDG pins
# ONLY — the VDD_SW rails are fed exclusively by the switch outputs.
sroute \
	-nets { VSS VDD VDD_SW } \
	-allowLayerChange 0 \
	-allowJogging 0 \
	-connect corePin \
    -corePinWidth 0.3

# M17: secondary PG pins — HEADBUF/GPG VDDG and the FILLBIAS well-bias pins
# (VNW->VDD, VPW->VSS; the taps come from addWellTap below).
# PG4/PG2-F1: `-powerDomains PD_GATED` is REQUIRED — without a domain scope
# this pass exits IMPSR-503 in 0.2 s having routed NOTHING (trigger = the
# CPF power domains + switch cells; the run-9 "GPGBUF triggers 503"
# diagnosis was a misread — it fires with zero GPGBUFs present). Same form
# as the PG1 repeater pass below, which always carried the option.
printStatus "Routing secondary power pins (VDDG / VNW / VPW)"
sroute \
	-nets { VDD VSS } \
	-connect { secondaryPowerPin } \
	-secondaryPinNet { VDD VSS } \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M1(1) M4(4) } \
	-powerDomains PD_GATED

# PG4 F1 acceptance gate (PHYSICAL — catches the IMPDB-1221/1223 rule
# no-ops AND the IMPSR-503/1253 sroute no-ops in one place, because both
# end the same way: no metal on the secondary pins):
#  a) net VDD must hold >> the broken baseline of 50 sWires (ring +
#     stripes only, nothing below M6 = the PG2-F1 signature);
#  b) EVERY HEADBUF footprint must be touched by net-VDD geometry (the
#     VDDG supply-in strap), and EVERY FILLBIAS by net-VDD (VNW) plus
#     non-followpin net-VSS (VPW; followpin rails touch every cell
#     trivially and prove nothing). tile_audit.py --pgdump repeats this
#     check independently on the saved signoff DB.
set __f1_vdd_sw [llength [dbGet [dbGet -p top.nets.name VDD].sWires -e]]
set __f1_vss_sw [llength [dbGet [dbGet -p top.nets.name VSS].sWires -e]]
logPuts "### UNL STATUS ### : PG4 F1 gate a — VDD sWires=$__f1_vdd_sw VSS sWires=$__f1_vss_sw post-secondary-sroute (broken baseline: 50)"
if {$__f1_vdd_sw < 500} {
	logPuts "FATAL (PG4/F1): only $__f1_vdd_sw VDD sWires after the secondary sroute — the VDDG/VNW strap pass did nothing (IMPSR-503/1253 class). Aborting."
	exit 1
}

################################################################################
# PG4 FABRIC COMPLETION: the secondary sroute above only draws a tiny M1
# finger ON each secondary pin and stacks vias opportunistically where PG
# metal happens to cross overhead (bring-up finding on the gate-b fail DB:
# 4754 of 7078 FILLBIAS taps — and most headers — ended as FLOATING M1
# fingers; only cells under a stripe/ring got real stacks). The header
# columns (x=31+80k) were never aligned with the stripe grid (x=50.5+50k),
# so "sroute + stripes" alone can NEVER supply this fabric. Also: HEADBUF's
# CDL bulks tie to VNW/VPW (NOT VDDG — the M17 "headers' body ties hold the
# well" comment was wrong), and headers expose no VNW/VPW LEF pin, so ALL
# well bias flows through the FILLBIAS strap network. What completes it:
#  1. one narrow vertical M2 VDD strap per TAP column (x0+0.10..0.40, over
#     the VNW pin bars) and per HEADER column (x0+2.325..2.625, over a VDDG
#     comb bar) — addStripe with -stacked_via_bottom_layer M1 puts a VIA1
#     on EVERY pin under the strap and full VIA2..7 stacks at every M8-grid
#     crossing (probe-proven: 32/32 pins via'd in the test column).
#     PG4/F2 WARNING: those VIA1s DO NOT SURVIVE to the final DB/GDS (the
#     v22c signoff DB had none under 7 of 8 header columns; mechanism
#     unknown — CTS/opt/ECO era). The pin hookup of record is the PG4/F2
#     strap-PIN link repair at the post-route repair stage; this stage's
#     via coverage check only gates the STRAP placement itself. M2 is
#     legal here: both LEFs are M1-only inside cells, straps go in
#     pre-place, and 0.3 um per 24 um is ~1% of M2 tracks.
#  2. a 0.25-um M1 jumper per FILLBIAS VPW pin to the VSS rail 0.15 um away
#     (the pin reaches toward the rail by cell design; the "VDD" rail on the
#     other side is VDD_SW, so VNW can NOT use the same trick — hence M2).
# addStripe -start_offset is AREA-relative here: strap_llx = area_llx +
# start_offset (probe-proven twice). Self-checks gate every step; dead-row
# cells (bottom row y<3, right-leg top row) are SKIPPED so the M17b
# end-of-flow scrub still deletes them cleanly.
################################################################################
printStatus "PG4: completing the pmk secondary strap fabric (M2 columns + VPW jumpers)"
# minimal stripe mode: -reset clears the main grid's antenna trim (proven:
# trim=core_ring SHREDS any strap that cannot reach the M8 grid into
# per-pin fragments — the covered-column pathology of bring-up v4/v5).
setAddStripeMode -reset
setAddStripeMode \
    -stacked_via_top_layer M8 \
    -stacked_via_bottom_layer M1 \
    -extend_to_closest_target none \
    -split_long_via $RISER_VIA_SPLIT

set __ram0_box [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
foreach {__rmx0 __rmy0 __rmx1 __rmy1} $__ram0_box {}

proc pg4_has_svia {box wantnet} {
	foreach {bx0 by0 bx1 by1} $box {}
	foreach o [dbQuery -area [list [expr {$bx0 - 0.5}] [expr {$by0 - 0.5}] [expr {$bx1 + 0.5}] [expr {$by1 + 0.5}]] -objType sVia] {
		if {[dbGet -e $o.net.name] eq $wantnet} { return 1 }
	}
	return 0
}
proc pg4_dead_row {bx} {
	global DESIGN_WIDTH DESIGN_HEIGHT FINGER_W
	foreach {x0 y0 x1 y1} $bx {}
	if {$y0 < 3.0} { return 1 }
	if {$y1 > [expr {$DESIGN_HEIGHT - 3.0}] && $x0 >= [expr {$DESIGN_WIDTH - $FINGER_W}]} { return 1 }
	return 0
}

# collect strap columns: tap columns keyed by inst x (pins at x0+0.10..0.40),
# header columns (pins at x0+2.325..2.625)
array unset __colys
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __x [format %.2f [lindex $__bx 0]]
	lappend __colys(T$__x) [lindex $__bx 1]
}
foreach __i [dbGet -p2 top.insts.cell.name HEADBUF16MA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __x [format %.2f [lindex $__bx 0]]
	lappend __colys(H$__x) [lindex $__bx 1]
}
set __nstrap 0
set __nstrap_skip 0
set __skipped_runs {}
set __placed_runs {}
foreach __key [array names __colys] {
	set __x0 [string range $__key 1 end]
	if {[string index $__key 0] eq "T"} {
		set __sx [expr {$__x0 + 0.10}]
	} else {
		set __sx [expr {$__x0 + 2.325}]
	}
	# cluster the cell y's into runs (gap > 40 um starts a new run)
	set __ys [lsort -real $__colys($__key)]
	set __runs {}
	set __rs [lindex $__ys 0]; set __re $__rs
	foreach __y $__ys {
		if {[expr {$__y - $__re}] > 40.0} { lappend __runs [list $__rs $__re]; set __rs $__y }
		set __re $__y
	}
	lappend __runs [list $__rs $__re]
	foreach __run $__runs {
		foreach {__ry0 __ry1} $__run {}
		set __ay0 [expr {$__ry0 - 1.0}]
		set __ay1 [expr {$__ry1 + 3.0}]
		# never let a strap cross ram0 (M1-only cells are safe; the MACRO is not)
		if {$__sx > [expr {$__rmx0 - 1.0}] && $__sx < [expr {$__rmx1 + 1.0}]} {
			if {$__ay0 < $__rmy1 && $__ay1 > $__rmy0} {
				if {$__ry1 < $__rmy0} { set __ay1 [expr {$__rmy0 - 0.5}] } else { set __ay0 [expr {$__rmy1 + 0.5}] }
			}
		}
		addStripe -layer M2 -nets {VDD} -direction vertical -width 0.3 \
			-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.1 \
			-area [list [expr {$__sx - 0.2}] $__ay0 [expr {$__sx + 0.5}] $__ay1]
		# PER-CELL coverage check. The engine places PARTIAL straps: with
		# top=M8 it keeps only the pieces it can upstack (bring-up v7: T25
		# kept just the y 4-14 piece over the ring band and 258 cells went
		# naked while the run looked "placed" and "healthy"). Any member
		# cell without a VDD via gets a top=M2 RETRY over just its
		# subrange (engine then places + VIA1s unconditionally); cells
		# still naked after the retry are waived (taps, recorded) or FATAL
		# (headers). NO lateral fixups: a bring-up sroute-rerun variant
		# "fixed" naked pins with 12-um M1 corewires across the row — a
		# short factory once placement fills the rows. Deleted.
		set __cw [expr {[string index $__key 0] eq "H" ? 4.0 : 0.4}]
		set __uncov {}
		foreach __y $__ys {
			if {$__y < $__ry0 || $__y > $__ry1} { continue }
			if {![pg4_has_svia [list $__x0 $__y [expr {$__x0 + $__cw}] [expr {$__y + 2.0}]] VDD]} { lappend __uncov $__y }
		}
		if {[llength $__uncov] > 0} {
			# cluster uncovered cells into subranges and retry with top=M2
			set __srs {}
			set __us [lindex $__uncov 0]; set __ue $__us
			foreach __y $__uncov {
				if {[expr {$__y - $__ue}] > 12.0} { lappend __srs [list $__us $__ue]; set __us $__y }
				set __ue $__y
			}
			lappend __srs [list $__us $__ue]
			setAddStripeMode -stacked_via_top_layer M2
			foreach __sr $__srs {
				foreach {__u0 __u1} $__sr {}
				addStripe -layer M2 -nets {VDD} -direction vertical -width 0.3 \
					-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.1 \
					-area [list [expr {$__sx - 0.2}] [expr {$__u0 - 1.0}] [expr {$__sx + 0.5}] [expr {$__u1 + 3.0}]]
			}
			setAddStripeMode -stacked_via_top_layer M8
			set __still {}
			foreach __y $__uncov {
				if {![pg4_has_svia [list $__x0 $__y [expr {$__x0 + $__cw}] [expr {$__y + 2.0}]] VDD]} { lappend __still $__y }
			}
			if {[llength $__still] > 0} {
				if {[string index $__key 0] eq "H"} {
					logPuts "FATAL (PG4/F1): [llength $__still] header cells in $__key still naked after the top=M2 retry (y: [lrange $__still 0 5]). Aborting."
					saveDesign dbs/pg4gateb_fail.innovus
					exit 1
				}
				foreach __y $__still {
					incr __nstrap_skip
					lappend __skipped_runs [list $__sx $__y $__y]
				}
				logPuts "PG4: waiving [llength $__still] naked taps in $__key after retry (y: [lrange $__still 0 5])"
			}
		}
		# unconditional continuity rect: partial attempt-1 pieces + retry
		# fragments merge into ONE conductor (raw same-net metal, no-op when
		# already continuous)
		add_shape -net VDD -layer M2 -rect [list $__sx [expr {$__ry0 - 0.5}] [expr {$__sx + 0.3}] [expr {$__ry1 + 2.5}]] -shape STRIPE -status ROUTED
		incr __nstrap
		lappend __placed_runs [list $__key $__sx $__ay0 $__ay1]
	}
}

# --- PG4 phase 2: columns whose strap band lies under FOREIGN M7 (the VSS
# ring legs at x 18-28 / 632-642, the VSS stripes at 59.5+50k, the notch
# legs) can never stack up to the M8 grid — the engine's antenna trim even
# shreds their strap into per-pin fragments (bring-up v4: T25/T637 whole
# columns, H511/H111/T61/T313/T361/T613 partials — VIA1-on-fragment looked
# "supplied" to a naive via check). Remedy, probe-proven piecewise:
# Remedy: ladder the sick strap to the NEAREST healthy column with
# horizontal SAME-LAYER M2 links — touching same-net same-layer metal
# connects with NO vias (editPowerVia -add_vias was proven a no-op for
# this, and only addStripe itself makes pin VIA1s). Links land at
# M8-VDD-row centers every ~100 um so column current spreads across the
# neighbour's existing stacks. A run is healthy iff it has >= 1 real
# upward stack (via4..7) in band.
proc pg4_upstacks {sx y0 y1} {
	set n 0
	foreach o [dbQuery -area [list [expr {$sx - 0.1}] $y0 [expr {$sx + 0.4}] $y1] -objType sVia] {
		if {[dbGet -e $o.net.name] ne "VDD"} { continue }
		set vn [dbGet -e $o.via.name]
		if {[string match -nocase via4* $vn] || [string match -nocase via5* $vn] || [string match -nocase via6* $vn] || [string match -nocase via7* $vn]} { incr n }
	}
	return $n
}
set __healthy {}
set __sick {}
set __link_rects {}
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	if {[pg4_upstacks $__sx $__ay0 $__ay1] > 0} { lappend __healthy $__pr } else { lappend __sick $__pr }
}
logPuts "### UNL STATUS ### : PG4 strap columns: [llength $__healthy] healthy / [llength $__sick] need the M3 ladder remedy"
set __nlink 0
foreach __pr $__sick {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	# nearest healthy neighbour with y overlap
	set __best ""
	set __bestd 1e9
	foreach __hr $__healthy {
		foreach {__hk __hx __hy0 __hy1} $__hr {}
		set __ov [expr {min($__ay1, $__hy1) - max($__ay0, $__hy0)}]
		if {$__ov < 2.0} { continue }
		set __d [expr {abs($__hx - $__sx)}]
		if {$__d < $__bestd} { set __bestd $__d; set __best $__hr }
	}
	if {$__best eq "" || $__bestd > 30.0} {
		logPuts "FATAL (PG4/F1): no healthy strap column within 30 um of sick run $__key ($__sx) — cannot ladder. Aborting."
		saveDesign dbs/pg4gateb_fail.innovus
		exit 1
	}
	foreach {__hk __hx __hy0 __hy1} $__best {}
	set __lx0 [expr {min($__sx, $__hx)}]
	set __lx1 [expr {max($__sx, $__hx) + 0.3}]
	set __oy0 [expr {max($__ay0, $__hy0)}]
	set __oy1 [expr {min($__ay1, $__hy1)}]
	# M8 VDD rows: lly = 51 + 50k -> centers 53.5 + 50k; one link per 100 um;
	# a short run gets a single mid-overlap link.
	set __k [expr {int(ceil(($__oy0 - 53.5) / 100.0))}]
	set __nl 0
	for {set __yc [expr {53.5 + 100.0 * $__k}]} {$__yc < $__oy1} {set __yc [expr {$__yc + 100.0}]} {
		if {$__yc < $__oy0} { continue }
		add_shape -net VDD -layer M2 -rect [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]] -shape STRIPE -status ROUTED
		lappend __link_rects [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]]
		incr __nl
		incr __nlink
	}
	if {$__nl == 0} {
		set __yc [expr {($__oy0 + $__oy1) / 2.0}]
		add_shape -net VDD -layer M2 -rect [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]] -shape STRIPE -status ROUTED
		lappend __link_rects [list $__lx0 [expr {$__yc - 0.15}] $__lx1 [expr {$__yc + 0.15}]]
		set __nl 1
		incr __nlink
	}
	logPuts "PG4: laddered $__key ($__sx) -> [lindex $__best 0] ([format %.2f $__hx]) with $__nl M2 links"
}
logPuts "### UNL STATUS ### : PG4 ladder remedy — [llength $__sick] columns linked with $__nlink M2 links"
# NB deliberately NO global secondary-sroute rerun here: a bring-up
# variant used one and it "fixed" naked pins by routing 12-um lateral M1
# corewires across the (still empty) rows — guaranteed shorts once
# placement fills them. The per-cell top=M2 retry above is the whole
# mechanism.
logPuts "### UNL STATUS ### : PG4 placed $__nstrap M2 secondary strap segments over [llength [array names __colys]] columns ($__nstrap_skip short tap runs waived)"
if {$__nstrap_skip > 100} {
	logPuts "FATAL (PG4/F1): $__nstrap_skip skipped strap runs — far more than the documented sub-ram0 sliver class. Aborting."
	exit 1
}

# VPW jumpers: R0 rows have the VSS rail at the cell bottom, MX at the top.
set __njump 0
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	foreach {__x0 __y0 __x1 __y1} $__bx {}
	if {[dbGet $__i.orient] eq "R0"} {
		add_shape -net VSS -layer M1 -rect [list [expr {$__x0 + 0.15}] [expr {$__y0 + 0.10}] [expr {$__x0 + 0.25}] [expr {$__y0 + 0.35}]] -shape STRIPE -status ROUTED
	} else {
		add_shape -net VSS -layer M1 -rect [list [expr {$__x0 + 0.15}] [expr {$__y0 + 1.65}] [expr {$__x0 + 0.25}] [expr {$__y0 + 1.90}]] -shape STRIPE -status ROUTED
	}
	incr __njump
}
logPuts "### UNL STATUS ### : PG4 added $__njump VPW->VSS-rail M1 jumpers"

# --- PG4 F1 gate b (v2, VIA-based): a dead finger has no via; a real strap
# does. Every live HEADBUF and FILLBIAS-VNW footprint must carry a VDD sVia;
# every live FILLBIAS-VPW footprint a VSS non-followpin wire or sVia.
proc pg4_has_wire {box wantnet skipfollow} {
	foreach {bx0 by0 bx1 by1} $box {}
	foreach o [dbQuery -area [list [expr {$bx0 - 0.5}] [expr {$by0 - 0.5}] [expr {$bx1 + 0.5}] [expr {$by1 + 0.5}]] -objType sWire] {
		if {[dbGet -e $o.net.name] ne $wantnet} { continue }
		if {$skipfollow && [dbGet -e $o.shape] eq "followpin"} { continue }
		return 1
	}
	return 0
}
set __f1_untouched 0
foreach __i [dbGet -p2 top.insts.cell.name HEADBUF16MA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	if {![pg4_has_svia $__bx VDD]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { logPuts "PG4 F1: header [dbGet $__i.name] @$__bx has NO VDD via (VDDG unsupplied)" }
	}
}
foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
	set __bx [lindex [dbGet $__i.box] 0]
	if {[pg4_dead_row $__bx]} { continue }
	set __exempt 0
	foreach __sk $__skipped_runs {
		foreach {__skx __sky0 __sky1} $__sk {}
		if {abs([lindex $__bx 0] + 0.10 - $__skx) < 0.35 && [lindex $__bx 1] >= [expr {$__sky0 - 0.5}] && [lindex $__bx 1] <= [expr {$__sky1 + 0.5}]} { set __exempt 1; break }
	}
	if {!$__exempt && ![pg4_has_svia $__bx VDD]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { logPuts "PG4 F1: welltap [dbGet $__i.name] @$__bx has NO VDD via (VNW unstrapped)" }
	}
	if {![pg4_has_wire $__bx VSS 1] && ![pg4_has_svia $__bx VSS]} {
		incr __f1_untouched
		if {$__f1_untouched <= 5} { logPuts "PG4 F1: welltap [dbGet $__i.name] @$__bx has NO VPW jumper" }
	}
}
logPuts "### UNL STATUS ### : PG4 F1 gate b — $__f1_untouched unsupplied pmk secondary-pin footprints (must be 0)"
if {$__f1_untouched > 0} {
	logPuts "FATAL (PG4/F1): $__f1_untouched pmk cells have no real secondary supply. Saving dbs/pg4gateb_fail.innovus; aborting."
	saveDesign dbs/pg4gateb_fail.innovus
	exit 1
}

# PG4 dangling-stack scrub: at VPW pins under the VSS M7 legs/stripes the
# FIRST secondary sroute leaves floating VIA3..VIA6 stacks (top merged into
# the M7 leg, bottom DANGLING at M3 — no via1/via2 ever placed): 946
# zero-area ANTENNA markers at signoff (bring-up v11). The pins themselves
# are supplied by the VPW M1 jumpers, so the stacks are pure litter. Delete
# exactly the {via3..6, no via1/via2/via7} VSS point-groups — a legit stack
# always includes via1 or via2 (pin/strap bottom) or is via7-only (ring
# crossings).
array unset __vgrp
foreach __o [dbGet [dbGet -p top.nets.name VSS].sVias -e] {
	set __vn [dbGet -e $__o.via.name]
	set __k "[format %.2f [dbGet $__o.pt_x]]_[format %.2f [dbGet $__o.pt_y]]"
	lappend __vgrp($__k) [list $__o $__vn]
}
set __nscrub 0
foreach __k [array names __vgrp] {
	set __has12 0; set __has7 0; set __has36 0
	foreach __e $__vgrp($__k) {
		set __vn [lindex $__e 1]
		if {[string match -nocase via1* $__vn] || [string match -nocase via2* $__vn]} { set __has12 1 }
		if {[string match -nocase via7* $__vn]} { set __has7 1 }
		if {[string match -nocase via3* $__vn] || [string match -nocase via4* $__vn] || [string match -nocase via5* $__vn] || [string match -nocase via6* $__vn]} { set __has36 1 }
	}
	if {$__has36 && !$__has12 && !$__has7} {
		foreach __e $__vgrp($__k) { dbDeleteObj [lindex $__e 0]; incr __nscrub }
	}
}
logPuts "### UNL STATUS ### : PG4 scrubbed $__nscrub dangling VSS stack vias (v11 baseline: ~946 antenna markers)"

# PG5 (2026-08-25): ram0's GROUND HALF WAS NEVER STRAPPED.
# The 8 KiB macro advertises 17 VSSE ports -- M4 bars across its full width --
# and this flow has never had a blockPin pass at all.  VDDPE/VDDCE happen to be
# crossed by the stripe grid's block rings; VSSE is not, so 16 of the 17 hung on
# nothing.  Innovus has said so since at least 2026-08-17 ("Net VSS, Pin Pin:
# ram0/VSSE ... has an unconnected terminal", 16 of them, all at x=75.000), and
# Pegasus carried the whole macro-internal ground island -- layout net 1, 16,885
# attachments, 8,901 of them device BULK terminals -- as an OPEN.  Neither report
# was a false alarm: the macro's internal ground is genuinely two disjoint metal
# pieces the integrator is expected to join through its VSSE pins.
# BOTTOM LAYER CAPPED AT M4 on purpose -- the pins ARE M4, and letting the pass
# reach into the standard-cell rows would re-route ground the follow-pin pass
# above has already done.
#
# WHY THIS PASS RUNS *HERE*, AFTER THE DANGLING-STACK SCRUB, AND NOT WITH THE
# OTHER sroutes.  The first version ran it right after the corePin sroute and
# it WORKED -- "Number of Block ports routed: 16", VIA4 x16 / M5 x15 / VIA5 x16
# / VIA6 x16 -- and then the PG4 dangling-stack scrub ATE ALL OF IT sixty lines
# later.  That scrub deletes VSS via point-groups that carry via3..6 with no
# via1/via2 and no via7, on the reasoning that a legit stack always has a
# pin/strap bottom or is a via7-only ring crossing.  A block-pin strap off an
# M4 macro pin is neither: it starts at VIA4 and stops at M7.  It matched the
# rule exactly.  MEASURED: the scrub count went 562 -> 608, +46, against the 48
# vias sroute had just created, and signoff verifyConnectivity still reported
# all 16 ram0/VSSE terminals unconnected.  Ordering, not geometry, was the bug.
printStatus "PG5: strapping ram0's VSSE block pins"
set __r0b [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
foreach {__r0x0 __r0y0 __r0x1 __r0y1} $__r0b {}
set __r0vss_pre [llength [dbGet [dbGet -p top.nets.name VSS].sWires -e]]
sroute \
	-nets { VSS } \
	-connect { blockPin } \
	-blockPin useLef \
	-allowLayerChange 1 \
	-allowJogging 1 \
	-layerChangeRange { M4(4) M8(8) } \
	-area [list [expr {$__r0x0 - 2.0}] [expr {$__r0y0 - 2.0}] [expr {$__r0x1 + 2.0}] [expr {$__r0y1 + 2.0}]]
set __r0vss_post [llength [dbGet [dbGet -p top.nets.name VSS].sWires -e]]
logPuts "### UNL STATUS ### : PG5 ram0 VSSE strap -- VSS sWires $__r0vss_pre -> $__r0vss_post"
if {$__r0vss_post <= $__r0vss_pre} {
	logPuts "FATAL (PG5): the ram0 blockPin sroute created no VSS geometry -- the macro's ground half stays an island (16 unstrapped VSSE ports). Aborting."
	exit 1
}

set __r0v4 0
foreach __o [dbGet [dbGet -p top.nets.name VSS].sVias -e] {
	if {![string match -nocase via4* [dbGet -e $__o.via.name]]} { continue }
	set __vx [dbGet $__o.pt_x] ; set __vy [dbGet $__o.pt_y]
	if {$__vx < $__r0x0 || $__vx > $__r0x1 || $__vy < $__r0y0 || $__vy > $__r0y1} { continue }
	incr __r0v4
}
logPuts "### UNL STATUS ### : PG5 ram0 VSSE strap -- $__r0v4 VSS VIA4 survive over the macro (0 means something scrubbed them again)"
if {$__r0v4 == 0} {
	logPuts "FATAL (PG5): every VSS VIA4 over ram0 was deleted after the blockPin sroute -- a later pass is eating the strap, exactly as the dangling-stack scrub did before this block was moved. Aborting."
	exit 1
}

# PG4 route blockages over every M2 strap band + ladder link: nanoroute
# dropped one signal VIA2 pad inside the T121 strap band at v11 (1 M2
# short) — special wires alone evidently do not fence via landing pads.
# deleteAllRouteBlks after routing removes these along with the M7/M8 ones.
#
# THE HALO IS 0.15, NOT 0.10, AND THE 0.05 DIFFERENCE IS THE WHOLE POINT
# (2026-08-26).  A 0.10 halo is exactly M2_S_1, so it fences the strap for a
# WIRE and not for a VIA: the first legal M2 position outside a 0.10 halo is the
# track at strap edge + 0.10, and a via CENTRED there puts its 0.10 um wide
# landing pad at strap edge + 0.05.  That is a real M2.S.1, it is invisible to
# the router because the router is measuring against the BLOCKAGE and not the
# strap, and it is invisible at post-route verifyGeometry because it reports as
# one "Regular Via & Routing Blockage" line among 808 expected blockage entries.
# It shipped exactly once, at (553.400,176.410) on the 2026-08-26 via-split cut,
# out of 105485 vias.
#
# 0.15 = M2_S_1 + half the minimum M2 via pad, so the nearest via centre the
# router can choose leaves the pad a full 0.10 um clear, and a wider multi-cut
# pad overlaps the halo and is refused outright.  The cost is 0.05 um of extra
# keepout on each side of 94 strap columns.
set __pgblkhalo [pgc_v M2_S_1]
if {$__pgblkhalo eq ""} { set __pgblkhalo 0.10 }
set __pgblkhalo [expr {$__pgblkhalo + 0.05}]
logPuts "### UNL STATUS ### : PG4 M2 strap blockage halo = $__pgblkhalo (M2_S_1 from the deck plus half a minimum via pad)"
set __nblk 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	createRouteBlk -box [list [expr {$__sx - $__pgblkhalo}] $__ay0 [expr {$__sx + 0.3 + $__pgblkhalo}] $__ay1] -layer 2
	incr __nblk
}
foreach __lr $__link_rects {
	foreach {__lx0 __ly0 __lx1 __ly1} $__lr {}
	createRouteBlk -box [list [expr {$__lx0 - 0.1}] [expr {$__ly0 - 0.1}] [expr {$__lx1 + 0.1}] [expr {$__ly1 + 0.1}]] -layer 2
	incr __nblk
}
logPuts "### UNL STATUS ### : PG4 created $__nblk M2 route blockages over the strap fabric"

# PG4 M7 pad-bridge pass: a strap upstack's M7 landing pads reach to
# sx+0.41; where a SAME-NET M7 stripe/ring edge sits 0.05..1.5 um away the
# net-blind wide-metal union rule fires (v11 Calibre: 36 = T49/T349/T649 x
# 12 M8-rows, pads at 49.51 vs stripe llx 50.5). One full-run-height M7
# rect bridges pad and stripe into a single union shape — additive, same
# net, M7 is power-only here.
set __nbridge 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __padr [expr {$__sx + 0.41}]
	set __padl [expr {$__sx - 0.11}]
	foreach __o [dbGet [dbGet -p top.nets.name VDD].sWires -e] {
		if {[dbGet -e $__o.layer.name] ne "M7"} { continue }
		set __b [lindex [dbGet $__o.box] 0]
		foreach {__bx0 __by0 __bx1 __by1} $__b {}
		if {[expr {$__by1 - $__by0}] < 100} { continue }
		if {[expr {min($__by1, $__ay1) - max($__by0, $__ay0)}] < 10} { continue }
		set __gapr [expr {$__bx0 - $__padr}]
		set __gapl [expr {$__padl - $__bx1}]
		if {$__gapr > 0.02 && $__gapr < 1.6} {
			add_shape -net VDD -layer M7 -rect [list [expr {$__sx + 0.25}] [expr {max($__ay0, $__by0)}] [expr {$__bx0 + 0.2}] [expr {min($__ay1, $__by1)}]] -shape STRIPE -status ROUTED
			incr __nbridge
		} elseif {$__gapl > 0.02 && $__gapl < 1.6} {
			add_shape -net VDD -layer M7 -rect [list [expr {$__bx1 - 0.2}] [expr {max($__ay0, $__by0)}] [expr {$__sx + 0.05}] [expr {min($__ay1, $__by1)}]] -shape STRIPE -status ROUTED
			incr __nbridge
		}
	}
}
logPuts "### UNL STATUS ### : PG4 added $__nbridge M7 pad-union bridges"

# PG4 duplicate-VIA1 dedupe: under same-net M7 stripes the FIRST sroute
# already stacked some pins; my strap adds a second VIA1 ~0.1 um away =
# VIA1 array-spacing violations (v11: 6 on T553). Keep the strap-centered
# via of each close pair, delete the other.
set __ndd 0
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __c [expr {$__sx + 0.15}]
	array unset __v1g
	foreach __o [dbQuery -area [list [expr {$__sx - 0.4}] $__ay0 [expr {$__sx + 0.7}] $__ay1] -objType sVia] {
		if {[dbGet -e $__o.net.name] ne "VDD"} { continue }
		if {![string match -nocase via1* [dbGet -e $__o.via.name]]} { continue }
		set __gy [expr {round([dbGet $__o.pt_y] * 2.0) / 2.0}]
		lappend __v1g($__gy) [list $__o [dbGet $__o.pt_x]]
	}
	foreach __gy [array names __v1g] {
		if {[llength $__v1g($__gy)] < 2} { continue }
		set __keep ""
		set __kd 1e9
		foreach __e $__v1g($__gy) {
			set __d [expr {abs([lindex $__e 1] - $__c)}]
			if {$__d < $__kd} { set __kd $__d; set __keep [lindex $__e 0] }
		}
		foreach __e $__v1g($__gy) {
			if {[lindex $__e 0] ne $__keep} { dbDeleteObj [lindex $__e 0]; incr __ndd }
		}
	}
}
logPuts "### UNL STATUS ### : PG4 deduped $__ndd doubled VIA1s under same-net stripes"

# PG4 fix for the LAST tile foundry-DRC violation — M7.S.4 pair (b), the
# notch-ring-bend VSS via-stack landing pads (PG3 finding). Under the M8
# finger-rail-to-ring strap at x 63.5-68.5 two same-net VSS pad groups face
# each other 1.02 um apart: the via7Array_6 stripe-via M7 pad (top edge
# y=569.75) vs the follow-pin VIA1-7 rail-stack pads at (66, 571+) (bottom
# ~570.77). Same net, but the deck's union-projection wide-metal rule is
# net-blind. Fix = ADD one merging VSS M7 rect over the gap so the union
# becomes a single shape (no facing edges). ADDITIVE ONLY — the PG3 lesson
# stands: deleting/redrawing engine shapes loses their stacked vias
# irrecoverably (editPowerVia can't rebuild them, IMPSR-554). Nearest
# foreign M7 is the VDD ring leg at y>=586 (14.5 um) and the VDD stripe
# column at x<=55.5 (8 um) — the merged shape clears both by miles.
# Validated on the PG3 signoff DB + Calibre blockdrc: M7.S.4 1 -> 0.
# COORDINATES ARE NOW BASE_H-RELATIVE (2026-08-16). The literal y 569.0-572.0
# above was validated at BASE_H=600 and is a NOTCH-RING-BEND offset, not an
# absolute: the structures it merges sit 28-31 um below the notch floor. When the
# tile shrank to BASE_H=430 the ring moved down with it, the patch did NOT, and
# it landed on the VDD ring leg instead -- turning a DRC fix into a hard
# VDD/VSS M7 SHORT at exactly (66,569)-(68.5,572). Anchoring it to BASE_H is what
# makes the fix survive a floorplan change; re-validate against Calibre blockdrc
# (M7.S.4 must stay 0) whenever the notch geometry moves again.
set __ps4_y0 [expr {$BASE_H - 31.0}]
set __ps4_y1 [expr {$BASE_H - 28.0}]
add_shape -net VSS -layer M7 -rect [list 63.5 $__ps4_y0 68.5 $__ps4_y1] -shape STRIPE -status ROUTED
set __ps4 0
foreach __sw [dbGet [dbGet -p top.nets.name VSS].sWires -e] {
	if {[dbGet $__sw.layer.name] ne "M7"} { continue }
	set __bx [lindex [dbGet $__sw.box] 0]
	if {[lindex $__bx 0] > 63.0 && [lindex $__bx 0] < 64.0 && [lindex $__bx 1] > [expr {$__ps4_y0 - 0.5}] && [lindex $__bx 1] < [expr {$__ps4_y0 + 0.5}]} { incr __ps4 }
}
if {$__ps4 == 0} {
	logPuts "FATAL (PG4): the M7.S.4(b) merge patch did not land — add_shape silently failed. Aborting."
	exit 1
}
logPuts "### UNL STATUS ### : PG4 M7.S.4(b) pad-merge patch placed"

################################################################################
# PG1 F1 (2026-07-10): ALWAYS-ON repeaters for the long SLEEP-chain links.
# The four columns whose chains jump ~400 um over the ram0 macro got their
# enable link repeated by place_opt with ORDINARY INVERTER PAIRS on VDD_SW —
# cells that die with the rail they are supposed to keep off: 202/1027
# switches' SLEEP then drifts mid-rail on always-on VDDG receivers and the
# column-tails re-enable/oscillate/crowbar (PG1 audit finding F1; the pmk
# sim model is buf(SLEEPOUT,SLEEP), so no gate sim can ever see this).
# Fix: splice a GPGBUFX4 (VDDG-powered always-on buffer — the pmk cell that
# exists for exactly this, already define_always_on_cell in the CPF) into
# every chain link longer than PG1_LINK_THRESH. This block runs AFTER the
# main secondary-pin sroute: a GPGBUF present during that pass trips
# IMPSR-503 ("level shifter secondary pins need a power domain") and the
# pass silently does NOTHING — the whole switch fabric loses its VDDG
# straps (proven, run 9). The repeaters' own AO hookup is a dedicated
# -powerDomains pass after place_opt (they are unplaced until then). The
# nets are then marked dont_touch so opt can never splice core cells into
# the chain again; the PG1 acceptance gate before signoff is the backstop.
################################################################################
printStatus "PG1: splicing GPGBUF AO repeaters into long SLEEP-chain links"
# ---------------------------------------------------------------------------
# PG1/F2b STRUCTURAL FIX (2026-08-25): PRE-PLACE THE AO REPEATERS.
#
# THE DEFECT THIS REMOVES.  Until now these repeaters were created UNPLACED,
# place_opt legalised them wherever it liked, the flow then FIXED them
# (tcl "PG4 v19: PIN THE REPEATERS FIRST"), and only afterwards did PG4/F2b
# demand a clear M2 corridor from each one to a main strap column.  Nothing in
# that sequence ever GUARANTEED such a corridor existed.  It worked by luck.
#
# THE LUCK RAN OUT, AND THE MARGIN SAYS HOW THIN IT ALWAYS WAS.  On 2026-08-17
# pgaorep_2 landed at x0 = 200.0 and its left corridor cleared the neighbouring
# VSS M2 strap (200.800..201.100) by 0.03 um -- three hundredths of a micron.
# When the fetch-ahead RTL moved it to x0 = 197.4 it landed in the 2.82 um
# pocket between the sleep chain's own M2 ladder (x 194.65..194.95, nine
# psoPSI segments whose y-spans OVERLAP into one continuous wall from 223.45 to
# 259.55) and its own VSSG strap (x 198.2..198.5, continuous 222.8..266.0).
# Every one of 13 candidate columns x 131 scan steps = 1703 link positions was
# rejected.  No search radius can reach past either wall: 45 -> 75 um took the
# candidate count 9 -> 13 and fixed nothing.
#
# THE FIX.  Place each repeater ABUTTING a real strap column and FIX it before
# place_opt runs, so the corridor is short and known BY CONSTRUCTION instead of
# discovered afterwards -- then blockade that corridor on M2 so the router
# cannot fill the very channel F2b will need.  The column set is read from
# __placed_runs, the live table this run just built; NOTHING here is a
# hardcoded coordinate.  (The stale 2026-07-11 M2 patch set that had to be
# attachment-guarded earlier in this file is what hardcoding costs.)
#
# FAIL-SOFT BY DESIGN.  If no column can host a repeater, the repeater is left
# unplaced and place_opt legalises it exactly as before -- this can only ever
# improve on the old behaviour, never replace a working placement with none.
# ---------------------------------------------------------------------------
set PG1_SITE_X0   1.0    ;# DEF: SITE origin x, TSMC65GPADV10TSITE
set PG1_SITE_STEP 0.2    ;# DEF: STEP 400 dbu at 2000 dbu/um
set PG1_ROW_Y0    3.0    ;# DEF: CORE_ROW_0 y
set PG1_ROW_STEP  2.0
set PG1_REP_W     1.4    ;# GPGBUFX4MA10TH width (7 sites)
# STANDOFF from the column cell (2026-08-25).  Placing the repeater flush
# against the tap cell put its own VDDG/VSSG M2 bands hard up against the
# column's strap: two of four repeaters fell back to the M19c rail jumper for
# VSSG ("both M2 bands collide") and then got NO VDD via at all, so PG4/F1
# aborted with 2 unsupplied pins.  One micron of clearance -- five sites --
# gives the bands room while keeping the F2b corridor ~1.3 um of open row
# instead of the 4.7 um run through the sleep-chain ladder that failed runs 1
# and 2.  The corridor is still blockaded, so it stays clear.
set PG1_REP_STANDOFF 1.0

proc pg1_snap_x {x} {
	global PG1_SITE_X0 PG1_SITE_STEP
	return [expr {$PG1_SITE_X0 + round(($x - $PG1_SITE_X0) / $PG1_SITE_STEP) * $PG1_SITE_STEP}]
}
proc pg1_snap_row {y} {
	global PG1_ROW_Y0 PG1_ROW_STEP
	return [expr {$PG1_ROW_Y0 + round(($y - $PG1_ROW_Y0) / $PG1_ROW_STEP) * $PG1_ROW_STEP}]
}
# Rows ALTERNATE orientation (DEF: CORE_ROW_0 y=3.0 N, CORE_ROW_1 y=5.0 FS,
# CORE_ROW_2 y=7.0 N ...).  A cell placed R0 into an FS row has its power rails
# upside down -- VDD where the row supplies VSS.  Derive it, never assume R0.
proc pg1_row_orient {y} {
	global PG1_ROW_Y0 PG1_ROW_STEP
	set k [expr {int(round(($y - $PG1_ROW_Y0) / $PG1_ROW_STEP))}]
	return [expr {($k % 2) == 0 ? "R0" : "MX"}]
}
# Is the footprint free of every already-placed instance?  At splice time the
# only placed cells are the preplaced-fixed PG structures (HEADBUF switches,
# FILLBIAS taps, well straps) -- standard cells are not placed yet -- so a
# clear answer here stays true through place_opt for a FIXED cell.
proc pg1_site_free {x0 y0 x1 y1} {
	foreach o [dbQuery -area [list [expr {$x0 - 0.05}] [expr {$y0 - 0.05}] \
	                               [expr {$x1 + 0.05}] [expr {$y1 + 0.05}]] -objType inst] {
		if {[dbGet -e $o.pStatus] eq "unplaced"} { continue }
		return 0
	}
	return 1
}
# LUP.6 (2026-08-25): give every pre-placed AO repeater its own n-well tap.
#
# The 2026-08-25 cut came out of Calibre with five LUP.6 latch-up markers, all
# five inside pgaorep_2 and all five in the N-WELL band above it.  The cause is
# not the 1.0 um standoff: ram0's 2 um halo blanks CORE_ROW_2 from x 72.8 to
# 396.8, so neither addFiller nor addWellTap can enter that row, and pgaorep_2
# sat alone in 324 um of it with its n-well untapped.  Only one of the four
# repeaters landed in a halo-blanked row THIS time; any of them can next time,
# so the tap is placed for all four rather than for the one that complained.
#
# FILLBIASNWA10TH, not FILLBIASA10TH, and WEST, not EAST.  Both flanking sites
# carry the repeater's own pin-access metal: the A input leaves west and the Y
# output east, because the cell's internal M1 pinches the A pin to 0.29 um and a
# two-cut VIA1 needs 0.38, so the router has to drop both vias OUTSIDE the cell.
# A FILLBIASA10TH on the east puts its VPW bar straight through the Y stub (a
# SHORT); on the west its VPW bar stops 0.065 um under the A stub (an M1.S.1).
# FILLBIASNWA10TH has no VPW bar at all and clears the A stub by 0.110 um.
# All of that was MEASURED by the post-harden DRC ECO, which had to rip and
# re-route the A net to fit the tap afterwards; placing it HERE, before any
# routing exists, is the whole point -- the router simply routes around it.
#
# FAIL-SOFT BY DESIGN.  Every failure path here logs and returns: the tap is a
# DRC improvement, and no repeater placement that works today may be lost to it.
proc pg1_place_nwtap {rep px ry orient} {
	set cellname FILLBIASNWA10TH
	set c [dbGet -p head.allCells.name $cellname -e]
	if {$c eq "0x0" || $c eq "" || $c eq "0"} {
		logPuts "PG1 NWTAP: $cellname is not in the library set -- no LUP.6 tap for $rep"
		return ""
	}
	set tw [dbGet -e $c.size_x]
	if {$tw eq "" || abs($tw - 0.4) > 0.001} {
		logPuts "PG1 NWTAP: $cellname is '$tw' um wide, not 0.400 -- the abut arithmetic was derived for 0.400; skipping $rep"
		return ""
	}
	set tx [expr {$px - $tw}]
	if {$tx < 1.0} {
		logPuts "PG1 NWTAP: no room west of $rep at x=$px -- skipping"
		return ""
	}
	# DO NOT use pg1_site_free here.  It pads its query window by 0.05 um on
	# every side, and the repeater this tap ABUTS starts at exactly $px -- so
	# the padded window always contains the repeater itself and every tap gets
	# skipped as "occupied".  Measured on the first run that carried this code:
	# all four taps skipped, on all four repeaters, for that reason alone.
	# The footprint has to be tested INSIDE its own edges, which is what the
	# post-harden DRC ECO's own site check does.
	set __occ 0
	foreach __o [dbQuery -area [list [expr {$tx + 0.01}] [expr {$ry + 0.01}] \
	                                 [expr {$tx + $tw - 0.01}] [expr {$ry + 1.99}]] -objType inst] {
		if {[dbGet -e $__o.pStatus] eq "unplaced"} { continue }
		incr __occ
		logPuts "PG1 NWTAP: [dbGet -e $__o.name] ([dbGet -e $__o.cell.name]) occupies the site west of $rep"
	}
	if {$__occ} {
		logPuts "PG1 NWTAP: the site west of $rep ({$tx $ry}) is occupied by $__occ instance(s) -- skipping"
		return ""
	}
	# and it must be a row of the tap's OWN site flavour
	set __rowok 0
	foreach __r [dbQuery -area [list [expr {$tx + 0.01}] [expr {$ry + 0.01}] \
	                                 [expr {$tx + $tw - 0.01}] [expr {$ry + 1.99}]] -objType row] {
		if {[dbGet -e $__r.site.name] eq [dbGet -e $c.site.name]} { set __rowok 1 }
	}
	if {!$__rowok} {
		logPuts "PG1 NWTAP: no [dbGet -e $c.site.name] row under {$tx $ry} -- skipping $rep"
		return ""
	}
	set tapname pg1nwtap_$rep
	if {[catch {addInst -cell $cellname -inst $tapname -physical -status fixed -loc [list $tx $ry] -ori $orient} __e]} {
		logPuts "PG1 NWTAP: addInst failed for $tapname ($__e) -- skipping"
		return ""
	}
	# bind its PG pins the way the flow binds every other tap
	globalNetConnect VDD    -type pgpin -pin VNW -inst $tapname -module {} -verbose
	globalNetConnect VSS    -type pgpin -pin VSS -inst $tapname -module {} -verbose
	globalNetConnect VDD_SW -type pgpin -pin VDD -inst $tapname -module {} -override -verbose
	lappend ::PG1_NWTAPS [list $tapname $rep $tx $ry $orient]
	logPuts [format "PG1 NWTAP: %s (%s) placed at (%.3f,%.3f) %s abutting %s -- pre-emptive LUP.6 well tie" \
		$tapname $cellname $tx $ry $orient $rep]
	return $tapname
}

# Place $inst abutting the strap column that best serves ($ix,$iy).  Returns
# the chosen column strap x on success, "" on failure.
#
# TWO THINGS THIS GETS RIGHT THAT THE FIRST VERSION DID NOT.
#
# 1. ABUT THE COLUMN *CELL*, NOT THE STRAP.  The strap x is the cell's x0 plus
#    0.10 (tap columns) or 2.325 (header columns), so a site offered at
#    "strap + 0.4" is INSIDE the FILLBIAS/HEADBUF that owns the strap.  Every
#    row of the nearest column then failed the occupancy test and the search
#    fell through to a far one.  Measured on the first attempt: pgaorep_1 was
#    placed 126.1 um from its ideal midpoint and pgaorep_2 129.9 um.  On links
#    of 216-220 um that is worse than not splicing at all -- the repeater
#    exists to HALVE the link, and a 126 um detour lengthens both halves.  The
#    cell box is now read from the DB and the repeater abuts its edge.
#
# 2. COST, NOT JUST DISTANCE IN X.  A column is only useful if one of its rows
#    is near the ideal y as well, so candidates are ranked by
#    |sx - ix| + (how far ideal y falls outside the column's run band).
#
# LEFT SIDE IS TRIED FIRST, deliberately: the gap immediately left of a column
# cell is open row, whereas the span to its right is the cell's own body, which
# carries its VPW/VNW/VSS structures.  A corridor over open row has less in it
# to collide with.
proc pg1_preplace_repeater {inst ix iy} {
	global __placed_runs PG1_REP_W PG1_ROW_STEP PG1_REP_STANDOFF
	if {![info exists __placed_runs]} { return "" }
	set cands {}
	foreach pr $__placed_runs {
		foreach {key sx ay0 ay1} $pr {}
		set ypen 0.0
		if {$iy < $ay0} { set ypen [expr {$ay0 - $iy}] }
		if {$iy > $ay1} { set ypen [expr {$iy - $ay1}] }
		lappend cands [list [expr {abs($sx - $ix) + $ypen}] $sx $ay0 $ay1]
	}
	if {[llength $cands] == 0} { return "" }
	set cands [lsort -real -index 0 $cands]
	foreach cand $cands {
		foreach {cost sx ay0 ay1} $cand {}
		set y_start [expr {$iy < $ay0 ? $ay0 : ($iy > $ay1 ? $ay1 : $iy)}]
		for {set k 0} {$k < 40} {incr k} {
			foreach sgn {1 -1} {
				if {$k == 0 && $sgn < 0} { continue }
				set ry [pg1_snap_row [expr {$y_start + $sgn * $k * $PG1_ROW_STEP}]]
				if {$ry < $ay0 || $ry > $ay1} { continue }
				# the column cell occupying THIS row (tap x0 = sx-0.10,
				# header x0 = sx-2.325, so look back 2.6 um)
				# THE COLUMN CELL, and nothing else.  Taking the first instance
				# the query returned put pgaorep_0 on the far side of the TCM:
				# ram0 spans x 75..~395, its bbox overlaps the query window of
				# the x=397.1 column, and the code happily "abutted" it --
				# placing the repeater at x=72.6 against a strap at 397.1 and
				# blockading a 323 um M2 channel across a whole row.
				# A real column cell CONTAINS its own strap x by construction
				# (tap: sx = x0+0.10, header: sx = x0+2.325), and is a few um
				# wide.  A macro satisfies neither.  Test both.
				set cx0 ""; set cx1 ""
				foreach o [dbQuery -area [list [expr {$sx - 2.60}] [expr {$ry + 0.20}] \
				                               [expr {$sx + 0.40}] [expr {$ry + 1.80}]] -objType inst] {
					if {[dbGet -e $o.pStatus] eq "unplaced"} { continue }
					set cb [lindex [dbGet $o.box] 0]
					set tx0 [lindex $cb 0]; set tx1 [lindex $cb 2]
					if {$sx < $tx0 || $sx > $tx1} { continue }
					if {[expr {$tx1 - $tx0}] > 5.0} { continue }
					set cx0 $tx0; set cx1 $tx1
					break
				}
				foreach side {L R} {
					if {$cx0 eq ""} {
						# no cell in this row of the run -- stand off the strap itself
						if {$side eq "L"} {
							set px [pg1_snap_x [expr {$sx - 0.10 - $PG1_REP_STANDOFF - $PG1_REP_W}]]
						} else {
							set px [pg1_snap_x [expr {$sx + 0.40 + $PG1_REP_STANDOFF}]]
						}
					} else {
						if {$side eq "L"} {
							set px [pg1_snap_x [expr {$cx0 - $PG1_REP_STANDOFF - $PG1_REP_W}]]
						} else {
							set px [pg1_snap_x [expr {$cx1 + $PG1_REP_STANDOFF}]]
						}
					}
					if {![pg1_site_free $px $ry [expr {$px + $PG1_REP_W}] [expr {$ry + 2.0}]]} { continue }
					set __or [pg1_row_orient $ry]
					if {[catch {placeInstance $inst $px $ry $__or}]} { continue }
					dbSet [dbGet -p top.insts.name $inst].pStatus fixed
					# Blockade the CHANNEL BETWEEN the repeater and the strap --
					# and NOTHING ELSE.  The first version blocked M2 over the
					# repeater's OWN footprint too, which stopped the PG4 strap
					# recipe from drawing its VDDG/VSSG M2 fingers and vias
					# there: all four repeaters came back "NO VDD via
					# (VDDG unsupplied)" and F1 aborted the run.  The blockage
					# exists to keep SIGNAL routing out of the link corridor,
					# not to fence off the cell that needs supplying.
					set __chan0 ""; set __chan1 ""
					if {$px >= [expr {$sx + 0.3}]} {
						set __chan0 [expr {$sx + 0.3}] ; set __chan1 $px
					} elseif {[expr {$px + $PG1_REP_W}] <= $sx} {
						set __chan0 [expr {$px + $PG1_REP_W}] ; set __chan1 $sx
					}
					# BACKSTOP: a link corridor is a few um.  Anything longer means
					# the host cell was misidentified (see the ram0 trap above);
					# refuse the placement rather than blockade half a row.
					if {$__chan0 ne "" && [expr {$__chan1 - $__chan0}] > 12.0} {
						dbSet [dbGet -p top.insts.name $inst].pStatus unplaced
						logPuts [format "PG1 PREPLACE: REJECTED %s at (%.3f,%.3f) -- channel to strap x=%.3f is %.1f um, not a corridor" \
							$inst $px $ry $sx [expr {$__chan1 - $__chan0}]]
						continue
					}
					# THE BLOCKAGE MUST COVER THE REPEATER'S OWN FOOTPRINT, NOT
					# JUST THE GAP.  Run 8 proved why: F2b's clearance test spans
					# the whole width from the column strap to the far edge of the
					# repeater's strap, and place_opt had routed SIGNALS straight
					# over the repeater --
					#     wire n_178                 x 398.65..398.75  y  75.85..151.95
					#     wire FE_OFN323_a0_2        x 399.05..399.15  y  98.05..139.55
					#     wire write_data[28]        x 398.25..398.35  y 134.25..154.15
					# n_178 alone is a 76 um vertical line crossing every scan y.
					# A gap-only blockage stopped at the repeater's left edge
					# (398.6) and n_178 sat 0.05 um past it.
					#
					# But covering the footprint is EXACTLY what broke F1 in run 4:
					# the PG4 supply pass needs M2 free over the cell to draw its
					# VDDG/VSSG fingers.  Both are true, and they are true at
					# DIFFERENT TIMES -- so the blockage is NAMED here, held
					# through place_opt (whose trial routing is what fills the
					# corridor), and LIFTED just before the supply pass runs.
					# Nothing routes between that lift and F2b, so the corridor
					# is still clear when F2b needs it, and F2b blockades its own
					# link the moment it draws it.
					set __b0 [expr {min($px, $sx) - 0.2}]
					set __b1 [expr {max($px + $PG1_REP_W, $sx + 0.3) + 0.2}]
					if {[catch {createRouteBlk -name pg1corr_$inst \
							-box [list $__b0 [expr {$ry - 0.2}] $__b1 [expr {$ry + 2.2}]] -layer 2}]} {
						createRouteBlk -box [list $__b0 [expr {$ry - 0.2}] $__b1 [expr {$ry + 2.2}]] -layer 2
					}
					lappend ::PG1_CORR_BLKS [list pg1corr_$inst $__b0 [expr {$ry - 0.2}] $__b1 [expr {$ry + 2.2}]]
					pg1_place_nwtap $inst $px $ry $__or
					logPuts [format "PG1 PREPLACE: %s -> (%.3f,%.3f) %s, abutting column cell at strap x=%.3f (%s side); ideal was (%.1f,%.1f); M2 blocked %s..%s through place_opt" \
						$inst $px $ry $__or $sx $side $ix $iy \
						[format %.3f $__b0] [format %.3f $__b1]]
					return $sx
				}
			}
		}
	}
	return ""
}
set PG1_LINK_THRESH 150.0
set PG1_NREP 0
set PG1_NPREPLACED 0
set ::PG1_CORR_BLKS {}
set ::PG1_NWTAPS {}
foreach np [dbGet -p top.nets.name psoPSI_*] {
	set netname [dbGet $np.name]
	set drv ""
	set lds {}
	foreach t [dbGet $np.instTerms.name -e] {
		if {[string match {*/SLEEPOUT} $t]} { set drv $t } \
		elseif {[string match {*/SLEEP} $t]} { lappend lds $t }
	}
	if {$drv eq "" || [llength $lds] != 1} { continue }
	set drvinst [string range $drv 0 [expr {[string last "/" $drv] - 1}]]
	set ldinst  [string range [lindex $lds 0] 0 [expr {[string last "/" [lindex $lds 0]] - 1}]]
	set p1 [lindex [dbGet [dbGet -p top.insts.name $drvinst].pt] 0]
	set p2 [lindex [dbGet [dbGet -p top.insts.name $ldinst].pt]  0]
	set dist [expr {abs([lindex $p1 0] - [lindex $p2 0]) + abs([lindex $p1 1] - [lindex $p2 1])}]
	if {$dist <= $PG1_LINK_THRESH} { continue }
	set repname pgaorep_$PG1_NREP
	set repnet  ${netname}_pg1rep
	logPuts "PG1: link $netname ($drvinst -> $ldinst) is ${dist}um — splicing $repname"
	addNet $repnet
	addInst -cell GPGBUFX4MA10TH -inst $repname
	# Pre-place ABUTTING a strap column, before place_opt can scatter it.
	# Ideal position = midway along the link this repeater is splitting.
	set __ideal_x [expr {([lindex $p1 0] + [lindex $p2 0]) / 2.0}]
	set __ideal_y [expr {([lindex $p1 1] + [lindex $p2 1]) / 2.0}]
	set __pp [pg1_preplace_repeater $repname $__ideal_x $__ideal_y]
	if {$__pp eq ""} {
		logPuts "PG1 PREPLACE: WARNING -- no hostable strap column for $repname; leaving it to place_opt (pre-2026-08-25 behaviour, F2b may abort)"
	} else {
		incr PG1_NPREPLACED
	}
	attachTerm $repname A $netname
	attachTerm $repname Y $repnet
	detachTerm $ldinst SLEEP
	attachTerm $ldinst SLEEP $repnet
	dbSet [dbGet -p top.nets.name $repnet].dontTouch true
	incr PG1_NREP
}
logPuts "### UNL STATUS ### : PG1 spliced $PG1_NREP GPGBUF AO repeaters into the SLEEP chain ($PG1_NPREPLACED pre-placed against a strap column)"
if {$PG1_NREP > 0 && $PG1_NPREPLACED < $PG1_NREP} {
	logPuts "### UNL STATUS ### : PG1 PREPLACE — [expr {$PG1_NREP - $PG1_NPREPLACED}] repeater(s) left to place_opt; PG4/F2b is back to discovering a corridor for those and may abort."
}
if {$PG1_NREP == 0} {
	logPuts "WARNING (PG1): no long SLEEP-chain links found — floorplan changed? Verify the chain."
}
# Freeze the whole enable chain + the macro PG-control nets against opt.
# NOT setAttribute (-dont_touch is not an option in 20.12 — IMPTCM-48,
# proven by run 9's re-buffered chain): dbSet the net attribute, and verify
# it took. The acceptance gate before signoff remains the hard backstop.
foreach np [dbGet -p top.nets.name psoPSI_*] {
	dbSet $np.dontTouch true
}
foreach nn {pd_sleep tcm_pgen tcm_retn} {
	set np [dbGet -p top.nets.name $nn -e]
	if {$np ne ""} { dbSet $np.dontTouch true }
}
set PG1_DT [llength [dbGet -p top.nets.dontTouch true -e]]
logPuts "### UNL STATUS ### : PG1 dont_touch set on $PG1_DT nets"
if {$PG1_DT == 0} {
	logPuts "FATAL (PG1): dont_touch did not take on any chain net"
	exit 1
}
# The repeaters were created AFTER the -inst * globalNetConnect lines ran —
# re-apply the AO secondary-pin rules to them (VSSG exists only on GPG cells).
# PG4/PG2-F1: -type pgpin (the -type net form never bound anything — the
# PG1-F1 repeaters shipped UNPOWERED, fix physically void as built), and
# gate the binding: 4 dead repeaters silently re-break the SLEEP chain.
if {$PG1_NREP > 0} {
	globalNetConnect VDD -type pgpin -pin VDDG -inst pgaorep_* -module {} -verbose
	globalNetConnect VSS -type pgpin -pin VSSG -inst pgaorep_* -module {} -verbose
	# (binding not checkable here — see the PG4 NOTE above; the geometric
	# repeater gate runs after their post-place sroute below)
}


verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.preplace.rpt
fixVia -short
fixVia -minCut
fixVia -minStep

# Reserve M7/M8 for power during signal routing.
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 7
createRouteBlk -box 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT -layer 8

################################################################################
# Placement
################################################################################
# (M17: the addWellTap pass moved UP before the power routing — FILLBIAS
# taps must exist when the secondary sroute runs. See the power section.)

# M17b: hard-block the two rows the switch checkerboard leaves uncovered —
# the BOTTOM row (1,1) and the right U-leg TOP row (581,1047). Their VDD_SW
# rails are permanently dead (IMPPSO-306 warns and the run rolls on) and
# place_opt parked 52 live cells (bnd_irq_* boundary flops, hart_id
# inverters) on the bottom one; blocked, they stay EMPTY — a dead floating
# rail with nothing live on it. Well taps already placed there are fine
# (FILLBIAS biases the wells from VNW/VPW = the AO nets; its VDD frame pin
# merely abuts the dead stub). POSITION IS LOAD-BEARING — the blockages must
# be created HERE, after everything upstream and just before place_opt:
#  * before addPowerSwitch they shift its checkerboard phase and the
#    uncovered rows MOVE ((1,1047)/(581,1045) went dark instead);
#  * before sroute they suppress the blocked rows' follow-pin rails and the
#    dead-row well-tap VDD frames go "unconnected" at signoff (6 IMPVFC-96).
# Do NOT cutRow the bottom row instead (re-flips every row's orientation
# parity above it — ~1000 M1 abutment shorts, proven) and do NOT drop the
# checkerboard (M1 pin-frame shorts wherever pmk cells stack vertically,
# also proven). Acceptance for any rerun: every IMPPSO-306 row lies inside
# one of these boxes, and no live cell places at row-origin y=1 or in the
# right-leg top row.
createPlaceBlockage -type hard -name dead_row_bottom \
	-box [list 0 0 $DESIGN_WIDTH 3]
createPlaceBlockage -type hard -name dead_row_rleg_top \
	-box [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 3}] $DESIGN_WIDTH $DESIGN_HEIGHT]
printStatus "Blocked the 2 switchless dead-rail rows"

################################################################################
# CPR5 (2026-08-14): THE ram0 CLOCK MUX'S SPURIOUS ClockMuxGlitchFree CHECK.
#
# CPR2's external TCM read port gave ram0/CLK a SECOND gated source: the tile
# now muxes clk_mem(1) (adddec's cg_mem, a gated clk_cpu) against tx_ext_clk
# (cg_tcm_ext, a directly gated mclk) on `tx_sel`. Innovus reads that mux as a
# clock gate and applies clock-gating setup/hold checks from tx_sel_reg to the
# mux, which is the SAME spurious check the TIMER's ClockMuxGlitchFree raises
# at assembly level (M14 precedent, re-derived for M19 in
# MCU_ARGUS/tcl/MCU_ARGUS.innovus.tcl:606-619).
#
# MEASURED COST OF NOT DISABLING IT (first CPR5 harden, 2026-08-15): signoff
# hold VIOLATED **-8.716 ns** on `Clock Gating Hold Check with Pin g1722/B`,
# after the hold fixer had already strung **>100 DLY4X0P5MA10TH cells
# (~11 ns) onto tx_sel** — exactly the "burns ~40 DLY cells / ~11 ns and then
# overshoots" behaviour the M14 note describes, at tile scale. That delay line
# is not merely wasted area: tx_sel is the ram0 mux SELECT, and delaying it
# 11 ns inside a 40 ns period moves the mux switch instant far enough to
# invalidate the lead/lag argument the port's correctness rests on.
#
# WHY THE CHECK IS SPURIOUS HERE (hart_tile.vhd:1174-1186, and it is an
# argument, not an assertion): tx_ext_clk is LOW except for exactly one pulse,
# at the edge leaving TX_READ, and clk_mem(1) is low across both mux switch
# instants because the core's clk_cpu has been gated off since the lead cycle.
# A mux whose two inputs are both low at the switch instant cannot glitch.
#
# The gate names are SYNTH-RUN DEPENDENT (this cut: g1721 = the OAI2XB1
# driving ram_clk, g1722 = the NAND2 on {tx_sel, tx_ext_clk}), so they are
# DERIVED from the DB rather than hardcoded — the Argus timer disable silently
# no-op'd for a whole spin when an M19 re-synth renamed g11710. Derivation:
# the instance(s) driving `ram_clk` that also touch `tx_sel`, plus one hop back
# through the mux's OWN internal nets (never through tx_sel itself, whose
# fanout is the entire 6-pin mux and the tx FSM).
################################################################################
# `fatal` = 1 for the pre-place call (the load-bearing one; if the mux cannot be
# found there the netlist is not a CPR2 tile and nothing downstream is valid) and
# 0 for the post-CTS re-apply, which is belt-and-braces: by then CTS has cloned
# and RENAMED both the select net (tx_sel -> FE_PHC<n>_tx_sel) and the clock net,
# so the derivation is glob-based and may legitimately land on the buffered
# copies. The BINDING proof that the disable took is the tx_sel DLY-cell gate
# after optDesign -postRoute, not this re-apply.
proc cpr5_disable_ram_clk_mux_check {tag fatal} {
	# Anchor on ram0's CLK pin, not on a net NAME: CTS renames nets, and a
	# name-matched derivation that silently returns nothing is precisely the
	# failure mode this whole constraint exists to avoid.
	set __ram0 [dbGet -p top.insts.name ram0]
	set __rc 0x0
	if {$__ram0 != 0x0} {
		foreach __t [dbGet $__ram0.instTerms] {
			if {[dbGet $__t.name] eq "ram0/CLK"} { set __rc [dbGet $__t.net] }
		}
	}
	if {$__rc == 0x0} {
		logPuts "FATAL (CPR5): ram0/CLK has no net — the CPR2 ram0 clock mux is missing from this netlist. Aborting."
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
	foreach __gg $__g {
		set __ii [dbGet -p top.insts.name $__gg]
		if {$__ii == 0x0} { continue }
		foreach __t [dbGet $__ii.instTerms] {
			set __n2 [dbGet $__t.net]
			if {$__n2 == 0x0} { continue }
			set __n2n [dbGet $__n2.name]
			# never hop through the SELECT net (its fanout is the whole 6-pin
			# mux and the tx FSM) nor back out along the clock net itself
			if {[string match *tx_sel* $__n2n]} { continue }
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
	logPuts "### UNL STATUS ### : CPR5 ram_clk mux gates ($tag): $__g"
	if {[llength $__g] < 1 || [llength $__g] > 6} {
		if {$fatal} {
			logPuts "FATAL (CPR5): ram_clk mux derivation found [llength $__g] gates (expect 2 — the tx_sel NAND and the OAI driving ram_clk). Aborting."
			exit 1
		}
		logPuts "### UNL STATUS ### : CPR5 re-apply ($tag) found [llength $__g] gates — skipped; the pre-place disable stands and the tx_sel DLY gate is the proof."
		return
	}
	set_interactive_constraint_modes [all_constraint_modes -active]
	foreach __m $__g {
		if {[catch {set_disable_clock_gating_check $__m} __r]} {
			logPuts "### UNL STATUS ### : CPR5 gating-check disable SKIPPED for $__m ($tag): $__r"
		} else {
			logPuts "### UNL STATUS ### : CPR5 gating-check disabled on $__m ($tag)"
		}
	}
	set_interactive_constraint_modes {}
}
cpr5_disable_ram_clk_mux_check preplace 1

place_opt_design
printStatus "Placement done"

# PG1 F1: the GPGBUF repeaters were UNPLACED when the secondary-pin sroute
# ran (it must run pre-place for the fixed switches/taps; the repeaters are
# ordinary movable cells that place_opt just legalized) — hook their AO
# supply pins (VDDG/VSSG, globalNetConnect'd above) up now, instance-
# targeted so nothing else is re-routed. verifyConnectivity at signoff is
# the backstop if this pass ever strands a pin.
if {[info exists PG1_NREP] && $PG1_NREP > 0} {
	printStatus "PG1: strapping the GPGBUF repeaters' secondary AO pins (PG4 M2 straps)"
	# LIFT the pre-place corridor blockages now.  They existed to keep
	# place_opt's trial routing out of the link corridors; from here to F2b
	# nothing routes, so the corridors stay clear -- and the supply pass below
	# needs M2 over each repeater to draw its VDDG/VSSG fingers and vias.
	set __nlift 0
	foreach __cb $::PG1_CORR_BLKS {
		foreach {__cbn __cx0 __cy0 __cx1 __cy1} $__cb {}
		set __done 0
		catch { deleteRouteBlk -name $__cbn ; set __done 1 }
		if {!$__done} {
			catch {
				foreach __o [dbGet top.fPlan.rBlkgs -e] {
					set __bb [lindex [dbGet $__o.boxes] 0]
					if {[llength $__bb] != 4} { continue }
					if {abs([lindex $__bb 0] - $__cx0) < 0.01 && abs([lindex $__bb 1] - $__cy0) < 0.01} {
						dbDeleteObj $__o ; set __done 1 ; break
					}
				}
			}
		}
		if {$__done} { incr __nlift }
	}
	logPuts "### UNL STATUS ### : PG1 lifted $__nlift/[llength $::PG1_CORR_BLKS] pre-place corridor blockages before the supply pass"
	if {$__nlift < [llength $::PG1_CORR_BLKS]} {
		logPuts "FATAL (PG1): could not lift every corridor blockage -- the supply pass would find M2 fenced off over the repeaters and PG4/F1 would report them unsupplied."
		saveDesign dbs/pg4rep_fail.innovus
		exit 1
	}
	# PG4 v19: PIN THE REPEATERS FIRST. The v18 signoff DB had all four
	# pgaorep hookups stranded 1.1-1.2 um from their cells: this stage runs
	# right after place_opt, but the repeaters are ordinary MOVABLE cells —
	# CTS/optDesign/postRoute-ECO relocated them AFTER the metal was drawn.
	# The in-flow via gate passed against the pre-CTS positions; the tell
	# was signoff verifyConnectivity IMPVFC-96 on every pgaorep VDDG+VSSG.
	# Headers/taps/FILLBIAS are preplaced fixed; the repeaters must be too
	# the moment their hand-drawn supply metal exists.
	dbSet [dbGet -p top.insts.name pgaorep_*].pStatus fixed
	# PG4: the old per-inst secondaryPowerPin sroute here is DELETED — at
	# v11 it landed a VSS via pad on pgaorep_2's own Y OUTPUT pin (M1
	# short marker; electrically the SLEEP chain pinned low = every
	# switch forced awake, invisible to any netlist check). The M2 strap
	# recipe below is the whole hookup; the via gate verifies it.
	# BUT addStripe only vias onto special-wire shapes, never onto PIN
	# geometry (v13: 4 repeaters unsupplied once the sroute fingers were
	# gone — the column fabric always via'd onto the first sroute's M1
	# fingers). So draw the fingers OURSELVES: M1 rects inset 0.01 inside
	# the VDDG/VSSG pin bar outlines — zero geometry beyond the pin, no
	# short possible. Bars per orient (cell 1.4 x 2.0, LEF R0 coords):
	#   VDDG: (0.37-0.55, 1.40-1.74) and (0.93-1.10, 1.45-1.74)
	#   VSSG: (0.36-0.53, 0.265-0.555) and (0.93-1.10, 0.265-0.59)
	proc pg4_rep_finger {net inst bar} {
		set bx [lindex [dbGet $inst.box] 0]
		foreach {x0 y0 x1 y1} $bx {}
		set or [dbGet $inst.orient]
		foreach {bx0 by0 bx1 by1} $bar {}
		set w 1.4; set h 2.0
		if {$or eq "MY" || $or eq "R180"} {
			set tx0 [expr {$w - $bx1}]; set tx1 [expr {$w - $bx0}]
		} else { set tx0 $bx0; set tx1 $bx1 }
		if {$or eq "MX" || $or eq "R180"} {
			set ty0 [expr {$h - $by1}]; set ty1 [expr {$h - $by0}]
		} else { set ty0 $by0; set ty1 $by1 }
		add_shape -net $net -layer M1 -rect [list 			[expr {$x0 + $tx0 + 0.01}] [expr {$y0 + $ty0 + 0.01}] 			[expr {$x0 + $tx1 - 0.01}] [expr {$y0 + $ty1 - 0.01}]] 			-shape STRIPE -status ROUTED
	}
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		pg4_rep_finger VDD $__i {0.37 1.40 0.55 1.74}
		pg4_rep_finger VDD $__i {0.93 1.45 1.10 1.74}
		pg4_rep_finger VSS $__i {0.36 0.265 0.53 0.555}
		pg4_rep_finger VSS $__i {0.93 0.265 1.10 0.59}
	}
	# PG4 F1 repeater supply straps + gate. The sroute above only fingers
	# the pins (PG2 found the run-10 repeaters UNPOWERED — the devlog's "AO
	# straps drawn" probe claim was never reproducible); give each pgaorep
	# a real M2 mini-strap per supply pin, engine-via'd like the column
	# straps (VIA1 on the pin + stacked vias at the M8-grid crossing).
	# GPGBUFX4 pin bars (LEF, x-disjoint on purpose): VDDG bar x0+0.37..0.55,
	# VSSG bar x0+0.93..1.10. The strap extends to just past the nearest
	# same-net M8 stripe (grid: VDD lly=51+50k, VSS lly=60+50k), direction
	# picked to stay inside the core and out of ram0/the notch.
	proc pg4_rep_strap {net sx y0 y1} {
		# find nearest same-net M8 stripe lly above y1 and below y0
		global DESIGN_HEIGHT DESIGN_WIDTH FINGER_W BASE_H
		set base [expr {$net eq "VDD" ? 51.0 : 60.0}]
		set kup [expr {int(ceil(($y1 + 2 - $base) / 50.0))}]
		set yup [expr {$base + 50.0 * $kup + 6.0}]
		set kdn [expr {int(floor(($y0 - 8 - $base) / 50.0))}]
		set ydn [expr {$base + 50.0 * $kdn - 1.0}]
		set ram [lindex [dbGet [dbGet -p top.insts.name ram0].box] 0]
		foreach {rx0 ry0 rx1 ry1} $ram {}
		set upok 1
		if {$yup > [expr {$DESIGN_HEIGHT - 2}]} { set upok 0 }
		if {$sx > [expr {$rx0 - 1}] && $sx < [expr {$rx1 + 1}] && $y1 < $ry1 && $yup > $ry0} { set upok 0 }
		if {$sx > [expr {$FINGER_W - 1}] && $sx < [expr {$DESIGN_WIDTH - $FINGER_W + 1}] && $yup > [expr {$BASE_H - 2}]} { set upok 0 }
		if {$upok} {
			set ay0 [expr {$y0 - 0.2}]
			set ay1 $yup
		} else {
			set ay0 $ydn
			set ay1 [expr {$y1 + 0.2}]
			if {$sx > [expr {$rx0 - 1}] && $sx < [expr {$rx1 + 1}] && $y0 > $ry0 && $ay0 < $ry1} {
				logPuts "FATAL (PG4/F1): repeater strap at x=$sx has no clean path to an M8 $net stripe. Aborting."
				exit 1
			}
		}
		# a different-net M2 strap (tap/header column) in this band = short:
		# report failure so the caller can try the pin's OTHER bar.
		# window = band + the 0.1 um M2 min spacing, EXACTLY — a 0.15
		# margin false-flagged a legal 0.13 gap (pgaorep_3, bring-up v10)
		foreach __o [dbQuery -area [list [expr {$sx - 0.099}] $ay0 [expr {$sx + 0.399}] $ay1] -objType sWire] {
			if {[dbGet -e $__o.layer.name] eq "M2" && [dbGet -e $__o.net.name] ne $net} {
				logPuts "PG4: repeater $net strap band at x=$sx collides with an M2 [dbGet -e $__o.net.name] strap — trying the alternate bar"
				return 0
			}
		}
		addStripe -layer M2 -nets [list $net] -direction vertical -width 0.3 \
			-set_to_set_distance 1000 -start_offset 0.2 -stop_offset 0.05 \
			-area [list [expr {$sx - 0.2}] $ay0 [expr {$sx + 0.5}] $ay1]
		return 1
	}
	setAddStripeMode -reset
	setAddStripeMode \
		-stacked_via_top_layer M8 \
		-stacked_via_bottom_layer M1 \
		-extend_to_closest_target none \
		-split_long_via $RISER_VIA_SPLIT
	set __rep_vdd_band [dict create]
	set __rep_railjump {}
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__bx {}
		set __or [dbGet $__i.orient]
		# GPGBUFX4 has TWO mirrored vertical bars per supply pin: R0/MX
		# VDDG at 0.37-0.55 and 0.93-1.10, VSSG at 0.93-1.10 and 0.36-0.53
		# (MY/R180 mirror in x: llx' = 1.4 - llx - 0.3). Try each candidate
		# bar; skip any whose 0.3-um band would touch a column strap of the
		# other net (pg4_rep_strap collision check) or the band already
		# claimed for this repeater's other supply.
		if {$__or eq "R0" || $__or eq "MX"} {
			set __vddc {0.37 0.80}
			set __vssc {0.80 0.30}
		} elseif {$__or eq "MY" || $__or eq "R180"} {
			set __vddc {0.73 0.30}
			set __vssc {0.30 0.77}
		} else {
			logPuts "FATAL (PG4/F1): repeater [dbGet $__i.name] orient $__or unsupported by the strap recipe. Aborting."
			exit 1
		}
		set __vdd_band ""
		foreach __c $__vddc {
			if {[pg4_rep_strap VDD [expr {$__x0 + $__c}] $__y0 $__y1]} { set __vdd_band $__c; break }
		}
		dict set __rep_vdd_band [dbGet $__i.name] $__vdd_band
		if {$__vdd_band eq ""} {
			logPuts "FATAL (PG4/F1): no collision-free VDD bar for repeater [dbGet $__i.name]. Aborting."
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
		set __vss_done 0
		foreach __c $__vssc {
			if {abs($__c - $__vdd_band) < 0.4} { continue }
			if {[pg4_rep_strap VSS [expr {$__x0 + $__c}] $__y0 $__y1]} { set __vss_done 1; break }
		}
		# M19c RAIL JUMPER -- UNCONDITIONAL SINCE 2026-08-25.
		# It used to be a FALLBACK taken only when BOTH candidate M2 VSS bands
		# collided with a column strap, and that made grounding the always-on
		# repeaters a PLACEMENT LOTTERY.  Measured: the 2026-08-17 cut took the
		# jumper on 2 of 4 repeaters, the 2026-08-25 cut on 1 of 4, and every
		# repeater that did NOT take it came out with a FLOATING VSSG -- four
		# nch_hvt source/drains, no bulk, no tap, no wire, no via.  Pegasus
		# reported all three as OPEN layout nets (X3/3733, X4/4946, X4/4947).
		# An always-on SLEEP repeater with a pull-up and no pull-down.
		# The M2 strap above still runs whenever it can; this is now belt AND
		# braces.  Ground is unswitched, the jumper is additive same-net M1
		# inside the cell's own pin bar, and it is LVS-proven on 7072 FILLBIAS
		# VPW pins -- there was never a reason to make it conditional.
		if {1} {
			# (first hit: pgaorep_0 on the M19c resynth
			# placement — both M2 VSS bands collided with column straps).
			# The VSSG pin never actually NEEDS the M2 mini-strap: ground
			# is unswitched, so the row follow-pin rail IS VSS and the
			# cell's own VSS rail pin (LEF: full-width at y<=0.15) sits
			# 0.115 um below the VSSG bar (y>=0.265) with NO foreign M1
			# between them at the bar's x (0.36-0.53 R0; checked against
			# the USEfix LEF OBS rects). Drop an in-cell M1 jumper from
			# bar to rail — the FILLBIAS VPW jumper trick, LVS-proven at
			# PG4 on 7072 pins. VDD has NO such fallback (row rails are
			# VDD_SW, must never touch VDDG) — its collision stays FATAL.
			if {$__or eq "MY" || $__or eq "R180"} {
				set __jx0 [expr {$__x0 + 1.4 - 0.53}]
				set __jx1 [expr {$__x0 + 1.4 - 0.36}]
			} else {
				set __jx0 [expr {$__x0 + 0.36}]
				set __jx1 [expr {$__x0 + 0.53}]
			}
			if {$__or eq "MX" || $__or eq "R180"} {
				set __jy0 [expr {$__y1 - 0.45}]
				set __jy1 [expr {$__y1 + 0.10}]
			} else {
				set __jy0 [expr {$__y0 - 0.10}]
				set __jy1 [expr {$__y0 + 0.45}]
			}
			add_shape -net VSS -layer M1 -rect [list $__jx0 $__jy0 $__jx1 $__jy1] -shape STRIPE -status ROUTED
			set __jwhy [expr {$__vss_done ? "M2 mini-strap also drawn" : "both M2 bands collide"}]
			logPuts "PG4/M19c: repeater [dbGet $__i.name] VSSG hooked via RAIL JUMPER at x=$__jx0 ($__jwhy)"
			lappend __rep_railjump [dbGet $__i.name]
			set __vss_done 1
		}
	}
	# LUP.6 flow fix, part 2 (2026-08-25): strap each pre-placed n-well tap.
	# A tap whose VNW is not tied to VDD does not stop latch-up, it only
	# silences the checker -- so the bar gets a real M1 pad (the PG4/F2
	# pattern: pin geometry is invisible to editPowerVia, only sWires are
	# not), an M2 jog east into the repeater's OWN always-on VDDG M2 band,
	# and the per-repeater editPowerVia below makes the via: its window is
	# the cell bbox +-0.5, and the tap abuts the cell, so the tap is inside
	# it already.  FAIL-SOFT throughout -- a tap that cannot be strapped is
	# reported and left to the post-harden DRC ECO, never fatal.
	set __nwstrapped 0
	foreach __t $::PG1_NWTAPS {
		foreach {__tn __trep __ttx __tty __tor} $__t {}
		set __tp [dbGet -p top.insts.name $__tn -e]
		if {$__tp eq "0x0" || $__tp eq "" || $__tp eq "0"} {
			logPuts "PG1 NWTAP: $__tn is gone from the DB -- not strapped"
			continue
		}
		if {![dict exists $__rep_vdd_band $__trep]} {
			logPuts "PG1 NWTAP: no VDDG band recorded for $__trep -- $__tn not strapped"
			continue
		}
		set __tband [dict get $__rep_vdd_band $__trep]
		if {$__tband eq ""} { continue }
		set __rp [dbGet -p top.insts.name $__trep -e]
		if {$__rp eq "0x0" || $__rp eq "" || $__rp eq "0"} { continue }
		foreach {__prx0 __pry0 __prx1 __pry1} [lindex [dbGet $__rp.box] 0] {}
		set __bandx1 [expr {$__prx0 + $__tband + 0.3}]
		foreach {__tx0 __ty0 __tx1 __ty1} [lindex [dbGet $__tp.box] 0] {}
		# FILLBIASNWA10TH VNW bar, LEF R0: RECT 0.150 1.210 0.250 1.730
		if {[dbGet $__tp.orient] eq "MX" || [dbGet $__tp.orient] eq "R180"} {
			set __npy0 [expr {$__ty1 - 1.730}] ; set __npy1 [expr {$__ty1 - 1.210}]
		} else {
			set __npy0 [expr {$__ty0 + 1.210}] ; set __npy1 [expr {$__ty0 + 1.730}]
		}
		set __npx0 [expr {$__tx0 + 0.150}] ; set __npx1 [expr {$__tx0 + 0.250}]
		if {$__bandx1 <= $__npx0} {
			logPuts "PG1 NWTAP: the VDDG band of $__trep ends at $__bandx1, west of $__tn's pad at $__npx0 -- not strapped"
			continue
		}
		set __njc [expr {($__npy0 + $__npy1) / 2.0}]
		set __njog [list $__npx0 [expr {$__njc - 0.15}] $__bandx1 [expr {$__njc + 0.15}]]
		# clearance: nothing foreign on M2 in the jog corridor
		set __ndirty 0
		foreach __q {sWire wire} {
			foreach __o [dbQuery -area [list [expr {[lindex $__njog 0] - 0.10}] [expr {[lindex $__njog 1] - 0.10}] \
			                            [expr {[lindex $__njog 2] + 0.10}] [expr {[lindex $__njog 3] + 0.10}]] -objType $__q] {
				if {[dbGet -e $__o.layer.name] ne "M2"} { continue }
				if {[dbGet -e $__o.net.name] eq "VDD"} { continue }
				incr __ndirty
			}
		}
		if {$__ndirty > 0} {
			logPuts "PG1 NWTAP: $__ndirty foreign M2 shape(s) in $__tn's jog corridor $__njog -- not strapped"
			continue
		}
		add_shape -net VDD -layer M1 -rect [list $__npx0 $__npy0 $__npx1 $__npy1] -shape STRIPE -status ROUTED
		add_shape -net VDD -layer M2 -rect $__njog -shape STRIPE -status ROUTED
		incr __nwstrapped
		logPuts [format "PG1 NWTAP: %s VNW pad {%.3f %.3f %.3f %.3f} + VDDG jog {%.3f %.3f %.3f %.3f} laid" \
			$__tn $__npx0 $__npy0 $__npx1 $__npy1 \
			[lindex $__njog 0] [lindex $__njog 1] [lindex $__njog 2] [lindex $__njog 3]]
	}
	logPuts "### UNL STATUS ### : PG1 LUP.6 pre-emptive n-well taps -- [llength $::PG1_NWTAPS] placed, $__nwstrapped strapped to a VDDG band"
	# VDDG via (PG4 v22, GDS-real form): the v18-v21 `add_via VIA1_V` here
	# was a GDS-PHANTOM — add_via specials pass every in-DB gate but
	# streamOut silently drops them (single-via A/B proof; same mechanism as
	# the strap-grid repair above). The finger (M1, in-pin) and the strap
	# (M2) OVERLAP in plan on the chosen band, so the ENGINE can via them:
	# per-repeater editPowerVia M1->M2, tightly windowed to the cell bbox
	# +0.5 so nothing else is touched. VSSG GETS THE SAME TREATMENT (2026-
	# 08-25): see the comment at the second editPowerVia below for why the
	# old "VSSG needs nothing extra" claim was wrong and what it cost.
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__rx0 __ry0 __rx1 __ry1} $__bx {}
		# -orthogonal_only 0: finger and strap are both VERTICAL — the
		# default only vias orthogonal crossings (v22b FATAL; probe-proven
		# 0 -> 1 via with the flag).
		editPowerVia -add_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -orthogonal_only 0 \
			-area [list [expr {$__rx0 - 0.5}] [expr {$__ry0 - 0.5}] [expr {$__rx1 + 0.5}] [expr {$__ry1 + 0.5}]]
		# THE VSS COUNTERPART, ADDED 2026-08-25.  The comment above used to
		# say VSSG needed nothing extra because "the VSS strap crosses the
		# VSS rails and the engine already vias those".  That is true and it
		# is not the point: via'ing the M2 strap to the VSS RAIL says nothing
		# about the VSSG BAR, which is a DIFFERENT M1 island under the same
		# strap and gets no via for exactly the reason the VDD line above
		# already identifies -- finger and strap are both VERTICAL, and the
		# default only vias orthogonal crossings.  Three of the four
		# repeaters on the 2026-08-25 cut shipped with a floating VSSG
		# because of that one missing line.
		editPowerVia -add_vias 1 -nets VSS -bottom_layer M1 -top_layer M2 -orthogonal_only 0 \
			-area [list [expr {$__rx0 - 0.5}] [expr {$__ry0 - 0.5}] [expr {$__rx1 + 0.5}] [expr {$__ry1 + 0.5}]]
	}
	# PG4 F1 ACCEPTANCE -- ASK THE BAR, NOT THE BOX (rewritten 2026-08-25).
	#
	# The gate that stood here was `pg4_has_svia $__bx VSS`: "is there ANY
	# special via on net VSS within the cell bbox +0.5".  Inside a powered row
	# the answer is ALWAYS yes, because the follow-pin rail running under the
	# cell carries via1 arrays.  The check was UNFALSIFIABLE, and on the
	# 2026-08-25 cut it passed and logged "all GPGBUF AO supplies via'd" over
	# THREE DEAD REPEATERS.  Pegasus found them: layout nets X3/3733, X4/4946
	# and X4/4947 each had exactly four attachments, all four source/drain
	# terminals of nch_hvt inside one cell -- no bulk, no tap, no wire, no via.
	#
	# A supply pin is hooked up only if ITS OWN M1 PIN BAR carries a VIA1, or
	# (VSSG only) an M1 jumper that leaves the bar and reaches the row rail.
	# The pg4_rep_finger pin redraw is INSIDE the bar by construction, so it
	# can never satisfy the second test -- which is precisely why the test is
	# written that way.  Same hole exists in the header/tap column gates; VDD
	# merely happens to pass there.
	proc pg4_bar_abs {inst bar} {
		foreach {x0 y0 x1 y1} [lindex [dbGet $inst.box] 0] {}
		set or [dbGet $inst.orient]
		foreach {bx0 by0 bx1 by1} $bar {}
		set w 1.4; set h 2.0
		if {$or eq "MY" || $or eq "R180"} {
			set tx0 [expr {$w - $bx1}]; set tx1 [expr {$w - $bx0}]
		} else { set tx0 $bx0; set tx1 $bx1 }
		if {$or eq "MX" || $or eq "R180"} {
			set ty0 [expr {$h - $by1}]; set ty1 [expr {$h - $by0}]
		} else { set ty0 $by0; set ty1 $by1 }
		return [list [expr {$x0 + $tx0}] [expr {$y0 + $ty0}] [expr {$x0 + $tx1}] [expr {$y0 + $ty1}]]
	}
	# a VIA1 of $net whose CENTRE falls inside one of the pin's own bars
	proc pg4_bar_via {inst bars net} {
		foreach bar $bars {
			set r [pg4_bar_abs $inst $bar]
			foreach {rx0 ry0 rx1 ry1} $r {}
			foreach o [dbQuery -area $r -objType sVia] {
				if {[dbGet -e $o.net.name] ne $net} { continue }
				if {![string match -nocase via1* [dbGet -e $o.via.name]]} { continue }
				set px [dbGet $o.pt_x]; set py [dbGet $o.pt_y]
				if {$px < [expr {$rx0 - 0.06}] || $px > [expr {$rx1 + 0.06}]} { continue }
				if {$py < [expr {$ry0 - 0.06}] || $py > [expr {$ry1 + 0.06}]} { continue }
				return 1
			}
		}
		return 0
	}
	# an M1 special wire of $net that overlaps the bar AND reaches a row rail
	# (the M19c jumper).  The in-pin finger cannot pass: it is inset inside
	# the bar and never comes within 0.15 um of either rail.
	proc pg4_bar_jumper {inst bars net} {
		foreach {ix0 iy0 ix1 iy1} [lindex [dbGet $inst.box] 0] {}
		foreach bar $bars {
			set r [pg4_bar_abs $inst $bar]
			foreach o [dbQuery -area $r -objType sWire] {
				if {[dbGet -e $o.net.name] ne $net} { continue }
				if {[dbGet -e $o.layer.name] ne "M1"} { continue }
				foreach {ox0 oy0 ox1 oy1} [lindex [dbGet $o.box] 0] {}
				if {$oy0 <= [expr {$iy0 + 0.15}]} { return 1 }
				if {$oy1 >= [expr {$iy1 - 0.15}]} { return 1 }
			}
		}
		return 0
	}
	set PG4_VDDG_BARS {{0.37 1.40 0.55 1.74} {0.93 1.45 1.10 1.74}}
	set PG4_VSSG_BARS {{0.36 0.265 0.53 0.555} {0.93 0.265 1.10 0.59}}
	set __rep_bad 0
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __nm [dbGet $__i.name]
		set __dv [pg4_bar_via $__i $PG4_VDDG_BARS VDD]
		set __sv [pg4_bar_via $__i $PG4_VSSG_BARS VSS]
		set __sj [pg4_bar_jumper $__i $PG4_VSSG_BARS VSS]
		if {!$__dv} {
			incr __rep_bad
			logPuts "PG4 F1: repeater $__nm VDDG BAR carries no VIA1 on net VDD -- the always-on supply is floating"
		}
		if {!$__sv && !$__sj} {
			incr __rep_bad
			logPuts "PG4 F1: repeater $__nm VSSG BAR carries no VIA1 and no rail jumper -- VSSG is FLOATING"
		}
		logPuts "PG4 F1: repeater $__nm supplies -- VDDG bar via=$__dv, VSSG bar via=$__sv, VSSG rail jumper=$__sj"
	}
	if {$__rep_bad > 0} {
		logPuts "FATAL (PG4/F1): $__rep_bad GPGBUF repeater supply pins unsupplied — dead AO repeaters re-break the SLEEP chain. Saving dbs/pg4rep_fail.innovus; aborting."
		saveDesign dbs/pg4rep_fail.innovus
		exit 1
	}
	logPuts "### UNL STATUS ### : PG4 F1 repeater gate -- every GPGBUF AO supply PIN BAR is via'd or rail-jumpered"
	# PG4/F2b (2026-07-11): the repeater VDDG strap is an ISLAND unless it
	# happens to catch an engine stack — F2b seed left pgaorep_2's 52-um
	# strap with a pin via1 and NOTHING upward (via2=0; the nearest ladder
	# passed 2.35 um above its top). The via gate above only proves the PIN
	# hop. Deterministic grid hop: one horizontal SAME-LAYER M2 link from
	# each repeater strap to the nearest main strap column with y-overlap
	# (touching same-net metal, no vias — the proven ladder mechanism; the
	# main columns are grid-connected by the post-route strap-grid repair).
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__rx0 __ry0 __rx1 __ry1} $__bx {}
		# the repeater's OWN strap piece: M2 VDD that x-OVERLAPS the cell
		# bbox, 4-60 um tall. First F2c run grabbed the nearest MAIN column
		# (full height, 2 um away) instead and self-linked it — x-overlap
		# and the height ceiling exclude main columns and ladder rungs.
		set __sp ""
		foreach __o [dbQuery -area [list [expr {$__rx0 - 2.0}] [expr {$__ry0 - 60.0}] [expr {$__rx1 + 2.0}] [expr {$__ry1 + 60.0}]] -objType sWire] {
			if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
			set __b2 [lindex [dbGet $__o.box] 0]
			foreach {__px0 __py0 __px1 __py1} $__b2 {}
			set __h [expr {$__py1 - $__py0}]
			if {$__h < 4.0 || $__h > 60.0} { continue }
			if {$__px1 < $__rx0 || $__px0 > $__rx1} { continue }
			set __sp $__b2
			break
		}
		if {$__sp eq ""} {
			# ---- CPR5 (2026-08-14): THE SAME-NET-COLUMN TRIM CASE ----------
			# First seen on the penta re-harden: pgaorep_1 landed at x 352.8
			# with its 1.4-um cell STRADDLING a main VDD strap column
			# (353.325-353.625). Both candidate VDDG bars (R180: x0+0.73 and
			# x0+0.30) therefore x-overlap that column, so pg4_rep_strap's
			# collision check — which only rejects a DIFFERENT-net M2 band —
			# passed, addStripe drew the mini-strap, and the engine TRIMMED it
			# against the same-net column it ran into: 396.8-397.6 instead of
			# 396.8-407.0, a 0.8-um remnant sitting 0.4 um BELOW the column.
			# The remnant carries the pin's VIA1 (the F1 gate above counts it)
			# but is an ISLAND, and it is invisible to the 4-60 um search
			# above, whose floor exists to exclude 0.3-um ladder rungs.
			# There is no band that avoids this: the column is narrower than
			# the cell and sits in the middle of it, so BOTH bars collide —
			# which is why the repair is a bridge, not a re-placement.
			# Repair = the F2b link idiom rotated 90 deg: one same-layer M2
			# patch spanning both x ranges across the y gap, so the remnant
			# merges into the column (which the post-route strap-grid repair
			# already ties to the M8 grid). Clearance-checked and FATAL-gated
			# exactly like the horizontal links; NOTHING changes for a
			# repeater whose 4-60 um strap was found normally.
			set __rem ""
			foreach __o [dbQuery -area [list [expr {$__rx0 - 2.0}] [expr {$__ry0 - 8.0}] [expr {$__rx1 + 2.0}] [expr {$__ry1 + 8.0}]] -objType sWire] {
				if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
				set __b2 [lindex [dbGet $__o.box] 0]
				foreach {__ax0 __ay0 __ax1 __ay1} $__b2 {}
				set __h [expr {$__ay1 - $__ay0}]
				# the trimmed remnant: taller than a 0.3 rung, shorter than
				# the 4.0 floor that already failed above
				if {$__h < 0.4 || $__h >= 4.0} { continue }
				if {$__ax1 < $__rx0 || $__ax0 > $__rx1} { continue }
				set __rem $__b2
				break
			}
			set __col ""; set __side ""
			if {$__rem ne ""} {
				foreach {__ax0 __ay0 __ax1 __ay1} $__rem {}
				foreach __o [dbQuery -area [list [expr {$__ax0 - 0.5}] [expr {$__ay0 - 3.0}] [expr {$__ax1 + 0.5}] [expr {$__ay1 + 3.0}]] -objType sWire] {
					if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
					set __b3 [lindex [dbGet $__o.box] 0]
					foreach {__qx0 __qy0 __qx1 __qy1} $__b3 {}
					# only a MAIN column qualifies as the reconnection target
					if {[expr {$__qy1 - $__qy0}] <= 60.0} { continue }
					if {$__qx1 < [expr {$__ax0 - 0.4}] || $__qx0 > [expr {$__ax1 + 0.4}]} { continue }
					if {$__qy0 >= $__ay1 && [expr {$__qy0 - $__ay1}] < 2.0} { set __col $__b3; set __side up;   break }
					if {$__qy1 <= $__ay0 && [expr {$__ay0 - $__qy1}] < 2.0} { set __col $__b3; set __side down; break }
				}
			}
			if {$__col eq ""} {
				logPuts "FATAL (PG4/F2b): repeater [dbGet $__i.name] has no VDDG M2 strap piece to link. Saving dbs/pg4rep_fail.innovus; aborting."
				saveDesign dbs/pg4rep_fail.innovus
				exit 1
			}
			foreach {__qx0 __qy0 __qx1 __qy1} $__col {}
			# BRIDGE FOOTPRINT, and this is the part that has to be tight.
			# When the remnant and the column already x-OVERLAP (the straddle
			# case that creates this situation in the first place), the bridge
			# only has to grow the remnant UPWARD on its OWN x — widening it to
			# the union of both x ranges buys nothing and reaches 0.2 um further
			# left, which is exactly where the psoPSI SLEEP-chain M2 route runs
			# (measured on the CPR5 fail DB: the union footprint was blocked by
			# psoPSI...pg1rep at x 353.25-353.35, the remnant-width one is not).
			if {$__qx1 > $__ax0 && $__qx0 < $__ax1} {
				set __bx0 $__ax0
				set __bx1 $__ax1
			} else {
				set __bx0 [expr {min($__ax0, $__qx0)}]
				set __bx1 [expr {max($__ax1, $__qx1)}]
			}
			if {$__side eq "up"} {
				set __by0 [expr {$__ay1 - 0.2}]; set __by1 [expr {$__qy0 + 0.2}]
				set __gap [expr {$__qy0 - $__ay1}]
			} else {
				set __by0 [expr {$__qy1 - 0.2}]; set __by1 [expr {$__ay0 + 0.2}]
				set __gap [expr {$__ay0 - $__qy1}]
			}
			# same clearance rule as the horizontal links: no FOREIGN M2 in the
			# patch footprint grown by the 0.10 um M2 narrow min-space
			set __clear 1
			set __cw [list [expr {$__bx0 - 0.10}] [expr {$__by0 - 0.10}] [expr {$__bx1 + 0.10}] [expr {$__by1 + 0.10}]]
			foreach __o [concat [dbQuery -area $__cw -objType sWire] [dbQuery -area $__cw -objType wire]] {
				if {[dbGet -e $__o.layer.name] ne "M2"} { continue }
				if {[dbGet -e $__o.net.name] eq "VDD"} { continue }
				set __clear 0; break
			}
			if {!$__clear} {
				logPuts "FATAL (PG4/F2b): repeater [dbGet $__i.name] same-net-trim bridge footprint ($__bx0 $__by0 $__bx1 $__by1) is blocked by foreign M2. Saving dbs/pg4rep_fail.innovus; aborting."
				saveDesign dbs/pg4rep_fail.innovus
				exit 1
			}
			add_shape -net VDD -layer M2 -rect [list $__bx0 $__by0 $__bx1 $__by1] -shape STRIPE -status ROUTED
			createRouteBlk -box [list [expr {$__bx0 - 0.1}] [expr {$__by0 - 0.1}] [expr {$__bx1 + 0.1}] [expr {$__by1 + 0.1}]] -layer 2
			logPuts "PG4/F2b(CPR5): repeater [dbGet $__i.name] mini-strap was TRIMMED by the same-net main column at x=$__qx0 ($__side) — bridged the [format %.2f $__gap] um gap with M2 [list $__bx0 $__by0 $__bx1 $__by1]"
			continue
		}
		foreach {__px0 __py0 __px1 __py1} $__sp {}
		# nearest main strap column with y-overlap
		# candidate main straps whose ACTUAL METAL y-overlaps the repeater
		# strap — the run band is NOT the metal (F2d: the H351 strap metal
		# starts at 398.0 while its band starts at 396; a 397.3 link
		# floated 0.4 um below the strap). Metal extents are SEED-VARIANT
		# per column, and 0.1-wide sleep-chain M2 routes block some scan
		# bands (F2e: pgaorep_0's nearest column only overlapped y >= 398.5
		# where the psoPSI wires run) — so try EVERY overlapping column in
		# distance order until one yields a clear link y.
		set __cands {}
		foreach __pr $__placed_runs {
			foreach {__key __msx __may0 __may1} $__pr {}
			if {$__may0 > [expr {$__py1 - 1.0}] || $__may1 < [expr {$__py0 + 1.0}]} { continue }
			set __d [expr {abs($__msx - $__px0)}]
			# SEARCH RADIUS 30 -> 45 um (2026-08-17), 45 -> 75 um (2026-08-25).
			# This cap is not a design rule, it is how far the search bothers to
			# look, and it keeps making the gate FLOORPLAN-FRAGILE: at 30 it
			# aborted three separate attempts (DESIGN_HEIGHT 920, the 2x macro
			# halo, and the L-shape) on repeaters whose nearest column had
			# simply moved further away.
			# 2026-08-25: it did it AGAIN, on the same repeater and with the
			# identical message, when the tile picked up the fetch-ahead RTL
			# (+233 instances, +1.4% standard-cell area):
			#     FATAL (PG4/F2b): no clear link y to any main strap column for
			#     repeater pgaorep_2 (9 candidates tried)
			# THE 45 -> 75 BUMP DID NOT FIX IT, AND THE NUMBER IS NOT THE CURE.
			# Raising the cap took the candidate count 9 -> 13 and changed
			# nothing else: 13 columns x 131 scan steps = 1703 link positions,
			# every one rejected.  Probed on the saved failure DB, the blocker
			# is GEOMETRIC and two-sided, so no radius can reach past it:
			#   LEFT  every corridor crosses the SLEEP CHAIN'S OWN M2 ladder at
			#         x 194.65..194.95 -- nine psoPSI_PD_GATED_EnNet__1_25*
			#         segments from y 223.45 to 259.55 that OVERLAP each other,
			#         so their union covers the whole 223.3..256.2 scan window
			#         with no gap anywhere;
			#   RIGHT every corridor crosses this repeater's OWN VSSG strap at
			#         x 198.2..198.5, y 222.8..266.0 -- likewise continuous.
			# pgaorep_2 sits in the 2.82 um pocket between them (its VDD strap
			# is at 197.77..198.07).  This is the F2e condition this file
			# already names -- "0.1-wide sleep-chain M2 routes block some scan
			# bands" -- gone from partial to total.
			# The cap stays at 75 because reach is still worth having and every
			# candidate is clearance-checked anyway; it is NOT a fix for this.
			# Widening only offers MORE columns; each is still clearance-checked
			# below before it is accepted, so nothing is loosened.
			if {$__d < 0.5 || $__d > 75.0} { continue }
			foreach __o [dbQuery -area [list [expr {$__msx + 0.05}] $__may0 [expr {$__msx + 0.25}] $__may1] -objType sWire] {
				if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
				set __b3 [lindex [dbGet $__o.box] 0]
				foreach {__qx0 __qy0 __qx1 __qy1} $__b3 {}
				if {[expr {$__qy1 - $__qy0}] < 4.0} { continue }
				set __ov [expr {min($__py1, $__qy1) - max($__py0, $__qy0)}]
				if {$__ov < 1.5} { continue }
				lappend __cands [list $__d $__msx $__qy0 $__qy1]
				break
			}
		}
		set __cands [lsort -real -index 0 $__cands]
		set __ly ""; set __best ""
		foreach __cand $__cands {
			foreach {__d __msx __qy0 __qy1} $__cand {}
			set __clx0 [expr {min($__px0, $__msx)}]
			set __clx1 [expr {max($__px1, $__msx + 0.3)}]
			# clearance margin = M2 narrow min-space 0.10 exactly — the
			# VSS twin sits at a LEGAL 0.13 gap and a fat margin blocks
			# every candidate y (first F2c run).
			set __sc0 [expr {max($__py0, $__qy0) + 0.5}]
			set __sc1 [expr {min($__py1, $__qy1) - 0.8}]
			# STEP 1.0 -> 0.25 um (2026-08-17). THIS is what actually failed:
			# the scan walked candidate link rows on a 1 um grid, so a column
			# whose only clear window is narrower than the grid reports "no
			# clear link y" even though a legal y exists a few tenths away.
			# Measured: the L-shape run aborted with SIX candidate columns
			# found and none usable. The step is a search resolution, not a
			# spacing rule -- every y it proposes still has to pass the
			# identical foreign-M2 clearance test in the loop body, so a finer
			# step can only ever find a link the coarse one missed.
			# MINCUT (VIA1.R.2/R.3): the clearance test in the loop body is BLIND TO
			# SAME-NET M2, and that blindness is what put four MINCUT markers on the
			# 2026-08-25 cut.
			# The LUP.6 n-well-tap jog laid by pg1_preplace_repeater is a 0.30 um VDD M2
			# bar, and it sits 0.08 um above the first row this scan offers, so the link
			# bar lands BESIDE it instead of on it.
			# Two 0.30 um bars 0.08 um apart are ONE 0.38 um polygon to Calibre, 0.38 is
			# wider than the VIA1.R.2 trigger width of 0.30, and every single-cut VIA1
			# under a wide M2 line then needs a redundant cut.
			# That redundant cut cannot be built at these sites: the tap M1 pad is 0.10 um
			# wide and the repeater VDDG finger is 0.16 x 0.32, while a two-cut VIA1 needs
			# 0.38 um.
			# So land the link bar ON the same-net bar, where the union stays 0.30, or at
			# least 0.10 um clear of it; never beside it.
			# MEASURED, three ways.  Moving the two link bars from y 113.30 to y 113.38
			# takes Innovus verifyGeometry MINCUT from 4 to 0 in the shipped database; the
			# full Calibre signoff deck (1592 rulechecks) over the same edit takes the cut
			# from 17 results to 13 with VIA1.R.2__VIA1.R.3 the only line that changes; and
			# the 2026-08-26 harden that first carried this code reported MINCUT = 0 with
			# both bars linked at y 113.38.
			set __sameov {}
			foreach __o [dbQuery -area [list [expr {$__clx0 - 0.10}] $__sc0 \
			                                [expr {$__clx1 + 0.10}] $__sc1] -objType sWire] {
				if {[dbGet -e $__o.layer.name] ne "M2"} { continue }
				if {[dbGet -e $__o.net.name]   ne "VDD"} { continue }
				foreach {__ox0 __oy0 __ox1 __oy1} [lindex [dbGet $__o.box] 0] {}
				if {$__oy1 - $__oy0 > 0.35} { continue }   ;# a vertical strap, not a bar
				lappend __sameov [list $__oy0 $__oy1]
			}
			# Same-net bars FIRST, because landing on one keeps the Calibre union at 0.30.
			# Then the regular 0.25 um scan, with every partially-overlapping row removed.
			set __rows {}
			foreach __s $__sameov {
				set __sy [lindex $__s 0]
				if {$__sy >= $__sc0 && $__sy < $__sc1} { lappend __rows $__sy }
			}
			for {set __cy $__sc0} {$__cy < $__sc1} {set __cy [expr {$__cy + 0.25}]} {
				set __bad 0
				foreach __s $__sameov {
					foreach {__sy0 __sy1} $__s {}
					if {abs($__cy - $__sy0) < 0.001} { set __bad 1 ; break }
					if {$__cy + 0.3 > $__sy0 && $__cy < $__sy1} { set __bad 1 ; break }
				}
				if {!$__bad} { lappend __rows $__cy }
			}
			logPuts [format "PG4/F2b: %d same-net 0.30 M2 bar(s) in the corridor; %d candidate link row(s) offered" \
				[llength $__sameov] [llength $__rows]]
			foreach __cy $__rows {
				set __ok 1
				foreach __o [concat [dbQuery -area [list [expr {$__clx0 - 0.10}] [expr {$__cy - 0.10}] [expr {$__clx1 + 0.10}] [expr {$__cy + 0.40}]] -objType sWire] [dbQuery -area [list [expr {$__clx0 - 0.10}] [expr {$__cy - 0.10}] [expr {$__clx1 + 0.10}] [expr {$__cy + 0.40}]] -objType wire]] {
					if {[dbGet -e $__o.layer.name] ne "M2"} { continue }
					if {[dbGet -e $__o.net.name] eq "VDD"} { continue }
					set __ok 0; break
				}
				if {$__ok} { set __ly $__cy; break }
			}
			if {$__ly ne ""} { set __best $__msx; set __lx0 $__clx0; set __lx1 $__clx1; break }
		}
		if {$__ly eq ""} {
			# 2026-08-25: SAY WHY, not just that.  Two runs have now died here
			# with a bare count, and "9 candidates tried" does not distinguish
			# "no columns in reach" from "every corridor blocked" -- which are
			# opposite problems with opposite fixes (widen the radius vs. move
			# the repeater / thin the corridor).  Dump the candidates and the
			# scan window each one offered, so the NEXT failure is diagnosed
			# from the log instead of from another experiment.
			logPuts "FATAL (PG4/F2b): no clear link y to any main strap column for repeater [dbGet $__i.name] ([llength $__cands] candidates tried). Saving dbs/pg4rep_fail.innovus; aborting."
			logPuts "PG4/F2b DIAG: repeater strap box = [list $__px0 $__py0 $__px1 $__py1]"
			foreach __cand $__cands {
				foreach {__dd __mmsx __qqy0 __qqy1} $__cand {}
				set __w0 [expr {max($__py0, $__qqy0) + 0.5}]
				set __w1 [expr {min($__py1, $__qqy1) - 0.8}]
				logPuts [format "PG4/F2b DIAG:   column x=%.3f  dist=%.3f  strap y=%.3f..%.3f  scan window %.3f..%.3f (%.3f um, %d steps)" \
					$__mmsx $__dd $__qqy0 $__qqy1 $__w0 $__w1 [expr {$__w1 - $__w0}] [expr {int(($__w1 - $__w0) / 0.25)}]]
			}
			saveDesign dbs/pg4rep_fail.innovus
			exit 1
		}
		add_shape -net VDD -layer M2 -rect [list $__lx0 $__ly $__lx1 [expr {$__ly + 0.3}]] -shape STRIPE -status ROUTED
		createRouteBlk -box [list [expr {$__lx0 - 0.1}] [expr {$__ly - 0.1}] [expr {$__lx1 + 0.1}] [expr {$__ly + 0.4}]] -layer 2
		logPuts "PG4/F2b: linked repeater [dbGet $__i.name] strap to main column x=$__best (link y=$__ly, span $__lx0-$__lx1)"
	}
	# fence the repeater straps from the router like the column straps
	foreach __i [dbGet -p top.insts.name pgaorep_*] {
		set __bx [lindex [dbGet $__i.box] 0]
		foreach {__x0 __y0 __x1 __y1} $__bx {}
		createRouteBlk -box [list [expr {$__x0 - 0.1}] [expr {$__y0 - 60.0}] [expr {$__x1 + 0.1}] [expr {$__y1 + 60.0}]] -layer 2
	}
}

################################################################################
# Clock tree synthesis (mclk from the clk port; clk_cpu is a generated clock
# through vesta's ClkGate -- ccopt traces it)
################################################################################
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
ccopt_design
# CPR5: re-derive and re-apply after ccopt — ccopt may resize/rename the mux
# gates, and a silently-dropped disable is exactly how the Argus timer version
# of this constraint no-op'd for a whole spin.
cpr5_disable_ram_clk_mux_check postcts 0
optDesign -postCTS -hold
# Full report_power (leakage + dynamic, statistical activity) beside the
# leakage-only ${DESIGN_NAME}_postCTS.power optDesign writes implicitly.
# Consumed by tools/python/gen_power_dashboard.py.
catch {report_power -outfile $REPORT_DIR/${DESIGN_NAME}_postCTS_full.power}
timeDesign -postCTS -expandedViews -outDir $REPORT_DIR/$DESIGN_NAME.timeDesign.postcts
report_ccopt_clock_trees -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_clock_trees.postcts
report_ccopt_skew_groups -file $REPORT_DIR/$DESIGN_NAME.report_ccopt_skew_groups.postcts
printStatus "CTS done"

################################################################################
# Signal routing
################################################################################
printStatus "Running nanoroute"
# THE G0 ROUTER-VS-CELL-OBS CLASS, REPRODUCED BY THIS RE-HARDEN (CPR5,
# 2026-08-15). Read this before touching the routing setup.
#
# The router draws SIGNAL M1 for pin access, and an M1 access shape is free to
# overhang the abutting cell and merge with THAT cell's INTERNAL M1 strap.
# Measured on the CPR5 penta placement:
#   * Pegasus tile LVS: SHORT — "Layout Net X5/3745 | Schematic Net
#     Xtie_0_cell7/LO  ==SHORT==  psoPSI_PD_GATED_EnNet__1_515_351_3_0_pg1rep"
#     — an M1 wire at {352.505 398.355 352.85 398.445} on the PSO enable-chain
#     link reaching 0.095 um into TIELOX1MA10TH tie_0_cell7 (351.8-352.6) and
#     merging with the tie's internal LO node. THE SAME DEFECT AS G0
#     (2026-07-22): same cell type, same net class, new location because the
#     placement moved. Unmatched devices 351:348, nets 193:181.
#   * Calibre blockdrc, same site: G.4:M1i x2 + M1.W.1 x1; and the sibling
#     M1.S.1 x2 / M1.S.5 x1 at (505.4,420.3) where a router M1 pad sits inside
#     an XOR2X1MA10TH.
# G0 closed this by SURGICAL rip+ecoRoute OUTSIDE the flow — which is why the
# archived M19c out/ carries a Jul-21 LEF/xsim.v beside a Jul-22 GDS/SDF, and
# why the flow re-manufactured the defect the moment it was re-run.
#
# CPR5b (2026-08-15) CLOSED IT AGAIN with a post-harden ECO, and so did
# tcm11_eco.tcl and g0_eco.tcl after it.  THAT IS NO LONGER HOW THIS FLOW
# HANDLES THE CLASS.  The repair is now an in-flow step at signoff --
# tcl/g0_repair.tcl, called just after the signoff verifyGeometry and before
# every shipped file.  The old ECOs are kept for their evidence, but they are
# history, and nothing in this flow calls them.
#
# WHAT MADE IT FOLDABLE.  The ECOs were coordinate-specific, and the class
# moves with the placement, so a frozen site list is useless -- but the site
# list was never the design decision.  Every one of the four archived repairs
# is the same recipe over two inputs the run already has: the marker line in
# its own verifyGeometry report, and the offending cell master's OBS section in
# the LEF this run was initialised with.  g0_repair.tcl computes the blockage
# boxes from those two, and its self-test reproduces all three archived sites
# box for box.  The two fixes that worked, per class:
#   * route-over-cell-OBS (the LVS short): rip + OBS-SHAPED M1/VIA1 blockages.
#   * pin squeezed against a PG stripe: PLACEMENT NUDGE (swap the cell with an
#     abutting filler) -- blockades only made ecoRoute give up and short.
#
# CORRECTION, 2026-08-25.  This comment used to end by saying Innovus
# verifyGeometry does NOT see the class and that only foundry LVS does.  THAT
# IS FALSE, and believing it is part of why the 2026-08-17 cut shipped shorted.
# Innovus reports it as
#     SHORT: Regular Via of Net <net> & Blockage of Cell <inst>  ( M1 )
# and it has done so on every cut anyone has looked at: the 2026-08-15 report
# named tie_0_cell7, the 2026-08-25 report named tie_0_cell6, and the VSS-fix
# report named g11129__6161 and registers_reg[30][17].  In every case Pegasus
# then agreed, net for net.  The in-flow verify is not blind here; it was being
# read by nobody.
#
# NOTE, because it is the trap that IS real: `ecoRoute -fix_drc` MANUFACTURES
# this class.  Measured -- repairing the two 2026-08-25 sites and then running
# the DRC fixer with the obstruction removed put a fresh merge into the very
# same flop, one OBS rect below the one it had just been routed out of.  The
# fixer below runs before the signoff repair, which is why the repair has to be
# at signoff and not here.
#
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
    -drouteAntennaEcoListFile $REPORT_DIR/$DESIGN_NAME.routeDesign.diodes.txt \
    -dbSkipAnalog true \
    -drouteEndIteration default
routeDesign

optDesign -postRoute -setup -hold
# PG4: +25 ps setup margin pass, SI-aware (M14/M16 ECO form) — the signoff
# SI corner shows a razor-thin reg2cgate WNS (-0.031 at PG3, -0.018 at the
# v11 re-harden; seed noise on a razor-thin baseline). Target-slack opt
# with SI delaycal pads exactly those paths.
setDelayCalMode -SIAware true
setOptMode -setupTargetSlack 0.025
optDesign -postRoute -setup
setOptMode -setupTargetSlack 0
setDelayCalMode -SIAware false

# CPR5 ACCEPTANCE GATE for the disable above: if the spurious ClockMuxGlitchFree
# hold check is still live, the hold fixer answers it with a DLY chain on
# tx_sel (measured: >100 DLY4 cells / ~11 ns on the first CPR5 harden). Zero
# such cells is the proof the disable took — the Argus precedent's
# "FE_PHC*control_reg_16: 40 -> 0" check, re-derived for this mux.
set __txdly [dbGet -p top.insts.name FE_PHC*tx_sel*]
set __ntxdly [expr {$__txdly == 0x0 ? 0 : [llength $__txdly]}]
logPuts "### UNL STATUS ### : CPR5 tx_sel hold-fix delay cells = $__ntxdly (want 0; 1st CPR5 harden had >100)"
if {$__ntxdly > 8} {
	logPuts "FATAL (CPR5): $__ntxdly hold-fix delay cells on tx_sel — the ram_clk mux gating-check disable did NOT take. Aborting before signoff."
	saveDesign $DATABASE_DIR/cpr5_txseldly_fail.innovus
	exit 1
}
# Full post-route power (see postCTS note)
catch {report_power -outfile $REPORT_DIR/${DESIGN_NAME}_postRoute_full.power}

verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
ecoRoute -fix_drc
verifyGeometry \
    -error 10000 \
    -warning 10000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt

# G0 EARLY DETECTOR (2026-08-25).  This report ALREADY carried the class on the
# last two cuts and nobody read it, which is ten minutes into the run instead of
# forty.  optDesign neither creates nor removes the class, so postroute is a
# valid early read.  DETECTOR ONLY -- the repair is at signoff, where every
# collateral file sits below it; reporting here just means a run that is going
# to need one says so early.
set __g0early [llength [g0r_parse_markers $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt]]
logPuts "### UNL STATUS ### : G0 EARLY -- $__g0early router-vs-cell-OBS M1 merge(s) already present at postroute (repaired at signoff)"

################################################################################
# PGR (2026-08-26) -- THE ROUTER'S OWN RESIDUAL, WHICH THE BLOCKAGES HIDE.
#
# The OTHER half of the post-route spacing class is not a PG pass at all, and
# the 2026-08-26 investigation started from the wrong premise about it.
# The M2.S.1 at (553.400,176.410) was made by NANOROUTE.  The detail router
# finished with "Total number of DRC violations = 4", all four on M2, and the
# report just above names all four: two regular vias sitting 0.045 and 0.050 um
# from a PG route BLOCKAGE edge, which is harmless because the blockage stands
# 0.1 um outside the strap it covers, and two pieces of regular routing INSIDE
# a blockage, one of which is 0.05 um from the VDD strap itself.
# deleteAllRouteBlks below then deletes the blockage, and the survivor becomes a
# real M2.S.1 that nothing between here and signoff will look at.
#
# So the marker was visible TEN MINUTES into the run, in Innovus' own report,
# and was invisible in practice because it was one line among 808 expected
# "Special Wire of Net VDD & Routing Blockage" entries.
#
# The scan does not trust the marker class to tell the two cases apart, because
# the blockage is not the strap.  It measures every regular rectangle against
# the real special metal with the deck's own rule and keeps only the ones that
# are still violations once the fence is gone.  On this cut that separates the
# four markers into one and three, which is exactly what Calibre said.
#
# THE REPAIR IS A FENCED RE-ROUTE, and three rehearsals on the shipped
# 2026-08-26 database picked it out of the alternatives:
#   bare ecoRoute then ecoRoute -fix_drc      site unchanged at 0.050 um
#   rip core/n_1239, ecoRoute, -fix_drc       site unchanged, 5 wires out,
#                                             5 wires back, the SAME via
#   rip, FENCE the strap on M2 + VIA1, then   site CLEAR, 6 wires back, the
#   ecoRoute, -fix_drc, unfence               M2 metal moved to x = 553.85
# NanoRoute does not believe this is a violation.  It will not repair it, it
# will not repair it after being made to route the net again, and the only
# thing that moves it is being told the space is unavailable.
# So there is no "try the cheap rung first" here: the cheap rungs are measured
# not to work on this class, and every extra ecoRoute is a perturbation.
#
# The fence is DERIVED from the special rectangle that convicted the marker,
# clipped to the marker plus 4 um and grown by the deck's own rule, so it is a
# few um of one strap and not a column.
#
# NOT FATAL.  A run that cannot clear it must still produce ONE self-consistent
# cut, which is the M19c lesson; the signoff Wiring gate below is what decides
# whether the cut ships.  The fenced re-route is also measured to be able to
# TRADE this class for a router-versus-cell-OBS M1 merge, which is why it runs
# HERE and not at signoff: the G0 repair further down is the antidote and it
# has not run yet.
################################################################################
printStatus "PGR: router residual scan (regular metal inside a PG route blockage)"
set __pgr_m [pgc_blockage_residuals $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt]
if {$__pgr_m eq "ERROR"} {
	logPuts "FATAL (PGR): the post-route verifyGeometry report could not be read, so the router"
	logPuts "             residual scan examined NOTHING and a zero here would not be a measurement."
	logPuts "             Aborting rather than reporting a pass nobody took."
	exit 1
}
set __pgr_res [pgc_real_residuals $__pgr_m]
set __pgr_n0 [llength $__pgr_res]
logPuts "### UNL STATUS ### : PGR -- [llength $__pgr_m] regular-vs-PG-blockage marker(s) examined, $__pgr_n0 still violating once the blockages go, on net(s): [pgc_residual_nets $__pgr_res]"
set __pgr_pass 0
while {[llength $__pgr_res] > 0 && $__pgr_pass < 2} {
	incr __pgr_pass
	set __pgr_nets [pgc_residual_nets $__pgr_res]
	logPuts "### UNL STATUS ### : PGR pass $__pgr_pass -- rip + fence + ecoRoute on [llength $__pgr_nets] net(s): $__pgr_nets"
	set __pgr_dt {}
	foreach __n $__pgr_nets {
		set __np [dbGetNetByName $__n]
		if {$__np eq "" || $__np == 0x0} {
			logPuts "### UNL STATUS ### : PGR   net $__n not found in the database, skipped"
			continue
		}
		set __dtwas [dbGet $__np.dontTouch]
		if {$__dtwas} { dbSet $__np.dontTouch false }
		set __wb [llength [dbGet -e $__np.wires]]
		deselectAll
		editSelect -net $__n
		editDelete -selected
		deselectAll
		logPuts "### UNL STATUS ### : PGR   RIP $__n wires $__wb -> [llength [dbGet -e $__np.wires]]"
		lappend __pgr_dt [list $__n $__dtwas]
	}
	set __pgr_fn {}
	set __pgr_i 0
	foreach __r $__pgr_res {
		foreach {__rn __rl __fx0 __fy0 __fx1 __fy1} $__r {}
		set __cut [expr {$__rl eq "M1" ? "VIA1" : ($__rl eq "M2" ? "VIA1" : "VIA2")}]
		set __nm pgr_fence_${__pgr_pass}_[incr __pgr_i]
		if {[catch {createRouteBlk -name $__nm -layer $__rl -cutLayer $__cut \
		     -box [list $__fx0 $__fy0 $__fx1 $__fy1]} __e]} {
			logPuts "### UNL STATUS ### : PGR   fence $__nm on $__rl failed: $__e"
			continue
		}
		lappend __pgr_fn $__nm
	}
	logPuts "### UNL STATUS ### : PGR   [llength $__pgr_fn] fence(s) up"
	ecoRoute
	ecoRoute -fix_drc
	foreach __nm $__pgr_fn { catch {deleteRouteBlk -name $__nm} }
	logPuts "### UNL STATUS ### : PGR   [llength $__pgr_fn] fence(s) removed"
	foreach __rr $__pgr_dt {
		foreach {__n __dtwas} $__rr {}
		set __np [dbGetNetByName $__n]
		if {$__np eq "" || $__np == 0x0} { continue }
		if {[llength [dbGet -e $__np.wires]] == 0} {
			logPuts "FATAL (PGR): $__n was ripped and came back with NO wires. A net this pass opened and"
			logPuts "             did not close is worse than the spacing violation it was chasing."
			logPuts "             Saving $DATABASE_DIR/pgr_open_fail.innovus; aborting."
			saveDesign $DATABASE_DIR/pgr_open_fail.innovus
			exit 1
		}
		if {$__dtwas} { dbSet $__np.dontTouch true }
	}
	verifyGeometry \
	    -error 10000 \
	    -warning 10000 \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt
	set __pgr_m [pgc_blockage_residuals $REPORT_DIR/$DESIGN_NAME.verifyGeometry.postroute.rpt]
	if {$__pgr_m eq "ERROR"} { break }
	set __pgr_res [pgc_real_residuals $__pgr_m]
	logPuts "### UNL STATUS ### : PGR after pass $__pgr_pass -- [llength $__pgr_res] residual(s) left on [pgc_residual_nets $__pgr_res]"
}
logPuts "### UNL STATUS ### : PGR -- router residuals $__pgr_n0 -> [llength $__pgr_res] in $__pgr_pass repair pass(es)"
if {[llength $__pgr_res] > 0} {
	logPuts "### UNL STATUS ### : PGR RESIDUAL PRESENT -- [llength $__pgr_res] site(s) will reach signoff as real"
	logPuts "### UNL STATUS ### :   spacing violations against PG metal, on [pgc_residual_nets $__pgr_res]."
	logPuts "### UNL STATUS ### :   This is a NanoRoute convergence failure, not a PG pass. The signoff"
	logPuts "### UNL STATUS ### :   Wiring gate below decides whether the cut ships."
}

deleteAllRouteBlks
addFiller

# M17b: scrub the two dead-rail rows BARE before signoff. The blockages
# (see the placement section) kept logic out, but addWellTap ran earlier
# and left FILLBIAS taps in the right-leg top row, and the dead VDD_SW rail
# stubs themselves flag as zero-area ANTENNA markers + dangling wires once
# nothing abuts them. Delete the leftover insts, then the two rail stubs —
# dry-run proven on the signoff DB: DRC 0, no IMPVFC-94/-96, conn drops to
# the 476 expected VDD_SW/VSS piece infos. (Deleting the rail out from
# under a FILLBIAS would re-strand its net-tied VDD frame — hence insts
# first, rails second.)
foreach __i [dbQuery -area [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 2.8}] $DESIGN_WIDTH [expr {$DESIGN_HEIGHT - 0.2}]] -objType inst] {
	if {[dbGet $__i.pt_y] > [expr {$DESIGN_HEIGHT - 3.5}]} { deleteInst [dbGet $__i.name] }
}
foreach __i [dbQuery -area [list 0 0.5 $DESIGN_WIDTH 2.9] -objType inst] {
	if {[dbGet $__i.pt_y] < 2.5} { deleteInst [dbGet $__i.name] }
}
editDelete -net VDD_SW -area [list 0 0.4 $DESIGN_WIDTH 1.9]
editDelete -net VDD_SW -area [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 1.6}] $DESIGN_WIDTH [expr {$DESIGN_HEIGHT - 0.1}]]
# PG4 v19: the PG4 secondary sroute (new since this scrub was written) drew
# M1 pin fingers on the dead-row FILLBIAS too; deleting the insts above
# leaves those fingers floating — v18 signoff flagged 16 of them as REAL
# M1 min-area viols (0.2x0.18 = 0.036 < 0.042) plus antenna litter in the
# right-leg top row. Delete the M1 VDD/VSS pieces inside the two dead-row
# bands; editDelete is whole-shape-contained, so the shared boundary rails
# (y outside the band) and anything crossing survive.
foreach __dnet {VDD VSS} {
	editDelete -net $__dnet -layer M1 -area [list 0 0.3 $DESIGN_WIDTH 2.6]
	editDelete -net $__dnet -layer M1 -area [list [expr {$DESIGN_WIDTH - $FINGER_W}] [expr {$DESIGN_HEIGHT - 3.0}] $DESIGN_WIDTH [expr {$DESIGN_HEIGHT - 0.1}]]
}
printStatus "Scrubbed the 2 dead-rail rows bare"

# (v22b: this stage MOVED here from the fabric section — the M8-crossing
# via3..7 stacks are only fully populated late in the flow: the fabric
# stage sees 371 via3 objects, the signoff DB holds ~2150. Post-route is
# also where the clearance check can see the routed signals.)
# PG4 v22: STRAP->GRID LINK REPAIR (the missing piece of the F1 fix).
# The engine's M8-crossing stacks START AT M3 (via3..7 — no via1/2 was
# ever placed at the crossings), so every M2 strap column was an ISLAND:
# pin-connected below, never grid-connected above. VDD has NO rails (rows
# carry VSS/VDD_SW only) — the crossing stack is a VDD column's ONLY feed,
# so the wells and switch supplies all hung on this. Found by pad-aware
# union-find over the PG dump (v21: 162/256 M2 pieces islanded; 2039 of
# 2154 via3-points had no via1/2 within 0.45; LVS softchk nxwell 6596 and
# ~2100 unmatched layout nets — the verifyConnectivity IMPVFC-200 "pieces
# not connected" class was RIGHT, not tracer noise).
# MECHANISM (probe-proven): `add_via` special vias are GDS-PHANTOMS on
# this install — they live in the DB and pass every dbQuery gate but
# streamOut silently drops them (single-via A/B: layer-52 count unchanged;
# the v18-v21 repeater VIA1_Vs never reached a GDS either). Engine vias
# stream. So: lay a small REAL M3 rect (0.2x0.08, inside the stack pad
# footprint) at each isolated via3 point on a strap, then ONE global
# `editPowerVia -add_vias 1 -nets VDD -bottom_layer M2 -top_layer M3` —
# the engine vias every strap/M3-rect overlap (probe: direct pad targeting
# finds nothing; with the rect it generates; +2 layer-52 records in the
# A/B GDS). ADDITIVE ONLY. Clearance-checked against non-VDD M3; a skipped
# crossing is fine — a column needs only ONE live crossing.
set __ngshape 0
set __ngblock 0
set __ngskip 0
array unset __v12pt
array unset __v3pt
array unset __v3ptr
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	set __vn [string tolower [dbGet -e $__o.via.name]]
	set __k "[format %.2f [dbGet $__o.pt_x]]_[format %.2f [dbGet $__o.pt_y]]"
	if {[string match via1* $__vn] || [string match via2* $__vn]} { set __v12pt($__k) 1 }
	if {[string match via3* $__vn]} { set __v3pt($__k) 1 }
}
set __npre2 0
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	if {[dbGet -e $__o.via.cutLayer.name] eq "VIA2"} { incr __npre2 }
}
foreach __k [array names __v3pt] {
	if {[info exists __v12pt($__k)]} { continue }
	foreach {__gvx __gvy} [split $__k _] {}
	set __onstrap 0
	foreach __o [dbQuery -area [list [expr {$__gvx - 0.05}] [expr {$__gvy - 0.05}] [expr {$__gvx + 0.05}] [expr {$__gvy + 0.05}]] -objType sWire] {
		if {[dbGet -e $__o.layer.name] eq "M2" && [dbGet -e $__o.net.name] eq "VDD"} { set __onstrap 1; break }
	}
	if {!$__onstrap} { incr __ngskip; continue }
	set __r [list [expr {$__gvx - 0.10}] [expr {$__gvy - 0.04}] [expr {$__gvx + 0.10}] [expr {$__gvy + 0.04}]]
	# 2026-08-26: this WAS a CONTAINMENT test, "is a foreign M3 shape inside my
	# own footprint", which is a short test and not a spacing test.  It reported
	# "0 blocked by foreign M3" on the cut that shipped an M1.S.1 200 um away,
	# because a shape 0.05 um outside the footprint is not inside it.
	# pgc_probe measures the SPACE to the nearest separate polygon against the
	# deck's own M3_S_1, and reports how many neighbours it examined so a zero
	# is a measurement rather than a silence.
	set __p [pgc_probe $__r M3 VDD]
	set __pv [lindex $__p 0]
	if {$__pv ne "CLEAR" && $__pv ne "MERGED"} {
		if {$__ngblock < 20} { pgc_note [pgc_say "PG4/F1 pad" $__r M3 VDD $__p] }
		incr __ngblock; continue
	}
	add_shape -net VDD -layer M3 -rect $__r -shape STRIPE -status ROUTED
	incr __ngshape
}
# The engine, not this script, chooses the via master and the position, so the
# only honest question is what it BUILT.  pgc_epv censuses, generates, measures
# every new via's real landing pads and deletes the ones that are too close.
# It does NOT relocate here: a column needs ONE live crossing, not all of them,
# so a given-up crossing costs nothing and the gate below still judges the total.
set __f1epv [pgc_epv PG4/F1 VDD M2 M3 VIA2 ALL 0]
set __npost2 0
foreach __o [dbGet [dbGet -p top.nets.name VDD].sVias -e] {
	if {[dbGet -e $__o.via.cutLayer.name] eq "VIA2"} { incr __npost2 }
}
set __nglink [expr {$__npost2 - $__npre2}]
logPuts "### UNL STATUS ### : PG4 strap-grid link repair — $__ngshape M3 pads laid ($__ngblock blocked by the clearance check, $__ngskip off-strap), engine created $__nglink VIA2s"
pgc_report PG4/F1
if {$__nglink < 1000} {
	logPuts "FATAL (PG4/F1): strap-grid link repair created only $__nglink VIA2s (expect ~2000) — the crossing-stack population or the editPowerVia mechanism changed. Saving dbs/pg4link_fail.innovus; aborting."
	saveDesign dbs/pg4link_fail.innovus
	exit 1
}

################################################################################
# PG4/F2 (2026-07-11, session 3) — strap-PIN link repair: the missing LAST
# HOP of the F1 fabric. The strap-grid repair above connects every strap UP
# to the M8 grid, but nothing ever connected the straps DOWN to the pins:
# the fabric-stage addStripe VIA1s do not survive to the final DB/GDS (the
# signoff DB has ZERO via1 sVias under 7 of 8 header-column straps; the
# GDS has zero layer-51 cuts under ANY strap — headers' VDDG hung on
# nwell diffusion only, LVS softchk nxwell 6596 and ~1631 unmatched layout
# nets were exactly this). Probe-proven fix (2026-07-11, restored signoff
# DB): per-column windowed `editPowerVia -add_vias 1 -nets VDD M1->M2
# -orthogonal_only 0` — the engine vias every sroute FINGER (M1 sWire,
# drawn ON the pin) x strap (M2) overlap: 52/52 header via1s in the test
# column, GDS-real (+60 layer-51 cuts), and the labeled LVS compare
# absorbed exactly the two probed columns' worth of unmatched nets (-103).
# Tap columns need a REAL M1 pad on each FILLBIAS VNW pin bar first
# (pin geometry is invisible to editPowerVia — the repeater lesson);
# orientation-aware (R0/MY bar y0+1.21..1.73, MX/R180 y0+0.27..0.79 —
# a full-height pad would short the VPW bar at the same x).
# Runs HERE (post-route, after the dead-row scrub) so no later stage can
# orphan or delete the vias. ADDITIVE ONLY.
################################################################################
proc pg4_count_via1 {x0 y0 x1 y1} {
	set n 0
	foreach o [dbQuery -area [list $x0 $y0 $x1 $y1] -objType sVia] {
		if {[dbGet -e $o.net.name] ne "VDD"} { continue }
		if {[string match -nocase via1* [dbGet -e $o.via.name]]} { incr n }
	}
	return $n
}
set __f2vias 0
set __f2covered 0
set __f2waived {}
foreach __pr $__placed_runs {
	foreach {__key __sx __ay0 __ay1} $__pr {}
	set __x0 [string range $__key 1 end]
	set __isH [expr {[string index $__key 0] eq "H"}]
	set __cells {}
	foreach __y $__colys($__key) {
		if {$__y >= [expr {$__ay0 - 1.5}] && $__y <= $__ay1} { lappend __cells $__y }
	}
	set __ncell [llength $__cells]
	if {$__ncell == 0} { continue }
	if {!$__isH} {
		foreach __i [dbGet -p2 top.insts.cell.name FILLBIASA10TH] {
			set __bx [lindex [dbGet $__i.box] 0]
			foreach {__ix0 __iy0 __ix1 __iy1} $__bx {}
			if {abs($__ix0 - $__x0) > 0.01} { continue }
			if {$__iy0 < [expr {$__ay0 - 1.5}] || $__iy0 > $__ay1} { continue }
			if {[pg4_dead_row $__bx]} { continue }
			set __or [dbGet $__i.orient]
			if {$__or eq "R0" || $__or eq "MY"} {
				set __py0 [expr {$__iy0 + 1.21}]; set __py1 [expr {$__iy0 + 1.73}]
			} else {
				set __py0 [expr {$__iy0 + 0.27}]; set __py1 [expr {$__iy0 + 0.79}]
			}
			# The pad has to stay ON the VNW pin bar, so its x is fixed and the
			# only freedom is y.  The two alternatives are the bottom and the
			# top half of the same bar, which are electrically the same pad.
			set __tp [list [expr {$__ix0 + 0.15}] $__py0 [expr {$__ix0 + 0.25}] $__py1]
			pgc_add_shape PG4/F2tap VDD M1 $__tp [list \
				[list [expr {$__ix0 + 0.15}] $__py0 [expr {$__ix0 + 0.25}] [expr {$__py0 + 0.26}]] \
				[list [expr {$__ix0 + 0.15}] [expr {$__py1 - 0.26}] [expr {$__ix0 + 0.25}] $__py1]]
		}
	}
	set __w0 [expr {$__sx - 0.5}]
	set __w1 [expr {$__sx + 0.9}]
	set __b [pg4_count_via1 $__w0 $__ay0 $__w1 $__ay1]
	# THIS is the pass that made the 2026-08-26 M1.S.1.  The engine answered a
	# 0.10 um tap pad with a two-cut array whose M1 landing pad is 0.33 um wide
	# and reaches to x=433.415, 0.076 um from a routed M1 wire of
	# core/datapath_inst/rf/n_551 against a 0.090 um rule.
	# Nothing in front of editPowerVia predicts that, so pgc_epv measures what
	# was built and, where a via has to go, re-offers the engine a window one
	# row tall on the far side of the deleted position.
	pgc_epv PG4/F2 VDD M1 M2 VIA1 [list $__w0 $__ay0 $__w1 $__ay1] 1
	set __a [pg4_count_via1 $__w0 $__ay0 $__w1 $__ay1]
	incr __f2vias [expr {$__a - $__b}]
	# Gate = ABSOLUTE per-cell coverage in the STRAP x-sliver, not the pass
	# delta: fabric-stage via1s survive at seed-dependent spots (first F2
	# run: a pre-existing via on the H431 bottom-stub finger made delta 0
	# for a covered header and false-FATALed). The sliver [sx-0.1,sx+0.4]
	# also refuses credit to off-strap strays like v22c's col-351 x+1.235
	# via1 column (finger vias to nowhere — not strap connections).
	set __cellh [expr {$__isH ? 4.1 : 2.1}]
	foreach __y $__cells {
		set __nc [pg4_count_via1 [expr {$__sx - 0.1}] [expr {$__y - 0.1}] [expr {$__sx + 0.4}] [expr {$__y + $__cellh}]]
		if {$__nc >= 1} { incr __f2covered; continue }
		if {$__isH} {
			logPuts "FATAL (PG4/F2): header $__key y=$__y has no strap-pin via1 in the strap sliver. Saving dbs/pg4f2_fail.innovus; aborting."
			saveDesign dbs/pg4f2_fail.innovus
			exit 1
		}
		lappend __f2waived [list $__key $__sx $__y]
	}
}
# --- PG4/F2g: DRC cleanup on the F2 metal (Myshkin bar: G.4/VIA1.R.4 = 0).
# (b) DOUBLE-column zones (a tap strap TOUCHING a header strap, 2 pairs on
#     this floorplan): the two pieces start/end at different y, so the
#     first/last finger reaches only ONE of them = a single-via connection
#     beside the merged plate -> VIA1.R.4. Align both pieces to the pair's
#     y-envelope and re-run the via pass there (every finger then gets a
#     via on BOTH straps).
set __npairfix 0
set __ncap 0
for {set __ii 0} {$__ii < [llength $__placed_runs]} {incr __ii} {
	for {set __jj [expr {$__ii + 1}]} {$__jj < [llength $__placed_runs]} {incr __jj} {
		foreach {__ka __sxa __ay0a __ay1a} [lindex $__placed_runs $__ii] {}
		foreach {__kb __sxb __ay0b __ay1b} [lindex $__placed_runs $__jj] {}
		if {[expr {abs($__sxa - $__sxb)}] > 0.35} { continue }
		set __oy0 [expr {max($__ay0a, $__ay0b)}]
		set __oy1 [expr {min($__ay1a, $__ay1b)}]
		if {[expr {$__oy1 - $__oy0}] < 4.0} { continue }
		# each strap's OWN piece: must CONTAIN its strap centerline —
		# a thin query window partial-overlaps the PARTNER's piece too
		# and dbQuery order is arbitrary (F2g probe: both queries
		# returned the same piece and the alignment no-op'ed).
		set __pa ""; set __pb ""
		foreach __pp [list a b] {
			set __psx [expr {$__pp eq "a" ? $__sxa : $__sxb}]
			set __ctr [expr {$__psx + 0.15}]
			foreach __o [dbQuery -area [list [expr {$__psx + 0.05}] $__oy0 [expr {$__psx + 0.25}] $__oy1] -objType sWire] {
				if {[dbGet -e $__o.layer.name] ne "M2" || [dbGet -e $__o.net.name] ne "VDD"} { continue }
				set __b [lindex [dbGet $__o.box] 0]
				if {[expr {[lindex $__b 3] - [lindex $__b 1]}] < 4.0} { continue }
				if {[lindex $__b 0] > $__ctr || [lindex $__b 2] < $__ctr} { continue }
				if {$__pp eq "a"} { set __pa $__b } else { set __pb $__b }
				break
			}
		}
		if {$__pa eq "" || $__pb eq ""} { continue }
		set __ey0 [expr {min([lindex $__pa 1], [lindex $__pb 1])}]
		set __ey1 [expr {max([lindex $__pa 3], [lindex $__pb 3])}]
		foreach __pp [list [list $__sxa $__pa] [list $__sxb $__pb]] {
			foreach {__psx __pbx} $__pp {}
			# No alternatives are offered: these two pieces exist to bring one
			# strap up to the pair's y-envelope, so any other position is a
			# different repair and not this one.
			if {[lindex $__pbx 1] > [expr {$__ey0 + 0.01}]} {
				pgc_add_shape PG4/F2pair VDD M2 \
					[list $__psx $__ey0 [expr {$__psx + 0.3}] [expr {[lindex $__pbx 1] + 0.1}]]
			}
			if {[lindex $__pbx 3] < [expr {$__ey1 - 0.01}]} {
				pgc_add_shape PG4/F2pair VDD M2 \
					[list $__psx [expr {[lindex $__pbx 3] - 0.1}] [expr {$__psx + 0.3}] $__ey1]
			}
		}
		pgc_epv PG4/F2pair VDD M1 M2 VIA1 \
			[list [expr {min($__sxa, $__sxb) - 0.5}] $__ey0 [expr {max($__sxa, $__sxb) + 0.9}] $__ey1] 1
		incr __npairfix
	}
}
# CAP POST-MORTEM (F2i): the per-via "pad-overhang caps" that lived here
# were POISON — each 0.15x0.1 cap misaligned with its 0.18-tall via pad
# (pt_y+-0.05 vs +-0.09) and made its OWN G.4 small-jog pair: 304 caps =
# 600 G.4:M2i markers (Calibre; the in-flow "6" read during the F2i
# acceptance was a stale/raced report). Never patch DRC classes with
# blind per-object decorations; prove each patch shape on a trial GDS
# (restore -> add_shape -> streamOut -> strmin -> blockdrc, ~6 min).
#
# (c) the PROVEN patch set (trial-GDS Calibre iterations 1-4, 2026-07-11):
# hardcoded, seed-stable (identical coordinates across F2f/F2i hardens),
# M7.S.4(b) house style. Covers the 8 residual results:
#   - stub-seam MERGES at the two double-column bottom stubs: unify the
#     T/H stub pieces into one block (the same seam-merge that the (b)
#     alignment applies to the main runs; kills the G.4 jog families and
#     converts the R.4 single-via question into a solvable R.2/R.3 one).
#   - side FILLS at the three via pads that overhang the strap union by
#     0.055 (column ends + column top): fill flush to the pad, reaching
#     exactly 0.1 past the strap edge — a >= min-width step is legal.
#   - the stub tap-via REGENERATE: a single via1 in the now-0.525-wide
#     merged block violates VIA1.R.2 (>0.42-wide M2 needs >=2 cuts). The
#     engine refuses to add cuts to a connected overlap, add_via and
#     add_shape-on-VIA1 are both GDS-phantoms — so DELETE the one via at
#     its exact coordinates and re-add on the wide overlap: the engine
#     regenerates it as a real 2-cut array (GDS layer-51 proven).
#
# ATTACHMENT GUARD (2026-08-25).  THE "seed-stable" CLAIM ABOVE IS FALSE, AND
# IT SHIPPED TWO DRC RESULTS.
#
# These eight rectangles are FILLS: each one exists only to close a 0.055 um
# pad overhang against a strap it is supposed to touch.  A fill that touches
# nothing is not a no-op -- it is a free-standing 0.03..0.04 um2 island, and
# M2.A.1 wants 0.052 um2.  It converts itself from a patch into a defect.
#
# That is exactly what the last two did.  Measured on the 2026-08-17 cut: the
# x=433 M2 column tops out near y=339.5, but the two "column top" fills are
# frozen at y=597.85 from 2026-07-11.  They sat 258 um above the column, in
# empty space -- nothing else on ANY layer within a 21 x 20 um window, nearest
# other M2 shape 155.4 um away -- and came back as
#     M2.A.1 (433.000,597.850) 0.040 um2   and   (433.575,597.850) 0.030 um2
# i.e. two of hart_tile's eight Calibre results, manufactured by this block.
#
# So the coordinates are NOT deleted (a fill that IS attached is doing real
# work, and four of these six demonstrably are) -- they are made CONDITIONAL on
# the thing they are supposed to attach to still being there.  Any fill whose
# footprint has no same-net M2 within 0.05 um is skipped and NAMED.  A skip is
# the signal that the placement moved under a frozen coordinate: re-derive it,
# do not re-freeze it.
proc pg4_patch_fill {net layer rect} {
	global __npatch __nskip __skiplist
	foreach {x0 y0 x1 y1} $rect {}
	# 0.05 um bloat: "touching", not "in the neighbourhood".  The pad-overhang
	# geometry these close is 0.055, so a real fill always overlaps its strap.
	set found 0
	foreach o [dbQuery -area [list [expr {$x0 - 0.05}] [expr {$y0 - 0.05}] \
	                               [expr {$x1 + 0.05}] [expr {$y1 + 0.05}]] -objType sWire] {
		if {[dbGet -e $o.net.name] ne $net} { continue }
		if {[dbGet -e $o.layer.name] ne $layer} { continue }
		set found 1
		break
	}
	if {!$found} {
		incr __nskip
		lappend __skiplist [format "%s %s (%.3f,%.3f)-(%.3f,%.3f) nothing to attach to" $net $layer $x0 $y0 $x1 $y1]
		return 0
	}
	# ATTACHED IS NOT THE SAME AS CLEAR.  A fill that touches its own strap can
	# still land inside the spacing rule of a routed wire on the other side, and
	# these coordinates are frozen from 2026-07-11 while the routing is not.
	set p [pgc_probe $rect $layer $net]
	set v [lindex $p 0]
	if {$v ne "CLEAR" && $v ne "MERGED"} {
		incr __nskip
		lappend __skiplist [pgc_say "$net $layer" $rect $layer $net $p]
		return 0
	}
	add_shape -net $net -layer $layer -shape STRIPE -status ROUTED -rect $rect
	incr __npatch
	return 1
}
set __npatch 0
set __nskip 0
set __skiplist {}
pg4_patch_fill VDD M2 {193.100 2.000 193.625 8.000}
pg4_patch_fill VDD M2 {433.100 2.000 433.625 7.500}
pg4_patch_fill VDD M2 {193.000 4.000 193.200 4.150}
pg4_patch_fill VDD M2 {193.575 4.050 193.725 4.150}
pg4_patch_fill VDD M2 {433.000 5.850 433.200 6.000}
pg4_patch_fill VDD M2 {433.575 5.850 433.725 5.950}
pg4_patch_fill VDD M2 {433.000 597.850 433.200 598.050}
pg4_patch_fill VDD M2 {433.575 597.850 433.725 598.050}
logPuts "### UNL STATUS ### : PG4/F2g frozen patch set — $__npatch placed, $__nskip skipped as unattached or too close"
foreach __sk $__skiplist { logPuts "### UNL STATUS ### :   patch SKIPPED: $__sk" }
set __b [pg4_count_via1 433.1 4.1 433.4 4.8]
editPowerVia -delete_vias 1 -nets VDD -bottom_layer M1 -top_layer M2 -area {433.15 4.20 433.35 4.40}
pgc_epv PG4/F2stub VDD M1 M2 VIA1 {433.05 4.15 433.45 4.80} 1
set __a [pg4_count_via1 433.1 4.1 433.4 4.8]
if {$__a < $__b} {
	logPuts "FATAL (PG4/F2g): stub tap-via regenerate lost the via ($__b -> $__a). Saving dbs/pg4f2_fail.innovus; aborting."
	saveDesign dbs/pg4f2_fail.innovus
	exit 1
}
logPuts "### UNL STATUS ### : PG4/F2g DRC cleanup — $__npairfix double-column zones aligned+re-via'd, patch set placed, stub via regenerated ($__b -> $__a)"
logPuts "### UNL STATUS ### : PG4/F2 strap-pin link repair — $__f2vias via1s created this pass, $__f2covered cells strap-covered, [llength $__f2waived] taps naked (first 10: [lrange $__f2waived 0 9])"
pgc_report PG4/F2tap
pgc_report PG4/F2
pgc_report PG4/F2pair
pgc_report PG4/F2stub
if {$__f2covered < 1400} {
	logPuts "FATAL (PG4/F2): only $__f2covered strap-covered cells (expect ~977 headers + ~700 taps). Saving dbs/pg4f2_fail.innovus; aborting."
	saveDesign dbs/pg4f2_fail.innovus
	exit 1
}

################################################################################
# PG6 (2026-08-25) -- VSS FOLLOW-PIN RAIL ISLANDS: detect, repair, and GATE.
#
# THE DEFECT.  hart_tile is a U, and in the LEFT finger the VSS follow-pin
# rails at y = 863, 867, 871, 875 and 879 had NO metal path out of the tile at
# all.  The M1 -> M7 via stacks that tie those rails to the PG grid stop at
# y = 858.91 on the left while the right finger continues to 874.91, and the
# four missing heights are exactly the islands.  The reason is structural: the
# VSS core-ring leg in the left finger tops out at y = 862 (the VDD leg reaches
# 876), the left finger's column-1 VSS M7 stripe is deliberately truncated at
# BASE_H-30.25 by the PG3 M7.S.4 fix, and the PG4 fabric-completion pass that
# draws the full-height M2 columns is `-nets {VDD}` only -- on the assumption
# that the follow-pin rails are already VSS everywhere.  In the top 20 um of
# the left finger they are not.
#
# WHY IT MATTERED.  Those rails are not filler-only.  Each of the four carries
# an MTCMOS HEADBUF16MA10TH header switch whose VSS pin is on the island; only
# its bulk tap is on real VSS.  The 9.9u header PMOS does not care, but the
# SLEEP/SLEEPOUT inverter pair's pull-down NMOS returned their current through
# the p-substrate.  Pegasus reported them as OPEN layout nets and its SCONNECT
# pass named them outright ("Rejected Nets: 1 3745 3746 3747 3748 3749") --
# rejected precisely BECAUSE they tap the substrate, which was the only ground
# they had.  A ninth island at y=879 was hidden by the second SCONNECT pass.
#
# THE DETECTOR IS THE POINT, not the repair.  It is derived from the row array
# and from metal, names no coordinate, and is re-run after the repair as the
# acceptance gate -- so this class cannot ship silently again.  Do NOT "fix"
# a future island by dropping a VSS: text on it so VIRTUAL_CONNECT merges it
# away: that deletes the only signal the flow has that a header switch is
# ungrounded.  That is the sentinel-blinding move the Stage J ring short
# exists to warn about.
################################################################################
proc pg6_q {area objtype} {
	set r {}
	if {[catch {set r [dbQuery -area $area -objType $objtype]}]} { return {} }
	return $r
}
# A candidate rail sits at a ROW EDGE.  Merge the row x-runs that share an
# edge, keep the runs that really carry a VSS follow-pin rail (which drops the
# two dead rows the M17b scrub strips bare), and ask each for a VIA1.
proc pg6_vss_rails {} {
	global DESIGN_WIDTH DESIGN_HEIGHT
	array unset __e
	foreach r [pg6_q [list 0 0 $DESIGN_WIDTH $DESIGN_HEIGHT] row] {
		foreach {rx0 ry0 rx1 ry1} [lindex [dbGet $r.box] 0] {}
		foreach ey [list $ry0 $ry1] {
			lappend __e([format %.2f $ey]) [list $rx0 $rx1]
		}
	}
	set out {}
	foreach k [lsort -real [array names __e]] {
		set merged {}
		foreach iv [lsort -real -index 0 $__e($k)] {
			foreach {a b} $iv {}
			if {[llength $merged] && $a <= [expr {[lindex [lindex $merged end] 1] + 0.001}]} {
				set last [lindex $merged end]
				lset merged end [list [lindex $last 0] [expr {max([lindex $last 1], $b)}]]
			} else {
				lappend merged [list $a $b]
			}
		}
		foreach iv $merged {
			foreach {a b} $iv {}
			set israil 0
			foreach o [pg6_q [list $a [expr {$k - 0.12}] $b [expr {$k + 0.12}]] sWire] {
				if {[dbGet -e $o.net.name] ne "VSS"} { continue }
				if {[dbGet -e $o.layer.name] ne "M1"} { continue }
				foreach {ox0 oy0 ox1 oy1} [lindex [dbGet $o.box] 0] {}
				if {[expr {$ox1 - $ox0}] < 1.0} { continue }
				set israil 1 ; break
			}
			if {!$israil} { continue }
			set hasvia 0
			foreach o [pg6_q [list $a [expr {$k - 0.25}] $b [expr {$k + 0.25}]] sVia] {
				if {[dbGet -e $o.net.name] ne "VSS"} { continue }
				if {![string match -nocase via1* [dbGet -e $o.via.name]]} { continue }
				set hasvia 1 ; break
			}
			lappend out [list $k $a $b $hasvia]
		}
	}
	return $out
}
proc pg6_m2_clear {x0 y0 x1 y1 net} {
	foreach t {sWire wire} {
		foreach o [pg6_q [list $x0 $y0 $x1 $y1] $t] {
			if {[dbGet -e $o.layer.name] ne "M2"} { continue }
			if {[dbGet -e $o.net.name] eq $net} { continue }
			return 0
		}
	}
	foreach o [pg6_q [list $x0 $y0 $x1 $y1] sVia] {
		if {[dbGet -e $o.net.name] eq $net} { continue }
		return 0
	}
	return 1
}
printStatus "PG6: VSS follow-pin rail island scan"
set __pg6_all [pg6_vss_rails]
set __pg6_isl {}
foreach __e $__pg6_all { if {![lindex $__e 3]} { lappend __pg6_isl $__e } }
logPuts "### UNL STATUS ### : PG6 VSS rail runs scanned = [llength $__pg6_all], UNGROUNDED ISLANDS = [llength $__pg6_isl]"
foreach __e $__pg6_isl {
	logPuts [format "PG6: island rail y=%.2f  x %.2f..%.2f" [lindex $__e 0] [lindex $__e 1] [lindex $__e 2]]
}
set __pg6_fixed 0
array unset __pg6g
foreach __e $__pg6_isl {
	# NB build the key in a variable first.  `lappend arr("$a_$b") v` does NOT
	# do what it looks like: quotes are not special mid-word, so the index
	# would carry the quote characters and `split` would hand expr `"1.0`.
	set __gk "[format %.1f [lindex $__e 1]]_[format %.1f [lindex $__e 2]]"
	lappend __pg6g($__gk) [lindex $__e 0]
}
foreach __k [array names __pg6g] {
	set __ys [lsort -real $__pg6g($__k)]
	foreach {__ka __kb} [split $__k _] {}
	set __anch {}
	foreach __e $__pg6_all {
		if {![lindex $__e 3]} { continue }
		if {abs([lindex $__e 1] - $__ka) > 0.5 || abs([lindex $__e 2] - $__kb) > 0.5} { continue }
		lappend __anch [lindex $__e 0]
	}
	if {[llength $__anch] == 0} {
		logPuts "PG6: no GROUNDED VSS rail shares x $__ka..$__kb -- the island cluster at y $__ys cannot be stitched locally"
		continue
	}
	set __ylo [lindex $__ys 0] ; set __yhi [lindex $__ys end]
	set __best "" ; set __bd 1e9
	foreach __ay $__anch {
		set __d [expr {$__ay < $__ylo ? $__ylo - $__ay : ($__ay > $__yhi ? $__ay - $__yhi : 0.0)}]
		if {$__d < $__bd} { set __bd $__d ; set __best $__ay }
	}
	set __sy0 [expr {min($__ylo, $__best) - 0.6}]
	set __sy1 [expr {max($__yhi, $__best) + 0.6}]
	# The column search IS the relocation ladder for this pass: it walks the run
	# and takes the first x that is clear.  pg6_m2_clear answers "is anything
	# foreign INSIDE this window", which is an overlap test, so the spacing
	# question is asked separately on the rung's own rectangle.
	# A rung 0.05 um from a routed wire is a DRC even though nothing is inside
	# the window, and that is the whole class this file grew a checker for.
	set __sx ""
	set __pg6tried 0
	for {set __cx [expr {$__ka + 2.0}]} {$__cx < [expr {$__kb - 2.0}]} {set __cx [expr {$__cx + 0.2}]} {
		incr __pg6tried
		if {![pg6_m2_clear [expr {$__cx - 0.55}] $__sy0 [expr {$__cx + 0.85}] $__sy1 VSS]} { continue }
		if {![pgc_ok [list [expr {$__cx - 0.15}] $__sy0 [expr {$__cx + 0.15}] $__sy1] M2 VSS]} { continue }
		set __sx $__cx ; break
	}
	if {$__sx eq ""} {
		logPuts "PG6: no clear M2 column anywhere in x $__ka..$__kb over y $__sy0..$__sy1 -- $__pg6tried x position(s) examined, cluster NOT repaired"
		continue
	}
	set __v1b 0
	foreach __o [pg6_q [list [expr {$__sx - 0.45}] $__sy0 [expr {$__sx + 0.45}] $__sy1] sVia] { incr __v1b }
	pgc_add_shape PG6 VSS M2 [list [expr {$__sx - 0.15}] $__sy0 [expr {$__sx + 0.15}] $__sy1]
	pgc_epv PG6 VSS M1 M2 VIA1 \
		[list [expr {$__sx - 0.45}] [expr {$__sy0 - 0.3}] [expr {$__sx + 0.45}] [expr {$__sy1 + 0.3}]] 1
	set __v1a 0
	foreach __o [pg6_q [list [expr {$__sx - 0.45}] $__sy0 [expr {$__sx + 0.45}] $__sy1] sVia] { incr __v1a }
	incr __pg6_fixed [llength $__ys]
	logPuts [format "PG6: rung at x=%.2f, y %.2f..%.2f stitches %d island rail(s) to the grounded rail at y=%.2f (vias in window %d -> %d)" \
		$__sx $__sy0 $__sy1 [llength $__ys] $__best $__v1b $__v1a]
}
# ACCEPTANCE: re-run the SAME detector on the repaired DB.
set __pg6_after {}
foreach __e [pg6_vss_rails] { if {![lindex $__e 3]} { lappend __pg6_after $__e } }
logPuts "### UNL STATUS ### : PG6 VSS rail islands [llength $__pg6_isl] -> [llength $__pg6_after] ($__pg6_fixed stitched)"
pgc_report PG6
foreach __e $__pg6_after {
	logPuts [format "PG6 RESIDUAL: island rail y=%.2f  x %.2f..%.2f" [lindex $__e 0] [lindex $__e 1] [lindex $__e 2]]
}
if {[llength $__pg6_after] > 0} {
	logPuts "FATAL (PG6): [llength $__pg6_after] VSS follow-pin rail(s) are still ungrounded islands. Each one is a run of row rail whose only path to ground is the p-substrate, and the 2026-08-25 cut proved they carry MTCMOS header switches. Saving $DATABASE_DIR/pg6_vssisland_fail.innovus; aborting."
	saveDesign $DATABASE_DIR/pg6_vssisland_fail.innovus
	exit 1
}

# PG4 v21 POST-MORTEM — the v19/v20 "final both-net dangling-stack scrub"
# and "floating-stub sweep" that lived here are DELETED, and must never
# come back in point-group form: the exact-(x,y) grouping rule (via3..6
# present, no via1/2/7 at the same point) called ~5000 groups dangling
# while Innovus' own antenna markers flagged only ~2200 — the excess were
# CONNECTED staircase stacks whose via1/2 sit at OFFSET centers (sroute
# builds them pad-overlapping, not co-centered). Deleting them cut the
# VNW/VPW well-bias feeds: tile LVS lit up with softchk nxwell 6597
# (v11-with-fabric baseline: 0) and ~500 unmatched bulk-sensitive devices,
# and the deleted pads left 43 REAL Calibre min-area slivers. The in-flow
# VSS-only 698-group scrub ABOVE is kept — it predates v12 and the v11 LVS
# (nxwell 0) proves it harmless. The leftover ~950-marker verifyGeometry
# ANTENNA class is DOCUMENTED NOISE: foundry ant25 = 0 on every cut.
# If litter must ever be scrubbed again, drive it from the verifyGeometry
# MARKERS (or a pad-overlap-aware union walk), never from point groups.
################################################################################
# PG1 acceptance gate (2026-07-10) — the hard check behind the dont_touch:
# 1. every SLEEP-chain net (psoPSI_*, *_pg1rep, pd_sleep) carries ONLY
#    HEADBUF switch pins and GPGBUF AO-repeater pins — one PD_GATED core
#    cell here silently un-gates a column-tail (PG1 finding F1);
# 2. ram0's PGEN and RETN are driven straight from the tcm_pgen/tcm_retn
#    ports — their receivers are on the macro's ALWAYS-ON rail, so any
#    in-tile driver is a dying-rail driver (PG1 finding F2).
# Runs after every optimization step is done; FAILS THE RUN on violation.
################################################################################
printStatus "PG1 acceptance gate"
set pg1_bad 0
foreach np [concat [dbGet -p top.nets.name psoPSI_* -e] [dbGet -p top.nets.name *_pg1rep -e] [dbGet -p top.nets.name pd_sleep -e]] {
	foreach it [dbGet $np.instTerms -e] {
		set c [dbGet $it.inst.cell.name]
		if {![string match HEADBUF* $c] && ![string match GPGBUF* $c]} {
			incr pg1_bad
			logPuts "PG1 VIOLATION: foreign cell [dbGet $it.name] ($c) on chain net [dbGet $np.name]"
		}
	}
}
foreach {pin port} {PGEN tcm_pgen RETN tcm_retn} {
	set np [dbGet -p top.insts.name ram0]
	set it [dbGet -p $np.instTerms.name ram0/$pin]
	set nn [dbGet $it.net.name]
	if {$nn ne $port} {
		incr pg1_bad
		logPuts "PG1 VIOLATION: ram0/$pin is driven by net '$nn', expected the AO port net '$port'"
	}
}
if {$pg1_bad > 0} {
	logPuts "FATAL (PG1): $pg1_bad power-gating acceptance violations — aborting before signoff"
	exit 1
}
logPuts "### UNL STATUS ### : PG1 acceptance gate PASSED (chain pure, ram0 PG pins port-driven)"

################################################################################
# WIDE-METAL SAME-NET CHANNEL UNION (2026-08-25).  M6.S.4 / M7.S.4 / M8.S.4.
#
# THE RULE.  "If EITHER line is wider than 4.50 and the parallel run exceeds
# 4.50, the space must be >= 1.50."  It is NET-BLIND: the foundry deck does not
# care that both sides are VDD.  The tech LEF carries it exactly, in the M6 and
# M7 SPACINGTABLEs (WIDTH 4.50 ... PARALLELRUNLENGTH 4.50 -> 1.50).
#
# WHAT IT COST ON THE 2026-08-17 CUT.  Three of hart_tile's eight Calibre
# results were ONE object: a 0.400-wide VDD M7 stitch at x 599.750..600.150,
# y 866..876, with its 0.300-wide M6 partner underneath, dropped into the
# 2.000 um channel between a 10 um VDD stripe ending at x=599.000 and a 5 um
# VDD stripe starting at x=601.000.  Two gaps, 0.750 and 0.850, both under
# 1.50, both with a 10 um parallel run:
#     M7.S.4 (599.000,866.000) 0.750 x 10.000
#     M7.S.4 (600.150,866.000) 0.850 x 10.000
#     M6.S.4 (600.100,866.000) 0.900 x  5.000
#
# WHY IT CANNOT BE LEGALISED BY MOVING OR NARROWING.  1.50 + w + 1.50 needs
# 3.00 um of channel even at w = 0, and the channel is 2.00 um.  There is no
# width and no position for that stitch that satisfies the rule.
#
# SO MERGE IT.  All five participating shapes are the SAME NET.  A rule that
# measures a SPACE stops seeing one when the shapes become a single union, and
# this file already established that as its house fix for this exact rule --
# see "PG4 M7 pad-bridge pass" above: "One full-run-height M7 rect bridges pad
# and stripe into a single union shape — additive, same net, M7 is power-only
# here."  This is the same move, generalised.
#
# MERGE, NOT DELETE, AND THAT CHOICE IS LOAD-BEARING.  Deleting the stitch also
# clears the rule, but that 0.400 rect is an advertised `PIN VDD / LAYER M7`
# RECT in out/hart_tile.lef, so removing it changes what MCU_hart's sroute
# blockPin pass finds to strap -- a silent cross-lineage change to a macro two
# tops bind.  Filling adds geometry to a pin that already exists and changes
# no pin's identity.
#
# DERIVED, NEVER FROZEN.  This scans the final PG geometry for the rule's own
# trigger conditions.  It does not name a coordinate.  Hardcoding this site is
# precisely what the stale M2.A.1 patch above did, and that patch shipped two
# DRC results of its own when the placement moved beneath it.
################################################################################
printStatus "wide-metal same-net channel union (M6.S.4/M7.S.4/M8.S.4)"
set WM_WIDE      4.50
set WM_SPACE     1.50
set WM_RUN       4.50
set __wm_fill    0
set __wm_report  {}
set __wm_fill_list {}
foreach __wlay {M6 M7 M8} {
	foreach __wnet {VDD VSS} {
		set __np [dbGet -p top.nets.name $__wnet -e]
		if {$__np eq "0x0" || $__np eq ""} { continue }
		# collect this net's shapes on this layer
		set __shapes {}
		foreach __o [dbGet $__np.sWires -e] {
			if {[dbGet -e $__o.layer.name] ne $__wlay} { continue }
			set __b [lindex [dbGet $__o.box] 0]
			if {[llength $__b] != 4} { continue }
			lappend __shapes $__b
		}
		set __shapes [lsort -unique $__shapes]
		# CENSUS.  The first run of this pass filled 0 channels and said only
		# that, which is indistinguishable from 'nothing to fix' -- and the
		# M6/M7 stitch it was written for demonstrably still exists.  Report
		# what was actually collected so a zero is diagnosable.
		logPuts [format {WM census: %s %s -- %d shapes collected} $__wnet $__wlay [llength $__shapes]]
		if {[llength $__shapes] < 2} { continue }
		# x-gaps: sort by left edge, compare each shape with the ones that start
		# before its right edge + WM_SPACE.  O(n * small) instead of O(n^2).
		set __sx [lsort -real -index 0 $__shapes]
		set __n [llength $__sx]
		for {set __i 0} {$__i < $__n} {incr __i} {
			foreach {__ax0 __ay0 __ax1 __ay1} [lindex $__sx $__i] {}
			set __aw [expr {$__ax1 - $__ax0}]
			for {set __j [expr {$__i + 1}]} {$__j < $__n} {incr __j} {
				foreach {__bx0 __by0 __bx1 __by1} [lindex $__sx $__j] {}
				set __gap [expr {$__bx0 - $__ax1}]
				if {$__gap >= $WM_SPACE} { break }
				if {$__gap <= 0.0} { continue }
				set __bw [expr {$__bx1 - $__bx0}]
				if {$__aw <= $WM_WIDE && $__bw <= $WM_WIDE} { continue }
				set __oy0 [expr {max($__ay0, $__by0)}]
				set __oy1 [expr {min($__ay1, $__by1)}]
				if {[expr {$__oy1 - $__oy0}] <= $WM_RUN} { continue }
				lappend __wm_fill_list [list $__wnet $__wlay $__ax1 $__oy0 $__bx0 $__oy1]
			}
		}
		# y-gaps: same, on the other axis
		set __sy [lsort -real -index 1 $__shapes]
		for {set __i 0} {$__i < $__n} {incr __i} {
			foreach {__ax0 __ay0 __ax1 __ay1} [lindex $__sy $__i] {}
			set __ah [expr {$__ay1 - $__ay0}]
			for {set __j [expr {$__i + 1}]} {$__j < $__n} {incr __j} {
				foreach {__bx0 __by0 __bx1 __by1} [lindex $__sy $__j] {}
				set __gap [expr {$__by0 - $__ay1}]
				if {$__gap >= $WM_SPACE} { break }
				if {$__gap <= 0.0} { continue }
				set __bh [expr {$__by1 - $__by0}]
				if {$__ah <= $WM_WIDE && $__bh <= $WM_WIDE} { continue }
				set __ox0 [expr {max($__ax0, $__bx0)}]
				set __ox1 [expr {min($__ax1, $__bx1)}]
				if {[expr {$__ox1 - $__ox0}] <= $WM_RUN} { continue }
				lappend __wm_fill_list [list $__wnet $__wlay $__ox0 $__ay1 $__ox1 $__by0]
			}
		}
	}
}
# Emit after scanning, never during: add_shape while iterating dbGet results
# invalidates the very list being walked.
if {[llength $__wm_fill_list] > 0} {
	foreach __f [lsort -unique $__wm_fill_list] {
		foreach {__fnet __flay __fx0 __fy0 __fx1 __fy1} $__f {}
		# SAFETY: never fill across a foreign net.  By construction the gap is
		# between two same-net shapes, but a third net's shape can sit inside
		# it on the same layer -- fill there and a same-net cosmetic becomes a
		# hard short.  Check before drawing, every time.
		# This WAS two containment loops, "is a foreign shape inside the channel
		# I am about to fill".  That answers the short question and nothing else:
		# a plate laid 0.30 um from a foreign M7 is legal by that test and a
		# M7.S.3 by the deck.  The halo is 2.0 um here because the wide-metal
		# tiers on these layers reach 1.50 um, so a 0.6 um look would not see
		# the neighbour the rule is about.
		set __wp [pgc_probe [list $__fx0 $__fy0 $__fx1 $__fy1] $__flay $__fnet 2.0]
		set __wv [lindex $__wp 0]
		if {$__wv ne "CLEAR" && $__wv ne "MERGED"} {
			lappend __wm_report [pgc_say "SKIPPED" [list $__fx0 $__fy0 $__fx1 $__fy1] $__flay $__fnet $__wp]
			continue
		}
		add_shape -net $__fnet -layer $__flay -shape STRIPE -status ROUTED \
			-rect [list $__fx0 $__fy0 $__fx1 $__fy1]
		incr __wm_fill
		lappend __wm_report [format "united %s %s (%.3f,%.3f)-(%.3f,%.3f) gap %.3f" \
			$__fnet $__flay $__fx0 $__fy0 $__fx1 $__fy1 [expr {($__fx1 - $__fx0) < ($__fy1 - $__fy0) ? ($__fx1 - $__fx0) : ($__fy1 - $__fy0)}]]
	}
}
printStatus "wide-metal same-net channel union — $__wm_fill sub-1.50 um same-net channels filled"
foreach __r $__wm_report { logPuts "### UNL STATUS ### :   $__r" }

################################################################################
# THE ONE CHANNEL THE PASS ABOVE CANNOT SEE, AND WHY IT NO LONGER NEEDS A PASS.
#
# The census above collects with `dbGet net.sWires`, and the top-right riser's
# M6/M7 metal is not on the net's special-wire list at all: it is the LANDING
# PAD OF A VIA STACK, which is why no amount of repainting metal ever moved it.
# tcl/wm_merge.tcl used to find the same object spatially and merge the three
# flanking VDD shapes into one union, so that a rule which measures a SPACE
# stopped seeing one.
#
# THAT PASS IS GONE (2026-08-26).  The pad is now short instead of merged: the
# narrow-strap addStripe passes carry -split_long_via $RISER_VIA_SPLIT, so a
# riser crossing a 10 um PG band lands three ~2.6-3.0 um via pieces instead of
# one 10.00 um pad, and the wide-metal rule's parallel-run gate (4.505 um,
# measured) never opens.  ../shared/constants.tcl carries the arithmetic beside
# the constant, and the reason enclosure could not have done it.
################################################################################

################################################################################
# Signoff checks + reports
################################################################################
printStatus "verifyConnectivity"
verifyConnectivity \
    -error 100000 \
    -connectPadSpecialPorts \
    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt

# PG5 ACCEPTANCE (2026-08-25): ram0's VSSE block pins, read out of Innovus's
# OWN report rather than re-derived.  Before the PG5 blockPin sroute, 16 of the
# macro's 17 VSSE ports had no metal on them at all and Innovus said so on
# every cut since at least 2026-08-17 -- IMPVFC-96, one line per port, all at
# x=75.000.  Nobody read them, and the tile shipped with the macro's whole
# internal ground half (16,885 attachments, 8,901 of them device bulk) as an
# LVS OPEN.  Reading the count here makes that impossible to repeat.
set __r0vsse 0
if {[catch {set __fh [open $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt r]}]} {
	logPuts "### UNL STATUS ### : PG5 acceptance -- verifyConnectivity report not readable; ram0/VSSE not checked"
} else {
	while {[gets $__fh __ln] >= 0} {
		if {[string match "*ram0/VSSE*unconnected terminal*" $__ln]} { incr __r0vsse }
	}
	close $__fh
	logPuts "### UNL STATUS ### : PG5 acceptance -- ram0/VSSE unconnected terminals = $__r0vsse (2026-08-17..25 baseline: 16)"
	if {$__r0vsse > 0} {
		logPuts "FATAL (PG5): $__r0vsse ram0/VSSE port(s) carry no metal -- the TCM's ground half is still an island. Saving $DATABASE_DIR/pg5_vsse_fail.innovus; aborting."
		saveDesign $DATABASE_DIR/pg5_vsse_fail.innovus
		exit 1
	}
}
printStatus "verifyGeometry"
# SAME-NET CHECKING (2026-08-25).  setVerifyGeometryMode appeared NOWHERE in
# this file, so every verifyGeometry above ran at defaults and its "SameNet: 0"
# was never a measurement -- it was the tool not being asked.
#
# That blind spot has a measured cost.  Three of hart_tile's eight Calibre
# results on the 2026-08-17 cut (M6.S.4 once, M7.S.4 twice) are SAME-NET
# wide-metal spacing: five VDD shapes, no foreign net anywhere near them.
# M6.S.4/M7.S.4 are net-BLIND rules -- the foundry deck does not care that both
# sides are VDD -- so Calibre saw all three while Innovus reported SameNet: 0
# and the run looked clean.  Turning this on is what makes the class fail here,
# in a 10-minute run, instead of in a Pegasus run two days later.
setVerifyGeometryMode -sameNet true
# PG4 v20: -error — the default 1000 cap TRUNCATED the v18/v19 signoff
# summaries (both reports stopped at exactly 1000; class counts under the
# cap are meaningless). The signoff numbers must be uncapped to be a
# baseline.
verifyGeometry \
    -antenna \
    -error 100000 \
    -warning 100000 \
    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt

################################################################################
# G0 REPAIR, IN THE FLOW (2026-08-25).
#
# WHAT CHANGED AND WHY.  Until now this flow DETECTED the router-vs-cell-OBS M1
# merge and stopped there, and the repair was a hand-written ECO per cut:
# cpr5b_eco.tcl, then tcm11_eco.tcl, then g0_eco.tcl, each keyed to instance
# names and coordinates from one placement and each correctly refusing to run
# on any other.  Every one of those ECOs also had to re-emit the collateral
# itself, and every one of them got some of it wrong -- tcm11_eco.tcl and
# drc_eco.tcl dropped the tile abstract's whole per-pin antenna model
# (ANTENNAGATEAREA 127 -> 0) because they called lefOut with no
# verifyProcessAntenna in front of it, and none of the three ever re-emitted
# the ILM at all.
#
# ORDERING, WHICH IS THE POINT.  This runs BEFORE every shipped file:
# saveDesign signoff, streamOut, write_sdf, saveNetlist, createInterfaceLogic,
# lefOut, both ETMs and saveDesign final are all below it.  The only writes
# above it are abort snapshots.  So there is one cut and one state, which is
# exactly what M19c did not have.
#
# The pre-repair report is kept beside the repaired one.  A run with nothing to
# repair leaves two identical files, which is a measurement; a missing
# .prerepair.rpt means this block did not execute at all.
################################################################################
printStatus "G0 repair (router-vs-cell-OBS M1 merges)"
file copy -force $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt \
                 $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.prerepair.rpt
set __g0r [g0r_repair_loop $REPORT_DIR $DESIGN_NAME \
           $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.prerepair.rpt]
foreach {__g0_before __g0_after __g0_passes} $__g0r {}
logPuts "### UNL STATUS ### : G0REPAIR -- sites $__g0_before -> $__g0_after in $__g0_passes pass(es)"
if {$__g0_after < 0} {
	logPuts "FATAL (G0REPAIR): the repair aborted part-way through. The database now holds ripped or"
	logPuts "                  half-fenced routing and must not be streamed out. Saving"
	logPuts "                  $DATABASE_DIR/g0repair_fail.innovus; aborting before any collateral."
	saveDesign $DATABASE_DIR/g0repair_fail.innovus
	exit 1
}
if {$__g0_before > 0} {
	# The signoff report has to describe the SHIPPED state, so re-measure with
	# the same flags rather than leaving the pre-repair numbers in place.
	printStatus "verifyGeometry (re-run after the G0 repair)"
	verifyGeometry \
	    -antenna \
	    -error 100000 \
	    -warning 100000 \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt
	verifyConnectivity \
	    -error 100000 \
	    -connectPadSpecialPorts \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt
	set __r0vsse2 0
	if {![catch {set __fh [open $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt r]}]} {
		while {[gets $__fh __ln] >= 0} {
			if {[string match "*ram0/VSSE*unconnected terminal*" $__ln]} { incr __r0vsse2 }
		}
		close $__fh
	}
	logPuts "### UNL STATUS ### : G0REPAIR -- ram0/VSSE unconnected terminals after the repair = $__r0vsse2 (must stay 0)"
	if {$__r0vsse2 > 0} {
		logPuts "FATAL (G0REPAIR): the repair re-opened $__r0vsse2 ram0/VSSE terminal(s). Saving $DATABASE_DIR/g0repair_fail.innovus; aborting."
		saveDesign $DATABASE_DIR/g0repair_fail.innovus
		exit 1
	}
}

################################################################################
# PGS (2026-08-26) -- PG SPACING AT SIGNOFF, AND THE PING-PONG IT BREAKS.
#
# The post-route PGR stage clears this class while the PG route blockages are
# still up.  It is not enough, and the first run with it proved why in one line:
#
#   G0REPAIR STAGE 1 pass 1 -- merges 0, non-antenna total 1 (before repair: 2)
#
# The G0 repair's bare ecoRoute took the two router-versus-cell-OBS M1 merges to
# zero and, on the SAME net, put the M2 back into the 0.05 um gap beside the VDD
# strap that PGR had just moved it out of.  Innovus reported it, as
# "SPACING: Regular Wire of Net core/n_1239 & Special Wire of Net VDD ( M2 )",
# and the G0 repair walked past it because it counts merges.
# Post-route measurement is therefore necessary and NOT sufficient: anything
# that re-routes after it can undo it, and the G0 repair is exactly that.
#
# THE FENCES ACCUMULATE, and that is the mechanism, not a detail.  The two
# classes are each other's escape route: fence the cell OBS and the router takes
# the strap gap, fence the strap and it takes the cell OBS.  Holding BOTH fences
# up at once is what leaves it a third path.  So this loop creates its PG fences
# and does not drop them between passes, and it calls the G0 repair from INSIDE
# the loop so that repair's own ecoRoute runs with the PG fences standing.
#
# The fences come down before the final verifyGeometry, because a fence is a
# routing blockage and would otherwise appear in the shipped-state report as
# markers of its own.
#
# NOT FATAL here.  The Wiring gate below is what judges the cut.
################################################################################
printStatus "PGS: PG spacing repair (regular routing too close to PG metal)"
set __pgs [pgc_spacing_residuals $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt]
if {$__pgs eq "ERROR"} {
	logPuts "FATAL (PGS): the signoff verifyGeometry report could not be read, so the PG spacing"
	logPuts "             scan examined NOTHING and a zero here would not be a measurement."
	logPuts "             Saving $DATABASE_DIR/pgs_read_fail.innovus; aborting."
	saveDesign $DATABASE_DIR/pgs_read_fail.innovus
	exit 1
}
set __pgs_n0 [llength $__pgs]
set __pgs_fn {}
set __pgs_p 0
logPuts "### UNL STATUS ### : PGS -- $__pgs_n0 regular-versus-PG spacing marker(s) after the G0 repair"
while {[llength $__pgs] > 0 && $__pgs_p < 3} {
	incr __pgs_p
	foreach __r $__pgs {
		foreach {__rn __rl __fx0 __fy0 __fx1 __fy1} $__r {}
		set __cut [expr {$__rl eq "M3" ? "VIA2" : "VIA1"}]
		set __nm pgs_fence_${__pgs_p}_[llength $__pgs_fn]
		if {[catch {createRouteBlk -name $__nm -layer $__rl -cutLayer $__cut \
		     -box [list $__fx0 $__fy0 $__fx1 $__fy1]} __e]} {
			logPuts "### UNL STATUS ### : PGS   fence $__nm on $__rl failed: $__e"
			continue
		}
		lappend __pgs_fn $__nm
	}
	set __pgs_nets {}
	foreach __r $__pgs {
		set __n [lindex $__r 0]
		if {[lsearch -exact $__pgs_nets $__n] < 0} { lappend __pgs_nets $__n }
	}
	set __pgs_dt {}
	foreach __n $__pgs_nets {
		set __np [dbGetNetByName $__n]
		if {$__np eq "" || $__np == 0x0} {
			logPuts "### UNL STATUS ### : PGS   net $__n not found in the database, skipped"
			continue
		}
		set __dtwas [dbGet $__np.dontTouch]
		if {$__dtwas} { dbSet $__np.dontTouch false }
		set __wb [llength [dbGet -e $__np.wires]]
		deselectAll
		editSelect -net $__n
		editDelete -selected
		deselectAll
		logPuts "### UNL STATUS ### : PGS   RIP $__n wires $__wb -> [llength [dbGet -e $__np.wires]]"
		lappend __pgs_dt [list $__n $__dtwas]
	}
	logPuts "### UNL STATUS ### : PGS pass $__pgs_p -- [llength $__pgs_fn] fence(s) standing, [llength $__pgs_dt] net(s) ripped"
	ecoRoute
	ecoRoute -fix_drc
	foreach __rr $__pgs_dt {
		foreach {__n __dtwas} $__rr {}
		set __np [dbGetNetByName $__n]
		if {$__np eq "" || $__np == 0x0} { continue }
		if {[llength [dbGet -e $__np.wires]] == 0} {
			logPuts "FATAL (PGS): $__n was ripped and came back with NO wires. A net this pass opened and"
			logPuts "             did not close is worse than the spacing violation it was chasing."
			logPuts "             Saving $DATABASE_DIR/pgs_open_fail.innovus; aborting."
			saveDesign $DATABASE_DIR/pgs_open_fail.innovus
			exit 1
		}
		if {$__dtwas} { dbSet $__np.dontTouch true }
	}
	verifyGeometry \
	    -antenna \
	    -error 100000 \
	    -warning 100000 \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt
	# The re-route above is measured to be able to TRADE this class for a
	# router-versus-cell-OBS merge.  Repair that HERE, while the PG fences are
	# still standing, so the two repairs cannot hand the net back and forth.
	set __pgs_g0 [llength [g0r_parse_markers $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt]]
	if {$__pgs_g0 > 0} {
		logPuts "### UNL STATUS ### : PGS   the re-route left $__pgs_g0 router-vs-cell-OBS merge(s); repairing them with the PG fences up"
		# STAGE 1 IS DISABLED FOR THE NESTED CALL, and that is deliberate.
		# Stage 1 is a bare global ecoRoute, and a bare global ecoRoute is what
		# put this net back in the strap gap in the first place; run here it
		# takes the merges to zero and hands back two SPACING markers against
		# the same cell (measured on the 04:22 database: non-antenna 7 -> 11,
		# and g0_repair's own STAGE 1 said so in its trade warning).
		# Stage 2 rips the net and fences the offending cell's OBS, so with the
		# PG fence already standing BOTH escape routes are closed at once, which
		# is the only configuration in which this net has to find a third one.
		set __g0conv_save $G0R_CONVPASS
		set G0R_CONVPASS 0
		set __pgs_g0r [g0r_repair_loop $REPORT_DIR $DESIGN_NAME \
		               $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt]
		set G0R_CONVPASS $__g0conv_save
		if {[lindex $__pgs_g0r 1] < 0} {
			logPuts "FATAL (PGS): the nested G0 repair aborted part-way through. Saving"
			logPuts "             $DATABASE_DIR/pgs_g0_fail.innovus; aborting before any collateral."
			saveDesign $DATABASE_DIR/pgs_g0_fail.innovus
			exit 1
		}
		verifyGeometry \
		    -antenna \
		    -error 100000 \
		    -warning 100000 \
		    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt
	}
	set __pgs [pgc_spacing_residuals $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt]
	if {$__pgs eq "ERROR"} { set __pgs {} ; break }
	logPuts "### UNL STATUS ### : PGS after pass $__pgs_p -- [llength $__pgs] PG spacing marker(s) left"
}
if {[llength $__pgs_fn] > 0} {
	foreach __nm $__pgs_fn { catch {deleteRouteBlk -name $__nm} }
	logPuts "### UNL STATUS ### : PGS -- [llength $__pgs_fn] fence(s) removed; re-measuring the shipped state"
	verifyGeometry \
	    -antenna \
	    -error 100000 \
	    -warning 100000 \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt
	verifyConnectivity \
	    -error 100000 \
	    -connectPadSpecialPorts \
	    -report $REPORT_DIR/$DESIGN_NAME.verifyConnectivity.signoff.rpt
}
logPuts "### UNL STATUS ### : PGS -- PG spacing markers $__pgs_n0 -> [llength $__pgs] in $__pgs_p pass(es)"

################################################################################
# CPR5 G0-CLASS ACCEPTANCE BANNER (2026-08-15).
#
# The signoff verifyGeometry above ALREADY reported this class in M19c and
# nobody read the summary, so the tile shipped with a real M1 merge that only
# foundry LVS ever named. This banner makes the non-antenna counts impossible
# to walk past. It is deliberately NOT a FATAL: the collateral downstream
# (LEF/ETM/GDS/SDF/xsim.v) must still be emitted from THIS cut so that a
# residual is at least self-consistent -- the M19c failure mode was a repair
# applied to the GDS alone, leaving the LEF and xsim.v from the unrepaired
# state. Judge the run on this banner, not on the run completing.
################################################################################
proc cpr5_vg_acceptance {rptfile} {
	set cells 0; set samenet 0; set wiring 0; set short 0; set overlap 0
	if {![file exists $rptfile]} {
		printStatus "G0 ACCEPTANCE — report $rptfile missing, cannot judge"
		return
	}
	set fh [open $rptfile r]
	while {[gets $fh line] >= 0} {
		if {[regexp {^\s*Cells\s*:\s*(\d+)}   $line -> v]} { set cells   $v }
		if {[regexp {^\s*SameNet\s*:\s*(\d+)} $line -> v]} { set samenet $v }
		if {[regexp {^\s*Wiring\s*:\s*(\d+)}  $line -> v]} { set wiring  $v }
		if {[regexp {^\s*Short\s*:\s*(\d+)}   $line -> v]} { set short   $v }
		if {[regexp {^\s*Overlap\s*:\s*(\d+)} $line -> v]} { set overlap $v }
	}
	close $fh
	set tot [expr {$cells + $samenet + $wiring + $short + $overlap}]
	# 2026-08-25: printStatus, NOT puts.  This banner did its job on the
	# 2026-08-17 cut -- it computed total 5 and said so -- and the warning was
	# lost anyway, because bare `puts` goes to the console and only
	# printStatus's four-hash lines reach log/hart_tile.log.  The run was
	# judged from the log, the log was silent, and a real LVS short shipped.
	# A guard that fires where nobody is looking is not a guard.
	printStatus "G0 ACCEPTANCE — verifyGeometry NON-ANTENNA: Cells=$cells SameNet=$samenet Wiring=$wiring Short=$short Overlap=$overlap (total $tot)"
	if {$tot > 0} {
		printStatus "G0-CLASS RESIDUAL PRESENT: $tot non-antenna verifyGeometry violations — see the banner below and $rptfile"
		logPuts "###############################################################################"
		logPuts "### G0-CLASS RESIDUAL PRESENT: $tot non-antenna verifyGeometry violations.  ###"
		logPuts "### THIS IS NOT COSMETIC. A 'Short: Regular Via/Wire of Net X & Blockage of ###"
		logPuts "### Cell Y (M1)' entry is a REAL merge with that cell's internal M1 node and ###"
		logPuts "### will come back as a Pegasus LVS SHORT (measured, CPR5 2026-08-15:        ###"
		logPuts "### psoPSI...pg1rep vs Xtie_0_cell7/LO, devices 351:348).                    ###"
		logPuts "### The M19c cut shipped with the identical Short=1 unnoticed and was        ###"
		logPuts "### repaired by an out-of-flow ECO, which is why its LEF/xsim.v and its      ###"
		logPuts "### GDS/SDF came from two different states. DO NOT repeat that: repair in    ###"
		logPuts "### the flow and re-emit ALL collateral, or record the residual explicitly.  ###"
		logPuts "### Offending entries: grep -E '^(SHORT|SPACING)' $rptfile                   ###"
		logPuts "###############################################################################"
	}
}
cpr5_vg_acceptance $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt

################################################################################
# G0 HARD GATE + NON-ANTENNA CLASS CENSUS (2026-08-25).
#
# The banner above is deliberately advisory, and that was the right call while
# the repair lived outside the flow: a residual had to be shippable so that the
# collateral at least came from one state.  It is no longer the right call.
# The repair now runs above, before any file is written, so a surviving
# "Blockage of Cell ( M1 )" marker means the repair FAILED, and that marker is
# a real merge between a signal net and a cell-internal node -- measured twice
# as a Pegasus LVS SHORT (2026-08-15 tie_0_cell7, 2026-08-25 n_421 and n_1532).
# Emitting a GDS on top of one is the M19c mistake with extra steps, so this
# aborts instead, leaving the database under an unmistakable name.
#
# The census below is not decoration.  A bare total cannot tell a NEW class
# from one the cut is already known to carry, and until 2026-08-26 this cut
# carried one: MINCUT x4 (VIA1.R.2/R.3) on the LUP.6 well-tap jogs, recorded
# here as the documented price of closing latch-up at source.
#
# IT WAS NOT A PRICE.  Those four markers were an ARTIFACT: the PG4/F2b link
# bar landed 0.08 um BESIDE the well-tap jog instead of on it, and Calibre
# unions two 0.30 um bars 0.08 um apart into one 0.38 um line, which is wider
# than the VIA1.R.2 trigger.  PG4/F2b is same-net aware now (see the MINCUT
# block there), the class is designed out at source, and latch-up gave up
# nothing.  This cut is expected to carry NO non-antenna class at all.
#
# MINCUT is therefore a hard gate below, alongside SHORT.  Naming every class
# by its own count is still what makes "as expected" distinguishable from "of
# something new".
################################################################################
set __vgclass {}
set __vgtot 0
set __vgread 0
catch {unset __vgc}
if {[catch {set __fh [open $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt r]}]} {
	logPuts "### UNL STATUS ### : G0 GATE -- signoff verifyGeometry report unreadable; the class census did NOT run"
} else {
	set __vglines 0
	while {[gets $__fh __ln] >= 0} {
		incr __vglines
		if {![regexp {^([A-Z]+):} $__ln -> __k]} { continue }
		if {$__k eq "ANTENNA"} { continue }
		if {[info exists __vgc($__k)]} { incr __vgc($__k) } else { set __vgc($__k) 1 }
		incr __vgtot
	}
	close $__fh
	foreach __k [lsort [array names __vgc]] { lappend __vgclass "$__k=$__vgc($__k)" }
	if {$__vgtot == 0} { set __vgclass "none" }
	logPuts "### UNL STATUS ### : G0 GATE -- $__vglines report line(s) examined; non-antenna marker classes: $__vgclass (total $__vgtot)"
	set __vgread 1
}
# MINCUT IS A HARD GATE NOW (2026-08-26), for the same reason SHORT is.
# Innovus verifyGeometry and Calibre agree exactly on this class.  On the
# 2026-08-25 cut both named FOUR markers at the same four sites -- the PG4/F2b
# link bars at x 397.10..399.27 and x 49.10..59.27 and their VIA1s -- and moving
# those two bars 0.08 um took Innovus MINCUT from 4 to 0 and Calibre
# VIA1.R.2__VIA1.R.3 from 4 to 0 with nothing else in a 1592-rulecheck deck
# moving.  So this class is free to detect in-flow, and a survivor here is a
# signoff DRC result found ten minutes into the run instead of an hour after it.
set __mincut 0
if {[info exists __vgc(MINCUT)]} { set __mincut $__vgc(MINCUT) }
logPuts "### UNL STATUS ### : G0 GATE -- verifyGeometry MINCUT count in the SHIPPED state = $__mincut (must be 0)"
if {!$__vgread} {
	logPuts "FATAL (G0 GATE): the signoff verifyGeometry report could not be read, so the MINCUT count above is a DEFAULT and not a measurement."
	logPuts "                 A gate that never examined anything must not report a pass. Saving $DATABASE_DIR/mincut_fail.innovus; aborting."
	saveDesign $DATABASE_DIR/mincut_fail.innovus
	exit 1
}
if {$__mincut > 0} {
	logPuts "FATAL (G0 GATE): $__mincut MINCUT marker(s) survive into the shipped state."
	logPuts "                 Each one is a single-cut VIA1 under an M2 line that Calibre will union to"
	logPuts "                 more than 0.30 um wide, and it comes back as VIA1.R.2__VIA1.R.3."
	logPuts "                 The known cause is a PG4/F2b link bar laid BESIDE a same-net 0.30 um bar"
	logPuts "                 instead of on it -- grep the log for 'PG4/F2b:' and read the offered row count."
	logPuts "                 No collateral is emitted. Saving $DATABASE_DIR/mincut_fail.innovus; aborting."
	logPuts "                 Sites: grep -A2 '^MINCUT' $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt"
	saveDesign $DATABASE_DIR/mincut_fail.innovus
	exit 1
}
# SHORT MUST ALSO BE ZERO, not just the G0 subclass.  A bare ecoRoute is
# measured to be able to TRADE a G0 merge for a different hard short -- on the
# 2026-08-15 placement it produced a Regular-Wire-vs-VDD-stripe short at
# (505.25,420.31), the PG-squeezed sibling class whose only known fix is a
# placement nudge.  A gate that only counts G0 markers would call that a
# success.
set __shortleft 0
if {![catch {set __fh [open $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt r]}]} {
	while {[gets $__fh __ln] >= 0} {
		if {[regexp {^\s*Short\s*:\s*([0-9]+)} $__ln -> __v]} { set __shortleft $__v }
	}
	close $__fh
}
logPuts "### UNL STATUS ### : G0 GATE -- verifyGeometry Short count in the SHIPPED state = $__shortleft (must be 0)"
if {$__shortleft > 0} {
	logPuts "FATAL (G0 GATE): $__shortleft short(s) in the shipped state. Whatever class they are, a"
	logPuts "                 Short here is two nets merged in the layout and Pegasus will say so."
	logPuts "                 No collateral is emitted. Saving $DATABASE_DIR/g0repair_fail.innovus."
	logPuts "                 Sites: grep -A2 '^SHORT' $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt"
	saveDesign $DATABASE_DIR/g0repair_fail.innovus
	exit 1
}
# WIRING IS A HARD GATE NOW (2026-08-26), and it is the one this cut needed.
#
# The 2026-08-26 via-split cut shipped with Wiring=2 in exactly this report and
# the run completed, because nothing here counted that bucket.  Those two
# markers came back from Calibre as M1.S.1 and M2.S.1, at the same coordinates,
# with the same measured gaps: Innovus said 0.076 against 0.09 and 0.05 against
# 0.1, Calibre said 0.076 against 0.09 and 0.05 against 0.1.
# The two engines agree on this class to the digit, so a survivor here is a
# signoff DRC result found ten minutes into the run instead of an hour after it,
# and there is no reason to let it reach a GDS.
#
# The banner above already printed the number.  It printed it on the last cut
# too.  A number in a banner nobody has to act on is how this flow has shipped
# every one of its defects, so this one aborts.
# THE GATE COUNTS THE PG CLASS, NOT THE WHOLE Wiring BUCKET, and the narrowing
# is deliberate and was measured into place.
#
# The first cut with this gate in it aborted on Wiring=2 that turned out to be
#   EndOfLine: Pin of Cell ...g45172 & Pin of Cell ...g45172  ( M1 )  0.09/0.11
#   EndOfLine: Regular Via of Net ...n_665 & Pin of that cell  ( M1 )  0.10/0.11
# Neither names a Special object.  The first is a foundry cell's own two pins
# measured against Innovus' LEF-derived end-of-line rule, which is a statement
# about the ABSTRACT and not about the cell's layout, and no PG pass and no
# router decision of this flow can move either of them.
# Gating the whole bucket would therefore have stopped every future cut on a
# class this repair has no lever over, and a gate that cannot be satisfied gets
# widened by the next person rather than obeyed.
#
# So the hard gate is: SPACING or EndOfLine markers that name a SPECIAL object,
# which is exactly PG metal against something it should not be near, and exactly
# what the PGR, PGCLEAR and PGS stages above are able to repair.  The rest of the
# bucket is still counted and still printed, immediately below and in the
# acceptance banner above, and is still a reason to read the report.
set __wiringleft 0
set __pgwire 0
set __pgwirelist {}
if {![catch {set __fh [open $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt r]}]} {
	while {[gets $__fh __ln] >= 0} {
		if {[regexp {^\s*Wiring\s*:\s*([0-9]+)} $__ln -> __v]} { set __wiringleft $__v }
		if {[regexp {^(SPACING|EndOfLine|SHORT):.*Special} $__ln]} {
			incr __pgwire
			if {$__pgwire <= 20} { lappend __pgwirelist [string trim $__ln] }
		}
	}
	close $__fh
}
logPuts "### UNL STATUS ### : G0 GATE -- verifyGeometry Wiring count in the SHIPPED state = $__wiringleft (PG-related: $__pgwire, which is the gated number)"
foreach __w $__pgwirelist { logPuts "### UNL STATUS ### :   PG-related marker: $__w" }
if {$__wiringleft > 0 && $__pgwire == 0} {
	logPuts "### UNL STATUS ### : G0 GATE -- the $__wiringleft Wiring violation(s) in this cut name NO special wire or via,"
	logPuts "### UNL STATUS ### :   so no PG pass and no PG-driven re-route can move them. They are NOT gated here."
	logPuts "### UNL STATUS ### :   Read them: grep -A2 -E '^(SPACING|EndOfLine)' $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt"
}
if {$__pgwire > 0} {
	logPuts "FATAL (G0 GATE): $__pgwire PG-related spacing violation(s) in the shipped state. Every one of these is a"
	logPuts "                 SPACING marker between routed metal and something else, and on the"
	logPuts "                 2026-08-26 cut both of them came back from Calibre as real results"
	logPuts "                 (M1.S.1 at 433.415,208.145 and M2.S.1 at 553.400,176.410)."
	logPuts "                 Two causes are known and both are repaired above: a PG pass laying metal"
	logPuts "                 without clearance (grep PGCLEAR) and a NanoRoute residual hidden by the"
	logPuts "                 PG route blockages (grep PGR). Read those two before touching anything."
	logPuts "                 No collateral is emitted. Saving $DATABASE_DIR/g0repair_fail.innovus; aborting."
	logPuts "                 Sites: grep -A2 '^SPACING' $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt"
	saveDesign $DATABASE_DIR/g0repair_fail.innovus
	exit 1
}
# SECOND, INDEPENDENT OPINION ON THE SAME QUESTION.
# The gate above trusts Innovus.  pgc_census re-derives the same verdict from
# the database and the DECK, so the two instruments have to fail together to
# let a violation through.  Measured on the 2026-08-26 shipped database: 58162
# PG rectangles examined on M1 and M2, exactly two too close, and they are the
# two Calibre named out of a 1592 rulecheck deck.  It costs 47 seconds.
set __pgccen [pgc_census {VDD VSS VDD_SW} {M1 M2}]
logPuts "### UNL STATUS ### : PGCLEAR census in the SHIPPED state = $__pgccen PG rectangle(s) closer than the deck rule (must be 0)"
if {$__pgccen > 0} {
	logPuts "FATAL (PGCLEAR): $__pgccen PG rectangle(s) sit closer to separate metal than the deck allows."
	logPuts "                 Innovus did not call these Wiring violations, which means the two"
	logPuts "                 instruments disagree; the sites are printed above with their measured"
	logPuts "                 gaps and the deck rule each was judged against."
	logPuts "                 No collateral is emitted. Saving $DATABASE_DIR/pgclear_fail.innovus; aborting."
	saveDesign $DATABASE_DIR/pgclear_fail.innovus
	exit 1
}
set __g0left [llength [g0r_parse_markers $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt]]
logPuts "### UNL STATUS ### : G0 GATE -- router-vs-cell-OBS M1 merges in the SHIPPED state = $__g0left (must be 0)"
if {$__g0left > 0} {
	logPuts "FATAL (G0 GATE): $__g0left router-vs-cell-OBS M1 merge(s) survive the in-flow repair."
	logPuts "                 Each one is a REAL layout short between a signal net and a cell-internal"
	logPuts "                 node and comes back from Pegasus as an LVS SHORT. No collateral is"
	logPuts "                 emitted. Saving $DATABASE_DIR/g0repair_fail.innovus; aborting."
	logPuts "                 Sites: grep 'Blockage of Cell' $REPORT_DIR/$DESIGN_NAME.verifyGeometry.signoff.rpt"
	saveDesign $DATABASE_DIR/g0repair_fail.innovus
	exit 1
}

printStatus "verifyProcessAntenna"
verifyProcessAntenna \
    -report $REPORT_DIR/$DESIGN_NAME.verifyProcessAntenna.signoff.rpt

setDelayCalMode -SIAware false
setAnalysisMode -analysisType onChipVariation -cppr both
printStatus "timeDesign signoff"
timeDesign \
    -si \
    -signoff \
    -outdir $REPORT_DIR/$DESIGN_NAME.timeDesign.signoff.rpt

report_clock_timing \
    -type skew \
    -nworst 10 > $REPORT_DIR/$DESIGN_NAME.report_clock_timing.skew.signoff.rpt

setAnalysisMode -checkType hold -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.hold.signoff.rpt
setAnalysisMode -checkType setup -skew true
report_timing > $REPORT_DIR/$DESIGN_NAME.report_timing.setup.signoff.rpt

reportGateCount \
    -level 2 \
    -outfile $REPORT_DIR/$DESIGN_NAME.reportGateCount.signoff.rpt
summaryReport \
    -noHtml \
    -outfile $REPORT_DIR/$DESIGN_NAME.summaryReport.signoff.rpt

saveDesign $DATABASE_DIR/$DESIGN_NAME.signoff.innovus -def -netlist -rc -tcon

################################################################################
# Output files: GDS, SDF, sim netlist, ILM, LEF abstract, per-corner ETMs
################################################################################
streamOut \
    $OUTPUT_DIR/$DESIGN_NAME.gds2 \
    -libName WorkLib \
    -structureName $DESIGN_NAME \
    -stripes 1 \
    -units 1000 \
    -mode ALL \
    -mapFile ../shared/innovus2gds.map

printStatus "Writing SDF file"
write_sdf $OUTPUT_DIR/$DESIGN_NAME.sdf

printStatus "Writing verilog for Xcelium"
saveNetlist \
    $OUTPUT_DIR/$DESIGN_NAME.xsim.v \
    -excludeCellInst ANTENNA2A10TH

# ILM -- interface logic + clock interface with real post-route timing
# (secondary abstraction; the assembly flow of record is ETM+LEF).
printStatus "Writing ILM"
createInterfaceLogic \
    -hold \
    -dir $OUTPUT_DIR/$DESIGN_NAME.ilm

# LEF abstract -- pins + blockages for top-level placement/routing. The tile
# uses M7/M8 for its own power ring/stripes, so the abstract exposes them as
# PG pins (top-level stripes via down onto the tile ring).
printStatus "Writing LEF abstract"
lefOut \
    -StripePin \
    -PGpinLayers 7 8 \
    -specifyTopLayer 8 \
    $OUTPUT_DIR/$DESIGN_NAME.lef

# Per-corner ETMs (.lib) -- THE M14 recipe: do_extract_model characterizes
# only the corner whose view is active for BOTH setup and hold, so force
# each corner in turn. These feed viewdefinition_top.tcl (etm_ss in the
# max+typ library sets, etm_ff in min).
printStatus "Extracting per-corner ETMs (both-views-active recipe)"
set_analysis_view -setup [list setup_analysis_view] -hold [list setup_analysis_view]
# NOTE: -view is REQUIRED in MMMC (TAMODEL-313 otherwise -- and innovus only
# PRINTS the error without throwing, so a missing -view fails SILENTLY).
if {[catch {do_extract_model -view setup_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib} etm_err]} {
	logPuts "ETM ss extraction FAILED: $etm_err"
} else {
	logPuts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm_ss.lib"
}
set_analysis_view -setup [list hold_analysis_view] -hold [list hold_analysis_view]
if {[catch {do_extract_model -view hold_analysis_view $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib} etm_err]} {
	logPuts "ETM ff extraction FAILED: $etm_err"
} else {
	logPuts "ETM written to $OUTPUT_DIR/$DESIGN_NAME.etm_ff.lib"
}
set_analysis_view -setup [list setup_analysis_view] -hold [list hold_analysis_view]

saveDesign $DATABASE_DIR/$DESIGN_NAME.final.innovus -def -netlist -rc -tcon
toc
printStatus "hart_tile harden complete"
exit
