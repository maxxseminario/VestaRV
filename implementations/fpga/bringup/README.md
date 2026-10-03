# FPGA bring-up: boot from SPI flash

The kit for proving the boot sequence of the `fpga_default` cut on a board: the
boot ROM in block RAM loads a program out of an external SPI flash, powers the
flash down and jumps to it. Everything here is built and checked by Bazel; the
simulation below is the reference a board run is read against.

| Target | What it is |
|---|---|
| `//software/bootrom_mp:rom_rcf` | The boot ROM image, byte-identical to the taped-out mask ROM (`:rom_rcf_reproducibility_test`) |
| `:flash_payload_bin` | `flash_payload.bin`, the bytes to write at flash address 0 |
| `:flash_payload_bin_test` | Byte order (`EF BE AD 10` first) and length of that binary |
| `:fpga_flash_boot` | GHDL: the FPGA file set boots the payload from a SPI flash model through the real ROM, and prints the boot timeline |
| `rcf_to_flash_bin.py` | Flashed RCF to raw flash binary, for any other image |

The payload is the `rv32ui-p-simple` ISA test. It passes by writing
`0xCAFEBABE` to `a0`, which is a top-level `MCU` port.

## Status

| Verified | How |
|---|---|
| The ROM image rebuilds from source to the mask-ROM golden | `rom_rcf_reproducibility_test`, run with no build cache |
| The FPGA file set boots the payload from flash | `:fpga_flash_boot` |
| The flash byte order | `:flash_payload_bin_test`, and the ROM's `SPIRXSB` setting (`SPI_CR_LOADBEEF = 0x108C8`, bit 16) |

| Not verified | |
|---|---|
| Vivado synthesis | No Vivado on the build host. GHDL runs the vendor-neutral clock model (`ClockPrimitives_generic.vhd`), not `BUFGCE` |
| Any board | No board, pinout or top level is tracked |
| Any flash part but the AT45DB021E | The ROM's commands (ABh wake, 0Bh fast read, B9h power-down) are what the model implements |

## Steps

Run everything from the repo root.

**1. Toolchain.**
```
sh tools/get_bazel.sh
```

**2. Build and check the images.**
```
tools/bin/bazel test //software/bootrom_mp:rom_rcf_reproducibility_test \
    //implementations/fpga/bringup:all
```
`:fpga_flash_boot` takes about 2 minutes. Its log, with the timeline, is
`bazel-testlogs/implementations/fpga/bringup/fpga_flash_boot/test.outputs/run.log`.

**3. Synthesize.**
```
tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files
vivado -mode batch -nojournal -nolog \
    -source implementations/fpga/synth/vivado_ooc_synth.tcl \
    -tclargs romimage=bazel-bin/software/bootrom_mp/rom.rcf
```
Without `romimage`, the script looks for `software/bootrom_mp/bin/rom.rcf`,
which is not tracked; a missing image synthesizes as an all-zero ROM and the
log says `no boot ROM image`. A bitstream also needs a board top level that
`synth/README.md` lists as missing: `MCU` has split `prtN_in/out/dir` ports,
so each pin needs an `IOBUF` with `T => prtN_dir(i)` (`'1'` = input).

**4. Pin out.**

| Signal | Pin | Note |
|---|---|---|
| Flash CS / MISO / MOSI / SCK | P1.0 / P1.1 / P1.2 / P1.3 | |
| Boot strap | P1.7 | High = boot from flash, low = Forth monitor |
| Trap | P1.6 | High = the core took a terminal trap |
| HFXT | P1.5 | 24 MHz; the UART divisors assume it |
| LFXT | P1.4 | 32.768 kHz, or tie low |
| UART0 TX / RX | P2.4 / P2.5 | 115200 baud, monitor only |
| Reset | `resetn_in` | Active low |
| Pass | `a0(31:0)` | `0xCAFEBABE`; route to an ILA, or compare and drive an LED |

**5. Program the flash.** Write
`bazel-bin/implementations/fpga/bringup/flash_payload.bin` at address 0 with
an external programmer. An AT45DB021E must first be set to 256-byte
("power of 2") pages, a one-time, permanent setting: it ships with 264-byte
pages, which do not map to the ROM's linear addresses.

**6. Boot.** Strap P1.7 high and release reset. Pass is `a0 = 0xCAFEBABE` with
P1.6 low. With P1.7 low the ROM enters the Forth monitor on UART0; a prompt
there separates a dead core from a dead flash path.

## Expected timeline

From `:fpga_flash_boot`, 24 MHz HFXT, times from reset release. The flash
chip-select (P1.0) is the line to put on a logic analyzer.

| Time | Event |
|---|---|
| 0 | Reset released |
| 0.762–0.772 ms | CS low/high: ABh wake-up |
| 0.807 ms | Flash leaves deep power-down (model tRDPD 35 µs) |
| 3.108–9.108 ms | CS low: the whole image streams in one continuous read |
| 9.109–9.132 ms | CS low/high: B9h power-down |
| 9.147 ms | `a0 = 0xCAFEBABE` |

A board flash with a slower wake-up shifts every event after it.

## Failure signatures

| Observation | Cause |
|---|---|
| P1.6 high within about 1 µs of reset | The core lacks the C extension: `fpga_default.json` must keep `"compressed": true`, because the ROM is `rv32ic` |
| P1.6 high about 13 µs after the last CS edge | The program fetched zeros from TCM; see the ClkGate note below |
| P1.6 high with no third CS frame | The ROM rejected a command word or segment address in the image |
| UART0 starts transmitting | The flash never answered and the ROM fell back to the monitor |
| No CS activity | Strap low, no HFXT, or reset held |

## Two defects this bench found

- **`fpga_default.json` had compressed instructions off.** The one boot ROM is
  `rv32ic`, so the FPGA core trapped on its first instruction. Now
  `"compressed": true`.
- **The vendor-neutral `ClkBufEn` sampled its enable with a falling-edge
  flop.** `adddec.vhd` launches `mem_en` on that same edge, so the flop
  caught the old value, every TCM clock pulse landed a cycle late, and the
  flash loads into the TCM were lost. It is now a low-transparent latch, the
  function of `BUFGCE` and of the ASIC ICG.

## Open: the app images do not boot

`//software/blinky` and the other `myshkin_app` images are linked at `0x814C`
and `rcf_flash.py` loads them at `0x8000`, but the ROM enters at
`PROG_BASE_ADDR = 0x8200`. Blinky traps on entry; the others share its layout.
Their golden tests pass because they check the image bytes, not that it boots.
Until the apps are relinked, use an ISA-test image as the payload.
