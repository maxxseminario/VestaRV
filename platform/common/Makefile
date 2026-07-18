# Castalia (4-hart multi-core VestaRV) chip generator Makefile
# Source of truth: python/generate.py — everything else is generated from it.
# All outputs stay inside platform/common/ (never touches ../../hdl, ../../software, ../../tools).

.PHONY: all help chip generate pdf web web-copy publish check-publish publish-chip check-chip install-hook show config verify clean install-deps

# Which implementations/asic/<CHIP>/docs/TRM.pdf the publish/check targets act on.
# The default build ('make chip') is Castalia; a non-default chip also needs its CONFIG,
# so use the publish-chip / check-chip convenience targets (they build the requested chip
# then regenerate the default Castalia artifacts so out/ and the tracked resolved-config
# JSON go back to HEAD).
CHIP ?= castalia
PUBLISH_PDF = ../../implementations/asic/$(CHIP)/docs/TRM.pdf

# pdflatex: PATH first, then any user-local TeX Live install
PDFLATEX := $(shell command -v pdflatex 2>/dev/null || ls $(HOME)/texlive/*/bin/*/pdflatex 2>/dev/null | head -1)

# Reproducible-PDF anchor: with SOURCE_DATE_EPOCH set, pdfTeX (>=1.40.17) pins the
# embedded /CreationDate, /ModDate AND the trailer /ID, so identical TRM.tex -> byte-
# identical TRM.pdf. This is what makes 'make check-publish' a meaningful byte-diff.
# It is an ARBITRARY FIXED instant (2025-01-01 UTC), not the build time — every TRM
# content date is config-driven, so this only affects otherwise-nondeterministic PDF
# metadata. Do not derive it from HEAD/now, or rebuilds stop being reproducible.
SOURCE_DATE_EPOCH ?= 1735689600

# Optional chip-name override for the whole configuration (TRM title page/prose,
# generated file headers): make chip CHIP_NAME=MyChip
CHIP_NAME ?=

# Optional configuration file (JSON) produced by docs/chip_configurator.html or
# written by hand: make chip CONFIG=path/to/config.json
# Knobs: chipName, numHarts, numMutexes, registerFileDualPort, isa.*,
# memory.*, peripherals.npu — every key optional, unknown keys are a hard
# error (typo protection), and the resolved result is written to
# config/ChipConfig.resolved.json. CHIP_NAME still wins over the file's
# chipName. Schema reference: docs/chip_configurator.html (interactive),
# the generated TRM's "Chip Configuration" section, or generate.py's
# _CONFIG_SCHEMA (the authority).
CONFIG ?=

# Default: 'make chip' regenerates the artifacts AND builds the TRM PDF
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

# ---------------------------------------------------------------------------
# Chip artifact generation (memory map -> headers, linker scripts, HDL, JSON, TRM LaTeX)
# ---------------------------------------------------------------------------
generate:
	@echo "Generating chip artifacts from python/generate.py..."
	@if [ -n "$(CONFIG)" ]; then echo "  • using config file: $(CONFIG)"; fi
	@cd python && CHIP_NAME='$(CHIP_NAME)' CHIP_CONFIG='$(if $(CONFIG),$(abspath $(CONFIG)),)' python3 generate.py
	@echo ""
	@echo "C-compiling the emitted MemoryMap.h (riscv-none-elf-gcc -fsyntax-only)..."
	@python3 python/check_memorymap_h.py out/software/include/MemoryMap.h
	@echo ""
	@echo "Checking docs/chip_configurator.html against the schema/pad-ring/geometry..."
	@python3 python/check_configurator_sync.py --strict
	@echo ""
	@echo "✅ Generation complete. Outputs:"
	@echo "  • out/software/include/MemoryMap.h, periph.S"
	@echo "  • out/linker-scripts/memory.x, periph.x, *.txt"
	@echo "  • out/hdl/MCU.vhd, MemoryMap.vhd, riscv_tb.vhd, MCU_routing_template.vhd"
	@echo "  • config/MemoryMap.json, ChipConfig.resolved.json, PadRing.json"
	@echo "  • latex/TRM/  (LaTeX sources incl. generated block/boot/sync/pinout diagrams)"

# The full chip: artifacts + the Technical Reference Manual PDF for exactly this
# configuration (chapters, register tables, memory map, and feature list are all
# derived from what python/generate.py instantiates)
chip: generate
	@$(MAKE) --no-print-directory pdf
	@$(MAKE) --no-print-directory web-copy
	@echo ""
	@echo "✅ Chip generation complete — RTL in out/hdl/, TRM at latex/TRM/TRM.pdf, web data in out/web/"

# ---------------------------------------------------------------------------
# TRM PDF (requires pdflatex; auto-detected from PATH or ~/texlive)
# ---------------------------------------------------------------------------
pdf:
	@if [ -z "$(PDFLATEX)" ]; then \
		echo "❌ pdflatex not found on PATH or in ~/texlive."; \
		echo "   Try: export PATH=\$$HOME/texlive/2026/bin/x86_64-linux:\$$PATH"; \
		exit 1; fi
	@if [ ! -f latex/TRM/TRM.tex ]; then \
		echo "❌ latex/TRM/TRM.tex not generated yet. Run 'make chip' first."; \
		exit 1; fi
	@echo "Compiling TRM (clean .aux + 3 pdflatex passes: converged AND reproducible)..."
	@cd latex/TRM && \
		export SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) FORCE_SOURCE_DATE=1 && \
		rm -f TRM.aux TRM.toc TRM.out TRM.lof TRM.lot TRM.idx && \
		for pass in 1 2 3; do \
			'$(PDFLATEX)' -interaction=nonstopmode TRM.tex > build.log 2>&1 || \
			{ echo "❌ pdflatex failed (pass $$pass) — last lines of latex/TRM/build.log:"; tail -25 build.log; exit 1; }; \
		done
	@grep -E "Output written|^!" latex/TRM/build.log | head -3
	@echo "✅ latex/TRM/TRM.pdf (reproducible; SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH))"

# ---------------------------------------------------------------------------
# Web data export (S2): out/web/chip_data.js is emitted by generate.py itself
# (writer wired into ChipGenerator.Generate() next to generateMemoryMapJson).
# 'make web' regenerates it and ALSO copies config/MemoryMap.json alongside it
# for WP S8's register browser. Both outputs stay under platform/common/out/web/
# (golden rule). 'web-copy' is the copy-only step the 'chip' chain reuses so a
# full 'make chip' doesn't regenerate twice.
# ---------------------------------------------------------------------------
web: generate
	@$(MAKE) --no-print-directory web-copy
	@if [ -z "$(CONFIG)" ]; then \
		python3 python/splice_web_data.py ../../docs/chip_configurator.html && \
		echo "  • spliced VESTA_DATA into docs/chip_configurator.html (S7 consumption contract)"; \
	else \
		echo "  • CONFIG build — skipping the docs/ splice (the page carries the default bundle)"; \
	fi

web-copy:
	@echo "Exporting machine-readable chip data to out/web/..."
	@mkdir -p out/web
	@cp config/MemoryMap.json out/web/MemoryMap.json
	@echo "✅ Web export:"
	@echo "  • out/web/chip_data.js   (VESTA_DATA: schema, defaults, packages, presets, memory map)"
	@echo "  • out/web/MemoryMap.json (full peripheral→register→bitfield tree, for the register browser)"

# Publish the built TRM to the repo's implementations tree (committing is left to you,
# so a stale or broken PDF never gets pushed by accident)
publish:
	@if [ ! -f latex/TRM/TRM.pdf ]; then \
		echo "❌ latex/TRM/TRM.pdf not built. Run 'make pdf' first."; \
		exit 1; fi
	@mkdir -p $(dir $(PUBLISH_PDF))
	@cp latex/TRM/TRM.pdf $(PUBLISH_PDF)
	@echo "✅ Published to $(PUBLISH_PDF)"
	@echo "   Review and commit it: git add $(PUBLISH_PDF) && git commit"

# Drift gate (the check_mcu_vhd.py analog for the TRM): rebuild the PDF deterministically
# from the CURRENT generated latex/TRM/TRM.tex and byte-compare it to the committed copy.
# Exit 0 = the published TRM matches what the generator produces; exit 1 = STALE.
# Assumes the TeX is current — run 'make generate' (or 'make chip') first if generate.py,
# the templates, or intro tex changed. Used by the pre-commit hook (see install-hook).
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

# Build + publish one chip's TRM in a single step, then restore the default (Castalia)
# artifacts. Use for non-default chips, which need their CONFIG:
#   make publish-chip CHIP=argus CONFIG=config/argus.json
# The trailing 'generate' returns out/ and the tracked config/*.resolved.json to Castalia
# (the CLAUDE.md "re-run plain make chip after any Argus-config run" idiom, baked in).
publish-chip:
	@$(MAKE) --no-print-directory generate CONFIG=$(CONFIG)
	@$(MAKE) --no-print-directory pdf
	@$(MAKE) --no-print-directory publish CHIP=$(CHIP)
	@$(MAKE) --no-print-directory generate CONFIG= >/dev/null
	@echo "↩  restored default (Castalia) artifacts"

# Non-default-chip drift check (manual; the pre-commit hook only gates the default
# Castalia TRM to avoid churning the tracked resolved-config JSON):
#   make check-chip CHIP=argus CONFIG=config/argus.json
check-chip:
	@$(MAKE) --no-print-directory generate CONFIG=$(CONFIG)
	@$(MAKE) --no-print-directory check-publish CHIP=$(CHIP); rc=$$?; \
	 $(MAKE) --no-print-directory generate CONFIG= >/dev/null; \
	 echo "↩  restored default (Castalia) artifacts"; \
	 exit $$rc

# Install the pre-commit hook that runs check-publish so a stale TRM can't be committed.
# The hook SOURCE is tracked at hooks/pre-commit; this copies it into the repo's .git.
install-hook:
	@hookdir="$$(cd ../.. && git rev-parse --absolute-git-dir)/hooks"; \
	 mkdir -p "$$hookdir"; \
	 cp hooks/pre-commit "$$hookdir/pre-commit"; \
	 chmod +x "$$hookdir/pre-commit"; \
	 echo "✅ Installed pre-commit hook -> $$hookdir/pre-commit"

show config:
	@./show_config.sh

# ---------------------------------------------------------------------------
# Config -> RTL -> proof: stage out/hdl into an Xcelium behavioral flow and run
# the smoke suite (the A3 Argus hand-staging pattern, productized). Needs the
# Cadence tools (verify.sh's runner sources ~/vestarv/cdspaths.sh itself) and
# the riscv-none-elf- toolchain if the image set for this NHARTS isn't built.
# ---------------------------------------------------------------------------
verify: generate
	@./verify.sh

# Clean generated files (Castalia outputs only — NEVER touches the Myshkin toolchain
# files in ../../software or ../../tools, and keeps latex/TRM/include/*_man.tex wrappers)
clean:
	@echo "⚠️  This removes generated Castalia outputs: out/, config/*.json,"
	@echo "    and LaTeX build artifacts in latex/TRM/ (not the _man.tex wrappers)."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf out; \
		rm -f config/MemoryMap.json config/ChipConfig.resolved.json config/PadRing.json; \
		rm -f latex/TRM/TRM.pdf latex/TRM/build.log latex/TRM/*.aux latex/TRM/*.toc latex/TRM/*.out latex/TRM/*.log; \
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
