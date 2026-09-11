# Register sources

One root for the register map: the descriptions and the VHDL generated from them.

| path | what |
|---|---|
| `rdl/` | the SystemRDL descriptions, hand-written: one `<block>.rdl` per peripheral, `vesta_udp.rdl` (the user-defined properties every block includes) and `castalia_penta_wound_afe.rdl` (the chip addrmap) |
| `vhdl/` | `<block>_regs_pkg.vhd`, one GENERATED package per block, 24 of them |

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

Full toolchain documentation: `tools/rdl/README.md`.
