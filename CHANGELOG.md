# Changelog

All notable changes to VestaRV are documented here.  
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### Planned
- FPGA reference implementation (Arty A7 or Nexys A7)
- Post-silicon characterization data for Myshkin (pending silicon return)
- CITATION.cff for academic referencing

---

## [1.0.0] — 2025-11-01 — Myshkin Tape-out

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
  - Native SPI flash read window at `0x8200`
- **Firmware**
  - Bootrom with Forth interpreter (`rv4th`)
  - SPI flash boot support
- **Verification**
  - Full RV32UI / RV32UM / RV32UA / RV32UC ISA test suite (adapted from riscv-tests)
  - Peripheral testbenches: NPU, SARADC, Forth interpreter
  - Standard benchmark suite (dhrystone, coremark-style benchmarks)
- **Chip generator**
  - Single-script generation of VHDL memory map, C headers, linker scripts, and LaTeX user guide
  - Peripheral intro LaTeX files for all peripherals
- **Documentation**
  - MCU User Guide (LaTeX → PDF, 130+ pages)
  - Implementation READMEs for Myshkin ASIC
  - Build system and verification READMEs

### Implementation Details (Myshkin)
- **Die size**: 1.0 mm × 1.5 mm
- **Package**: QFN-44
- **Process**: TSMC 65nm GP CMOS
- **Target supply**: 1.2 V digital core / 2.5 V I/O and analog
- **Clock**: Up to 24 MHz
- **Analog front-end power**: < 325 µW at 2.5 V

---

## Repository History

Prior to the 1.0.0 release, VestaRV was developed as a private research project at the University of Nebraska-Lincoln (Analog, Mixed-Signal, and System-on-Chip group). The initial public release coincides with the Myshkin tape-out submission.
