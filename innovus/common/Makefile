# =============================================================================
# Innovus P&R targets -- multi-core (Castalia + Argus) flows. Batch, no GUI.
# PER-BLOCK layout (2026-07-27): each block owns innovus/common/<BLOCK>/
# {tcl,in,out,rpt,log,dbs,timingReports}; runs execute with CWD = the block
# dir, so inside a block everything is still tcl/ in/ out/ rpt/ log/ dbs/.
# Shared data (constants.tcl, innovus2gds.map, streamOut.map,
# analog_abstracts_dummy.lib) lives in innovus/common/shared/; pre-reorg
# flat-layout session junk is in innovus/common/attic/.
# Repo refs from inside a block are ../../../ (hdl, genus, std_cells, cpf).
# Cross-block reads are explicit (e.g. chip flows read
# ../hart_tile/out/hart_tile.lef, ../MCU_WOUND/in/MCU_WOUND_hier.pnr.v).
#
#   make hart_tile.innovus   harden ONE hart_tile (hart_tile/tcl/...)
#                            needs ../../../genus/hart_tile/out/hart_tile.genus.{v,sdc}
#   make MCU_MP.innovus      top-level assembly: 4x tile (ILM/LEF) + control
#                            plane + CTS; needs the tile outputs +
#                            ../../../genus/MCU_MP/out/MCU_MP_hier.genus.{v,sdc}
#   make MCU_WOUND.innovus   wound-patch SoC block P&R (2689x1700 frame, 4x tile
#                            LEF/ETM + wound fabric). PREREQUISITES, in order:
#                              1. genus: make MCU_WOUND_hier.genus (Stage I)
#                              2. MCU_WOUND/prep_top_netlist_wound.sh
#   make chip_top_wound_quad.innovus
#                            wound-patch SoC CONNECTED chip-top on the
#                            QUADRANT-SYMMETRIC Castalia-Quad floorplan (four
#                            corner tiles, wound control plane in the center
#                            band; THE tape-out floorplan -- the row-layout
#                            chip_top_wound flow was deleted 2026-07-27, never
#                            revert). FLAT run, symmetric 3x3 mm die
#                            (-155,-155)-(2845,2845), 2690x2690 interior.
#                            Carries the three cq8a floorplan-stage DRC fixes
#                            (M7 stripe phase +9.0 um, 0.9 um PG band snaps,
#                            irq_gf halo 20 um). PREREQUISITES, in order:
#                              1. genus: make MCU_WOUND_hier.genus
#                              2. MCU_WOUND/prep_top_netlist_wound.sh
#                                 (-> ../MCU_WOUND/in/MCU_WOUND_hier.pnr.v,
#                                 consumed unchanged -- NO separate block P&R)
#                              3. chip_top_wound_quad/gen_chip_top_wound_quad_sdc.sh
#                                 -> in/chip_top_wound_quad.sdc
#                            Inputs in/chip_top_wound_quad.{v,sdc} +
#                            ../MCU_WOUND/in/MCU_WOUND_hier.pnr.v +
#                            ../hart_tile/out/hart_tile.lef
#                            (tcl/chip_top_wound_quad.innovus.tcl,
#                             tcl/chip_top_wound_padlists.tcl,
#                             tcl/viewdefinition_chip_wound_quad.tcl).
#                            AFTER the run: chip_top_wound_quad/
#                            prep_top_netlist_wound_quad.sh
#                            -> out/chip_top_wound_quad.xsim.clean.v
#
# Add ".gui" to any target to run the SAME flow with the Innovus window up and
# keep it open after (the trailing `exit` is stripped to a temp copy):
#   make hart_tile.innovus.gui   watch the tile harden come up / inspect it
# The plain (no .gui) targets stay headless -- use those for long unattended
# signoff runs so no GUI/license is left dangling.
#
# Each run (inside its block dir): log/<name>.log, rpt/<name>.*, out/<name>.*,
# dbs/<name>.*.innovus, timingReports/ (implicit optDesign reports -- now
# per-block, so the design-cell-name clobber trap is gone).
# The frozen Myshkin tape-out flow lives in ../myshkin -- NEVER touch it.
# =============================================================================

SHELL := /bin/bash
# Blocks are one level below innovus/common/, so the repo root is three levels
# up from a run's CWD; this Makefile itself sits at innovus/common/.
CDSPATHS := $(abspath ../..)/cdspaths.sh

# target name -> block directory
blk_hart_tile.innovus           := hart_tile
blk_hart_tile_argus.innovus     := hart_tile_argus
blk_MCU_MP.innovus              := MCU_MP
blk_MCU_DP.innovus              := MCU_DP
blk_MCU_WOUND.innovus           := MCU_WOUND
blk_MCU_ARGUS.innovus           := MCU_ARGUS
blk_chip_top_quad.innovus       := chip_top_quad
blk_chip_top_dp.innovus         := chip_top_dp
blk_chip_top_wound_quad.innovus := chip_top_wound_quad
blk_chip_top_argus.innovus      := chip_top_argus
# MCU_castalia = chip_top_wound_quad renamed by user directive (2026-07-28).
# Despite the MCU_ prefix this is a FLAT CHIP run WITH the LQFP-100 pad ring,
# not a block assembly like MCU_MP/MCU_WOUND -- see signoff_mp/Makefile.
blk_MCU_castalia.innovus        := MCU_castalia
# CP4a (Castalia-Penta): MCU_castalia + a FIFTH, SOFT hart (the always-on
# orchestrator) in the centre band. Same flat-chip-with-pad-ring shape as
# MCU_castalia. SCAFFOLD ONLY as of CP4a -- the hart4 floorplan (TCM placement
# + region + CTS + PG) is marked `# CP4b TODO` inside its tcl and the run is
# NOT expected to be correct until CP4b fills those in. PREREQUISITES:
#   1. genus: make orch_tile.genus && genus/orch_tile/rename_orch_modules.sh
#   2. genus: make MCU_PENTA_hier.genus
#   3. MCU_castalia_penta/prep_top_netlist_penta.sh
#   4. MCU_castalia_penta/gen_MCU_castalia_penta_sdc.sh
blk_MCU_castalia_penta.innovus  := MCU_castalia_penta
# MCU_hart (2026-08-24): the SINGLE-HART block assembly -- one hardened
# hart_tile macro, no pad ring.  Built as a small vehicle to chase the MCU/chip
# LVS mismatch (the 2026-08-18 penta verdict is a TOP-CELL PORT mismatch, so a
# single-hart top reproduces the class at a fraction of the cost).
# THE FLOORPLAN IS DERIVED at run time from the staged config's macro
# inventory: read the ### UNL STATUS ### block near the top of the log for the
# die size and the macro placement before letting the run reach
# place_opt_design.  PREREQUISITES, in order:
#   1. stage MCU.vhd/MemoryMap.vhd into genus/common/in/hart_hdl/
#   2. genus: make MCU_hart_hier.genus
#   3. MCU_hart/prep_top_netlist_hart.sh
blk_MCU_hart.innovus            := MCU_hart

TARGETS := hart_tile.innovus MCU_MP.innovus MCU_DP.innovus MCU_WOUND.innovus \
           chip_top_quad.innovus chip_top_dp.innovus chip_top_wound_quad.innovus \
           hart_tile_argus.innovus MCU_ARGUS.innovus chip_top_argus.innovus \
           MCU_castalia.innovus MCU_castalia_penta.innovus MCU_hart.innovus

.PHONY: help $(TARGETS)

help:
	@echo "Targets: $(TARGETS)  (append .gui to see the window)"
	@echo "Layout : innovus/common/<BLOCK>/{tcl,in,out,rpt,log,dbs,timingReports}"

# PG4/PG2-F1 wrapper hard-fail (extends the M17 zero-switches precedent):
# the four message IDs below are the exact silent-failure chain that shipped
# a sourceless VDD_SW three times (GNC never bound pins / sroute routed
# nothing) -- Innovus prints them, returns rc=0, and tcl catch never fires,
# so the LOG is the only place they exist. Scoped to the same target list as
# the pre-reorg Makefile (the Castalia-line + Argus flows; the quad chip
# flows were never in the list).
$(TARGETS):
	@blk=$(blk_$@); [ -n "$$blk" ] || { echo "no block mapping for $@"; exit 1; }; \
	mkdir -p $$blk/log $$blk/out $$blk/rpt $$blk/dbs; \
	( source $(CDSPATHS) && cd $$blk && \
	  innovus -no_gui -batch -overwrite -log log/$(basename $@) -files tcl/$@.tcl )
	@case "$@" in hart_tile.innovus|MCU_MP.innovus|MCU_DP.innovus|MCU_WOUND.innovus|chip_top_dp.innovus|hart_tile_argus.innovus|MCU_ARGUS.innovus|MCU_hart.innovus) \
		if grep -nE "IMPDB-122[13]|IMPSR-(503|1253)" $(blk_$@)/log/$(basename $@).log; then \
			echo "FATAL (PG4 wrapper): PG-hookup errors in $(blk_$@)/log/$(basename $@).log -- PG2-F1 class"; exit 1; \
		fi;; esac
# TCL-ERROR WRAPPER (2026-08-25).  WITHOUT `-batch` ABOVE, a tcl error does not
# fail the run -- Innovus prints IMPSYT-6692/6693 and DROPS TO AN INTERACTIVE
# PROMPT, where it sits forever.  `make` never returns and the run looks like a
# slow one.  Measured: a one-word typo (an undeclared `global` in a proc) hung a
# 10-minute tile harden for 22 minutes before anyone looked, and the tell was a
# single line 2 MB up the console.  `-batch` turns that into a clean non-zero
# exit; this grep names it in the log so the cause is not a needle hunt.
	@case "$@" in hart_tile.innovus|MCU_MP.innovus|MCU_DP.innovus|MCU_WOUND.innovus|chip_top_dp.innovus|hart_tile_argus.innovus|MCU_ARGUS.innovus|MCU_hart.innovus) \
		if grep -nE "IMPSYT-669[23]" $(blk_$@)/log/$(basename $@).log; then \
			echo "FATAL (tcl wrapper): script error in $(blk_$@)/tcl/$@.tcl -- out/ and rpt/ are STALE, not new"; exit 1; \
		fi;; esac

# GUI variant: same script minus the trailing `exit`, run WITH the window.
%.innovus.gui:
	@blk=$(blk_$*.innovus); [ -n "$$blk" ] || { echo "no block mapping for $*"; exit 1; }; \
	mkdir -p $$blk/log $$blk/out $$blk/rpt $$blk/dbs $$blk/.tmp; \
	sed '/^[[:space:]]*exit[[:space:]]*$$/d' $$blk/tcl/$*.innovus.tcl > $$blk/.tmp/$*.innovus.gui.tcl; \
	source $(CDSPATHS) && cd $$blk && \
	innovus -overwrite -log log/$*.innovus.gui -files .tmp/$*.innovus.gui.tcl
