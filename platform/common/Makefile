# VestaRV: chip generator for Castalia, the five-hart part with a soft
# orchestrator at hart 0 and four hardened tiles.
# python/generate.py is the source of truth; everything else is generated from it.
# Every output stays inside platform/common/: this Makefile never writes to
# ../../hdl, ../../software or ../../tools.

.PHONY: all help chip generate pdf web web-copy publish check-publish publish-chip check-chip install-hook show config verify clean install-deps

# Which implementations/asic/<CHIP>/docs/TRM.pdf the publish and check targets act
# on. `make chip` builds Castalia; a non-default chip also needs its CONFIG, so use
# publish-chip or check-chip, which build the requested chip and then regenerate
# the default artifacts so out/ and the tracked resolved-config JSON return to HEAD.
CHIP ?= castalia
PUBLISH_PDF = ../../implementations/asic/$(CHIP)/docs/TRM.pdf

# pdflatex: PATH first, then any user-local TeX Live install
PDFLATEX := $(shell command -v pdflatex 2>/dev/null || ls $(HOME)/texlive/*/bin/*/pdflatex 2>/dev/null | head -1)

# Reproducible-PDF anchor. With SOURCE_DATE_EPOCH set, pdfTeX 1.40.17 and later pins
# the embedded /CreationDate, /ModDate and the trailer /ID, so identical TRM.tex
# gives a byte-identical TRM.pdf, which is what makes check-publish a meaningful
# byte diff. It is an arbitrary fixed instant, not the build time: every TRM content
# date is config driven, so this affects only otherwise-nondeterministic PDF
# metadata. Deriving it from HEAD or from now would end reproducibility.
SOURCE_DATE_EPOCH ?= 1735689600
# The TRM's visible revision date, taken from the newest commit date of the TRM's
# own input set rather than from the wall clock. A wall-clock date would be
# restamped by every `make verify`, since verify depends on generate, and
# check-publish could then pass only on the publish day. It is deliberately not
# SOURCE_DATE_EPOCH: that fixed instant would print the same date on every TRM
# forever. This one means something and is still identical for every checkout of
# the same tree. `?=` lets a caller override it, and the fallback keeps a git-less
# export building, where LatexUserGuide.py falls through to SOURCE_DATE_EPOCH.
VESTA_TRM_DATE_EPOCH ?= $(shell git -C $(CURDIR) log -1 --format=%ct -- \
    python latex config 2>/dev/null)
export VESTA_TRM_DATE_EPOCH
# The title page also prints a build hash: the abbreviated hash of the same commit
# the revision date comes from, so the two agree. The pdf target writes it to
# latex/TRM/buildhash.tex as a \BuildHash define and the template falls back to
# "unversioned" when that file is missing, as in a git-less export. It is not a
# dirty-tree indicator: that would make check-publish unpassable on any edited tree.
VESTA_TRM_BUILD_HASH ?= $(shell git -C $(CURDIR) log -1 --format=%h --abbrev=8 -- \
    python latex config 2>/dev/null)
export VESTA_TRM_BUILD_HASH

# Chip-name override for the whole configuration, covering the TRM title page and
# prose and the generated file headers: make chip CHIP_NAME=MyChip
CHIP_NAME ?=

# Configuration file, written by hand or exported by docs/chip_configurator.html:
# make chip CONFIG=path/to/config.json
# Knobs: chipName, numHarts, numMutexes, registerFileDualPort, isa.*, memory.*,
# peripherals.npu. Every key is optional and an unknown key is a hard error, which
# is the typo protection. This reaches generate.py as CHIP_CONFIG, the environment
# form of its --config flag, and CHIP_NAME still wins over the file's chipName.
# generate.py's _CONFIG_SCHEMA is the authority on the schema. The resolved result
# is written to out/config/ChipConfig.resolved.json on every run; the TRACKED
# config/ pair is refreshed only by a default build, so a CONFIG= build leaves the
# working tree clean and needs no restoring run.
CONFIG ?=

# `make chip` regenerates the artifacts and builds the TRM PDF.
all: chip

help:
	@echo "=========================================="
	@echo "Castalia Chip Generator"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make chip         - Generate the full chip configuration AND its TRM PDF:"
	@echo "                      headers, linker scripts, drop-in HDL, JSON, TRM LaTeX + PDF"
	@echo "                      (optional: CHIP_NAME=MyChip renames the chip everywhere;"
	@echo "                       CONFIG=cfg.json feeds a docs/chip_configurator.html export)"
	@echo "  make generate     - Chip artifacts only (no PDF)"
	@echo "  make pdf          - Compile the Technical Reference Manual PDF only"
	@echo "  make publish      - Copy the built TRM.pdf to implementations/asic/castalia/docs/"
	@echo "                      (then review + commit it yourself)"
	@echo "  make check-publish- Verify the committed TRM matches the generator (byte-diff a"
	@echo "                      deterministic rebuild vs the published PDF; exit 1 if stale)"
	@echo "  make publish-chip - Build + publish a non-default chip's TRM, then restore Castalia"
	@echo "                      (e.g. make publish-chip CHIP=argus CONFIG=config/argus.json)"
	@echo "  make check-chip   - check-publish for a non-default chip (CHIP=/CONFIG= as above)"
	@echo "  make install-hook - Install a pre-commit hook that runs check-publish"
	@echo "  make show         - Show the resolved chip configuration + derived pad ring"
	@echo "                      (reads config/ChipConfig.resolved.json from the last build)"
	@echo "  make verify       - Prove the configuration BOOTS: stage the generated RTL into"
	@echo "                      an Xcelium behavioral flow and run the smoke suite"
	@echo "                      (CONFIG= as for make chip; SUITE=full for the whole"
	@echo "                       regression; MAX_PARALLEL=N, FORCE_IMAGES=1)"
	@echo "  make clean        - Remove generated output files (out/, config JSON)"
	@echo "  make install-deps - Check Python/LaTeX dependencies"
	@echo ""
	@echo "Source of truth: python/generate.py"
	@echo "Documentation:   README.md (and CLAUDE.md for AI sessions)"
	@echo "=========================================="

# Chip artifacts: memory map to headers, linker scripts, HDL, JSON, TRM LaTeX.
SYNC_MODE ?= --strict

# The generator needs a SystemRDL-capable interpreter: generate.py reads
# hdl/common/regs/rdl/*.rdl for its register maps, systemrdl-compiler needs Python
# 3.8 or newer, and several hosts here ship 3.6 as /usr/bin/python3.
# python/rdl_python.py returns this shell's python3 when it can already import the
# compiler, and otherwise the hermetic interpreter and pinned wheels bazel
# provisions, which are the ones //platform/common:chip_artifacts_* uses, so make
# and bazel agree by construction. It fails loudly rather than generating a chip
# with eighteen peripherals' registers missing. Every other python3 below is a
# self-contained checker with no third-party dependency.
GEN_PYTHONPATH := $(shell python3 python/rdl_python.py --pythonpath)
GEN_PYTHON := $(shell python3 python/rdl_python.py --python)

generate:
	@echo "Generating chip artifacts from python/generate.py..."
	@if [ -n "$(CONFIG)" ]; then echo "  • using config file: $(CONFIG)"; fi
	@if [ -z "$(GEN_PYTHON)" ]; then python3 python/rdl_python.py >/dev/null; exit 1; fi
	@echo "  • SystemRDL interpreter: $(GEN_PYTHON)"
	@echo "Checking every knob's two default literals agree (schema <-> _cfg)..."
	@python3 python/check_config_defaults.py
	@cd python && CHIP_NAME='$(CHIP_NAME)' CHIP_CONFIG='$(if $(CONFIG),$(abspath $(CONFIG)),)' PYTHONPATH='$(GEN_PYTHONPATH)' $(GEN_PYTHON) generate.py
	@echo ""
	@echo "C-compiling the emitted MemoryMap.h (riscv-none-elf-gcc -fsyntax-only)..."
	@python3 python/check_memorymap_h.py out/software/include/MemoryMap.h
	@echo ""
	@echo "Checking docs/chip_configurator.html against the schema/pad-ring/geometry..."
	@python3 python/check_configurator_sync.py $(SYNC_MODE)
	@echo ""
	@echo "Checking intro-chapter register names against the generated memory map..."
	@python3 python/check_intro_names.py
	@echo ""
	@echo "✅ Generation complete. Outputs:"
	@echo "  • out/software/include/MemoryMap.h, periph.S"
	@echo "  • out/linker-scripts/memory.x, periph.x, *.txt"
	@echo "  • out/hdl/MCU.vhd, MemoryMap.vhd, riscv_tb.vhd, MCU_routing_template.vhd"
	@echo "  • out/config/ChipConfig.resolved.json, PadRing.json (this build), config/MemoryMap.json"
	@echo "  • latex/TRM/  (LaTeX sources incl. generated block/boot/sync/pinout diagrams)"

# The full chip: artifacts plus the Technical Reference Manual PDF for exactly this
# configuration. Chapters, register tables, memory map and feature list all derive
# from what python/generate.py instantiates.
chip: generate
	@$(MAKE) --no-print-directory pdf
	@$(MAKE) --no-print-directory web-copy
	@echo ""
	@echo "✅ Chip generation complete — RTL in out/hdl/, TRM at latex/TRM/TRM.pdf, web data in out/web/"

# TRM PDF. Needs pdflatex, auto-detected from PATH or ~/texlive.
pdf:
	@if [ -z "$(PDFLATEX)" ]; then \
		echo "❌ pdflatex not found on PATH or in ~/texlive."; \
		echo "   Try: export PATH=\$$HOME/texlive/2026/bin/x86_64-linux:\$$PATH"; \
		exit 1; fi
	@if [ ! -f latex/TRM/TRM.tex ]; then \
		echo "❌ latex/TRM/TRM.tex not generated yet. Run 'make chip' first."; \
		exit 1; fi
	@echo "Compiling TRM (clean .aux + 3 pdflatex passes: converged AND reproducible)..."
	@printf '%% Generated by the Makefile (pdf target), do not edit\n\\newcommand{\\BuildHash}{%s}\n' \
		"$(if $(VESTA_TRM_BUILD_HASH),$(VESTA_TRM_BUILD_HASH),unversioned)" > latex/TRM/buildhash.tex
	@cd latex/TRM && \
		export SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) FORCE_SOURCE_DATE=1 && \
		rm -f TRM.aux TRM.toc TRM.out TRM.lof TRM.lot TRM.idx && \
		for pass in 1 2 3; do \
			'$(PDFLATEX)' -interaction=nonstopmode TRM.tex > build.log 2>&1 || \
			{ echo "❌ pdflatex failed (pass $$pass) — last lines of latex/TRM/build.log:"; tail -25 build.log; exit 1; }; \
		done
	@grep -E "Output written|^!" latex/TRM/build.log | head -3
	@$(MAKE) --no-print-directory trm-lint
	@echo "✅ latex/TRM/TRM.pdf (reproducible; SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH))"

# Read the rendered text back and look for LaTeX that leaked through as literal
# characters. pdflatex exits 0 on these: a mangled command compiles cleanly and
# ships wrong text, and an unresolved \ref renders as "??". The log catches
# neither, so the built PDF is the only place to check. Skipped, not failed, where
# pdftotext is unavailable.
trm-lint:
	@if ! command -v pdftotext >/dev/null 2>&1; then \
		echo "⚠️  pdftotext not found — skipping TRM text lint."; exit 0; fi
	@pdftotext -layout latex/TRM/TRM.pdf /tmp/trm-lint-$$$$.txt 2>/dev/null; \
	bad=0; \
	for pat in 'texttt' 'SI{' 'ref{' 'begin{' 'end{' 'mathrm{' 'emph{' '??'; do \
		if grep -q -F -- "$$pat" /tmp/trm-lint-$$$$.txt 2>/dev/null; then \
			echo "❌ TRM text lint: literal '$$pat' rendered in the PDF —"; \
			grep -n -F -- "$$pat" /tmp/trm-lint-$$$$.txt | head -3 | sed 's/^/     /'; \
			bad=1; \
		fi; \
	done; \
	rm -f /tmp/trm-lint-$$$$.txt; \
	if [ $$bad -ne 0 ]; then \
		echo "   A LaTeX command leaked through as text, or a cross-reference is unresolved."; \
		exit 1; fi
	@if grep -q "There were undefined references" latex/TRM/TRM.log 2>/dev/null; then \
		echo "❌ TRM: pdflatex reports undefined references —"; \
		grep -o "Hyper reference \`[^']*'" latex/TRM/TRM.log | sort -u | head -10 | sed 's/^/     /'; \
		grep -o "Reference \`[^']*' on page" latex/TRM/TRM.log | sort -u | head -10 | sed 's/^/     /'; \
		exit 1; fi
	@echo "✅ TRM text lint clean (no leaked LaTeX, no unresolved references)"

# Web data export. generate.py emits out/web/chip_data.js itself; `make web`
# regenerates it and copies config/MemoryMap.json alongside for the register
# browser. Both outputs stay under platform/common/out/web/. web-copy is the
# copy-only step the chip chain reuses so a full `make chip` does not regenerate
# twice.
#
# The inner generate here runs non-strict, SYNC_MODE empty, and the strict check
# runs after the splice. A strict inner generate would make `make web` fail on the
# very drift it exists to repair, while running the check afterwards still ends the
# target red if the splice did not fix it. The default `make generate` is unchanged
# and still a hard gate.
web:
	@$(MAKE) --no-print-directory generate SYNC_MODE=
	@$(MAKE) --no-print-directory web-copy
	@if [ -z "$(CONFIG)" ]; then \
		python3 python/splice_web_data.py ../../docs/chip_configurator.html && \
		echo "  • spliced VESTA_DATA into docs/chip_configurator.html (S7 consumption contract)"; \
		python3 python/splice_register_browser.py ../../docs/register_browser.html && \
		echo "  • spliced VESTA_REGDATA into docs/register_browser.html (register-browser provenance)"; \
	else \
		echo "  • CONFIG build — skipping the docs/ splices (the pages carry the default bundle)"; \
	fi
	@echo ""
	@echo "Re-checking the splices under the STRICT gates..."
	@python3 python/check_configurator_sync.py --strict
	@if [ -z "$(CONFIG)" ]; then \
		python3 ../../tools/python/check_register_browser.py \
			--page ../../docs/register_browser.html --map out/web/MemoryMap.json; \
	fi

web-copy:
	@echo "Exporting machine-readable chip data to out/web/..."
	@mkdir -p out/web
	@cp config/MemoryMap.json out/web/MemoryMap.json
	@echo "✅ Web export:"
	@echo "  • out/web/chip_data.js   (VESTA_DATA: schema, defaults, packages, presets, memory map)"
	@echo "  • out/web/MemoryMap.json (full peripheral→register→bitfield tree, for the register browser)"

# Publish the built TRM to the implementations tree. Committing is left to the
# caller, so a stale or broken PDF is never pushed by accident.
publish:
	@if [ ! -f latex/TRM/TRM.pdf ]; then \
		echo "❌ latex/TRM/TRM.pdf not built. Run 'make pdf' first."; \
		exit 1; fi
	@mkdir -p $(dir $(PUBLISH_PDF))
	@cp latex/TRM/TRM.pdf $(PUBLISH_PDF)
	@echo "✅ Published to $(PUBLISH_PDF)"
	@echo "   Review and commit it: git add $(PUBLISH_PDF) && git commit"

# Drift gate for the TRM, the analogue of check_mcu_vhd.py: rebuild the PDF
# deterministically from the current latex/TRM/TRM.tex and byte-compare it to the
# committed copy. Exit 0 means the published TRM matches the generator, exit 1
# means stale. It assumes the TeX is current, so run `make generate` first if
# generate.py, the templates or the intro tex changed. The pre-commit hook runs it.
check-publish: pdf
	@if [ ! -f $(PUBLISH_PDF) ]; then \
		echo "❌ No published TRM at $(PUBLISH_PDF) — run 'make publish' to create it."; \
		exit 1; fi
	@if cmp -s latex/TRM/TRM.pdf $(PUBLISH_PDF); then \
		echo "✅ Published TRM is up to date: $(PUBLISH_PDF)"; \
	else \
		echo "❌ Published TRM is STALE: latex/TRM/TRM.pdf differs from $(PUBLISH_PDF)"; \
		echo "   Refresh it:  make publish   (then: git add $(PUBLISH_PDF))"; \
		exit 1; fi

# Build and publish one chip's TRM, then restore the default artifacts. For
# non-default chips, which need their CONFIG:
#   make publish-chip CHIP=argus CONFIG=config/argus.json
# The trailing generate returns out/ to the default chip; the tracked config/ pair
# never left it.
publish-chip:
	@$(MAKE) --no-print-directory generate CONFIG=$(CONFIG)
	@$(MAKE) --no-print-directory pdf
	@$(MAKE) --no-print-directory publish CHIP=$(CHIP)
	@$(MAKE) --no-print-directory generate CONFIG= >/dev/null
	@echo "↩  restored default (Castalia) artifacts"

# Drift check for a non-default chip. Manual: the pre-commit hook gates only the
# default TRM, so it does not churn the tracked resolved-config JSON.
#   make check-chip CHIP=argus CONFIG=config/argus.json
check-chip:
	@$(MAKE) --no-print-directory generate CONFIG=$(CONFIG)
	@$(MAKE) --no-print-directory check-publish CHIP=$(CHIP); rc=$$?; \
	 $(MAKE) --no-print-directory generate CONFIG= >/dev/null; \
	 echo "↩  restored default (Castalia) artifacts"; \
	 exit $$rc

# Install the pre-commit hook that runs check-publish, so a stale TRM cannot be
# committed. The hook source is tracked at hooks/pre-commit and copied into .git.
install-hook:
	@hookdir="$$(cd ../.. && git rev-parse --absolute-git-dir)/hooks"; \
	 mkdir -p "$$hookdir"; \
	 cp hooks/pre-commit "$$hookdir/pre-commit"; \
	 chmod +x "$$hookdir/pre-commit"; \
	 echo "✅ Installed pre-commit hook -> $$hookdir/pre-commit"

show config:
	@./show_config.sh

# Config to RTL to proof: stage out/hdl into an Xcelium behavioral flow and run the
# smoke suite. Needs the Cadence tools, which verify.sh's runner reaches by sourcing
# cdspaths.sh itself, and the riscv-none-elf- toolchain if the image set for this
# NHARTS is not built.
verify: generate
	@./verify.sh

# Clean the generated Castalia outputs only. It never touches the Myshkin toolchain
# files under ../../software or ../../tools, and keeps the
# latex/TRM/include/*_man.tex wrappers.
clean:
	@echo "⚠️  This removes generated Castalia outputs: out/, config/*.json,"
	@echo "    and LaTeX build artifacts in latex/TRM/ (not the _man.tex wrappers)."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf out; \
		rm -f config/MemoryMap.json config/ChipConfig.resolved.json config/PadRing.json; \
		rm -f latex/TRM/TRM.pdf latex/TRM/build.log latex/TRM/buildhash.tex latex/TRM/*.aux latex/TRM/*.toc latex/TRM/*.out latex/TRM/*.log; \
		echo "✅ Cleaned generated files"; \
	else \
		echo "❌ Clean cancelled"; \
	fi

install-deps:
	@echo "Python 3 (>= 3.6):"
	@command -v python3 >/dev/null && python3 --version || echo "  ❌ python3 not found"
	@echo "pdflatex (TeX Live):"
	@if [ -n "$(PDFLATEX)" ]; then '$(PDFLATEX)' --version | head -1; else \
		echo "  ❌ not found — try: export PATH=\$$HOME/texlive/2026/bin/x86_64-linux:\$$PATH"; fi
	@echo "Figure tools (only needed when editing latex/figures/*.svg):"
	@command -v soffice >/dev/null && echo "  ✅ soffice" || echo "  ⚠️  soffice (LibreOffice) not found"
	@command -v gs >/dev/null && echo "  ✅ ghostscript" || echo "  ⚠️  ghostscript not found"
