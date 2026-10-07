# Castalia chip generator

Generator for the VestaRV multi-core chips (Castalia, 5 harts; Argus, 18). `python/generate.py`
is the single source of truth for the memory map, pinout, generated RTL, headers, linker
scripts and TRM; registers come from SystemRDL ([`tools/rdl`](../../tools/rdl/README.md)).
Outputs land in `out/`, `config/` and `latex/TRM/`; `hdl/common/` is never written. Bazel
map: [`BAZEL.md`](../../BAZEL.md).

```sh
sh tools/get_bazel.sh                                            # once
tools/bin/bazel build //platform/common:chip_artifacts_castalia  # hermetic generation
tools/bin/bazel test  //platform/...                             # all generator gates
tools/bin/bazel build //platform/common/latex/bazel:trm_pdf_local  # TRM PDF (manual, host TeX)
```

| Make (in `platform/common/`) | Action |
|---|---|
| `make generate [CONFIG=config/<cfg>.json]` | Generate in place |
| `make chip` / `make publish` / `make check-publish` | Generate + PDF / publish PDF / verify published PDF is current |
| `make verify [CONFIG=…] [SUITE=full]` | Xcelium ISA run on the generated RTL (`SUITE=full` = tape-out regression; needs Cadence + `riscv-none-elf-`) |
| `make verify-lps` | CPF-aware power-gate bench; the only run that exercises power intent |

`make help` lists the rest. `xcelium/riscv_test/behavioral_mp/` is a smoke run, not the
regression.

## Configuration

A JSON file in `config/` (`castalia.json` = tape-out chip and built-in defaults; also
`castalia_b`, `argus`, `asic_default`, `fpga_default`), written by hand or exported from
[`docs/chip_configurator.html`](../../docs/chip_configurator.html). Knobs and validation:
`_CONFIG_SCHEMA` in `python/generate.py`; unknown keys and bad values are hard errors.

- A missing key takes the Castalia default; any other chip must pin what differs.
- `chipName` is documentation only; the top entity is always `MCU`.
- At `numHarts` 1, set `orchestrator` and `isa.minimalTiles` false.
- `isa.minimalTiles` builds tiles as rv32iac: tile code must be built without M/B and no
  binary may migrate between hart 0 and a tile.
- `peripherals.cqAfeStubs` and `peripherals.qspi` share slot 12; set at most one.
- `debug.enable` requires `package.model` `castalia-lqfp100`.
- `memory.romSize` and `memory.tcmSizePerHart` must match the 8 KiB macros or elaboration fails.
- A `CONFIG=` run leaves `out/` on that chip and writes its resolved config to
  `out/config/`; the tracked `config/*.json` follow only the default chip. Rerun
  `make generate` to restore Castalia.

Out-of-tree blocks attach through `VESTA_OVERLAY`; contract in `python/overlay.py`.
