#!/bin/bash
# Regenerate all Myshkin RISC-V microcontroller toolchain files
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
echo "  • ../../software/commune/include/MemoryMap.h"
echo "  • ../../software/commune/include/periph.S"
echo "  • ../../tools/build/linker-scripts/memory.x"
echo "  • ../../tools/build/linker-scripts/periph.x"
echo "  • ../../tools/build/linker-scripts/*.txt"
echo "  • config/MemoryMap.json"
echo "  • latex/MCU-User-Guide/"
echo ""
echo "Next steps:"
echo "  1. Rebuild firmware: cd ../../software && make clean && make"
echo "  2. Run verification: cd ../../verification/isa && make"
echo "  3. Generate PDF docs: cd latex/MCU-User-Guide && pdflatex MCU-User-Guide.tex"
echo ""
