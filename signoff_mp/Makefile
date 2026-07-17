# =============================================================================
# signoff_mp Makefile -- command-line DRC / LVS on the digital blocks.
#
#   make drc  BLOCK=<name> [LAYOUT=<file>] [RULE=<deck>]
#   make lvs  BLOCK=<name> [LAYOUT=<file>] [NETLIST=<file.v>]
#   make ant  BLOCK=<name> [LAYOUT=<file>]           # antenna (ant25)
#   make signoff BLOCK=<name> [LAYOUT=<file>]        # drc + ant + lvs
#   make blocks                                      # list known blocks
#
# LAYOUT is format-agnostic: .gds/.gds2/.gdsii[.gz]/.oas/.oasis all work
# (ingest_layout.sh normalizes to GDS, then rebuilds the block's signoff OA
# lib through the GUARDED strmin -- the Myshkin-collision cellMap is never
# bypassed). When LAYOUT is omitted, the block's canonical P&R output from
# ../innovus/common/out/ is used. Re-ingest is skipped when the source file
# is unchanged (path+mtime stamp in <lib>/.ingest_stamp).
#
# The heavy lifting stays in the proven, per-run-isolated runners (CQ8b):
# drc.sh / lvs.sh (setsid process groups, atomic publish-back, stale-readback
# gates). This file only normalizes block names, formats, and defaults.
#
# LICENSE COURTESY: Calibre/Pegasus licenses are shared -- targets are
# serialized (.NOTPARALLEL); never run two `make signoff` in parallel either.
# Chip-scale runtimes: chipdrc ~10 min, chip LVS ~66 min at 18 harts (launch
# long LVS detached/setsid from your own shell if a session reaper may run:
# lvs.sh already re-execs setsid, but the CALLER can still be reaped).
# =============================================================================

SHELL := /bin/bash
.NOTPARALLEL:

OUT := ../innovus/common/out

# --------------------------- per-block parameter table ----------------------
# For each block: _LIB (signoff OA lib), _CELL (topcell), _GDS (default layout),
# _RULE (default DRC deck), _NETLIST/_INC/_CTL/_LABELS (LVS collateral).
# Decks resolve in drc.sh: local decks/*.rul first, then the frozen Myshkin set.

BLOCKS := hart_tile hart_tile_argus mcu mcu_argus chip_top chip_top_argus chip_top_quad

hart_tile_LIB       := hart_tile_mp
hart_tile_CELL      := hart_tile
hart_tile_GDS       := $(OUT)/hart_tile.gds2
hart_tile_RULE      := blockdrc
hart_tile_NETLIST   := pvs/hart_tile.lvs.v
hart_tile_INC       := lvs_include_tile
hart_tile_CTL       :=
hart_tile_LABELS    :=

# NB: the Argus tile's GDS topcell is "hart_tile" (same design name as the
# Castalia tile, different hardening) -- the LIB is the discriminator.
hart_tile_argus_LIB     := hart_tile_argus_signoff
hart_tile_argus_CELL    := hart_tile
hart_tile_argus_GDS     := $(OUT)/hart_tile_argus.gds2
hart_tile_argus_RULE    := blockdrc
hart_tile_argus_NETLIST := pvs/hart_tile_argus.lvs.v
hart_tile_argus_INC     := lvs_include_tile
hart_tile_argus_CTL     :=
# Same-cell-name trap at TILE level (A6's chip_top lesson): cell "hart_tile"
# makes lvs.sh default to the CASTALIA tile's lvslabels -- override to Argus's.
# Expected standalone verdict (validated 2026-07-16): rc=0, shorts EMPTY,
# bounded residual ~944:940 insts (0.09%) = the switched-rail VDD_SW
# matcher-limit class (Argus's lvslabels is chip-collateral-sized, ~70 labels
# vs the Castalia tile's ~470 which bought its 0:0). Not a defect; a full
# standalone label set would be the fix if a 0:0 tile verdict is ever needed.
hart_tile_argus_LABELS  := pvs/hart_tile_argus.lvslabels

mcu_LIB       := MCU_MP_signoff
mcu_CELL      := MCU
mcu_GDS       := $(OUT)/MCU_MP.gds2
mcu_RULE      := blockdrc
mcu_NETLIST   := pvs/MCU_full.lvs.v
mcu_INC       := lvs_include_mcu
mcu_CTL       := pvs/lvs_mcu_ctl
mcu_LABELS    :=

# Argus MCU assembly: DRC-supported; no standalone LVS netlist has ever been
# cut for it (chip-level LVS covers it) -- pass NETLIST= explicitly if needed.
# NB: BOTH assemblies' GDS topcell is "MCU" (the Myshkin-collision heartland --
# the guarded strmin's cellMap is what makes this safe); LIB discriminates.
mcu_argus_LIB     := MCU_ARGUS_signoff
mcu_argus_CELL    := MCU
mcu_argus_GDS     := $(OUT)/MCU_ARGUS.gds2
mcu_argus_RULE    := blockdrc
mcu_argus_NETLIST :=
mcu_argus_INC     := lvs_include_mcu
mcu_argus_CTL     :=
mcu_argus_LABELS  :=

chip_top_LIB       := chip_top_signoff
chip_top_CELL      := chip_top
chip_top_GDS       := $(OUT)/chip_top.gds2
chip_top_RULE      := chipdrc
chip_top_NETLIST   := pvs/chip_top_full.lvs.v
chip_top_INC       := lvs_include_chip
chip_top_CTL       := pvs/lvs_chip_ctl
chip_top_LABELS    :=

# Argus chip: topcell is ALSO "chip_top" (distinct only by lib) -> needs its
# own lvslabels (A6 lesson) and the A7-cut netlist.
chip_top_argus_LIB     := chip_argus_a7_signoff
chip_top_argus_CELL    := chip_top
chip_top_argus_GDS     := $(OUT)/chip_top_argus.gds2
chip_top_argus_RULE    := chipdrc
chip_top_argus_NETLIST := pvs/chip_top_argus_a7_full.lvs.v
chip_top_argus_INC     := lvs_include_chip
chip_top_argus_CTL     := pvs/lvs_chip_argus_ctl
chip_top_argus_LABELS  := pvs/chip_top_argus_a7.lvslabels

chip_top_quad_LIB     := chip_top_quad_signoff
chip_top_quad_CELL    := chip_top_quad
chip_top_quad_GDS     := $(OUT)/chip_top_quad.gds2
chip_top_quad_RULE    := chipdrc
chip_top_quad_NETLIST := pvs/chip_top_quad_full.lvs.v
chip_top_quad_INC     := lvs_include_chip
chip_top_quad_CTL     := pvs/lvs_chip_quad_ctl
chip_top_quad_LABELS  :=

# ------------------------------ resolution -----------------------------------
ifdef BLOCK
ifeq ($(filter $(BLOCK),$(BLOCKS)),)
$(error unknown BLOCK '$(BLOCK)' -- run 'make blocks' for the list)
endif
LIB     := $($(BLOCK)_LIB)
CELL    := $($(BLOCK)_CELL)
LAYOUT  ?= $($(BLOCK)_GDS)
RULE    ?= $($(BLOCK)_RULE)
NETLIST ?= $($(BLOCK)_NETLIST)
INC     := $($(BLOCK)_INC)
CTL     := $($(BLOCK)_CTL)
LABELS  := $($(BLOCK)_LABELS)
endif

define NEED_BLOCK
	@if [ -z "$(BLOCK)" ]; then echo "usage: make $@ BLOCK=<name>  (make blocks for the list)"; exit 2; fi
endef

# ------------------------------- targets --------------------------------------
.PHONY: help blocks check-env check-netlist ingest drc ant lvs signoff

check-env:
	@for t in strmin calibre pegasus calibredrv; do \
	  command -v $$t > /dev/null || { echo "$$t not on PATH -- source ~/vestarv/cdspaths.sh first"; exit 2; }; \
	done

check-netlist:
	$(NEED_BLOCK)
	@if [ -z "$(NETLIST)" ]; then \
	  echo "lvs: BLOCK=$(BLOCK) has no default LVS netlist -- pass NETLIST=<file.lvs.v>"; \
	  echo "     (REMEMBER the invariant: any re-P&R invalidates saved LVS netlists;"; \
	  echo "      regenerate from the cut's own post-route DB, see a7/regen_lvs_netlist2.tcl)"; \
	  exit 2; \
	fi

help:
	@echo "signoff_mp command-line DRC/LVS (format-agnostic: gds/gds2/gdsii[.gz]/oas/oasis)"
	@echo ""
	@echo "  make drc     BLOCK=<name> [LAYOUT=<file>] [RULE=blockdrc|chipdrc|celldrc|...]"
	@echo "  make ant     BLOCK=<name> [LAYOUT=<file>]        antenna check (ant25)"
	@echo "  make lvs     BLOCK=<name> [LAYOUT=<file>] [NETLIST=<lvs.v>]"
	@echo "  make signoff BLOCK=<name> [LAYOUT=<file>]        drc + ant + lvs"
	@echo "  make ingest  BLOCK=<name> [LAYOUT=<file>]        (re)build the OA lib only"
	@echo "  make blocks                                      list blocks + defaults"
	@echo ""
	@echo "Results: calibre/<lib>/<cell>/results/<rule>.rpt and pvs/<lib>/<cell>/*.rep"
	@echo "Env: source ~/vestarv/cdspaths.sh first. Licenses shared: one heavy run at a time."

blocks:
	@printf "%-16s %-24s %-14s %-10s %s\n" "BLOCK" "LIB" "CELL" "DRC RULE" "DEFAULT LAYOUT"; \
	for b in $(BLOCKS); do \
	  case $$b in \
	    hart_tile)       printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(hart_tile_LIB)" "$(hart_tile_CELL)" "$(hart_tile_RULE)" "$(hart_tile_GDS)";; \
	    hart_tile_argus) printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(hart_tile_argus_LIB)" "$(hart_tile_argus_CELL)" "$(hart_tile_argus_RULE)" "$(hart_tile_argus_GDS)";; \
	    mcu)             printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_LIB)" "$(mcu_CELL)" "$(mcu_RULE)" "$(mcu_GDS)";; \
	    mcu_argus)       printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_argus_LIB)" "$(mcu_argus_CELL)" "$(mcu_argus_RULE)" "$(mcu_argus_GDS)";; \
	    chip_top)        printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_LIB)" "$(chip_top_CELL)" "$(chip_top_RULE)" "$(chip_top_GDS)";; \
	    chip_top_argus)  printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_argus_LIB)" "$(chip_top_argus_CELL)" "$(chip_top_argus_RULE)" "$(chip_top_argus_GDS)";; \
	    chip_top_quad)   printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_quad_LIB)" "$(chip_top_quad_CELL)" "$(chip_top_quad_RULE)" "$(chip_top_quad_GDS)";; \
	  esac; \
	done

ingest: check-env
	$(NEED_BLOCK)
	./ingest_layout.sh $(LIB) $(CELL) $(LAYOUT)

drc: ingest
	./drc.sh $(LIB) $(CELL) $(RULE)

ant: ingest
	./drc.sh $(LIB) $(CELL) ant25

lvs: check-netlist ingest
	@if [ -n "$(LABELS)" ]; then \
	  LVSLABELS=$(LABELS) ./lvs.sh $(LIB) $(CELL) $(NETLIST) $(INC) $(CTL); \
	else \
	  ./lvs.sh $(LIB) $(CELL) $(NETLIST) $(INC) $(CTL); \
	fi

signoff: drc ant lvs
	@echo "signoff: BLOCK=$(BLOCK) drc+ant+lvs complete -- reports under calibre/$(LIB)/$(CELL)/results and pvs/$(LIB)/$(CELL)"
