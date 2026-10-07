# SystemRDL toolchain

The SystemRDL descriptions in `hdl/common/regs/rdl/` are the register map for all 22
peripherals. A width, access code, reset value or field description is written once there
and reaches the TRM tables, `MemoryMap.h`, `MemoryMap.vhd`, `config/MemoryMap.json`, the
configurator, the register browser, the VHDL register packages and the firmware headers.
`generate.py` builds every register template from the descriptions and holds no register
data. Gates re-derive each block's decode from its VHDL and compare it with the description.
AFE/BIASG descriptions live in the gitignored `private/analog/`.

Adoption: 21 of the 22 generated packages are `use`d by their entity (all except the debug
module), and 20 blocks decode through `hdl/common/periph_regs.vhd` (all except IRQROUTER
and DEBUG); see [`hdl/common/regs/README.md`](../../hdl/common/regs/README.md).

## Files

| Path | Content |
|---|---|
| `hdl/common/regs/rdl/*.rdl` | One description per block, `vesta_udp.rdl` (user-defined properties), the chip addrmap |
| `platform/common/config/rdl.json` | Registry: file, addrmap, template, prefixes, `registerSource`, `parameters` per block |
| `platform/common/python/rdl_model.py` | Loader: compiles `.rdl` into the generator's `RegisterTemplate`/`BitField` objects |
| `platform/common/python/rdl_{latex,cheader,vhdl,configurator}.py` | Emitters into gitignored `platform/common/out/rdl/` |
| `platform/common/python/rdl_vhdl_pkg.py` | Emits tracked `hdl/common/regs/vhdl/<x>_regs_pkg.vhd`; `rdl_vhdl.RTL_PACKAGES` lists them |
| `platform/common/python/rdl_cheader_regs.py` | Emits tracked `software/include/regs/*.h` via PeakRDL-cheader |
| `platform/common/python/rdl_legacy_constants.json` | Frozen pre-migration constants, the independent reference |
| `hdl/common/regs/templates/` | Skeleton block (`skel.rdl`, `SKEL.vhd`) for new peripherals |
| `tools/rdl/requirements.in`, `requirements_lock.txt` | Pinned wheels |

## Commands

```sh
tools/bin/bazel run  //platform/common/python:rdl_vhdl_pkgs     # hdl/common/regs/vhdl/
tools/bin/bazel run  //platform/common/python:rdl_regs_headers  # software/include/regs/
tools/bin/bazel run  //:regs                                    # both, then the generator
tools/bin/bazel run  //platform/common:rdl_generate             # out/rdl/ (all four emitters)
tools/bin/bazel test //platform/... //tools/rdl:all             # all gates
```

## Changing a register

1. Edit the `.rdl`.
2. Regenerate both tracked trees and commit them with the description.
3. Run the gates. **The RTL is the authority:** when `rdl_vs_vhdl_<block>_test` fails, the
   description is wrong unless the VHDL is being changed in the same commit.
4. A geometry change also moves `rdl_legacy_constants.json`; that edit records that the
   register really changed.

Still edited in `generate.py`: peripheral identity (prose, prefixes, intro chapter, feature
line) and instantiation (base, vector, clock domain, pins, per-instance reset values for
GPIO and I2C). For a parameterised block (`clint`, `mutex_bank`, `irq_router`, `pwr_ctrl`),
`generate.py` passes the parameter values at its `_rdlRegisters()` call.

## Adding a peripheral

1. Write `hdl/common/regs/rdl/<name>.rdl` (start from `hdl/common/regs/templates/`):
   `` `include "vesta_udp.rdl" ``, one `addrmap` with `vesta_peripheral` = the template
   name (`UARTx`, not `UART0`).
2. Add an `rdl.json` entry with `"rdl": true`, file, addrmap, prefixes and
   `"registerSource": "rdl"`.
3. In `generate.py`, declare the `PeripheralTemplate` and call `_rdlRegisters('<NAME>', p)`.
   No `RegisterTemplate`/`BitField`: `rdl_vs_generator_test` rejects them.
4. Add a reader to `platform/common/python/rdl_vs_vhdl_test.py` and a target in
   `platform/common/BUILD.bazel`.
5. Add the block to `rdl_vhdl.RTL_PACKAGES` (with a `_DECODE` entry), regenerate, `use` the
   package from the entity, and add it to every RTL analysis order: tb BUILD files,
   `opensource_sim/mcu/defs.bzl`, `platform/common/python/verify_stage.py`, Genus
   `read_hdl` (package immediately before its entity) and the Xcelium cell lists.

## Description rules

- Reserved bits are omitted; the loader fills the gaps.
- `vesta_access` (`rw r r0 r1 rw0 rw1 w w0 w1`) must agree with `sw`/`hw`/`onwrite`/
  `singlepulse` or compilation fails; `woset`/`woclr`/`wot` all map to `rw1`.
  `singlepulse` is one-bit only, so write multi-bit commands as `sw = w`.
- `vesta_named_values = true` makes enum members `#define`s; otherwise they are documentation.
- Parameterised blocks set `vesta_indexed = true` and may use `{expr}` in `vesta_name`/`desc`,
  `vesta_index`, `vesta_live` and `vesta_values_*` (defined in `vesta_udp.rdl`).
- Absent registers use `` `ifdef `` guards (`VESTA_IRQR_*`, `VESTA_PWR_*`). **No defines must
  always mean the default five-hart chip.**
- An entity adopting its package must **replace** `use work.MemoryMap.all;`, not add to it;
  duplicate declarations hide each other and `rdl_vhdl_pkg_test` fails.

## Gates (`//platform/common:` unless noted)

| Target | Checks |
|---|---|
| `rdl_vhdl_pkg_test` | Tracked packages byte-identical to emission; `migrated` flags match actual `use` |
| `rdl_pkg_vs_legacy_test` | Package values equal `rdl_legacy_constants.json` |
| `rdl_vs_vhdl_<block>_test` | Description vs VHDL decode and reset branch; parameterised blocks at 1/5/18/32 harts |
| `rdl_vs_generator_test` | `.rdl` vs `config/MemoryMap.json`; registry vs `generate.py` |
| `regs_headers_identity_test`, `regs_headers_vs_memorymap_test`, `regs_headers_compile_test` | Headers current, addresses equal `MemoryMap.h`, compile at `-Werror` |
| `rdl_negative_control_test` | Each comparison fails on a one-token mutation |
| `//tools/rdl:toolchain_smoke_test`, `//tools/rdl:peakrdl_export_test` | Pinned wheels import; descriptions export via stock PeakRDL |

## Toolchain pinning

`systemrdl-compiler` (Python ≥ 3.8) is mandatory: generation stops without it. Wheels are
pinned by version and sha256 in `requirements_lock.txt`, read by `pip.parse` in
`MODULE.bazel`. Make runs the generator under `platform/common/python/rdl_python.py`, which
uses the host `python3` if it imports the compiler and Bazel's hermetic interpreter
otherwise. To relock after editing `requirements.in`:

```sh
python3.11 -m pip download --only-binary=:all: --dest /tmp/rdlwheels -r tools/rdl/requirements.in
# then write name==version --hash=sha256:<sha256sum> per wheel into requirements_lock.txt
```

`castalia_regs.h` does not co-compile with `software/commune/include/myshkin.h` (8 colliding
macros). Overlays (`VESTA_OVERLAY`) add `.rdl` files and registry rows; see
[`platform/common/README.md`](../../platform/common/README.md).
