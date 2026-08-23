# Castalia ASIC Implementation

Castalia is a **five-hart wound-monitoring MCU**, and it is not five identical cores.
Hart 0 is the always-on soft **orchestrator**, emitted as `entity work.orch_tile`; harts
1-4 are the **channel tiles**, four instances of one hardened `hart_tile` macro, uniform
with each other and individually power-gateable. It is derived from the same core as the
single-core Myshkin tape-out, and is generated from one configuration by the
`platform/common/` chip generator.

## Hart 0 and the four tiles

`orchestrator = true` is what makes hart 0 the orchestrator. It keeps every hart-0 wiring
special the chip already had - the SPI0 flash/XIP quartet, `sleep => sleep_cpu`,
`trap_flag` on the GPIO0 trap pin, `tcm_pgen => pgen_mem(1)`, arbiter master slice 0 with
no isolation clamps - and it is the management hart: it runs boot, owns the console and
the CLINT, and is the only master the read-only per-hart TCM apertures answer. Harts 1-4
are fully uniform channel tiles - hart IDs 1-4, `pwr_ctrl` rows 1-4 (so PWRCR carries a
gate bit for every one of them), isolation clamps, `tcm_pgen => pd_sleep(h)`. The
orchestrator sits outside the MTCMOS fabric entirely, so its PWRCR bit reads 0 and ignores
writes, and a blanket PWRCR write gates every channel tile and leaves the orchestrator
running.

`isa.minimalTiles = true` makes the four tiles **rv32iac**: they drop M and B, while hart 0
keeps the full chip ISA (`rv32imac_zba_zbb_zbs_zbc`). This is the one ISA asymmetry the
chip has, and it lands on the seam that already exists - hart 0 is soft, harts 1-4 are one
hardened macro placed four times - so the split costs no extra hardening. A and C are
deliberately not dropped: the tiles are exactly the harts that run the shared-fabric LR/SC
and AMO locking, so removing A would break the mutex infrastructure outright, and C is
decoder-only while it shrinks code, which matters more now that a TCM is 8 KiB. Measured
at genus on the 8 KiB tile, full ISA vs rv32iac: tile 132,657 -> 109,926 um2 (-17.1%),
core 60,540 -> 37,808 um2 (-37.5%), 2,576 -> 2,210 flops, 2.687 -> 1.945 mW (-27.6%),
460 -> 379 uW leakage.

**Software contract.** No binary may migrate between hart 0 and a corner tile, and
anything the tiles execute must be built without M and B.

## Building through Bazel

Castalia is the default (golden-master) configuration of the Bazel-managed
`platform/common/` generator. Run all commands below **from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

### Generating the chip

```sh
tools/bin/bazel build //platform/common:chip_artifacts_castalia
```

| Target | What it produces |
|--------|------------------|
| `//platform/common:chip_artifacts_castalia` | The whole Castalia artifact tree: drop-in RTL (`MCU.vhd`, `MemoryMap.vhd`, `riscv_tb.vhd`), `MemoryMap.h`, `periph.S`, linker scripts, pad-ring JSON/TCL, the web data bundle, and the TRM LaTeX project. |
| `//platform/common:chip_artifacts_castalia_repro` | A second, independent generation of the same configuration, for the determinism gate to byte-compare against. |
| `//platform/common:castalia_mcu_vhd`, `:castalia_memorymap_vhd`, `:castalia_riscv_tb_vhd` | Named handles on the individual drop-in RTL files. |
| `//platform/common:castalia_memorymap_h`, `:castalia_periph_s`, `:castalia_linker_scripts`, `:castalia_software_include` | The firmware-facing half of the same tree. |
| `//platform/common:castalia_padring_json`, `:castalia_padring_tcl` | The pad-ring description consumed by the physical flow. |
| `//platform/common:trm_latex_tree` | The generated TRM LaTeX project, as one directory artifact. |

Never run `bazel run //:generate` - that is the raw generator and it writes
wherever it happens to be invoked. The hermetic path is
`//platform/common:chip_artifacts_castalia`.

### Gates attached to those artifacts

`tools/bin/bazel test //platform/...` runs all of these:

| Target | What it proves |
|--------|----------------|
| `//platform/common:check_mcu_vhd_test` | The regenerated `MCU.vhd` is a byte-for-byte drop-in for the tracked `hdl/common/MCU.vhd`. |
| `//platform/common:check_memorymap_vhd_test` | Constant-by-constant equivalence with the tracked `hdl/common/MemoryMap.vhd`. |
| `//platform/common:check_riscv_tb_vhd_test` | The generated `riscv_tb.vhd` still matches the tracked 5-hart testbench. |
| `//platform/common:check_memorymap_h_test` | The emitted `MemoryMap.h` still compiles, under the hermetic RISC-V gcc. |
| `//platform/common:check_intro_names_test` | Every register named in a hand-written peripheral intro is something the generator actually emits. |
| `//platform/common:check_configurator_sync_test` | `docs/chip_configurator.html` is in sync with the generator, at the strict bar. |
| `//platform/common:splice_web_data_check_test` | The `VESTA_DATA` block spliced into the configurator page is not stale. |
| `//platform/common:generation_determinism_test` | Two independent generations are byte-identical. |
| `//platform/common:trm_latex_tree_test` | The generated TRM tree is complete: master document, includes, figures. |
| `//platform/common:castalia_analog_chapter_test` | The analog chapter is present in the generated TRM tree. |
| `//platform/common/python:check_config_defaults_test` | Each knob's two default literals in `generate.py` agree with each other. |

### TRM PDF

The PDF half is a Bazel-wrapped host TeX build, tagged manual:

```sh
tools/bin/bazel build //platform/common/latex/bazel:trm_pdf_local
tools/bin/bazel test //platform/common/latex/bazel:check_publish_test \
                     //platform/common/latex/bazel:trm_lint_test
```

`:check_publish_test` is red whenever TRM-affecting commits have landed since
the last publish - that is the point of the gate. `:trm_lint_test` lints the
generated LaTeX.

### License-free simulation of this RTL

```sh
tools/bin/bazel test //opensource_sim:isa_regression
```

Nine GHDL ISA suites (`//opensource_sim:isa_rv32ui` and siblings) plus the unit
benches `//hdl/common/tb:mp_arbiter_tb` and `//hdl/common/tb:pmp_unit_tb`. No
licensed tools involved.

### Outside Bazel

Cadence flows (Genus, Innovus, Pegasus, Xcelium, `make verify`) are permanently
outside Bazel - they are licensed binaries behind a license server, so no
hermetic target can wrap them. Run them via `source cdspaths.sh`.

Full map of the Bazel build: [`BAZEL.md`](../../../BAZEL.md).

## Overview

- **Chip Name**: Castalia
- **Configuration**: 5-hart chip - one soft orchestrator plus four hardened channel tiles
- **Process Node**: TSMC 65nm
- **Package**: LQFP-100, 14 × 14 mm body, 0.5 mm pitch (`package.model = castalia-lqfp100`) *(preliminary — `package.preliminary` is still true)*

## Configuration

- **Cores**: 5× VestaRV32. Hart 0 (`orch_tile`, soft) is RV32IMAC + Zb*, ISA string `rv32imac_zba_zbb_zbs_zbc`; harts 1-4 (`hart_tile`, hardened, placed 4×) are rv32iac. Every hart has its own private TCM; hart ID via the `mhartid` CSR
- **Boot ROM**: 16 KiB shared boot ROM (all five harts reset to PC 0x0; the boot ROM dispatches on `mhartid`)
- **Private memory**: 8 KiB TCM per hart, plus five read-only TCM apertures through which the management hart - and only it - reads any hart's private TCM
- **Shared memory window** (arbitrated, serializing round-robin): 80 KiB of shared RAM — a 64 KiB shared bulk region (4× 16 KiB banks) plus a 16 KiB NPU staging RAM
- **Synchronization**: CLINT (inter-processor + per-hart timer interrupts), 16 hardware mutexes, and a per-hart PLIC-style peripheral interrupt router (claim/complete, any-vector-to-any-hart routing)
- **Interrupt vectors**: 121 (vectors 83/84 are the CLINT software/timer interrupts; 85 is the router's MEIP slot)

### Peripherals

- **GPIO**: 6× 8-pin ports (48 pins, all bonded on the LQFP-100) with edge-triggered interrupts and per-pin alternate-function mux (up to 8 AFs per pin)
- **Communication**:
  - 2× SPI (SPI0 provides memory-mapped access to external flash)
  - 2× UART with hardware parity
  - 2× I²C (master and slave mode)
- **Timers**: 2× 32-bit timers with PWM outputs and input capture
- **Compute**: 1× Neural Processing Unit (NPU) co-processor
- **Analog front end**: 5× `afe_stub` slaves - AFE0-3, one per channel site, owned by harts 1-4 respectively, plus the EIS engine, which stays hart-0/management-only
- **Near-field**: 1× NFC controller (NFC0)
- **Debug**: RISC-V debug module with a JTAG DTM (`debug.enable = true`; the LQFP-100 is the model that bonds the TAP)
- **System Control**: CRC16 engine, 2× digitally controllable oscillators, windowed watchdog timer, power controller (PWRCTRL), per-tile MTCMOS power gating with hardware gate/wake sequencing

## Directory Contents

- **`docs/`** — Technical documentation
  - `TRM.pdf` — Technical Reference Manual (config-driven, built by
    `//platform/common/latex/bazel:trm_pdf_local`)
- **`config/`** — Configuration files used for code generation (as available)

## Configuration Provenance

Castalia is the **default (golden-master) configuration** of the `platform/common/`
generator. The entire chip — memory-map headers, linker scripts, drop-in RTL, and the TRM
— is regenerated from one JSON configuration by
`//platform/common:chip_artifacts_castalia`; the Cadence `make verify` run proves the
configuration boots. Key knobs for this build: `numHarts = 5`, `orchestrator = true`,
`isa.minimalTiles = true`, `numMutexes = 16`, `memory.tcmSizePerHart = 8 KiB`,
`memory.sharedBulkRamSize = 64 KiB`, `memory.npuStagingRamSize = 16 KiB`,
`peripherals.npu = true`, `package.model = castalia-lqfp100`. The tracked resolved form
is `platform/common/config/ChipConfig.resolved.json`; `config/castalia4.json` keeps the
historical four-identical-tiles shape as a standing matrix row.

## Silicon Status

**The last physical cut is `MCU_castalia_penta`, tag `cpr6`, Innovus signoff
database written 2026-08-17 22:39.** It *is* post-penta: the layout carries a
soft `orch_tile` as hart 0 and four hardened `hart_tile` macros as harts 1-4.
But it was hardened from `platform/common/config/penta_wound.json`
(`chipName = PentaWound`), **not** from the golden-master Castalia
configuration the rest of this README describes. Nothing physical has run since
2026-08-18.

Everything below was read out of the untracked EDA trees (`genus/`, `innovus/`,
`signoff_mp/`), which are gitignored and exist only on the build machine. Dates
are file mtimes there; they are the only provenance those artifacts carry.

### Where the flow actually stands

- [x] RTL complete (5-hart `hdl/common/` tree)
- [x] Behavioral verification (multi-core boot/ISA + shared-window suite)
- [x] `hart_tile` re-synthesized rv32iac and re-hardened at an 8 KiB TCM — 2026-08-17 02:20
- [x] Five-hart top placed & routed with a connected pad ring — `cpr6`, 2026-08-17 22:39
- [x] Signoff antenna (Calibre `ant25`) clean — 0 violations, 2026-08-18 00:07
- [ ] Gate-level (post-genus, SDF-annotated) verification — **partial.** All 7 smoke tests
      pass on the 2026-08-15 `cpr7` netlist, but only one of the seven (`rv32ui-p-simple`)
      was re-run on the final `cpr6` netlist, 2026-08-17 20:31. It passed. The other six
      have not been re-run against the netlist that was signed off.
- [ ] **Signoff DRC is NOT closed** — 2,354 `chipdrc` results, 2026-08-17 23:48
- [ ] **LVS is NOT closed** — Pegasus reports `MISMATCH`, 2026-08-18 00:21
- [ ] **The golden-master Castalia configuration has never been hardened** — see below

### What the hardened cut contains

`MCU_castalia_penta` is the pad-ringed chip top. There is no separate
`chip_top` wrapper any more; the C0-era `chip_top` was deleted 2026-07-27 and
the pad ring now lives inside this module.

| Measured at signoff | Value |
|---|---|
| Die | -155 to 2845 um, i.e. 3.0 x 3.0 mm; core box 1 to 2689 um |
| Top total | 1,903,469 gates, 84,311 placed cells, 2,284,164 um2 |
| `mcu0/hart0` (`orch_tile`, soft) | 111,897 gates, 16,180 placed cells, 134,277 um2 |
| `mcu0/hart1`-`hart4` (`hart_tile` macro, 4x) | 254,500 gates each, 305,400 um2 abstract each |
| `hart_tile` macro itself | 97,997 gates, 10,852 cells, 117,597 um2; antenna clean; setup +0.200 ns MET, hold +0.023 ns MET |
| Worst timing at chip signoff | setup +0.030 ns MET, hold +0.010 ns MET |
| Pad ring | 81 pads: 48 GPIO (`P0_0`-`P5_7`), `TCK`/`TDI`/`TDO`/`TMS`/`TRSTN`, `RESETN`, 8 analog-reserve (`ARSV0`-`ARSV7`), `AVDD`/`AVSS`/`POC`, 3x `VDD`/`VSS`, 3x `VDDPST`/`VSSPST`, 4 corners, 2 ring cuts |
| Debug | `debug_module dm0` and `jtag_dtm dtm0` are both in the netlist |

The core shape of that build matches this README: `numHarts = 5`,
`orchestrator = true`, `isa.minimalTiles = true`, 8 KiB TCM per hart, 64 KiB
shared bulk + 16 KiB NPU staging, 16 mutexes, `castalia-lqfp100`,
`debug.enable = true`, NPU and NFC on.

The **peripheral set does not match**. `penta_wound.json` turns on the wound
set — DMA, event fabric, I2C target, I3C, 1-Wire, PWM, QSPI, RTC, TRNG — which
the golden master leaves off, and it leaves `peripherals.cqAfeStubs` off, which
the golden master turns on. **No hardened netlist anywhere in the tree contains
the four `afe_stub` slaves or the EIS engine.** The analog front end this
README lists as a peripheral has never been through synthesis or place & route.

### What is not closed

**DRC.** The `cpr6` cut reports 2,354 Calibre `chipdrc` results against 1,770
for the July four-tile `MCU_castalia`. Seventeen routing-layer rule classes are
open that the July cut did not have at all: `M2.A.1` (177), `M7.S.4` (9),
`M4.A.1` (5), `M2.S.2` (4), `M4.S.1` (4), `VIA7.S.2` (4), `LUP.6` (3),
`M3.S.2` (3), `M7.S.3` (3), `M2.S.2.1` (2), and one each of `M1.S.1`,
`M5.S.3`, `M6.S.3`, `M6.S.4`, `VIA1.R.4:M2`, `VIA7.W.1`, `DM7.S.2`. These are
real metal spacing and minimum-area violations, not the base-layer and pad-cell
classes the C6 DRC endgame (2026-07-29) had already triaged as waivable. **The
"real classes 0" result that closed C6 does not carry over to this cut.**

Innovus agrees: `verifyGeometry` at signoff reports 308 SameNet violations, and
`verifyConnectivity` reports 2,779 problems (192 unconnected terminals, 967
special-wire opens, 1,620 regular opens), concentrated on the VSS ring and
stripes.

**LVS.** Pegasus reports `Run Result : MISMATCH`, with extraction errors,
connectivity mismatches and parameter mismatches. This is not a penta
regression — the July `MCU_castalia` (2026-07-29) and `chip_top_wound_quad`
(2026-07-27) runs record the same `MISMATCH`. **LVS has never closed on any
chip-level cut in this family**, and any earlier claim in this file that it had
was wrong.

**RTL drift.** Three commits change RTL that is inside the hardened cut and
post-date it, so no netlist reflects them: `e81e99a` (2026-08-21, NPU packed
operand modes — `npu0` is in the cut), `c089dc6` (2026-08-23, Debug Module
`abstractauto` — `dm0` is in the cut), and `23d3dca` (2026-08-20, `SARADC.vhd`,
which this build does not instantiate).

### Stale artifacts, for anyone reading the EDA trees

| Artifact | Date | Status |
|---|---|---|
| `signoff_mp/MCU_castalia_signoff` | 2026-07-29 | **Pre-penta.** The four-identical-tile cut. This is what the C6 DRC endgame closed. |
| `signoff_mp/chip_top_wound_quad_signoff` | 2026-07-27 | **Pre-penta.** Stage J wound quad. |
| `signoff_mp/chip_top_quad_signoff`, `chip_top_dp_signoff` | 2026-07-16 / 07-23 | **Pre-penta**, and `chip_top_dp` is a dead tape-out target. |
| `innovus/.../pre_tcm8k_bak/`, `signoff_mp/MCU_castalia_penta_base16k` | 2026-08-13 / 08-15 | Post-penta but **pre-8 KiB-TCM**: the `cp5` and `cpr7` cuts, archived when the TCM halved. |
| All published layout renders under `assets/` | — | Four-identical-tile signoff GDS. Pre-penta by construction. |

### Explicitly unknown

- Whether the golden-master Castalia peripheral set (AFE stubs on, wound
  peripherals off) closes timing or fits the same die. It has never been run.
- Whether the 81-pad ring in the cut is the final LQFP-100 bond-out.
  `package.preliminary` is still `true`.
- Whether the open DRC classes are fixable by ECO or need a re-route. No
  triage pass has been run on them.

## Publications

- Multi-core VestaRV derivative of the Myshkin single-core platform.

## Contact

For detailed specifications or collaboration opportunities, contact Maxx Seminario (mseminario2@huskers.unl.edu).
