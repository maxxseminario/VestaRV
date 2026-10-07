# Castalia

Five-hart VestaRV MCU in TSMC 65 nm. Hart 0 is a soft orchestrator
(`orch_tile`); harts 1–4 are four instances of one hardened `hart_tile` macro,
each power-gateable. Castalia is the default configuration of the
`platform/common/` generator.

| | |
|---|---|
| Hart 0 | `rv32imac_zba_zbb_zbs_zbc`; runs boot, owns the console and CLINT, always on |
| Harts 1–4 | `rv32iac` (`isa.minimalTiles`); MTCMOS-gated, isolation-clamped |
| Boot ROM | 16 KiB, shared; every hart resets to 0x0 and dispatches on `mhartid` |
| Memory | 8 KiB TCM per hart; 64 KiB shared RAM + 16 KiB NPU staging RAM |
| Sync | CLINT, 16 hardware mutexes, per-hart interrupt router |
| Peripherals | 6× GPIO (48 pins), 2× SPI, 2× UART, 2× I²C, 2× timer, NPU, NFC, CRC16, watchdog, power controller, JTAG debug |
| Package | LQFP-100, 14 × 14 mm (preliminary) |

Code that runs on harts 1–4 must be built without M and B. A binary built for
hart 0 does not run on a tile.

The analog front-end RTL, configurations and tests live in the gitignored
`private/analog/` tree.

## Build

From the repo root:

```sh
sh tools/get_bazel.sh
tools/bin/bazel build //platform/common:chip_artifacts_castalia   # RTL, headers, linker scripts, pad ring, TRM
tools/bin/bazel test  //platform/...                              # generator gates
tools/bin/bazel test  //opensource_sim:isa_regression             # GHDL ISA regression
```

TRM PDF: `tools/bin/bazel build //platform/common/latex/bazel:trm_pdf_local`.
Target and gate details: [`platform/common/README.md`](../../../platform/common/README.md).
Cadence flows (Genus, Innovus, Pegasus, Xcelium) run outside Bazel after
`source cdspaths.sh`.

## Contents

- `docs/`: Technical Reference Manual (`TRM.pdf`) and planning notes
- `analog/`: measured analog chapter of the TRM

Contact: Maxx Seminario (mseminario2@huskers.unl.edu).
