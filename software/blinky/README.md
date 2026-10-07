# blinky — smoke application

Minimal VestaRV app and the template for the other app packages; targets and
conventions are in [`software/README.md`](../README.md).

```sh
tools/bin/bazel build //software/blinky:blinky_flashed_rcf       # from the repo root
tools/bin/bazel test  //software/blinky:blinky_flashed_rcf_test
```

- Does not currently boot from flash: links at `0x814C`, the flash tool loads at
  `0x8000`, the boot ROM jumps to `0x8200`. The golden test checks bytes only.
- A firmware change regenerates `testdata/blinky_flashed_rcf_golden.txt` in the same commit.
