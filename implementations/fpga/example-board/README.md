# Example FPGA Board Implementation

This is a template directory for documenting an FPGA implementation of VestaRV.

## Building through Bazel

The RTL, headers, linker scripts and firmware images that go into a bitstream
are all Bazel-managed; the vendor synthesis itself is not (see below). Run all
commands below **from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### What Bazel produces for a board port

| Target | What it produces |
|--------|------------------|
| `//platform/common:chip_artifacts_castalia` | The chip artifact tree your port instantiates: `MCU.vhd`, `MemoryMap.vhd`, `MemoryMap.h`, `periph.S`, linker scripts, pad-ring JSON/TCL. |
| `//platform/common:castalia_hdl` | Just the generated RTL half of that tree. |
| `//platform/common:castalia_software_include`, `//platform/common:castalia_linker_scripts` | The firmware-facing half. |
| `//hdl:vhdl_sources` | Every tracked VHDL source in the repo, as one filegroup - the file set your vendor project should read. |
| `//software/bootrom_mp:rom_rcf` | The mask-ROM image to preload into block RAM. |
| `//software/blinky:blinky_rcf` (also `gpiotoggle`, `looptest`, `slowblink`, `traptest`) | Demo firmware images, built with the hermetic RISC-V cross-compiler. |

Never run `bazel run //:generate` - that is the raw generator and it writes
wherever it happens to be invoked. The hermetic path is
`//platform/common:chip_artifacts_castalia`.

### Gates worth running before you build a bitstream

| Target | What it proves |
|--------|----------------|
| `//opensource_sim:isa_regression` | Nine GHDL ISA suites (`//opensource_sim:isa_rv32ui` and siblings) over the same RTL. License-free. |
| `//hdl/common/tb:mp_arbiter_tb`, `//hdl/common/tb:pmp_unit_tb` | The shared-bus arbiter and PMP unit benches, under GHDL. |
| `//software/blinky:blinky_flashed_rcf_test` | The demo image is byte-identical to its tracked golden. |
| `//software/bootrom_mp:rom_rcf_reproducibility_test` | The boot ROM image is byte-identical to its tracked golden. |
| `//platform/common:check_mcu_vhd_test` | The generated `MCU.vhd` matches the tracked drop-in RTL you are synthesizing. |

### Out-of-Bazel path

Vendor synthesis and programming (Vivado, Quartus, and the board programmer)
stay outside Bazel - proprietary installs. Run them as documented under
"Building" and "Programming the FPGA" below; feed them the Bazel-built RTL and
firmware images above.

Full map of the Bazel build: [`BAZEL.md`](../../../BAZEL.md).

## Overview

- **FPGA Board**: Example Board
- **FPGA Device**: [e.g., Xilinx Artix-7 100T, Intel Cyclone V]
- **Target Application**: [e.g., prototype, development board, demo]

## Configuration

- **Core**: VestaRV32 (RV32IMAC + Zb*)
- **ROM Size**: [e.g., 16 KiB, implemented in block RAM]
- **RAM Size**: [e.g., 32 KiB, implemented in block RAM]
- **Clock Frequency**: [e.g., 50 MHz]
- **Peripherals**:
  - GPIO: Connected to LEDs, switches, buttons
  - UART: Connected to USB-UART bridge
  - SPI: Connected to [specify]
  - [List other peripherals and their board connections]

## Pin Assignments

| Signal | FPGA Pin | Board Connection |
|--------|----------|------------------|
| CLK    | [pin]    | [description]    |
| UART_TX| [pin]    | USB-UART         |
| UART_RX| [pin]    | USB-UART         |
| LED[0] | [pin]    | LED 0            |
| ...    | ...      | ...              |

## Directory Contents

- **`docs/`** — User guide, setup instructions
- **`config/`** — Configuration files and constraint files (.xdc, .sdc)
- **`images/`** — Block diagram, pinout diagram
- **`bitstreams/`** — Pre-built bitstream files

## Building

```bash
# Synthesis tool commands
[Add vivado/quartus commands here]
```

## Programming the FPGA

```bash
# Programming commands
[Add programming instructions]
```

## Resource Utilization

| Resource | Used | Available | Utilization |
|----------|------|-----------|-------------|
| LUTs     | -    | -         | - %         |
| FFs      | -    | -         | - %         |
| BRAM     | -    | -         | - %         |
| DSP      | -    | -         | - %         |

## Testing

[Add notes about testing procedures, demo programs, etc.]
