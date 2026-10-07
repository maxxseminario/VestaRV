# Example FPGA board

Template for a board port. Start from the `fpga_default` configuration.

A port adds:
- a top level that instantiates `MCU` with an `IOBUF` per pin (`T => prtN_dir(i)`);
- pin constraints, added to [`../synth/fpga_default_ooc.xdc`](../synth/fpga_default_ooc.xdc);
- a 24 MHz clock on HFXT (P1.5), e.g. [`../synth/mmcm_24mhz.vhd`](../synth/mmcm_24mhz.vhd);
- reset held until the clock is stable.

Synthesis: [`../synth/`](../synth/README.md). Boot from SPI flash: [`../bringup/`](../bringup/README.md).
