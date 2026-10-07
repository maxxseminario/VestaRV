# Castalia

Five-hart VestaRV MCU in TSMC 65 nm, and the default (golden-master)
configuration of the `platform/common/` generator. Hart 0 is a soft
orchestrator (`orch_tile`); harts 1–4 are four instances of one hardened
`hart_tile` macro, identical to each other and individually power-gateable.

The analog front-end RTL, register descriptions, configurations and tests live
in the gitignored `private/analog/` tree. The measured analog chapter
(`analog/`) and the TRM stay here.

## Architecture

| | |
|---|---|
| Hart 0 (`orch_tile`, soft) | `rv32imac_zba_zbb_zbs_zbc`. Runs boot, owns the console and CLINT, keeps the SPI0 flash/XIP port and the GPIO0 trap pin. Outside the MTCMOS fabric: always on. |
| Harts 1–4 (`hart_tile`, hardened ×4) | `rv32iac` (`isa.minimalTiles = true`). MTCMOS-gated with isolation clamps; `pwr_ctrl` rows 1–4. |
| Boot ROM | 8 KiB, shared. Every hart resets to 0x0; the ROM dispatches on `mhartid`. |
| Private memory | 8 KiB TCM per hart. Hart 0 alone can read any hart's TCM through read-only apertures. |
| Shared memory | 64 KiB bulk RAM (4 × 16 KiB) + 16 KiB NPU staging RAM, round-robin arbitrated |
| Synchronization | CLINT (IPI and per-hart timers), 16 hardware mutexes, per-hart interrupt router |
| Peripherals | 6× GPIO (48 pins), 2× SPI (SPI0 maps external flash), 2× UART, 2× I²C, 2× timer, NPU, NFC, CRC16, 2× DCO, watchdog, power controller |
| Debug | RISC-V debug module with JTAG DTM |
| Package | LQFP-100, 14 × 14 mm, 0.5 mm pitch (preliminary) |

A PWRCR write gates any combination of harts 1–4; hart 0's bit reads 0 and
ignores writes.

**Why the tiles are `rv32iac`.** Dropping M and B shrinks the tile 17 %
(132,657 → 109,926 µm², core −37 %) and its power 28 % (2.69 → 1.95 mW), at
Genus on the 8 KiB tile. A stays because the tiles run the LR/SC and AMO
locking on the shared fabric; C stays because it is decoder-only and shrinks
code in an 8 KiB TCM.

**Software contract.** Code that runs on harts 1–4 must be built without M and
B. A binary built for hart 0 does not run on a tile.

## Build

From the repo root:

```sh
sh tools/get_bazel.sh
tools/bin/bazel build //platform/common:chip_artifacts_castalia
tools/bin/bazel test  //platform/...
```

| Target | Produces |
|---|---|
| `//platform/common:chip_artifacts_castalia` | Whole artifact tree: `MCU.vhd`, `MemoryMap.vhd`, `riscv_tb.vhd`, `MemoryMap.h`, `periph.S`, linker scripts, pad ring, TRM LaTeX |
| `//platform/common:castalia_mcu_vhd`, `:castalia_memorymap_vhd`, `:castalia_riscv_tb_vhd` | The individual RTL files |
| `//platform/common:castalia_memorymap_h`, `:castalia_periph_s`, `:castalia_linker_scripts` | The firmware-facing files |
| `//platform/common:castalia_padring_json`, `:castalia_padring_tcl` | Pad ring for the physical flow |
| `//platform/common/latex/bazel:trm_pdf_local` | TRM PDF (host TeX, tagged manual) |

`//platform/...` includes the identity gates: the generated `MCU.vhd`,
`MemoryMap.vhd` and `riscv_tb.vhd` must equal the tracked copies in
`hdl/common/`, and two independent generations must be byte-identical. The
full gate list is in [`platform/common/README.md`](../../../platform/common/README.md).

License-free simulation: `tools/bin/bazel test //opensource_sim:isa_regression`
(GHDL ISA suites plus the arbiter and PMP benches).

Cadence flows (Genus, Innovus, Pegasus, Xcelium) run outside Bazel after
`source cdspaths.sh`.

## Configuration

`platform/common/config/castalia.json` sets only `chipName`: Castalia is the
generator's built-in default. The resolved form is tracked as
`platform/common/config/ChipConfig.resolved.json`. Key knobs: `numHarts = 5`,
`orchestrator = true`, `isa.minimalTiles = true`, `numMutexes = 16`,
`memory.tcmSizePerHart = 8 KiB`, `memory.sharedBulkRamSize = 64 KiB`,
`memory.npuStagingRamSize = 16 KiB`, `peripherals.npu = true`,
`package.model = castalia-lqfp100`.

## Contents

- `docs/`: Technical Reference Manual (`TRM.pdf`) and planning notes
- `analog/`: measured analog chapter of the TRM

Contact: Maxx Seminario (mseminario2@huskers.unl.edu).
