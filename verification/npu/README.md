# verification/npu — NPU golden-model Python library (P4.1/P4.2)

Pure-Python, integer-only, bit-exact golden model of the VestaRV NPU's
fixed-point datapath (`hdl/common/periph/NPU.vhd` + `hdl/common/commune/
FPMac.vhd` + `hdl/common/commune/FPSigmoid.vhd`), replicating exactly the
David Bishop `fixed_pkg` compatibility fork actually compiled into this repo
(`hdl/common/commune/fixed_pkg_c.vhdl`). No floats anywhere in the
arithmetic path; every intermediate is an exact Python integer at a known
fixed-point scale, rounded/saturated only at the exact points the RTL does.

Python 3.6+ compatible (no walrus, no 3.7+ stdlib). **This machine's default
`python3` is a Calibre wrapper that re-evaluates and strips quotes from
`python3 -c "..."` — never use `-c`; run these as script files.** Prefer
`/usr/bin/python3` (plain CPython 3.6.12) if `python3 script.py` ever
misbehaves.

## Building and testing with Bazel

Bazel runs this library's gates hermetically, against its own pinned Python, so
none of the `python3`-wrapper caveats above apply inside the sandbox. Every
command is run from the repo root.

One-time bootstrap:

```sh
sh tools/get_bazel.sh            # fetches bazelisk into tools/bin/bazel
tools/bin/bazel test //...       # first run downloads all toolchains
```

`tools/bin/bazel test //verification/npu/...` runs all nine tests of this
package:

| Target | Verb | What it proves |
|---|---|---|
| `//verification/npu:validate_mlp_test` | test | `npu_fixed` reproduces the chip-config MLP golden set (`verification/isa/tests/periph/NPU_data`) bit-exactly, 201/201 |
| `//verification/npu:regen_actf_vectors_test` | test | the tracked `actf_vectors/` files are exactly what `gen_actf_vectors.py` produces today; regeneration happens in a scratch tree, never over the tracked copies |
| `//verification/npu:regen_conv_vectors_test` | test | the same for `conv_vectors/` |
| `//verification/npu:regen_gemm_vectors_test` | test | the same for `gemm_vectors/` |
| `//verification/npu:regen_xnor_vectors_test` | test | the same for `xnor_vectors/` |
| `//verification/npu:gen_wactf_golden_test` | test | the `wactf` firmware-smoke golden generator's own self-checks agree with `npu_fixed` |
| `//verification/npu:gen_wgemm_golden_test` | test | the same for `wgemm` |
| `//verification/npu:gen_wnpuconv_golden_test` | test | the same for `wnpuconv` |
| `//verification/npu:gen_wxnpu_golden_test` | test | the same for `wxnpu`, through the shared XNOR encoders |
| `//verification/npu:validate_mlp` | build | the validation runner as a hermetic binary; `bazel run` it with an absolute `--data-dir` when you want the mismatch trace |

The library targets themselves are `//verification/npu:npu_fixed` (the
fixed-point arithmetic) and `//verification/npu:xnor_gen_lib` (the XNOR
encoders), with `//verification/npu:generator_srcs` staging the generator
sources for the regeneration tests.

The full target map is in [`BAZEL.md`](../../BAZEL.md).

## Files

- **`npu_fixed.py`** — the arithmetic library. Key functions:
  - `resize_sfixed(raw_in, n_in, m_out, n_out, round_style, overflow_style)`
    — bit-exact `fixed_pkg` `resize` for sfixed (round-half-to-even,
    saturate-on-overflow by default).
  - `int_to_sfixed(value, m, n, overflow_style)` — bit-exact `fixed_pkg`
    `to_sfixed(INTEGER, left_index, right_index)`, including its
    saturating-integer-constant quirk (see docstring — `to_sfixed(1, 0,
    -N)` does NOT give an exact 1.0).
  - `mac_step(acc_raw, a_raw, b_raw, acc_m, n_bits)` — one `FPMac.vhd`
    step: exact multiply, exact add, one round+saturate resize.
  - `sigmoid(x_raw, x_m, n_bits, rho)` — `FPSigmoid.vhd`'s piecewise
    quadratic approximation, replicated stage-by-stage.
  - `think_layer(x_list, w_list, ni, nn, ben, aen, x_m, w_m, y_m, n_bits,
    rho, w_offset, trace)` — one NPU THINK over one fully-connected layer,
    matching the FSM's bias-first, contiguous-weight-walk order.

- **`validate_mlp.py`** — validation runner. Reproduces the 2-layer MLP
  (`y = 2x^2 + 1` fit, 5-neuron hidden layer + sigmoid, 1 linear output;
  201 points, `x in [-1, 1]`) from `hdl/common/tb/NPU_tb.vhd` and checks it
  bit-exactly against the golden files. Validates **both** fixed-point
  configurations found in this repo for this same network (see script
  docstring for how each was identified):
  - `bench` (X_M=0, W_M=3, Y_M=3, N=15, RHO=2) — `NPU_tb.vhd`'s own generic
    defaults; golden files under `xcelium/NPU/{behavioral,genus}` and
    `xcelium/periph_test/behavioral`.
  - `chip` (X_M=0, W_M=7, Y_M=7, N=24, RHO=2) — the MCU_MP chip
    instantiation's generics (`hdl/common/MCU.vhd`); golden files under
    `verification/isa/tests/periph/NPU_data`.

  Run with no arguments to validate every known golden-file directory:
  ```
  cd ~/vestarv/verification/npu
  /usr/bin/python3 validate_mlp.py
  ```
  Or target one directory/config explicitly:
  ```
  /usr/bin/python3 validate_mlp.py --data-dir ~/vestarv/xcelium/NPU/behavioral --config bench
  /usr/bin/python3 validate_mlp.py --data-dir ~/vestarv/verification/isa/tests/periph/NPU_data --config chip
  ```
  Prints `N_match / N_total` and, for any mismatch, a full hex/float trace
  (per-neuron layer-1 pre-sigmoid accumulator + post-sigmoid output, layer-2
  pre-output accumulator, model vs. expected) for the first 5 mismatches.
  Exit code 0 iff 100% bit-exact.

- **`gen_conv_vectors.py`** — **PENDING-DESIGN-DOC.** A software-only 1D
  convolution reference generator built on the same `mac_step`/`sigmoid`
  primitives, using the adjudicator-pinned accumulation order (bias first,
  then channel-outer/kernel-inner MAC walk). There is no conv datapath in
  `NPU.vhd` yet and no frozen staging-RAM layout or output file format —
  this only exists so a future RTL implementation has a known-good
  reference to check against. See its module docstring before using it for
  anything beyond scratch experimentation. Example:
  ```
  /usr/bin/python3 gen_conv_vectors.py --cin 2 --l 16 --k 3 --cout 4 \
      --s 1 --d 1 --ben 1 --aen 1 --seed 1 --out /tmp/conv_vectors.hex
  ```

- **`gen_xnor_vectors.py`** — **PENDING-DESIGN-DOC (file format only).** Golden-vector
  generator for the NPU XNOR/popcount binary mode (digperiphs P4.2,
  `~/work/chip_docs/castalia/digperiphs/npu_family_spec.md` D6/D9/D17). Unlike
  the conv generator, this is a **new, standalone datapath** — no MAC, no
  sigmoid, no dependency on `npu_fixed.py` — implementing exactly the frozen
  bit-level contract:
  ```
  value_n = 2*popcount(XNOR(a, w_n)) - K     (LSB-first packing, tail-masked)
  fires iff value_n >= THRESH                (Q7.24 +-1.0 output word)
  ```
  The library entry point is `xnor_layer(a_words, w_words_per_neuron, K,
  THRESH)`. Three self-tests run automatically at script start (assertions,
  not opt-in): **(1)** tail-mask invariance — independent garbage fills in
  the unused tail bits of both `a` and every neuron's `w` (K=40 and K=33)
  produce identical outputs; **(2)** value/K parity holds across random
  cases; **(3)** a documentation-grade demo that `popcount(XNOR(a,w))` is
  invariant under a uniform bit-reversal of *both* operands at full-word K
  — proving why dense full-word vectors alone cannot catch a packing/bit-
  order bug (family-spec D6's test-pattern correction) and that the real
  discriminator is the partial-last-word tail-mask test.

  Emits `npu_xnor_<case>_{cfg,in,w,exp}.txt` into `xnor_vectors/` — cases:
  `base`, `tail40` (+ companion `tail40_tailalt`, byte-identical `exp`,
  different tail garbage), `tail33` (single-bit tail mask), `tie` /
  `tie_offlattice` (on-/off-lattice threshold boundaries), `extremes_k1` /
  `extremes_k4096` / `extremes_n256` (K and N scope bounds, staging-RAM
  footprint checked), `neuronorder` (neuron-major addressing-bug detector,
  incl. an explicit pairwise weight-swap self-check).

  **PROVISIONAL cfg-file header** (awaits the design doc): `npu_xnor_<case>_cfg.txt`
  holds 6 scalars, one per line, in the order named by the `CFG_FIELDS` list
  at the top of the script — `K N THRESH IVSAR WVSAR OVSAR`. Renaming or
  reordering the header is a one-line change to that list; nothing else in
  the file depends on the order. Data files (`in`/`w`/`exp`) are plain
  signed-decimal-int-per-line, matching the conv generator's idiom exactly
  (no comment lines).
  ```
  cd ~/vestarv/verification/npu
  /usr/bin/python3 gen_xnor_vectors.py
  ```

## Validation result (current)

```
$ /usr/bin/python3 validate_mlp.py
... (4 golden-file directories, 201 points each)
RESULT: 100% bit-exact (201/201).   [x4, all directories/configs]
```

## Rounding rule determination (cited)

`hdl/common/commune/fixed_pkg_c.vhdl`:
- Line 28: `constant fixed_round_style : fixed_round_style_type := fixed_round;`
- Line 30: `constant fixed_overflow_style : fixed_overflow_style_type := fixed_saturate;`
- Lines 5603-5697: `resize` (sfixed overload) — structural integer-bit
  overflow check happens first (saturates and skips rounding entirely if
  it fires); otherwise slices to the target width and, if fraction bits
  are being dropped, calls `round_fixed`.
- Lines 2272-2308: `round_fixed` (sfixed overload) — the actual tie rule:
  rounds up iff the discarded-bits remainder's MSB is '1' AND (any lower
  discarded bit is '1' OR the kept LSB is '1'). A bare tie (remainder ==
  exactly half, kept LSB == 0) does **not** round up. This is
  **round-half-to-even (banker's rounding)**, not round-half-up. Overflow
  from the round-up itself (`round_up`, lines 2222-2235) saturates a
  second time if it flips the sign bit.
- Lines 5139-5149: `saturate` — positive extreme = all-ones with the sign
  bit forced to 0 (`0111...1`); negative extreme = its bitwise NOT
  (`1000...0`).
- Lines 4744-4797: `to_sfixed(INTEGER, left_index, right_index)` — used for
  the NPU's bias tap (`to_sfixed(1, X_M_BITS, -N_BITS)`) and two of
  `FPSigmoid.vhd`'s literal constants; replicated in `int_to_sfixed`,
  including the saturating-overflow branch for integer constants that
  don't fit the target's *integer* bit width (e.g. `to_sfixed(1, 0, -N)`
  saturates to `2^N - 1`, not an exact `2^N`).

## Open questions / notes for the senior adjudicator

- **Repo inconsistency found (not introduced by this work):**
  `verification/isa/tests/periph/NPU.S`'s `get_y_loop` comment says "Mask
  for 19 bits (3 integer + 15 fractional + 1 sign)" and applies `0x7FFFF` —
  that is the *bench* config's width (M=3, N=15 → 19 bits total), but the
  golden data it actually reads (`NPU_data/npu0_yhat.s`) is generated at
  the *chip* config (M=7, N=24 → 32 bits, i.e. the mask should be a no-op).
  This validator confirms the `chip`-config golden files are internally
  bit-exact against `npu_fixed.py`, independent of that RTL-test-side
  masking question — flagging it here since it's a live discrepancy in
  `NPU.S`, not something this task was scoped to fix.
- `gen_conv_vectors.py`'s memory-layout/output-format choices are all
  provisional (see its docstring) pending the design doc; nothing there
  should be treated as a frozen contract.
- The library is written generically over (X_M, W_M, Y_M, N, RHO) — it
  does not hardcode either the `bench` or `chip` widths — so it should
  drop in cleanly once a real design doc pins additional configs (e.g. a
  conv-specific instantiation).
