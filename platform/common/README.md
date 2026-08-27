# Castalia Chip Generator

Generator for **Castalia**, the 5-hart multi-core VestaRV MCU (`hdl/common/`) - a soft
orchestrator on hart 0 plus four hardened rv32iac channel tiles. This is a fork of
`platform/` (the single-core Myshkin generator) adapted for the multi-core chip.
One Python description (`python/generate.py`) is the single source of truth for the memory
map, every peripheral register and bit field, the GPIO/package pinout, and the Technical
Reference Manual.

**All outputs stay inside this directory.** Unlike `platform/`, nothing here writes to
`../software/`, `../tools/`, or `../hdl/` — the generated HDL goes to `out/hdl/` so the
hand-maintained `hdl/common/` RTL is never touched.

---

## Building with Bazel

Bazel runs the generator hermetically, in a sandbox that cannot touch the
source tree, with every consistency check wired up as a test.

Run everything from the repo root:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Chip artifact targets

| Target | What it is / what it proves |
|--------|-----------------------------|
| `//platform/common:chip_artifacts_castalia` | The full generated tree for the default Castalia configuration (`out/hdl/`, `out/software/`, `out/web/`, `out/pnr/`, `config/`, `latex/TRM/`). This is the artifact generation; the TRM PDF is a separate target |
| `//platform/common:chip_artifacts_argus` | The same tree for the 18-hart Argus course configuration |
| `//platform/common:chip_artifacts_castalia_repro` | A second, independent generation of the Castalia configuration; exists only to be byte-compared by the determinism test |
| `//platform/common:trm_latex_tree` | The generated LaTeX TRM tree alone |

Individual generated files are exported as filegroups off the Castalia tree, for
example `//platform/common:castalia_mcu_vhd`, `:castalia_memorymap_vhd`,
`:castalia_riscv_tb_vhd`, `:castalia_memorymap_h`, `:castalia_periph_s`,
`:castalia_linker_scripts`, `:castalia_padring_json`, `:castalia_padring_tcl`,
`:castalia_chip_data_js` and `:castalia_resolved_config`.

```sh
tools/bin/bazel build //platform/common:chip_artifacts_castalia
tools/bin/bazel test  //platform/...
```

**Never `bazel run` the raw generator.** It writes wherever it is invoked; the
hermetic path is `//platform/common:chip_artifacts_castalia`.

### Generator gate tests

| Test target | What it proves |
|-------------|----------------|
| `//platform/common:check_mcu_vhd_test` | The generated `MCU.vhd` is a byte-for-byte drop-in for the tracked `hdl/common/MCU.vhd` (header comment aside) |
| `//platform/common:check_memorymap_vhd_test` | Constant-by-constant equivalence with the tracked `hdl/common/MemoryMap.vhd` |
| `//platform/common:check_riscv_tb_vhd_test` | The tb generator is a no-op at the tracked hart count |
| `//platform/common:check_memorymap_h_test` | The emitted C header still compiles, using the hermetic riscv-gcc |
| `//platform/common:check_intro_names_test` | Every `\register{}` / `\bitfield{}` name in the hand-written intro chapters names something the generator actually emits |
| `//platform/common:check_configurator_sync_test` | `docs/chip_configurator.html` matches the schema, the spliced data bundle and the derived geometry, at the STRICT bar |
| `//platform/common:splice_web_data_check_test` | The `VESTA_DATA` region spliced into the configurator page is not stale against the bundle this build emits |
| `//platform/common:generation_determinism_test` | Two independent generations of the same configuration are byte-identical |
| `//platform/common:argus_generation_test` | Argus still generates, and its machine-readable outputs still parse |
| `//platform/common:trm_latex_tree_test` | The published TRM tree is complete: master document, generated includes, referenced figures |
| `//platform/common:castalia_analog_chapter_test` | The Analog Front-End chapter is present in the generated TRM tree |
| `//platform/common/python:check_config_defaults_test` | Every knob's two default literals in `generate.py` (schema entry and `_cfg()` call site) agree |

### TRM PDF and writers

The PDF half uses host TeX and is tagged `manual`, so it is not part of
`bazel test //...`:

```sh
tools/bin/bazel build //platform/common/latex/bazel:trm_pdf_local
tools/bin/bazel test  //platform/common/latex/bazel:check_publish_test
tools/bin/bazel test  //platform/common/latex/bazel:trm_lint_test
```

`//platform/common/latex/bazel:check_publish_test` is red whenever
TRM-affecting commits have landed since the last publish; that is the point of
the gate.

Two `bazel run` targets here deliberately write into the source tree:

```sh
tools/bin/bazel run //platform/common/python:splice_register_browser -- --data <MemoryMap.json> docs/register_browser.html
tools/bin/bazel run //platform/common/python:splice_web_data -- --data <chip_data.js> docs/chip_configurator.html
```

Full map of the Bazel build: [`BAZEL.md`](../../BAZEL.md).

## Outside Bazel

One job here has no Bazel target: proving a configuration actually boots. It
stages the generated RTL into an Xcelium behavioral flow and runs the ISA/sh
smoke suite, so it needs the licensed Cadence tools and a host
`riscv-none-elf-` toolchain, and it regenerates in place before it runs.

```bash
cd platform/common
make verify                 # smoke suite on the default (Castalia) configuration
make verify CONFIG=f.json   # same, for a JSON configuration
make verify SUITE=full      # the whole regression instead of the smoke suite
```

## Configuring a chip (no RTL editing required)

The whole configuration is one small JSON file in `config/` - produced interactively by
**`../docs/chip_configurator.html`** or written by hand. A configuration is built by giving
it a `chip_artifacts` target in `BUILD.bazel` with `config = "config/<name>.json"`, the way
`chip_artifacts_argus` names `config/argus.json`.
Every key is optional (missing keys keep the Castalia defaults) and the schema is
**validated**: an unknown key or out-of-range value is a hard error, never a silent
fallback. The knobs (authoritative list: `_CONFIG_SCHEMA` in `python/generate.py`, also
documented in the generated TRM's "Chip Configuration" section):

| Key | Meaning |
|-----|---------|
| `chipName` | Docs-only rename (TRM, headers) |
| `numHarts` | Hart/tile count — 5 = Castalia golden master, 18 = Argus (sim-proven) |
| `orchestrator` | `true` (the default) = hart 0 is the always-on soft orchestrator (`orch_tile`) and harts 1..N-1 are gateable channel tiles, on memory map v2; `false` = the historical shape, every hart a hardened `hart_tile` (kept as a standing row by `config/castalia4.json`) |
| `numMutexes` | HW mutex bank size (16 = Castalia, 32 = Argus) |
| `registerFileDualPort` | Dual-port regfile (ASIC) vs single-port (FPGA) |
| `isa.*` | `mul fastMul div atomics compressed bitmanip minimalTiles counters counters64` plus the X-series extension knobs |
| `isa.minimalTiles` | `true` (the default) = harts 1..N-1 drop M and B and are built rv32iac; hart 0 keeps the full chip ISA. No binary may migrate between hart 0 and a tile, and anything the tiles execute must be built without M/B |
| `memory.*` | `romSize tcmSizePerHart sharedBulkRamSize npuStagingRamSize` (bytes) |
| `peripherals.npu` | `false` = Argus-style chip with no NPU at all |
| `peripherals.i2c1` | `false` = drop the second I²C instance (slot 15 dead, vectors 70–82 reserved, SDA1/SCL1 pins revert to plain GPIO) |
| `peripherals.uart1` | `false` = drop the second UART (slot 5 dead, vectors 52–54 reserved, TX1/RX1 pins revert to plain GPIO) |
| `peripherals.spi1` | `false` = drop the second SPI (slot 3 dead, vectors 11–12 reserved, CS1/MISO1/MOSI1/SCK1 pins revert to plain GPIO) |
| `peripherals.timer1` | `false` = drop the second TIMER (slot 7 dead, vectors 22–27 reserved, T1CMP\*/T1CAP\* pins revert to plain GPIO) |
| `package.model` | Package model name defined in `generate.py` (`_PACKAGE_MODELS`: `myshkin-qfn44`, `castalia-quad-qfn64`, `castalia-lqfp100`). **Default since 2026-08-16: `castalia-lqfp100`** — the LQFP-100 large pinout (14 × 14 mm, 100 pins), moved there as the pad-side half of the `debug.enable` flip because it is the only model that bonds the JTAG TAP. It also bonds the sixteen electrode pads, which is half of what gates the TRM's Analog Front-End chapter (the other half is the orchestrator shape: `numHarts = 5` with `orchestrator = true`). `config/castalia4.json`, `argus.json` and `argus_course.json` (the last untracked since 2026-08-27, bench-machine only) pin `myshkin-qfn44` (they are not that chip; see their `_packageNote`), and `argus_debug.json` pins `castalia-lqfp100` provisionally, to reach the JTAG balls. |
| `package.preliminary` | `false` = suppress the TRM package-section "Preliminary" banner |

Every build also writes `config/ChipConfig.resolved.json` (all knobs plus the derived
geometry — shared-window address width, RAM bank count, extended-flash base, CLINT
register layout), `config/PadRing.json` — the **pad ring, derived from the package
model** in `generate.py` (QFN-44 pin order, sides, power domains) — and
`out/pnr/chip_top_padring.tcl`, the same ring as ordered per-side pad lists for the
`innovus/common` chip_top pad-ring flow. The pad ring is deliberately *derived, not
configured*: the package model is its single source, and the TRM's labeled pinout
figure is generated from the same model. The peripheral *set* is otherwise fixed RTL
template content — the NPU and every second instance (I²C1, UART1, SPI1, TIMER1) are
real drop knobs (G1a/G1b): a dropped instance's window reads zero, its vectors become
reserved gaps (the numbering is frozen), and its pins revert to plain GPIO. Working
configurations live in `config/` (`argus.json` = the 18-hart course chip;
`castalia_no{i2c1,uart1,spi1,timer1}.json` = the G1a/G1b proof configs).

Generation produces the complete Technical Reference Manual for exactly the generated
configuration: the feature list, peripheral chapters (intro LaTeX snippets + register
tables), memory/address-space diagrams, interrupt tables, and multi-core defines are all
derived from what `python/generate.py` instantiates. pdflatex is auto-detected from PATH
or `~/texlive` (no inkscape/shell-escape required — see SVG note below).

**SVG figures:** unlike `platform/`, the diagram figures are pre-converted, cropped PDFs
(`latex/figures/*.pdf`) included with plain `\includegraphics` — the `\includesvg`/inkscape
flow is not used (it silently dropped the figures in past Myshkin builds, which ran without
shell-escape). If you edit one of the source `.svg` files, regenerate its PDF with:

```bash
cd latex/figures
python3 svg2pdf.py <figure-name-without-extension>   # needs soffice + ghostscript
```

The script also resolves the literal LaTeX macros (`\bitfield{...}`, `\textoverline{...}`, …)
embedded in the SVG text labels, which only rendered correctly under inkscape's LaTeX-export
flow and otherwise appear as raw macro source in the figure.

---

## What it generates

| Output | Purpose |
|--------|---------|
| `latex/TRM/` | Complete TRM LaTeX project (compile `TRM.tex` for the PDF) |
| `out/software/include/MemoryMap.h` | C header: base addresses, register offsets, bit-field macros |
| `out/software/include/periph.S` | Assembly definitions of the same |
| `out/linker-scripts/memory.x`, `periph.x`, `*.txt` | Linker memory regions (incl. `SHARED_RAM`) and symbols |
| `out/hdl/MemoryMap.vhd`, `MCU.vhd`, `MCU_routing_template.vhd` | Generated VHDL. `MemoryMap.vhd` (2026-07-04) and `MCU.vhd` (2026-07-05, golden-master templated from `hdl_templates/MCU.template.vhd` + `python/mcu_vhd.py`) are verified **drop-in replacements** for their `hdl/common/` originals (full behavioral_mp regression passes with the cell list pointed at them) but are not wired into the build; the routing template is reference-only |
| `config/MemoryMap.json` | Machine-readable full memory map |
| `config/ChipConfig.resolved.json` | The resolved configuration: every knob + derived geometry |
| `config/PadRing.json` | The derived pad ring (package model → pin/side/power-domain list) |
| `out/web/chip_data.js` | Web data bundle (`const VESTA_DATA = {…}`) — see below |
| `out/web/MemoryMap.json` | Copy of `config/MemoryMap.json` for the web register browser |

## Web data export

Every generation emits **`out/web/chip_data.js`**, a single
`const VESTA_DATA = { … };` bundle so the web tooling — `../docs/chip_configurator.html`
and a future register browser — can **consume the generator instead of transcribing it**
(the old configurator carried a hand-copied second source of truth; see
`~/vesta_docs/vesta_showcase/audit_findings.md` §4.1). It is written by
`python/web_export.py`, wired into `ChipGenerator.Generate()` next to
`generateMemoryMapJson`, and is deterministic (no timestamps). Top-level keys:

| Key | Contents |
|-----|----------|
| `schema` | Every `_CONFIG_SCHEMA` key: description **plus** machine-readable constraints — `type`, `min`/`max`/`step`, `enum`, `default` (from the declarative `_CONFIG_META`, cross-checked against the validator lambdas) |
| `defaults` | Schema key → default value |
| `packages` | Pad table for **every** `_PACKAGE_MODELS` model (myshkin-qfn44 **and** castalia-quad-qfn64): pin/side/name/io-type/power-domain + GPIO alt-function map, built via the same `Package`/`CreatePackage` machinery |
| `derivedPresets` | Derived geometry for the shipped configs (`castalia`, `argus`, `cq`): ISA string, shared-window width, bank count, flash base, CLINT layout |
| `verifiedHarts` | `{ values: [4, 18], note }` — the sim-proven hart counts |
| `memoryRegions` | Region-level address map (ROM, peripheral window, CLINT/mutex/IRQ-router, TCM, shared RAM, flash) |
| `meta` | Provenance (chip name, source config, note) |

Generation also copies `config/MemoryMap.json` to `out/web/MemoryMap.json` for the
register browser. All outputs stay under `platform/common/out/web/` (golden rule).

**Drift gate.** `python/check_configurator_sync.py` compares the configurator HTML
against the generator; it now takes **`--strict`** (exit non-zero on any drift) while the
default stays WARN-only. **Consumption contract for the HTML:**
the configurator declares a spliceable region

```html
/*VESTA_DATA_BEGIN*/ … /*VESTA_DATA_END*/
```

and `python/splice_web_data.py --data out/web/chip_data.js ../docs/chip_configurator.html`
injects the current bundle between those markers (idempotent; `--data` defaults to
`out/web/chip_data.js`; `--check` reports staleness). The markers
are added on the HTML side by its owner; the splice tool only needs to exist here.

---

## Castalia vs. Myshkin (what changed in this fork)

Chip definition (`python/generate.py`):
- `asicName='Castalia'`; the vector count is derived (121 today), with CLINT msip=83, mtip=84 and the router's meip slot at 85
- New shared-window peripherals with **absolute base addresses** (no legacy slot):
  `CLINT` @ `0x5000`, `MUTEX` bank @ `0x6000`, `IRQROUTER` @ `0x7000`
- `ExtraMemorySections`: `SHARED_RAM` @ `0x10000` (the whole `memory.sharedBulkRamSize`, 64 KiB today) and, when the NPU is present, `NPU_RAM` @ `0x0C000`, for the linker script
- `SharedWindowSections`: shared-window rows for the TRM address-space diagram
- `ExtraLatexIntroFiles`: the hand-written Multi-Core Architecture chapter

Generator engine (`python/`):
- `Peripheral`/`ChipGenerator.CreatePeripheral` accept `absoluteBaseAddress=` for
  peripherals outside the legacy `0x4000` slot space, and `legacySlot=` for moved
  shared-window peripherals whose old `0x4000`-page slot number the RTL still uses
- The generator emits an "MCU_MP Compatibility" section into `out/hdl/MemoryMap.vhd`
  (per-vector `IRQB_*` names, `RegSlotSYS_*`, GPIO reset values in RTL port numbering,
  `pnum_*` pin constants, slot masks — driven by the `McuMpCompat` block in
  `generate.py`, values transcribed from the RTL package). `python/check_memorymap_vhd.py`
  diffs the generated package against `hdl/common/MemoryMap.vhd` by name/type/value
- The generator also produces the top-level integration RTL `out/hdl/MCU.vhd` by
  golden-master templating (`hdl_templates/MCU.template.vhd` holds the fixed boilerplate;
  `python/mcu_vhd.py` fills the `--@GEN:*@` regions — IRQ signals/`irq_comb`, shared-window
  slave fabric, dead-window zeroing, per-instance memory-bus port maps — from new
  `CreatePeripheral` bus metadata: `sharedBus`, `combinationalRead`, `clockDomain`,
  `strobeNote`). `python/check_mcu_vhd.py` exit 0 = byte-identical to the RTL minus header
- All output paths redirected into `out/` (see table above); signal-routing VHD is written
  as a fresh template instead of editing an `MCU.vhd` in place
- Python 3.6 compatible (`copytree` shim); address-space diagram fixed to use the same
  RAM-slot address formula as `memory.x` (the old code drew RAM at the wrong addresses)

Configuration-driven TRM (2026-07-06):
- The TRM PDF (`latex/TRM/TRM.pdf`) is built from the generated LaTeX tree;
  `chipName` renames the chip everywhere it appears (docs only - the generated RTL
  is name-independent and stays byte-identical to `hdl/common/`)
- The System Configuration feature list is GENERATED (`include/FeaturesList.tex`) from the
  instantiated peripheral set: each `PeripheralTemplate` carries a `latexFeatureSummary`
  bullet (with `{count}` instance-count substitution), and the multi-core bullets (hart
  count, shared RAM size, CLINT/mutex-count/IRQ-router presence) come from `numHarts=` and
  the shared-window peripherals actually created
- New config-driven LaTeX defines: `\NumHarts`/`\NumHartsWord`/`\MaxHartIndex`,
  `\VectorsCount`/`\TopVector`/`\RoutedVectorsCount`/`\MeipVector`/`\ClintMsipVector`/
  `\ClintMtipVector`, and the router row's `\IrqEnableWords`/`\IrqEnableWordsWord`/
  `\IrqEnuTopVector`/`\IrqEnuMsb` — the master template's prose and the IRQROUTER chapter
  use these (and `\AsicNameForUserGuide`) instead of hardcoded
  "Castalia"/"four-hart"/"85"/"three enable registers, vectors 0--84". (`\PeriphVectorsCount`
  is still emitted, but it is the CLINT's own vector number, NOT a count of peripheral
  vectors — the source list grew past it in digperiphs and no prose quotes it any more.) (`\SharedWindowStartAddress`/`\SharedWindowEndAddress` were
  retired in the D-series figure sweep: they were min/max over the address-space diagram's
  rows, not the RTL window's edges, and had no consumers.)
- Hand-written extra chapters are input via generated `include/ExtraIntroChapters.tex`
  (from `ExtraLatexIntroFiles`), so chapter filenames/revisions live in generate.py

TRM content:
- New chapter: **Multi-Core Architecture** (`latex/PeripheralIntroductions/MULTICORE-intro-castalia-2026-07.tex`)
  — harts/roles, shared window + arbitration, shared peripheral page map, boot mailboxes,
  synchronization rules
- New peripheral chapters: CLINT, MUTEX, IRQROUTER (intro prose + generated register tables)
- Interrupts, startup, and atomics sections updated for 4 harts
- Shared peripherals publish their real shared-window base addresses (UART0 at `0x12000`,
  the rest at `0x13000 + 256*legacy_slot`) in the register tables, C headers, and linker
  scripts — their legacy `0x4X00` windows read zeros in the RTL
- SYSTEM/NPU/TIMER/UART intros reviewed for Castalia (2026-07): NPU data formats and
  address-register semantics corrected against the RTL, timer clock-mux handoff procedure
  documented, shared-UART usage rules added, interrupt entry/exit contract corrected
  (hardware pushes only the return PC at sp-4)

Hand-maintained (survive regeneration, not overwritten):
- `latex/PeripheralIntroductions/*.tex` — per-peripheral prose (edit these, then regenerate)
- `latex/TRM/include/InterruptsTable_man.tex`, `SystemConfigurationList_man.tex` — thin
  wrappers selecting the generated tables
- `latex/TRM.template.tex` — the master document (edit this, never `latex/TRM/TRM.tex`)

Known TODOs:
- Package/pinout is inherited from Myshkin unchanged; the "preliminary" note is
  config-driven since G4 (`package.preliminary`). When a chip gets its own package:
  add a model to `_PACKAGE_MODELS` in `generate.py` and select it via `package.model`.
- ~~Last intro not yet reviewed for Castalia: SPI~~ DONE (2026-07-11, session 4):
  every intro now carries a `-castalia-` suffix. The SPI rewrite covers the M11
  shared window (SPI0 `0x4200` / SPI1 `0x4300`), the RX-read-clears-TCIF
  cross-hart side effect, the SMCLK/boot-clock rule, SPI1 as the droppable
  slave-capable instance, and the hart-0-only flash extended memory at the
  config-driven base (`\FlashBaseAddress`) with the M12 BOOT-pin/segment-loader
  boot story. The AFE/SARADC intros were deleted 2026-07-11 — both peripherals
  are removed from Castalia (originals live in `platform/`); this also moots the
  three missing AFE figures. GPIO was rewritten 2026-07-09 with the
  multi-alternate-function (PxAFS) work.
- ~~Cross-repo: the ROM bootrom must be rebuilt against the Castalia memory map~~ DONE
  (M12): the multicore bootrom (`software/bootrom_mp/`) implements the single-ROM boot —
  mhartid dispatch, shared-RAM mailbox zeroing, WFI tile park, and the msip tile loader.
- ~~The description's WDT register order contradicts the RTL~~ FIXED (G5a 2026-07-11):
  the description now carries the RTL order (WDT_PASS=12/WDT_CR=13/WDT_SR=14); the
  stale doc-side `RegSlotWDT*` constants in `hdl/common/MemoryMap.vhd` were aligned the
  same day (no RTL logic read them). Generation is warning-free and
  `check_memorymap_vhd.py` is drop-in clean. (The matching GPIO pin-reset-attribute
  discrepancy was FIXED 2026-07-09 with the multi-AF work.)
