# =============================================================================
# Innovus P&R targets -- MCU_MP physical flow (M14). Batch, no GUI.
#
#   make hart_tile.innovus   harden ONE hart_tile (tcl/hart_tile.innovus.tcl)
#                            needs ../genus/out/hart_tile.genus.{v,sdc}
#   make MCU_MP.innovus      top-level assembly: 4x tile (ILM/LEF) + control
#                            plane + CTS (tcl/MCU_MP.innovus.tcl)
#                            needs the tile outputs + ../genus/out/MCU_MP_hier.genus.{v,sdc}
#   make chip_top.innovus    M15 pad-ring floorplan PROTOTYPE (geometry only):
#                            tphn pad ring around a reserved core area on a
#                            3x3 mm die (tcl/chip_top.innovus.tcl). No core
#                            netlist / CTS / route -- inputs in/chip_top.v only.
#
# Each run: log/<name>.log, rpt/<name>.*, out/<name>.*, dbs/<name>.*.innovus
# The frozen Myshkin tape-out flow lives in ../innovus -- NEVER touch it.
# =============================================================================

SHELL := /bin/bash
CDSPATHS := $(abspath ..)/cdspaths.sh

.PHONY: help hart_tile.innovus MCU_MP.innovus chip_top.innovus

help:
	@echo "Targets: hart_tile.innovus | MCU_MP.innovus | chip_top.innovus   (see comments in this Makefile)"

hart_tile.innovus MCU_MP.innovus chip_top.innovus:
	@mkdir -p log out rpt dbs
	source $(CDSPATHS) && innovus -no_gui -overwrite -log log/$(basename $@) -files tcl/$@.tcl
