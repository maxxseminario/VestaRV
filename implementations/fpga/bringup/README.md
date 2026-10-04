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

**4. Simulate the boot (optional, ~2 min)**
```
tools/bin/bazel test //implementations/fpga/bringup:fpga_flash_boot
```
The boot timeline is in
`bazel-testlogs/implementations/fpga/bringup/fpga_flash_boot/test.outputs/run.log`.

**5. Synthesize**
```
tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files
vivado -mode batch -nojournal -nolog \
    -source implementations/fpga/synth/vivado_ooc_synth.tcl \
    -tclargs romimage=bazel-bin/software/bootrom_mp/rom.rcf
```

**6. Boot.** Strap P1.7 high and release reset. Pass is `a0 = 0xCAFEBABE`
(top-level `MCU` port).

| Signal | Pin |
|---|---|
| Flash CS / MISO / MOSI / SCK | P1.0 / P1.1 / P1.2 / P1.3 |
| Boot strap (high = flash) | P1.7 |
| HFXT, 24 MHz | P1.5 |
| Reset (active low) | `resetn_in` |
