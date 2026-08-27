# FPGA substitution cells

The MCU is generated for an ASIC, so it instantiates compiled memory macros and
analog cells by name. None of those exist on an FPGA. This directory holds a
synthesizable stand-in for each one, under the same entity name, so the
generated `MCU.vhd` binds them without a single edit to generated RTL.

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
  five files in `sim/` are the ones this directory supersedes.
- **Leave out the peripheral sources your configuration disables.** A disabled
  block's RTL refers to `MemoryMap` constants that are only emitted when the block
  is enabled, so compiling it fails outright. With `fpga.json` that means
  `common/periph/NPU.vhd`.

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

These cells were proven to bind and elaborate against the generated one-hart MCU
before they were committed. The check needs no FPGA tool and takes a couple of
seconds:

```sh
make -C platform/common generate CONFIG=config/fpga.json
source cdspaths.sh
xrun -64bit -V200X -licqueue -elaborate -top MCU -f <file list>
```

The file list is `xcelium/riscv_test/behavioral_mp/cell_list_behavioral.txt` with
the five `sim/` cells above swapped for this directory's, `common/periph/NPU.vhd`
dropped, the testbench lines dropped, and `hdl/common/MCU.vhd` and
`MemoryMap.vhd` pointed at `platform/common/out/hdl/`. Elaboration binds the FPGA
architectures by name, so the log line for `rom0` reads
`rom2k_hvt_pg(fpga):rom@rom_hvt_pg(fpga)` when the swap took.
