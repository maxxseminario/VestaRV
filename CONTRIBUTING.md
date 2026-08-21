# Contributing to VestaRV

Thank you for your interest in contributing! VestaRV is an open-source RISC-V core and SoC framework. Contributions are welcome across all areas — HDL, firmware, verification, documentation, and tooling.

---

## Table of Contents

- [Ways to Contribute](#ways-to-contribute)
- [Building and Testing with Bazel](#building-and-testing-with-bazel)
- [Reporting Bugs](#reporting-bugs)
- [Proposing Changes](#proposing-changes)
- [Pull Request Guidelines](#pull-request-guidelines)
- [HDL Style Guide](#hdl-style-guide)
- [Firmware Style Guide](#firmware-style-guide)
- [Verification Requirements](#verification-requirements)
- [Documentation Standards](#documentation-standards)
- [Code of Conduct](#code-of-conduct)

---

## Building and Testing with Bazel

The repo is Bazel-managed: a fresh clone needs no locally installed toolchains.
Run all commands below **from the repo root**.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

The everyday commands:

```sh
tools/bin/bazel test //...                            # the whole gate set
tools/bin/bazel test //opensource_sim:isa_regression  # full ISA sim, license-free
tools/bin/bazel build //software/bootrom_mp:rom_rcf   # the mask-ROM image
tools/bin/bazel build //platform/common:chip_artifacts_castalia
```

Never run `bazel run //:generate` - that is the raw generator and it writes
wherever it happens to be invoked. The hermetic generation path is
`//platform/common:chip_artifacts_castalia` (and
`//platform/common:chip_artifacts_argus`).

Cadence flows (Genus, Innovus, Pegasus, Xcelium, `make verify`) are permanently
outside Bazel - licensed binaries. Run them exactly as before, via
`source cdspaths.sh`.

Full map of what is Bazel-managed and what is not: [`BAZEL.md`](BAZEL.md).

---

## Ways to Contribute

| Area | Examples |
|------|---------|
| **HDL** | Bug fixes in the core or peripherals, new peripheral modules, synthesis improvements |
| **Firmware** | Boot ROM improvements, new firmware examples, Forth interpreter extensions |
| **Verification** | New ISA test cases, peripheral testbenches, simulation scripts |
| **Documentation** | Improving READMEs, correcting the user guide, adding application notes |
| **Build System** | Bazel rules and targets (`tools/bin/bazel`, see [Building and Testing with Bazel](#building-and-testing-with-bazel)), Makefile improvements, new script utilities, toolchain support |
| **FPGA Ports** | New board support packages with pinout and constraints |

---

## Repository Structure & Frozen Trees

As of the 2026-07 hierarchy restructure, the HDL/tool trees are split into one directory
per VestaRV instantiation. **Some trees are frozen and must never be edited** — hygiene or
fixes in those trees are a proposal to the maintainer only:

| Tree | Status | Notes |
|------|--------|-------|
| `hdl/common/` | **Live** | Shared multi-core tile RTL (Castalia + Argus derive from here). All multi-core RTL changes go here. |
| `platform/common/` | **Live** | The Castalia/Argus chip generator (single source of truth). |
| `innovus/common/` | **Live** | Multi-core P&R flow (hand-maintained tcl/sh/Makefile; build-artifact subdirs are generated, not committed). |
| `hdl/myshkin/` | **FROZEN — do not touch** | Single-core Myshkin tape-out RTL. |
| `platform/myshkin/` | **FROZEN — do not touch** | Single-core Myshkin generator. |
| `innovus/myshkin/` | **FROZEN — do not touch** | Single-core Myshkin P&R flow. |
| `hdl/argus/` | Frozen snapshot | 18-hart Argus RTL snapshot (regenerable from `config/argus.json`). |

### `hdl/common/MCU.vhd` is a generated product — never hand-edit it

`hdl/common/MCU.vhd` (and `MemoryMap.vhd`) is the output of `make chip`. **Do not edit it
by hand.** To change the top level:

1. Edit `platform/common/hdl_templates/MCU.template.vhd` (fixed regions) or
   `platform/common/python/generate.py` + `mcu_vhd.py` (generated regions).
2. Run `cd platform/common && make chip`. Bazel builds the same artifact
   hermetically as `//platform/common:chip_artifacts_castalia`, but it is
   sandboxed and never writes into the tree, so the in-tree regeneration is
   what updates the tracked file.
3. Copy `platform/common/out/hdl/MCU.vhd` over `hdl/common/MCU.vhd`.
4. Prove it with `tools/bin/bazel test //platform/...` - the identity gates
   there are the same ones CI runs, and they fail on any hand-edit.

Generator outputs never leave `platform/common/` on their own — copies into `hdl/`,
`software/`, or `docs/` are explicit, scripted publish steps.

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

5. **Run the Bazel gate set before you open the PR** - from the repo root, `tools/bin/bazel test //...`. It must be green (except for the known-red cases called out in [`BAZEL.md`](BAZEL.md)). CI runs the same gates. See [Building and Testing with Bazel](#building-and-testing-with-bazel).

6. **Update documentation** — if you add or change a register, peripheral, or configuration option, update the relevant README and re-run `make chip` (in `platform/common/`) if the memory map is affected.

7. **Do not commit generated artifacts** — everything under `platform/common/out/` (the generated RTL, headers, linker scripts, and TRM) is a build output. Commit only the source (`platform/common/python/generate.py`, the LaTeX templates, and the peripheral intro files) and let the reviewer regenerate. The published drop-in RTL (`hdl/common/MCU.vhd` / `MemoryMap.vhd`) is committed but is itself a `make chip` product — see [Repository Structure & Frozen Trees](#repository-structure--frozen-trees).

### What CI checks before a merge

Five jobs in `.github/workflows/ci.yml` gate every pull request, and the merge
queue re-runs them against a candidate rebased onto current `main`
(see [`.github/MERGE_QUEUE.md`](.github/MERGE_QUEUE.md)):

| Check | What it proves |
|---|---|
| `Chip generator gates` | `make generate` is clean, and the tracked `hdl/common/MCU.vhd` / `MemoryMap.vhd` are byte-identical to what the generator emits. A hand-edit of the generated RTL cannot merge. |
| `Docs link + generator syntax gates` | Every relative link in the HTML and Markdown resolves; the generator byte-compiles; no workflow targets a self-hosted runner. |
| `Bootrom + ISA image builds` | The mask ROM reproduces byte-identically with the pinned toolchain, and the full N=4 ISA image set still assembles and links. |
| `Bazel hermetic gates` | `bazel test //...` minus the GHDL half, from a checkout with no toolchain installed: chip generation, every firmware and course-lab golden, the ISA image contract, the python tooling, the docs gates. Also proves the lockfile is current, the whole build graph analyzes, and that no build action wrote into the source tree. |
| `Repo hygiene gates` | The `tools/ci/` guards: CRLF endings preserved where they are load-bearing, VHDL is 7-bit ASCII, `.bazelignore` still excludes the EDA output trees, and no build output or oversized blob is tracked. |

Two more hosted jobs run on every PR from `.github/workflows/`: the GHDL ISA
regression in `sim.yml` and the Verilog bridge plus cocotb smoke test in
`physical.yml`.

You can run all of the hygiene gates locally, from the repo root:

```sh
python3 tools/ci/check_line_endings.py
python3 tools/ci/check_vhdl_style.py
python3 tools/ci/check_bazelignore.py
python3 tools/ci/check_repo_hygiene.py
```

See [`tools/ci/README.md`](tools/ci/README.md) for what each one blesses and how
to regenerate the line-ending manifest when a deliberate change moves it.

---

## HDL Style Guide

VestaRV HDL is written in **VHDL-93/2008**.

- **Naming**: `snake_case` for signals and variables; `PascalCase` for entity and architecture names; `ALL_CAPS` for constants and generics.
- **Ports**: Group related ports with a comment header. Use `in`/`out` consistently; avoid `inout` except for pad-level models.
- **Clocking**: All synchronous logic uses a single rising-edge clock per clock domain. Use the shared `ClkGate` component (in `hdl/common/`) for gated clocks rather than combinatorial clock enable.
- **Reset**: Active-low synchronous or asynchronous reset named `resetn`. Use `if resetn = '0' then` — not `if not resetn`.
- **Comments**: Include a brief header comment on each process explaining what it does. Keep inline comments concise.
- **No `std_logic_arith`** in new code — use `ieee.numeric_std` instead. (Legacy files may still use the older package; do not change working files gratuitously.)

---

## Firmware Style Guide

Firmware is written in **C (C11)** or **RISC-V assembly (RV32)**.

- Use the common makefiles in `tools/build/makefiles/` — do not duplicate build logic.
- Keep peripheral access through the generated header `MemoryMap.h` (published to `software/commune/include/` per chip configuration) and `periph.S`.
- Assembly files (`.S`) should have a file-level comment block describing the program and register usage.
- C files should include `init.h` for startup and use the `WRITE32` / `READ32` macros from the firmware commons where applicable.

---

## Verification Requirements

**Before you open a PR, run the full Bazel gate set from the repo root:**

```sh
tools/bin/bazel test //...
```

Targeted subsets while you iterate: `//opensource_sim:isa_regression` (the
license-free GHDL ISA regression), `//platform/...` (chip generation and its
identity/determinism gates), `//software/...` (firmware image goldens),
`//hdl/common/tb:mp_arbiter_tb` and `//hdl/common/tb:pmp_unit_tb` (unit
benches).

Any HDL change that modifies:
- **The VestaRV core** (`hdl/common/vesta/`) — must pass the full ISA regression: `tools/bin/bazel test //opensource_sim:isa_regression`
- **A peripheral** (`hdl/common/periph/`) — must include or update the corresponding testbench in `hdl/common/tb/` and demonstrate a passing simulation: `tools/bin/bazel test //hdl/common/tb:all`
- **The memory map** — must regenerate via `cd platform/common && make chip`, then pass the identity gates: `tools/bin/bazel test //platform/...`

Simulation can be run with any VHDL-2008-compatible simulator (GHDL, ModelSim, Xcelium, Questa). See [`hdl/README.md`](hdl/README.md) for simulation setup.

---

## Documentation Standards

- READMEs use **GitHub Flavored Markdown**.
- The Technical Reference Manual is a LaTeX project in `platform/common/latex/`. Peripheral documentation is written in the peripheral intro files there and generated into the TRM via `make chip`. Do not hand-edit the generated LaTeX/PDF under `platform/common/out/` — these are overwritten on every generation.
- Register descriptions in `platform/common/python/generate.py` must match the VHDL source exactly (bit positions, reset values, accessibility).

---

## Code of Conduct

Be respectful and constructive. This project is maintained as part of academic research; response times may vary. Harassment or personal attacks of any kind will not be tolerated.

For project-related questions, reach out to Maxx Seminario at mseminario2@huskers.unl.edu.
