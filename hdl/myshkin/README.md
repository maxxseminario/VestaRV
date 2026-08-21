# VestaRV MCU

This directory contains the RTL for the complete VestaRV MCU system — the processor core, all peripherals, top-level integration, and shared components.

---

## Building and testing with Bazel

This is the frozen single-core tape-out snapshot, so it has no Bazel targets of
its own. What covers it is the tree-wide source handle and the graph-level
checks. Every command is run from the repo root.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

| Target | Verb | What it proves |
|---|---|---|
| `//hdl:vhdl_sources` | build | this directory's `*.vhd` files are declared build inputs, so an edit here is visible to the graph instead of silently invisible to it |
| `//tools:check_tracer_independence_test` | test | the tracer independence guard, which scans every file in `//hdl:vhdl_sources` |
| `//hdl/common/tb:mp_arbiter_tb`, `//hdl/common/tb:pmp_unit_tb` | test | the GHDL unit benches - note they bind the shared `hdl/common/` RTL, not this snapshot |
| `//opensource_sim:isa_regression` | test | the ISA regression, likewise against `hdl/common/`, not this snapshot |

Two things stay outside Bazel here on purpose: the Myshkin generator
(`platform/myshkin`) overwrites tracked files in place, so it is run directly
by its own scripts, and the Cadence flows are licensed binaries that keep
theirs.

The full target map is in [`BAZEL.md`](../../BAZEL.md).

---

## Architecture Overview

![MCU Block Diagram](../../assets/ASIC_block_diagram.png)

### Memory Map

The memory map is configurable and varies between implementations. The general layout order is:

| Region | Description |
|--------|-------------|
| ROM | Boot ROM — holds the bootloader and initial program |
| Peripheral I/O | Memory-mapped peripheral registers, one slot per peripheral |
| RAM | Data RAM — program stack and heap |
| Interrupt Vectors | IRQ vector table, located within or just above RAM |
| SPI Flash window | Optional native SPI flash read window for XIP execution |

See the implementation-specific READMEs (e.g., [`implementations/asic/myshkin-2025-11/README.md`](../../implementations/asic/myshkin-2025-11/README.md)) for concrete address values.

---

## Processor Core — `vesta/`

The **VestaRV** core is a single-issue, in-order, multicycle RISC-V processor implemented as a finite-state-machine datapath. It is not pipelined in the classical sense; each instruction executes through a fetch→decode→execute→writeback cycle controlled by a single FSM in `controller.vhd`.

### Key Microarchitecture Features

| Feature | Detail |
|---------|--------|
| ISA | RV32I + M + C + A + ZBA + ZBB + ZBC + ZBS |
| Privilege levels | Machine mode (M) |
| Multiplier | Fast (single-cycle) 32×32 hardware multiplier |
| Divider | Multi-cycle hardware divider |
| Compressed ISA (C) | Split-fetch handler for 16-bit instructions at 4-byte-aligned boundaries |
| Atomics (A) | LR/SC and AMO instructions |
| Interrupts | Stack-based recursive interrupt controller — up to 83 vectors, priority-encoded, re-entrant |
| Context switching | Software-managed (standard ABI register save/restore) |
| Clock gating | Instruction-retire clock gate (`cg_insret`) to reduce dynamic power |

### Core Source Files

| File | Description |
|------|-------------|
| `vesta.vhd` | Top-level core entity; instantiates datapath and controller |
| `datapath.vhd` | Register file, ALU mux, PC logic, memory interface |
| `controller.vhd` | Main FSM — fetch, decode, execute, writeback, interrupt handling |
| `alu.vhd` | Arithmetic-logic unit (RV32IMACZB*) |
| `aludec.vhd` | ALU control decoder |
| `maindec.vhd` | Main instruction decoder |
| `irq_handler.vhd` | Interrupt priority encoder and stack-based context controller |
| `csr_unit.vhd` | Control and Status Register file (machine-mode) |
| `regfile.vhd` | 32×32-bit integer register file |
| `regfile_firq.vhd` | Fast-IRQ shadow register file variant |
| `regfile_sbirq.vhd` | Stack-based IRQ register file variant |
| `c_dec.vhd` | RVC compressed instruction decoder (expands 16-bit → 32-bit) |
| `div.vhd` | Multi-cycle integer divider |
| `extend.vhd` | Sign/zero extension unit |
| `loadext.vhd` | Load data alignment and extension |
| `store_ext.vhd` | Store data alignment |
| `branch_valid.vhd` | Branch condition evaluator |
| `pulse_extender.vhd` | One-shot pulse generation utility |

---

## Peripheral Modules — `periph/`

All peripherals share a common memory-mapped register interface: 32-bit word-addressed registers, byte-enable writes, synchronous reads. Interrupt lines feed the core's `irq_vector` input.

| Module | File | Description |
|--------|------|-------------|
| **GPIO** | `GPIO.vhd` | 8-bit bidirectional port with direction, pull-enable, and alternate function mux |
| **SPI** | `SPI.vhd` | SPI master with configurable clock polarity/phase and optional SPI-flash extension |
| **UART** | `UART.vhd` | Full-duplex UART with configurable baud rate |
| **I2C** | `I2C.vhd` | I2C master controller |
| **TIMER** | `TIMER.vhd` | 32-bit timer/counter with capture, compare, and PWM |
| **SYSTEM** | `SYSTEM.vhd` | System control: clock mux/divider, DCO trim, watchdog, CRC engine, power gating |
| **NPU** | `NPU.vhd` | Hardware neural network accelerator (fixed-point MAC array) |


For full register-level documentation of each peripheral, see the **Technical Reference Manual (TRM)** PDF at [`implementations/asic/myshkin-2025-11/docs/TRM.pdf`](../../implementations/asic/myshkin-2025-11/docs/TRM.pdf).

---

## Shared Components — `commune/`

Components in this directory are used by multiple modules across the design.

| Component | Description |
|-----------|-------------|
| `ClkGate` | Clock-gate cell — use this instead of combinatorial enables on clocks |
| `ClkDivPower2` | Divide-by-2ⁿ clock divider |
| `ClockMuxGlitchFree` | Glitch-free two-input clock multiplexer |
| `CRC16` | CRC-16/CCITT engine |
| `Synchronizer` | 2-FF CDC synchronizer for single-bit signals |
| `SynchronizerSLV` | CDC synchronizer for std_logic_vector |
| `GlitchFilter_behav` | Majority-vote glitch filter for pad inputs |
| `FPMac` | IEEE 754 single-precision multiply-accumulate (used by NPU) |
| `FPSigmoid` | Piecewise-linear sigmoid approximation (used by NPU) |
| `fixed_pkg_c.vhdl` | VHDL fixed-point arithmetic package |
| `macros.vhd` | Package containing common conversions |

---

## Top-Level Integration — `MCU.vhd`

`MCU.vhd` wires together:
- The VestaRV core
- Generic ROM and SRAM instances 
- All peripheral instances
- The address decoder (`adddec.vhd`)
- Pad cells (for ASIC implementation)
- Clock and reset distribution
- IRQ aggregation

The port list of `MCU` directly maps to physical chip pads and is the entry point for both FPGA and testbench instantiation.

---

## `MemoryMap.vhd` 

`MemoryMap.vhd` contains peripheral base addresses and register slot address constants.
