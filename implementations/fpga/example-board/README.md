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
| `//platform/common:chip_artifacts_fpga` | The same tree generated from `config/fpga.json` - the cut-down bring-up configuration. **Start here, not from Castalia** (see below). |
| `//hdl:vhdl_sources` | Every tracked VHDL source in the repo, as one filegroup. This is a POOL to pick from, **not** a file list to hand a synthesis tool as-is - see "Picking the file set" below. |
| `//software/bootrom_mp:rom_rcf` | The mask-ROM image to preload into block RAM. |
| `//software/blinky:blinky_rcf` (also `gpiotoggle`, `looptest`, `slowblink`, `traptest`) | Demo firmware images, built with the hermetic RISC-V cross-compiler. |

### Which configuration to synthesize

`chip_artifacts_castalia` is the ASIC: five harts, an orchestrator, the AFE and
NPU, a package that bonds a JTAG TAP. It is not the place to start on a board.

`config/fpga.json` is the bring-up cut - one hart, no orchestrator, and every
optional peripheral off, chosen so that nothing in the design lacks an FPGA
counterpart. Its `_comment` fields explain why each knob is pinned rather than
inherited, which matters because several generator defaults changed after the
ASIC taped out. Generate it with:

```sh
make -C platform/common generate CONFIG=config/fpga.json
# then, to put out/ and the tracked resolved config back to Castalia:
make -C platform/common generate
```

### Picking the file set

The generated `MCU.vhd` instantiates compiled memory macros and analog cells by
name, and none of them exist on an FPGA. `hdl/fpga/` holds a synthesizable
stand-in for each, under the same entity name, so the generated RTL binds them
with no edits.

**`hdl/common/sim/` and `hdl/fpga/` declare the same entities, and exactly one
of the two may appear in any file list.** Compile both - which is what handing a
tool all of `//hdl:vhdl_sources` does - and the tool binds whichever
architecture it analyzed last. That is a silent way to synthesize the simulation
cells, and the simulation ROM alone hardcodes an absolute image path and loads
its array in a time-zero process.

`hdl/fpga/README.md` is the authority on the substitution set: which single file
to keep from `sim/`, which peripheral sources to drop for a given
configuration, where the boot ROM image comes from, what the stand-ins
deliberately do not model (the DCOs produce no clock; retention and power
gating are accepted and ignored), and what is still missing before a bitstream
exists at all - a top level, IOBUF resolution for the bidirectional pads,
constraints, a board clock on the HFXT pad, and a reset held past configuration.

Read it before assembling a project.

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

- **Core**: VestaRV32. `config/fpga.json` builds RV32IMA - M and A stay on
  because every firmware image in `software/` is compiled `-march=rv32ima`;
  C and Zb are off because rv32ima uses neither.
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
