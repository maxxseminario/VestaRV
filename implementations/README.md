# VestaRV Implementations

Per-chip documentation. Castalia and Argus are configurations of the `platform/common/`
generator ([targets and gates](../platform/common/README.md)); Myshkin uses the frozen
`platform/myshkin/` generator.

| Directory | Chip |
|---|---|
| [`asic/castalia/`](asic/castalia/README.md) | Five-hart reference MCU, TSMC 65 nm |
| [`asic/argus/`](asic/argus/README.md) | 18-hart teaching chip, 3 × 3 tile array |
| [`asic/myshkin-2025-11/`](asic/myshkin-2025-11/README.md) | Single-core tape-out, November 2025; silicon validated |
| [`asic/example-chip/`](asic/example-chip/README.md) | Template for a new ASIC |
| [`fpga/synth/`](fpga/synth/README.md), [`fpga/bringup/`](fpga/bringup/README.md) | Vivado OOC synthesis; SPI-flash boot bring-up |
| [`fpga/example-board/`](fpga/example-board/README.md) | Template for an FPGA board |

Naming: ASIC `<chip>` or `<chip>-<year>-<month>`; FPGA `<board>-<variant>`.
