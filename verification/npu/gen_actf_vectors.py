#!/usr/bin/env python3
"""gen_actf_vectors.py -- FROZEN golden-vector generator for the NPU ACTF
activation mux (MODE=0/MLP,
`~/work/chip_docs/castalia/digperiphs/npu_actf_design.md` D9/D10, adjudicated
2026-07-23 with amendments A1/A2), built entirely on npu_fixed.py's validated,
bit-exact MAC/sigmoid/activate model. Emits one case per design-doc GROUP into
actf_vectors/, at the FROZEN MCU/chip generics:

    X_M=0  W_M=7  Y_M=7  N=24  RHO=2      (Q0.24 in, Q7.24 weight/acc/out)

Golden-file interface (D10, FROZEN):
    npu_actf_<case>_cfg.txt  -- 8 scalars, one per line, in order:
                                NI NN BEN AEN ACTF IVSAR WVSAR OVSAR
    npu_actf_<case>_in.txt   -- NI+1 lines (raw Q0.24 signed) -- every case
                                here uses NI=0 (ONE shared input, X_HALF =
                                0.5 real, reused by every neuron -- only the
                                per-neuron WEIGHT varies).
    npu_actf_<case>_w.txt    -- (NN+1)*(NI+1) lines (BEN always 0 in this
                                bench -- activation, not bias, is under
                                test), one weight per neuron, walked
                                contiguously exactly as think_layer() reads
                                it.
    npu_actf_<case>_exp.txt  -- NN+1 lines, one post-activation (or
                                passthrough) output per neuron.
    All data values are raw fixed-point words reinterpreted as signed
    decimal ints (the conv/xnor/gemm idiom -- no comment lines).

THE x=0.5 EXACT-ACCUMULATOR TRICK (design-doc D9 kickoff note): X is Q0.24
(|x|<1, so X cannot itself reach an accumulator target). Fixing the ONE
shared input at X_HALF = 0.5 (raw 2**23) and choosing each neuron's OWN
weight as `w_raw = 2 * target_raw` makes the single MAC tap's exact product
equal `target_raw << N_BITS` with ZERO remainder (see `build_case`'s
in-line proof), so `mac_step` lands EXACTLY on the desired signed
accumulator with no rounding to reason about -- every boundary/knee value
below is therefore exact, not "close to". Legal range of the trick: since
`w_raw = 2*target_raw` must fit the Q7.24 signed range [-2**31, 2**31),
`target_raw` (and hence the real accumulator magnitude) must stay under 64.

MANDATORY SELF-TESTS (family A1 discipline, this doc's own list): this
generator builds every case's data IN MEMORY first, runs six self-tests
against that data, and ONLY IF ALL PASS does it write the golden files to
disk.

Usage:
    /usr/bin/python3 gen_actf_vectors.py
    (no arguments -- builds every case, self-tests, then regenerates every
    case into ./actf_vectors/)
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from npu_fixed import (think_layer, mac_step, sigmoid, activate,           # noqa: E402
                        relu, tanh_approx, clamp01, exp_approx,
                        resize_sfixed, _sat_bounds)

# ---------------------------------------------------------------------------
# Frozen MCU/chip generics (npu_actf_design.md binding inputs)
# ---------------------------------------------------------------------------
X_M = 0
W_M = 7
Y_M = 7
N_BITS = 24
RHO = 2

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "actf_vectors")
RAM_WORDS = 4096            # staging RAM size (word-addressed)

A_MIN, A_MAX = -(1 << 24), (1 << 24)          # Q0.24 legal raw range [min, max)
B_MIN, B_MAX = -(1 << 31), (1 << 31)          # Q7.24 legal raw range [min, max)
MIN_OUT, MAX_OUT = _sat_bounds(Y_M, N_BITS)   # Q7.24 sat bounds

# The one shared input, every case (NI=0): raw Q0.24 for real 0.5.
X_HALF = 1 << (N_BITS - 1)

# Handy raw-unit constants (all Q(Y_M).(N_BITS) accumulator-scale integers).
ONE      = 1 << N_BITS               # real 1.0
QUARTER  = 1 << (N_BITS - 2)          # real 0.25
SIXTEENTH = 1 << (N_BITS - 4)         # real 0.0625
TWO      = 2 * ONE                    # real 2.0
FIVE     = 5 * ONE                    # real 5.0
EIGHT    = 8 * ONE                    # real 8.0
FIFTY    = 50 * ONE                   # real 50.0
EPS      = 1                          # real 2**-24 (smallest raw unit)


# ---------------------------------------------------------------------------
# Address allocation (conv/gemm/xnor idiom: sequential, staggered).
# ---------------------------------------------------------------------------
class AddrAlloc(object):
    def __init__(self, start=64):
        self.cursor = start

    def alloc(self, n, gap=29):
        base = self.cursor
        self.cursor += n + gap
        return base


alloc = AddrAlloc()

CFG_FIELDS = ['NI', 'NN', 'BEN', 'AEN', 'ACTF', 'IVSAR', 'WVSAR', 'OVSAR']

CASE_DATA = {}       # case -> dict(targets, w_list, aen, actf, outs, ivsar, wvsar, ovsar)
CASES_MANIFEST = []  # ordered list of case names (build order)


def write_lines(path, values):
    with open(path, 'w') as f:
        for v in values:
            f.write("%d\n" % v)


def write_cfg(case, values):
    path = os.path.join(OUT_DIR, "npu_actf_%s_cfg.txt" % case)
    write_lines(path, [values[name] for name in CFG_FIELDS])


def build_case(case, targets, aen, actf, note=""):
    """Builds one case IN MEMORY: NI=0 (single shared X_HALF input), NN =
    len(targets)-1, BEN=0. Each neuron's weight is `2*target` -- proven
    (via mac_step, the SAME primitive npu_fixed uses everywhere else) to
    land the accumulator EXACTLY on `target` with zero remainder:

        real(X_HALF) = 0.5, real(w) = 2*target/2**N_BITS = 2*real(target)
        exact product = 0.5 * 2*real(target) = real(target)   (no rounding)

    Then computes the case's true expected outputs via think_layer() (the
    ONE arithmetic entry point -- never reimplemented), which now (P4.4 D9)
    threads `actf` through to `activate()` when aen."""
    for t in targets:
        assert -(1 << 30) < t < (1 << 30), \
            "%s: target %d exceeds the x=0.5 trick's |real|<64 legal range" % (case, t)

    w_list = [2 * t for t in targets]
    for w in w_list:
        assert B_MIN <= w < B_MAX, "%s: derived weight %d out of Q7.24 legal range" % (case, w)

    # Bookkeeping proof (not the source of the golden data): each target is
    # EXACTLY reproduced by a lone mac_step, no rounding.
    for t, w in zip(targets, w_list):
        acc = mac_step(0, X_HALF, w, Y_M, N_BITS)
        assert acc == t, \
            "%s: x=0.5 trick did not land exactly on target %d (got %d) -- " \
            "generator bug, not an RTL concern" % (case, t, acc)

    nn = len(targets) - 1
    outs, _ = think_layer([X_HALF], w_list, ni=0, nn=nn, ben=0, aen=aen,
                          x_m=X_M, w_m=W_M, y_m=Y_M, n_bits=N_BITS, rho=RHO,
                          actf=actf, w_offset=0)
    assert len(outs) == nn + 1

    in_len, w_len, out_len = 1, nn + 1, nn + 1
    ivsar = alloc.alloc(in_len)
    wvsar = alloc.alloc(w_len)
    ovsar = alloc.alloc(out_len)
    assert alloc.cursor <= RAM_WORDS, \
        "%s: address allocator exceeded the %d-word staging RAM" % (case, RAM_WORDS)

    CASE_DATA[case] = dict(targets=targets, w_list=w_list, aen=aen, actf=actf,
                           outs=outs, ni=0, nn=nn, ivsar=ivsar, wvsar=wvsar,
                           ovsar=ovsar, note=note)
    CASES_MANIFEST.append(case)
    print("%-12s NI=0 NN=%-2d BEN=0 AEN=%d ACTF=%d  IVSAR=%-5d WVSAR=%-5d OVSAR=%-5d  %s"
          % (case, nn, aen, actf, ivsar, wvsar, ovsar, note))
    return outs


def write_case_files():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)
    for case in CASES_MANIFEST:
        d = CASE_DATA[case]
        values = {'NI': 0, 'NN': d['nn'], 'BEN': 0, 'AEN': 1 if d['aen'] else 0,
                  'ACTF': d['actf'], 'IVSAR': d['ivsar'], 'WVSAR': d['wvsar'],
                  'OVSAR': d['ovsar']}
        write_cfg(case, values)
        write_lines(os.path.join(OUT_DIR, "npu_actf_%s_in.txt" % case), [X_HALF])
        write_lines(os.path.join(OUT_DIR, "npu_actf_%s_w.txt" % case), d['w_list'])
        write_lines(os.path.join(OUT_DIR, "npu_actf_%s_exp.txt" % case), d['outs'])


# ---------------------------------------------------------------------------
# GROUP builders (npu_actf_design.md D10 GROUPs)
# ---------------------------------------------------------------------------
def gen_sigregress():
    # G-SIGMOID-REGRESS (also G-XCOLLAPSE: run FIRST, no warm-up pokes, all
    # outputs checked for definedness by the tb): AEN=1, ACTF=0. zero,
    # in-range +/-, OOR (|x|>=4) +/-.
    build_case("sigregress", [0, ONE, -ONE, FIVE, -FIVE], aen=True, actf=0,
               note="zero, +1/-1 in-range, +5/-5 OOR -- the ACTF=0 "
                    "collapse anchor (also G-XCOLLAPSE: run first)")


def gen_relu():
    # G-RELU: AEN=1, ACTF=1. Straddle zero (-eps/0/+eps, the tie boundary
    # ReLU(0)=0=passthrough(0)), plus large +/- (proves full Q7.24, not
    # clamped to [-1,1)).
    build_case("relu", [-EPS, 0, EPS, FIFTY, -FIFTY], aen=True, actf=1,
               note="-eps/0/+eps straddle, +50/-50 large (Q7.24 not clamped)")


def gen_tanh():
    # G-TANH: AEN=1, ACTF=2. The |x|=2 saturation knee (just below/at/just
    # above -- D3's pre-shift proof), small +/- (quadratic region), deep OOR
    # +/- (|x|>=4 in the DOUBLED domain, i.e. |acc|>=2 -- here 8.0 is
    # comfortably past both thresholds), and x=0 (tanh(0)=0 exactly).
    build_case("tanh", [TWO - SIXTEENTH, TWO, TWO + SIXTEENTH, QUARTER, -QUARTER,
                        EIGHT, -EIGHT, 0],
               aen=True, actf=2,
               note="knee |x|=2 (below/at/above), +/-0.25 quadratic, "
                    "+/-8.0 deep OOR, x=0")


def gen_clamp():
    # G-CLAMP: AEN=1, ACTF=3. +1.0 exact (-> 1-2**-24), -1.0 exact (-> -1.0
    # exactly), beyond both rails, in-range identity.
    build_case("clamp", [ONE, -ONE, TWO, -TWO, QUARTER], aen=True, actf=3,
               note="+1.0/-1.0 exact rails, +2.0/-2.0 beyond, +0.25 identity")


def gen_expa():
    # G-EXP: AEN=1, ACTF=4. acc=0 -> exactly 1.0 (softmax boundary), acc<0
    # -> (0,1), acc>0 -> (1,2) (proves NO clamp, distinct from sigmoid).
    build_case("expa", [0, -ONE, ONE], aen=True, actf=4,
               note="0 -> 1.0 exactly, -1.0 -> (0,1), +1.0 -> (1,2)")


def gen_reserved():
    # G-RESERVED: ACTF=5 baked in cfg; the tb ALSO reruns this case with
    # force_actf=>7 against the SAME exp file (both reserved codes decode
    # as sigmoid, D6 -- one golden file covers both).
    build_case("reserved", [0, ONE, -ONE, FIVE, -FIVE], aen=True, actf=5,
               note="reserved ACTF=5 == sigmoid (D6); tb also force_actf=>7 "
                    "vs the SAME file")


def gen_aen0():
    # G-AEN0: AEN=0. The tb sweeps force_actf=>0..4 against this ONE exp
    # file (== the raw accumulator, unconditionally -- ACTF is a don't-care
    # when AEN=0, D1 master enable). ACTF=0 baked in cfg is a placeholder
    # (overridden every run).
    build_case("aen0", [0, ONE, -ONE, FIVE, -FIVE], aen=False, actf=0,
               note="AEN=0 passthrough; tb sweeps force_actf=>0..4, all "
                    "must equal the raw accumulator")


# ---------------------------------------------------------------------------
# MANDATORY SELF-TESTS (family A1 discipline; the kickoff's explicit list)
# ---------------------------------------------------------------------------
SELFTEST_SUMMARY = {}


def test_relu_vs_sigmoid_neg():
    """(a) relu(neg) != sigmoid(neg): the 'relu' case's small IN-RANGE
    negative output (-eps, where plain sigmoid is nonzero) must differ from
    what sigmoid would have produced at the SAME accumulator -- proves
    ReLU is not silently aliasing sigmoid. (The large -50.0 negative is
    EXCLUDED from this particular check: it is deep out-of-range, where
    sigmoid's own OOR branch also emits 0 -- both 0, no discriminance
    there; -50.0's job is the separate "Q7.24 not clamped" proof.)"""
    d = CASE_DATA['relu']
    checked = 0
    for t, out in zip(d['targets'], d['outs']):
        if t < 0:
            sig = sigmoid(t, Y_M, N_BITS, RHO)
            if sig == 0:
                continue   # deep-OOR negative: sigmoid's own branch also gives 0
            assert out != sig, \
                "relu: acc=%d (relu=%d) equals sigmoid(%d)=%d -- does not discriminate" \
                % (t, out, t, sig)
            assert out == 0, "relu: acc=%d (negative) did not clamp to 0 (got %d)" % (t, out)
            checked += 1
    assert checked >= 1, "relu: expected >=1 in-range negative acc in the self-test, found %d" % checked
    SELFTEST_SUMMARY['relu_vs_sigmoid'] = "PASS (%d in-range negative acc(s): relu=0 != sigmoid, differ)" % checked
    print("  (a) PASS: relu(neg) == 0 != sigmoid(neg) on %d in-range negative acc(s)" % checked)


def test_tanh_knee_vs_sigmoid_saturation():
    """(b) tanh_approx saturates at |x|=2 while plain sigmoid(x) does NOT
    saturate until |x|=4 -- the D3 pre-shift's entire reason to exist."""
    d = CASE_DATA['tanh']
    knee_at = TWO
    tanh_at_knee = d['outs'][d['targets'].index(knee_at)]
    # tanh's own saturated value at |x|=2 (D3: 2*(2^N-1) - 2^N == 2^N - 2,
    # the exact 2y-1 post-map of the sigmoid OOR-quirk rail).
    tanh_saturated_value = (2 * ((1 << N_BITS) - 1)) - (1 << N_BITS)
    sig_at_knee = sigmoid(knee_at, Y_M, N_BITS, RHO)
    assert tanh_at_knee == tanh_saturated_value, \
        "tanh: |x|=2 knee did not saturate to the expected exact value " \
        "(got %d, expected %d)" % (tanh_at_knee, tanh_saturated_value)
    assert sig_at_knee < (1 << N_BITS) - 2, \
        "tanh: plain sigmoid(2.0) unexpectedly near-saturated (got %d) -- self-test's " \
        "own discriminance is broken" % sig_at_knee
    SELFTEST_SUMMARY['tanh_knee'] = \
        "PASS (tanh(|x|=2)=%d saturated, plain sigmoid(2.0)=%d NOT saturated)" \
        % (tanh_at_knee, sig_at_knee)
    print("  (b) PASS: tanh_approx saturates at |x|=2 (raw=%d) while plain "
          "sigmoid(2.0)=%d does NOT saturate (sigmoid's own knee is |x|=4)"
          % (tanh_at_knee, sig_at_knee))


def test_exp_boundary():
    """(c) 2*sigma(0) == 1<<N_BITS EXACTLY (the softmax stable-max boundary,
    D5's decisive argument for choosing 2*sigma over plain sigma)."""
    d = CASE_DATA['expa']
    out_at_zero = d['outs'][d['targets'].index(0)]
    assert out_at_zero == (1 << N_BITS), \
        "expa: exp_approx(0) = %d != 1<<N_BITS = %d" % (out_at_zero, 1 << N_BITS)
    SELFTEST_SUMMARY['exp_boundary'] = "PASS (exp_approx(0) == 1<<%d exactly)" % N_BITS
    print("  (c) PASS: exp_approx(acc=0) == 1<<%d == %d exactly (softmax boundary)"
          % (N_BITS, 1 << N_BITS))


def test_clamp_rails_vs_passthrough():
    """(d) clamp01(+-2.0) == the +/- Q0.24 rails, and != the RAW passthrough
    accumulator (2.0/-2.0's own raw words) -- proves clamp is a real
    saturating function, not a passthrough alias (D4)."""
    d = CASE_DATA['clamp']
    plus2 = d['outs'][d['targets'].index(TWO)]
    minus2 = d['outs'][d['targets'].index(-TWO)]
    rail_pos = (1 << N_BITS) - 1
    rail_neg = -(1 << N_BITS)
    assert plus2 == rail_pos, "clamp: +2.0 -> %d != +rail %d" % (plus2, rail_pos)
    assert minus2 == rail_neg, "clamp: -2.0 -> %d != -rail %d" % (minus2, rail_neg)
    assert plus2 != TWO, "clamp: +2.0 output equals the raw passthrough value -- not clamping"
    assert minus2 != -TWO, "clamp: -2.0 output equals the raw passthrough value -- not clamping"
    SELFTEST_SUMMARY['clamp_rails'] = "PASS (+2.0->%d, -2.0->%d, both != raw passthrough)" % (plus2, minus2)
    print("  (d) PASS: clamp01(+2.0)=%d == +rail, clamp01(-2.0)=%d == -rail, "
          "neither equals the raw passthrough accumulator" % (plus2, minus2))


def test_tanh_forgot_the_times2():
    """(e) the 'forgot the x2 pre-shift' bug model (sigmoid at the PLAIN
    accumulator, still post-mapped 2y-1) DIFFERS from the correct
    tanh_approx on the x in [2,4) knee cases (D10's explicit discriminant)."""
    d = CASE_DATA['tanh']

    def buggy_tanh(x_raw):
        y = sigmoid(x_raw, Y_M, N_BITS, RHO)   # BUG: no doubling of the input
        return (y << 1) - (1 << N_BITS)

    knee_cases = [TWO, TWO + SIXTEENTH]   # x in [2,4) region (real x=2.0, 2.0625)
    ndiff = 0
    for t in knee_cases:
        correct = d['outs'][d['targets'].index(t)]
        buggy = buggy_tanh(t)
        assert correct != buggy, \
            "tanh: acc=%d correct=%d == buggy(no x2)=%d -- self-test does not discriminate" \
            % (t, correct, buggy)
        ndiff += 1
    SELFTEST_SUMMARY['tanh_forgot_x2'] = "PASS (%d/%d knee cases differ from the no-x2 bug model)" % (ndiff, len(knee_cases))
    print("  (e) PASS: %d/%d x in [2,4) knee cases differ from the 'forgot the "
          "x2 pre-shift' bug model (which only saturates at |x|=4)" % (ndiff, len(knee_cases)))


def test_tanh_sign_extension():
    """(f) at least one tanh output is NEGATIVE, and its low-32-bit unsigned
    reinterpretation is a LARGE positive value -- the exact corruption a
    zero-extended (instead of sign-extended) tanh word would read as (GA3)."""
    d = CASE_DATA['tanh']
    neg_outs = [(t, o) for t, o in zip(d['targets'], d['outs']) if o < 0]
    assert len(neg_outs) >= 1, "tanh: no negative output in the case -- self-test needs one"
    t, o = neg_outs[0]
    unsigned_equiv = o & 0xFFFFFFFF
    assert unsigned_equiv > (1 << 31), \
        "tanh: negative output %d's unsigned reinterpretation %d is not " \
        "visibly huge -- self-test does not discriminate" % (o, unsigned_equiv)
    SELFTEST_SUMMARY['tanh_sign_ext'] = \
        "PASS (acc=%d -> tanh=%d; zero-ext would read as %d, a huge positive word)" % (t, o, unsigned_equiv)
    print("  (f) PASS: tanh(acc=%d)=%d is negative; a zero-extension bug would "
          "read it back as %d (huge positive) -- sign-extension is load-bearing"
          % (t, o, unsigned_equiv))


def test_reserved_equals_sigmoid():
    """(bonus, D6): every 'reserved' output equals plain sigmoid(acc) at the
    same accumulator -- the when-others arm's contract."""
    d = CASE_DATA['reserved']
    for t, out in zip(d['targets'], d['outs']):
        sig = sigmoid(t, Y_M, N_BITS, RHO)
        assert out == sig, "reserved: acc=%d actf=5 output %d != sigmoid %d" % (t, out, sig)
    SELFTEST_SUMMARY['reserved_eq_sigmoid'] = "PASS (%d/%d reserved outputs == sigmoid)" % (len(d['targets']), len(d['targets']))
    print("  (bonus) PASS: all %d 'reserved' (ACTF=5) outputs == plain sigmoid(acc)" % len(d['targets']))


def test_aen0_passthrough():
    """(bonus, D1): every 'aen0' output equals the raw accumulator exactly
    (AEN=0 passthrough, ACTF a don't-care)."""
    d = CASE_DATA['aen0']
    for t, out in zip(d['targets'], d['outs']):
        assert out == t, "aen0: acc=%d output %d != passthrough %d" % (t, out, t)
    SELFTEST_SUMMARY['aen0_passthrough'] = "PASS (%d/%d outputs == raw accumulator)" % (len(d['targets']), len(d['targets']))
    print("  (bonus) PASS: all %d 'aen0' (AEN=0) outputs == the raw accumulator" % len(d['targets']))


def run_self_tests():
    print("\n=== MANDATORY self-tests (npu_actf_design.md D9 kickoff list) ===")
    test_relu_vs_sigmoid_neg()
    test_tanh_knee_vs_sigmoid_saturation()
    test_exp_boundary()
    test_clamp_rails_vs_passthrough()
    test_tanh_forgot_the_times2()
    test_tanh_sign_extension()
    test_reserved_equals_sigmoid()
    test_aen0_passthrough()
    print("=== self-tests: ALL PASS ===\n")


def print_selftest_summary():
    print("=== Self-test summary block ===")
    order = ['relu_vs_sigmoid', 'tanh_knee', 'exp_boundary', 'clamp_rails',
             'tanh_forgot_x2', 'tanh_sign_ext', 'reserved_eq_sigmoid', 'aen0_passthrough']
    labels = ['(a) relu(neg) != sigmoid(neg)          ',
              '(b) tanh knee vs sigmoid saturation    ',
              '(c) exp boundary 2*sigma(0)=1<<N        ',
              '(d) clamp rails != passthrough          ',
              '(e) tanh forgot-the-x2 discriminance    ',
              '(f) tanh sign-extension discriminance   ',
              '    reserved == sigmoid                 ',
              '    aen0 == passthrough                 ']
    for key, label in zip(order, labels):
        print("  %s %s" % (label, SELFTEST_SUMMARY[key]))
    print("")


def main():
    print("=== gen_actf_vectors.py -- NPU ACTF (MODE=0/MLP) golden vectors "
          "(npu_actf_design.md D9/D10) ===")
    print("Generics: X_M=%d W_M=%d Y_M=%d N=%d RHO=%d\n" % (X_M, W_M, Y_M, N_BITS, RHO))

    gen_sigregress()
    gen_relu()
    gen_tanh()
    gen_clamp()
    gen_expa()
    gen_reserved()
    gen_aen0()

    run_self_tests()
    print_selftest_summary()

    write_case_files()

    print("=== Manifest (%d cases) ===" % len(CASES_MANIFEST))
    for case in CASES_MANIFEST:
        d = CASE_DATA[case]
        print("  %-12s NN=%-2d AEN=%d ACTF=%d  IVSAR=%-5d WVSAR=%-5d OVSAR=%-5d  %s"
              % (case, d['nn'], d['aen'], d['actf'], d['ivsar'], d['wvsar'], d['ovsar'], d['note']))
    print("\nNext free staging-RAM word address: %d / %d" % (alloc.cursor, RAM_WORDS))
    print("\nWrote %d cases to %s" % (len(CASES_MANIFEST), OUT_DIR))


if __name__ == '__main__':
    main()
