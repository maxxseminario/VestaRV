# lab11_npu -- REFERENCE SOLUTION

**PRIVATE -- do not commit.** Moves to the course's private repo before any
vestarv commit. Only `../skeleton/` ships publicly.

Build/run: `make sim` (instructor). Expected: `run_sim: PASS (a0=0xCAFEBABE)`.

The NPU (module M11, TRM ch. 16), hart-0 only. A fixed-point multiply-accumulate:
stage a 2-element input vector (`X = Q0.24`) + weight vector (`W = Q7.24`) into
the NPU staging RAM at `0xC000`, point `IVSAR/WVSAR/OVSAR` (WORD indices) at them,
run a THINK (`NPUCR = THINK | NI(2) | NN(1)`), poll `NPUCR` bit 16 back to 0, read
the output and check against a host-precomputed constant:

```
X0=0.5  W0=2.0   X1=0.25  W1=3.0
OUT = 0.5*2.0 + 0.25*3.0 = 1.75 = 0x01C00000
```

Student implements `npu_configure` + `npu_think`. Skeleton stubs them (NPU never
started -> output stays 0) -> FAILS (`OUT=0x0`). No shared course-band words; all
expected values are compile-time constants (no `/` or `%` on variables, per the
divider erratum). Never touch `0xC000-0xFFFF` while THINK may be active. ~9 s wall.
