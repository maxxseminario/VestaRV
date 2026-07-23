#!/usr/bin/env python3
"""gen_wactf_golden.py -- THROWAWAY golden-value generator for the wactf.S
firmware smoke (npu_actf_design.md D12, digperiphs P4.4).

NOT part of the frozen D10 bench pipeline (gen_actf_vectors.py/actf_vectors/)
-- this is a standalone helper, structured exactly like
gen_wnpuconv_golden.py/gen_wxnpu_golden.py/gen_wgemm_golden.py, that reuses
the SAME validated npu_fixed.think_layer()/activate() (never reimplements the
arithmetic) to compute the exact expected words for the wactf.S ACTF sweep,
at the real MCU/silicon generics (X_M=0, W_M=7, Y_M=7, N=24, RHO=2):

ONE staged MLP-mode (MODE=0) network layout, NI=0 (1 input) / NN=1 (2
neurons), reused across a sweep of THINKs (design-doc D12) -- only OVSAR
(and, where a group needs a different accumulator magnitude, WVSAR) is
re-pointed between THINKs so results never overwrite each other:

  Group A (shared X=0.5, W_A0=+1.0/W_A1=-1.0 -> acc0=+0.5/acc1=-0.5, both
  well inside the sigmoid/tanh linear band |acc|<2): THINK1 (ACTF=0
  sigmoid), THINK2 (ACTF=1 ReLU), THINK3 (ACTF=2 tanh), THINK6 (ACTF=5
  reserved -> must equal THINK1), THINK7 (AEN=0, ACTF=2 -> raw passthrough).

  Group B (clamp): W_B0=+3.0/W_B1=+0.25 -> acc0=+1.5 (clamps to the +rail
  0x00FFFFFF), acc1=+0.125 (in-range identity). THINK4 (ACTF=3 clamp).

  Group C (exp): W_C0=0.0/W_C1=-1.0 -> acc0=0 exactly (exp~(0)=1.0 =
  0x01000000 exactly), acc1=-0.5 (exp~(-0.5) in (0,1.0)). THINK5 (ACTF=4
  exp-approx).

Run with /usr/bin/python3 (NEVER `python3 -c` -- this machine's default
python3 is the aoj_cal wrapper, which re-evaluates its arguments and STRIPS
QUOTES).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import think_layer, activate, sigmoid, relu, tanh_approx, clamp01, exp_approx  # noqa: E402

X_M, W_M, Y_M, N_BITS, RHO = 0, 7, 7, 24, 2


def u32(raw):
    return raw & 0xFFFFFFFF


def s32(u):
    u &= 0xFFFFFFFF
    return u - (1 << 32) if u & 0x80000000 else u


NI, NN = 0, 1  # 1 input, 2 neurons

# ---------------------------------------------------------------------------
# Group A: shared linear-band pair, reused THINK1/2/3/6/7.
# ---------------------------------------------------------------------------
X_VAL = 4194304 * 2          # 0.5 in Q0.24 (X_M=0)  = 0x00800000
assert X_VAL == 0x00800000

W_A0 = 1 << N_BITS            # +1.0 in Q7.24 = 0x01000000
W_A1 = -(1 << N_BITS)         # -1.0 in Q7.24 = 0xFF000000
w_listA = [W_A0, W_A1]

# ---------------------------------------------------------------------------
# Group B: clamp pair (one >= +1.0, one in-range).
# ---------------------------------------------------------------------------
W_B0 = 3 << N_BITS             # +3.0 in Q7.24 = 0x03000000  -> acc = 1.5
W_B1 = (1 << N_BITS) // 4       # +0.25 in Q7.24 = 0x00400000 -> acc = 0.125
w_listB = [W_B0, W_B1]

# ---------------------------------------------------------------------------
# Group C: exp pair (acc=0 exactly, and a negative acc).
# ---------------------------------------------------------------------------
W_C0 = 0                       # 0.0  -> acc = 0 exactly
W_C1 = -(1 << N_BITS)          # -1.0 -> acc = -0.5 (same as group A neuron1)
w_listC = [W_C0, W_C1]

print("=== gen_wactf_golden.py -- wactf.S golden values (D9/D12 arithmetic core) ===")
print("Generics: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d  NI=%d NN=%d"
      % (X_M, W_M, Y_M, N_BITS, RHO, NI, NN))
print("X (shared, Q0.24) = %d  0x%08X" % (X_VAL, u32(X_VAL)))
print("Group A: W_A0=%d(0x%08X) W_A1=%d(0x%08X)"
      % (W_A0, u32(W_A0), W_A1, u32(W_A1)))
print("Group B: W_B0=%d(0x%08X) W_B1=%d(0x%08X)"
      % (W_B0, u32(W_B0), W_B1, u32(W_B1)))
print("Group C: W_C0=%d(0x%08X) W_C1=%d(0x%08X)"
      % (W_C0, u32(W_C0), W_C1, u32(W_C1)))


def run_group(name, w_list, aen, actf, trace_label):
    trace = []
    outs, _ = think_layer([X_VAL], w_list, ni=NI, nn=NN, ben=0, aen=aen,
                           x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO,
                           w_offset=0, trace=trace, actf=actf)
    print("\n-- %s (aen=%d actf=%d) --" % (name, aen, actf))
    for idx, acc in enumerate(trace):
        print("  %s acc[%d] = %-12d (%.6f)" % (trace_label, idx, acc,
                                                 acc / float(1 << N_BITS)))
    for idx, v in enumerate(outs):
        print("  %s out[%d]  = %-12d  0x%08X" % (trace_label, idx, v, u32(v)))
    return outs, trace


# THINK1: Group A, AEN=1, ACTF=0 (sigmoid legacy)
t1_out, t1_acc = run_group("THINK1 sigmoid (ACTF=0)", w_listA, 1, 0, "T1")

# THINK2: Group A, AEN=1, ACTF=1 (ReLU)
t2_out, t2_acc = run_group("THINK2 ReLU (ACTF=1)", w_listA, 1, 1, "T2")

# THINK3: Group A, AEN=1, ACTF=2 (tanh)
t3_out, t3_acc = run_group("THINK3 tanh (ACTF=2)", w_listA, 1, 2, "T3")

# THINK4: Group B, AEN=1, ACTF=3 (clamp)
t4_out, t4_acc = run_group("THINK4 clamp (ACTF=3)", w_listB, 1, 3, "T4")

# THINK5: Group C, AEN=1, ACTF=4 (exp-approx)
t5_out, t5_acc = run_group("THINK5 exp (ACTF=4)", w_listC, 1, 4, "T5")

# THINK6: Group A, AEN=1, ACTF=5 (reserved -> must equal THINK1)
t6_out, t6_acc = run_group("THINK6 reserved (ACTF=5)", w_listA, 1, 5, "T6")

# THINK7: Group A, AEN=0, ACTF=2 (master-enable proof: raw passthrough)
t7_out, t7_acc = run_group("THINK7 AEN=0 passthrough (ACTF=2)", w_listA, 0, 2, "T7")

# ---------------------------------------------------------------------------
# Self-checks (D9 generator discipline: prove the vectors actually bite).
# ---------------------------------------------------------------------------
print("\n-- self-checks --")

# THINK1 sanity: both accs deep in-range, mixed sign.
assert t1_acc[0] > 0 and t1_acc[1] < 0, "THINK1 accs are not mixed sign"
assert abs(t1_acc[0]) < (2 << N_BITS) and abs(t1_acc[1]) < (2 << N_BITS), \
    "THINK1 accs are not |acc|<2"
# THINK1 must equal a direct sigmoid() call (compat anchor).
assert t1_out[0] == sigmoid(t1_acc[0], Y_M, N_BITS, RHO)
assert t1_out[1] == sigmoid(t1_acc[1], Y_M, N_BITS, RHO)
print("  THINK1 PASS: mixed-sign in-range accs, outputs == direct sigmoid()")

# THINK2 ReLU: positive passes through raw, negative -> exactly 0.
assert t2_out[0] == t2_acc[0] and t2_acc[0] > 0, "THINK2 positive ReLU mismatch"
assert t2_out[1] == 0, "THINK2 negative ReLU must be exactly 0"
assert t2_out[1] != t1_out[1], "ReLU(neg) must differ from sigmoid(neg)"
print("  THINK2 PASS: relu(+)=passthrough=%d, relu(-)=0 (!= sigmoid(-)=%d)"
      % (t2_out[0], t1_out[1]))

# THINK3 tanh: negative acc must give a SIGNED (negative) 32-bit word; tanh(0
# would be 0, but here neither acc is 0) exact via tanh_approx().
assert t3_out[0] == tanh_approx(t3_acc[0], Y_M, N_BITS, RHO)
assert t3_out[1] == tanh_approx(t3_acc[1], Y_M, N_BITS, RHO)
assert t3_out[1] < 0, "THINK3 negative-acc tanh word must be negative (GA3)"
assert s32(u32(t3_out[1])) < 0, "THINK3 negative tanh word must sign-extend to negative in 32 bits"
assert t3_out[0] > 0, "THINK3 positive-acc tanh word must be positive"
print("  THINK3 PASS: tanh(+)=%d (0x%08X), tanh(-)=%d (0x%08X, signed-negative)"
      % (t3_out[0], u32(t3_out[0]), t3_out[1], u32(t3_out[1])))

# THINK4 clamp: acc0 (1.5) must clamp to the +rail 0x00FFFFFF; acc1 (0.125,
# in-range) must be the identity (== the raw acc, no clamp).
assert t4_acc[0] == 1.5 * (1 << N_BITS), "THINK4 acc0 is not exactly 1.5"
assert u32(t4_out[0]) == 0x00FFFFFF, "THINK4 acc0 did not clamp to the +rail"
assert t4_out[0] != t4_acc[0], "clamp must actually clamp (differ from raw acc)"
assert t4_out[1] == t4_acc[1], "THINK4 acc1 in-range must be identity"
assert t4_out[1] == clamp01(t4_acc[1], N_BITS)
print("  THINK4 PASS: clamp(1.5)=0x%08X (rail, != raw 0x%08X), clamp(0.125)=0x%08X (identity)"
      % (u32(t4_out[0]), u32(t4_acc[0]), u32(t4_out[1])))

# THINK5 exp: acc0 == 0 exactly -> exp~(0) == 1<<24 == 0x01000000 exactly;
# acc1 < 0 -> word strictly in (0, 1<<24).
assert t5_acc[0] == 0, "THINK5 acc0 is not exactly 0"
assert t5_out[0] == (1 << N_BITS) == 0x01000000, "exp~(0) must be exactly 1.0 (0x01000000)"
assert t5_out[0] == exp_approx(0, Y_M, N_BITS, RHO)
assert t5_acc[1] < 0
assert 0 < t5_out[1] < (1 << N_BITS), "THINK5 negative-acc exp word must be in (0, 1.0)"
print("  THINK5 PASS: exp(0)=0x%08X (exactly 1.0), exp(-0.5)=0x%08X (in (0,1.0))"
      % (u32(t5_out[0]), u32(t5_out[1])))

# THINK6 reserved (ACTF=5): must be BIT-IDENTICAL to THINK1's sigmoid words.
assert t6_out == t1_out, "reserved ACTF=5 must equal the sigmoid (ACTF=0) golden (D6)"
print("  THINK6 PASS: reserved ACTF=5 words == THINK1 sigmoid words exactly")

# THINK7 (AEN=0): raw passthrough regardless of ACTF -- must equal the raw
# Group-A accumulators (full Q7.24, unactivated), and must differ from
# THINK3's tanh outputs (same ACTF field, AEN gates it off).
assert t7_out == t1_acc == t2_acc == t3_acc, "THINK7 passthrough must equal the raw Group-A accs"
assert t7_out != t3_out, "AEN=0 must NOT apply ACTF=2 (master-enable proof)"
print("  THINK7 PASS: AEN=0 passthrough == raw acc (0x%08X, 0x%08X), != tanh output (D1 master enable)"
      % (u32(t7_out[0]), u32(t7_out[1])))

print("\n=== Done -- all self-checks PASS ===")


def emit(label, outs):
    print("%s (decimal) = %s" % (label, outs))
    print("%s (hex)     = %s" % (label, ["0x%08X" % u32(v) for v in outs]))


emit("t1_out", t1_out)
emit("t2_out", t2_out)
emit("t3_out", t3_out)
emit("t4_out", t4_out)
emit("t5_out", t5_out)
emit("t6_out", t6_out)
emit("t7_out", t7_out)
