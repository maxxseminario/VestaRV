# Inherited riscv-tests scaffolding (not runnable against the VestaRV core)

Several test suites in this tree are inherited verbatim from the upstream
[`riscv-tests`](https://github.com/riscv-software-src/riscv-tests) scaffolding.
They target ISA features the **VestaRV core does not implement**, so they are
**kept for provenance only** — they are not part of any VestaRV regression and
will not pass (or even build meaningfully) against this core.

| Path | Upstream feature | Why it does not apply to VestaRV |
|------|------------------|----------------------------------|
| `rv32si/` | Supervisor-mode ISA | VestaRV is **M-mode only** — no S/U privilege modes |
| `rv32uf/` | Single-precision FPU (`F`) | VestaRV has **no FPU** |
| `rv32ud/` | Double-precision FPU (`D`) | VestaRV has **no FPU** |
| `hypervisor/` | H-extension / virtualization | VestaRV has **no hypervisor / S-mode** |
| `../benchmarks/pmp/` | Physical Memory Protection | VestaRV implements **no PMP** |
| `../benchmarks/vec-*` | Vector extension (`V`) | VestaRV implements **no V extension** |

What VestaRV *does* run lives in the active regression suites
(`rv32ui`, `rv32ua`, `rv32um`, `rv32uc`, `rv32uzba/zbb/zbc/zbs`, plus the
`sh*` multi-core system tests) — see the top-level `CLAUDE.md` "Test flows"
section and the `behavioral_mp` runner. The RV64 (`rv64*`) directories are
likewise upstream scaffolding for a 64-bit core and do not apply to this
32-bit implementation.

These directories are retained so the origin of the test framework stays
traceable; do not add them to any VestaRV test list.
