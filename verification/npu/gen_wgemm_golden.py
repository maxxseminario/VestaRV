#!/usr/bin/env python3
"""gen_wgemm_golden.py -- THROWAWAY golden-value generator for the wgemm.S
firmware smoke (npu_gemm_design.md S5, digperiphs P4.3).

NOT part of the frozen D10 bench pipeline (gen_gemm_vectors.py/gemm_vectors/)
-- this is a standalone helper, structured exactly like
gen_wnpuconv_golden.py/gen_wxnpu_golden.py, that reuses the SAME validated
npu_fixed.think_layer() (never reimplements the arithmetic) to compute the
exact expected words for the TWO-LAYER CHAINED GEMM case wgemm.S exercises,
at the real MCU/silicon generics (X_M=0, W_M=7, Y_M=7, N=24, RHO=2):

  Layer 1 (chaining source, design-doc ADJUDICATION ADDENDUM A2):
    M1=2  K1=3  N1=4  BEN=0  AEN=1 (sigmoid, ACTF=0)  MODE=3 (gemm)
    A1 row-major (Q0.24), B1 column-major (Q7.24) -> C1 (Q0.24, sigmoid out)

  Layer 2 (chained: A2 = C1 IN PLACE, zero repack -- IVSAR2 = OVSAR1):
    M2=2  K2=4(=N1)  N2=2  BEN=0  AEN=0  MODE=3 (gemm)
    B2 column-major (Q7.24) at its own WVSAR2 -> C2 (Q7.24)

Chaining legality (A2, D2 point 4): C1's raw words must satisfy the Q0.24
"|C|<1" contract (A is the 25-bit Q0.24 SramQ_in slice) -- checked below
before printing anything. Since FPSigmoid's outputs are always in [0,1)
(a sigmoid approximation, never negative), this is true by construction
whenever AEN=1 on the chaining layer; asserted anyway as a harness check.

Run with /usr/bin/python3 (NEVER `python3 -c` -- this machine's default
python3 is the aoj_cal wrapper, which re-evaluates its arguments and STRIPS
QUOTES).

Prints (in order): the predicted-cycle formula check for both layers, the
A1/B1/B2 stimulus tables (decimal + 32-bit two's-complement hex, ready to
paste into `li`/immediate constants in wgemm.S), the layer-1 pre-activation
accumulator trace (proving the |acc|<4 sigmoid-active-band + mixed-sign
self-check), the 8 C1 words (Q0.24 sigmoid output) and the 4 C2 words
(Q7.24), and the chained-A2-legality self-check.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import think_layer  # noqa: E402

X_M, W_M, Y_M, N_BITS, RHO = 0, 7, 7, 24, 2

# ---------------------------------------------------------------------------
# Layer 1: chaining source. MUST run AEN=1 (design-doc addendum A2: chaining
# C->A needs |C|<1; the sigmoid's zero-extended Q0.24 output words chain
# exactly, the passthrough Q7.24 form only chains when |C|<1 by construction).
# ---------------------------------------------------------------------------
M1, K1, N1, AEN1 = 2, 3, 4, True

# A1 row-major (Q0.24 raw); real values ~0.005-0.013 (well inside [-1,1))
A1 = [
    [150000, -220000, 90000],
    [-130000, 180000, -70000],
]

# B1[k][n], K1=3 rows x N1=4 cols (Q7.24 raw; real values ~0.014-0.024)
B1mat = [
    [400000, -350000, 300000, -260000],
    [-330000, 310000, -280000, 240000],
    [290000, -270000, 250000, -230000],
]
w_list1 = [B1mat[k][n] for n in range(N1) for k in range(K1)]  # column-major (D10)

# ---------------------------------------------------------------------------
# Layer 2: chained (A2 = C1 in place, zero repack). K2 MUST equal N1.
# ---------------------------------------------------------------------------
M2, K2, N2, AEN2 = 2, 4, 2, False
assert K2 == N1, "chaining shape contract: K2 must equal N1 (A2 = C1 in place)"

# B2[k][n], K2=4 rows x N2=2 cols (Q7.24 raw; real values ~0.017-0.03)
B2mat = [
    [500000, -450000],
    [-420000, 380000],
    [360000, -340000],
    [-310000, 290000],
]
w_list2 = [B2mat[k][n] for n in range(N2) for k in range(K2)]  # column-major (D10)


def u32(raw):
    return raw & 0xFFFFFFFF


def predicted_cycles(m, k, n):
    return 1 + m * n * (5 * k + 1) + 2


T1 = predicted_cycles(M1, K1, N1)
T2 = predicted_cycles(M2, K2, N2)
assert T1 == 131, "layer1 cycle formula mismatch (expected 131, got %d)" % T1
assert T2 == 87, "layer2 cycle formula mismatch (expected 87, got %d)" % T2

print("=== gen_wgemm_golden.py -- wgemm.S golden values (D10 arithmetic core) ===")
print("Generics: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d" % (X_M, W_M, Y_M, N_BITS, RHO))
print("Layer1: M=%d K=%d N=%d BEN=0 AEN=%d MODE=gemm  T=%d cycles"
      % (M1, K1, N1, int(AEN1), T1))
print("Layer2: M=%d K=%d N=%d BEN=0 AEN=%d MODE=gemm  T=%d cycles (chained A2=C1)"
      % (M2, K2, N2, int(AEN2), T2))

# ---------------------------------------------------------------------------
# Operand legality (npu_gemm_design.md binding inputs)
# ---------------------------------------------------------------------------
for row in A1:
    for a in row:
        assert -(1 << 24) <= a < (1 << 24), "A1 value %d out of Q0.24 legal range" % a
for b in w_list1:
    assert -(1 << 31) <= b < (1 << 31), "B1 value %d out of Q7.24 legal range" % b
for b in w_list2:
    assert -(1 << 31) <= b < (1 << 31), "B2 value %d out of Q7.24 legal range" % b

print("\n-- A1 (Q0.24 raw, row-major; decimal / 32-bit hex) --")
for m in range(M1):
    for k in range(K1):
        v = A1[m][k]
        print("  A1[m=%d][k=%d] = %-9d  0x%08X" % (m, k, v, u32(v)))

print("\n-- B1 (Q7.24 raw, column-major w_list[n*K1+k]=B1[k][n]; decimal / 32-bit hex) --")
for n in range(N1):
    for k in range(K1):
        v = B1mat[k][n]
        print("  B1[k=%d][n=%d] (w_list[%2d]) = %-9d  0x%08X" % (k, n, n * K1 + k, v, u32(v)))

print("\n-- B2 (Q7.24 raw, column-major w_list[n*K2+k]=B2[k][n]; decimal / 32-bit hex) --")
for n in range(N2):
    for k in range(K2):
        v = B2mat[k][n]
        print("  B2[k=%d][n=%d] (w_list[%2d]) = %-9d  0x%08X" % (k, n, n * K2 + k, v, u32(v)))

# ---------------------------------------------------------------------------
# Layer 1: run think_layer per row (D10's exact idiom), tracing the
# pre-activation accumulator to prove the sigmoid-active-band self-check.
# ---------------------------------------------------------------------------
C1 = []
traces1 = []
for m in range(M1):
    trace = []
    out_m, _ = think_layer(A1[m], w_list1, ni=K1 - 1, nn=N1 - 1, ben=0, aen=1,
                            x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO,
                            w_offset=0, trace=trace)
    C1.append(out_m)
    traces1.extend(trace)

band = 4 << N_BITS
print("\n-- layer1 pre-activation accumulator trace (sigmoid active band |acc|<4) --")
for idx, acc in enumerate(traces1):
    m, n = idx // N1, idx % N1
    print("  acc[m=%d][n=%d] = %-12d (%.6f)" % (m, n, acc, acc / float(1 << N_BITS)))
for acc in traces1:
    assert -band < acc < band, \
        "layer1: pre-activation acc %d falls outside the sigmoid active band |acc|<4" % acc
assert any(a > 0 for a in traces1) and any(a < 0 for a in traces1), \
    "layer1: pre-activation accs are not a mix of positive and negative"
print("  self-check PASS: all %d pre-activation accs within |acc|<4, mixed sign"
      % len(traces1))

flat_C1 = [C1[m][n] for m in range(M1) for n in range(N1)]
print("\n-- C1 (Q0.24 sigmoid output, row-major m*N1+n; decimal / 32-bit hex) --")
for m in range(M1):
    for n in range(N1):
        idx = m * N1 + n
        v = flat_C1[idx]
        print("  C1[m=%d][n=%d] (idx=%d) = %-9d  0x%08X" % (m, n, idx, v, u32(v)))

# ---------------------------------------------------------------------------
# Chained-A2-legality self-check (design-doc D2 zero-repack claim; A2 raw
# words are the 25-bit Q0.24 SramQ_in slice legal range).
# ---------------------------------------------------------------------------
for v in flat_C1:
    assert -(1 << 24) <= v < (1 << 24), \
        "C1 value %d is out of the Q0.24 |C|<1 chaining-legal range" % v
print("\n  chaining self-check PASS: all %d C1 words satisfy the Q0.24 |C|<1 "
      "A-chaining contract (D2 point 4)" % len(flat_C1))

# ---------------------------------------------------------------------------
# Layer 2: A2 = C1 IN PLACE (zero repack), one think_layer call per row.
# ---------------------------------------------------------------------------
A2 = [flat_C1[m * K2:(m + 1) * K2] for m in range(M2)]
assert M2 * K2 == len(flat_C1), "chaining shape mismatch: M2*K2 != M1*N1"

C2 = []
for m in range(M2):
    out_m, _ = think_layer(A2[m], w_list2, ni=K2 - 1, nn=N2 - 1, ben=0, aen=0,
                            x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO,
                            w_offset=0)
    C2.append(out_m)
flat_C2 = [C2[m][n] for m in range(M2) for n in range(N2)]

print("\n-- C2 (Q7.24 passthrough output, row-major m*N2+n; decimal / 32-bit hex) --")
for m in range(M2):
    for n in range(N2):
        idx = m * N2 + n
        v = flat_C2[idx]
        print("  C2[m=%d][n=%d] (idx=%d) = %-9d  0x%08X" % (m, n, idx, v, u32(v)))

# ---------------------------------------------------------------------------
# D14 sanity: an M=1 subsumption check on layer 2 row 0 (harness check
# against refactors, same idiom as gen_gemm_vectors.py's test (a)).
# ---------------------------------------------------------------------------
out_single, _ = think_layer(A2[0], w_list2, ni=K2 - 1, nn=N2 - 1, ben=0, aen=0,
                             x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO,
                             w_offset=0)
assert out_single == C2[0], "layer2 row0 M=1 subsumption sanity FAILED"
print("\n  D14 sanity PASS: layer2 row0 == a lone think_layer() call")

print("\n=== Done ===")
print("flat_C1 (decimal) = %s" % flat_C1)
print("flat_C1 (hex)     = %s" % ["0x%08X" % u32(v) for v in flat_C1])
print("flat_C2 (decimal) = %s" % flat_C2)
print("flat_C2 (hex)     = %s" % ["0x%08X" % u32(v) for v in flat_C2])
