# Register sources

`rdl/` holds the hand-written SystemRDL descriptions and is the authority. `vhdl/` holds the
22 generated `<block>_regs_pkg.vhd` packages, tracked because Genus, Xcelium and GHDL read
the tree directly. **Never hand-edit `vhdl/`**; analyse a package before its entity.
`periph_regs` design note: `REGFILE.md`. Toolchain and gates:
[`tools/rdl/README.md`](../../../tools/rdl/README.md).

```sh
tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs      # vhdl/
tools/bin/bazel run //platform/common/python:rdl_regs_headers   # software/include/regs/
```

A change to `hdl/common/periph_regs.vhd` or any `vhdl/` table moves every frozen count in
`toolchains/ghdl/synth_census.json` (`//toolchains/ghdl:synth_census_test`).
