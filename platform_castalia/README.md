# Castalia Chip Generator

Generator for **Castalia**, the 4-hart multi-core VestaRV MCU (`hdl/MCU_MP/`). This is a
fork of `platform/` (the single-core Myshkin generator) adapted for the multi-core chip.
One Python description (`python/generate.py`) is the single source of truth for the memory
map, every peripheral register and bit field, the GPIO/package pinout, and the Technical
Reference Manual.

**All outputs stay inside this directory.** Unlike `platform/`, nothing here writes to
`../software/`, `../tools/`, or `../hdl/` — the generated HDL goes to `out/hdl/` so the
hand-maintained `hdl/MCU_MP/` RTL is never touched.

---

## Quick Start

```bash
cd platform_castalia
./regenerate.sh          # or: cd python && python3 generate.py   (works on Python >= 3.6)
```

Then compile the TRM PDF (needs TeX Live; no inkscape/shell-escape required — see SVG note below):

```bash
cd latex/TRM
pdflatex TRM.tex && pdflatex TRM.tex
```

or `make pdf` from this directory.

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
| `out/hdl/MemoryMap.vhd`, `MCU_routing_template.vhd` | Generated VHDL. `MemoryMap.vhd` is a verified **drop-in replacement** for `hdl/MCU_MP/MemoryMap.vhd` (full behavioral_mp regression passes with the cell list pointed at it, 2026-07-04) but is not wired into the build; the routing template is reference-only |
| `config/MemoryMap.json` | Machine-readable full memory map |

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
  diffs the generated package against `hdl/MCU_MP/MemoryMap.vhd` by name/type/value
- All output paths redirected into `out/` (see table above); signal-routing VHD is written
  as a fresh template instead of editing an `MCU.vhd` in place
- Python 3.6 compatible (`copytree` shim); address-space diagram fixed to use the same
  RAM-slot address formula as `memory.x` (the old code drew RAM at the wrong addresses)

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
- AFE intro: three figures (`fsmstatediagram.png`, `dsTimingDia.png`, `peripheral.png`) are
  missing from the repo; their figure blocks are commented out with `TODO(castalia)` markers
  (same figures are also unresolved in `platform/`).
- Package/pinout is inherited from Myshkin unchanged (§2 carries a "preliminary" note) —
  revisit when Castalia gets a package.
- Remaining intros not yet reviewed for Castalia: AFE, SARADC, SPI, GPIO (their filenames
  keep the inherited `-myshkin-`/undated suffixes until reviewed; see CLAUDE.md).
- Cross-repo: the ROM bootrom must be rebuilt against the Castalia memory map (it was
  compiled with UART0 at `0x4400`, which now reads zeros — the BOOT-pin-low Forth console
  path is dead until then; SPI-flash boot is unaffected).
- The description's WDT register order (WDTCR=12/WDTSR=13/WDTPASS=14) contradicts the RTL
  (WDT_PASS=12/WDT_CR=13/WDT_SR=14) — the TRM and `MemoryMap.h` document these offsets
  wrong. Same for the GPIO0/GPIO1 pin reset attributes (trap DIR, lfxt/hfxt SEL, tx0 DIR).
  `make chip` warns about both; the generated VHDL emits the RTL truth.
