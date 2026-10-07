# Example ASIC Chip

Template for documenting a new VestaRV ASIC. A new chip is a new configuration of the
`platform/common/` generator; [`docs/new_chip.md`](../../../docs/new_chip.md) has the
full procedure.

## Adding a chip

1. Put the configuration under `platform/common/config/` (start from
   `asic_default.json`).
2. Add a `chip_artifacts` rule to `platform/common/BUILD.bazel` modeled on
   `//platform/common:chip_artifacts_argus`, with `config =` pointing at the file.
3. Add a generation test modeled on `//platform/common:argus_generation_test`.

```sh
tools/bin/bazel run   //:generate -- --config platform/common/config/<chip>.json --out <dir>
tools/bin/bazel build //platform/common:chip_artifacts_<chip>    # hermetic equivalent
tools/bin/bazel test  //platform/...                             # inherited generator gates
```

Cadence flows run outside Bazel after `source cdspaths.sh`.

## Template

| | |
|---|---|
| Chip / tape-out | `<name>`, YYYY-MM |
| Process | e.g. 65 nm |
| Application | e.g. sensor hub |
| Core | VestaRV32, ISA string |
| Memory | ROM, RAM sizes |
| Clock | e.g. 24 MHz |
| Peripherals | GPIO, UART, SPI, timer, ... |

Directories: `docs/` (user guide, datasheet), `config/` (generation JSON), `images/`
(block diagram, floorplan), `specifications/` (electrical, timing, validation).

Silicon status: RTL / synthesis / P&R / tape-out submitted / silicon received / validated.
