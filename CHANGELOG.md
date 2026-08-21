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

**`1.x` is the single-core Myshkin line** — `1.0.0` is the taped-out chip
(TSMC 65nm, November 2025), and the `1.0.x` / `1.1.x` releases that follow are
its post-tape-out bring-up, characterisation and verification work on the same
silicon.

**`2.x` is the multi-core line, and it targets the next tape-out.** It is a
genuinely different chip: 4 harts, a shared-memory fabric, a chip generator that
emits the whole configuration from one source. **No `2.x` release has been
fabricated** — Castalia and Argus are tape-out-ready designs. Only `1.0.0`
exists in silicon.

Releases below were reconstructed retroactively from the development log; each
names the commit it is anchored to.

---

## [Unreleased]

### Added
- **Physical CI (tier 3), `physical.yml`.** The sky130 RTL-to-GDSII flow now
  runs in CI on GitHub-hosted runners: the GHDL Verilog bridge and the cocotb
  core smoke sim on every PR/push/merge-group (minutes, hosted,
  required-check-safe), and the full LibreLane hardening weekly / on the
  `run-physical` PR label / on `workflow_dispatch` / on every release tag.
  Signoff is gated by `sky130/check_metrics.py` on `final/metrics.json` (six
  counts, present and zero; missing = fail), never on mid-run logs.
- **Release automation, `release.yml`.** Pushing a tag `vX.Y.Z` re-proves the
  physical flow at that tag (via `workflow_call` into `physical.yml`) and
  publishes a GitHub Release whose notes are that version's CHANGELOG section
  (a missing section fails the release) and whose assets are the signoff
  bundle (GDS, netlists, metrics, reports), the bridge netlist, and the TRM.
- **Merge queue doctrine, `.github/MERGE_QUEUE.md`** + `merge_group` triggers
  on the tier-1 and tier-3 fast jobs; `sim.yml` and the harden job stay out of
  the queue by design (shared license seat / 4–5 h wall time).

### Fixed
- **The register-browser provenance gate was red on main since `085eef9`** and
  had no repair tool (the K7/F-K5-2 class): the page's embedded memory map
  was stale against the generator. `splice_register_browser.py` now exists,
  `make web` splices and re-checks both docs pages, and the page is respliced.
- **The self-hosted sim runner never had the `cadence` label** — registered
  2026-07-18 with the labels prompt skipped, so `runs-on: [self-hosted,
  cadence]` never matched and every `sim.yml` run since then queued and was
  cancelled by its successor without a single test executing. Diagnosis and
  the one-click fix are documented in `.github/RUNNER_SETUP.md`; applying the
  label needs the repo GUI and is not yet done.
- The site's "Connect" card linked to a placeholder LinkedIn URL. `pages.yml`
  gates only on the relative-link checker, which classifies external URLs as
  unverified, so nothing caught it.

---

## [2.11.0] — 2026-08-05 — Machine identity CSRs

Anchor: `2f98999`

### Fixed
- **Four required read-only M-mode CSRs were absent from the decode map.**
  `mvendorid` (0xF11), `marchid` (0xF12), `mimpid` (0xF13) and `mconfigptr`
  (0xF15) were missing from `csr_addr_valid`, so a plain `csrr` of a CSR the
  specification *requires* every RISC-V core to implement raised an
  illegal-instruction exception — and because the reset configuration's
  `TRAP_STATE` is terminal, the hart wedged there forever. They now retire and
  read zero, which is a **defined** answer ("not implemented" / "not
  assigned"), not a missing one: discovery software must read these registers
  and interpret zero rather than infer absence. Writing any of them remains an
  illegal instruction in every build.

### Added
- A blind detector (`idcsrmp`) that guards the *shape* of the fix rather than
  just its outcome — it fails if the fix is over-wide (0xF10/0xF16 must keep
  trapping) or over-narrow (a legal 0xF14 read must succeed). It joins both
  standing lists, moving four counts on purpose: suite 141 → 142, default
  `SUITE=full` 148 → 149, Argus N=18 142 → 143, knobs-on canary 67 → 68.
- A "Machine Information Registers" section in the TRM's privileged-architecture
  chapter, deliberately outside the `trapCsr` guard because — unlike every
  register in the trap-CSR table — these five exist in *every* configuration.
- This changelog's retroactive version history, and annotated tags for all
  20 prior releases.

### Changed
- The README now describes the chip *generator* and its three chips rather than
  a single core, and Core Specifications separates what is always built from
  what is selectable per configuration (Zfinx, the crypto set, code-size
  extensions, U-mode, PMP, counters).
- `sim.yml` job names no longer carry hardcoded test counts. Both had gone
  stale — the smoke job claimed 27 against a 29-entry list, the full job 117
  against a standing 141 — so they name their source list instead of a number
  that rots.

---

## [2.10.1] — 2026-08-04 — Lineage merge + CI provenance fix

Anchor: `9e104b8`

### Added
- Merged the `sky130-flow` branch into the mainline: an open-source
  RTL-to-GDSII path (GHDL bridge, LibreLane config, cocotb smoke test) and a
  GHDL-based ISA regression running 139/139 including the Zfinx FPU and the
  crypto extensions.

### Fixed
- Two GHDL synthesis blockers in the core: a `std_logic_vector'` qualification
  for the SH2ADD/SH3ADD `&` overload, and a clamp on reserved `Zcmp` `rlist`
  encodings 0–3 that otherwise violate the declared `1..13` subtype range when
  the lookup is evaluated from reset. Both are behaviour-neutral on defined
  encodings.
- `docs/register_browser.html` re-embedded from the generated `MemoryMap.json`.
  It had carried a stale `ENABLE_TRAPCSR: false` since the trap-CSR default
  flipped, failing the CI provenance gate and publishing wrong data to the
  documentation site.

## [2.10.0] — 2026-08-04 — K-series: per-configuration verification matrix

Anchor: `c7e7f94`

### Added
- A 28-row configuration matrix: every shipped knob combination is built,
  simulated and pinned, rather than only the default build.
- A constrained-random program generator (`tools/randgen`) with a two-gate
  legality design, plus blind detector tests for each defect below.
- An image-polarity tripwire that compares every standing-gate image
  byte-for-byte across both `#ifdef` polarities.

### Changed
- **`priv.trapCsr` now defaults on for both chips.** The standard M-mode trap
  architecture ships in every build. Boot is bit-identical — `mtrapctl.LEGACY`
  resets to 1, so a chip boots on the legacy vector path and enters standard
  delivery only when firmware opts in per hart. Cost: +144 flops per tile,
  +3.85 % standard-cell area, timing neutral.

### Fixed
- **Six RTL defects**, each found by generated or matrix stimulus and each
  shipped with a detector that was proven to fail before the fix:
  divider magnitude handling at `INT_MIN`; an unqualified divide dispatch that
  let a split-fetch bubble re-arm the divider with the previous operation's
  selects; a `ZEXT.H` decode that aliased the `pack` encoding space; `shamt[5]`
  being accepted on RV32; and two comparator/tracer defects.
- Both divider defects are **plausibly present in taped-out Myshkin silicon**
  (shared `div.vhd`/`alu.vhd` lineage) — flagged for validation assessment.

## [2.9.0] — 2026-08-02 — S-series: structural retire of the commit path

Anchor: `a3180fa`

### Changed
- Consolidated 271 scattered commit sites into 8, migrating every FSM shape to
  a single commit block. Bit-exact at every one of the 19 commits — verified
  against a 4.6-million-record instruction stream that did not move.

### Added
- Permanent design assertions and masks enforcing the commit invariant.
- 34 PSL properties on the four leaf units, 21 of them mutant-proven.

## [2.8.0] — 2026-07-31 — Lockstep co-simulation + the F-series fix pass

Anchor: `f75ba3c`

### Added
- **Spike lockstep co-simulation** (`tools/cosim`): every retired instruction is
  compared against a reference model, single-hart and multi-hart, with a tracked
  gate-file record and drift checker.

### Fixed
- Twelve RTL findings closed, including several that committed real,
  side-effecting bus traffic where none was architecturally justified:
  `TRAP_STATE` performed a store on every cycle of its self-loop; a failed
  `sc.w` still performed a bus read; **every `iret` issued a phantom
  side-effecting read — recorded as a silicon erratum**; `lr.w` addressed the
  bus at the wrong operand and armed the reservation there.
- A write to a read-only CSR now traps in every build. This retroactively made
  the `unimp` encoding trap rather than being accepted and dropped as a silent
  NOP, which it had been for years.

## [2.7.0] — 2026-07-29 — Privileged architecture

Anchor: `74baa48`

### Added
- Standard M-mode trap CSRs (`mstatus`/`mtvec`/`mie`/`mip`/`mscratch`/`mepc`/
  `mcause`/`mtval` plus a custom `mtrapctl` legacy-select), standard trap
  delivery, MRET/ECALL/EBREAK.
- **U-mode**: privilege register, MPP push/pop, `mcounteren`, `misa.U`, and a
  U-mode decode gate.
- **PMP (Smpmp)** physical memory protection.
- All three default to off at this release; the build is bit-identical to a
  pre-P1 chip unless enabled.

### Fixed
- A U-mode CSR-write escape, a trapping-AMO write in the default build, and a
  PMP MRET-return escape — three real defects found by the programme itself.

## [2.6.0] — 2026-07-27 — Field power, event fabric, and the wound chip

Anchor: `8eeb491`

### Added
- **EVFAB0 event fabric** @0x6B00: an 8-channel PPI-style crossbar routing 16
  events to 10 tasks with pre-mask taps in ten blocks.
- **Field-power mode**: PGOOD hold-in-reset boot gating, strap/field wake
  sources, per-bank shared-RAM gating, and a harvested-boot ROM path that
  provisions the NFC tag and sleeps instead of downloading from flash.
- A per-chip analog TRM chapter with bias-generator, control-amplifier and
  transimpedance-stage characterisation, and generated waveform figures.

### Fixed
- **A real VDD–VSS short in the PDB3A pad-ring cell**, found during the
  symmetric wound-chip signoff and confirmed to be inherited family-wide.
- A nibble-packing bug in the harvested bootrom's `P6AFS` write, found by a
  composed board-level bench.

## [2.5.0] — 2026-07-23 — Digital peripheral family + NPU modes

Anchor: `55361d9`

### Added
- **Nine new peripherals**, each with RTL, a bench, gate closure and generator
  integration: QSPI, I3C, NFC, RTC (always-on wall clock), PWM (2-channel,
  shadow-buffered), 1-Wire, **DMA** (the first new arbiter master, N=5),
  I2C target mode, and a TRNG.
- **NPU P4 family**: signed architecture, CONV1D mode, XNOR-popcount binary
  mode, GEMM mode, and activation functions (sigmoid/ReLU/tanh/clamp/exp).
- A think-done interrupt for the NPU.

### Fixed
- A gate-level X-collapse root-caused to three nested defects; the wound gate
  smoke went 27/27 green for the first time.

## [2.4.0] — 2026-07-18 — X-series ISA extensions + CI

Anchor: `539e87d`

### Added
- **Scalar crypto**: Zbkb, Zbkc, Zbkx, and Zkn (AES + SHA).
- **Zicboz** cache-block zero, **Zcmp**/**Zcmt** code-size reduction.
- **Zfinx** single-precision FPU operating in the x-registers.
- GitHub Actions CI: generator gates, docs gates, software build, and a
  self-hosted Cadence simulation tier.
- Core width parameterisation (`XLEN`/`ILEN`/`SHAMT_W`) replacing hardcoded
  32-bit widths, with no behaviour change.

### Fixed
- A divide-aliasing bug: an ungated `EXECUTE`→`DIV_WAIT` writeback.
- A stale WDT unlock key in the register browser, caught by the first CI run.

## [2.3.0] — 2026-07-16 — Interrupt fabric, chip-tops, and the public site

Anchor: `df5b9aa`

### Changed
- Replaced the interrupt fan-out with **`irq_router`** @0x7000: a PLIC-style
  controller with atomic claim/complete, one registered `meip` wire per hart,
  exactly-once delivery, and fixed lowest-ID priority. Handlers moved to a
  plain-ret ABI under a dispatcher.

### Added
- Connected pad-ring chip-tops for Castalia (C0) and Argus (A6/A7), with
  Calibre DRC and Pegasus LVS harnesses and a make-based signoff front end.
- The public documentation site: landing page, schematic figures, interactive
  chip configurator, register browser and roadmap.
- A power dashboard scraping Genus/Innovus reports into a per-block page.

### Removed
- The SYSTEM0 interrupt enable/priority/recursion path and its packing quirk.

## [2.2.0] — 2026-07-12 — Argus, signoff closure, and the repository split

Anchor: `382d361`

### Added
- **Argus**, an 18-hart teaching chip generated from the same source with
  128 KiB shared RAM, 32 hardware mutexes and no NPU.
- Signoff DRC (Calibre) and LVS (Pegasus) closure, low-power MTCMOS
  verification, and rail analysis.
- A pre-commit gate that stops a stale TRM from being committed.

### Changed
- Split `hdl/`, `platform/` and `innovus/` into one directory per chip
  instantiation, freezing the Myshkin trees.

## [2.1.0] — 2026-07-09 — Configurable ISA, power gating, and the pad ring

Anchor: `691f8fd`

### Added
- **Configurable core ISA extensions**: M/A/C/Zb* become generics; a disabled
  extension traps as illegal and its hardware is generated away. A read-only
  `misa` CSR advertises the built set.
- **MTCMOS power gating**: every hart tile is a switchable header-gated domain
  with hardware gate/wake sequencing, driven by a new `PWRCTRL` @0x4B00.
- Multi-alternate-function GPIO (`PxAFS` plane select, up to 8 AFs per pin).
- An interactive chip configurator and a `CONFIG=` JSON input to `make chip`.

### Changed
- Digital-only respin: the AFE and SARADC analog blocks are dropped end to end.

## [2.0.0] — 2026-07-06 — Castalia: the multi-core chip and its generator

Anchor: `e45d58c` · **targets the next tape-out; not fabricated**

The single-core Myshkin SoC becomes a **family of chips generated from one
source**. This is a different piece of silicon, hence the major bump.

### Added
- **Multi-hart architecture**: four harts behind a serializing round-robin
  `mp_arbiter`, a CLINT (software + per-hart timer interrupts), a 16-entry
  hardware mutex bank, grant-locked cross-hart atomics, and LR/SC.
- **Memory-map rework**: a private 16 KiB TCM per hart, everything else behind
  the shared window — peripherals at their legacy addresses, 64 KiB shared bulk
  RAM, NPU staging RAM.
- **Single-ROM boot**: all four harts reset to PC 0x0 and fetch one shared boot
  ROM; tiles park until an msip loader fills their TCM. The preloaded-TCM
  fiction is retired end to end.
- **Tile extraction**: four structurally identical `hart_tile` instances on a
  registered boundary, hardened once and instantiated four times.
- **The chip generator** (`make chip`): headers, linker scripts, drop-in
  `MCU.vhd`/`MemoryMap.vhd` proven byte-identical to the live RTL, and the
  config-driven TRM PDF. `make verify` proves a configuration boots.
- Execute-from-shared support and a latency-insensitive arbiter.

### Fixed
- A `hw_clint_en` port default lost at a netlist boundary meant tiles could
  never wake — a silicon-class bug only the physical flow could catch.

---

## [1.1.5] — 2026-07-01 — Peripheral verification suite

Anchor: `e195dea`

### Added
- Standalone VHDL testbenches for UART, GPIO, TIMER, SPI, I2C, SYSTEM and NPU,
  plus a shared testbench helper library and a unified Xcelium setup.

### Fixed
- A UART RX overflow flag checking the wrong status bit (TX-complete instead of
  RX-complete), so overflows were never flagged.
- Compressed-instruction handling: `c.addi16sp` and compressed `jal`.

## [1.1.4] — 2026-06-29 — Simulation throughput and repository hygiene

Anchor: `a01bca7`

### Added
- Parallel Xcelium simulation runs.

### Fixed
- `flash_prepend.sh` program start address (0x8200 → 0x8000): the binary
  compiles the IVT to 0x8000 and start code to 0x8200.

## [1.1.3] — 2026-05-05 — 12-bit DSADC acquisition

Anchor: `5e0ca46`

### Added
- A fast DSADC acquisition path and histogram tooling for the 12-bit
  dual-slope converter.

## [1.1.2] — 2026-04-27 — Firmware toolchain and flash programming

Anchor: `02285fa`

### Added
- A C toolchain and firmware examples building against the auto-generated
  `MemoryMap.h`.
- Flash programming infrastructure: a Raspberry Pi programmer, a UART
  programmer, and Forth-based RAM upload/streaming tools with corruption
  detection and retry.
- AFE bring-up firmware and dashboard bitfield support.

### Fixed
- Silicon bring-up findings on real Myshkin parts: the TIMER0 clock source
  constant was wrong (the timer ran correctly in simulation but counted at 0 Hz
  on silicon), and a header/port mapping confusion between GPIO2 and Port 3.

## [1.1.1] — 2026-04-19 — Publication restructure

Anchor: `9a0bc05`

### Changed
- Restructured the repository for public release; renamed `hardware/` to
  `hdl/`; replaced the TRM symlink with a real committed PDF so it resolves on
  GitHub.

## [1.1.0] — 2026-04-18 — Silicon bring-up and ADC characterisation

Anchor: `94022d5`

First substantial work on fabricated Myshkin silicon.

### Added
- **The Forth dashboard**: a bench debug GUI driving the chip over UART through
  its ROM Forth interpreter, with live register and bitfield views.
- SARADC data acquisition with logging, histogram generation, and **INL/DNL
  analysis**.

### Fixed
- A hardware MSB inversion in ADC readings, and UART transaction corruption
  handled with strict address-echo validation.

## [1.0.2] — 2026-03-19 — Documentation set

Anchor: `3d54553`

### Added
- The Myshkin user guide and Technical Reference Manual, HDL and verification
  READMEs, this changelog, and open-source simulation build instructions
  (GHDL / NVC).
- Silicon-validated status for the Myshkin tape-out.

## [1.0.1] — 2026-02-17 — Public repository release

Anchor: `4602ccc`

### Added
- The `implementations/` tree recording the Myshkin ASIC (TSMC 65nm, November
  2025 tape-out).
- A firmware project generator with a barebones template.
- Verification and firmware READMEs.

### Removed
- ARM IP and foundry files, excluded by pattern from the public repository.

---

## [1.0.0] — Nov. 2025 — Myshkin Tape-out

First complete VestaRV SoC tape-out. Submitted to TSMC 65nm GP process, November 2025.

### Added
- **VestaRV core** — RV32IMAC + ZBA/ZBB/ZBC/ZBS multicycle processor
  - Stack-based recursive interrupt controller (83 vectors)
  - Fast hardware multiplier and multi-cycle divider
  - RVC split-fetch handler for compressed instructions at 4-byte boundaries
  - Machine-mode CSR unit
- **Peripheral set**
  - GPIO (4× 8-bit ports with alternate function mux)
  - SPI master × 2 (one with native SPI-flash extension)
  - UART × 2
  - I2C × 2
  - 32-bit Timer/Counter × 2
  - SYSTEM peripheral (clock mux, DCO, watchdog, CRC, power gating)
  - NPU — fixed-point neural network accelerator
  - SARADC — SAR ADC peripheral interface
  - AFE — potentiostat + 12-bit dual-slope ADC for electrochemical sensing
- **Memory configuration**
  - 16 KiB ROM (ARM Artisan)
  - 32 KiB RAM (2× 16 KiB ARM Artisan SRAM)
  - Native SPI flash read window 
- **Firmware**
  - Bootrom with Forth interpreter (`rv4th`)
  - SPI flash boot support
- **Verification**
  - Full RV32UI / RV32UM / RV32UA / RV32UC ISA test suite (adapted from riscv-tests) — implemented as RISC-V assembly programs simulated on the full chip in VHDL testbench
  - Peripheral verification primarily through assembly-level tests simulated at the full chip level; select peripherals additionally verified with dedicated VHDL-level testbenches (located in `hdl/MCU/tb/`)
  - Standard benchmark suite (dhrystone, coremark-style benchmarks)
- **Documentation**
  - [Technical Reference Manual](implementations/asic/myshkin-2025-11/docs/TRM.pdf)
  - Implementation READMEs for Myshkin ASIC
  - Build system and verification READMEs

### Implementation Details (Myshkin)
- **Die size**: 1.0 mm × 1.5 mm
- **Package**: QFN-44
- **Process**: TSMC 65nm GP CMOS
- **Target supply**: 1.0 V digital core / 2.5 V analog / 3.3 V I/0
- **Clock**: Up to 24 MHz
- **Analog front-end power**: < 325 µW at 2.5 V

---

## Repository History

Prior to the 1.0.0 release, VestaRV was developed as a private personal project. The initial public release coincides with the Myshkin tape-out submission via the University of Nebraska-Lincoln (IC Design Group).

Every release from `1.0.1` onward carries an annotated git tag, and the version
headings above link to the diff that release introduced. **`1.0.0` has no tag**
— the Myshkin tape-out predates this repository's first commit, so no commit
honestly represents it.

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
