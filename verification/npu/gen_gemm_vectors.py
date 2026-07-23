#!/usr/bin/env python3
"""gen_gemm_vectors.py -- FROZEN golden-vector generator for the NPU GEMM
mode (MODE=3, `~/vesta_docs/digperiphs/npu_gemm_design.md` D2/D10, adjudicated
2026-07-23), built entirely on npu_fixed.py's validated, bit-exact MAC model.
Emits one case per design-doc case roster into gemm_vectors/, at the FROZEN
MCU/chip generics:

    X_M=0  W_M=7  Y_M=7  N=24  RHO=2      (Q0.24 in, Q7.24 weight/acc/out)

GEMM = M independent MLP THINKs (D2 KEY FINDING): for each output row m, hold
input vector A[m][:], and sweep N output columns, each a length-K dot against
column n's contiguous weights B[:][n]. This file therefore NEVER reimplements
mac_step/resize/sigmoid -- every value comes from npu_fixed.think_layer(),
called once per row exactly as npu_gemm_design.md D10 shows:

    C[m], _ = think_layer(A[m], w_list, ni=K-1, nn=N-1, ben=0, aen=AEN,
                           x_m=0, w_m=7, y_m=7, n_bits=24, rho=2, w_offset=0)

Golden-file interface (D10, FROZEN):
    npu_gemm_<case>_cfg.txt  -- 9 scalars, one per line, in order:
                                M K N BEN AEN ACTF IVSAR WVSAR OVSAR
                                (BEN is always 0 -- D6 contract-only bias).
    npu_gemm_<case>_in.txt   -- M*K lines, A ROW-MAJOR: A[m][k] at line m*K+k.
    npu_gemm_<case>_w.txt    -- K*N lines, B COLUMN-MAJOR: w_list[n*K+k] =
                                B[k][n] (one column's K weights contiguous --
                                exactly the flat array think_layer() walks
                                contiguously per neuron/column).
    npu_gemm_<case>_exp.txt  -- M*N lines, C ROW-MAJOR: C[m][n] at line m*N+n,
                                Q7.24 (or Q0.24 sigmoid raw when AEN=1).
    All data values are raw fixed-point words reinterpreted as signed decimal
    ints (the conv/xnor idiom -- no comment lines in the data files).

A/B legality (npu_gemm_design.md binding inputs): A raw is Q0.24, legal range
[-2**24, 2**24) (real A in [-1,1), the DUT's 25-bit SramQ_in(24 downto 0)
slice); B/C raw is Q7.24, legal range [-2**31, 2**31) (real B/C in [-128,128)).

MANDATORY SELF-TESTS (design-doc ADJUDICATION ADDENDUM A1): this generator
builds every case's data IN MEMORY first, runs five self-tests against that
data (M=1 subsumption, k-reverse discriminance, B-transpose discriminance,
saturation evidence, round-activity), and ONLY IF ALL PASS does it write the
golden files to disk -- an assertion failure here means the vectors do not
yet "bite" and must be re-tuned before anything is emitted.

Usage:
    /usr/bin/python3 gen_gemm_vectors.py
    (no arguments -- builds every case, self-tests, then regenerates every
    case into ./gemm_vectors/)
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import (think_layer, mac_step, resize_sfixed, _sat_bounds,  # noqa: E402
                        ROUND_TRUNCATE, SAT_SATURATE)

# ---------------------------------------------------------------------------
# Frozen MCU/chip generics (npu_gemm_design.md binding inputs)
# ---------------------------------------------------------------------------
X_M = 0
W_M = 7
Y_M = 7
N_BITS = 24
RHO = 2

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gemm_vectors")
RAM_WORDS = 4096            # staging RAM size (word-addressed), D4/D9 G1

A_MIN, A_MAX = -(1 << 24), (1 << 24)          # Q0.24 legal raw range [min, max)
B_MIN, B_MAX = -(1 << 31), (1 << 31)          # Q7.24 legal raw range [min, max)

MIN_OUT, MAX_OUT = _sat_bounds(Y_M, N_BITS)   # (-2**31, 2**31 - 1), Q7.24 sat bounds


# ---------------------------------------------------------------------------
# The one arithmetic entry point (D10): M independent think_layer() THINKs.
# ---------------------------------------------------------------------------
def gemm_compute(A, w_list, M, K, N, aen, actf=0):
    """A: list of M lists, each length K (row-major A[m][k], raw Q0.24).
    w_list: flat length K*N, COLUMN-MAJOR (w_list[n*K+k] = B[k][n]).
    Returns C: list of M lists, each length N (C[m][n]).
    Reuses think_layer() verbatim, once per row, w_offset=0 every call
    (B is reused across all M rows -- npu_gemm_design.md KEY FINDING #3).
    actf=0 default keeps the sigmoid-legacy behavior every pre-P4.4 call
    site here relies on."""
    C = []
    for m in range(M):
        out_m, _ = think_layer(A[m], w_list, ni=K - 1, nn=N - 1, ben=0, aen=aen,
                                x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS,
                                rho=RHO, w_offset=0, actf=actf)
        C.append(out_m)
    return C


# ---------------------------------------------------------------------------
# Self-test support: a walk REPLICA (bookkeeping only -- calls ONLY
# npu_fixed.mac_step for the actual arithmetic, and npu_fixed.resize_sfixed
# with a DIFFERENT round_style purely to detect whether rounding fired; it
# never reimplements the round/saturate RULE itself, it just asks the
# library's own two public, already-parameterized entry points what each
# would have done, and diffs). Used by self-tests (d) and (e).
# ---------------------------------------------------------------------------
def _mac_step_with_round_flag(acc_raw, a_raw, b_raw, acc_m, n_bits):
    """new_acc is EXACTLY npu_fixed.mac_step's real result (round-to-nearest,
    saturate) -- the arithmetic path used everywhere else in this file.
    `rounded` additionally asks resize_sfixed (also npu_fixed's own function,
    not reimplemented here) what the TRUNCATING resize would have produced
    from the identical exact widened sum, and reports whether the two
    differ. The "exact widen" recomputed here (acc<<n + a*b) is the
    documented, lossless VHDL '+'/'*' step npu_fixed.py's own module
    docstring says is NEVER itself an approximation -- only resize
    rounds/saturates, and both resize calls below let resize_sfixed (not
    this file) decide that."""
    new_acc = mac_step(acc_raw, a_raw, b_raw, acc_m, n_bits)
    exact_sum = (acc_raw << n_bits) + a_raw * b_raw
    trunc_acc = resize_sfixed(exact_sum, 2 * n_bits, acc_m, n_bits,
                               round_style=ROUND_TRUNCATE,
                               overflow_style=SAT_SATURATE)
    return new_acc, (new_acc != trunc_acc)


def replicate_gemm_walk(A, w_list, M, K, N, y_m=Y_M, n_bits=N_BITS):
    """Replica of the m-outer/n-inner GEMM accumulation walk (D2: AccResetN
    per column, k=0..K-1 IN ORDER, no bias), calling ONLY mac_step for the
    arithmetic. Returns:
      finals[m][n] -- final Q(y_m).(n_bits) raw accumulator (pre-activation)
      sat_events   -- [(m, n, k)] where an INTERMEDIATE step (k < K-1) landed
                      exactly on a saturation bound
      round_count  -- total MAC steps where round-to-nearest changed the
                      pre-round (truncated) value
      total_steps  -- total MAC steps = M*N*K
    """
    finals = [[0] * N for _ in range(M)]
    sat_events = []
    round_count = 0
    total_steps = 0
    for m in range(M):
        for n in range(N):
            acc = 0
            for k in range(K):
                a = A[m][k]
                b = w_list[n * K + k]     # column-major contract (D10)
                acc, rounded = _mac_step_with_round_flag(acc, a, b, y_m, n_bits)
                total_steps += 1
                if rounded:
                    round_count += 1
                if k < K - 1 and (acc == MAX_OUT or acc == MIN_OUT):
                    sat_events.append((m, n, k))
            finals[m][n] = acc
    return finals, sat_events, round_count, total_steps


# ---------------------------------------------------------------------------
# Address allocation (conv/xnor idiom: sequential, staggered, non-zero-based
# -- catches base-add bugs). maxfit gets its OWN pinned region (below) since
# its 3888-word footprint would otherwise consume nearly the whole RAM out
# from under every other case's shared cursor; per the conv/xnor precedent,
# cases are not required to coexist in one staged image.
# ---------------------------------------------------------------------------
class AddrAlloc(object):
    def __init__(self, start=64):
        self.cursor = start

    def alloc(self, n, gap=29):
        base = self.cursor
        self.cursor += n + gap
        return base


alloc = AddrAlloc()

CFG_FIELDS = ['M', 'K', 'N', 'BEN', 'AEN', 'ACTF', 'IVSAR', 'WVSAR', 'OVSAR']

CASE_DATA = {}       # case -> dict(A, w_list, M, K, N, aen, actf, C, flat_C, ivsar, wvsar, ovsar)
CASES_MANIFEST = []  # ordered list of case names (build order)


def write_lines(path, values):
    with open(path, 'w') as f:
        for v in values:
            f.write("%d\n" % v)


def write_cfg(case, values):
    path = os.path.join(OUT_DIR, "npu_gemm_%s_cfg.txt" % case)
    write_lines(path, [values[name] for name in CFG_FIELDS])


def build_case(case, M, K, N, aen, actf, a_fn=None, b_fn=None, A=None, w_list=None,
               ivsar=None, wvsar=None, ovsar=None, note=""):
    """Builds one case's A/w_list/C IN MEMORY (no disk I/O) and records it in
    CASE_DATA. Either supply (a_fn, b_fn) callables of (m,k)/(k,n), or
    already-built (A, w_list) lists directly (used by maxfit's seeded-random
    stimulus, to avoid any re-evaluation-order subtlety in a lazy callable)."""
    if A is None:
        A = [[a_fn(m, k) for k in range(K)] for m in range(M)]
    if w_list is None:
        w_list = [b_fn(k, n) for n in range(N) for k in range(K)]

    assert len(A) == M and all(len(row) == K for row in A), \
        "%s: A shape mismatch (expected %dx%d)" % (case, M, K)
    assert len(w_list) == K * N, "%s: w_list length %d != K*N=%d" % (case, len(w_list), K * N)

    for row in A:
        for a in row:
            assert A_MIN <= a < A_MAX, "%s: A value %d out of Q0.24 legal range" % (case, a)
    for b in w_list:
        assert B_MIN <= b < B_MAX, "%s: B value %d out of Q7.24 legal range" % (case, b)

    C = gemm_compute(A, w_list, M, K, N, aen)
    for row in C:
        assert len(row) == N
    flat_C = [C[m][n] for m in range(M) for n in range(N)]

    in_len, w_len, out_len = M * K, K * N, M * N
    footprint = in_len + w_len + out_len
    assert footprint <= RAM_WORDS, \
        "%s: footprint %d (=%d+%d+%d) exceeds the %d-word staging RAM" \
        % (case, footprint, in_len, w_len, out_len, RAM_WORDS)

    if ivsar is None:
        ivsar = alloc.alloc(in_len)
        wvsar = alloc.alloc(w_len)
        ovsar = alloc.alloc(out_len)
        assert alloc.cursor <= RAM_WORDS, \
            "%s: address allocator exceeded the %d-word staging RAM" % (case, RAM_WORDS)
    else:
        assert wvsar is not None and ovsar is not None, \
            "%s: partial explicit SAR override (need all three or none)" % case
    # non-overlap within this case's own three regions
    regions = sorted([(ivsar, in_len, 'IVSAR'), (wvsar, w_len, 'WVSAR'), (ovsar, out_len, 'OVSAR')])
    for i in range(len(regions) - 1):
        base_i, len_i, name_i = regions[i]
        base_j, _, name_j = regions[i + 1]
        assert base_i + len_i <= base_j, \
            "%s: %s [%d,%d) overlaps %s at %d" % (case, name_i, base_i, base_i + len_i, name_j, base_j)

    CASE_DATA[case] = dict(A=A, w_list=w_list, M=M, K=K, N=N, aen=aen, actf=actf,
                            C=C, flat_C=flat_C, ivsar=ivsar, wvsar=wvsar, ovsar=ovsar,
                            in_len=in_len, w_len=w_len, out_len=out_len,
                            footprint=footprint, note=note)
    CASES_MANIFEST.append(case)
    print("%-14s M=%-3d K=%-3d N=%-3d AEN=%d ACTF=%d  IVSAR=%-5d WVSAR=%-5d OVSAR=%-5d "
          "footprint=%-5d  %s"
          % (case, M, K, N, aen, actf, ivsar, wvsar, ovsar, footprint, note))
    return C


def write_case_files():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    for case in CASES_MANIFEST:
        d = CASE_DATA[case]
        M, K, N = d['M'], d['K'], d['N']
        values = {'M': M, 'K': K, 'N': N, 'BEN': 0, 'AEN': 1 if d['aen'] else 0,
                  'ACTF': d['actf'], 'IVSAR': d['ivsar'], 'WVSAR': d['wvsar'], 'OVSAR': d['ovsar']}
        write_cfg(case, values)
        flat_A = [d['A'][m][k] for m in range(M) for k in range(K)]
        write_lines(os.path.join(OUT_DIR, "npu_gemm_%s_in.txt" % case), flat_A)
        write_lines(os.path.join(OUT_DIR, "npu_gemm_%s_w.txt" % case), d['w_list'])
        write_lines(os.path.join(OUT_DIR, "npu_gemm_%s_exp.txt" % case), d['flat_C'])


# ---------------------------------------------------------------------------
# Case builders (npu_gemm_design.md pinned roster; all pure-integer stimulus
# -- no floats anywhere in the arithmetic/construction path).
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# k-reverse tie engineering (feeds test (b)). PROOF-OF-NEED (empirically
# verified while building this generator, see devlog): round-half-to-even
# accumulate-and-resize-every-step is, absent an exact tie or an
# intermediate saturation, PROVABLY ORDER-INVARIANT -- each non-tie tap's
# rounding decision depends only on that tap's OWN product (its low 24
# bits are unaffected by the running accumulator, which always carries zero
# low-order fraction bits into the next widen), so a plain reversal of
# generic "nice-looking" affine data reproduces the IDENTICAL final result
# (confirmed: the base/asym affine data alone did NOT discriminate). To make
# G-ASYM (and base) genuinely order-sensitive per the design doc's D2 "per-
# step round+saturate is non-associative" claim, one tap is engineered to
# land EXACTLY on the round-half-to-even tie boundary (remainder == 2**23
# out of 2**48) with the OTHER taps chosen so the running accumulator's
# parity at that tie differs between the forward and reversed walk -- only
# then does the tie's "round to even" resolve differently by order.
# ---------------------------------------------------------------------------
def _ext_gcd(a, b):
    if a == 0:
        return b, 0, 1
    g, x1, y1 = _ext_gcd(b % a, a)
    return g, y1 - (b // a) * x1, x1


def _modinv_pow2(a, bits=24):
    """Modular inverse of odd `a` mod 2**bits (extended Euclid) -- pure
    integer bookkeeping to CONSTRUCT a tie-inducing stimulus pair, not part
    of the RTL/FPMac arithmetic replica itself."""
    m = 1 << bits
    g, x, _ = _ext_gcd(a % m, m)
    assert g == 1, "a=%d must be odd (invertible mod 2**%d)" % (a, bits)
    return x % m


def _tie_partner(a, bits=24):
    """Given odd raw `a`, returns raw `b` such that (a*b) mod 2**bits ==
    2**(bits-1) EXACTLY -- i.e. a*b lands precisely on the round-half-to-
    even tie boundary of a mac_step at n_bits=bits."""
    inv = _modinv_pow2(a, bits)
    half = 1 << (bits - 1)
    return (half * inv) % (1 << bits)


def gen_base():
    # 1. base: M=4,K=4,N=4, AEN=0. Distinct non-symmetric values, row 0 /
    # column 0 engineered with one round-half-to-even TIE tap (k=1) so the
    # k-reverse self-test (b) genuinely discriminates (see the block comment
    # above -- generic affine data alone proved order-INVARIANT here).
    M, K, N = 4, 4, 4

    def a_fn(m, k):
        return (m * 9173 + k * 337 + 101) % 2000000 - 1000000

    def b_fn(k, n):
        return (k * 50021 + n * 3079 + 401) % 4000000 - 2000000

    A = [[a_fn(m, k) for k in range(K)] for m in range(M)]
    w_list = [b_fn(k, n) for n in range(N) for k in range(K)]

    a_tie = 654321  # odd (invertible mod 2**24)
    b_tie = _tie_partner(a_tie)
    A[0] = [211000, a_tie, 233000, 244000]
    tie_col0 = [227000, b_tie, 259000, 271000]
    for k in range(K):
        w_list[0 * K + k] = tie_col0[k]

    build_case("base", M, K, N, aen=0, actf=0, A=A, w_list=w_list,
               note="plain path: m-outer/n-inner walk, contiguous gemm_yptr, "
                    "per-row WVSAR reload fires 3x (M=4); row0/col0 carries "
                    "an engineered round-tie for the k-reverse self-test")
    d = CASE_DATA["base"]
    flat_A = [d['A'][m][k] for m in range(M) for k in range(K)]
    assert len(set(flat_A)) == len(flat_A), "base: A values are not all distinct"
    assert len(set(d['w_list'])) == len(d['w_list']), "base: B values are not all distinct"


def gen_asym():
    # 2. asym: M=3,K=5,N=4, AEN=0. THE load-bearing case (M != K != N,
    # A/B all distinct & non-symmetric affine forms -- no accidental
    # symmetry can hide an index swap or a transpose). Row 0 / column 0
    # additionally carries an engineered round-half-to-even TIE (k=2) for
    # the k-reverse self-test (b) -- see the block comment above gen_base.
    M, K, N = 3, 5, 4

    def a_fn(m, k):
        return (m + 1) * 300000 + (k + 1) * 11000

    def b_fn(k, n):
        return (k + 1) * 300000 + (n + 1) * 17000

    A = [[a_fn(m, k) for k in range(K)] for m in range(M)]
    w_list = [b_fn(k, n) for n in range(N) for k in range(K)]

    a_tie = 987651  # odd (invertible mod 2**24)
    b_tie = _tie_partner(a_tie)
    # filler values end in a nonzero remainder mod 1000 (a_fn/b_fn above are
    # both exact multiples of 1000, so a +1 offset can never collide with
    # the surrounding formula-generated matrix), AND +1 was verified (see
    # devlog) to keep the forward/reverse walk's accumulated parity at the
    # tie tap DIFFERENT between the two orders (a naive +231 offset flipped
    # enough parities that the tie resolved identically both ways -- the
    # exact filler values matter, not just their non-collision).
    A[0] = [311001, 322001, a_tie, 344001, 355001]
    tie_col0 = [317001, 334001, b_tie, 368001, 385001]
    for k in range(K):
        w_list[0 * K + k] = tie_col0[k]

    build_case("asym", M, K, N, aen=0, actf=0, A=A, w_list=w_list,
               note="load-bearing: M!=K!=N, discriminates m/n-swap, "
                    "B-transpose, and k-reverse (self-tested below); "
                    "row0/col0 carries an engineered round-tie")
    d = CASE_DATA["asym"]
    flat_A = [d['A'][m][k] for m in range(M) for k in range(K)]
    assert len(set(flat_A)) == len(flat_A), "asym: A values are not all distinct"
    assert len(set(d['w_list'])) == len(d['w_list']), "asym: B values are not all distinct"


def gen_sat():
    # 3. sat: M=2,K=6,N=3, AEN=0. Column 0 saturates positive mid-walk (k=1)
    # then returns toward range by K-1=5 (the per-step-saturation-order
    # proof); column 1 saturates and STAYS saturated to the end; column 2 is
    # a small-magnitude control that never saturates. Row 1 uses a different,
    # modest A vector purely for distinctness/diversity (the huge B in
    # columns 0/1 saturates regardless of A's exact magnitude, since a
    # single max_a*max_b product real-value already sits at the +-128 edge).
    M, K, N = 2, 6, 3
    max_a, min_a = (1 << 24) - 1, -(1 << 24)
    max_b, min_b = (1 << 31) - 1, -(1 << 31)

    A = [
        [max_a, max_a, min_a, min_a, min_a, 100000],
        [500000, -300000, 700000, -900000, 200000, -100000],
    ]
    # w_list[n*K+k] = B[k][n], column-major
    col0 = [max_b, max_b, max_b, 0, 0, 100000]              # saturate then return
    col1 = [max_b, max_b, min_b, min_b, min_b, max_b]       # saturate and stay
    col2 = [50000, 50000, 50000, 50000, 50000, 50000]       # control, no saturation
    w_list = col0 + col1 + col2

    build_case("sat", M, K, N, aen=0, actf=0, A=A, w_list=w_list,
               note="col0 saturates(+) mid-walk then returns; col1 ends "
                    "saturated(+); col2 control (no saturation)")


def gen_degen_m1():
    # 4. degen_m1: M=1,K=5,N=7 (one row) -- the D14 MLP-subsumption case.
    M, K, N = 1, 5, 7

    def a_fn(m, k):
        return (k * 6131 + 191) % 800000 - 400000

    def b_fn(k, n):
        return (k * 3079 + n * 911 + 53) % 3000000 - 1500000

    build_case("degen_m1", M, K, N, aen=0, actf=0, a_fn=a_fn, b_fn=b_fn,
               note="M=1: one THINK; D14 subsumption self-check below")


def gen_degen_n1():
    # 5. degen_n1: M=5,K=3,N=1 (matrix x vector).
    M, K, N = 5, 3, 1

    def a_fn(m, k):
        return (m * 4177 + k * 919 + 233) % 900000 - 450000

    def b_fn(k, n):
        return (k * 6553 + 71) % 2500000 - 1250000

    build_case("degen_n1", M, K, N, aen=0, actf=0, a_fn=a_fn, b_fn=b_fn,
               note="N=1: matrix x vector (single weight column)")


def gen_degen_k1():
    # 6. degen_k1: M=3,K=1,N=3 (rank-1 outer product).
    M, K, N = 3, 1, 3

    def a_fn(m, k):
        return (m * 5011 + 307) % 700000 - 350000

    def b_fn(k, n):
        return (n * 4297 + 613) % 2200000 - 1100000

    build_case("degen_k1", M, K, N, aen=0, actf=0, a_fn=a_fn, b_fn=b_fn,
               note="K=1: rank-1 outer product (single-tap dot per output)")


def gen_degen_111():
    # 7. degen_111: M=N=K=1 -- single MAC, single output.
    M, K, N = 1, 1, 1

    def a_fn(m, k):
        return 8710231

    def b_fn(k, n):
        # +1 vs. a "rounder" nearby value: forces the single MAC step's
        # exact-widen remainder above the round-half-to-even boundary, so
        # the lone step actually rounds (round_count>0, self-test (e)).
        return 913442172

    build_case("degen_111", M, K, N, aen=0, actf=0, a_fn=a_fn, b_fn=b_fn,
               note="M=N=K=1: single MAC step, single output")


def gen_maxfit():
    # 8. maxfit: M=K=N=36 (footprint 3*1296=3888 <= 4096), seeded random
    # values. Pinned SARs (roster): IVSAR=0, WVSAR=1296, OVSAR=2592 -- its
    # own address space (bypasses the shared alloc; see AddrAlloc comment).
    M, K, N = 36, 36, 36
    rng = random.Random(20260723)
    a_range = 1 << 22    # real magnitude up to ~0.25 (well inside Q0.24 legal)
    b_range = 1 << 22    # real magnitude up to ~0.25 (modest, avoids blanket
    #                      saturation across 36 accumulated taps)
    A = [[rng.randint(-a_range, a_range - 1) for _ in range(K)] for _ in range(M)]
    w_list = [rng.randint(-b_range, b_range - 1) for _ in range(K * N)]

    build_case("maxfit", M, K, N, aen=0, actf=0, A=A, w_list=w_list,
               ivsar=0, wvsar=1296, ovsar=2592,
               note="near-4096-word fit boundary (3888/4096), seeded random "
                    "(seed=20260723), pinned SARs per roster")


def gen_aen():
    # 9. aen: M=3,K=4,N=3, AEN=1, ACTF=0. A/B chosen explicitly (mod-based
    # affine formulas stayed single-signed at these small index ranges --
    # no wraparound occurred) so every pre-activation accumulator lies in
    # the sigmoid active band (|acc| < 4), with a spread of positive/
    # negative accs across the 9 outputs -- verified against the actual
    # accumulator trace below.
    M, K, N = 3, 4, 3
    A = [
        [200000, -150000, 90000, -60000],
        [-180000, 130000, -70000, 50000],
        [160000, -140000, 80000, -40000],
    ]
    Bmat = [                                   # B[k][n], K=4 rows, N=3 cols
        [800000, -700000, 600000],
        [-650000, 550000, -500000],
        [700000, -600000, 550000],
        [-600000, 500000, -450000],
    ]
    w_list = [Bmat[k][n] for n in range(N) for k in range(K)]   # column-major

    build_case("aen", M, K, N, aen=1, actf=0, A=A, w_list=w_list,
               note="AEN=1 sigmoid: pre-activation accs verified |acc|<4, "
                    "mixed sign (see self-test)")

    # Verify the pre-activation band + sign-spread directly (via
    # think_layer's own trace hook -- no reimplementation).
    d = CASE_DATA["aen"]
    band = 4 << N_BITS
    traces = []
    for m in range(M):
        trace = []
        think_layer(d['A'][m], d['w_list'], ni=K - 1, nn=N - 1, ben=0, aen=1,
                     x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO,
                     w_offset=0, trace=trace)
        traces.extend(trace)
    assert len(traces) == M * N
    for acc in traces:
        assert -band < acc < band, \
            "aen: pre-activation acc %d (%.6f) falls outside the sigmoid active band |acc|<4" \
            % (acc, acc / float(1 << N_BITS))
    assert any(a > 0 for a in traces) and any(a < 0 for a in traces), \
        "aen: pre-activation accs are not a mix of positive and negative"
    print("  aen self-check: all %d pre-activation accs within |acc|<4 "
          "(min=%.6f max=%.6f), mixed sign OK"
          % (len(traces), min(traces) / float(1 << N_BITS), max(traces) / float(1 << N_BITS)))


def gen_aen_relu_exp():
    # P4.4 adjudication amendment A2 (npu_actf_design.md D10): the
    # NPU_gemm_tb "aen" force_actf=>1 rerun now exercises LIVE ReLU (ACTF=1
    # is a real activation post-P4.4, not a sigmoid-behaves-as-0 poke).
    # Reuses the EXACT SAME A/w_list already built (and self-tested) for
    # the frozen "aen" case in CASE_DATA -- that quartet itself is never
    # touched; this emits ONLY the one new expected-output file.
    d = CASE_DATA['aen']
    A, w_list, M, K, N = d['A'], d['w_list'], d['M'], d['K'], d['N']

    C_relu = gemm_compute(A, w_list, M, K, N, aen=1, actf=1)
    flat_relu = [C_relu[m][n] for m in range(M) for n in range(N)]

    ndiff = sum(1 for a, b in zip(flat_relu, d['flat_C']) if a != b)
    assert ndiff > 0, \
        "aen_relu_exp: ReLU golden is IDENTICAL to the sigmoid golden on every " \
        "output -- the aen accumulators are supposed to be mixed-sign (does not discriminate)"

    path = os.path.join(OUT_DIR, "npu_gemm_aen_relu_exp.txt")
    write_lines(path, flat_relu)
    print("  gen_aen_relu_exp: wrote %s (%d values; %d/%d differ from the "
          "sigmoid 'aen' golden -- ACTF=1 is now live ReLU, the P4.4 inversion)"
          % (path, len(flat_relu), ndiff, len(flat_relu)))


# ---------------------------------------------------------------------------
# MANDATORY SELF-TESTS (design-doc ADJUDICATION ADDENDUM A1)
# ---------------------------------------------------------------------------
SELFTEST_SUMMARY = {}


def test_m1_subsumption():
    """(a) M=1 subsumption: for degen_m1, the GEMM result equals a lone
    think_layer call (trivially true by construction -- asserted anyway as
    a harness check against refactors)."""
    d = CASE_DATA['degen_m1']
    assert d['M'] == 1
    out_single, _ = think_layer(d['A'][0], d['w_list'], ni=d['K'] - 1, nn=d['N'] - 1,
                                 ben=0, aen=d['aen'], x_m=X_M, w_m=W_M, y_m=Y_M,
                                 n_bits=N_BITS, rho=RHO, w_offset=0)
    assert out_single == d['C'][0], \
        "M=1 subsumption FAILED: degen_m1's GEMM row != a lone think_layer call"
    SELFTEST_SUMMARY['m1_subsumption'] = "PASS (degen_m1, N=%d outputs match)" % d['N']
    print("  (a) PASS: M=1 subsumption -- degen_m1's GEMM result == a single "
          "think_layer(...) call (D14 sanity), %d/%d outputs match" % (d['N'], d['N']))


def _k_reverse_variant(A, w_list, M, K, N, aen):
    """Recompute with the k-walk reversed: A[m] reversed AND each B column
    (the contiguous K-block per neuron) reversed -- same dot mathematically,
    different per-step rounding order (D2: non-associative)."""
    A_rev = [row[::-1] for row in A]
    w_rev = [0] * (K * N)
    for n in range(N):
        col = w_list[n * K:(n + 1) * K]
        w_rev[n * K:(n + 1) * K] = col[::-1]
    return gemm_compute(A_rev, w_rev, M, K, N, aen)


def test_k_reverse_discriminance():
    """(b) k-reverse discriminance on asym (and base): assert the reversed-
    walk result differs from the pinned result in at least one word."""
    for case in ('base', 'asym'):
        d = CASE_DATA[case]
        M, K, N = d['M'], d['K'], d['N']
        C_rev = _k_reverse_variant(d['A'], d['w_list'], M, K, N, d['aen'])
        flat_orig = d['flat_C']
        flat_rev = [C_rev[m][n] for m in range(M) for n in range(N)]
        ndiff = sum(1 for x, y in zip(flat_orig, flat_rev) if x != y)
        assert ndiff > 0, \
            "%s: k-reversed accumulation produced the IDENTICAL result -- " \
            "this case does not discriminate a reversed k-walk" % case
        SELFTEST_SUMMARY['k_reverse_%s' % case] = "PASS (%d/%d words differ)" % (ndiff, len(flat_orig))
        print("  (b) PASS: %s k-reverse discriminance -- %d/%d words differ "
              "under a reversed k-walk" % (case, ndiff, len(flat_orig)))


def test_b_transpose_discriminance():
    """(c) B-transpose discriminance on asym: repack B row-major
    (w_list[k*N+n] = B[k][n]) and assert the result differs from the
    column-major-contract result."""
    d = CASE_DATA['asym']
    M, K, N = d['M'], d['K'], d['N']
    w_list = d['w_list']
    B = [[w_list[n * K + k] for n in range(N)] for k in range(K)]   # unpack column-major
    w_rowmajor = [0] * (K * N)
    for k in range(K):
        for n in range(N):
            w_rowmajor[k * N + n] = B[k][n]                        # repack row-major (SAME K*N count)
    C2 = gemm_compute(d['A'], w_rowmajor, M, K, N, d['aen'])
    flat_orig = d['flat_C']
    flat2 = [C2[m][n] for m in range(M) for n in range(N)]
    ndiff = sum(1 for x, y in zip(flat_orig, flat2) if x != y)
    assert ndiff > 0, \
        "asym: row-major-repacked B produced the IDENTICAL result -- " \
        "this case does not discriminate a transposed-B read"
    SELFTEST_SUMMARY['b_transpose'] = "PASS (%d/%d words differ)" % (ndiff, len(flat_orig))
    print("  (c) PASS: asym B-transpose discriminance -- %d/%d words differ "
          "(K=%d != N=%d guarantees a shape-level misread is observable)"
          % (ndiff, len(flat_orig), K, N))


def test_saturation_evidence():
    """(d) saturation evidence on sat: replicate the walk with EXPLICIT
    mac_step calls (via replicate_gemm_walk, which imports mac_step from
    npu_fixed -- never reimplemented) to COUNT mid-accumulation saturation
    events, confirm >=1 output ends saturated, >=1 output LEAVES saturation
    afterward, and the replica walk's final accs equal think_layer's own
    outputs (faithfulness)."""
    d = CASE_DATA['sat']
    A, w_list, M, K, N = d['A'], d['w_list'], d['M'], d['K'], d['N']
    finals, sat_events, round_count, total_steps = replicate_gemm_walk(A, w_list, M, K, N)

    for m in range(M):
        for n in range(N):
            assert finals[m][n] == d['C'][m][n], \
                "sat: replica-walk final acc[%d][%d]=%d != think_layer output %d " \
                "-- replica walk is not faithful" % (m, n, finals[m][n], d['C'][m][n])

    assert len(sat_events) >= 1, "sat: no mid-accumulation (k < K-1) saturation event found"

    mid_by_mn = {}
    for (m, n, k) in sat_events:
        mid_by_mn.setdefault((m, n), []).append(k)

    ended_sat = [(m, n) for m in range(M) for n in range(N)
                 if finals[m][n] in (MIN_OUT, MAX_OUT)]
    left_sat = [(m, n) for (m, n) in mid_by_mn if finals[m][n] not in (MIN_OUT, MAX_OUT)]

    assert len(ended_sat) >= 1, "sat: no output ends saturated"
    assert len(left_sat) >= 1, "sat: no output leaves saturation after an interior clamp"

    SELFTEST_SUMMARY['saturation_evidence'] = \
        "PASS (%d mid-walk sat events, %d outputs end saturated, %d leave saturation, " \
        "%d/%d steps faithful)" % (len(sat_events), len(ended_sat), len(left_sat), M * N, M * N)
    print("  (d) PASS: G-SAT saturation evidence -- %d mid-walk sat events "
          "(at m,n,k=%s), %d/%d outputs end saturated, %d outputs leave "
          "saturation after an interior clamp; replica walk faithful to "
          "think_layer on all %d outputs (%d total MAC steps)"
          % (len(sat_events), sat_events, len(ended_sat), M * N, len(left_sat), M * N, total_steps))


def test_round_activity():
    """(e) round-activity: count MAC steps where rounding actually fired
    (resize changed the exact pre-round value); assert > 0 on every case
    (conv precedent: 38/72 steps rounded)."""
    print("  (e) round-activity per case:")
    per_case = {}
    for case in CASES_MANIFEST:
        d = CASE_DATA[case]
        _, _, round_count, total_steps = replicate_gemm_walk(d['A'], d['w_list'],
                                                              d['M'], d['K'], d['N'])
        per_case[case] = (round_count, total_steps)
        print("      %-14s round_count=%-6d / total_steps=%-6d" % (case, round_count, total_steps))
        assert round_count > 0, \
            "%s: zero MAC steps rounded (round_count=0) -- stimulus is not " \
            "generic enough to exercise rounding" % case
    SELFTEST_SUMMARY['round_activity'] = per_case
    print("      PASS: every case has round_count > 0")


def run_self_tests():
    print("\n=== MANDATORY self-tests (npu_gemm_design.md ADJUDICATION ADDENDUM A1) ===")
    test_m1_subsumption()
    test_k_reverse_discriminance()
    test_b_transpose_discriminance()
    test_saturation_evidence()
    test_round_activity()
    print("=== self-tests: ALL PASS ===\n")


def print_selftest_summary():
    print("=== Self-test summary block ===")
    print("  (a) M=1 subsumption:         %s" % SELFTEST_SUMMARY['m1_subsumption'])
    print("  (b) k-reverse (base):        %s" % SELFTEST_SUMMARY['k_reverse_base'])
    print("  (b) k-reverse (asym):        %s" % SELFTEST_SUMMARY['k_reverse_asym'])
    print("  (c) B-transpose (asym):      %s" % SELFTEST_SUMMARY['b_transpose'])
    print("  (d) saturation evidence:     %s" % SELFTEST_SUMMARY['saturation_evidence'])
    print("  (e) round-activity per case:")
    for case, (rc, ts) in SELFTEST_SUMMARY['round_activity'].items():
        print("        %-14s %d/%d steps rounded" % (case, rc, ts))
    print("")


def main():
    print("=== gen_gemm_vectors.py -- NPU GEMM (MODE=3) golden vectors "
          "(npu_gemm_design.md D2/D10) ===")
    print("Generics: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d\n" % (X_M, W_M, Y_M, N_BITS, RHO))

    gen_base()
    gen_asym()
    gen_sat()
    gen_degen_m1()
    gen_degen_n1()
    gen_degen_k1()
    gen_degen_111()
    gen_maxfit()
    gen_aen()
    gen_aen_relu_exp()

    run_self_tests()
    print_selftest_summary()

    write_case_files()

    print("=== Manifest (%d cases) ===" % len(CASES_MANIFEST))
    for case in CASES_MANIFEST:
        d = CASE_DATA[case]
        print("  %-14s M=%-3d K=%-3d N=%-3d AEN=%d  IVSAR=%-5d WVSAR=%-5d OVSAR=%-5d  "
              "in=%-5d w=%-5d exp=%-5d  footprint=%-5d"
              % (case, d['M'], d['K'], d['N'], d['aen'], d['ivsar'], d['wvsar'], d['ovsar'],
                 d['in_len'], d['w_len'], d['out_len'], d['footprint']))
    print("\nNext free staging-RAM word address (shared allocator, excludes "
          "maxfit's pinned own-region): %d / %d" % (alloc.cursor, RAM_WORDS))
    print("\nWrote %d cases to %s" % (len(CASES_MANIFEST), OUT_DIR))


if __name__ == '__main__':
    main()
