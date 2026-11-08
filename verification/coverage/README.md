# Coverage collection, Castalia multi-hart

Xcelium code and FSM coverage over the behavioral suite at the shipped configuration
(five harts), merged per hart class, plus hand-defined crosses from a monitor.

| File | Job |
|---|---|
| `run_coverage.sh` | compile once, elaborate two snapshots, run a test list, keep per-test results |
| `castalia.ccf` | coverage scope: every `vesta` subtree, the arbiter, the reservation unit, the mutex bank; toggle on `maindec`, `c_dec`, `mp_arbiter` |
| `gen_cov_mon.py` | writes the monitor and the two tops, taking the enum literals from the RTL |
| `ucis_dump.py` | reads one `.ucd` through `libucis.so` with ctypes |
| `merge_cov.py` | merges by summation, reports per class, compares the tool against the monitor |
| `compare_verdicts.py` | instrumented run against the uninstrumented reference |
| `crosses.py` | prints the crosses from a merged JSON |

## Why there is no IMC here

Xcelium 20.09 ships `imc` only with vManager, and an older IMC (IUS 15.2) rejects a 20.09
database with `serialization exception`. 20.09 does install the UCIS read API, so the per-test
databases are read through it and merged by key. All tests share one snapshot, hence one
model, which is the condition that makes a sum equal to an IMC union merge.

## Prerequisites, once per tree

```sh
tools/bin/bazel build //tools/rdl:all          # the wheels make generate needs; in a worktree, link tools/bin/bazel first
make -C platform/common generate
python3 tools/cosim/check_gate_files.py --restore
python3 platform/common/python/verify_stage.py  # run from platform/common
# then verification/isa/build_mp_images.sh with the printed NHARTS, RCF_DEST, GROUPS and
# DEFINES, exactly as platform/common/verify.sh does it
```

## Run

```sh
verification/coverage/run_coverage.sh build
verification/coverage/run_coverage.sh run cov     # coverage + monitor
verification/coverage/run_coverage.sh run base    # uninstrumented reference
verification/coverage/compare_verdicts.py <work>/results/base <work>/results/cov
verification/coverage/run_coverage.sh merge
```

`<work>` is `xcelium/riscv_test/cov_castalia`. A rerun skips tests that have a verdict file;
`FORCE=1` reruns them. A test can be left out of a merge with `merge --exclude name`, which
is the negative control: the state only that test enters must fall to zero.

Random streams go through the same runner with a different image directory and result tag:

```sh
IMG_DIR=verification/isa/rcf_kf8k TESTS_FILE=list RUN_TAG=rand \
    verification/coverage/run_coverage.sh run cov
verification/coverage/run_coverage.sh merge --tag cov,rand --out merged_rand
```

## Reading the numbers

The denominators come from the elaborated model, and one model serves both hart classes: a
tile's FSM and block counts include arms its generics make unreachable. A state the tool
lists and no test reaches therefore needs classifying before it means anything.
