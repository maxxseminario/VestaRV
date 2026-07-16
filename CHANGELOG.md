# Changelog

All notable changes to VestaRV are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

The 2026 program (branch `multicore-mp`) turned the single-core Myshkin SoC into a
**family of chips generated from one source**: a 4-hart multiprocessor (Castalia), an
18-hart teaching chip (Argus), and a config-driven `make chip` / `make verify` generator.
Entries below are grouped by era (newest first), dated from the development log.

### 2026-07-14 — Castalia C0: connected pad-ring chip-top
#### Added
- Connected `chip_top` wrapper wiring the hardened Castalia MCU assembly into the tphn
  pad ring; pads-in-DUT gate simulation.
- Chip-top DRC/LVS signoff pass.

### 2026-07-12 – 2026-07-14 — M19 / M19c: PLIC-lite interrupt fabric + gate-sim closure
#### Changed
- Replaced the M7 IRQ fan-out with `irq_router` @0x7000: a PLIC-style interrupt controller
  with atomic claim (@0x7800) / complete, one registered `meip` wire per hart delivered
  through IVT slot 85, exactly-once delivery, and lowest-ID fixed priority.
- Interrupt handlers moved to a plain-ret ABI under a MEIP dispatcher; CLINT software/timer
  interrupts (slots 83/84) keep classic hardware-vectored ISRs.
#### Removed
- Retired the SYSTEM0 interrupt enable/priority/recursion path and its ENU packing quirk.
#### Fixed
- M19c physical re-harden: tile SDCs refreshed, tile re-hardened (233 pins, −3.6% area),
  assembly re-P&R'd (binding gate 7/7).

### 2026-07-12 — Repository restructure + TRM publish drift gate
#### Changed
- Split `hdl/`, `platform/`, and `innovus/` into one directory per instantiation
  (`myshkin/` frozen, `common/` = the shared multi-core Castalia/Argus tree, `argus/`
  frozen snapshot).
#### Added
- TRM publish/drift gate (`make check-publish` + pre-commit hook) keeping the published
  PDFs in sync with the generator.

### 2026-07-10 – 2026-07-12 — Argus A0–A5: 18-hart derivative + chip-top
#### Added
- Parameterized the generator on hart count (`NHARTS`); **Argus**, an 18-hart teaching
  chip, is generated from `config/argus.json` with 128 KiB shared RAM (8× 16 KiB banks),
  32 hardware mutexes, and no NPU.
- 18-hart behavioral regression green; A4 compact-tile harden + 3×3 tile-array assembly;
  A5 connected `chip_top` (FLAT run, pads-in-DUT smoke).

### 2026-07-10 – 2026-07-12 — PG1–PG4: low-power verify + signoff DRC/LVS closure
#### Added
- PG1 low-power (MTCMOS power-gating) verification; PG2 rail analysis (IR/EM/inrush).
- PG3 signoff DRC (Calibre) + LVS (Pegasus); PG4 signoff closure (tile clean, MCU
  committed cut).

### 2026-07-06 – 2026-07-12 — Generator G-track: `make chip` / `make verify`
#### Added
- `make chip` now emits drop-in `MCU.vhd` + `MemoryMap.vhd` — byte-identical to the live
  `hdl/common/` tree (gated by `check_mcu_vhd.py`) — plus C headers, linker scripts, and
  the config-driven ~160-page TRM PDF.
- `make verify [CONFIG=…]` proves a configuration boots by staging the generated RTL into
  an Xcelium behavioral flow and running the multi-core boot/ISA smoke suite.
- Configurable ISA extensions and individually droppable peripherals; interactive
  `docs/chip_configurator.html` front-end; package model.

### 2026-07-07 – 2026-07-09 — M15–M17b: pad ring + power gating
#### Added
- M15 geometry pad-ring prototype; M16 analog floorplan.
- M17 power controller (`PWRCTRL` @0x4B00) + per-tile MTCMOS power gating with hardware
  gate/wake (cold-boot) sequencing; M17b PG signoff cleanup.

### 2026-07-06 — M10–M14: Castalia rework (memory + physical)
#### Changed
- M10 latency-insensitive (wait-for-release) arbiter + execute-from-shared support.
- M11 memory-map rework — private TCM per hart, everything else behind the shared-window
  arbiter; M12 single-ROM boot — all harts reset to PC 0x0 and fetch the shared boot ROM.
#### Added
- M13 tile extraction: four structurally identical `hart_tile` instances on a registered
  boundary; M14 physical tile harden + 4× assembly.

### Through 2026-07-05 — M1–M9: multi-core bring-up
#### Added
- Multi-hart architecture: a shared-memory window behind `mp_arbiter` (serializing
  round-robin), a CLINT (software + per-hart timer interrupts), a 16-entry hardware mutex
  bank, cross-hart atomics (grant-locked AMOs), and advisory LR/SC locks.
- Behavioral and gate-level (post-genus, SDF-annotated) bring-up, including gate-sim
  X-pathology closure.

### Earlier — peripheral testbenches
#### Added
- VHDL testbenches for the UART, GPIO, TIMER, SPI, and I2C peripherals.
#### Fixed
- UART RX overflow flag was checking the wrong status bit (TX-complete instead of
  RX-complete), so overflows never got flagged.

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
