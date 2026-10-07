# Argus

18-hart VestaRV teaching chip, TSMC 65 nm, assembled as a 3 × 3 tile array. Generated
from [`platform/common/config/argus.json`](../../../platform/common/config/argus.json);
frozen RTL snapshot in `hdl/argus/`.

| | |
|---|---|
| Harts | 18× `rv32imac_zba_zbb_zbs`, no orchestrator |
| Memory | 16 KiB shared boot ROM; 16 KiB TCM per hart; 128 KiB shared RAM |
| Sync | CLINT, 32 mutexes, per-hart interrupt router |
| Peripherals | 4× GPIO, 2× SPI, 2× UART, 2× I²C, 2× timer, CRC16, watchdog; no NPU |

```sh
tools/bin/bazel build //platform/common:chip_artifacts_argus
tools/bin/bazel test  //platform/common:argus_generation_test
```

Argus has no RTL identity gate: `//platform/...` grades the tracked RTL against
Castalia only. TRM: `docs/TRM.pdf`.
