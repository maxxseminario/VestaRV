# =============================================================================
# Genus synthesis targets (batch, no GUI) — PER-BLOCK layout (2026-07-27).
#
# Each block owns a directory:  genus/<BLOCK>/{tcl,out,rpt,log,fv}
# Shared generated inputs live in genus/common/in (INPUT_DIR=../common/in in
# every block tcl); old flat-layout session junk is in genus/common/attic.
# Runs execute with CWD = genus/<BLOCK>/, so inside a block everything is
# still tcl/ out/ rpt/ log/, and repo refs are ../../hdl, ../../ic, ../../ip.
# Cross-block reads are explicit (e.g. MCU_WOUND/tcl reads
# ../hart_tile/out/hart_tile.genus.v).
#
#   make MCU_MP.genus    synthesize the 4-hart MCU_MP tree  (MCU_MP/tcl/MCU_MP.genus.tcl)
#   make MCU.genus       synthesize the single-core Myshkin tree
#   make MCU_WOUND.genus       FLAT wound SoC (gate-sim netlist; harts inlined)
#   make MCU_WOUND_hier.genus  HIERARCHICAL wound SoC top for block P&R -- the
#                              four harts stay `hart_tile` instances bound to the
#                              hardened tile LEF/ETM downstream. Feeds
#                              innovus/common/MCU_WOUND/prep_top_netlist_wound.sh ->
#                              in/MCU_WOUND_hier.pnr.v + MCU_WOUND.innovus.tcl.
#                              REQUIRES hart_tile/out/hart_tile.genus.v
#                              (make hart_tile.genus).
#
# Each run (inside its block dir):
#   log/<top>.log, log/<top>.cmd   genus session logs (-overwrite: no .log1 spam)
#   rpt/<top>.genus.*.rpt          area/gates/timing/power/clk-gating/rules
#   out/<top>.genus.{v,g,sdc,sdf}  netlist + db + constraints + timing
#
# cdspaths.sh is sourced by the recipe, so a plain shell works:
#   cd ~/vestarv/genus && make MCU_MP.genus
#
# Runtime: single-core MCU took ~13 min; MCU_MP (4 harts, high effort) longer.
# Progress: tail -f <BLOCK>/log/<top>.log
# =============================================================================

SHELL := /bin/bash
CDSPATHS := $(abspath ..)/cdspaths.sh

# target name -> block directory (variants collapse onto their block)
block_of = $(firstword \
  $(if $(filter MCU_hart%,$(1)),MCU_hart) \
  $(if $(filter MCU_PENTA%,$(1)),MCU_PENTA) \
  $(if $(filter orch_tile%,$(1)),orch_tile) \
  $(if $(filter MCU_WOUND%,$(1)),MCU_WOUND) \
  $(if $(filter MCU_MP%,$(1)),MCU_MP) \
  $(if $(filter MCU_DP%,$(1)),MCU_DP) \
  $(if $(filter MCU_ARGUS%,$(1)),MCU_ARGUS) \
  $(if $(filter hart_tile_argus%,$(1)),hart_tile_argus) \
  $(if $(filter hart_tile%,$(1)),hart_tile) \
  $(if $(filter DMA%,$(1)),DMA) \
  $(if $(filter MCU%,$(1)),MCU) \
  $(1))

TARGETS := MCU_MP.genus MCU.genus MCU_WOUND.genus MCU_WOUND_hier.genus \
           MCU_DP.genus MCU_DP_hier.genus MCU_DP_hier_s3.genus \
           hart_tile.genus MCU_MP_hier.genus hart_tile_argus.genus \
           MCU_ARGUS_hier.genus QSPI.genus I3C.genus NFC.genus RTC.genus \
           PWM.genus OneWire.genus I2CTarget.genus NPU.genus EVFAB.genus \
           orch_tile.genus MCU_PENTA_hier.genus MCU_hart_hier.genus

.PHONY: help $(TARGETS) DMA_nch4.genus DMA_nch2.genus

help:
	@echo "Targets: $(TARGETS) DMA_nch4.genus DMA_nch2.genus"
	@echo "Layout : genus/<BLOCK>/{tcl,out,rpt,log,fv}; shared inputs genus/common/in"

# HARD-FAIL WRAPPER (2026-08-16), the genus sibling of the PG4 wrapper in
# innovus/common/Makefile, and added for a failure that actually shipped a wrong
# answer here: a tcl error (`set_false_path` on a pin whose instance path had
# moved, TUI-61) left genus sitting at an interactive prompt, and it STILL EXITED
# 0. make reported success, the stale out/ and rpt/ from the PREVIOUS run were
# still on disk with their old timestamps, and reading them looked exactly like
# "the change had no effect" -- a plausible, completely wrong conclusion.
# The log is the only place the failure exists, so the log is what is checked.
# THE TEST IS "Encountered problems processing file" AND NOTHING ELSE. A first
# version also failed on any `Error : ... [TUI-|VHDL-|HDL-]` line, and that was
# too blunt: MCU_PENTA_hier's black-box census probes `get_db ... .is_black_box`,
# which this genus does not recognise, so it logs `Error : Unrecognized
# attribute. [TUI-183]` and carries on to a Normal exit with every output
# written. Failing that build taught exactly the wrong lesson -- that the gate
# cries wolf. "Encountered problems processing file" is genus's own marker for
# "the tcl aborted", which is the condition that leaves out/ and rpt/ stale.
$(TARGETS):
	@blk=$(call block_of,$(basename $@)); \
	mkdir -p $$blk/log $$blk/out $$blk/rpt; \
	source $(CDSPATHS) && cd $$blk && \
	genus -no_gui -overwrite -log log/$(basename $@) -files tcl/$@.tcl
	@blk=$(call block_of,$(basename $@)); \
	if grep -qE "Encountered problems processing file" $$blk/log/$(basename $@).log; then \
		echo "FATAL (genus wrapper): tcl errors in $$blk/log/$(basename $@).log -- genus exits 0 on these, so out/ and rpt/ are STALE, not new:"; \
		grep -nE "Encountered problems processing file|^Error +: " $$blk/log/$(basename $@).log | head -5; \
		exit 1; \
	fi

# DMA -- ONE tcl (DMA/tcl/DMA.genus.tcl), TWO shapes selected by DMA_NCH
# (D6 dual-shape). Each shape's netlist module is named plain "DMA"; the FILE
# (DMA/out/DMA_nch{4,2}.genus.v) is the discriminator -- one bound per mixed-
# binding gate run in xcelium/DMA/genus/.
DMA_nch4.genus:
	@mkdir -p DMA/log DMA/out DMA/rpt; \
	source $(CDSPATHS) && cd DMA && \
	DMA_NCH=4 genus -no_gui -overwrite -log log/$(basename $@) -files tcl/DMA.genus.tcl

DMA_nch2.genus:
	@mkdir -p DMA/log DMA/out DMA/rpt; \
	source $(CDSPATHS) && cd DMA && \
	DMA_NCH=2 genus -no_gui -overwrite -log log/$(basename $@) -files tcl/DMA.genus.tcl
