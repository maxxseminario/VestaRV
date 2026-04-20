# VestaRV Software Build System - Summary

## What Was Implemented

### 1. **Updated Blinky Project**
- ✅ Fixed paths to use `tools/build/` instead of old `build-system/`
- ✅ Added RCF generation with proper binary padding
- ✅ Integrated `flash_prepend.sh` for SPI flash headers
- ✅ Added `flash` and `sim` targets for simulation workflow
- ✅ Fallback to `tools/build/linker-scripts/` if platform files not generated
- ✅ Added helpful make targets and documentation

### 2. **Template Generator Updates**
- ✅ Updated `software/Makefile` template for future projects
- ✅ Includes all RCF generation and flash header logic
- ✅ Proper directory structure (obj/, bin/, rcf/)
- ✅ Help target for user guidance

### 3. **Documentation**
- ✅ Created `software/blinky/README.md` - Project-specific guide
- ✅ Created `software/WORKFLOW.md` - Complete development workflow
- ✅ Includes troubleshooting and examples

## User Workflow

### Simple 3-Step Process:

```bash
# 1. Build the application
cd software/blinky
make all

# 2. Add flash headers for simulation
make flash

# 3. Copy to testbench
make sim
```

### Even Simpler 2-Step:

```bash
make all      # Build
make sim      # Flash + copy (automatically runs 'make flash')
```

## What Gets Generated

| File | Description | Used For |
|------|-------------|----------|
| `bin/blinky.elf` | Executable with debug symbols | GDB debugging |
| `bin/blinky.bin` | Raw binary | Programming flash |
| `bin/blinky.hex` | Intel HEX format | Alternative format |
| `bin/blinky.dump` | Disassembly listing | Code review |
| `bin/blinky_padded.bin` | Padded to full memory | RCF generation |
| `rcf/xxxxxxxxxxxxblinky.rcf` | RCF with flash headers | Xcelium simulation |

## Flash Header Format

The `flash_prepend.sh` script adds SPI flash protocol headers:

```
Line 1: 0x10ADBEEF    - Load segment command
Line 2: 0x00008000    - Start address (RAM base)
Line 3: <end_addr>    - End address (start + program size)
Lines 4-N: <data>     - Actual program binary data
Last line: 0xCAFEBABE - Execute command
```

This matches the serial flash model protocol in `hdl/MCU/tb/serial_flash.vhd`.

## Xcelium Integration

After `make sim`, the RCF file is copied to `verification/isa/rcf/`. 

Update your testbench to load it:

```vhdl
-- In hdl/MCU/tb/tb_defs.vhd or similar:
constant test_files : file_array := (
    "../../../verification/isa/rcf/xxxxxxxxxxxxblinky.rcf",
    -- other test files...
);
```

The filename is padded to 22 characters with leading 'x' characters for consistency.

## Memory Map

| Region | Address | Size | Usage |
|--------|---------|------|-------|
| ROM | 0x0000 | 16KB | Bootloader (TYPE=rom projects) |
| Peripherals | 0x4000 | 4KB | Memory-mapped I/O |
| RAM | 0x8000 | 32KB | Application code + data + stack |

Stack grows downward from 0x10000 (top of RAM).

## Key Files

```
software/
├── Makefile              # Project generator (make new PROJECT=name)
├── WORKFLOW.md           # Complete user guide
├── blinky/              # Example/test project
│   ├── makefile         # Build configuration
│   ├── README.md        # Project-specific guide
│   ├── src/
│   │   ├── main.c       # Application code
│   │   └── start.S      # Startup assembly
│   ├── bin/             # Build outputs
│   └── rcf/             # Simulation files
└── commune/             # Shared library code
    ├── src/
    └── include/
```

## Seamless User Experience

### For Developers:
1. **Write C code** in `src/main.c`
2. **Run `make all`** to build
3. **Run `make sim`** to prepare for simulation

### For Verification Engineers:
- RCF files automatically appear in `verification/isa/rcf/`
- Compatible with existing ISA test infrastructure
- Same flash protocol as verification tests

### For New Projects:
```bash
cd software
make new PROJECT=myapp
cd myapp
# Edit src/main.c
make sim
```

All paths, headers, and scripts are pre-configured!

## Advantages Over Old System

1. **Unified Build System**: Same tools for firmware and verification tests
2. **Automatic Flash Headers**: No manual RCF manipulation needed
3. **Self-Documenting**: `make help` provides guidance
4. **Platform Integration**: Uses platform-generated headers and linker scripts
5. **Flexible**: Falls back to static files if platform not generated

## Testing Checklist

- ✅ Build compiles successfully
- ✅ RCF file generated with correct size (20480 words)
- ✅ Flash headers added correctly (verified 0x10ADBEEF, 0xCAFEBABE)
- ✅ File copied to verification/isa/rcf/
- ✅ Filename padded to 22 characters
- ✅ Documentation complete and accurate

## Next Steps for Users

1. **Try the example**: `cd software/blinky && make sim`
2. **Create your own project**: `make new PROJECT=myproject`
3. **Add peripheral code**: Include `MemoryMap.h` and use defined addresses
4. **Simulate in Xcelium**: Update testbench with your RCF filename
5. **Debug**: Use .dump file and .elf with GDB if needed
