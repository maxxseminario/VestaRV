<table border="0" cellspacing="0" cellpadding="0">
  <tr>
    <td>
      <img src="assets/vesta_logo_light.png#gh-light-mode-only" alt="VestaRV32 logo" height="80" />
      <img src="assets/vesta_logo_dark.png#gh-dark-mode-only" alt="VestaRV32 logo" height="80" />
    </td>
    <td style="padding-left:12px;">
      <h1 style="margin:0;">VestaRV - A Custom RISC-V Core &amp; SoC</h1>
    </td>
  </tr>
</table>

VestaRV is a 32-bit RISC-V core in VHDL plus a chip generator: one JSON configuration
fixes harts, ISA and peripherals, and one build emits RTL, C headers, linker scripts,
pad ring and the [TRM](implementations/asic/castalia/docs/TRM.pdf). Version v2.11.0
([changelog](CHANGELOG.md)); silicon to date is v1.0.0 (Myshkin, TSMC 65 nm, 2025).

## Quick start

```sh
sh tools/get_bazel.sh                                            # bazelisk -> tools/bin/bazel
tools/bin/bazel test //...                                       # every gate (first run ~1 GB, 10-20 min)
tools/bin/bazel build //platform/common:chip_artifacts_castalia  # generate the reference chip
tools/bin/bazel test //opensource_sim:isa_regression             # GHDL ISA regression, no licenses
tools/bin/bazel run //:regs                                      # regenerate everything from SystemRDL
```

Run from the repo root. Use `chip_artifacts_*` targets, not `bazel run //:generate`,
which writes wherever it is invoked. Cadence flows run outside Bazel after
`source cdspaths.sh`. Full target map: [`BAZEL.md`](BAZEL.md).

## Repository map

| Path | Contents |
|---|---|
| [`platform/common/`](platform/common/README.md) | Chip generator and configurations |
| [`hdl/`](hdl/README.md) | RTL; live tree [`hdl/common/`](hdl/common/README.md) |
| [`implementations/`](implementations/README.md) | Per-chip docs: Castalia, Argus, Myshkin, FPGA |
| [`opensource_sim/`](opensource_sim/README.md), [`sky130/`](sky130/README.md) | License-free simulation; open sky130 flow |
| [`docs/new_chip.md`](docs/new_chip.md) | Adding a chip or peripheral |

Maxx Seminario (mseminario2@huskers.unl.edu). Published for reference; no external
contributions. MIT License ([`LICENSE`](LICENSE)).
