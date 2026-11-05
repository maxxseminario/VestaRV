# coverage: first coverage collection, Castalia five-hart behavioral flow

## Result

Coverage now runs on the shipped five-hart Castalia configuration, merged per hart class, over the 157-test catalog (all sh* tests included). All 157 pass with and without instrumentation, and every test ends at the same femtosecond (0 differences).

| `cpu_state`, 157 tests | hart 0 (orch) | harts 1-4 (tile) |
|---|---|---|
| states reached (of 42) | 19 | 15 |
| unreachable by config | 18 | 20 |
| dead in every config (INITIALIZE) | 1 | 1 |
| reachable but untested | 4 | 6 |
| transitions reached (of 118) | 32 | 23 |
| transitions never reached | 86 | 95 |
| of those, unreachable by config | 50 | 57 |
| of those, dead in every config | 2 | 2 |
| of those, reachable but untested | 34 | 36 |

- **Main gap:** no interrupt has ever been taken at the end of an atomic or (on hart 0) a divide. `irq_save` is 0 in every AMO, LR, SC and DIV state on all five harts.
- **Tiles:** a tile takes an interrupt only from SLEEPING, never while running.
- **Standard trap delivery:** on tiles it is untested. On hart 0, one test (`rocsrw`) carries it in the catalog.
- **RTL bugs:** none found. Three items are marked suspicious below.
- **Random campaign:** it adds 0 states, 0 transitions and 0 cross bins, and 4 blocks on hart 0.

`imc` does not exist for this Xcelium. Merging is done through the UCIS library Xcelium does ship (see Tooling).

## Measured

### Code coverage (covered/total items, from the elaborated model)

| Unit | Metric | orch | tile |
|---|---|---|---|
| `maindec` | block | 342/433 | 260/433 |
| | branch | 109/148 | 92/148 |
| | toggle | 195/276 | 176/276 |
| `c_dec` | block | 61/110 | 47/110 |
| | branch | 58/106 | 44/106 |
| | toggle | 131/132 | 132/132 |
| whole core | block | 1471/2454 | 1085/2404 |
| | branch | 871/1637 | 594/1596 |

The tile column is the union of harts 1-4. Denominators include logic the generics disable, so these are not quality scores. Most unhit `maindec` and `c_dec` items are the Zbk*, Zkn, Zfinx, Zcmp, Zcmt, Zcb, Zimop and U-mode arms (read from the source lines, not counted one by one).

Fabric:
- `mp_arb0`: block 31/33, branch 22/24, toggle 913/1052, states 4/4, transitions 8/9.
- `resv0`: block 36/36, branch 20/20.
- `mtx0`: block 6/6, branch 2/2.

### States never reached

| State | Hart class | Classification | Basis |
|---|---|---|---|
| CBOZ_WRITE, CBOZ_GAP | both | unreachable by config | ZICBOZ off, decode gated (`maindec.vhd:462`) |
| 11 ZCM_* states | both | unreachable by config | ZCMP and ZCMT off (`maindec.vhd:468`) |
| FPU_FETCH3, FPU_WAIT, FPU_DONE | both | unreachable by config | ZFINX off |
| PAUSE_WAIT | both | unreachable by config | ZIHINT off |
| WRS_WAIT | both | unreachable by config | ZAWRS off |
| DIV_WAIT, DIV_DONE | tile | unreachable by config | `TILE_ENABLE_DIV` false (`maindec.vhd:935`) |
| INITIALIZE | both | suspicious (dead, all configs) | see S2 |
| DBG_SV, DBG_JUMP, DBG_RET | both | reachable but untested here | needs the `xrun_dbg.sh` harness, not run |
| TRAP_STATE | orch | reachable but untested | terminal on hart 0, so a passing test cannot end there; tiles reach it in 5 tests by design |
| MTRAP_SV, MTRAP_JUMP, MTRAP_RET | tile | reachable but untested | `TILE_ENABLE_TRAPCSR` true, but no tile code leaves legacy mode |

### Transitions never reached, excluding config-dead ones

| Group | orch | tile | Transitions |
|---|---|---|---|
| Legacy interrupt after an atomic or divide | 5 | 4 | AMO_WRITE, AMO_COMPLETE, LR_READ, SC_CHECK (and DIV_DONE on orch) -> IRQ_SV |
| Legacy interrupt, other | 1 | 3 | IRQ_REST -> IRQ_SV; tile also EXECUTE and MEMORY_WAIT -> IRQ_SV |
| Standard delivery | 8 | 12 | the same check points -> MTRAP_SV; tile also the whole MTRAP path |
| Sleep | 3 | 3 | IRQ_REST -> SLEEPING, SLEEPING -> EXECUTE, SLEEPING -> SLEEPING |
| Debug | 15 | 14 | every -> DBG_SV, the DBG_JUMP and DBG_RET paths |
| Terminal trap | 2 | 0 | EXECUTE -> TRAP_STATE, TRAP_STATE hold |
| Dead (S2, S3) | 2 | 2 | INITIALIZE -> EXECUTE, EXECUTE -> IRQ_REST |

All of these are reachable but untested except the Dead row. Full lists are in `coverage_merged.json`.

### Suspicious

- **S1, arbiter release valve.** LOCKED -> IDLE (`mp_arbiter.vhd:188`) has 0 hits in 2,584 LOCKED cycles. Its comment says an AMO that ends without a write takes it, but AMO_READ, AMO_WRITEBACK and AMO_COMPUTE have no divert arm, and the AMO_WRITE arm issues its write first. From the core side it looks unreachable. Tile power-down isolation dropping `lock` mid-AMO was not analysed. This is a formal candidate (roadmap step 4).
- **S2, INITIALIZE is dead.** Reset loads EXECUTE (`vesta.vhd:1285`), and `next_state <= INITIALIZE` appears only in the reset branch. The tool's hit is the time-zero default value; the monitor never sees it on a clock edge.
- **S3, EXECUTE -> IRQ_REST arms are shadowed.** `vesta.vhd:2276`, `2390` and `2543` sit below the `mem_access_controller` arms at `2242`, `2366` and `2513`, and iret always raises that flag (`maindec.vhd:924`, with `IRET_FN3` and `IRET_FN7` both zero). Iret always goes through MEMORY_WAIT. Harmless dead logic, by reading; not proven formally.

### Crosses (monitor, per hart, sampled on `clk_cpu` unless stated)

- **`cpu_state` x `irq_save`:** high only in EXECUTE (10), MEMORY_WAIT (17), IRQ_SV, IRQ_JUMP and SLEEPING (2) on hart 0. Tiles: only SLEEPING, IRQ_SV, IRQ_JUMP (101 each).
- **`cpu_state` x `sh_sel`:** hart 0 runs AMOs on both private (29) and shared (67) memory. Tiles run AMOs and LR/SC only on shared memory.
- **AMO phase x arbiter grant:** across 323 cross-hart AMOs (67 hart 0, 256 tile), no cycle of AMO_READ, AMO_WRITEBACK or AMO_COMPUTE saw another master hold the arbiter, sampled on `mclk`. 323 equals the DATA -> LOCKED count exactly.
- **PMP cross:** no bins, since PMP is off on every Castalia hart.

The `clk_cpu` table shows AMO_WRITE with LOCKED/other = 177 on tiles, which looks alarming. It is a sampling artefact: `clk_cpu` is gated, so the state is seen only at its release edge, after the arbiter has moved on. The `mclk` table was added to check this. It shows 0 LOCKED/other in AMO_WRITE and one self LATCH and DATA per AMO.

### Random campaign and non-catalog images

- **Six K3 streams** (6/6 byte-reproducible; 6/6 pass, identical with and without instrumentation): 0 new states, 0 new transitions, 0 new cross bins. They add 4 blocks and 4 branches on hart 0, 2 of each in `c_dec`. Tile numbers do not move, because the streams run on hart 0 only.
- **86 built images outside the catalog:** 22 pass, 64 fail. Merging the 22 adds 4 hart-0 transitions: `MEMORY_WAIT -> MTRAP_SV` (`privirq`), `SLEEPING -> EXECUTE` (`privwfi`), and `IRQ_REST -> SLEEPING` and the SLEEPING hold (`ignleak`, `insretov`).
- **The 64 failures are not triaged.** Six were sampled (`privmret`, `privecal`, `privebrk`, `privmcau`, `privmst`, `privmie`), and `privmret`'s header pins the trapCsr-OFF polarity. Most of the rest are knob-specific by name. These failures are not evidence of a defect, and they are excluded from all merges.

### Instrument validation

| Check | Result |
|---|---|
| Verdicts and end time, directed | 157 compared, 0 differences |
| Verdicts and end time, random | 6 compared, 0 differences |
| Tool vs monitor, moving transitions | orch 30 = 30, tile 21 = 21, none outside the model |
| Tool vs monitor, states | agree except INITIALIZE (S2) |
| Negative control: drop `rocsrw` | hart-0 MTRAP_SV 6 -> 0 in both instruments; AMO_READ unchanged at 96 |
| Negative control: drop `shamo` | tile AMO_READ 256 -> 0 in both instruments |
| Seeded fault: end time off by 1 fs | comparator reports DIFF, exit 1 |
| Seeded fault: monitor loses a row | check reports `only-tool ['MEMORY_WAIT->IRQ_SV']` |
| Expected-fail streams `k3nc1`, `k3nc2` | both FAIL through the runner |

The tool-vs-monitor check earned its place. The first CCF used `set_fsm_reset_scoring`, which reported EXECUTE as never reached; a toy design confirmed it moves reset-state entries out of the count. It was removed and the suite rerun.

Cost at 4 parallel: 14m49s with coverage against 9m51s without (summed wall 3327 s against 2303 s). The work directory is 177 MB.

## Not measured

- **Other polarities:** only the shipped configuration. The roadmap asks for both polarities and all 248 images.
- **Debug:** the `xrun_dbg.sh` flows were not run, so all DBG_* numbers are zero by flow, not proven gaps.
- **Expression coverage:** instrumented, but the UCIS walk returned no items. Not reported.
- **Gate level:** nothing.
- **Sign-off of the classifications:** they come from reading the RTL. Only the config-dead rows were checked against the decode. Reachable-but-untested means no gating found, not a demonstrated path.
- **Rerun scope:** the suite ran before a late fix giving the monitor write access, which cleared a harmless `*E,OBJACC` per mirror. Four tests were rerun after the fix; all 20 monitor files are byte-identical. The other 153 were not rerun.
- **RTL source:** the ARM memory models are gitignored, so they were read from `~/vestarv/hdl/common/sim`. The ROM image matches the tracked record (the runner checks this).

## RTL findings

None needing a fix. S1-S3 above are for the owner's judgement. No files under `hdl/` changed.

## Tooling

- **`imc`:** absent from all three Xcelium trees (18.09, 19.03, 20.09). The only copies are IUS 15.2, under `/mnt/poseidon/cadence/INCISIV152` and the aegean backups.
- **IUS 15.2 route:** it rejects a 20.09 database (`serialization exception`). IUS `irun` fails on licensing, so it cannot produce a compatible database either.
- **What was used:** `libucis.so` and `ucis.h` ship with Xcelium 20.09. `ucis_dump.py` reads them through ctypes, and `merge_cov.py` sums by key. All tests share one snapshot, so all share one model; 0 shape mismatches were recorded across the 157 databases.
- **Crosses:** VHDL has no route to internal signals here, so a monitor reads them through `xm_mirror`, with no path back into the design.
- **Stale tracked list:** `tools/cosim/gate/behavioral_mp/cell_list_behavioral.txt` lacks `sync.vhd` and `PINMUX.vhd`, and `verify_stage.py` injects neither. The staged list fails analysis on current main (62 `SELLIB` errors), so `make verify` should fail in a fresh tree too, though `make verify` itself was not run. The runner works around it.

## Reproduce

In the worktree, per `verification/coverage/README.md`:

```sh
verification/coverage/run_coverage.sh build
verification/coverage/run_coverage.sh run cov
verification/coverage/run_coverage.sh run base
verification/coverage/compare_verdicts.py xcelium/riscv_test/cov_castalia/results/base xcelium/riscv_test/cov_castalia/results/cov
verification/coverage/run_coverage.sh merge
verification/coverage/crosses.py xcelium/riscv_test/cov_castalia/results/merged.json
verification/coverage/run_coverage.sh merge --exclude rv32ua-p-rocsrw --out nc_rocsrw
```

Merged data: `~/work/chip_docs/castalia/next_steps_2026-11/coverage_merged.json`.

## Files changed in the worktree

New and uncommitted, all under `verification/coverage/`: `run_coverage.sh`, `castalia.ccf`, `gen_cov_mon.py`, `ucis_dump.py`, `merge_cov.py`, `compare_verdicts.py`, `crosses.py`, `README.md`, and this report. Nothing tracked changed.

## Owner decisions

1. Write a directed test for interrupts landing on atomics and divides, on hart 0 and tiles. This is the bug class of M8 and irqctx, and the largest gap here. It needs an edge-determined trigger, not a calibrated one (method rule 7).
2. Add the passing non-catalog tests (`privirq`, `privwfi`, `ignleak`, `insretov`) to the Castalia catalog, or say why not.
3. Decide whether tiles need any standard-trap test, given they ship with TRAPCSR on.
4. Repair the tracked cell list.
5. Keep, or remove, the S1-S3 logic. Removing any moves the netlist, so that waits for closure.
