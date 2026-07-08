# Castalia (4-hart multi-core VestaRV) chip generator Makefile
# Source of truth: python/generate.py — everything else is generated from it.
# All outputs stay inside platform_castalia/ (never touches ../hdl, ../software, ../tools).

.PHONY: all help chip generate pdf publish show config clean install-deps

PUBLISH_PDF = ../implementations/asic/castalia/docs/TRM.pdf

# pdflatex: PATH first, then any user-local TeX Live install
PDFLATEX := $(shell command -v pdflatex 2>/dev/null || ls $(HOME)/texlive/*/bin/*/pdflatex 2>/dev/null | head -1)

# Optional chip-name override for the whole configuration (TRM title page/prose,
# generated file headers): make chip CHIP_NAME=MyChip
CHIP_NAME ?=

# Optional configuration file (JSON) produced by docs/chip_configurator.html or
# written by hand: make chip CONFIG=path/to/config.json
# It overrides the scalar knobs in python/generate.py (chip name, hart count,
# register file, ISA generics, memory-region sizes). CHIP_NAME still wins over
# the file's chipName. See docs/chip_configurator.html for the schema.
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
	@echo "  make show         - Show current MCU configuration"
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
	@echo "✅ Generation complete. Outputs:"
	@echo "  • out/software/include/MemoryMap.h, periph.S"
	@echo "  • out/linker-scripts/memory.x, periph.x, *.txt"
	@echo "  • out/hdl/MCU.vhd, MemoryMap.vhd, MCU_routing_template.vhd"
	@echo "  • config/MemoryMap.json"
	@echo "  • latex/TRM/  (LaTeX sources)"

# The full chip: artifacts + the Technical Reference Manual PDF for exactly this
# configuration (chapters, register tables, memory map, and feature list are all
# derived from what python/generate.py instantiates)
chip: generate
	@$(MAKE) --no-print-directory pdf
	@echo ""
	@echo "✅ Chip generation complete — RTL in out/hdl/, TRM at latex/TRM/TRM.pdf"

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
	@echo "Compiling TRM (two pdflatex passes)..."
	@cd latex/TRM && \
		'$(PDFLATEX)' -interaction=nonstopmode TRM.tex > build.log 2>&1 && \
		'$(PDFLATEX)' -interaction=nonstopmode TRM.tex > build.log 2>&1 || \
		{ echo "❌ pdflatex failed — last lines of latex/TRM/build.log:"; tail -25 build.log; exit 1; }
	@grep -E "Output written|^!" latex/TRM/build.log | head -3
	@echo "✅ latex/TRM/TRM.pdf"

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

show config:
	@./show_config.sh

# Clean generated files (Castalia outputs only — NEVER touches the Myshkin toolchain
# files in ../software or ../tools, and keeps latex/TRM/include/*_man.tex wrappers)
clean:
	@echo "⚠️  This removes generated Castalia outputs: out/, config/MemoryMap.json,"
	@echo "    and LaTeX build artifacts in latex/TRM/ (not the _man.tex wrappers)."
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -rf out; \
		rm -f config/MemoryMap.json; \
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
