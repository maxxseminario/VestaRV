# VESTA RISC-V Core Block Diagram

This directory contains block diagram sources for the VESTA RV32IMAC CPU core.

## Files

- `vesta_block_diagram.tex` - Professional TikZ/LaTeX block diagram (recommended for presentations)
- `vesta_block_diagram_simple.md` - Mermaid-based diagram (for quick visualization)

## Compiling the LaTeX Diagram

### Option 1: Using pdflatex (requires LaTeX installation)
```bash
cd generator/latex/block-diagram
pdflatex vesta_block_diagram.tex
```

### Option 2: Using latexmk (recommended)
```bash
latexmk -pdf vesta_block_diagram.tex
```

### Option 3: Online (no installation needed)
1. Go to [Overleaf](https://www.overleaf.com)
2. Create a new project
3. Copy the contents of `vesta_block_diagram.tex`
4. Click "Recompile"
5. Download the PDF

## Mermaid Diagram

The Mermaid diagram in `vesta_block_diagram_simple.md` can be viewed:
- Directly on GitHub (renders automatically)
- In VS Code with Mermaid preview extension
- At [Mermaid Live Editor](https://mermaid.live)

## Architecture Overview

The VESTA core implements the RV32IMAC instruction set:

| Extension | Description |
|-----------|-------------|
| **I** | Base Integer ISA |
| **M** | Multiply/Divide |
| **A** | Atomic Operations (LR/SC, AMO) |
| **C** | Compressed Instructions (16-bit) |
| **Zicsr** | Control/Status Registers |

### Main Components

1. **Controller** - Instruction decoding and control signal generation
   - Main Decoder (maindec.vhd)
   - ALU Decoder (aludec.vhd) 
   - Branch Validation (branch_valid.vhd)

2. **Datapath** - Data processing and register operations
   - Register File (regfile.vhd) - 32 x 32-bit registers
   - ALU (alu.vhd) - Arithmetic/Logic operations
   - Divider (div.vhd) - Multi-cycle division
   - Extend (extend.vhd) - Immediate generation
   - Load/Store Extensions (loadext.vhd, store_ext.vhd)

3. **IRQ Handler** - Interrupt management with priority and nesting
   - Supports configurable number of IRQs
   - Priority levels
   - Nested interrupt support

4. **C_DEC** - Compressed instruction decoder (RVC)
   - Expands 16-bit instructions to 32-bit

5. **CSR Unit** - Control/Status Register management
   - Performance counters
   - System configuration

### Features
- Single-cycle execution for most instructions
- Multi-cycle division
- Clock gating for power management
- Atomic memory operations (LR/SC, AMO)
- Fast interrupt handling with context save/restore
