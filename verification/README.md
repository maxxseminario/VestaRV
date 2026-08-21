# VestaRV Verification Suite

This directory contains comprehensive verification infrastructure for the VestaRV RISC-V processor core, including instruction-level tests, benchmarks, and test environments.

## Building and testing with Bazel

Bazel is the recommended way to build the test images and run the gates: it
fetches the exact pinned RISC-V cross compiler and a from-source GHDL, so a
fresh clone needs no local toolchain at all. The `make` flows below still work
and are kept as the legacy path. Every command is run from the repo root.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

| Target | Verb | What it proves |
|---|---|---|
| `//verification/isa:all_images` | build | every ISA image this repo builds - the eight CI suites plus `rv32uzf`, flashed and unflashed |
| `//verification/isa:ci_rcfs`, `//verification/isa:ci_images` | build | exactly the image set `./build_mp_images.sh 4 rcf_ci` stages |
| `//verification/isa:image_contract_test` | test | the image contract a stale or mis-staged image breaks first (word count, flash header, execute word, file-name length) |
| `//verification:env_headers`, `//verification:env_p_linker_scripts` | build | the p-mode test environment every image compiles and links against |
| `//verification/npu/...` | test | the NPU golden model: vector regeneration, the firmware-smoke golden generators, and `validate_mlp` against the chip-config golden set |
| `//opensource_sim:isa_regression` | test | all nine ISA suites actually running against the RTL under GHDL, license free |

`benchmarks/` and `mt/` are not in the Bazel graph; build them with the legacy
`make` path described below. See [`isa/README.md`](isa/README.md) and
[`npu/README.md`](npu/README.md) for the per-suite and per-generator targets,
and [`BAZEL.md`](../BAZEL.md) for the full map.

## Directory Structure

### **`isa/`** — ISA Instruction Tests
RISC-V instruction set architecture verification tests adapted from the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) repository.

- Tests organized by extension: `rv32ui`, `rv32um`, `rv32ua`, `rv32uc`, etc.
- Automated build system generates `.elf`, `.dump`, `.bin`, and `.rcf` files
- Central `rcf/` directory for VHDL simulation memory initialization
- See [`isa/README.md`](isa/README.md) for detailed build instructions

**Purpose:** Verify correct implementation of RISC-V instruction set

### **`benchmarks/`** — Performance Benchmarks
Standard benchmark suite for measuring processor performance and validating functionality under realistic workloads.

Includes:
- **dhrystone** — Integer performance benchmark
- **multiply** — Multiplication performance
- **qsort**, **rsort** — Sorting algorithms
- **median** — Statistical operations
- **mm** — Matrix multiplication
- **towers** — Towers of Hanoi
- **mt-*** — Multi-threaded benchmarks (matmul, memcpy, vvadd)
- **vec-*** — Vector operation benchmarks (daxpy, memcpy, sgemm, strcmp)
- **spmv** — Sparse matrix-vector multiply

**Purpose:** Performance characterization and stress testing

### **`mt/`** — Multi-threaded Tests
Thread-based test programs including various matrix multiplication and vector addition implementations.

- Multiple matmul variants (ad, ae, af, ag, etc.)
- Vector addition tests (vvadd0-4)

**Purpose:** Test multi-core/multi-thread support (if applicable)

### **`env/`** — Test Environment
Common test infrastructure and environment files from the riscv-tests repository.

Contains:
- `encoding.h` — RISC-V instruction encodings
- `p/`, `pm/`, `pt/`, `v/` — Test environment configurations for different privilege modes

**Purpose:** Shared test environment for consistent test execution

## Quick Start

Legacy path. The `make` recipes below still work and need a locally installed
RISC-V toolchain; the Bazel targets above build the same images with a pinned,
fetched one.

### Build ISA Tests
```bash
cd isa/
make rv32ui        # Build user-level integer tests
make rv32um        # Build multiply/divide tests
make all           # Build all ISA tests
```

### Build Benchmarks
```bash
cd benchmarks/
make all
```

### Run in VHDL Simulation
1. Build tests to generate RCF files:
   ```bash
   cd isa/
   make rv32ui
   ```

2. RCF files are collected in `isa/rcf/` directory

3. Point your VHDL testbench to load RCF files from this location:
   ```vhdl
   -- Example: Load test program into ROM
   -- ROM initialization file: verification/isa/rcf/rv32ui-p-add.rcf
   ```

4. See `hdl/myshkin/tb/` for example testbench implementations

## Test Organization

### ISA Test Suites

| Suite    | Description                           | Example Tests |
|----------|---------------------------------------|---------------|
| rv32ui   | User-level integer instructions       | add, sub, and, or, xor, sll, sra |
| rv32um   | Integer multiply/divide               | mul, mulh, div, rem |
| rv32ua   | Atomic instructions                   | lr.w, sc.w, amoswap |
| rv32uc   | Compressed instructions               | c.addi, c.li, c.j |
| rv32uzb* | Bit manipulation                      | clz, ctz, andn, orn |
| periph   | Custom peripheral tests               | GPIO, UART, SPI, Timer tests |

### Benchmark Categories

| Category | Description | Purpose |
|----------|-------------|---------|
| Integer  | dhrystone, multiply | Basic integer performance |
| Memory   | memcpy, vvadd | Memory system performance |
| Algorithm| qsort, rsort, median, towers | Complex algorithm validation |
| Linear Algebra | mm, spmv, vec-* | Mathematical operations |
| Multi-threaded | mt-* | Parallel execution testing |

## Adding New Tests

### ISA Tests
1. Add test source to appropriate `isa/tests/<suite>/` directory
2. Update `isa/Makefile` if adding new test suite
3. Run `make <suite>` to build and generate RCF files

### Benchmarks
1. Add benchmark source to `benchmarks/<name>/`
2. Update `benchmarks/Makefile` with new target
3. Build with `make <benchmark-name>`

## Test Results

### Pass/Fail Criteria
- **ISA Tests**: Tests use pass/fail macros that write to specific test registers
- **VHDL Testbench**: Monitor test completion register to determine pass/fail
- **Success**: Program writes pass value to test status register
- **Failure**: Program writes fail code or hangs/times out

### Expected Results
All ISA tests should pass on a correctly implemented VestaRV core. Benchmark tests should complete without hanging or exceptions.

## Requirements

- **RISC-V Toolchain**: `riscv-none-elf-gcc` (see [`tools/build/README.md`](../tools/build/README.md))
- **Python 3**: For RCF generation (`intelhex` module)
- **Make**: GNU Make for build automation
- **VHDL Simulator**: Xcelium, ModelSim, GHDL, or similar for running tests

## Test Coverage

VestaRV verification includes:
- ✅ All RV32I base instructions
- ✅ M extension (multiply/divide)
- ✅ A extension (atomics)
- ✅ C extension (compressed)
- ✅ Zb* extensions (bit manipulation)
- ✅ Peripheral functionality (GPIO, UART, SPI, Timer, etc.)
- ✅ Interrupt handling
- ✅ Memory access patterns
- ✅ Performance benchmarking

## Related Documentation

- [`isa/README.md`](isa/README.md) — Detailed ISA test build instructions
- [`../tools/build/README.md`](../tools/build/README.md) — Toolchain setup
- [`../hdl/myshkin/tb/`](../hdl/myshkin/tb/) — VHDL testbench examples
- [`../software/README.md`](../software/README.md) — Firmware development guide

## References

- [RISC-V ISA Specification](https://riscv.org/technical/specifications/)
- [riscv-tests Repository](https://github.com/riscv-software-src/riscv-tests)
- [RISC-V Compliance Tests](https://github.com/riscv-non-isa/riscv-arch-test)
