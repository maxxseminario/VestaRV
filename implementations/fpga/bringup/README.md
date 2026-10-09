# FPGA bring-up: boot from SPI flash

The boot ROM loads a test program from an external SPI flash and runs it. Run
everything from the repo root.

**1. Toolchain**
```
sh tools/get_bazel.sh
```

**2. Build the boot ROM**
```
tools/bin/bazel build //software/bootrom_mp:rom_rcf
```
Output: `bazel-bin/software/bootrom_mp/rom.rcf`

**3. Build the flash image**
```
tools/bin/bazel build //implementations/fpga/bringup:flash_payload_bin
```
Output: `bazel-bin/implementations/fpga/bringup/flash_payload.bin`, the
`rv32ui-p-simple` ISA test. Write it at flash address 0.

For an LED instead of the `a0` check, use `slowblink`, which toggles P3.0 at a few
hertz from a CPU loop:
```
tools/bin/bazel build //implementations/fpga/bringup:slowblink_flash_bin
```
Output: `bazel-bin/implementations/fpga/bringup/slowblink_flash.bin`.
`blinky` clocks its timer from SMCLK, which the ROM switches to LFXT after a flash
boot, so it toggles only every few minutes.

**4. Simulate the boot (optional, ~2 min)**
```
tools/bin/bazel test //implementations/fpga/bringup:fpga_flash_boot
```
`:<app>_flash_boot` runs the same boot for each of the five firmware apps.
The boot timeline is in
`bazel-testlogs/implementations/fpga/bringup/fpga_flash_boot/test.outputs/run.log`.

**5. Board top level and pins**
```
tools/bin/bazel build //implementations/fpga/bringup:fpga_top
```
Outputs in `bazel-bin/implementations/fpga/bringup/`, generated from the chip's
`MCU.vhd` and pad ring:
- `fpga_top.vhd`: `MCU` with one inout port per bonded pin (Vivado infers the
  IOBUFs), `clk_hfxt`, `clk_lfxt`, `resetn`, and `pass_led`, which is on while
  `a0 = 0xCAFEBABE`.
- `fpga_pins.xdc`: the clock constraints and one commented pin line per port.
  Copy it, fill in `PACKAGE_PIN` and `IOSTANDARD` for the board, uncomment.

`:fpga_top_flash_boot` runs the step-4 boot through these pins.

| `fpga_top` port | Wire to |
|---|---|
| `p0_0` / `p0_1` / `p0_2` / `p0_3` | Flash CS / MISO / MOSI / SCK |
| `p0_7` | Boot strap: high = boot from flash |
| `clk_hfxt` | 24 MHz |
| `clk_lfxt` | 32.768 kHz, or tie low |
| `resetn` | Reset button, active low |
| `pass_led` | LED |
| `p2_0` | P3.0 in the firmware headers: slowblink's LED pin |

Port `pK_B` is pad-ring pin `PK.B`, which the firmware headers call `P(K+1).B`.

**6. Synthesize**

Out of context, `MCU` as top (no board needed):
```
tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files
vivado -mode batch -nojournal -nolog \
    -source implementations/fpga/synth/vivado_ooc_synth.tcl \
    -tclargs romimage=bazel-bin/software/bootrom_mp/rom.rcf
```
For a bitstream, use the same file list plus `fpga_top.vhd`, `fpga_top` as top,
the filled-in `fpga_pins.xdc`, and `rom.rcf` in Vivado's working directory.

**7. Boot.** Strap `p0_7` high and release reset. `pass_led` lights when the
payload passes; with `slowblink`, `p2_0` blinks.
