# VestaRV Toolchain Generator Makefile
# Automates generation of headers, linker scripts, and documentation

.PHONY: all help generate show config clean pdf install-deps

# Default target
all: generate

# Help target - show available commands
help:
	@echo "=========================================="
	@echo "VestaRV Toolchain Generator"
	@echo "=========================================="
	@echo ""
	@echo "Available targets:"
	@echo "  make              - Regenerate all toolchain files (default)"
	@echo "  make generate     - Regenerate all toolchain files"
	@echo "  make show         - Show current MCU configuration"
	@echo "  make config       - Alias for 'make show'"
	@echo "  make pdf          - Compile LaTeX documentation to PDF"
	@echo "  make clean        - Remove generated files"
	@echo "  make install-deps - Check Python/LaTeX dependencies"
	@echo "  make help         - Show this help message"
	@echo ""
	@echo "Source of truth: python/generate.py"
	@echo "Documentation:   README.md"
	@echo "=========================================="

# Generate all toolchain files
generate:
	@echo "=========================================="
	@echo "VestaRV Toolchain Generator"
	@echo "=========================================="
	@echo ""
	@echo "Generating toolchain files from generate.py..."
	@echo ""
	@cd python && python3 generate.py
	@echo ""
	@echo "=========================================="
	@echo "✅ Toolchain generation complete!"
	@echo "=========================================="
	@echo ""
	@echo "Generated files:"
	@echo "  • ../../software/commune/include/MemoryMap.h"
	@echo "  • ../../software/commune/include/periph.S"
	@echo "  • ../../tools/build/linker-scripts/memory.x"
	@echo "  • ../../tools/build/linker-scripts/periph.x"
	@echo "  • ../../tools/build/linker-scripts/*.txt"
	@echo "  • config/MemoryMap.json"
	@echo "  • latex/TRM/"
	@echo ""

# Show current configuration
show config:
	@./show_config.sh

# Compile PDF documentation
pdf:
	@echo "=========================================="
	@echo "Compiling Technical Reference Manual (TRM) PDF"
	@echo "=========================================="
	@echo ""
	@if [ ! -d "latex/TRM" ]; then \
		echo "⚠️  LaTeX files not generated. Run 'make generate' first."; \
		exit 1; \
	fi
	@cd latex/TRM && \
		pdflatex -interaction=nonstopmode TRM.tex > /dev/null 2>&1; \
		pdflatex -interaction=nonstopmode TRM.tex > /dev/null 2>&1; \
		if [ -f TRM.pdf ]; then \
			echo "✅ PDF compiled successfully: latex/TRM/TRM.pdf"; \
			ls -lh TRM.pdf | awk '{print "   Size: " $$5 ", Pages: (see PDF)"}'; \
		else \
			echo "❌ PDF compilation failed"; \
			exit 1; \
		fi
	@echo ""
	@echo ""

# Clean generated files (WARNING: This removes toolchain files!)
clean:
	@echo "⚠️  WARNING: This will remove ALL generated toolchain files!"
	@echo "Files to be removed:"
	@echo "  • ../../software/commune/include/MemoryMap.h"
	@echo "  • ../../software/commune/include/periph.S"
	@echo "  • ../../tools/build/linker-scripts/memory.x"
	@echo "  • ../../tools/build/linker-scripts/periph.x"
	@echo "  • config/MemoryMap.json"
	@echo "  • latex/TRM/"
	@echo ""
	@read -p "Are you sure? [y/N] " -n 1 -r; \
	echo; \
	if [[ $$REPLY =~ ^[Yy]$$ ]]; then \
		rm -f ../../software/commune/include/MemoryMap.h; \
		rm -f ../../software/commune/include/periph.S; \
		rm -f ../../tools/build/linker-scripts/memory.x; \
		rm -f ../../tools/build/linker-scripts/periph.x; \
		rm -f ../../tools/build/linker-scripts/*.txt; \
		rm -f config/MemoryMap.json; \
		rm -rf latex/TRM; \
		echo "✅ Cleaned generated files"; \
	else \
		echo "❌ Clean cancelled"; \
	fi

# Check dependencies
install-deps:
	@echo "=========================================="
	@echo "Checking Dependencies"
	@echo "=========================================="
	@echo ""
	@echo "Python 3:"
	@which python3 > /dev/null && python3 --version || echo "  ❌ Python 3 not found"
	@echo ""
	@echo "LaTeX (for PDF generation):"
	@which pdflatex > /dev/null && pdflatex --version | head -1 || echo "  ⚠️  pdflatex not found (optional, needed for PDF generation)"
	@echo ""
	@echo "Required Python packages: (none - stdlib only)"
	@echo ""
	@echo "To install LaTeX on Ubuntu/Debian:"
	@echo "  sudo apt-get install texlive-latex-base texlive-latex-extra"
	@echo ""
	@echo "To install LaTeX on macOS:"
	@echo "  brew install --cask mactex"
	@echo ""
