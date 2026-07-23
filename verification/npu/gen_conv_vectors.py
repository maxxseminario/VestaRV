#!/usr/bin/env python3
"""gen_conv_vectors.py -- FROZEN golden-vector generator for the NPU CONV1D
mode (npu_conv_design.md D9), built entirely on npu_fixed.py's validated,
bit-exact MAC/sigmoid model. Emits one case per design-doc GROUP into
conv_vectors/, at the FROZEN MCU/chip generics:

    X_M=0  W_M=7  Y_M=7  N=24  RHO=2      (Q0.24 in, Q7.24 weight/acc/out)

Golden-file interface (D9, FROZEN -- do not change without a doc amendment):
    npu_conv_<case>_cfg.txt  -- 12 scalars, one per line, in order:
                                K Cin Cout Lout S D BEN AEN ACTF IVSAR WVSAR OVSAR
    npu_conv_<case>_in.txt   -- Cin*L lines, channel-major: in[c][t] at line c*L+t
    npu_conv_<case>_w.txt    -- Cout*(Cin*K+BEN) lines, filter-major,
                                bias-first-per-filter when BEN
    npu_conv_<case>_exp.txt  -- Cout*Lout lines, flat f*Lout+j order
    All data values are raw fixed-point words reinterpreted as signed
    (Python ints straight out of npu_fixed.py -- never re-derived here).

L (the physical per-channel input length) is NOT stored in the cfg file (D9's
12-scalar header has no L field) -- both this generator and NPU_conv_tb.vhd
independently DERIVE it from the same "exact valid conv, no padding" formula:

    L = D*(K-1) + 1 + (Lout-1)*S

so the two sides never need to agree out-of-band. The Lout=0 case (G-DEGEN
zero-output) needs NO in/w/exp files at all (D10 G3): only a cfg file, read
by the tb to confirm immediate-done + zero staging-RAM writes.

Pinned accumulation order (D2/npu_family_spec.md): bias FIRST (if BEN, weight
= first word of the filter block, CurrX = to_sfixed(1, X_M, -N) -- the
saturating-integer-constant quirk, NOT an exact 1.0), then c OUTER, k INNER
-- exactly the contiguous weight-pointer walk `think_layer()` already
implements when handed a flattened (c-outer, k-inner) input vector per
output. No arithmetic is reimplemented here: every MAC step and every
sigmoid evaluation runs through npu_fixed.mac_step()/sigmoid() by way of
think_layer().

Usage:
    /usr/bin/python3 gen_conv_vectors.py
    (no arguments -- regenerates every case into ./conv_vectors/)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import think_layer  # noqa: E402  -- the only arithmetic entry point used

# ---------------------------------------------------------------------------
# Frozen MCU/chip generics (npu_conv_design.md binding inputs)
# ---------------------------------------------------------------------------
X_M = 0
W_M = 7
Y_M = 7
N_BITS = 24
RHO = 2

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "conv_vectors")

MAX_CYCLES = 1000000       # D10 G4: bench cases must stay well under this
RAM_WORDS = 4096            # staging RAM size (word-addressed)


def calc_L(K, S, D, Lout):
    """The 'exact valid conv, no padding' input length for a chosen Lout.
    Lout = floor((L - D*(K-1) - 1)/S) + 1 inverted for an exact fit (no
    wasted/unused input samples): L = D*(K-1) + 1 + (Lout-1)*S."""
    return D * (K - 1) + 1 + (Lout - 1) * S


def conv_out_len(L, K, S, D):
    """Forward direction (sanity-check only): Lout for a 'valid' 1D conv."""
    span = D * (K - 1) + 1
    if span > L:
        return 0
    return (L - span) // S + 1


def predicted_cycles(K, Cin, Cout, Lout, BEN):
    """D6, exact: T = 1 + Cout*Lout*(5*Cin*K + 3*B + 1) + 2."""
    B = 1 if BEN else 0
    return 1 + Cout * Lout * (5 * Cin * K + 3 * B + 1) + 2


def compute_conv(inputs, weights, cin, k, cout, lout, s, d, ben, aen):
    """inputs: list of Cin lists, each length L (raw Q(X_M).N_BITS).
    weights: flat list, filter-major, bias-first-per-filter if ben.
    Returns: list of Cout lists, each length Lout (raw Q(Y_M).N_BITS, or
    Q0.N_BITS post-sigmoid if aen). Every MAC/sigmoid step runs through
    npu_fixed.think_layer()/mac_step()/sigmoid() -- this function only
    does index bookkeeping (the pinned c-outer/k-inner flattening)."""
    weights_per_filter = (1 if ben else 0) + cin * k
    outputs = []
    for f in range(cout):
        w_base = f * weights_per_filter
        w_slice = weights[w_base:w_base + weights_per_filter]
        filt_out = []
        for j in range(lout):
            x_flat = []
            for c in range(cin):
                for kk in range(k):
                    t = j * s + kk * d
                    x_flat.append(inputs[c][t])
            ni = len(x_flat) - 1
            out_list, _ = think_layer(
                x_flat, w_slice, ni=ni, nn=0, ben=ben, aen=aen,
                x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO)
            filt_out.append(out_list[0])
        outputs.append(filt_out)
    return outputs


# ---------------------------------------------------------------------------
# Deterministic stimulus generators (raw fixed-point ints; not part of the
# arithmetic path -- just test-data synthesis). Distinct, modest-magnitude,
# reproducible without an RNG.
# ---------------------------------------------------------------------------
def in_val(c, t):
    return (c * 9173 + t * 337 + 101) % 2000000 - 1000000


def w_val(f, c, k):
    return (f * 50021 + c * 3079 + k * 197 + 401) % 4000000 - 2000000


def bias_val(f):
    return (f * 12345 + 6789) % 3000000 - 1500000


class AddrAlloc(object):
    """Sequential, staggered (non-zero-based) word-address allocator over
    the 4096-word staging RAM -- D9: 'vary [addresses] across cases (not
    all zero-based) to catch base-add bugs'."""

    def __init__(self, start=64):
        self.cursor = start

    def alloc(self, n, gap=29):
        base = self.cursor
        self.cursor += n + gap
        return base


alloc = AddrAlloc()


def write_lines(path, values):
    with open(path, 'w') as f:
        for v in values:
            f.write("%d\n" % v)


def write_cfg(case, k, cin, cout, lout, s, d, ben, aen, actf, ivsar, wvsar, ovsar):
    path = os.path.join(OUT_DIR, "npu_conv_%s_cfg.txt" % case)
    write_lines(path, [k, cin, cout, lout, s, d,
                        1 if ben else 0, 1 if aen else 0, actf,
                        ivsar, wvsar, ovsar])


CASES_MANIFEST = []  # (case, K,Cin,Cout,Lout,S,D,BEN,AEN,ACTF,IVSAR,WVSAR,OVSAR,T)


def emit_case(case, k, cin, cout, lout, s, d, ben, aen, actf,
              input_fn, weight_fn, bias_fn=None, has_data=True):
    """Builds inputs/weights via the supplied per-index callbacks, computes
    the golden outputs (through think_layer -- no arithmetic here), and
    writes the four D9 files. Returns the computed outputs (flat, f*Lout+j)
    for any case-specific post-hoc assertions (G-ASYM, G-SAT)."""
    L = calc_L(k, s, d, lout)
    assert lout == 0 or conv_out_len(L, k, s, d) == lout, \
        "%s: calc_L/conv_out_len round-trip mismatch" % case

    T = predicted_cycles(k, cin, cout, lout, ben)
    assert T < MAX_CYCLES, "%s: predicted cycle count %d exceeds the %d ceiling (D10 G4)" % (case, T, MAX_CYCLES)

    if not has_data:
        # G-DEGEN zero-output: no in/w/exp files at all (D10 G3).
        ivsar = wvsar = ovsar = 0
        write_cfg(case, k, cin, cout, lout, s, d, ben, aen, actf, ivsar, wvsar, ovsar)
        CASES_MANIFEST.append((case, k, cin, cout, lout, s, d, ben, aen, actf,
                                ivsar, wvsar, ovsar, T, "in=0 w=0 out=0 (no data files)"))
        print("%-14s K=%-3d Cin=%-2d Cout=%-3d Lout=%-3d S=%d D=%d BEN=%d AEN=%d ACTF=%d  "
              "predicted_cycles=%d (no data files; degenerate)" %
              (case, k, cin, cout, lout, s, d, ben, aen, actf, T))
        return None

    inputs = [[input_fn(c, t) for t in range(L)] for c in range(cin)]
    weights_per_filter = (1 if ben else 0) + cin * k
    weights = []
    for f in range(cout):
        if ben:
            weights.append(bias_fn(f) if bias_fn else bias_val(f))
        for c in range(cin):
            for kk in range(k):
                weights.append(weight_fn(f, c, kk))
    assert len(weights) == cout * weights_per_filter

    outputs = compute_conv(inputs, weights, cin, k, cout, lout, s, d, ben, aen)
    flat_out = [outputs[f][j] for f in range(cout) for j in range(lout)]

    in_len = cin * L
    w_len = cout * weights_per_filter
    out_len = cout * lout
    ivsar = alloc.alloc(in_len)
    wvsar = alloc.alloc(w_len)
    ovsar = alloc.alloc(out_len)
    assert alloc.cursor < RAM_WORDS, "%s: address allocator exceeded the %d-word staging RAM" % (case, RAM_WORDS)

    write_cfg(case, k, cin, cout, lout, s, d, ben, aen, actf, ivsar, wvsar, ovsar)
    flat_in = [inputs[c][t] for c in range(cin) for t in range(L)]
    write_lines(os.path.join(OUT_DIR, "npu_conv_%s_in.txt" % case), flat_in)
    write_lines(os.path.join(OUT_DIR, "npu_conv_%s_w.txt" % case), weights)
    write_lines(os.path.join(OUT_DIR, "npu_conv_%s_exp.txt" % case), flat_out)

    CASES_MANIFEST.append((case, k, cin, cout, lout, s, d, ben, aen, actf,
                            ivsar, wvsar, ovsar, T,
                            "in=%d w=%d out=%d @ IVSAR=%d WVSAR=%d OVSAR=%d" %
                            (in_len, w_len, out_len, ivsar, wvsar, ovsar)))
    print("%-14s K=%-3d Cin=%-2d Cout=%-3d Lout=%-3d S=%d D=%d BEN=%d AEN=%d ACTF=%d  "
          "L=%-3d predicted_cycles=%-7d IVSAR=%-5d WVSAR=%-5d OVSAR=%-5d" %
          (case, k, cin, cout, lout, s, d, ben, aen, actf, L, T, ivsar, wvsar, ovsar))
    return flat_out


# ---------------------------------------------------------------------------
# GROUP generators (npu_conv_design.md D9)
# ---------------------------------------------------------------------------
def gen_base():
    # G-BASE: the plain path; proves the c-outer/k-inner walk + flat output order.
    emit_case("base", k=8, cin=2, cout=4, lout=16, s=1, d=1, ben=False, aen=False, actf=0,
              input_fn=in_val, weight_fn=w_val)


def gen_asym():
    # G-ASYM: asymmetric kernel (ramp, distinct per f,c) + non-palindromic
    # input ramp. Load-bearing index-order test: MUST differ from its own
    # reversed-tap-order variant (asserted here, generator-side).
    k, cin, cout, lout, s, d = 4, 2, 2, 5, 1, 1

    # NOTE: magnitudes must be large enough that a MAC product actually
    # registers a nonzero raw value after the Q.24 resize (a raw product
    # under ~2**24 rounds to 0 -- small "human-friendly" ramps like
    # (c+1)*1000+(t+1) silently vanish here and defeat the whole point of
    # this case).
    def asym_in(c, t):
        return (c + 1) * 300000 + (t + 1) * 10000

    def asym_w(f, c, kk):
        return (f + 1) * 300000 + (c + 1) * 30000 + (kk + 1) * 3000

    flat_out = emit_case("asym", k, cin, cout, lout, s, d, ben=False, aen=False, actf=0,
                          input_fn=asym_in, weight_fn=asym_w)

    # Self-check: recompute with the k-order of every filter's weights
    # REVERSED and confirm the result differs (proves the test data itself
    # is index-order-sensitive, i.e. a reversed/mis-nested RTL walk would be
    # CAUGHT by this case, not accidentally masked by symmetric data).
    L = calc_L(k, s, d, lout)
    inputs = [[asym_in(c, t) for t in range(L)] for c in range(cin)]
    weights_rev = []
    for f in range(cout):
        for c in range(cin):
            for kk in range(k):
                weights_rev.append(asym_w(f, c, k - 1 - kk))  # k reversed within each (f,c) block
    outputs_rev = compute_conv(inputs, weights_rev, cin, k, cout, lout, s, d, False, False)
    flat_rev = [outputs_rev[f][j] for f in range(cout) for j in range(lout)]
    assert flat_out != flat_rev, "G-ASYM: reversed-tap-order variant produced the SAME result -- test data is not index-order-sensitive"
    print("  G-ASYM self-check: reversed-tap-order golden result differs (OK)")


def gen_stride():
    k, cin, cout, lout, d = 4, 2, 2, 5, 1
    emit_case("stride_s2", k, cin, cout, lout, s=2, d=d, ben=False, aen=False, actf=0,
              input_fn=in_val, weight_fn=w_val)
    emit_case("stride_s4", k, cin, cout, lout, s=4, d=d, ben=False, aen=False, actf=0,
              input_fn=in_val, weight_fn=w_val)


def gen_dil():
    k, cin, cout, lout, s = 4, 2, 2, 5, 1
    for dval, name in ((2, "dil_d2"), (4, "dil_d4"), (8, "dil_d8")):
        emit_case(name, k, cin, cout, lout, s=s, d=dval, ben=False, aen=False, actf=0,
                  input_fn=in_val, weight_fn=w_val)


def gen_stride_dil():
    emit_case("stride_dil", k=4, cin=2, cout=2, lout=5, s=2, d=2,
              ben=False, aen=False, actf=0, input_fn=in_val, weight_fn=w_val)


def gen_ben():
    # G-BEN: bias = first weight of the filter block, once per output,
    # re-fetched per j (D5).
    emit_case("ben", k=4, cin=2, cout=3, lout=4, s=1, d=1, ben=True, aen=False, actf=0,
              input_fn=in_val, weight_fn=w_val, bias_fn=bias_val)


def gen_aen():
    # G-AEN: AEN=1, ACTF=0 (sigmoid-legacy). The tb reuses this SAME
    # cfg/in/w/exp data set for the ACTF=1 P4.1 fallback poke (must produce
    # the identical expected outputs -- ACTF is decoded but the activation
    # mux itself doesn't land until P4.4).
    emit_case("aen", k=4, cin=2, cout=2, lout=4, s=1, d=1, ben=False, aen=True, actf=0,
              input_fn=in_val, weight_fn=w_val)


def gen_sat():
    # G-SAT: drive the accumulator to both saturation rails. filter 0: all
    # taps at (max weight * max input) -> positive clamp. filter 1: all taps
    # at (min weight * max input) -> negative clamp. Single-channel, single
    # output -- the FINAL value equals the exact clamp bound, which is
    # sufficient proof the per-step round+saturate path (npu_fixed.mac_step,
    # reused unmodified) actually hit it (saturation, once hit, cannot be
    # undone by further same-direction accumulation).
    k, cin, cout, lout, s, d = 4, 1, 2, 1, 1, 1
    max_w = (1 << (W_M + N_BITS)) - 1     # 2**31 - 1
    min_w = -(1 << (W_M + N_BITS))        # -2**31
    max_x = (1 << N_BITS) - 1             # 2**24 - 1 (X_M=0)
    max_out = (1 << (Y_M + N_BITS)) - 1
    min_out = -(1 << (Y_M + N_BITS))

    def sat_in(c, t):
        return max_x

    def sat_w(f, c, kk):
        return max_w if f == 0 else min_w

    flat_out = emit_case("sat", k, cin, cout, lout, s, d, ben=False, aen=False, actf=0,
                          input_fn=sat_in, weight_fn=sat_w)
    assert flat_out[0] == max_out, "G-SAT: filter 0 did not hit the positive clamp (%d != %d)" % (flat_out[0], max_out)
    assert flat_out[1] == min_out, "G-SAT: filter 1 did not hit the negative clamp (%d != %d)" % (flat_out[1], min_out)
    print("  G-SAT self-check: filter0=%d (== +clamp), filter1=%d (== -clamp) OK" % (flat_out[0], flat_out[1]))


def gen_multi():
    # G-MULTI: proves the channel-advance branch (cL += L) and the
    # filter_base <= CurrWAddr snapshot across MANY filters/channels.
    emit_case("multi", k=4, cin=8, cout=16, lout=4, s=1, d=1, ben=False, aen=False, actf=0,
              input_fn=in_val, weight_fn=w_val)


def gen_degen():
    # G-DEGEN: Lout=1 single output (data-bearing) + Lout=0 (no data files;
    # tb asserts immediate done + zero staging-RAM writes, D10 G3).
    emit_case("degen_l1", k=2, cin=1, cout=1, lout=1, s=1, d=1, ben=False, aen=False, actf=0,
              input_fn=in_val, weight_fn=w_val)
    emit_case("degen_l0", k=1, cin=1, cout=1, lout=0, s=1, d=1, ben=False, aen=False, actf=0,
              input_fn=None, weight_fn=None, has_data=False)


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    print("=== gen_conv_vectors.py -- NPU CONV1D golden vectors (D9) ===")
    print("Generics: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d\n" % (X_M, W_M, Y_M, N_BITS, RHO))

    gen_base()
    gen_asym()
    gen_stride()
    gen_dil()
    gen_stride_dil()
    gen_ben()
    gen_aen()
    gen_sat()
    gen_multi()
    gen_degen()

    print("\n=== Manifest (%d cases) ===" % len(CASES_MANIFEST))
    total_predicted = 0
    for row in CASES_MANIFEST:
        case, k, cin, cout, lout, s, d, ben, aen, actf, ivsar, wvsar, ovsar, T, note = row
        total_predicted += T
        print("  %-14s T=%-8d %s" % (case, T, note))
    print("\nTotal predicted NpuClk cycles across all cases: %d" % total_predicted)
    print("Next free staging-RAM word address: %d / %d" % (alloc.cursor, RAM_WORDS))
    print("\nWrote %d cases to %s" % (len(CASES_MANIFEST), OUT_DIR))


if __name__ == '__main__':
    main()
