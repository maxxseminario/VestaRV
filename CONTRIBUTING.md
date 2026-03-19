# Contributing to VestaRV

Thank you for your interest in contributing! VestaRV is an open-source RISC-V core and SoC framework. Contributions are welcome across all areas — HDL, firmware, verification, documentation, and tooling.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Reporting Bugs](#reporting-bugs)
- [Proposing Changes](#proposing-changes)
- [Pull Request Guidelines](#pull-request-guidelines)
- [HDL Style Guide](#hdl-style-guide)
- [Firmware Style Guide](#firmware-style-guide)
- [Verification Requirements](#verification-requirements)
- [Documentation Standards](#documentation-standards)
- [Code of Conduct](#code-of-conduct)

---

## Ways to Contribute

| Area | Examples |
|------|---------|
| **HDL** | Bug fixes in the core or peripherals, new peripheral modules, synthesis improvements |
| **Firmware** | Boot ROM improvements, new firmware examples, Forth interpreter extensions |
| **Verification** | New ISA test cases, peripheral testbenches, simulation scripts |
| **Documentation** | Improving READMEs, correcting the user guide, adding application notes |
| **Build System** | Makefile improvements, new script utilities, toolchain support |
| **FPGA Ports** | New board support packages with pinout and constraints |

---

## Reporting Bugs

Before opening an issue, please check that:
- The bug has not already been reported
- You can reproduce it on the latest `main` branch

When opening an issue, please include:
- A clear title and description
- Steps to reproduce (simulation command, firmware, waveform screenshot if applicable)
- Expected vs. actual behavior
- Environment (OS, toolchain version, simulator version)
- Relevant VHDL, C, or assembly snippets if short enough to include inline

---

## Proposing Changes

For non-trivial changes, open an issue first to discuss the approach before writing code. This avoids wasted effort and ensures the change aligns with the project direction.

For small fixes (typos, one-line corrections), you can open a PR directly.

---

## Pull Request Guidelines

1. **Fork** the repository and create a branch from `main`:
   ```bash
   git checkout -b feature/my-new-peripheral
   ```

2. **Keep PRs focused** — one logical change per PR. Avoid mixing unrelated fixes.

3. **Write a clear PR description** explaining:
   - What changed and why
   - Any trade-offs or known limitations
   - How to test the change (simulation command, expected output)

4. **Include verification** for HDL changes — at minimum a passing simulation of the affected module. See [Verification Requirements](#verification-requirements).

5. **Update documentation** — if you add or change a register, peripheral, or configuration option, update the relevant README and re-run `generator/python/generate.py` if the memory map is affected.

6. **Do not commit generated artifacts** — files under `generator/latex/MCU-User-Guide/` (except the `.tex` templates), `generator/gcc/lib/include/MemoryMap.h`, and `generator/config/MemoryMap.json` are generated outputs. Commit only the source (`generate.py` and peripheral intro files) and let CI or the reviewer regenerate.

---

## HDL Style Guide

VestaRV HDL is written in **VHDL-93/2008**.

- **Naming**: `snake_case` for signals and variables; `PascalCase` for entity and architecture names; `ALL_CAPS` for constants and generics.
- **Ports**: Group related ports with a comment header. Use `in`/`out` consistently; avoid `inout` except for pad-level models.
- **Clocking**: All synchronous logic uses a single rising-edge clock per clock domain. Use the `ClkGate` component from `hdl/MCU/commune/` for gated clocks rather than combinatorial clock enable.
- **Reset**: Active-low synchronous or asynchronous reset named `resetn`. Use `if resetn = '0' then` — not `if not resetn`.
- **Comments**: Include a brief header comment on each process explaining what it does. Keep inline comments concise.
- **No `std_logic_arith`** in new code — use `ieee.numeric_std` instead. (Legacy files may still use the older package; do not change working files gratuitously.)

---

## Firmware Style Guide

Firmware is written in **C (C11)** or **RISC-V assembly (RV32)**.

- Use the common makefiles in `build-system/makefiles/` — do not duplicate build logic.
- Keep peripheral access through the generated header `MemoryMap.h` (`generator/gcc/lib/include/`) and `periph.S`.
- Assembly files (`.S`) should have a file-level comment block describing the program and register usage.
- C files should include `init.h` for startup and use the `WRITE32` / `READ32` macros from the firmware commons where applicable.

---

## Verification Requirements

Any HDL change that modifies:
- **The VestaRV core** (`hdl/MCU/vesta/`) — must pass all ISA tests (`cd verification/isa && make all`)
- **A peripheral** (`hdl/MCU/periph/`) — must include or update the corresponding testbench in `hdl/MCU/tb/` and demonstrate a passing simulation
- **The memory map** — must regenerate the memory map and confirm `python3 generator/python/generate.py` runs without error

Simulation can be run with any VHDL-2008-compatible simulator (GHDL, ModelSim, Xcelium, Questa). See [`hdl/README.md`](hdl/README.md) for simulation setup.

---

## Documentation Standards

- READMEs use **GitHub Flavored Markdown**.
- The MCU User Guide is a LaTeX project in `generator/latex/`. Peripheral documentation is written in `generator/latex/PeripheralIntroductions/` and generated into the guide via `generate.py`. Do not hand-edit files inside `generator/latex/MCU-User-Guide/include/` — these are overwritten on every generation.
- Register descriptions in `generator/python/generate.py` must match the VHDL source exactly (bit positions, reset values, accessibility).

---

## Code of Conduct

Be respectful and constructive. This project is maintained as part of academic research; response times may vary. Harassment or personal attacks of any kind will not be tolerated.

For project-related questions, reach out to Maxx Seminario at mseminario2@huskers.unl.edu.
