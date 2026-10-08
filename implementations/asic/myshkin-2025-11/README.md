# Myshkin

First VestaRV tape-out: single-core mixed-signal MCU, TSMC 65 nm, November 2025.
Silicon received and validated March 2026. RTL is the frozen
[`hdl/myshkin/`](../../../hdl/myshkin/README.md) tree.

| | |
|---|---|
| Application | Mixed-signal electrochemical sensing SoC for autonomous wound monitoring |
| Core | VestaRV32, RV32IMAC + Zba/Zbb/Zbc/Zbs, 24 MHz |
| Memory | 16 KiB ROM, 32 KiB RAM |
| Peripherals | 4× 8-bit GPIO, 2× SPI (one with flash extension), 2× UART, 2× I²C, 2× timer, NPU, system control (clocks, power gating, watchdog) |
| Analog | Potentiostat front end, ADC |
| Die / package | 1.0 × 1.5 mm, QFN-44 |

The potentiostat paper received the Best Student Paper Award at IEEE ISCAS 2026.

## Build

The Myshkin generator (`platform/myshkin/`) is frozen and outside Bazel: it overwrites
tracked files in place. Regenerate only if required, with
`platform/myshkin/regenerate.sh`. Its tracked register map is what every Bazel-built
firmware image compiles against:

| Target | Contents |
|---|---|
| `//platform/myshkin/gcc/lib:platform_headers` | `MemoryMap.h` + `periph.S` |
| `//platform/myshkin/gcc/lib:linker_fragments` | `memory.x` + `periph.x`, pulled in by `MCU.ld` |
| `//software/bootrom_mp:rom_rcf` | Mask-ROM image; `:rom_rcf_reproducibility_test` checks it against the golden |
| `//software/blinky:blinky_rcf` | Example app (also `gpiotoggle`, `looptest`, `slowblink`, `traptest`); `:blinky_flashed_rcf_test` locks it to a golden |

`//opensource_sim:isa_regression` simulates the shared `hdl/common/` RTL, not this
snapshot. Cadence flows run outside Bazel after `source cdspaths.sh`.

## Board operations

`make help` in this directory lists the serial targets: `make flash <program>`,
`make run-rcf <program>` (RAM upload and jump; `RAM_ENTRY=`, `METHOD=poke`, `VERIFY=1`,
`LOG=auto` options), and the Forth script targets. `test_uart.py` checks basic Forth
communication with the chip.

## Contents

- `docs/TRM.pdf`: Technical Reference Manual
- `config/`: `ChipConfig.json`, `MemoryMap.json`, `BoardConfig.json`
- `images/`: block diagram, layout, bonding diagram

Contact: Maxx Seminario (mseminario2@huskers.unl.edu).
