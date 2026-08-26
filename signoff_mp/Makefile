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
# ../innovus/common/<BLOCK>/out/ is used. Re-ingest is skipped when the source file
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

# per-block layout (2026-07-27): $(INN)/<BLOCK>/{out,dbs,...}
INN := ../innovus/common

# --------------------------- per-block parameter table ----------------------
# For each block: _LIB (signoff OA lib), _CELL (topcell), _GDS (default layout),
# _RULE (default DRC deck), _NETLIST/_INC/_CTL/_LABELS (LVS collateral).
# Decks resolve in drc.sh: local decks/*.rul first, then the frozen Myshkin set.

BLOCKS := hart_tile hart_tile_argus mcu mcu_dp mcu_wound mcu_argus chip_top_dp chip_top_wound_quad chip_top_argus chip_top_quad mcu_castalia mcu_castalia_penta mcu_hart
# chip_top + chip_top_wound REMOVED 2026-07-27: row-layout Castalia flows deleted, never revert

hart_tile_LIB       := hart_tile_mp
hart_tile_CELL      := hart_tile
hart_tile_GDS       := $(INN)/hart_tile/out/hart_tile.gds2
hart_tile_RULE      := blockdrc
hart_tile_NETLIST   := pvs/hart_tile.lvs.v
hart_tile_INC       := lvs_include_tile
# CTL IS MANDATORY FOR THIS BLOCK (2026-08-25) -- it is not an option.
# pvs/lvs_tile_ctl declares GDS layer 231 as a NET-text-only layer
# (text_layer + attach metal1, deliberately NOT port -text_layer), and
# tcl/hart_tile_lvs_netlist.tcl emits the 407 VDD_SW: virtual-connect texts on
# that layer so they name the internal switched rail WITHOUT also declaring a
# phantom top-cell VDD_SW port.  It also normalises the layout pin text bus-bit
# delimiters [n] -> <n> to match the rewrite lvs.sh already applies to the CDL.
# Run this block WITHOUT the control file and the 407 texts land on a layer the
# TSMC deck has never heard of: no virtual connect, and FIND_SHORTS goes
# text-blind -- silently, with an empty shorts file that proves nothing.
hart_tile_CTL       := pvs/lvs_tile_ctl
hart_tile_LABELS    :=

# NB: the Argus tile's GDS topcell is "hart_tile" (same design name as the
# Castalia tile, different hardening) -- the LIB is the discriminator.
hart_tile_argus_LIB     := hart_tile_argus_signoff
hart_tile_argus_CELL    := hart_tile
hart_tile_argus_GDS     := $(INN)/hart_tile_argus/out/hart_tile_argus.gds2
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
mcu_GDS       := $(INN)/MCU_MP/out/MCU_MP.gds2
mcu_RULE      := blockdrc
mcu_NETLIST   := pvs/MCU_full.lvs.v
mcu_INC       := lvs_include_mcu
mcu_CTL       := pvs/lvs_mcu_ctl
mcu_LABELS    :=

# CastaliaDP respin assembly (Stage F2a, 2026-07-21): same cell name "MCU" as
# the other two assemblies (LIB discriminates; guarded strmin cellMap makes the
# Myshkin collision safe). LABELS empty = the shared cell-MCU default, which is
# CORRECT here (same design/ports as the Castalia assembly -- unlike the Argus
# tile-labels trap). NETLIST is cut from THIS cut's own DB (A7 rule) via the
# a7/regen recipe before any `make lvs BLOCK=mcu_dp`.
mcu_dp_LIB       := MCU_DP_signoff
mcu_dp_CELL      := MCU
mcu_dp_GDS       := $(INN)/MCU_DP/out/MCU_DP.gds2
mcu_dp_RULE      := blockdrc
mcu_dp_NETLIST   := pvs/MCU_DP_full.lvs.v
mcu_dp_INC       := lvs_include_mcu
mcu_dp_CTL       := pvs/lvs_mcu_ctl
mcu_dp_LABELS    :=

# Wound-patch SoC assembly (staged 2026-07-26; NOTHING RUN YET). Cell name is
# "MCU" again -- the Myshkin-collision heartland; the LIB discriminates and the
# guarded strmin cellMap makes it safe. LABELS is EXPLICIT and MANDATORY here:
# lvs.sh defaults to pvs/<cell>.lvslabels = pvs/MCU.lvslabels, which is the
# CASTALIA/DP assembly's label set -- exactly the A6 cell-name trap that
# produced a phantom VDD_SW MISMATCH on the Argus tile. pvs/MCU_WOUND.lvslabels
# must be dumped from the WOUND cut's own signoff DB (gen_mcu_lvslabels.py /
# the block's *_lvs_netlist.tcl) alongside pvs/MCU_WOUND_full.lvs.v -- the A7
# same-cut rule, which lvs.sh enforces by mtime. NB while that file does not
# exist, lvs.sh's `if [ -f "$LABELS" ]` makes the VDD_SW injection a SILENT
# no-op (the G2 hart_tile_vddsw class) -- generate it before trusting a verdict.
# CTL reuses pvs/lvs_mcu_ctl: verified design-agnostic (it names only
# hart_tile + Xhart0..3/VDD_SW, identical in this assembly).
# BUILD THE COLLATERAL WITH:  ./gen_wound_lvs_collateral.sh block
#   -> tcl/mcu_wound_lvs_netlist.tcl (A7 fresh-init + defIn, FE_OFN/CTS_ gate,
#      same-session labels) then the tile-netlist concat that makes _full.
#   pvs/MCU_WOUND_full.lvs.v MUST be assembly + the FULL pvs/hart_tile.lvs.v
#   (F2a: a boxed tile or a stub aborts the compare at the matcher threshold).
mcu_wound_LIB       := MCU_WOUND_signoff
mcu_wound_CELL      := MCU
mcu_wound_GDS       := $(INN)/MCU_WOUND/out/MCU_WOUND.gds2
mcu_wound_RULE      := blockdrc
mcu_wound_NETLIST   := pvs/MCU_WOUND_full.lvs.v
mcu_wound_INC       := lvs_include_mcu
mcu_wound_CTL       := pvs/lvs_mcu_ctl
mcu_wound_LABELS    := pvs/MCU_WOUND.lvslabels

# Argus MCU assembly: DRC-supported; no standalone LVS netlist has ever been
# cut for it (chip-level LVS covers it) -- pass NETLIST= explicitly if needed.
# NB: BOTH assemblies' GDS topcell is "MCU" (the Myshkin-collision heartland --
# the guarded strmin's cellMap is what makes this safe); LIB discriminates.
mcu_argus_LIB     := MCU_ARGUS_signoff
mcu_argus_CELL    := MCU
mcu_argus_GDS     := $(INN)/MCU_ARGUS/out/MCU_ARGUS.gds2
mcu_argus_RULE    := blockdrc
mcu_argus_NETLIST :=
mcu_argus_INC     := lvs_include_mcu
mcu_argus_CTL     :=
mcu_argus_LABELS  :=

chip_top_LIB       := chip_top_signoff
chip_top_CELL      := chip_top
chip_top_GDS       := $(INN)/attic/out.chip_top.gds2  # DELETED row-layout flow (2026-07-27)
chip_top_RULE      := chipdrc
chip_top_NETLIST   := pvs/chip_top_full.lvs.v
chip_top_INC       := lvs_include_chip
chip_top_CTL       := pvs/lvs_chip_ctl
chip_top_LABELS    :=

# DP chip (G2): topcell chip_top_dp is UNIQUE repo-wide (no _LABELS needed --
# LABELS defaults to pvs/chip_top_dp.lvslabels; the lvs.sh chip_top* case also
# injects pvs/hart_tile_vddsw.lvslabels into the tile struct).
chip_top_dp_LIB     := chip_top_dp_signoff
chip_top_dp_CELL    := chip_top_dp
chip_top_dp_GDS     := $(INN)/chip_top_dp/out/chip_top_dp.gds2
chip_top_dp_RULE    := chipdrc
chip_top_dp_NETLIST := pvs/chip_top_dp_full.lvs.v
chip_top_dp_INC     := lvs_include_chip
chip_top_dp_CTL     := pvs/lvs_chip_dp_ctl
chip_top_dp_LABELS  :=

# Wound chip (staged 2026-07-26; NOTHING RUN YET). topcell chip_top_wound is
# UNIQUE repo-wide, so lvs.sh's pvs/<cell>.lvslabels default resolves correctly
# -- LABELS stays empty exactly like chip_top_dp. (pvs/chip_top_wound.lvslabels
# is staged as a copy of pvs/MCU.lvslabels, the C0/G2 chip precedent: the tile
# row sits at the same native coordinates in every Castalia-line assembly. It
# must still be RE-DUMPED from the wound cut's own DB before a real verdict --
# A7 same-cut rule, enforced by lvs.sh's mtime gate.) The lvs.sh chip_top* case
# also injects pvs/hart_tile_vddsw.lvslabels into the tile struct.
# BUILD THE COLLATERAL WITH:  ./gen_wound_lvs_collateral.sh chip
#   -> tcl/chip_top_wound_lvs_netlist.tcl (A7 fresh-init + defIn, FE_OFN/CTS_
#      gate, same-session labels) + patch_chip_pads_wound.py (17 pads incl. the
#      ARSV->AIO binding) + the tile-netlist concat that makes _full.
chip_top_wound_LIB     := chip_top_wound_signoff
chip_top_wound_CELL    := chip_top_wound
chip_top_wound_GDS     := $(INN)/attic/out.chip_top_wound.gds2  # DELETED row-layout flow (2026-07-27)
chip_top_wound_RULE    := chipdrc
chip_top_wound_NETLIST := pvs/chip_top_wound_full.lvs.v
chip_top_wound_INC     := lvs_include_chip
chip_top_wound_CTL     := pvs/lvs_chip_wound_ctl
chip_top_wound_LABELS  :=

# Wound-QUAD chip (staged 2026-07-27; NOTHING RUN YET): the wound SoC re-cut on
# the quadrant-symmetric Castalia-Quad floorplan. topcell chip_top_wound_quad is
# UNIQUE repo-wide, so lvs.sh's pvs/<cell>.lvslabels default resolves correctly
# -- LABELS stays EMPTY, the chip_top_dp / chip_top_wound convention. NB unlike
# chip_top_wound, NO placeholder pvs/chip_top_wound_quad.lvslabels is staged: a
# placeholder from another floorplan would be actively wrong (4 corner tiles,
# R0/MY/MX/R180) and, being NEWER than any netlist, would slip past lvs.sh's
# mtime gate. The file is created by the same innovus session that writes the
# netlist. The lvs.sh chip_top* case also injects pvs/hart_tile_vddsw.lvslabels
# into the tile struct.
# There is deliberately no `mcu_wound_quad` block: this is a FLAT chip run (the
# MCU_WOUND hierarchy is placed/routed inside the chip), so no assembly cut and
# no assembly GDS/netlist exist to sign off separately.
# BUILD THE COLLATERAL WITH:  ./gen_wound_quad_lvs_collateral.sh
#   -> tcl/chip_top_wound_quad_lvs_netlist.tcl (A7 fresh-init + defIn, FE_OFN/
#      CTS_ gate measured against out/chip_top_wound_quad.xsim.v, same-session
#      4-orientation labels) + patch_chip_pads_wound.py REUSED verbatim (binds
#      by instance name; the padlist file is literally shared) + the
#      tile-netlist concat that makes _full.
chip_top_wound_quad_LIB     := chip_top_wound_quad_signoff
chip_top_wound_quad_CELL    := chip_top_wound_quad
chip_top_wound_quad_GDS     := $(INN)/chip_top_wound_quad/out/chip_top_wound_quad.gds2
chip_top_wound_quad_RULE    := chipdrc
chip_top_wound_quad_NETLIST := pvs/chip_top_wound_quad_full.lvs.v
chip_top_wound_quad_INC     := lvs_include_chip
chip_top_wound_quad_CTL     := pvs/lvs_chip_wound_quad_ctl
chip_top_wound_quad_LABELS  :=

# MCU_castalia: the SAME design as chip_top_wound_quad above, renamed by user
# directive (2026-07-28). NAMING WARNING for future readers -- despite the
# `mcu_castalia` key and the MCU_ prefix, this is NOT a block assembly like
# mcu / mcu_dp / mcu_wound: it is a FLAT CHIP run WITH the LQFP-100 pad ring,
# i.e. a chip_top_* in everything but name. The MCU_ prefix here does not carry
# the repo's usual "block assembly" meaning.
# Its VIA structs are MCU_castalia_VIA* (flat run -> design name seeds them), so
# they do NOT match strmin_gds.sh's literal `MCU_VIA*` pattern and cannot be
# hijacked from myshkin_tapeout; the topcell pin + the XSTRM-287 FATAL gate
# still apply unchanged. _LABELS is set EXPLICITLY (cell name is unique, so the
# default would resolve correctly, but the A6 same-name trap makes explicit the
# house rule).
mcu_castalia_LIB     := MCU_castalia_signoff
mcu_castalia_CELL    := MCU_castalia
mcu_castalia_GDS     := $(INN)/MCU_castalia/out/MCU_castalia.gds2
mcu_castalia_RULE    := chipdrc
mcu_castalia_NETLIST := pvs/MCU_castalia_full.lvs.v
mcu_castalia_INC     := lvs_include_chip
mcu_castalia_CTL     := pvs/lvs_MCU_castalia_ctl
mcu_castalia_LABELS  := pvs/MCU_castalia.lvslabels

# CASTALIA-PENTA (CP5, 2026-08-13): the 5-core re-cut of the SAME chip --
# four hardened corner tiles untouched + the SOFT orchestrator hart4 (its own
# 16 KiB TCM) in the right band flank. Like mcu_castalia (and DESPITE the MCU_
# prefix) this is NOT a block assembly: it is a FLAT CHIP run WITH the LQFP-100
# pad ring, hence RULE=chipdrc.
# CPR7 RETARGET (2026-08-15): the block now signs off the CPR6 RE-CUT (5 cores
# on the CPR5b tile, orchestrator renumbered to hart0, tiles hart1..hart4)
# after its own closure ECO.  LAYOUT is the CPR7 ECO cut of record
# (out/MCU_castalia_penta.cpr7.gds2), NOT out/MCU_castalia_penta.cpr6.gds2 (that
# one still carries the unrepaired VSS M4 antenna) and NOT the CP-era
# out/MCU_castalia_penta{,.cp5}.gds2 -- those are the 4-tile-numbering reference
# cuts and must never be signed off as the product.
# RENUMBER CONSEQUENCE, load-bearing for LVS: the four SWITCHED-RAIL hardened
# tiles are Xmcu0/Xhart1..Xhart4 now (Xhart0 is the SOFT orchestrator and has no
# VDD_SW), so the _CTL cpoints and the lvslabels loop moved by one -- see
# pvs/lvs_MCU_castalia_penta_ctl and tcl/MCU_castalia_penta_lvs_netlist.tcl.
# Its VIA structs are MCU_castalia_penta_VIA* (flat run -> the design name seeds
# them), so like MCU_castalia_VIA* they cannot collide with Myshkin's MCU_VIA*
# family; the strmin topcell pin + the XSTRM-287 FATAL gate still apply.
# _LABELS is EXPLICIT (house rule for every same-family block; the cell name is
# unique so the default would also resolve, but explicit is the A6 lesson).
# NB the tile-struct VDD_SW injection in lvs.sh is guarded by `case $cell in
# chip_top*)` -- MCU_castalia_penta does NOT match it, exactly like
# MCU_castalia. Parity with the reference block is deliberate (the CP5
# adjudication compares residuals class-by-class); see the CP5 report.
# BUILD THE COLLATERAL WITH:  ./gen_MCU_castalia_penta_lvs_collateral.sh
mcu_castalia_penta_LIB     := MCU_castalia_penta_signoff
mcu_castalia_penta_CELL    := MCU_castalia_penta
# CPR6 RETARGET (2026-08-18): the LVS collateral was moved to the cpr6.signoff
# cut (CUTSEL in gen_MCU_castalia_penta_lvs_collateral.sh + the netlist tcl)
# for the 8 KiB-TCM re-implementation, but this default still pointed at the
# Aug-15 cpr7 GDS -- the 16 KiB lineage. A bare `make lvs BLOCK=...` would
# then have compared an 8 KiB source netlist against a 16 KiB layout, which is
# exactly the cross-cut compare the A7 rule exists to prevent. The default now
# follows CUTSEL. The cpr7 antenna argument no longer applies: this cut
# measures Antenna 0 / dangling 0 in its own signoff verifyGeometry +
# verifyConnectivity reports.
mcu_castalia_penta_GDS     := $(INN)/MCU_castalia_penta/out/MCU_castalia_penta.cpr6.gds2
mcu_castalia_penta_RULE    := chipdrc
mcu_castalia_penta_NETLIST := pvs/MCU_castalia_penta_full.lvs.v
# INC RETARGET (2026-08-18, LVS setup fix): the penta chip instantiates the
# 8 KiB TCM macro sram1p8k_hvt_pg (5x: 4 hardened tiles + the soft
# orchestrator). lvs_include_chip has no CDL for it, so Pegasus aborted with
#   ERROR (NVN-13010): Cell sram1p8k_hvt_pg is not defined.  -> rc=1
# lvs_include_chip_penta = lvs_include_chip + that one .include_cdl line.
mcu_castalia_penta_INC     := lvs_include_chip_penta
mcu_castalia_penta_CTL     := pvs/lvs_MCU_castalia_penta_ctl
mcu_castalia_penta_LABELS  := pvs/MCU_castalia_penta.lvslabels

# MCU_hart (2026-08-24): the SINGLE-HART block assembly -- the small vehicle
# built to chase the MCU/chip LVS mismatch at reduced cost.  This IS a block
# assembly (unlike mcu_castalia / mcu_castalia_penta, whose MCU_ prefix is
# misleading): no pad ring, hence RULE=blockdrc.
# CELL is "MCU" again, the Myshkin-collision heartland -- the LIB discriminates
# and the guarded strmin cellMap makes it safe.  _LABELS is EXPLICIT and
# MANDATORY: lvs.sh defaults to pvs/<cell>.lvslabels = pvs/MCU.lvslabels, which
# is the CASTALIA/DP assembly's label set, i.e. exactly the A6 cell-name trap
# that produced a phantom VDD_SW MISMATCH on the Argus tile.  While
# pvs/MCU_hart.lvslabels does not exist, lvs.sh's `if [ -f "$LABELS" ]` makes
# the VDD_SW injection a SILENT no-op -- generate it before trusting a verdict.
# _INC is lvs_include_hart, which is the ONLY include in this tree carrying a
# CDL for the new rom2k_hvt_pg boot ROM.  Without it Pegasus aborts with
#   ERROR (NVN-13010): Cell rom2k_hvt_pg is not defined.
# which is the same abort the 2026-08-16 TCM swap hit on sram1p8k_hvt_pg.
# _CTL binds the ONE hardened tile's switched rail: `lvs_cpoint VDD_SW_H0
# Xhart0/VDD_SW`.  Keep it in sync with tcl/MCU_hart_lvs_netlist.tcl's label
# text -- a name/index skew there is a phantom MISMATCH, not an error.
# BUILD THE COLLATERAL WITH:  ./gen_MCU_hart_lvs_collateral.sh
mcu_hart_LIB       := MCU_hart_signoff
mcu_hart_CELL      := MCU
mcu_hart_GDS       := $(INN)/MCU_hart/out/MCU_hart.gds2
mcu_hart_RULE      := blockdrc
mcu_hart_NETLIST   := pvs/MCU_hart_full.lvs.v
mcu_hart_INC       := lvs_include_hart
mcu_hart_CTL       := pvs/lvs_MCU_hart_ctl
mcu_hart_LABELS    := pvs/MCU_hart.lvslabels

# Argus chip: topcell is ALSO "chip_top" (distinct only by lib) -> needs its
# own lvslabels (A6 lesson) and the A7-cut netlist.
chip_top_argus_LIB     := chip_argus_a7_signoff
chip_top_argus_CELL    := chip_top
chip_top_argus_GDS     := $(INN)/chip_top_argus/out/chip_top_argus.gds2
chip_top_argus_RULE    := chipdrc
chip_top_argus_NETLIST := pvs/chip_top_argus_a7_full.lvs.v
chip_top_argus_INC     := lvs_include_chip
chip_top_argus_CTL     := pvs/lvs_chip_argus_ctl
chip_top_argus_LABELS  := pvs/chip_top_argus_a7.lvslabels

chip_top_quad_LIB     := chip_top_quad_signoff
chip_top_quad_CELL    := chip_top_quad
chip_top_quad_GDS     := $(INN)/chip_top_quad/out/chip_top_quad.gds2
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
	@case "$(BLOCK)" in \
	  mcu_wound)           M="gen_wound_lvs_collateral.sh block";; \
	  chip_top_wound)      M="gen_wound_lvs_collateral.sh chip";; \
	  chip_top_wound_quad) M="gen_wound_quad_lvs_collateral.sh";; \
	  mcu_hart)            M="gen_MCU_hart_lvs_collateral.sh";; \
	  *) M=;; esac; \
	if [ -n "$$M" ] && [ ! -s "$(NETLIST)" ]; then \
	  echo "lvs: $(NETLIST) is missing -- build the wound collateral first:"; \
	  echo "       ./$$M"; \
	  echo "     (A7 fresh-init netlist + same-session lvslabels + the FULL"; \
	  echo "      pvs/hart_tile.lvs.v appended -- a boxed/stubbed tile aborts the compare)"; \
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
	    chip_top_dp)     printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_dp_LIB)" "$(chip_top_dp_CELL)" "$(chip_top_dp_RULE)" "$(chip_top_dp_GDS)";; \
	    mcu_dp)          printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_dp_LIB)" "$(mcu_dp_CELL)" "$(mcu_dp_RULE)" "$(mcu_dp_GDS)";; \
	    mcu_wound)       printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_wound_LIB)" "$(mcu_wound_CELL)" "$(mcu_wound_RULE)" "$(mcu_wound_GDS)";; \
	    chip_top_wound)  printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_wound_LIB)" "$(chip_top_wound_CELL)" "$(chip_top_wound_RULE)" "$(chip_top_wound_GDS)";; \
	    chip_top_wound_quad) printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_wound_quad_LIB)" "$(chip_top_wound_quad_CELL)" "$(chip_top_wound_quad_RULE)" "$(chip_top_wound_quad_GDS)";; \
	    chip_top_argus)  printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_argus_LIB)" "$(chip_top_argus_CELL)" "$(chip_top_argus_RULE)" "$(chip_top_argus_GDS)";; \
	    chip_top_quad)   printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(chip_top_quad_LIB)" "$(chip_top_quad_CELL)" "$(chip_top_quad_RULE)" "$(chip_top_quad_GDS)";; \
	    mcu_castalia)    printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_castalia_LIB)" "$(mcu_castalia_CELL)" "$(mcu_castalia_RULE)" "$(mcu_castalia_GDS)";; \
	    mcu_castalia_penta) printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_castalia_penta_LIB)" "$(mcu_castalia_penta_CELL)" "$(mcu_castalia_penta_RULE)" "$(mcu_castalia_penta_GDS)";; \
	    mcu_hart)        printf "%-16s %-24s %-14s %-10s %s\n" $$b "$(mcu_hart_LIB)" "$(mcu_hart_CELL)" "$(mcu_hart_RULE)" "$(mcu_hart_GDS)";; \
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
