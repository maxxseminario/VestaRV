# FPGA substitution cells

Synthesizable stand-ins for the ASIC macros and cells, under the same entity
names, for the `fpga_default` configuration (one `rv32imac` hart).

**Exactly one file per entity may be in a file list.** `hdl/common/sim/`,
`hdl/common/commune/` and this directory declare the same entities; with two,
the tool silently binds the last one analyzed. Use
`//opensource_sim/fpga_default:fpga_default_vivado_files`, never a hand-built list.

| Flow | `ClkGate` file | Gate |
|---|---|---|
| ASIC (Genus) | `common/commune/ClkGate_cmn65gp_ARM.vhd` | `PREICGX1BA10TH` |
| Simulation | `common/sim/ClkGate.vhd` | latch + AND |
| FPGA, Vivado | `fpga/ClkGate.vhd` + `ClockPrimitives_xilinx.vhd` | `BUFGCE` |
| FPGA, GHDL | `fpga/ClkGate.vhd` + `ClockPrimitives_generic.vhd` | latch + AND |

Also here: clock mux, clock divider, ROM/RAM (block RAM; the ROM loads `rom.rcf`
from the working directory) and analog stubs.

Differs from the ASIC: switch MCLK/SMCLK sources only at reset; divided clocks
are gated pulses; the DCOs output nothing (selecting one hangs the board);
memory power-down does nothing.

Check: `tools/bin/bazel test //opensource_sim/fpga_default:all //implementations/fpga/bringup:all`.
Synthesis: [`implementations/fpga/synth/`](../../implementations/fpga/synth/README.md).
Bring-up: [`implementations/fpga/bringup/`](../../implementations/fpga/bringup/README.md).
