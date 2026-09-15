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

VestaRV is a 32-bit RISC-V processor core written in VHDL from the official
instruction-set specification, deriving from no existing implementation. The
repository around it is a chip generator: one configuration file fixes the hart
count, the ISA and the peripheral set, and one build emits that chip's RTL, C
headers, linker scripts, pad ring and Technical Reference Manual together. 337
Bazel tests hold every configuration to its sources, from register-description
versus RTL comparisons through a license-free GHDL regression of the core.

> **[Technical Reference Manual - Castalia, revised September 12, 2026](implementations/asic/castalia/docs/TRM.pdf)** (315 pages, build `a4fafc19`)  
> Register reference, system architecture, debug/JTAG chapter, analog front-end
> chapter and programming guide for the five-hart chip, generated from the chip
> configuration by [`platform/common`](platform/common/README.md).  
> Also tracked: the [Myshkin TRM v1.0.0](implementations/asic/myshkin-2025-11/docs/TRM.pdf), the first VestaRV tape-out.

> **Current version: v2.11.0**, the multi-core line. Silicon to date is
> **v1.0.0** (Myshkin, TSMC 65nm, November 2025); no `2.x` configuration has
> been fabricated. Full history in the [changelog](CHANGELOG.md).

Named after **Vesta**, Roman goddess of hearth and the eternal flame.

![MCU Block Diagram](assets/castalia_block_diagram.png)

Figure 2 of the TRM, drawn flat: every master in a band across the top, the
multi-hart shared-bus arbiter as the single bus bar it behaves like, and the
peripherals of the default configuration in one rank below it, with the package
boundary in red. The four AFE sites are the analog channels the TRM's Analog
Front-End chapter measures.

---

## First run

```bash
git clone https://github.com/maxxseminario/VestaRV.git && cd VestaRV
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # the whole gate set; nothing to install first
tools/bin/bazel run //:generate  # emit the chip
```

`test //...` is 337 automatic targets (14 more are tagged `manual`): the
generated RTL against the tracked RTL, the register descriptions against both
the VHDL and the C headers, firmware and mask-ROM images against their goldens,
and the license-free GHDL ISA regression. Cold it is 10-20 minutes, nearly all
of it fetching ~1 GB of toolchains and building GHDL from source; measured here
with `time` on a **warm** cache it reports in about a second, and forcing every
test to execute again is about ten minutes. `//:generate` writes RTL to
`platform/common/out/hdl/`, C headers to `out/software/include/`, linker scripts
to `out/linker-scripts/`, the pad ring to `out/pnr/` and the TRM sources to
`platform/common/latex/TRM/`.

**The ASIC starting point is
[`config/asic_default.json`](platform/common/config/asic_default.json)**: one
hart, no orchestrator, the smallest configuration that goes through synthesis,
place-and-route and LVS.

```bash
make -C platform/common generate CONFIG=config/asic_default.json
tools/bin/bazel build //platform/common:chip_artifacts_asic_default
tools/bin/bazel test //opensource_sim/asic_default:asic_default_elaborate \
                     //opensource_sim/asic_default:asic_default_boot
```

**The FPGA starting point is
[`config/fpga_default.json`](platform/common/config/fpga_default.json)**: one
hart, no board in particular; the RTL is the deliverable and
[`hdl/fpga/`](hdl/fpga/README.md) holds the synthesizable stand-ins.

```bash
make -C platform/common generate CONFIG=config/fpga_default.json
tools/bin/bazel test //opensource_sim/fpga_default:fpga_default_elaborate
```

The FPGA clock cells (27 clock nets on an Artix-7's 32 buffers), the out-of-context
Vivado run and the constraints template are in
[`implementations/fpga/synth/`](implementations/fpga/synth/README.md).

---

Both recipes are written out with the gate that refuses each mistake in
[`docs/new_chip.md`](docs/new_chip.md): configure and prove a chip of your own,
then add a peripheral to it.

## ISA

**Always built**, with no knob that removes them:

- RV32I base integer instruction set.
- `cycle`, `instret` and their high halves. `time`/`timeh` are implemented in no build and trap.
- Stack-based recursive interrupt handling.

**Per-hart class** (`isa.minimalTiles`), generated into `derived.hartClasses` in [`platform/common/config/ChipConfig.resolved.json`](platform/common/config/ChipConfig.resolved.json), which is where these rows and the same table in the TRM come from. A minimal tile is rv32iac and nothing more: the `TILE_ENABLE_*` constants drop M, Zb, every Z extension, U-mode and PMP, while A, C and the trap CSRs are kept (debug is not per-class: the Debug Module halts tiles). Anything more than one class executes is built for the narrowest row (graded on the linked ELF by `//software/testtools:tile_isa_test`).

| Hart class | Harts | ISA string | Privilege |
| --- | --- | --- | --- |
| Orchestrator, soft core | 0 | `rv32imac_zba_zbb_zbs_zbc` | M-mode, trap CSRs, debug |
| Tile, hardened `hart_tile` macro | 1-4 | `rv32iac` | M-mode, trap CSRs, debug |

**Selectable per configuration.** Each knob generates its hardware away when off
and traps the encoding as an illegal instruction; a read-only `misa` advertises
I, M, A, B, C and U. These default on:

- **Base extensions:** `isa.mul` (M multiply) `isa.div` (M divide) `isa.atomics` (A, LR/SC and AMO) `isa.compressed` (C) `isa.bitmanip` (Zba/Zbb/Zbc/Zbs).
- **Core and tile shape:** `core.fetchAhead` (one flop, removes most of the C-extension straddling-fetch stall) `isa.minimalTiles` (the table above; it costs no extra hardening because the tiles are one macro instanced four times).
- **Privilege:** `priv.trapCsr` (M-mode trap CSRs and standard delivery; firmware opts in via `mtrapctl`) `debug.enable` (debug mode, the Debug Module and the JTAG DTM).

Eighteen ISA knobs and two privilege knobs default off. Compute: `isa.zfinx` (single-precision FP in the x-registers) `isa.zicond`. Crypto: `isa.zkn` (AES and SHA) `isa.zbkb` `isa.zbkc` `isa.zbkx`. Code size: `isa.zcmp` `isa.zcmt` `isa.zcb`. Memory and atomics: `isa.zicboz` `isa.zabha` `isa.zacas` `isa.zawrs`. Counters and hints: `isa.counters` `isa.counters64` `isa.zihpm` `isa.zihint` `isa.zimop`. Privilege: `priv.umode` (user mode) `priv.pmp` (Smpmp, 8 or 16 entries).

The 61-knob schema is `_CONFIG_SCHEMA` in
[`platform/common/python/generate.py`](platform/common/python/generate.py); an
unknown key raises rather than falling back to a default.

---

## Build and verify

Everything builds and tests through **Bazel**, hermetically: a fresh clone needs
no locally installed toolchain. Bazel provisions Python, a C/C++ toolchain, the
exact RISC-V cross-compiler the mask ROM was pinned to, a from-source GHDL and a
hermetic TeX Live.

Run every command from the repository root. Add `<repo>/tools/bin` to `PATH`
for plain `bazel`.

| What you want | Command |
|---|---|
| The whole gate set (337 tests) | `tools/bin/bazel test //...` |
| Generate a chip (RTL, headers, linker scripts, TRM sources) | `tools/bin/bazel build //platform/common:chip_artifacts_castalia` |
| Prove the generated RTL matches the tracked RTL | `tools/bin/bazel test //platform/...` |
| Regenerate everything derived from the register descriptions | `tools/bin/bazel run //:regs` |
| Build the mask-ROM image | `tools/bin/bazel build //software/bootrom_mp:rom_rcf` |
| Build every firmware app | `tools/bin/bazel build //software/...` |
| Build all 259 ISA test programs (518 images, plain and flashed) | `tools/bin/bazel build //verification/isa:all_images` |
| Run the full ISA simulation regression (GHDL, no licenses) | `tools/bin/bazel test //opensource_sim:isa_regression` |
| Core and peripheral unit benches (26) | `tools/bin/bazel test //hdl/common/tb:all` |
| Synthesizability of every block (39 entities) | `tools/bin/bazel test //hdl/common/synth:synth` |
| Frozen flop, latch and cell counts for those entities | `tools/bin/bazel test //toolchains/ghdl:synth_census_test` |
| Python tooling and docs gates | `tools/bin/bazel test //tools/... //docs/...` |
| Bind the FPGA cut against the synthesizable stand-in cells | `tools/bin/bazel test //opensource_sim/fpga_default:fpga_default_elaborate` |
| Write the ordered VHDL file list a Vivado run reads | `tools/bin/bazel build //opensource_sim/fpga_default:fpga_default_vivado_files` |

Configurations live in [`platform/common/config`](platform/common/config) and are
selected with `CONFIG=`. `castalia.json` is the reference chip: hart 0 is an
always-on soft `orch_tile` orchestrator in the centre band and harts 1-4 are
instances of one hardened `hart_tile` macro. `argus.json` is the frozen 18-hart
teaching chip, `asic_default.json` the minimal ASIC starting point and
`fpga_default.json` the FPGA one. A bare build with no `CONFIG=` is the
reference chip, which is the configuration the tracked RTL identity gates grade.

The first build fetches roughly 1 GB of toolchains and compiles GHDL from source
(10-20 minutes cold); everything after that is cached, including across
output-base wipes. No target carries the `known_red` tag today; CI still passes
`--test_tag_filters=-known_red` so a future understood-but-unadjudicated red can
be tagged rather than left to rot.

A fully open-source path needs no proprietary EDA license:
`tools/bin/bazel test //opensource_sim:isa_regression` runs the
riscv-tests-derived suite on a GHDL built from source. The one piece Bazel does
not run is the cocotb smoke test, `./opensource_sim/run_sim.sh --smoke-only`.
See [`opensource_sim/README.md`](opensource_sim/README.md) and
[`sky130/README.md`](sky130/README.md), the companion flow that takes the same
RTL to a signed-off sky130 GDSII.

[`BAZEL.md`](BAZEL.md) has the full target map, the conventions and what
deliberately stays outside Bazel.

---

## Peripherals

One row per block in the default and `castalia.json` configurations. `Regs` is
the block's register count and `Dflt` / `Chip` its instance count in each, all
read out of the generated register map (`out/web/MemoryMap.json`); `RF` marks the
blocks that instantiate the shared register-file module (`_REGFILE` in
[`platform/common/python/rdl_vhdl.py`](platform/common/python/rdl_vhdl.py));
`Bench` names a [`hdl/common/tb`](hdl/common/tb/BUILD.bazel) target, except NPU's,
which is `//verification/npu`; MUTEX has none.

| Block | Function | Regs | Dflt | Chip | RF | Bench |
|---|---|---|---|---|---|---|
| GPIO | General-purpose eight-pin port whose every pin carries an alternate-function mux onto a peripheral signal | 13 | 6 | 6 | Y | `GPIO_tb` |
| SPI | Serial peripheral interface that operates as bus master or as addressed slave | 5 | 2 | 2 | Y | `SPI_tb` |
| UART | Full-duplex asynchronous serial port with hardware parity generation and checking | 5 | 2 | 2 | Y | `UART_tb` |
| TIMER | 32-bit timer and counter with input capture, output compare and edge-aligned PWM | 8 | 2 | 2 | Y | `TIMER_tb` |
| SYSTEM | Clock sourcing and DCO trim, reset control, watchdog, power state and a CRC16 engine | 11 | 1 | 1 | Y | `SYSTEM_tb` |
| NPU | Fixed-point MLP accelerator that evaluates one fully-connected layer per pass | 7 | 1 | 1 | Y | `npu` |
| PWRCTRL | MTCMOS cold-gating controller that sequences the switchable tile power domains | 5 | 1 | 1 | - | `pwr_ctrl_tb` |
| QSPI | Quad-SPI flash controller with configurable lane widths and execute-in-place fetch | 6 | - | 1 | Y | `QSPI_tb` |
| I2C | I2C port that operates as bus master or as addressed slave | 9 | 2 | 2 | Y | `I2C_tb` |
| CLINT | Core-local interruptor holding per-hart `msip`, one shared `mtime` and per-hart `mtimecmp` | 17 | 1 | 1 | - | `irq_sys_tb` |
| MUTEX | Sixteen word-mapped advisory locks for single-instruction cross-hart exclusion | 16 | 1 | 1 | - | - |
| I3C | MIPI I3C basic single-controller with dynamic address assignment and in-band interrupts, interoperable with legacy I2C targets | 9 | - | 1 | Y | `I3C_tb` |
| NFC | ISO/IEC 14443A tag and card-emulation engine whose RF front end sits off the die | 10 | 1 | 1 | Y | `NFC_tb` |
| RTC | 32.768 kHz always-on wall clock with an alarm and a periodic tick | 7 | - | 1 | Y | `RTC_tb` |
| PWM | Glitch-free two-channel edge-aligned generator whose waveform registers are double-buffered | 9 | - | 1 | Y | `PWM_tb` |
| OneWire | Dallas/Maxim 1-Wire master that runs the bus primitives in hardware | 7 | - | 1 | Y | `OneWire_tb` |
| DMA | Four-channel single-shot controller that masters the shared arbiter, paced by software or by an event | 20 | - | 1 | Y | `DMA_tb` |
| TRNG | Ring-oscillator entropy source with a harvest engine and a repetition-count health test | 4 | - | 1 | Y | `TRNG_tb` |
| I2CTarget | Hardware-autonomous I2C target with address match and clock stretching | 5 | - | 1 | Y | `I2CTarget_tb` |
| EVFAB | PPI-style event and trigger crossbar, eight channels, with no processor in the loop | 29 | - | 1 | Y | `EVFAB_tb` |
| IRQROUTER | Per-hart interrupt routing and enable rows ahead of a claim and complete stage | 29 | 1 | 1 | - | `irq_router_tb` |

227 registers over 21 blocks in the default configuration, 323 over 30 in
`castalia.json`. Seventeen blocks instantiate `periph_regs` and keep only their
datapath; CLINT, MUTEX, IRQROUTER and PWRCTRL cannot, because their register set
is a function of the hart, mutex or vector count. See
[`hdl/common/regs/REGFILE.md`](hdl/common/regs/REGFILE.md).

---

## Register flow

`hdl/common/regs/rdl/` is the authority: one hand-written SystemRDL description
per block, 22 of them, plus the user-defined properties and the chip addrmap.

A width, an access code, a reset value or a field description written there
reaches the 22 VHDL packages in `hdl/common/regs/vhdl/`, the 21 C headers in
`software/include/regs/`, `MemoryMap.h`, `MemoryMap.vhd`, the generator's
peripheral templates, the TRM register chapters, the configurator and the
register browser. Nothing generated is ever hand-edited.

The gates: `//platform/common:rdl_vhdl_pkg_test` fails on a one-byte difference
between a tracked package and a fresh emission, `:rdl_pkg_vs_legacy_test` grades
every value against the constants frozen before the migration, the 21
`:rdl_vs_vhdl_<block>_test` targets re-derive each decode out of the VHDL and
compare it against the description, and `:regs_headers_identity_test` and
`:regs_headers_compile_test` do the same for the headers.

Regenerate the whole chain with `tools/bin/bazel run //:regs`, then review with
`git status`. Details in
[`hdl/common/regs/README.md`](hdl/common/regs/README.md) and
[`tools/rdl/README.md`](tools/rdl/README.md).

---

## Author and support

_Maxx Seminario_  
PhD Student, Integrated Circuit Design  
Analog, Mixed-Signal, and System-on-Chip Design  
University of Nebraska-Lincoln  
Email: mseminario2@huskers.unl.edu

For access, support or questions about VestaRV or its MCU subsystem, contact the
author by email.

This repository is published for reference and does not accept external
contributions at this time.

## License

VestaRV is released under the **MIT License**. See [`LICENSE`](LICENSE) for full details.
