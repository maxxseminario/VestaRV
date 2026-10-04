# FPGA substitution cells

The generated MCU instantiates ASIC macros and cells by name. Each file here is
a synthesizable stand-in under the same entity name, so the generated RTL binds
it with no edits. Configuration: `platform/common/config/fpga_default.json`,
one `rv32imac` hart (compressed is required: the boot ROM is `rv32ic`).

Bring-up procedure: [`implementations/fpga/bringup/`](../../implementations/fpga/bringup/README.md).

## The one rule

`hdl/common/sim/`, `hdl/common/commune/` and this directory declare the same
entities. **Exactly one of each may be in a file list**; with two, the tool
binds whichever it analyzed last, silently. Do not build a file list by hand:
`//opensource_sim/fpga_default:fpga_default_vivado_files` is the Vivado list,
and `_FPGA_SUBS` in `opensource_sim/fpga_default/defs.bzl` makes the swap.

Which `ClkGate` each flow gets:

| Flow | File | Gate |
|---|---|---|
| ASIC (Genus) | `common/commune/ClkGate_cmn65gp_ARM.vhd` | `PREICGX1BA10TH` |
| Simulation | `common/sim/ClkGate.vhd` | latch + AND |
| FPGA, Vivado | `fpga/ClkGate.vhd` + `ClockPrimitives_xilinx.vhd` | `BUFGCE` |
| FPGA, GHDL | `fpga/ClkGate.vhd` + `ClockPrimitives_generic.vhd` | latch + AND |

## Files

| File | Replaces | Why |
|---|---|---|
| `ClockPrimitives.vhd` | — | Declares `ClkBufEn` and `ClkBuf` |
| `ClockPrimitives_xilinx.vhd` | — | `BUFGCE` / `BUFG`. Vivado only |
| `ClockPrimitives_generic.vhd` | — | Latch + AND / wire. GHDL and non-Xilinx flows; pair of the above |
| `ClkGate.vhd` | `sim/ClkGate.vhd` | A `ClkBufEn` instead of an inferred latch |
| `ClockMuxGlitchFree.vhd` | `sim/ClockMuxGlitchFree.vhd` | Fabric mux into one buffer; the ASIC mux costs a clock net per input |
| `ClkDivPower2.vhd` | `commune/ClkDivPower2.vhd` | One enable-qualified counter instead of a ripple chain of clock nets |
| `ARM_IP_RAM.vhd` | `sim/ARM_IP_RAM.vhd` | Infers block RAM |
| `ARM_IP_ROM.vhd` | `sim/ARM_IP_ROM.vhd` | Block RAM initialized from `rom.rcf` in the working directory |
| `analog_stubs.vhd` | `sim/` glitch filter, POR and oscillator models | Synthesizable stubs |

## Clock budget

`fpga_default` uses 27 global clock buffers (25 generated, 2 pads) of the 32 on
an Artix-7. Each `ClkGate` costs one `BUFGCE`, so larger configurations need an
UltraScale+ part. Details: `implementations/fpga/synth/README.md`.

## Differences from the ASIC

- Switching MCLK or SMCLK between HFXT and LFXT can glitch; do it only at reset.
- A divided clock is the source clock passed one cycle in 2^N, not a square wave.
- The DCOs output nothing; firmware that selects a DCO hangs the board.
- `RETN`, `PGEN` and `EMA` are ignored, so memory power-down does nothing.

## Checks

```
tools/bin/bazel test //opensource_sim/fpga_default:fpga_default_elaborate \
    //platform/common:fpga_default_generation_test \
    //implementations/fpga/bringup:fpga_flash_boot
```
Elaboration, configuration generation, and a full boot from SPI flash. GHDL is
not a synthesis tool, so none of these shows that Vivado infers block RAM.
