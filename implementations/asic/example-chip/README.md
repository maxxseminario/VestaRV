# Example ASIC Chip

Template for a new VestaRV ASIC. A chip is a configuration of the `platform/common/`
generator; full procedure in [`docs/new_chip.md`](../../../docs/new_chip.md).

1. Add the configuration under `platform/common/config/` (start from `asic_default.json`).
2. Add a `chip_artifacts` rule to `platform/common/BUILD.bazel` modeled on
   `//platform/common:chip_artifacts_argus`, `config =` pointing at the file.
3. Add a generation test modeled on `//platform/common:argus_generation_test`.

```sh
tools/bin/bazel build //platform/common:chip_artifacts_<chip>
tools/bin/bazel test  //platform/...
```

Use the `chip_artifacts_*` target, not `bazel run //:generate`, which writes wherever
it is invoked.

Document: process, tape-out date, core ISA, memory, clock, peripherals, silicon
status; directories `docs/`, `config/`, `images/`, `specifications/`.
