# Castalia chip generator

Generator for the VestaRV multi-core chips: Castalia (5 harts: soft orchestrator on hart 0,
four rv32iac tiles) and Argus (18 harts). `python/generate.py` is the single source of truth
for the memory map, pinout, generated RTL, headers, linker scripts and TRM. Register maps
come from SystemRDL ([`tools/rdl/README.md`](../../tools/rdl/README.md)). Outputs land in
`out/`, `config/` and `latex/TRM/`; the tracked RTL in `hdl/common/` is never written, and
gates prove the generated VHDL is a drop-in for it. Full Bazel map: [`BAZEL.md`](../../BAZEL.md).

## Running the generator

From the repo root:

```sh
sh tools/get_bazel.sh                                            # fetch bazelisk once
tools/bin/bazel build //platform/common:chip_artifacts_castalia  # hermetic, sandboxed
tools/bin/bazel test  //platform/...                             # generator gates
```

`//:generate` runs the same generator directly, writing to a directory of your choice:

```sh
tools/bin/bazel run //:generate -- --config platform/common/config/<cfg>.json --out <dir>
tools/bin/bazel run //:regs        # .rdl -> VHDL packages -> C headers -> generator, in order
```

`--config` may also be given as `CONFIG=` (Make) or `CHIP_CONFIG` (environment); setting
two different files is an error. `--out` defaults to this directory, which is the layout
the byte-compare gates grade. Inputs (`hdl_templates/`, `latex/`, `config/rdl.json`) always
come from this directory.

Make, from `platform/common/` (`make help` lists everything):

| Command | Action |
|---|---|
| `make generate [CONFIG=config/<cfg>.json]` | Generate in place |
| `make chip` | `generate` plus TRM PDF |
| `make show` | Print the resolved configuration and pad ring |
| `make publish` / `make check-publish` | Copy TRM.pdf to `implementations/asic/castalia/docs/` / verify it is current |
| `make verify [CONFIG=…] [SUITE=full]` | Stage generated RTL into Xcelium and run the ISA smoke suite; `SUITE=full` is the tape-out regression |
| `make verify-lps [LPS_MODE=monitor\|plain\|nolps\|block]` | CPF-aware power-gate bench: gates tiles 1 and 4, checks clamps, relaunches |

`make verify` and `verify-lps` need licensed Cadence tools and a host `riscv-none-elf-`
toolchain. `make verify` is the only check that a configuration boots; only `verify-lps`
exercises power intent. `xcelium/riscv_test/behavioral_mp/` is a smoke run, not the
regression (`xcelium/riscv_test/README.suites`).

## Targets and artifacts

| Target / output | Content |
|---|---|
| `//platform/common:chip_artifacts_castalia` | Full tree for the default chip, `config/castalia.json` |
| `//platform/common:chip_artifacts_{argus,castalia_b,asic_default,fpga_default}` | Same for the other configurations |
| `//platform/common:castalia_*` | Single-file filegroups: `_mcu_vhd`, `_memorymap_vhd`, `_memorymap_h`, `_periph_s`, `_linker_scripts`, `_padring_tcl`, `_chip_data_js`, `_resolved_config`, … |
| `//platform/common:trm_latex_tree` | Generated TRM LaTeX tree |
| `//platform/common/latex/bazel:trm_pdf_local` | TRM PDF (host TeX, tagged `manual`) |
| `out/hdl/MCU.vhd`, `MemoryMap.vhd` | Generated RTL, drop-in for `hdl/common/` |
| `out/software/include/MemoryMap.h`, `periph.S` | C and assembly register definitions |
| `out/linker-scripts/` | `memory.x`, `periph.x`, ROM/RAM size files |
| `out/pnr/chip_top_padring.tcl` | Pad ring for the Innovus chip-top flow |
| `out/web/chip_data.js`, `MemoryMap.json` | Data for the configurator and register browser |
| `config/MemoryMap.json`, `ChipConfig.resolved.json`, `PadRing.json` | Memory map, resolved knobs, pad ring derived from the package model |
| `latex/TRM/` | TRM LaTeX project |

Writers into the source tree:

```sh
tools/bin/bazel run //platform/common/python:splice_web_data -- --data <chip_data.js> docs/chip_configurator.html
tools/bin/bazel run //platform/common/python:splice_register_browser -- --data <MemoryMap.json> docs/register_browser.html
```

## Gates

| Test (`//platform/common:` unless noted) | Proves |
|---|---|
| `check_mcu_vhd_test`, `check_memorymap_vhd_test` | Generated `MCU.vhd` / `MemoryMap.vhd` equal the tracked `hdl/common/` files |
| `check_riscv_tb_vhd_test` | Testbench generator is a no-op at the tracked hart count |
| `check_memorymap_h_test` | `MemoryMap.h` compiles with the hermetic riscv-gcc |
| `check_intro_names_test` | Every register/field named in the intro chapters exists |
| `check_configurator_sync_test`, `splice_web_data_check_test` | `docs/chip_configurator.html` matches the schema and current data bundle |
| `generation_determinism_test` | Two generations are byte-identical |
| `argus_generation_test`, `trm_latex_tree_test` | Argus generates; TRM tree is complete |
| `//platform/common/python:check_config_defaults_test` | Each knob's schema default equals its `_cfg()` fallback |
| `//platform/common/latex/bazel:check_publish_test` | Published TRM is current (red until `make publish`) |

## Configurations

A configuration is a JSON file in `config/`, written by hand or exported from
[`docs/chip_configurator.html`](../../docs/chip_configurator.html). Knobs: `_CONFIG_SCHEMA`
in `python/generate.py`; unknown keys and out-of-range values are hard errors.

| Config | Chip |
|---|---|
| `castalia.json` | Tape-out chip; equal to the built-in defaults |
| `castalia_b.json` | Castalia with hart 0's ISA fully enabled |
| `argus.json` | 18-hart Argus |
| `asic_default.json`, `fpga_default.json` | Minimal ASIC / FPGA starting points |

Rules that change results:

- A missing key takes the Castalia default; any other chip must pin what differs.
- Keys starting with `_` are comments.
- `chipName` is documentation only; the top entity is always `MCU`.
- At `numHarts` 1, set `orchestrator` and `isa.minimalTiles` false.
- `isa.minimalTiles` builds harts 1..N-1 as rv32iac: tile code must be built without M/B
  and no binary may migrate between hart 0 and a tile.
- `peripherals.cqAfeStubs` and `peripherals.qspi` share slot 12; set at most one.
- `debug.enable` requires `package.model` `castalia-lqfp100`, the only model bonding JTAG.
- `memory.romSize` and `memory.tcmSizePerHart` must match the 8 KiB ROM and SRAM macros;
  RTL asserts fail at elaboration otherwise.
- A `CONFIG=` run leaves `out/` on that chip and writes its resolved config and pad ring to
  `out/config/`; the tracked `config/*.json` follow only the default chip. Rerun
  `make generate` to restore Castalia.

## Extending

- **Knob:** add it to `_CONFIG_SCHEMA` (validator) and `_CONFIG_META` (type, default,
  bounds), read it with `_cfg('<key>', <default>)`, and keep both defaults equal
  (`check_config_defaults_test`). The configurator reads it from `chip_data.js`; resplice it.
- **Peripheral:** write its `.rdl` and registry entry ([`tools/rdl`](../../tools/rdl/README.md)),
  declare the `PeripheralTemplate` in `generate.py` followed by `_rdlRegisters('<NAME>', p)`,
  instantiate it with `CreatePeripheral`, and add
  `latex/PeripheralIntroductions/<NAME>-intro-castalia-<date>.tex`.
- **TRM prose:** edit `latex/TRM.template.tex` or the intro files, never `latex/TRM/`.
  Figures are pre-converted PDFs: after editing an SVG run `python3 svg2pdf.py <name>` in
  `latex/figures/` (needs `soffice` and ghostscript).
- **Out-of-tree blocks:** `VESTA_OVERLAY` (or `"overlay"` in the config JSON) names a
  directory mirroring the repo; contract in `python/overlay.py`. With no overlay the
  generation is unchanged.
