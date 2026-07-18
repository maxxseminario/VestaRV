# .divcheck — divider register-aliasing regression

**Expected result: PASS.** A **FAIL here means the divider register-aliasing bug
has regressed** — treat it as a hard stop, not a flaky test.

## What it guards

`src/main.c` issues the four RV32M divide/remainder forms whose destination
register aliases a source operand:

| case               | instruction              | correct result |
|--------------------|--------------------------|----------------|
| `rd == rs1`        | `divu a, a, gd`          | `100/10 = 10`  |
| `rd == rs2`        | `divu b, ga, b`          | `100/10 = 10`  |
| `rd == rs1` (rem)  | `remu c, c, gd`          | `100%10 = 0`   |
| `rd == rs1 == rs2` | `divu d, d, d`           | `x/x   = 1`    |

It calls `pass()` only when all four are correct (`10, 10, 0, 1`); otherwise
`fail()`.

## The bug this pins down

This was a real core defect found in **2026-07** by the ECEN 4xx course program
(the SDK builds at `-O2`, which normally lowers constant division to
multiply-shift and hid the divider; the `divcheck` inline-asm forces the real
`divu`/`remu`). Root cause: a **phantom register writeback that fired before the
divider latched its operands**, so with `rd == rs1`/`rd == rs2`/`rd == rs1 == rs2`
the divide computed on the already-overwritten operand and returned garbage
(`rd==rs1 → 0`, `rd==rs2 → 0xFFFFFFFF`).

It was **fixed and regression-proven pre-tapeout** in `hdl/common/vesta`
(`vesta.vhd` / `div.vhd`), before any silicon. This program keeps it green.

## Run it

```bash
cd software/course/.divcheck
make                                   # builds bin/ + rcf/xxxxxxxxxxdivcheck.rcf
../sdk/run_sim.sh rcf/xxxxxxxxxxdivcheck.rcf
```

Healthy run finishes in ~10 s and prints:

```
rd==rs1 divu:10  rd==rs2 divu:10  rd==rs1 remu:0  self:1
run_sim: PASS (a0=0xCAFEBABE)
```
