# Castalia Chip Generator

Generator for **Castalia**, the 4-hart multi-core VestaRV MCU (`hdl/common/`). This is a
fork of `platform/` (the single-core Myshkin generator) adapted for the multi-core chip.
One Python description (`python/generate.py`) is the single source of truth for the memory
map, every peripheral register and bit field, the GPIO/package pinout, and the Technical
Reference Manual.

**All outputs stay inside this directory.** Unlike `platform/`, nothing here writes to
`../software/`, `../tools/`, or `../hdl/` — the generated HDL goes to `out/hdl/` so the
hand-maintained `hdl/common/` RTL is never touched.

---

## Quick Start

```bash
cd platform/common
make chip                # generate every chip artifact AND build the TRM PDF
make chip CHIP_NAME=Foo  # same configuration, renamed chip (TRM title/prose, file headers)
make chip CONFIG=f.json  # apply a JSON configuration (see "Configuring a chip" below)
make generate            # artifacts only (no PDF); make pdf = PDF only
make web                 # export the machine-readable web bundle (see "Web data export")
make show                # print the resolved configuration + derived pad ring
make verify              # PROVE the configuration boots: stage the generated RTL into
                         # an Xcelium behavioral flow + run the ISA/sh smoke suite
                         # (CONFIG= as above; SUITE=full = whole regression; needs the
                         #  Cadence tools and the riscv-none-elf- toolchain)
```

## Configuring a chip (no RTL editing required)

The whole configuration is one small JSON file passed as `make chip CONFIG=config.json`
— produced interactively by **`../docs/chip_configurator.html`** or written by hand.
Every key is optional (missing keys keep the Castalia defaults) and the schema is
**validated**: an unknown key or out-of-range value is a hard error, never a silent
fallback. The knobs (authoritative list: `_CONFIG_SCHEMA` in `python/generate.py`, also
documented in the generated TRM's "Chip Configuration" section):

| Key | Meaning |
|-----|---------|
| `chipName` | Docs-only rename (TRM, headers); `CHIP_NAME=` on the make line wins |
| `numHarts` | Hart/tile count — 4 = Castalia golden master, 18 = Argus (sim-proven) |
| `numMutexes` | HW mutex bank size (16 = Castalia, 32 = Argus) |
| `registerFileDualPort` | Dual-port regfile (ASIC) vs single-port (FPGA) |
| `isa.*` | `mul fastMul div atomics compressed bitmanip counters counters64` |
| `memory.*` | `romSize tcmSizePerHart sharedBulkRamSize npuStagingRamSize` (bytes) |
| `peripherals.npu` | `false` = Argus-style chip with no NPU at all |
| `peripherals.i2c1` | `false` = drop the second I²C instance (slot 15 dead, vectors 70–82 reserved, SDA1/SCL1 pins revert to plain GPIO) |
| `peripherals.uart1` | `false` = drop the second UART (slot 5 dead, vectors 52–54 reserved, TX1/RX1 pins revert to plain GPIO) |
| `peripherals.spi1` | `false` = drop the second SPI (slot 3 dead, vectors 11–12 reserved, CS1/MISO1/MOSI1/SCK1 pins revert to plain GPIO) |
| `peripherals.timer1` | `false` = drop the second TIMER (slot 7 dead, vectors 22–27 reserved, T1CMP\*/T1CAP\* pins revert to plain GPIO) |
| `package.model` | Package model name defined in `generate.py` (`_PACKAGE_MODELS`: `myshkin-qfn44`, `castalia-quad-qfn64`, `castalia-lqfp100`). **Default since 2026-08-16: `castalia-quad-qfn64`** — the Castalia-Quad QFN-64 quad pinout, which also gates the TRM's Analog Front-End chapter. `config/castalia4.json` and the three `argus*.json` rows pin `myshkin-qfn44` (they are not that chip; see their `_packageNote`). |
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

`make chip` produces the complete Technical Reference Manual for exactly the generated
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
| `config/ChipConfig.resolved.json` | The resolved configuration: every knob + derived geometry (`make show` prints it) |
| `config/PadRing.json` | The derived pad ring (package model → pin/side/power-domain list) |
| `out/web/chip_data.js` | Web data bundle (`const VESTA_DATA = {…}`) — see below |
| `out/web/MemoryMap.json` | Copy of `config/MemoryMap.json` for the web register browser (`make web`) |

## Web data export (`make web`)

`make web` (also part of `make chip`) emits **`out/web/chip_data.js`**, a single
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

`make web` also copies `config/MemoryMap.json` to `out/web/MemoryMap.json` for the
register browser. All outputs stay under `platform/common/out/web/` (golden rule).

**Drift gate.** `python/check_configurator_sync.py` compares the configurator HTML
against the generator; it now takes **`--strict`** (exit non-zero on any drift) while the
default stays WARN-only (used by `make generate`). **Consumption contract for the HTML:**
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
- `asicName='Castalia'`, `vectorsCount=85` (adds CLINT msip=83, mtip=84)
- New shared-window peripherals with **absolute base addresses** (no legacy slot):
  `CLINT` @ `0x11000`, `MUTEX` bank @ `0x13000`, `IRQROUTER` @ `0x13900`
- `ExtraMemorySections`: `SHARED_RAM` @ `0x10000` (1 KiB) for the linker script
- `SharedWindowSections`: shared-window rows for the TRM address-space diagram
- `ExtraLatexIntroFiles`: the hand-written Multi-Core Architecture chapter

Generator engine (`python/`):
- `Peripheral`/`ChipGenerator.CreatePeripheral` accept `absoluteBaseAddress=` for
  peripherals outside the legacy `0x4000` slot space, and `legacySlot=` for moved
  shared-window peripherals whose old `0x4000`-page slot number the RTL still uses
- `make chip` emits an "MCU_MP Compatibility" section into `out/hdl/MemoryMap.vhd`
  (per-vector `IRQB_*` names, `RegSlotSYS_*`, GPIO reset values in RTL port numbering,
  `pnum_*` pin constants, slot masks — driven by the `McuMpCompat` block in
  `generate.py`, values transcribed from the RTL package). `python/check_memorymap_vhd.py`
  diffs the generated package against `hdl/common/MemoryMap.vhd` by name/type/value
- `make chip` also generates the top-level integration RTL `out/hdl/MCU.vhd` by
  golden-master templating (`hdl_templates/MCU.template.vhd` holds the fixed boilerplate;
  `python/mcu_vhd.py` fills the `--@GEN:*@` regions — IRQ signals/`irq_comb`, shared-window
  slave fabric, dead-window zeroing, per-instance memory-bus port maps — from new
  `CreatePeripheral` bus metadata: `sharedBus`, `combinationalRead`, `clockDomain`,
  `strobeNote`). `python/check_mcu_vhd.py` exit 0 = byte-identical to the RTL minus header
- All output paths redirected into `out/` (see table above); signal-routing VHD is written
  as a fresh template instead of editing an `MCU.vhd` in place
- Python 3.6 compatible (`copytree` shim); address-space diagram fixed to use the same
  RAM-slot address formula as `memory.x` (the old code drew RAM at the wrong addresses)

Configuration-driven TRM (2026-07-06, `make chip` = artifacts + PDF):
- `make chip` now also compiles `latex/TRM/TRM.pdf` (use `make generate` for artifacts only);
  `CHIP_NAME=<name>` renames the chip everywhere it appears (docs only — the generated RTL
  is name-independent and stays byte-identical to `hdl/common/`)
- The System Configuration feature list is GENERATED (`include/FeaturesList.tex`) from the
  instantiated peripheral set: each `PeripheralTemplate` carries a `latexFeatureSummary`
  bullet (with `{count}` instance-count substitution), and the multi-core bullets (hart
  count, shared RAM size, CLINT/mutex-count/IRQ-router presence) come from `numHarts=` and
  the shared-window peripherals actually created
- New config-driven LaTeX defines: `\NumHarts`/`\NumHartsWord`/`\MaxHartIndex`,
  `\VectorsCount`/`\PeriphVectorsCount`/`\ClintMsipVector`/`\ClintMtipVector` — the master
  template's prose uses these (and `\AsicNameForUserGuide`) instead of hardcoded
  "Castalia"/"four-hart"/"85". (`\SharedWindowStartAddress`/`\SharedWindowEndAddress` were
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
  same day (no RTL logic read them). `make chip` is warning-free and
  `check_memorymap_vhd.py` is drop-in clean. (The matching GPIO pin-reset-attribute
  discrepancy was FIXED 2026-07-09 with the multi-AF work.)
