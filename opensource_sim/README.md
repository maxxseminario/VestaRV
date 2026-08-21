# VestaRV open-source simulation & verification quickstart

This directory drives a 100%-open-source simulate/verify flow for the `vesta`
RISC-V core (RV32IMAC + Zb\*, multicycle, plus the X-series Z-extensions —
Zicond, Zcb, Zimop, Zihint, Zicboz, Zabha, Zacas, Zcmp, Zcmt, scalar-crypto
Zbkb/Zbkc/Zbkx/Zkn, and the Zfinx single-precision FPU) — GHDL as the VHDL
simulator, cocotb for the smoke test, and the riscv-tests-derived ISA suite for
instruction coverage. No proprietary EDA tools or licenses are involved
anywhere in this directory.

The ISA testbench enables every one of those extension generics that a single
bare core can actually exercise, and builds the `verification/isa` ext-probes
with the matching `-DCORE_ENABLE_<EXT>` so their result-checking (ON) arm runs
against the enabled RTL; Zfinx is additionally covered end-to-end by the
`rv32uzf` functional suite. Exactly TWO implemented extensions are left off,
each a genuine single-bare-core limit (not a tooling gap), with justification in
the SKIP table of `isa/run_isa.sh`: Zawrs (`wrs.nto` blocks on a reservation
only another master can clear) and Zihpm (its probe needs the counter-static
polarity). Those two extensions' MCU-dependent behaviour, plus every
extension's illegal-encoding negative-control "poison" and the multi-hart /
peripheral system tests, need the MCU or a multi-hart / trap-watching harness
and are SKIP-listed, never silently dropped.

This is **simulate/verify only**. [`sky130/`](../sky130/README.md) takes the
same RTL all the way to a signed-off sky130 GDSII (synthesis, P&R, DRC, LVS);
this directory just proves the RTL is functionally correct first, with a much
lighter toolchain (no PDK, no LibreLane).

## Quick start

```sh
git clone https://github.com/maxxseminario/VestaRV.git && cd VestaRV
./opensource_sim/setup_env.sh && source opensource_sim/env.sh
./opensource_sim/run_sim.sh
```

The first command installs GHDL/gcc/make (via your system package manager),
a Python venv with cocotb, and a pinned RISC-V GCC toolchain (system-wide if
one's already on your PATH, otherwise a self-contained download — nothing
outside this directory is touched). The second runs the cocotb smoke test
and the full ISA regression and prints a combined pass/fail summary.

## Building and testing with Bazel

The same regression runs as bazel tests, and that is the recommended path: the
simulator is `@ghdl` built from source, the images come from
`//verification/isa`'s ON-polarity `os_*` targets, and the RISC-V toolchain is
fetched and pinned by the build. Nothing is installed on the host, so no GHDL
version check, no venv, and no container fallback is involved. Every command is
run from the repo root. The `setup_env.sh` / `run_sim.sh` flow above stays as
the legacy path, and it is still the only one that runs the cocotb smoke test.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

| Target | Verb | What it proves |
|---|---|---|
| `//opensource_sim:isa_regression` | test | the whole nine-suite ISA regression, the tier-2 CI gate |
| `//opensource_sim:isa_rv32ui` | test | one suite through `run_isa.sh` in prebuilt-image mode; likewise `:isa_rv32um`, `:isa_rv32ua`, `:isa_rv32uc`, `:isa_rv32uzba`, `:isa_rv32uzbb`, `:isa_rv32uzbc`, `:isa_rv32uzbs`, `:isa_rv32uzf` |
| `//opensource_sim/isa:rv32ui` | test | the finer-grained port: one bazel target per image, so a single failure names itself (pilot scope, rv32ui, CI-polarity images) |
| `//opensource_sim/isa:rv32ui-p-add` | test | one image on its own - the per-test debug loop, in place of a hand-written `ghdl -r` |
| `//opensource_sim/isa:vesta_isa_lib` | build | the curated RTL source order plus `vesta_isa_tb.vhd` still analyze clean under `--std=08 -fsynopsys` |
| `//opensource_sim/isa:source_list_sync_test` | test | that curated order still matches `run_isa.sh`, `sky130/synth.sh` and `sky130/sim/Makefile` |
| `//verification/isa:os_rv32ui_rcfs` | build | the ON-polarity images a suite consumes, defines mirroring `run_isa.sh`'s `CORE_ENABLE_DEFS` |
| `//toolchains/ghdl:ghdl` | build | the from-source GHDL (mcode backend) the tests run on |

The full target map is in [`BAZEL.md`](../BAZEL.md).

## CI (`.github/workflows/sim.yml`)

The ISA regression is also the repo's tier-2 CI, as bazel tests: `bazel test
//opensource_sim/...` runs one `sh_test` per suite on every PR / push /
nightly, fully hermetically — the images come from `//verification/isa`'s
`os_*` targets (hermetic xPack GCC, defines mirroring `run_isa.sh`'s
`CORE_ENABLE_DEFS`), the simulator is `@ghdl` built from source, and its
std/ieee libraries are bazel outputs. The runner installs nothing but
bazelisk. The wrappers drive `run_isa.sh` in prebuilt-image mode
(`ISA_BUILD_DIR` set ⇒ the make step and the RISC-V-toolchain requirement
drop away; `ISA_WORK_DIR` keeps GHDL's work library out of the read-only
runfiles tree). The cocotb smoke test rides in `physical.yml` instead (its
`sim-smoke` job), so CI covers both halves of `run_sim.sh`.

## What just ran

**Smoke test** (`sky130/sim`, via `make -C sky130/sim`): a cocotb testbench
drives the bare `vesta` core against a behavioral 3-instruction program
(`lui`/`addi`/self-loop) and checks the magic value lands in `a0`, the gated
core clock actually toggles, and no trap ever fires. It's the same test
`sky130/README.md`'s flow uses as its simulation-side signoff step — see
[`sky130/sim/Makefile`](../sky130/sim/Makefile) and
[`sky130/sim/test_vesta_smoke.py`](../sky130/sim/test_vesta_smoke.py).

**ISA suite** (`opensource_sim/isa/run_isa.sh`): builds and runs the core
RISC-V instruction tests from [`verification/isa`](../verification/isa) —
suites `rv32ui` (base integer), `rv32um` (multiply/divide), `rv32ua`
(atomics **and** the X-series extension probes), `rv32uc` (compressed), the
bit-manipulation extensions `rv32uzba`/`rv32uzbb`/`rv32uzbc`/`rv32uzbs`, and
`rv32uzf` (the Zfinx single-precision FP suite — converted rv32uf + directed FP
vectors, built `-march=rv32imc_zfinx`). The run/skip counts come from the run
summary itself (`ISA RESULTS: <npass>/<ntotal> passed (skipped: <nskip>)`) —
the suite grows with the tree, so no number is quoted here. The skips fall in
four documented families, all keyed in `run_isa.sh`'s `SKIP` table: (1) MCU /
multi-hart system-integration tests (peripheral MMIO, the HW-mutex bank,
CLINT/IRQ routing, or harts launched through the `mp_boot` ROM — none of
which exist on this one-hart, peripheral-less harness); (2) X-series
negative-control "poison" probes (encodings that MUST take the
illegal-instruction trap, verified in the repo under an external
trap-watching harness — this a0-sentinel harness has no software trap
recovery, so a trap dead-ends rather than reporting a sentinel); (3) the
privileged/trap/IRQ/debug machinery suites (`priv*`/`pmp*`/`dbg*mp` and the
F/K-series detectors — they need trap delivery, the
`TRAPCSR`/`PMP`/`UMODE`/`DEBUG` generics the TB predates, or the `hart_tile`
shared bus); and (4) the W-series MCU-peripheral exercisers plus the newer
`sh*` system tests. A NEW test failing here gets triaged into a family with
its reason — never silently dropped, and never listed without being run and
verified out-of-scope first.
The POSITIVE, result-checking arm of every bare-verifiable extension IS run and
passes. Each test is a small assembly program that self-checks and writes a
sentinel to `a0` (register x10): `0xCAFEBABE` = pass, `0xDEADBEEF` = fail (the
repo-wide `RVTEST_PASS`/`RVTEST_FAIL` convention — see
`verification/env/p/riscv_test.h`). `run_isa.sh` prints one `PASS`/`FAIL`/
`TIMEOUT`/`SKIP` line per test and finishes with
`ISA RESULTS: <npass>/<ntotal> passed (skipped: <nskip>)`.

## Manual steps

If you'd rather do it by hand (or `setup_env.sh` can't cover your distro):

**1. Install base packages**

```sh
# apt (Debian trixie / Ubuntu 24.04+ — the tested path, ghdl >= 5 here):
sudo apt-get install ghdl gcc make python3-venv curl wget xz-utils

# dnf (Fedora):
sudo dnf install ghdl gcc make python3 python3-pip curl wget xz

# zypper (openSUSE) — ghdl is frequently missing/old in default repos;
# check `ghdl --version` after this and see Troubleshooting below if so:
sudo zypper install gcc make python3 python3-venv curl wget xz
```

**2. Python venv + cocotb**

```sh
python3 -m venv opensource_sim/.venv
opensource_sim/.venv/bin/pip install 'cocotb>=2.0'
```

**3. RISC-V toolchain** (skip if `riscv-none-elf-gcc` is already on your PATH)

```sh
# x86_64; swap x64 -> arm64 on aarch64 hosts
curl -fL -o /tmp/xpack-gcc.tar.gz \
  https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v14.2.0-3/xpack-riscv-none-elf-gcc-14.2.0-3-linux-x64.tar.gz
mkdir -p opensource_sim/tools
tar -xf /tmp/xpack-gcc.tar.gz -C opensource_sim/tools
export PATH="$PWD/opensource_sim/tools/xpack-riscv-none-elf-gcc-14.2.0-3/bin:$PATH"
export RISCV_PREFIX=riscv-none-elf-
```

**4. Build ISA test images**

```sh
# The rv32ua ext-probes dispatch their ON (result-checking) arm on build-time
# -DCORE_ENABLE_<EXT> flags — they MUST match the extension generics the
# testbench enables, so pass the same set run_isa.sh uses (CORE_ENABLE_DEFS in
# isa/run_isa.sh). Overriding RISCV_GCC_OPTS replaces it, so repeat the base
# opts too. rm -rf build/ first: make keys the .elf on the .S alone, so a stale
# OFF-polarity build/ would be silently reused.
rm -rf verification/isa/build
make -C verification/isa rv32ui rv32um rv32ua rv32uc \
    rv32uzba rv32uzbb rv32uzbc rv32uzbs rv32uzf \
    RISCV_GCC_OPTS="-static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
      -DCORE_ENABLE_COMPRESSED -DCORE_ENABLE_ZICOND -DCORE_ENABLE_ZCB -DCORE_ENABLE_ZIMOP \
      -DCORE_ENABLE_ZIHINT -DCORE_ENABLE_ZICBOZ -DCORE_ENABLE_ZABHA -DCORE_ENABLE_ZACAS \
      -DCORE_ENABLE_ZCMP -DCORE_ENABLE_ZCMT -DCORE_ENABLE_ZBKB -DCORE_ENABLE_ZBKC \
      -DCORE_ENABLE_ZBKX -DCORE_ENABLE_ZKN -DCORE_ENABLE_ZFINX"
# .elf/.dump/.bin/.rcf land in verification/isa/build/<suite>/
# (In practice just run isa/run_isa.sh — it does exactly this build for you.)
```

**5. Run one test by hand** (for debugging a single failure)

`opensource_sim/isa/run_isa.sh` keeps its GHDL work library in
`opensource_sim/isa/work/` after any run, so once you've run it (or the
steps below) once, you can re-run a single test directly:

```sh
cd opensource_sim/isa
ghdl -r --std=08 -fsynopsys --workdir=work vesta_isa_tb \
    -gTEST_FILE=../../verification/isa/build/rv32ui/xxxxxxrv32ui-p-add.rcf
```

(The `.rcf` filenames carry leading `x`-padding to a fixed length — an isa
Makefile convention. Tab-complete or `ls` the build directory for exact names;
the `.elf`/`.dump` files keep the plain names.)

Exit 0 = PASS (`a0` reached `0xCAFEBABE`); nonzero = FAIL (`0xDEADBEEF`) or a
watchdog TIMEOUT. Swap the `-gTEST_FILE=` path for any other built `.rcf`.

If `opensource_sim/isa/work/` doesn't exist yet, analyze the RTL once first
(same curated dependency order `run_isa.sh` uses, kept in sync with
`sky130/synth.sh` and `sky130/sim/Makefile` — see its `SOURCES` array):

```sh
mkdir -p opensource_sim/isa/work
for f in hdl/common/constants.vhd hdl/common/MemoryMap.vhd \
         hdl/common/vesta/extend.vhd hdl/common/vesta/loadext.vhd \
         hdl/common/vesta/store_ext.vhd hdl/common/vesta/branch_valid.vhd \
         hdl/common/vesta/pulse_extender.vhd hdl/common/vesta/aludec.vhd \
         hdl/common/vesta/maindec.vhd hdl/common/vesta/div.vhd \
         hdl/common/vesta/alu.vhd hdl/common/vesta/regfile_sbirq.vhd \
         hdl/common/vesta/c_dec.vhd hdl/common/vesta/csr_unit.vhd \
         hdl/common/vesta/irq_handler.vhd \
         hdl/common/vesta/fpu_simple.vhd hdl/common/vesta/fpu.vhd \
         hdl/common/vesta/controller.vhd \
         hdl/common/vesta/datapath.vhd hdl/common/sim/ClkGate.vhd \
         hdl/common/vesta/vesta.vhd opensource_sim/isa/vesta_isa_tb.vhd; do
  ghdl -a --std=08 -fsynopsys --workdir=opensource_sim/isa/work "$f"
done
```

## Container fallback

If your distro's GHDL is missing or older than 5.x and you don't want to
change your host, run the whole flow inside `debian:trixie-slim` (ships
GHDL >= 5 in its own repos):

```sh
podman run --rm -it -v "$PWD":/work -w /work debian:trixie-slim bash -c '
  apt-get update && apt-get install -y ghdl gcc make python3-venv python3-pip curl xz-utils git &&
  ./opensource_sim/setup_env.sh && source opensource_sim/env.sh && ./opensource_sim/run_sim.sh'
```

(swap `podman` for `docker` if that's what you have — the command is
otherwise identical).

## Troubleshooting

- **GHDL missing or < 5.x**: `setup_env.sh` detects this and refuses to
  proceed rather than silently using a broken simulator. Either upgrade to a
  distro release that ships GHDL 5.x (Debian trixie / Ubuntu 24.04+), or use
  the container fallback above. Do not build GHDL from source for this flow.
- **Toolchain arch mismatch**: `setup_env.sh` only auto-downloads prebuilt
  xPack binaries for `x86_64` (`linux-x64`) and `aarch64` (`linux-arm64`).
  On any other architecture, install `riscv-none-elf-gcc` yourself and make
  sure it's on `PATH` (or point `RISCV_PREFIX` at it) before running
  `setup_env.sh` — it will detect and reuse a system toolchain.
- **`pip install cocotb` fails to build**: cocotb needs a C compiler and
  Python headers to build its simulator bridge — install `gcc` plus your
  distro's Python dev package (`python3-dev` on apt, `python3-devel` on
  dnf/zypper) and re-run `setup_env.sh`.
- **Where artifacts land**: ISA build outputs are in
  `verification/isa/build/<suite>/`; GHDL work libraries and per-test logs
  are in `opensource_sim/isa/work/`; the cocotb smoke test's GHDL work
  library is in `sky130/sim/sim_build/`.
- **Viewing the smoke-test waveform**:
  ```sh
  gtkwave sky130/sim/vesta_smoke.vcd
  ```
