#!/usr/bin/env python3
"""gen_wnpuconv_golden.py -- THROWAWAY golden-value generator for the
wnpuconv.S firmware smoke (npu_conv_design.md S6, digperiphs P4.1).

NOT part of the frozen D9 bench pipeline (gen_conv_vectors.py/conv_vectors/) --
this is a standalone helper that reuses the SAME validated npu_fixed.py
arithmetic core (mac_step/int_to_sfixed, the exact fixed_pkg_c round-half-
to-even + saturate replica) to compute the exact expected Q7.24 outputs for
the ONE case wnpuconv.S exercises on real MCU/silicon generics
(X_M=0, W_M=7, Y_M=7, N=24, RHO=2):

    K=4  Cin=2  Cout=2  Lout=4  S=1  D=1  BEN=1  AEN=0  MODE=1 (conv)
    L = (Lout-1)*S + (K-1)*D + 1 = 7

Run with /usr/bin/python3 (NEVER `python3 -c` -- this machine's default
python3 is the aoj_cal wrapper, which re-evaluates its arguments and STRIPS
QUOTES).

Prints (in order): the predicted-cycle formula check, the input/weight
tables (decimal + 32-bit two's-complement hex, ready to paste into
`li`/immediate constants in wnpuconv.S), the 8 flat expected outputs
(f*Lout+j order, decimal + hex), and a per-MAC-step rounding trace for
EVERY output that reports whether the fixed_pkg resize step actually added
+1 (a real round-up, not a bit that happened to already be exact) -- the
task's "must not be a case where rounding never actually fires" bar.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import mac_step, int_to_sfixed  # noqa: E402

X_M, W_M, Y_M, N_BITS, RHO = 0, 7, 7, 24, 2
K, CIN, COUT, LOUT, S, D, BEN, AEN = 4, 2, 2, 4, 1, 1, True, False

L = (LOUT - 1) * S + (K - 1) * D + 1
assert L == 7, "L formula mismatch"


def predicted_cycles(k, cin, cout, lout, ben):
    b = 1 if ben else 0
    return 1 + cout * lout * (5 * cin * k + 3 * b + 1) + 2


T_CYCLES = predicted_cycles(K, CIN, COUT, LOUT, BEN)
print("=== gen_wnpuconv_golden.py -- wnpuconv.S golden values (D9 arithmetic core) ===")
print("Generics: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d" % (X_M, W_M, Y_M, N_BITS, RHO))
print("Case: K=%d Cin=%d Cout=%d Lout=%d S=%d D=%d BEN=%d AEN=%d  L=%d  T=%d cycles"
      % (K, CIN, COUT, LOUT, S, D, BEN, AEN, L, T_CYCLES))

# ---------------------------------------------------------------------------
# Distinctive Q0.24 inputs / Q7.24 weights -- magnitudes ~1e5-1e6 (raw units;
# real value = raw / 2**24, so these sit around 0.006 .. 0.06 in real terms,
# well inside Q0.24's [-1,1) and Q7.24's +-128 range) so per-step rounding is
# genuinely exercised (a raw product whose low 24 discarded bits are exactly
# zero would prove nothing -- verified below).
# ---------------------------------------------------------------------------
inputs = {
    0: [200000, -350000, 725003, -140007, 999999, -50021, 615003],
    1: [-275000, 400001, -125007, 333333, -800001, 275005, -60003],
}
assert all(len(v) == L for v in inputs.values())

# filter-major weights, bias FIRST per filter (D2/D5 pinned order)
weights = {
    0: {
        'bias': 450000,
        (0, 0): 120007, (0, 1): -230011, (0, 2): 310013, (0, 3): -410017,
        (1, 0): -150029, (1, 1): 260031, (1, 2): -370037, (1, 3): 480041,
    },
    1: {
        'bias': -600013,
        (0, 0): -140051, (0, 1): 250057, (0, 2): -360061, (0, 3): 470069,
        (1, 0): 130079, (1, 1): -240083, (1, 2): 350089, (1, 3): -460097,
    },
}


def u32(raw):
    return raw & 0xFFFFFFFF


def compute_output(f, j):
    """Pinned order: bias step 0 (if BEN), then c OUTER, k INNER -- exactly
    the contiguous NPU weight-pointer walk. Returns (acc_final, steps) where
    steps is [(label, acc_before, a_raw, b_raw, acc_after), ...] for tracing."""
    acc = 0
    steps = []
    if BEN:
        bias_x = int_to_sfixed(1, X_M, N_BITS)   # the to_sfixed(1) quirk: 2**24-1
        w = weights[f]['bias']
        new_acc = mac_step(acc, bias_x, w, Y_M, N_BITS)
        steps.append(('bias', acc, bias_x, w, new_acc))
        acc = new_acc
    for c in range(CIN):
        for k in range(K):
            t = j * S + k * D
            x = inputs[c][t]
            w = weights[f][(c, k)]
            new_acc = mac_step(acc, x, w, Y_M, N_BITS)
            steps.append(((c, k), acc, x, w, new_acc))
            acc = new_acc
    return acc, steps


print("\n-- inputs (Q0.24 raw, decimal / 32-bit hex) --")
for c in range(CIN):
    for t in range(L):
        v = inputs[c][t]
        print("  in[c=%d][t=%d] = %-9d  0x%08X" % (c, t, v, u32(v)))

print("\n-- weights (Q7.24 raw, filter-major, bias first; decimal / 32-bit hex) --")
for f in range(COUT):
    v = weights[f]['bias']
    print("  w[f=%d].bias      = %-9d  0x%08X" % (f, v, u32(v)))
    for c in range(CIN):
        for k in range(K):
            v = weights[f][(c, k)]
            print("  w[f=%d][c=%d][k=%d] = %-9d  0x%08X" % (f, c, k, v, u32(v)))

flat_out = []
all_steps = []  # (f, j, label, acc_before, a, b, acc_after, floor_val, remainder, half, rounded)
for f in range(COUT):
    for j in range(LOUT):
        acc, steps = compute_output(f, j)
        flat_out.append(acc)
        for label, acc_before, a, b, acc_after in steps:
            prod = a * b
            total = (acc_before << N_BITS) + prod
            floor_val = total >> N_BITS         # arithmetic (floor) shift, matches resize_sfixed
            remainder = total - (floor_val << N_BITS)
            half = 1 << (N_BITS - 1)
            rounded = (acc_after == floor_val + 1)
            all_steps.append((f, j, label, acc_before, a, b, acc_after,
                               floor_val, remainder, half, rounded))

print("\n-- flat expected outputs (f*Lout+j order; decimal / 32-bit hex) --")
for f in range(COUT):
    for j in range(LOUT):
        idx = f * LOUT + j
        v = flat_out[idx]
        print("  out[f=%d][j=%d] (idx=%d) = %-9d  0x%08X" % (f, j, idx, v, u32(v)))

print("\n-- rounding evidence (per-MAC-step resize_sfixed trace) --")
rounding_hits = [s for s in all_steps if s[-1]]
nonzero_remainder = [s for s in all_steps if s[8] != 0]
print("  total MAC steps traced         : %d" % len(all_steps))
print("  steps with nonzero remainder    : %d" % len(nonzero_remainder))
print("  steps where resize ROUNDED (+1) : %d" % len(rounding_hits))
assert rounding_hits, "no MAC step actually rounded up -- test data is not load-bearing for rounding"
print("  first 5 steps that rounded up:")
for f, j, label, acc_before, a, b, acc_after, floor_val, remainder, half, rounded in rounding_hits[:5]:
    print("    f=%d j=%d step=%-8s acc_before=%-11d a=%-9d b=%-9d "
          "floor=%-11d remainder=%-9d half=%-9d -> acc_after=%d (rounded up)"
          % (f, j, str(label), acc_before, a, b, floor_val, remainder, half, acc_after))

print("\n-- operand survival hex (for the 'unchanged after run' negative-structure check) --")
print("  (same as the input/weight tables above -- inputs/weights are never")
print("   written by the accelerator; only OUT_ADDR is written)")

print("\nDone. flat_out (decimal) = %s" % flat_out)
print("flat_out (hex)           = %s" % ["0x%08X" % u32(v) for v in flat_out])
