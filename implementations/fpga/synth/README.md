# FPGA synthesis: the clocking, the budget, and the run

The bring-up cut generates and elaborates, but until this directory existed
nothing said whether a synthesizer could build it. The answer turned on one
number: an Artix-7 has **32 BUFGCTRL sites**, and the design as drawn for the
ASIC asks for 43 clock nets.

**No board is tracked here.** `vivado_ooc_synth.tcl` runs out of context with
`MCU` as the top, which needs no device pins and no constraints file beyond the
clock structure, and produces the clock-resource report the budget is read from.
`implementations/fpga/example-board/` is still the template for an actual port.

## The budget, before and after

Counted mechanically over the generated `MCU.vhd` plus every entity it
instantiates, with the instance multiplicity of `config/fpga_default.json`
(SYSTEM x1, GPIO x6, SPI x1, UART x1, I2C x1, TIMER x1, hart_tile x1). A
"generated clock net" is a net that reaches a flip-flop clock pin and is not a
primary input.

| Block | Before | After | What changed |
|---|---|---|---|
| SYSTEM | 23 | 9 | the two divider muxes stop clocking flops from 14 ripple taps |
| TIMER | 4 | 4 | - |
| SPI | 3 | 3 | - |
| UART | 3 | 3 | - |
| I2C | 3 | 1 | the divider is one enable-qualified counter, not a ripple chain |
| adddec | 2 | 2 | - |
| hart_tile | 2 | 2 | - |
| vesta | 1 | 1 | - |
| GPIO x6 | 0 | 0 | - |
| **Generated** | **41** | **25** | |
| Primary (HFXT, LFXT pads) | 2 | 2 | |
| **Total** | **43** | **27** | against 32 BUFGCTRL |

The two DCO branches are already absent from both columns: `analog_stubs.vhd`
ties the oscillator outputs to '0', so four nets constant-fold.

The lever is not the clock GATE, which costs one buffer either way. It is the
clock MUX. The ASIC `ClockMuxGlitchFree` gives every slice three flip-flops and
a PREICG gate clocked by THAT SLICE'S input, so all eight inputs of each divider
mux are flop clock pins even though seven of them are never selected.
`hdl/fpga/ClockMuxGlitchFree.vhd` puts the interlock in fabric and the
multiplexing in one clock buffer; the fourteen ripple taps become data nets.

What that costs is stated in the cell's header and repeated in
`hdl/fpga/README.md`: the FPGA mux is not glitch-free across asynchronous
sources. Switching MCLK or SMCLK between HFXT and LFXT on this target is a
reset-time operation, not a running one. The two DIVIDER muxes are safe as
drawn, because every input is a tap of input 0.

## Running it

```sh
tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files
vivado -mode batch -nojournal -nolog \
    -source implementations/fpga/synth/vivado_ooc_synth.tcl
```

Both from the repo root: the manifest's paths are exec-root relative, which is
workspace-root relative once `bazel-out` resolves. Knobs go through
`-tclargs part=... outdir=...`; the defaults are an `xc7a100tcsg324-1` and
`build/fpga_default_ooc`.

Reports land in the output directory: `utilization.rpt`,
`clock_utilization.rpt` (the one the table above is checked against),
`clock_networks.rpt`, `clock_interaction.rpt` and `drc.rpt`.

**Not run in this repository.** No Vivado, Yosys or nextpnr install is reachable
from this host, so the table above is a static count and not a synthesis result.
The check that DOES run is
`tools/bin/bazel test //opensource_sim/fpga_default:fpga_default_elaborate`,
which binds the substituted file set under GHDL. GHDL is not a synthesis tool
and says nothing about buffer counts.

## Why the file list comes out of Bazel

`hdl/common/sim/`, `hdl/common/commune/` and `hdl/fpga/` declare the same
entities, `entity work.x` binds at ANALYSIS, and a tool handed the whole of
`//hdl:vhdl_sources` binds whichever architecture it read last. The order is
therefore part of the design, and
`//opensource_sim/fpga_default:fpga_default_vivado_files` writes the same order a
`ghdl_test` analyzes, out of the same source sets, so the two cannot drift. Do
not glob for sources and do not sort the list.

One file differs between the two: `hdl/fpga/ClockPrimitives_generic.vhd` for
GHDL, `hdl/fpga/ClockPrimitives_xilinx.vhd` for Vivado. They declare the same
two architectures, the second out of BUFGCE and BUFG. Exactly one may appear in
a file list, and the manifest picks the Xilinx one.

## What is here

| File | What it is |
|---|---|
| `vivado_ooc_synth.tcl` | the non-project out-of-context run |
| `fpga_default_ooc.xdc` | clock constraints: 2 primaries, 5 multiplexed generated clocks with their exclusivity groups, 18 BUFGCE-derived ones listed but deliberately not declared, and the two fabric muxes that have no buffer of their own |
| `mmcm_24mhz.vhd` | board clock source, any oscillator in and 24 MHz out to the HFXT pad. Vivado only, not in any file list, not used by the out-of-context run |

## Still missing before a bitstream

Unchanged from `hdl/fpga/README.md`: a top level that instantiates `MCU` and
resolves its bidirectional pads into IOBUFs, a device and a pinout, a reset held
past configuration, and external wiring for the SPI flash the boot sequence
expects. This directory adds the clocking and the synthesis recipe, not those.
