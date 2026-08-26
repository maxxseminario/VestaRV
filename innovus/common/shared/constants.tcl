################################################################################
# Library and Directory Constants -- MCU_MP physical flow (M14, tsmc65nm)
#
# Derived from the frozen Myshkin ~/vestarv/innovus/tcl/constants.tcl. The
# Myshkin scripts referenced ../ip and ../ic relative to the run dir; those
# siblings no longer exist under ~/vestarv -- the real IP/analog-abstract
# source tree is /home/mseminario2/chips/myshkin/{ip,ic} (absolute here).
################################################################################

set KIT_DIR         "/opt/design_kits/TSMC65-PDK"
set STD_CELL_DIR    "/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10"
set IO_PAD_DIR      "/opt/design_kits/TSMC65-IP/tsmc/digital/Back_End/lef/tpfn65gpgv2od3_200c/mt_2/9lm/lef"
set QXTECH_FILE     "/opt/design_kits/TSMC65-IP/arm/sc10/hvt/aci/sc-ad10/voltagestorm/tsmc65_hvt_sc_adv10_9lm_2thick.cl/icecaps.tch"

# Per-block since the 2026-07-27 reorg: runs execute with CWD = the block dir,
# so the repo root is 3 up and genus is itself per-block. Every consumer writes
# "$GENUS_DIR/out/...", so this must be the genus BLOCK dir; block dir name ==
# genus dir name for all 9 consumers (hart_tile, hart_tile_argus, MCU_MP,
# MCU_WOUND, MCU_DP, MCU_ARGUS — audited 2026-07-29). The 5 chip-top flows
# stage in/*.sdc and reference no $GENUS_DIR (a consumer added there would
# fail loudly at init on the nonexistent genus/<chip-top> dir).
set GENUS_DIR    "../../../genus/[file tail [pwd]]"
set IC_DIR       "/home/mseminario2/chips/myshkin/ic"
set HDL_DIR      "../../../hdl"
set SCRIPT_DIR   tcl
set INPUT_DIR    in
set IP_DIR       "/home/mseminario2/chips/myshkin/ip"
set OUTPUT_DIR   out
set LOG_DIR      log
set TMP_DIR      "../.tmp"   ;# DEAD from block CWDs; zero consumers (2026-07-29 audit) — kept for safety
set REPORT_DIR   rpt
set DATABASE_DIR dbs

# Standard cell library constants
set PIN_GRID_SPACING_X 0.20
set PIN_GRID_SPACING_Y 0.20
set STD_CELL_HEIGHT    2.00

################################################################################
# NARROW-RISER VIA EXTENT CAP -- the PG via-generation default that closes the
# foundry wide-metal rules (M6.S.4 / M7.S.4) at source.
#
# THE OBJECT.  A narrow M2 secondary strap that crosses a 10 um PG ring band
# gets a STACKED via whose landing pad is the EXACT CROSSOVER RECTANGLE of the
# two wires, so the pad is 0.30 x 10.00 on every layer from M3 to M8.  On M6 and
# M7 that pad is the ONLY metal the riser has, and it faces the wide PG plates
# that flank the band across a channel 2.00 um wide.  The wide-metal rule is
# NET-BLIND and wants 1.50 um of space, so no width and no position for that
# riser satisfies it: 1.50 + w + 1.50 needs 3.00 um of channel at any width.
#
# WHY NOT LESS METAL AROUND THE CUTS.  The rule has four gates and enclosure
# only moves one of them.  Measured against signoff_mp/decks/blockdrc.rul
# (CLN65S_9M_6X1Z1U.26_2a) and tsmc_cln65_a10_6X1Z_tech.lef, which agree to the
# digit: VIA6 needs 0.04 um of M6 on two opposite sides (VIA6.EN.2, LEF
# ENCLOSURE BELOW 0.04 0.00) so the M6 pad can shrink 0.30 -> 0.18 and the M6
# gap improves 0.900 -> 0.960 against a 1.500 requirement, and VIA7 needs
# 0.02 um of M7 (VIA7.EN.1, LEF ENCLOSURE BELOW 0.08 0.02) which is EXACTLY what
# the M7 pad already carries.  Enclosure closes neither layer.
#
# WHAT DOES CLOSE IT.  The rule only fires when the parallel run exceeds
# M6_S_4_L + GRID = 4.505 um, and the run here is the pad's own height.  Cap the
# via extent below that and the rule stops seeing the object.  MEASURED on a
# synthetic Calibre run against that same deck: a 0.30 x h bar 0.900 um from a
# 5 um plate fires at h = 4.510 and is clean at h = 4.500, 4.400, 4.000; two
# 4.000 um bars split by a gap as small as 0.300 um are also clean, so the split
# pieces are measured separately rather than accumulated.
#
# SCOPE.  This is a default for the NARROW-STRAP passes only, not a global via
# mode.  The cap buys DRC only where the via pad IS the metal; on the main mesh
# the pad is buried inside a 5 or 10 um stripe, where capping it changes no
# polygon any rule can see and only removes cuts.  It is also free in
# electromigration terms here and not there: from the tech LEF's own numbers
# (VIA1..VIA6 1.5 ohm/cut, VIA7 0.22, M2 0.14 ohm/sq) a riser's whole via stack
# is 0.19 ohm uncapped and 0.25 ohm capped against 46.7 ohm for 100 um of the
# 0.30 um M2 strap it feeds, whereas on a 10 um PG stripe the via array IS the
# bottleneck.
#
# THRESHOLD 4.5, AND A RAISED THRESHOLD WAS TRIED AND FAILED.  4.5 is the rule's
# own wide-metal trigger, so every crossover the rule can see gets capped.  A
# narrower variant at 6.0 -- covering only the 10 and 14 um PG-band crossings and
# leaving the ~950 five-micron stripe crossings untouched, to shrink the
# perturbation to the strap fabric -- was tried and the run FATALed at the PG4/F2b
# repeater link gate ("no clear link y to any main strap column for repeater
# pgaorep_2, 14 candidates tried").  The flow's own gate caught it; the value is
# back at 4.5, which completes.
#
# {threshold step offset height} for setAddStripeMode -split_long_via: split any
# crossover via longer than 4.5 um into 2.6 um pieces on a 3.3 um pitch, placed
# symmetrically (offset -1).  A 10 um band crossing becomes three pieces of
# 2.600 / 2.650 / 3.000 -- the engine EXTENDS THE LAST PIECE to the end of the
# crossover, which is why the height is 2.6 and not 4.0 (measured: {4.5 5.0 -1
# 4.0} produced a 4.500 um last piece, one grid step from the 4.505 firing
# point).
################################################################################
set RISER_VIA_SPLIT	{4.5 3.3 -1 2.6}
