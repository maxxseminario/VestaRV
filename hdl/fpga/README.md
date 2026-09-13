# FPGA substitution cells

The MCU is generated for an ASIC, so it instantiates compiled memory macros and
analog cells by name. None of those exist on an FPGA. This directory holds a
synthesizable stand-in for each one, under the same entity name, so the
generated `MCU.vhd` binds them without a single edit to generated RTL.

## The bring-up cut at a glance

The configuration is [`platform/common/config/fpga.json`](../../platform/common/config/fpga.json):
the smallest VestaRV that still runs the boot ROM, cut down for an FPGA rather
than for area.

| | |
|---|---|
| Board | **None is tracked.** No device, constraints file or bitstream exists in this repository; [`implementations/fpga/example-board/`](../../implementations/fpga/example-board/README.md) is an unfilled template for the first port. **The RTL is the deliverable.** |
| Top entity | `MCU`. `chipName` is documentation only: the emitted top is `entity MCU` in every configuration, because the name is fixed template text in `hdl_templates/MCU.template.vhd`. |
| Harts | 1, an ordinary `hart_tile` (`orchestrator` is pinned false), `rv32ima`. |
| Clock | One board clock on the **HFXT pad**. `SYS_CLK_CR` resets to zero, which selects `clk_hfxt` for both MCLK and SMCLK, so the chip runs from that pad out of reset and needs no PLL. Every bench in the tree models it at **24 MHz** with UART0 at 115200 baud. |
| Boot ROM | 8192 B, one `rom2k_hvt_pg` (2048 x 32). |
| TCM | 8192 B for the one hart, one `sram1p8k_hvt_pg`. |
| Shared RAM | 65536 B, four `sram1p16k_hvt_pg` (4096 x 32 each). |
| Pin constraints | **None is tracked.** `config/PadRing.json` in the generated artifacts is the 44-pin QFN-44 signal list an `.xdc` or `.sdc` is written from; it names every pin, its alternate functions and its power domain. |
| Generate | `tools/bin/bazel build //platform/common:chip_artifacts_fpga` |
| Gates | `//platform/common:fpga_generation_test`, `//opensource_sim/fpga:fpga_elaborate` |

The ROM and TCM depths are contracts, not suggestions: the generated `MCU.vhd`
asserts `RomAddrBits = RomMacroAddrBits` and `hart_tile.vhd:839` asserts
`RamSize = 8192`, both concurrently, so block RAMs built to other depths fail at
time zero rather than on the board.

## The one rule

`hdl/common/sim/` and `hdl/fpga/` declare the same entities. **Exactly one of
the two may appear in any file list.** Compile both and the tool picks whichever
architecture it analyzed last, which is a silent way to end up simulating the
FPGA cells or synthesizing the simulation ones.

For a synthesis or implementation run, take all of `hdl/common/`, plus all of
`hdl/fpga/`, plus the generated `platform/common/out/hdl/`, with two subtractions:

- **From `hdl/common/sim/`, keep only `ClockMuxGlitchFree.vhd`.** It sits in that
  directory but it is ordinary synthesizable RTL, it is the break-before-make clock
  mux `SYSTEM.vhd` instantiates, and `hdl/fpga/` does not replace it. The other
  six files in that directory are the ones this one supersedes.
- **Leave out the peripheral sources your configuration disables.** A disabled
  block's RTL refers to `MemoryMap` constants that are only emitted when the block
  is enabled, so compiling it fails outright. With `fpga.json` that means
  `common/periph/NPU.vhd`.

One further split, and it runs the other way: `common/periph/TrngRoEnsemble.vhd`
is the real ring oscillator and is what a synthesis run compiles, while
`TrngRoEnsemble_sim.vhd` is the behavioural model a simulator needs. They
declare the same entity and must never be co-listed either.

## What is here

| File | Replaces | Why the simulation model will not do |
|---|---|---|
| `ClkGate.vhd` | `sim/ClkGate.vhd` | the simulation gate is a level-sensitive latch, which Vivado infers as a real latch on every gated clock path; this one captures the enable in a falling-edge flip-flop |
| `ARM_IP_RAM.vhd` | `sim/ARM_IP_RAM.vhd` | the simulation model clears the whole array asynchronously while `PGEN` is high, and no block RAM can do that, so the tool builds the memory from distributed RAM and flip-flops instead |
| `ARM_IP_ROM.vhd` | `sim/ARM_IP_ROM.vhd` | the simulation model loads its array from a process that runs at time zero, which synthesis cannot do, and it hardcodes an absolute path to the image |
| `analog_stubs.vhd` | `sim/GlitchFilter_behav.vhd`, `sim/PowerOnResetCheng_behav.vhd`, `sim/OscillatorCurrentStarved_simulation.vhd` | the oscillator model drives its clock from `wait for` statements |

## Boot ROM image

`rom2k_hvt_pg` takes the image path as a generic, `InitFile`, defaulting to
`rom.rcf` in the tool's working directory. The image is
`software/bootrom_mp/bin/rom.rcf`, one 32-bit binary word per line. Either copy
it next to the project, or pass an absolute path as a synthesis generic. If the
file cannot be opened, synthesis still completes and warns, and the ROM reads as
all zeros; a core that fetches nothing but zeros is what that looks like on the
board.

## What these cells do not model

- **The DCOs produce no clock.** The output is tied low. This is safe out of
  reset because `SYS_CLK_CR` resets to zero, which selects `clk_hfxt` for both
  MCLK and SMCLK, so the chip runs from the HFXT pad. Firmware that selects a
  DCO as a clock source will stop the clock it is running on and hang the board.
- **Interrupt inputs are not filtered or synchronized.** The `GlitchFilter`
  entity has no clock port, so no digital filter fits behind that interface.
  Metastability hardening belongs in the top level's pad logic.
- **The TRNG entropy source is a combinational ring.** Nothing in this
  directory stands in for it, and `peripherals.trng` reaches this configuration
  true. `TrngRoEnsemble.vhd` closes `RING_STAGES` inverter loops that a place
  and route tool will either break or refuse to route until told otherwise, and
  an FPGA ring is not a characterized entropy source in any case. Either turn
  the block off for the board or constrain the loops by hand.
- **Retention and power gating do nothing.** `RETN`, `PGEN` and `EMA` are
  accepted and ignored. Memory contents survive a power-down the power
  controller thinks it performed, so a `MEMPWRCR` sequence measured on this
  target does not tell you what silicon will do.

## Still needed before a bitstream

These cells make the generated MCU synthesizable. They are not a complete FPGA
target on their own. Still missing: a top level that instantiates `MCU` and
resolves its bidirectional pads into IOBUFs, a constraints file, a board clock
driving the HFXT pad, a reset that is held long enough after configuration, and
external wiring for the SPI flash the boot sequence expects.

## Checking the set without a synthesis tool

`tools/bin/bazel test //opensource_sim/fpga:fpga_elaborate` is the check, and it
needs no FPGA tool and no license. It analyzes the generated one-hart `MCU.vhd`
and `MemoryMap.vhd` out of `//platform/common:chip_artifacts_fpga` with this
directory substituted for `hdl/common/sim/`, and runs the result for 1 ns. A
pass means every stand-in binds by name and the three memory depths above hold.
It runs in about a second and is wired into
[`.github/workflows/sim.yml`](../../.github/workflows/sim.yml).

`//platform/common:fpga_generation_test` sits one layer below it and is what
keeps `config/fpga.json` from rotting against a knob rename: the configuration
still generates and its machine-readable outputs still parse. There is no
determinism gate for this configuration; `:generation_determinism_test` and
`:castalia_b_generation_determinism_test` cover the default and all-on
generations only.

GHDL is not a synthesis tool, so neither gate says Vivado infers block RAM from
these arrays. The equivalent check under a commercial elaborator, for when one
is available:

```sh
tools/bin/bazel build //platform/common:chip_artifacts_fpga
source cdspaths.sh
xrun -64bit -V200X -licqueue -elaborate -top MCU -f <file list>
```

The file list is `xcelium/riscv_test/behavioral_mp/cell_list_behavioral.txt` with
the six `sim/` cells above swapped for this directory's, `common/periph/NPU.vhd`
dropped, the testbench lines dropped, and `hdl/common/MCU.vhd` and
`MemoryMap.vhd` pointed at the generated tree. Elaboration binds the FPGA
architectures by name, so the log line for `rom0` reads
`rom2k_hvt_pg(fpga):rom@rom_hvt_pg(fpga)` when the swap took.
