#!/bin/bash
# Regenerate all Castalia (4-hart multi-core) RISC-V microcontroller toolchain files
# This script regenerates headers, linker scripts, and documentation

set -e  # Exit on error

echo "=========================================="
echo "VestaRV Toolchain Generator"
echo "=========================================="
echo ""

# Navigate to generator/python directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR/python"

echo "Generating toolchain files from generate.py..."
echo ""

# Run the generator
python3 generate.py

echo ""
echo "=========================================="
echo "✅ Toolchain generation complete!"
echo "=========================================="
echo ""
echo "Generated files:"
echo "  • out/software/include/MemoryMap.h"
echo "  • out/software/include/periph.S"
echo "  • out/linker-scripts/memory.x"
echo "  • out/linker-scripts/periph.x"
echo "  • out/linker-scripts/*.txt"
echo "  • config/MemoryMap.json"
echo "  • latex/TRM/"
echo ""
echo "Next steps:"
echo "  1. Rebuild firmware: (Castalia firmware build TBD)"
echo "  2. Run verification: cd ../xcelium/riscv_test/behavioral_mp && ./xrun_parallel.sh"
echo "  3. Generate PDF docs: cd latex/TRM && pdflatex TRM.tex"
echo ""
