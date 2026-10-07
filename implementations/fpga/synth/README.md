# FPGA synthesis

Out-of-context Vivado synthesis of `MCU` (`fpga_default` configuration). No
board or pins needed.

```sh
tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files //software/bootrom_mp:rom_rcf
vivado -mode batch -nojournal -nolog -source implementations/fpga/synth/vivado_ooc_synth.tcl \
    -tclargs part=xc7a100tcsg324-1 romimage=bazel-bin/software/bootrom_mp/rom.rcf
```

Reports go to `build/fpga_default_ooc/`. The design needs 27 global clock
buffers (32 on an Artix-7). Use the Bazel file list only: a hand-built list
can bind the wrong `ClkGate`.

| File | Contents |
|---|---|
| `vivado_ooc_synth.tcl` | The synthesis run |
| `fpga_default_ooc.xdc` | Clock constraints (board-independent); pin lines are placeholders |
| `mmcm_24mhz.vhd` | Optional board clock source: any oscillator to 24 MHz on HFXT |

Not yet run in Vivado.
