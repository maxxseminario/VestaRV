#!/bin/bash
# Show current VestaRV MCU configuration summary

echo "=========================================="
echo "VestaRV MCU Configuration Summary"
echo "=========================================="
echo ""

# Navigate to script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Extract info from MemoryMap.json if it exists
if [ -f "config/MemoryMap.json" ]; then
    CHIP_NAME=$(grep -m1 '"ChipName"' config/MemoryMap.json | sed 's/.*"ChipName": "\(.*\)".*/\1/')
    echo "Current Implementation: $CHIP_NAME"
    echo ""
    
    echo "Memory Layout:"
    ROM_START=$(grep -m1 '"RomStartAddress"' config/MemoryMap.json | grep -o '[0-9]*')
    ROM_END=$(grep -m1 '"RomEndAddress"' config/MemoryMap.json | grep -o '[0-9]*')
    ROM_SIZE=$(grep -m1 '"RomSize"' config/MemoryMap.json | grep -o '[0-9]*')
    RAM_START=$(grep -m1 '"RamStartAddress"' config/MemoryMap.json | grep -o '[0-9]*')
    RAM_END=$(grep -m1 '"RamEndAddress"' config/MemoryMap.json | grep -o '[0-9]*')
    RAM_SIZE=$(grep -m1 '"RamSize"' config/MemoryMap.json | grep -o '[0-9]*')
    PERIPH_START=$(grep -m1 '"PeripheralMemoryStartAddress"' config/MemoryMap.json | grep -o '[0-9]*')
    PERIPH_END=$(grep -m1 '"PeripheralMemoryEndAddress"' config/MemoryMap.json | grep -o '[0-9]*')
    SP_INIT=$(grep -m1 '"StackPointerInit"' config/MemoryMap.json | grep -o '[0-9]*')
    
    printf "  ROM:        0x%05X - 0x%05X (%d bytes)\n" "$ROM_START" "$ROM_END" "$ROM_SIZE"
    printf "  Peripheral: 0x%05X - 0x%05X\n" "$PERIPH_START" "$PERIPH_END"
    printf "  RAM:        0x%05X - 0x%05X (%d bytes)\n" "$RAM_START" "$RAM_END" "$RAM_SIZE"
    printf "  Stack Init: 0x%05X\n" "$SP_INIT"
    echo ""
    echo "  ⚠️  Final RAM block is DMA to NPU. If using NPU, move stack pointer"
    echo "     to avoid conflict with DMA transfers."
    echo ""
    
    echo "CPU Configuration:"
    grep -q '"COMPRESSED_ISA": true' config/MemoryMap.json && echo "  ✓ RV32IC (compressed instructions)" || echo "  ✗ RV32I only"
    grep -q '"ENABLE_MUL": true' config/MemoryMap.json && echo "  ✓ M extension (multiply/divide)" || echo "  ✗ No multiply/divide"
    echo "  ✓ Recursive interrupt handling"
    grep -q '"ENABLE_IRQ_FAST_CONTEXT_SWITCHING": true' config/MemoryMap.json && echo "  ✓ Fast interrupt context switching" || echo "  ○ Standard interrupt context switching"
    echo ""
    
    echo "Peripherals:"
    grep -A1 '"Name"' config/MemoryMap.json | grep '"Name"' | sed 's/.*"Name": "\(.*\)".*/  • \1/' | head -20
    echo ""
    
    PERIPH_COUNT=$(grep -c '"Name"' config/MemoryMap.json)
    VECTOR_COUNT=$(grep -m1 '"VectorsCount"' config/MemoryMap.json | grep -o '[0-9]*')
    echo "Total Peripherals: $PERIPH_COUNT"
    echo "Interrupt Vectors: $VECTOR_COUNT"
    echo ""
else
    echo "⚠️  MemoryMap.json not found. Run ./regenerate.sh first."
    echo ""
fi

echo "Source of truth: python/generate.py"
echo "Documentation:   README.md"
echo ""
echo "To regenerate:   make  (or ./regenerate.sh)"
echo "=========================================="
