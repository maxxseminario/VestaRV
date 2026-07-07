# =============================================================================
# Genus synthesis targets (batch, no GUI).
#
#   make MCU_MP.genus    synthesize the 4-hart MCU_MP tree  (tcl/MCU_MP.genus.tcl)
#   make MCU.genus       synthesize the single-core Myshkin tree (tcl/MCU.genus.tcl)
#
# Each run:
#   log/<top>.log, log/<top>.cmd   genus session logs (-overwrite: no .log1 spam)
#   rpt/<top>.genus.*.rpt          area/gates/timing/power/clk-gating/rules
#   out/<top>.genus.{v,g,sdc,sdf}  netlist + db + constraints + timing
#
# cdspaths.sh is sourced by the recipe, so a plain shell works:
#   cd ~/vestarv/genus && make MCU_MP.genus
#
# Runtime: single-core MCU took ~13 min; MCU_MP (4 harts, high effort) longer.
# Progress: tail -f log/MCU_MP.log
# =============================================================================

SHELL := /bin/bash
CDSPATHS := $(abspath ..)/cdspaths.sh

.PHONY: help MCU_MP.genus MCU.genus hart_tile.genus MCU_MP_hier.genus

help:
	@echo "Targets: MCU_MP.genus | MCU.genus | hart_tile.genus | MCU_MP_hier.genus   (see comments in this Makefile)"

MCU_MP.genus MCU.genus hart_tile.genus MCU_MP_hier.genus:
	@mkdir -p log out rpt
	source $(CDSPATHS) && genus -no_gui -overwrite -log log/$(basename $@) -files tcl/$@.tcl
