---
name: castalia-chipgen
description: Work on the platform/common chip generator — add/modify config knobs, droppable peripherals, memory-map or register changes, and TRM documentation. Use whenever editing generate.py/mcu_vhd.py/hdl_templates, adding a CONFIG= schema key, dropping/adding a peripheral instance, or doing TRM/intro work. Encodes the gate ritual, the end-to-end knob checklist, and the degrade idioms that have burned sessions.
---

# platform/common chip generator + TRM work

Single source of truth: `platform/common/python/generate.py`. The RTL wins; the
generator documents it. `hdl/common/MCU.vhd` IS the `make chip` product — NEVER
hand-edit it (edit `hdl_templates/MCU.template.vhd` fixed regions or
generate.py/mcu_vhd.py generated regions, then `make chip` and copy
`out/hdl/MCU.vhd` over it). Read `platform/common/CLAUDE.md` for the current
facts; THIS skill is the procedure.

## THE GATE RITUAL (run after EVERY change, no exceptions)

```bash
cd ~/vestarv/platform/common
make chip [CONFIG=config/foo.json]      # or make generate for artifacts-only
python3 python/check_mcu_vhd.py         # must exit 0: STRICT IDENTICAL at defaults
python3 python/check_memorymap_vhd.py   # must end: DROP-IN COMPATIBLE
# build log must be warning-free and end "configurator sync: OK"
```

- **After ANY `CONFIG=` run, re-run plain `make chip` (or `make generate`)** so
  `out/` holds the Castalia artifacts again, and re-verify check_mcu_vhd exits 0.
- `make verify [CONFIG=…]` PROVES a config boots: stages out/hdl into
  `xcelium/riscv_test/verify_<chip>/`, builds images at the config's NHARTS,
  runs the ~26-test smoke. `source ~/vestarv/cdspaths.sh` first; 600 s hard
  timeout per sim (HUNG = FAIL); modest MAX_PARALLEL (shared license).
- The G3 sync checker WILL print DRIFT for any new schema key until
  `docs/chip_configurator.html` learns it — that is it working, not a bug.
- Milestone discipline: default build STRICT IDENTICAL **after each knob**, not
  just at the end. A carve of fixed template into emitters must be a **proven
  no-op first** (emit at defaults, byte-diff) before any gating logic lands.

## Checklist: new config knob / droppable peripheral instance

The proven chain (G1a i2c1, G1b uart1/spi1/timer1 — mirror them):

1. `_CONFIG_SCHEMA` key + validator; hoisted presence flag with a comment.
2. `CreatePeripheral(...)` gate in generate.py.
3. **Frozen IRQ vectors**: the instance's vectors become `IRQB_RSVD<n>` (85
   total, NEVER renumber, never touch CLINT 83/84). Gate
   `_mcuMpIrqFirstVector[NAME]`. mcu_vhd auto-skips RSVD in decls/irq_comb.
4. Pin fallout in the GPIO tables: dropped primaries get `funcName=''` +
   reworded description (lint already relaxed); altFuncs whose SOURCE is the
   dropped peripheral get gated (cross-owner relocations on the same pins
   SURVIVE — e.g. TIMER AF1s on the SPI1 pins go with the timers, not spi1).
5. `_mcuMpPnums` AF1 groups: gate the dropped rows + compose the header
   (bidirectional altFunc↔pnum cross-check must stay satisfied).
6. Output-spread pool members leave `_GPIO_AF_SPREAD` via `_droppedSpreadFuncs`
   BEFORE the map is applied (the spread planes are emitted from the pins'
   FromSpread altFuncs; `SPREAD_SIG` in mcu_vhd.py owns spellings).
7. `McuMpGeometry[...]` flag + resolved-config `peripherals` entry.
8. mcu_vhd.py: `__init__` drops (shslv / pg0SelOrder / busSpecs / shimGroups
   with comment variants), side template `MCU.template.<inst>.vhd`
   (`@<INST>BLOCK:` pad decls + instance carrying its own `--@GEN:bus:<inst>@`),
   degrade emitters for mixed regions, crossCheck side-block guard, dispatch +
   `expected` set + bus-marker exclusion list.
9. Configurator HTML: DEFAULTS + toggle/control + `configObject()` +
   `SCHEMA_TO_CFG`; sync checker `DEFAULTS_TO_SCHEMA`.
10. `verify_stage.py`: config_tags + test tags — **decide by READING each
    sh-test .S** (shlock TXes on UART1; shperiph = SPI1+UART1 roles; shtimer
    role 1 = TIMER1; shuart/afsel survive drops). When in doubt, gate the test.
11. Proof config `config/castalia_no<inst>.json` → `make verify` PASS →
    plain `make chip` → full gate ritual.

## Degrade idioms (VHDL aggregates — each has burned a session)

- Named aggregates need FULL choice coverage: dropped rows become `'0'`
  bindings (the hi-Z "unassigned" idiom), NEVER deletions.
- **Aggregate-FINAL rows have no trailing comma** — a degrade regex requiring
  `,` silently skips them and you find out via xmvhdl IDENTU. Carry `,?`.
- Surviving pnum constant (AF0 transcription groups) → keep the pnum choice,
  drive `'0'`. Gated pnum (AF1 relocation constants leave MemoryMap.vhd with
  their owner) → literal pin index.
- Plain-GPIO passthroughs (`p2_out(0)` ex-CS1, `p3_out(pnum_gpio2_t1_cap0)`)
  survive drops — they reference no dropped signal and ARE the plain-GPIO
  idiom. afsel.S's negative control depends on the P2.0 one.
- Hunt SECONDARY references to dropped signals beyond the obvious regions:
  input muxes, ren_in muxes, tie-offs (`t1_cap1_out <= '0'` ex-SARADC), fabric
  decls. `grep <sig> out/hdl/MCU.vhd` on the dropped build until clean.

## Transcription discipline (mcu_vhd.py)

- generate.py owns FACTS; mcu_vhd.py owns transcribed RTL STRUCTURE (spellings,
  orders, narrative comments); cross-checks RAISE on disagreement.
- Carving fixed template → emitter: extract the exact lines by script
  (`repr()` per line, trailing whitespace preserved), paste as a module table,
  and prove byte-identity at defaults before writing any degrade logic.
- Python stays 3.6-compatible (no walrus/dirs_exist_ok/f-string `=`);
  mcu_vhd.py indents with TABS.
- NEVER `python3 -c "…"` on this machine (aoj_cal wrapper strips quotes) —
  write script FILES (scratchpad).

## TRM / documentation

- Edit `latex/TRM.template.tex`, `latex/PeripheralIntroductions/*.tex`,
  `packages-commands.template.tex` — everything in `latex/TRM/` except
  `include/*_man.tex` is overwritten by `make chip`.
- Config-conditional prose: `\ifnpupresent` / `\ifpackagepreliminary` pattern —
  add new `\newif` defines in LatexUserGuide.py `GenerateDefinesFile()`.
- Intro naming: `-castalia-<YYYY-MM>` = reviewed for Castalia; `-myshkin-` /
  undated = not yet. On review: rename, update generate.py's
  `latexIntroFileName`, delete the superseded copy. Verify addresses against
  the M11 map (legacy 0x4X00 slots) — two "reviewed" intros still carried
  pre-M11 addresses once.
- Chapters are per-INSTANCE (a dropped instance loses its chapter
  automatically); shared-template prose mentioning the sibling instance should
  be written config-agnostically ("in configurations that include it").
- Figures: pre-converted PDFs via `latex/figures/svg2pdf.py` — never
  `\includesvg`.
- After a TRM content change worth publishing: copy `latex/TRM/TRM.pdf` to
  `implementations/asic/castalia/docs/TRM.pdf`.

## Never

- Touch `hdl/myshkin/` or `platform/` (frozen Myshkin), or overwrite
  `software/bootrom/bin/rom.rcf`.
- Commit without the user's OK; never commit PDK/foundry artifacts (public repo).
- Renumber IRQ vectors or move the extended-flash base off the strict
  complement of sh_sel.
