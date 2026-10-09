# Example FPGA board

Template for a board port. Start from the `fpga_default` configuration.

`tools/bin/bazel build //implementations/fpga/bringup:fpga_top` generates the two
board files from the chip's `MCU.vhd` and pad ring:
- `fpga_top.vhd`: the top level, one inout port per bonded pin;
- `fpga_pins.xdc`: clock constraints and a labelled pin line per port.

A port adds the board's `PACKAGE_PIN` / `IOSTANDARD` values to a copy of
`fpga_pins.xdc`, a 24 MHz clock on `clk_hfxt` (e.g. [`../synth/mmcm_24mhz.vhd`](../synth/mmcm_24mhz.vhd)),
and a reset held until that clock is stable.

Synthesis: [`../synth/`](../synth/README.md). Boot from SPI flash: [`../bringup/`](../bringup/README.md).
