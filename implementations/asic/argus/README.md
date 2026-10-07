# Argus

18-hart VestaRV teaching chip in TSMC 65 nm, assembled as a 3 × 3 tile array.
Generated from [`platform/common/config/argus.json`](../../../platform/common/config/argus.json);
frozen RTL snapshot in `hdl/argus/`.

| | |
|---|---|
| Harts | 18× `rv32imac_zba_zbb_zbs`, no orchestrator; hart ID from `mhartid` |
| Boot ROM | 16 KiB, shared; every hart resets to 0x0 |
| Memory | 16 KiB TCM per hart; 128 KiB shared RAM (8 × 16 KiB banks), round-robin arbitrated |
| Sync | CLINT, 32 hardware mutexes, per-hart interrupt router; 85 vectors |
| Peripherals | 4× GPIO, 2× SPI, 2× UART, 2× I²C, 2× timer, CRC16, 2× DCO, watchdog, per-tile MTCMOS gating; no NPU |

Argus differs from Castalia only in configuration knobs (`numHarts`, `numMutexes`,
`orchestrator`, `memory.sharedBulkRamSize`, NPU off); the hart tile RTL is identical.

## Build

From the repo root:

```sh
sh tools/get_bazel.sh
tools/bin/bazel run   //:generate -- --config platform/common/config/argus.json --out <dir>
tools/bin/bazel build //platform/common:chip_artifacts_argus      # hermetic: RTL, headers, pad ring, TRM sources
tools/bin/bazel test  //platform/common:argus_generation_test     # outputs present and parse
tools/bin/bazel test  //opensource_sim:isa_regression             # shared RTL, GHDL
```

Argus has no RTL identity gate: `//platform/...` grades the tracked RTL against the
Castalia configuration only. Cadence flows run outside Bazel after
`source cdspaths.sh`.

`docs/TRM.pdf` is the Technical Reference Manual.

Contact: Maxx Seminario (mseminario2@huskers.unl.edu).
