# Changelog

All notable changes to VestaRV are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## Versioning scheme

VestaRV uses [semantic versioning](https://semver.org/) read against **silicon**, not an API:

| Bump | Meaning | Line |
|------|---------|------|
| **Major** | A new chip — a different piece of silicon, targeting its own tape-out | `2.x` |
| **Minor** | A substantial capability added to an existing chip: new ISA extensions, new peripherals, a new verification methodology, a physical-design close | `x.1.0`, `x.2.0`, … |
| **Patch** | Documentation, tooling, repository hygiene, and self-contained bug fixes | `x.y.1`, `x.y.2`, … |

**`1.x` is the single-core Myshkin line.** `1.0.0` is the taped-out chip (TSMC
65nm, November 2025); the `1.0.x` / `1.1.x` releases are post-tape-out bring-up,
characterisation and verification on the same silicon.

**`2.x` is the multi-core line and targets the next tape-out.** It is a different
chip: 4 harts, a shared-memory fabric, and a generator that emits the whole
configuration from one source. **No `2.x` release has been fabricated**; Castalia
and Argus are tape-out-ready designs. Only `1.0.0` exists in silicon.

Releases below were reconstructed retroactively; each names the commit it is
anchored to.

---

## [Unreleased]

### Added
- Physical CI (`physical.yml`): sky130 RTL-to-GDSII on GitHub-hosted runners — GHDL bridge and cocotb smoke on every PR/push, full LibreLane hardening weekly, on label, on dispatch and on release tags; signoff gated by `sky130/check_metrics.py` on `final/metrics.json`.
- Release automation (`release.yml`): a `vX.Y.Z` tag re-proves the physical flow and publishes a GitHub Release with this changelog's section as notes and the signoff bundle, bridge netlist and TRM as assets.
- Merge-queue support (`.github/MERGE_QUEUE.md`, `merge_group` triggers on the fast CI jobs).

### Changed
- CI runs on GitHub-hosted runners only, enforced by a `ci.yml` gate that rejects self-hosted targets.
- The CI simulation tier is now the open-source GHDL ISA regression, run as bazel tests (`//opensource_sim`) with a hermetic `@ghdl` toolchain.

### Fixed
- The register-browser provenance gate: added `splice_register_browser.py`; `make web` now splices and re-checks both docs pages.
- Self-hosted `sim.yml` runs never executed because the runner lacked its `cadence` label.
- A placeholder LinkedIn URL on the site's "Connect" card.

---

## [2.11.0] — 2026-08-05 — Machine identity CSRs

Anchor: `2f98999`

### Fixed
- `mvendorid`, `marchid`, `mimpid` and `mconfigptr` were missing from the CSR decode map, so reading them trapped; they now read zero (writes remain illegal).

### Added
- The `idcsrmp` detector test, which also checks the fix is neither over-wide (0xF10/0xF16 still trap) nor over-narrow (0xF14 reads).
- A "Machine Information Registers" section in the TRM privileged-architecture chapter.
- This changelog's retroactive version history and annotated tags for all prior releases.

### Changed
- The README describes the chip generator and its three chips; Core Specifications separates always-built features from per-configuration options.
- `sim.yml` job names reference their test lists instead of hardcoded counts.

---

## [2.10.1] — 2026-08-04 — Lineage merge and CI provenance fix

Anchor: `9e104b8`

### Added
- Merged the sky130 open-source flow: GHDL bridge, LibreLane config, cocotb smoke test, and a GHDL ISA regression (139/139, including Zfinx and crypto).

### Fixed
- Two GHDL synthesis blockers in the core (SH2ADD/SH3ADD `&` qualification; reserved `Zcmp` `rlist` 0–3 range clamp), behaviour-neutral on defined encodings.
- `docs/register_browser.html` re-embedded from the generated `MemoryMap.json` (stale `ENABLE_TRAPCSR`).

## [2.10.0] — 2026-08-04 — Per-configuration verification matrix

Anchor: `c7e7f94`

### Added
- A 28-row configuration matrix: every shipped knob combination is built, simulated and pinned.
- A constrained-random program generator (`tools/randgen`) and detector tests for each defect below.
- An image-polarity tripwire comparing standing-gate images across both `#ifdef` polarities.

### Changed
- `priv.trapCsr` defaults on for both chips; boot is bit-identical (`mtrapctl.LEGACY` resets to 1). Cost: +144 flops per tile, +3.85 % cell area, timing neutral.

### Fixed
- Six RTL defects: divider `INT_MIN` magnitude handling, an unqualified divide dispatch, `ZEXT.H` aliasing `pack`, `shamt[5]` accepted on RV32, and two comparator/tracer defects.
- Both divider defects are plausibly present in Myshkin silicon (shared lineage) and are flagged for validation.

## [2.9.0] — 2026-08-02 — Structural commit-path consolidation

Anchor: `a3180fa`

### Changed
- Consolidated 271 commit sites into 8 under a single commit block, bit-exact against a 4.6-million-record instruction trace.

### Added
- Permanent design assertions enforcing the commit invariant.
- 34 PSL properties on the four leaf units, 21 mutant-proven.

## [2.8.0] — 2026-07-31 — Lockstep co-simulation

Anchor: `f75ba3c`

### Added
- Spike lockstep co-simulation (`tools/cosim`), single- and multi-hart, with a tracked gate-file record and drift checker.

### Fixed
- Twelve RTL findings, including spurious bus traffic: a store every cycle in `TRAP_STATE`, a bus read on failed `sc.w`, a phantom read on every `iret` (silicon erratum), and `lr.w` addressing the wrong operand.
- Writes to read-only CSRs now trap in every build, so `unimp` traps instead of executing as a NOP.

## [2.7.0] — 2026-07-29 — Privileged architecture

Anchor: `74baa48`

### Added
- Standard M-mode trap CSRs and delivery (`mstatus`/`mtvec`/`mie`/`mip`/`mscratch`/`mepc`/`mcause`/`mtval`, custom `mtrapctl`), MRET/ECALL/EBREAK.
- U-mode: privilege register, MPP push/pop, `mcounteren`, `misa.U`, U-mode decode gate.
- PMP (Smpmp) physical memory protection.
- All three default off; the default build is bit-identical to the previous release.

### Fixed
- A U-mode CSR-write escape, a trapping-AMO write in the default build, and a PMP MRET-return escape.

## [2.6.0] — 2026-07-27 — Field power, event fabric, and the full-peripheral chip

Anchor: `8eeb491`

### Added
- EVFAB0 event fabric @0x6B00: an 8-channel crossbar routing 16 events to 10 tasks.
- Field-power mode: PGOOD boot gating, strap/field wake, per-bank shared-RAM gating, and a harvested-boot ROM path that provisions the NFC tag.
- A per-chip analog TRM chapter (bias generator, control amplifier, transimpedance stage) with generated figures.

### Fixed
- A VDD–VSS short in the PDB3A pad-ring cell, inherited family-wide.
- A nibble-packing bug in the harvested bootrom's `P6AFS` write.

## [2.5.0] — 2026-07-23 — Digital peripheral family and NPU modes

Anchor: `55361d9`

### Added
- Nine peripherals with RTL, bench, gate closure and generator integration: QSPI, I3C, NFC, RTC, PWM, 1-Wire, DMA (fifth arbiter master), I2C target mode, TRNG.
- NPU: signed architecture, CONV1D, XNOR-popcount binary and GEMM modes, activation functions (sigmoid/ReLU/tanh/clamp/exp).
- An NPU think-done interrupt.

### Fixed
- A gate-level X-collapse with three nested causes; the full-peripheral gate smoke passes 27/27.

## [2.4.0] — 2026-07-18 — ISA extensions and CI

Anchor: `539e87d`

### Added
- Scalar crypto: Zbkb, Zbkc, Zbkx, Zkn (AES + SHA).
- Zicboz cache-block zero; Zcmp/Zcmt code-size reduction.
- Zfinx single-precision FPU in the x-registers.
- GitHub Actions CI: generator, docs and software-build gates, plus a Cadence simulation tier.
- Core width parameterisation (`XLEN`/`ILEN`/`SHAMT_W`), no behaviour change.

### Fixed
- Divide aliasing from an ungated `EXECUTE`→`DIV_WAIT` writeback.
- A stale WDT unlock key in the register browser.

## [2.3.0] — 2026-07-16 — Interrupt fabric, chip-tops, and the public site

Anchor: `df5b9aa`

### Changed
- `irq_router` @0x7000 replaces the interrupt fan-out: PLIC-style claim/complete, one `meip` per hart, fixed lowest-ID priority; handlers use a plain-ret ABI.

### Added
- Pad-ring chip-tops for Castalia and Argus with Calibre DRC / Pegasus LVS harnesses and a make-based signoff front end.
- The public documentation site: landing page, schematics, chip configurator, register browser, roadmap.
- A power dashboard built from Genus/Innovus reports.

### Removed
- The SYSTEM0 interrupt enable/priority/recursion path.

## [2.2.0] — 2026-07-12 — Argus, signoff closure, and the repository split

Anchor: `382d361`

### Added
- Argus: an 18-hart teaching chip from the same source (128 KiB shared RAM, 32 hardware mutexes, no NPU).
- Signoff DRC (Calibre) and LVS (Pegasus) closure, MTCMOS verification, and rail analysis.
- A pre-commit gate that blocks committing a stale TRM.

### Changed
- `hdl/`, `platform/` and `innovus/` split per chip; Myshkin trees frozen.

## [2.1.0] — 2026-07-09 — Configurable ISA, power gating, and the pad ring

Anchor: `691f8fd`

### Added
- Configurable ISA extensions: M/A/C/Zb* as generics (disabled extensions trap and are generated away), advertised by a read-only `misa`.
- MTCMOS power gating: each hart tile is a header-gated domain with hardware sequencing via `PWRCTRL` @0x4B00.
- Multi-alternate-function GPIO (`PxAFS`, up to 8 AFs per pin).
- An interactive chip configurator and `CONFIG=` JSON input to `make chip`.

### Changed
- Digital-only respin: AFE and SARADC dropped.

## [2.0.0] — 2026-07-06 — Castalia: the multi-core chip and its generator

Anchor: `e45d58c` · **targets the next tape-out; not fabricated**

The single-core Myshkin SoC becomes a family of chips generated from one source.

### Added
- Multi-hart architecture: four harts behind a round-robin `mp_arbiter`, CLINT, 16-entry hardware mutex bank, grant-locked cross-hart atomics, LR/SC.
- Memory map: 16 KiB private TCM per hart; peripherals, 64 KiB shared bulk RAM and NPU staging RAM behind the shared window.
- Single-ROM boot: all harts start at 0x0 from one shared ROM; tiles park until an msip loader fills their TCM.
- Tile extraction: four identical `hart_tile` instances on a registered boundary, hardened once.
- The chip generator (`make chip`): headers, linker scripts, `MCU.vhd`/`MemoryMap.vhd` byte-identical to the RTL, and the TRM; `make verify` proves a configuration boots.
- Execute-from-shared support and a latency-insensitive arbiter.

### Fixed
- A `hw_clint_en` port default lost at a netlist boundary, which kept tiles from waking.

---

## [1.1.5] — 2026-07-01 — Peripheral verification suite

Anchor: `e195dea`

### Added
- Standalone VHDL testbenches for UART, GPIO, TIMER, SPI, I2C, SYSTEM and NPU, a shared helper library, and a unified Xcelium setup.

### Fixed
- UART RX overflow checked TX-complete instead of RX-complete, so overflows were never flagged.
- Compressed-instruction handling of `c.addi16sp` and compressed `jal`.

## [1.1.4] — 2026-06-29 — Simulation throughput and repository hygiene

Anchor: `a01bca7`

### Added
- Parallel Xcelium simulation runs.

### Fixed
- `flash_prepend.sh` program start address (0x8200 → 0x8000).

## [1.1.3] — 2026-05-05 — 12-bit DSADC acquisition

Anchor: `5e0ca46`

### Added
- A fast acquisition path and histogram tooling for the 12-bit dual-slope ADC.

## [1.1.2] — 2026-04-27 — Firmware toolchain and flash programming

Anchor: `02285fa`

### Added
- A C toolchain and firmware examples built against the generated `MemoryMap.h`.
- Flash programming: Raspberry Pi and UART programmers, and Forth-based RAM upload/streaming with corruption detection and retry.
- AFE bring-up firmware and dashboard bitfield support.

### Fixed
- Silicon bring-up: a wrong TIMER0 clock-source constant (0 Hz on silicon) and a GPIO2/Port 3 header mapping mix-up.

## [1.1.1] — 2026-04-19 — Publication restructure

Anchor: `9a0bc05`

### Changed
- Restructured for public release: `hardware/` renamed to `hdl/`; the TRM symlink replaced with a committed PDF.

## [1.1.0] — 2026-04-18 — Silicon bring-up and ADC characterisation

Anchor: `94022d5`

First substantial work on fabricated Myshkin silicon.

### Added
- The Forth dashboard: a bench debug GUI driving the chip over UART through its ROM Forth interpreter.
- SARADC acquisition with logging, histograms and INL/DNL analysis.

### Fixed
- An MSB inversion in ADC readings, and UART transaction corruption (now rejected by address-echo validation).

## [1.0.2] — 2026-03-19 — Documentation set

Anchor: `3d54553`

### Added
- Myshkin user guide and TRM, HDL and verification READMEs, this changelog, and GHDL/NVC simulation instructions.
- Silicon-validated status for the Myshkin tape-out.

## [1.0.1] — 2026-02-17 — Public repository release

Anchor: `4602ccc`

### Added
- The `implementations/` tree recording the Myshkin ASIC.
- A firmware project generator with a barebones template.
- Verification and firmware READMEs.

### Removed
- ARM IP and foundry files, excluded by pattern from the public repository.

---

## [1.0.0] — Nov. 2025 — Myshkin Tape-out

First complete VestaRV SoC tape-out, TSMC 65nm GP, November 2025.

### Added
- **VestaRV core**: RV32IMAC + Zba/Zbb/Zbc/Zbs multicycle processor
  - Stack-based recursive interrupt controller (83 vectors)
  - Fast hardware multiplier and multi-cycle divider
  - RVC split-fetch for compressed instructions at 4-byte boundaries
  - Machine-mode CSR unit
- **Peripherals**
  - GPIO (4× 8-bit ports with alternate-function mux)
  - SPI master × 2 (one with native SPI-flash extension)
  - UART × 2
  - I2C × 2
  - 32-bit Timer/Counter × 2
  - SYSTEM (clock mux, DCO, watchdog, CRC, power gating)
  - NPU (fixed-point neural network accelerator)
  - SARADC interface
  - AFE (potentiostat + 12-bit dual-slope ADC for electrochemical sensing)
- **Memory**
  - 16 KiB ROM (ARM Artisan)
  - 32 KiB RAM (2× 16 KiB ARM Artisan SRAM)
  - Native SPI flash read window
- **Firmware**
  - Bootrom with Forth interpreter (`rv4th`)
  - SPI flash boot
- **Verification**
  - RV32UI / RV32UM / RV32UA / RV32UC ISA suites (adapted from riscv-tests), run on the full chip in a VHDL testbench
  - Chip-level assembly peripheral tests, plus VHDL testbenches for selected peripherals
  - Benchmarks (Dhrystone, CoreMark-style)
- **Documentation**
  - [Technical Reference Manual](implementations/asic/myshkin-2025-11/docs/TRM.pdf)
  - Implementation, build-system and verification READMEs

### Implementation Details (Myshkin)
- **Die size**: 1.0 mm × 1.5 mm
- **Package**: QFN-44
- **Process**: TSMC 65nm GP CMOS
- **Supplies**: 1.0 V core / 2.5 V analog / 3.3 V I/O
- **Clock**: up to 24 MHz
- **AFE power**: < 325 µW at 2.5 V

---

## Repository History

Before 1.0.0, VestaRV was a private personal project. The first public release coincides with the Myshkin tape-out submission via the University of Nebraska-Lincoln (IC Design Group).

Every release from `1.0.1` onward has an annotated git tag, and the version headings link to each release's diff. `1.0.0` has no tag: the tape-out predates the repository's first commit.

<!-- Release comparison links. Generated from the tag list; regenerate if tags change. -->
[2.11.0]: https://github.com/maxxseminario/VestaRV/compare/v2.10.1...v2.11.0
[2.10.1]: https://github.com/maxxseminario/VestaRV/compare/v2.10.0...v2.10.1
[2.10.0]: https://github.com/maxxseminario/VestaRV/compare/v2.9.0...v2.10.0
[2.9.0]: https://github.com/maxxseminario/VestaRV/compare/v2.8.0...v2.9.0
[2.8.0]: https://github.com/maxxseminario/VestaRV/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/maxxseminario/VestaRV/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/maxxseminario/VestaRV/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/maxxseminario/VestaRV/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/maxxseminario/VestaRV/compare/v2.3.0...v2.4.0
[2.3.0]: https://github.com/maxxseminario/VestaRV/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/maxxseminario/VestaRV/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/maxxseminario/VestaRV/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/maxxseminario/VestaRV/compare/v1.1.5...v2.0.0
[1.1.5]: https://github.com/maxxseminario/VestaRV/compare/v1.1.4...v1.1.5
[1.1.4]: https://github.com/maxxseminario/VestaRV/compare/v1.1.3...v1.1.4
[1.1.3]: https://github.com/maxxseminario/VestaRV/compare/v1.1.2...v1.1.3
[1.1.2]: https://github.com/maxxseminario/VestaRV/compare/v1.1.1...v1.1.2
[1.1.1]: https://github.com/maxxseminario/VestaRV/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/maxxseminario/VestaRV/compare/v1.0.2...v1.1.0
[1.0.2]: https://github.com/maxxseminario/VestaRV/compare/v1.0.1...v1.0.2
[1.0.1]: https://github.com/maxxseminario/VestaRV/releases/tag/v1.0.1
