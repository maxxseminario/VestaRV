# Register sources

`rdl/` holds the hand-written SystemRDL descriptions (one `<block>.rdl` per peripheral,
`vesta_udp.rdl`, the chip addrmap) and is the authority. `vhdl/` holds the 22 generated
`<block>_regs_pkg.vhd` packages, tracked because Genus, Xcelium and GHDL read the tree
directly. **Never hand-edit `vhdl/`**: `//platform/common:rdl_vhdl_pkg_test` fails on any
byte difference. Analyse a package before the entity that `use`s it. `templates/` is a
skeleton block for new peripherals. Toolchain and gates:
[`tools/rdl/README.md`](../../../tools/rdl/README.md).

```sh
tools/bin/bazel run //platform/common/python:rdl_vhdl_pkgs      # vhdl/
tools/bin/bazel run //platform/common/python:rdl_regs_headers   # software/include/regs/
```

`hdl/common/periph_regs.vhd` is the shared peripheral bus decode, driven by the package
tables (`NWORDS RSTVAL IMPL W1C WOSET WOT PULSE RCLR HWOWN`); design note `REGFILE.md`,
bench `hdl/common/tb/periph_regs_tb.vhd`. 20 blocks use it; IRQROUTER (524-word window,
64 decoded) and DEBUG (on the DMI) cannot. A change to it or to any `vhdl/` table moves
every frozen count in `toolchains/ghdl/synth_census.json` (`//toolchains/ghdl:synth_census_test`).
