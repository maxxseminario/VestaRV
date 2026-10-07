# hdl/myshkin: frozen single-core snapshot

RTL of the Myshkin tape-out (TSMC 65 nm, November 2025). Frozen: do not edit; RTL work
goes to [`hdl/common/`](../common/README.md). Chip docs:
[`implementations/asic/myshkin-2025-11/`](../../implementations/asic/myshkin-2025-11/README.md).

Contents: `MCU.vhd`, `MemoryMap.vhd` (from `platform/myshkin/`), `vesta/` (core),
`periph/` (GPIO, SPI, UART, I2C, TIMER, SYSTEM, NPU), `commune/`, `macros/`, `sim/`, `tb/`.

No Bazel target tests this tree: the unit benches and `//opensource_sim:isa_regression`
exercise `hdl/common/`. `//hdl:vhdl_sources` only declares its files as inputs.
