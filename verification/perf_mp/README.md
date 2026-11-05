# verification/perf_mp: multi-hart performance measurement

Sibling of `verification/cpi/`. That harness is one bare core with one-cycle memory under GHDL; this one runs the real
five-hart default Castalia `MCU.vhd` under Xcelium, booted through the shared ROM and SPI flash like every `sh*` test,
so `mp_arbiter`, the tile boundary registers and the CLINT are all in the path. All results are behavioral simulation.

## Run

```sh
cd verification/perf_mp          # python is /usr/bin/python3.6; MAX_PARALLEL defaults to 4
./fetch_coremark.sh              # pinned EEMBC sources into the run dir (not vendored)
python3.6 run_mpcpi.py setup     # snapshots perf_d0 and perf_d3 under xcelium/riscv_test/perf_mp
python3.6 run_mpcpi.py sweep     # -> results/mpcpi.json
python3.6 run_mpcpi.py negctrl   # -> results/negctrl.json
python3.6 run_irqlat.py matrix   # -> results/irqlat.json
python3.6 run_flat.py setup; python3.6 run_flat.py all   # one-cycle ceiling -> results/flat.json
python3.6 run_bench.py plan all  # CoreMark, Dhrystone -> results/bench/*.json
python3.6 check_results.py results/mpcpi.json t1_lw_n0   # gate against expected_mp.json
```

Needs the gitignored `ARM_IP_RAM.vhd`/`ARM_IP_ROM.vhd` from `~/vestarv/hdl/common/sim` (read only; the ROM path is
retargeted to `tools/cosim/gate/bootrom_mp_rom.rcf`) and the pad Verilog named in `cell_list.txt`.

## Files

| File | Role |
|---|---|
| `perf_mon.vhd` | Observer beside the testbench (external names): print window, per-hart arbiter wait, interrupt timing, heartbeat, and the `STALL_D` injected delay |
| `perf_top.vhd` | Top: `riscv_tb` plus `perf_mon`; one snapshot serves all images, each run's cwd supplies `../rcf/` |
| `gen_mpcpi.py`, `run_mpcpi.py` | Per-class kernels on one hart while others hammer the shared window |
| `gen_irqlat.py`, `run_irqlat.py` | mtimecmp phase sweep over victim instructions, both delivery modes |
| `run_bench.py`, `rt/`, `coremark/` | CoreMark and Dhrystone: port, startup, per-variant linker scripts, flash image composer (`compose.py`) |
| `run_flat.py` | Same binaries on `verification/cpi`'s bench: the flat one-cycle ceiling |
| `check_results.py`, `expected_mp.json` | Exact gate on uncontended rows |

The testbench copy changes two things only, both in `simlib.setup()`: the 100 ms watchdog and the flash model's size.

## Method rules

- `mcycle` and `minstret` are the counters: `mcycle` is on free-running mclk, so stalls count. Zihpm is off in the
  shipped configuration, so `mhpmcounter*` read zero and are not used. Interrupt latency cannot be taken from them and
  comes from `perf_mon`.
- Kernels are 32 copies against an empty loop in the same memory; `.option norvc` except `*16`, word-aligned.
- An idle hart issues no shared traffic (parked in ROM, or `extinguish`/WFI), so "0 others" is a true zero.
- Same-word LR/SC kernels use fixed attempts and count failures. A retry loop does not terminate when SC is starved.
- Long runs: `perf_mon` reports retires per hart every 4M cycles (`HB` lines in `xmsim.log`). `simlib.sim` kills a run
  whose counts stop moving, and `budget_s` comes from the recorded cycle estimate in `run_bench.PLAN`.
- Do not name an image with `spi`, `uart`, `timer` or `gpio`: `riscv_tb` keys pin shorts on the file name.

## Limits

DMA and the debug module are arbiter masters too (N=7) and stay idle here. Contended numbers depend on round-robin
phase, so they are not gated. Not silicon, no SDF timing, no bus-level jitter from real clocks.
