# SystemRDL toolchain

The descriptions in `hdl/common/regs/rdl/` are the register map for all 22 peripherals.
`generate.py` builds every register template from them (registry:
`platform/common/config/rdl.json`). TRM tables, `MemoryMap.h`/`.vhd`, the configurator and
the tracked VHDL packages and firmware headers are all regenerated from them. Wheels are
pinned in `requirements.in` / `requirements_lock.txt`; `systemrdl-compiler` (Python ≥ 3.8) is
mandatory. AFE/BIASG descriptions live in the gitignored `private/analog/`.

```sh
tools/bin/bazel run  //platform/common/python:rdl_vhdl_pkgs     # hdl/common/regs/vhdl/
tools/bin/bazel run  //platform/common/python:rdl_regs_headers  # software/include/regs/
tools/bin/bazel test //platform/... //tools/rdl:all             # all gates
```

## Changing a register

Edit the `.rdl`, run both regenerators, commit the tracked outputs with it, run the gates.

- **The RTL is the authority:** when `rdl_vs_vhdl_<block>_test` fails, fix the description.
- A geometry change to a migrated block also changes
  `platform/common/python/rdl_legacy_constants.json`.
- Peripheral prose, prefixes and instantiation (base, vector, pins, per-instance resets)
  stay in `generate.py`.

## Adding a peripheral

1. Write `<name>.rdl` (`` `include "vesta_udp.rdl" ``, `vesta_peripheral` = template name, e.g. `UARTx`).
2. Add an `rdl.json` entry with `"rdl": true` and `"registerSource": "rdl"`.
3. In `generate.py`, declare the `PeripheralTemplate` and call `_rdlRegisters('<NAME>', p)`;
   no `RegisterTemplate`/`BitField`.
4. Add a reader to `platform/common/python/rdl_vs_vhdl_test.py` and a target in
   `platform/common/BUILD.bazel`.
5. Add the block to `rdl_vhdl.RTL_PACKAGES`, regenerate, and add the package to every RTL
   analysis order (tb BUILD files, `opensource_sim/mcu/defs.bzl`,
   `platform/common/python/verify_stage.py`, Genus `read_hdl`, Xcelium cell lists).

## Caveats

- `vesta_access` must agree with `sw`/`hw`/`onwrite`/`singlepulse` or compilation fails.
- Shape guards (`VESTA_IRQR_*`, `VESTA_PWR_*`) must keep "no defines = default five-hart chip".
- An entity adopting its `<x>_regs_pkg` must **replace** `use work.MemoryMap.all;`, not add
  to it; duplicate declarations hide each other.
- Genus reads each package immediately before its entity; `genus/` is gitignored, so a
  fresh area must re-add the `read_hdl` pairs.
- `castalia_regs.h` does not co-compile with `software/commune/include/myshkin.h`.
- Overlays (`VESTA_OVERLAY`) add `.rdl` files and registry rows; regenerating writes the
  tree's own blocks too, so keep only the overlay's output.
