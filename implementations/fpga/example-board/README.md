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
| `//platform/common:chip_artifacts_fpga_default` | The same tree generated from `config/fpga_default.json` - the cut-down bring-up configuration. **Start here, not from Castalia** (see below). |
| `//hdl:vhdl_sources` | Every tracked VHDL source in the repo, as one filegroup. This is a POOL to pick from, **not** a file list to hand a synthesis tool as-is - see "Picking the file set" below. |
| `//software/bootrom_mp:rom_rcf` | The mask-ROM image to preload into block RAM. |
| `//software/blinky:blinky_rcf` (also `gpiotoggle`, `looptest`, `slowblink`, `traptest`) | Demo firmware images, built with the hermetic RISC-V cross-compiler. |

### Which configuration to synthesize

`chip_artifacts_castalia` is the ASIC: five harts, an orchestrator, the AFE and
NPU, a package that bonds a JTAG TAP. It is not the place to start on a board.

`config/fpga_default.json` is the bring-up cut - one hart, no orchestrator, and every
optional peripheral off, chosen so that nothing in the design lacks an FPGA
counterpart. Its `_comment` fields explain why each knob is pinned rather than
inherited, which matters because several generator defaults changed after the
ASIC taped out. Generate it with:

```sh
make -C platform/common generate CONFIG=config/fpga_default.json
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

`hdl/fpga/README.md` is the authority on the substitution set: which files to
drop from `sim/` and `commune/`, which peripheral sources to drop for a given
configuration, where the boot ROM image comes from, what the stand-ins
deliberately do not model (the DCOs produce no clock; retention and power
gating are accepted and ignored), and what is still missing before a bitstream
exists at all - a top level, IOBUF resolution for the bidirectional pads,
constraints, a board clock on the HFXT pad, and a reset held past configuration.

Read it before assembling a project. You do not have to assemble the list by
hand: `//opensource_sim/fpga_default:fpga_default_vivado_files` writes it, in
analysis order, out of the same source sets the GHDL gate analyzes, so the
vendor flow and the simulation flow cannot drift.

`implementations/fpga/synth/` is the worked version of everything below the
"Building" heading: a non-project out-of-context Vivado run with `MCU` as the
top, a clock constraints template, and a 24 MHz MMCM wrapper for the HFXT pad.
It needs no board, and it is where the clock-buffer budget is measured.

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

- **Core**: VestaRV32. `config/fpga_default.json` builds RV32IMA - M and A stay on
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

Out of context, no board needed, from the repo root:

```bash
tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files
vivado -mode batch -nojournal -nolog \
    -source implementations/fpga/synth/vivado_ooc_synth.tcl \
    -tclargs part=<device>
```

For a real board, replace the top: instantiate `MCU`, resolve its bidirectional
pads into IOBUFs, feed `prt1_in(5)` from `implementations/fpga/synth/mmcm_24mhz.vhd`,
and hold `resetn_in` low until the MMCM locks.

```bash
# Board-specific implementation commands
[Add the project-mode or place-and-route commands here]
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
| BUFGCTRL | -    | 32        | - %         |

The clock row is the one that is already accounted for without a tool:
`fpga_default` asks for 27 clock nets, 25 of them generated, against 32 BUFGCTRL
on an Artix-7. The derivation is in `implementations/fpga/synth/README.md`.

## Testing

[Add notes about testing procedures, demo programs, etc.]
