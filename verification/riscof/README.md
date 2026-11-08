# verification/riscof: riscv-arch-test conformance

Runs the official riscv-arch-test suite (3.x, the RISCOF-format tree) on the Castalia
multi-hart behavioural simulation and compares every signature with Spike and Sail. The
test runs on one chosen hart while the rest of the chip is live; hart 0 launches it, then
reads the signature back through its load path and streams it to the bench on `a0`.

| Path | Role |
|---|---|
| `run_riscof.sh` | one run: ISA profile (`tile`, `orch`) on a hart |
| `vesta/` | DUT plugin, ISA and platform YAMLs, `env/` (model header, launcher, link map) |
| `ref/` | reference plugin (Spike and Sail in one run), Sail config generator |
| `sim/` | stage the snapshot, derive the bench, ELF to image, run a test, report, slicer |
| `exclusions.txt` | every excluded test with its reason |
| `repro/` | directed checks against Spike: the CSR stall, misaligned traps, the decode fixes, `jalr` bit 0 |

## Run

Needs Xcelium (`cdspaths.sh`), `riscv-none-elf-gcc`, Spike (path from the `spike` key of
the reference plugin config in `ref/`), a python >= 3.7 environment with `pip install riscof`,
a riscv-arch-test checkout (tag 3.10.0 was used) and optionally the prebuilt
`sail_riscv_sim` from the sail-riscv releases page.

```sh
sim/stage.sh                                  # compile + elaborate into xcelium/riscof
export RISCOF_ENV=<prefix> ARCH_TEST=<checkout> SAIL=<sail_riscv_sim>
./run_riscof.sh tile 1 /path/to/work/tile_h1  # harts 1-4
./run_riscof.sh orch 0 /path/to/work/orch_h0
sim/report.py table.md h1=/path/to/work/tile_h1 h0=/path/to/work/orch_h0
```

Conformance is per hart: the hart index is a parameter, and only one word of the image
changes with it. `report.py` reads the signatures itself rather than RISCOF's verdict.

## What differs from a stock RISCOF target

- `sim/patch_arch_test.py` moves the trap handlers into TCM; this is the only change to
  the test environment, and it exists because of a core defect (`repro/`).
- Tests too large for the chip's RAM cannot link. `sim/split_big.py` makes slices of them
  with every case kept in exactly one slice; run those with `SUITE=<dir>/rv32i_m`.
- `LOAD=preload` (default) bakes the shared-RAM body into the RAM macros at elaboration,
  against about 24 us of sim time per word for `LOAD=flash`, the full bootrom SPI load.
- The `orch` YAML states `misa` without B (reset value 0x40001105): riscv-config rejects
  the letter. The RTL reads 0x40001107.
