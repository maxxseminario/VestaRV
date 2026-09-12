# Register sources

> **Analog interfacing collateral lives outside the public tree.** The AFE2/BIASG RTL,
> their `.rdl` descriptions and C headers, the AFE-bearing configurations, benches, ISA
> tests and lab tools were removed on 2026-09-11 and kept in the gitignored
> `private/analog/`, which mirrors their original paths. See `private/analog/README.md`.

One root for the register map: the descriptions and the VHDL generated from them.

| path | what |
|---|---|
| `rdl/` | the SystemRDL descriptions, hand-written: one `<block>.rdl` per peripheral, `vesta_udp.rdl` (the user-defined properties every block includes) and `castalia_penta_wound.rdl` (the chip addrmap) |
| `vhdl/` | `<block>_regs_pkg.vhd`, one GENERATED package per block, 22 of them |

`rdl/` is the authority. A width, an access code, a reset value or a field
description is written once there and reaches the TRM tables, `MemoryMap.h`,
`MemoryMap.vhd`, `software/include/regs/*.h`, the configurator, the register
browser and `vhdl/` from it.

`vhdl/` is generated output that is TRACKED, because Genus, Xcelium and GHDL all
read the RTL tree and none of them runs bazel. **Nothing under `vhdl/` is ever
hand-edited**: an edit there is overwritten by the next emission and fails the
byte-compare gate meanwhile. A package must be analysed before the entity that
`use`s it.

Regenerate, from the repository root:

    tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs      # vhdl/
    tools/bin/bazel run //platform/common/python:rdl_regs_headers   # software/include/regs/

The emitters are `platform/common/python/rdl_vhdl.py` (its `RTL_PACKAGES` table
names every package and the entity it belongs to) and `rdl_cheader_regs.py`.

Gates: `//platform/common:rdl_vhdl_pkg_test` fails when a tracked package differs
from a fresh emission by one byte; `//platform/common:rdl_pkg_vs_legacy_test`
grades every emitted value against the constants frozen before the migration; and
`//platform/common:rdl_vs_vhdl_<periph>_test` re-derives each decode out of the
VHDL and compares it against the description.

## `periph_regs`: the module that decodes the tables

`hdl/common/periph_regs.vhd` is the house peripheral bus protocol written once:
the slot decode, the byte-lane write merge, the registered read mux, the write-1
arms and the strobe retirement. A peripheral instantiates it with the tables its
`<block>_regs_pkg` already carries (`NWORDS`, `RSTVAL`, `IMPL`, `W1C`, `WOSET`,
`WOT`, `PULSE`, `RCLR`, `HWOWN`) and keeps only its datapath. That is the whole
point of the eight table constants in `vhdl/`: they are not documentation, they
are the decode. Design note, property-to-mask table, hook table and migration
recipe: `REGFILE.md`. Unit bench: `hdl/common/tb/periph_regs_tb.vhd`.

**Seventeen blocks use it**, one instance each: DMA, EVFAB, GPIO, I2C, I2CTarget,
I3C, NFC, NPU, OneWire, PWM, QSPI, RTC, SPI, SYSTEM, TIMER, TRNG and UART.

**Five do not, and will not without a change of scope:**

| block | why |
|---|---|
| CLINT, MUTEX, IRQROUTER, PWRCTRL | parameterised. The register SET is a function of the hart, mutex or vector count, so there is no constant table to pass; they also decode a bare integer index rather than a slot. Blocked until the tables can be emitted per configuration |
| DEBUG | not on the peripheral bus at all (DMI, not `EnMemPeriph` / `WEn` / `MABPart`). No adoption path |

Their packages are still emitted, tracked and gated; an unread package costs one
analysis and synthesises to nothing.

Full toolchain documentation: `tools/rdl/README.md`.
