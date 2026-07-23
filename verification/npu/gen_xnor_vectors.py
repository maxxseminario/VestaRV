#!/usr/bin/env python3
"""gen_xnor_vectors.py -- golden-vector generator for the NPU XNOR/popcount
binary mode (digperiphs P4.2, `~/vesta_docs/digperiphs/npu_family_spec.md`
D6/D9/D17 -- SPEC-FROZEN bit-level semantics; the file-format details below
are marked PROVISIONAL and await the design doc).

XNOR is a NEW datapath (no MAC, no sigmoid -- D9): this file does NOT
import npu_fixed.py (that library is the FPMac/FPSigmoid MLP/CONV/GEMM
replica; nothing here reuses it). Everything is exact Python-integer
bit/popcount arithmetic -- no floats anywhere, per house rule.

Frozen semantics implemented (npu_family_spec.md D6/D9/D17):
    K input bits (1..4096), N neurons (1..256). Packing LSB-first: bit i at
    word bit (i mod 32), word (i >> 5). Activations: ceil(K/32) words at
    IVSAR. Weights: neuron-major, neuron n's ceil(K/32) words at
    WVSAR + n*ceil(K/32). Outputs: one word per neuron at OVSAR + n.

    value_n = 2*popcount(XNOR(a, w_n)) - K, counting ONLY bits 0..K-1 -- the
    last word is TAIL-MASKED when K mod 32 != 0 (unused tail bits may hold
    ARBITRARY GARBAGE in the staged words; the model must be invariant to
    it -- that is the entire point of D6's test-pattern correction).

    Fires iff value_n >= THRESH (signed 32-bit). Output word: fires ->
    +1.0 Q7.24 = 0x01000000; else -1.0 Q7.24 = 0xFF000000 (unsigned) /
    -16777216 (signed) -- returned/written as the signed Python int, the
    same "raw fixed-point word as a signed decimal" convention npu_fixed.py
    and gen_conv_vectors.py already use.

Golden-file interface (PROVISIONAL -- structure kept so a rename/reorder of
the cfg header is a ONE-LINE change: edit the `CFG_FIELDS` list below):
    npu_xnor_<case>_cfg.txt -- 6 scalars, one per line, in CFG_FIELDS order:
                               K N THRESH IVSAR WVSAR OVSAR
    npu_xnor_<case>_in.txt  -- ceil(K/32) lines: the packed activation words
    npu_xnor_<case>_w.txt   -- N*ceil(K/32) lines, neuron-major (neuron n's
                               words contiguous, in neuron order)
    npu_xnor_<case>_exp.txt -- N lines, one expected output word per neuron
    All data values are raw signed-decimal ints (conv idiom) -- no comment
    lines in the data files themselves (matches gen_conv_vectors.py's
    plain-numeric cfg/in/w/exp files byte-for-byte; the PROVISIONAL marker
    and field order live here in this docstring/the CFG_FIELDS comment, not
    inside the emitted data files, so a future testbench parser never has
    to skip a comment line).

Usage:
    /usr/bin/python3 gen_xnor_vectors.py
    (no arguments -- runs the self-tests, then regenerates every case into
    ./xnor_vectors/)
"""
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xnor_vectors")
RAM_WORDS = 4096          # staging RAM size (word-addressed), D17/D9

FIRE = 0x01000000         # +1.0 Q7.24
NOT_FIRE = -16777216      # -1.0 Q7.24 (0xFF000000 as signed 32-bit two's complement)


# ---------------------------------------------------------------------------
# Core library: xnor_layer() and its bit-packing helpers.
# ---------------------------------------------------------------------------
def bits32(x):
    """Mask any Python int (positive or negative two's-complement) down to
    its low 32 bits, unsigned."""
    return x & 0xFFFFFFFF


def popcount32(x):
    return bin(bits32(x)).count('1')


def nwords_for_k(k):
    return (k + 31) // 32


def tail_mask(k):
    """Mask selecting the COUNTED bits of the LAST packed word (D6/D17):
    bits 0..(k mod 32 - 1), or all 32 bits when k is an exact multiple of
    32 (no tail at all)."""
    rem = k % 32
    return 0xFFFFFFFF if rem == 0 else (1 << rem) - 1


def popcount_xnor(a_words, w_words, k):
    """popcount(XNOR(a, w)) over exactly the K counted bits -- the last
    word's uncounted (garbage-eligible) bits are masked out before
    counting, per the D6/D9 tail-mask contract."""
    nw = nwords_for_k(k)
    assert len(a_words) == nw, "a_words length %d != ceil(K/32)=%d" % (len(a_words), nw)
    assert len(w_words) == nw, "w_words length %d != ceil(K/32)=%d" % (len(w_words), nw)
    mask_last = tail_mask(k)
    last = nw - 1
    pop = 0
    for i in range(nw):
        x = bits32(~(bits32(a_words[i]) ^ bits32(w_words[i])))  # XNOR
        if i == last:
            x &= mask_last
        pop += popcount32(x)
    return pop


def xnor_layer(a_words, w_words_per_neuron, K, THRESH):
    """THE library function (npu_family_spec.md D6/D9/D17).

    a_words           : list of ceil(K/32) packed activation words (ints;
                         unused tail bits of the last word may be garbage)
    w_words_per_neuron: list of N entries, each a list of ceil(K/32) packed
                         weight words for that neuron (same tail-garbage
                         tolerance)
    K                 : exact input bit count, 1..4096
    THRESH            : signed 32-bit fire threshold

    Returns a list of N output words (Python ints; FIRE or NOT_FIRE), tail
    mask applied INSIDE (the caller never needs to pre-clean garbage).
    """
    assert 1 <= K <= 4096, "K=%d out of the D17 scope (1..4096)" % K
    nw = nwords_for_k(K)
    assert len(a_words) == nw, \
        "a_words length %d != ceil(K/32)=%d" % (len(a_words), nw)

    outputs = []
    for n, w_words in enumerate(w_words_per_neuron):
        assert len(w_words) == nw, \
            "neuron %d weight length %d != ceil(K/32)=%d" % (n, len(w_words), nw)
        pop = popcount_xnor(a_words, w_words, K)
        value = 2 * pop - K
        outputs.append(FIRE if value >= THRESH else NOT_FIRE)
    return outputs


# ---------------------------------------------------------------------------
# Bit-packing / test-data-construction helpers (not part of the arithmetic
# contract itself -- used to build deterministic, precisely-controlled
# stimulus and by the self-tests below).
# ---------------------------------------------------------------------------
def unpack_bits(words, k):
    """LSB-first unpack: bit i (0..k-1) of the packed word list."""
    return [(bits32(words[i >> 5]) >> (i & 31)) & 1 for i in range(k)]


def pack_bits(bit_list):
    """LSB-first pack: inverse of unpack_bits. Any bit beyond the supplied
    list's length (up to the word boundary) is left 0 -- i.e. tail bits are
    clean by construction unless a caller deliberately dirties them
    afterward (see with_tail_garbage)."""
    k = len(bit_list)
    nw = nwords_for_k(k) if k > 0 else 1
    words = [0] * nw
    for i, b in enumerate(bit_list):
        if b:
            words[i >> 5] |= (1 << (i & 31))
    return words


def with_tail_garbage(words, k, garbage):
    """Return a COPY of `words` with the last word's UNCOUNTED (tail) bits
    OR-ed in from `garbage` (any 32-bit pattern -- only the bits outside
    tail_mask(k) are taken). The counted bits (0..k-1's share of the last
    word) are preserved unchanged. No-op when k is an exact multiple of 32
    (no tail bits exist)."""
    nw = nwords_for_k(k)
    mask_last = tail_mask(k)
    out = list(words)
    last = nw - 1
    kept = bits32(out[last]) & mask_last
    out[last] = kept | (bits32(garbage) & (~mask_last & 0xFFFFFFFF))
    return out


def alt_bits(k):
    """A simple, non-constant, fully deterministic K-bit pattern
    (0,1,0,1,...) used as the canonical hand-constructed 'a' activation
    vector. Deliberately NOT all-zero: XNOR(0, w) degenerates to NOT(w),
    which would exercise only half of the XNOR truth table."""
    return [i % 2 for i in range(k)]


def agree_word(a_bits, num_agree):
    """Pack a w-bit vector achieving EXACTLY `num_agree` XNOR agreements
    against `a_bits` (LSB-first: positions 0..num_agree-1 match, the rest
    are flipped -- so popcount(XNOR(pack(a_bits), this)) == num_agree
    exactly, letting cases target an exact `value` by construction rather
    than by search)."""
    k = len(a_bits)
    assert 0 <= num_agree <= k
    w_bits = [a_bits[i] if i < num_agree else (1 - a_bits[i]) for i in range(k)]
    return pack_bits(w_bits)


# ---------------------------------------------------------------------------
# Self-tests (run at script start, per task spec) -- these are the enforcement
# of D6's test-pattern correction, not the case files themselves.
# ---------------------------------------------------------------------------
def test_tail_mask_invariance():
    """1. Tail-mask invariance: same logical (counted-bit) vectors, two
    DIFFERENT garbage fills in the tail bits of BOTH a and w's last words
    -> identical xnor_layer outputs. K=40 and K=33 (single-bit tail, the
    harshest mask)."""
    for K in (40, 33):
        a_bits = alt_bits(K)
        a_base = pack_bits(a_bits)
        # three neurons at distinct, in-range agreement counts
        raw_targets = [K // 3, (2 * K) // 3, K - 1]
        agree_list = []
        for t in raw_targets:
            t = min(max(t, 0), K)
            while t in agree_list:
                t = min(t + 1, K)
            agree_list.append(t)
        w_base = [agree_word(a_bits, ag) for ag in agree_list]
        THRESH = 0

        variantA_a = with_tail_garbage(a_base, K, 0x33333333)
        variantB_a = with_tail_garbage(a_base, K, 0xCCCCCCCC)
        variantA_w = [with_tail_garbage(w, K, 0x0F0F0F0F ^ (i * 0x01010101))
                      for i, w in enumerate(w_base)]
        variantB_w = [with_tail_garbage(w, K, 0xF0F0F0F0 ^ (i * 0x02020202))
                      for i, w in enumerate(w_base)]

        outA = xnor_layer(variantA_a, variantA_w, K, THRESH)
        outB = xnor_layer(variantB_a, variantB_w, K, THRESH)
        assert outA == outB, \
            "tail-mask invariance FAILED at K=%d: %r vs %r" % (K, outA, outB)
    print("  PASS: tail-mask invariance holds for K=40 and K=33 under "
          "independent garbage fills of BOTH a and w's last words")


def test_value_parity():
    """2. Parity/lattice: value = 2*popcount - K always has the SAME
    parity as K (trivially, since 2*popcount is always even) -- assert it
    across random (K, a, w) triples, including odd/even K and multi-word
    K."""
    rng = random.Random(4242)
    trials = 40
    for _ in range(trials):
        K = rng.randint(1, 4096)
        nw = nwords_for_k(K)
        a = [rng.getrandbits(32) for _ in range(nw)]
        w = [rng.getrandbits(32) for _ in range(nw)]
        pop = popcount_xnor(a, w, K)
        value = 2 * pop - K
        assert (value - K) % 2 == 0, \
            "parity broken: K=%d pop=%d value=%d" % (K, pop, value)
        assert -K <= value <= K, \
            "value out of range: K=%d pop=%d value=%d" % (K, pop, value)
    print("  PASS: value/K parity holds across %d random (K, a, w) cases "
          "(K in 1..4096, both odd and even, multi-word)" % trials)


def test_reversal_blindness():
    """3. Reversal blindness demo (documentation-grade, D6 correction):
    popcount(XNOR(a, w)) is INVARIANT under a uniform bit-reversal applied
    to BOTH operands, for full-word K (no tail mask involved) -- this is
    exactly why dense full-word vectors cannot catch a bit-order/endian
    bug; the real discriminator is the tail-mask test above."""
    rng = random.Random(99)
    for K in (32, 64, 96, 128):
        nw = nwords_for_k(K)
        a = [rng.getrandbits(32) for _ in range(nw)]
        w = [rng.getrandbits(32) for _ in range(nw)]
        pop_orig = popcount_xnor(a, w, K)

        a_rev = pack_bits(unpack_bits(a, K)[::-1])
        w_rev = pack_bits(unpack_bits(w, K)[::-1])
        pop_rev = popcount_xnor(a_rev, w_rev, K)

        assert pop_orig == pop_rev, \
            "reversal changed popcount at K=%d (%d vs %d) -- should be invariant" \
            % (K, pop_orig, pop_rev)
    print("  PASS: reversal blindness demo -- popcount(XNOR(a,w)) is "
          "invariant under uniform bit-reversal of BOTH operands at "
          "full-word K (32/64/96/128). This is WHY full-word dense vectors "
          "cannot catch a bit-order bug (family-spec D6 correction): a DUT "
          "with the wrong bit order permutes both operands identically and "
          "these vectors would still 'pass'. The load-bearing test is the "
          "partial-last-word tail-mask case above, not this one.")


def run_self_tests():
    print("=== gen_xnor_vectors.py self-tests ===")
    test_tail_mask_invariance()
    test_value_parity()
    test_reversal_blindness()
    print("=== self-tests: ALL PASS ===\n")


# ---------------------------------------------------------------------------
# PROVISIONAL cfg header (npu_family_spec.md D4/D9/D17 register-map delta;
# NPUCFG1=THRESH, NPUCFG2[12:0]=K exact bit count -- the design doc pins
# final field positions/names). Renaming or reordering the header is a
# ONE-LINE change: edit this list (and the `values` dict key it maps to, if
# renaming). Do NOT hardcode field order anywhere else.
# ---------------------------------------------------------------------------
CFG_FIELDS = ['K', 'N', 'THRESH', 'IVSAR', 'WVSAR', 'OVSAR']


class AddrAlloc(object):
    """Sequential, staggered (non-zero-based) word-address allocator over
    the 4096-word staging RAM -- same idiom as gen_conv_vectors.py's
    AddrAlloc: vary addresses across cases (not all zero-based) to catch
    base-add bugs, and keep every case's regions non-overlapping."""

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


def write_cfg(case, k, n, thresh, ivsar, wvsar, ovsar):
    values = {'K': k, 'N': n, 'THRESH': thresh,
              'IVSAR': ivsar, 'WVSAR': wvsar, 'OVSAR': ovsar}
    path = os.path.join(OUT_DIR, "npu_xnor_%s_cfg.txt" % case)
    write_lines(path, [values[name] for name in CFG_FIELDS])


CASES_MANIFEST = []  # (case, K, N, nwords, IVSAR, WVSAR, OVSAR, footprint, fire_pattern, note)


def emit_case(case, a_words, w_list, K, THRESH, note=""):
    """Builds the four PROVISIONAL golden files for one case from already-
    constructed (a_words, w_list) via xnor_layer -- no arithmetic here
    beyond the one xnor_layer() call; this function only does address
    allocation, file writing, and the manifest/print bookkeeping."""
    N = len(w_list)
    assert 1 <= N <= 256, "%s: N=%d out of the D17 scope (1..256)" % (case, N)
    nw = nwords_for_k(K)
    assert len(a_words) == nw, "%s: a_words length mismatch" % case
    for w in w_list:
        assert len(w) == nw, "%s: weight length mismatch" % case

    # distinct per-neuron weights (task requirement, every case)
    assert len(set(tuple(w) for w in w_list)) == N, \
        "%s: duplicate neuron weight vectors -- not distinct per neuron" % case

    outputs = xnor_layer(a_words, w_list, K, THRESH)
    fires = sum(1 for o in outputs if o == FIRE)
    if N > 1:
        assert 0 < fires < N, \
            "%s: degenerate fire pattern (%d/%d fire) -- not a mix" % (case, fires, N)

    in_len = nw
    w_len = N * nw
    out_len = N
    footprint = in_len + w_len + out_len
    assert footprint <= RAM_WORDS, \
        "%s: footprint %d exceeds the %d-word staging RAM" % (case, footprint, RAM_WORDS)

    ivsar = alloc.alloc(in_len)
    wvsar = alloc.alloc(w_len)
    ovsar = alloc.alloc(out_len)
    assert alloc.cursor <= RAM_WORDS, \
        "%s: address allocator exceeded the %d-word staging RAM" % (case, RAM_WORDS)

    write_cfg(case, K, N, THRESH, ivsar, wvsar, ovsar)
    write_lines(os.path.join(OUT_DIR, "npu_xnor_%s_in.txt" % case), a_words)
    flat_w = [w for neuron_w in w_list for w in neuron_w]
    write_lines(os.path.join(OUT_DIR, "npu_xnor_%s_w.txt" % case), flat_w)
    write_lines(os.path.join(OUT_DIR, "npu_xnor_%s_exp.txt" % case), outputs)

    fire_pattern = ''.join('F' if o == FIRE else '.' for o in outputs)
    CASES_MANIFEST.append((case, K, N, nw, ivsar, wvsar, ovsar, footprint, fire_pattern, note))
    print("%-20s K=%-5d N=%-4d words/neuron=%-4d IVSAR=%-5d WVSAR=%-5d OVSAR=%-5d "
          "footprint=%-5d fire=[%s]  %s"
          % (case, K, N, nw, ivsar, wvsar, ovsar, footprint, fire_pattern, note))
    return outputs


# ---------------------------------------------------------------------------
# Case generators (task spec, "Cases" list -- all distinct per-neuron
# weights and non-degenerate fire/not-fire mixes, enforced by emit_case's
# own asserts above).
# ---------------------------------------------------------------------------
def gen_base():
    # base: K=64, N=8, THRESH=0. Eight neurons at distinct exact agreement
    # counts, alternating fire/miss (constructed, not searched).
    K, N, THRESH = 64, 8, 0
    a_bits = alt_bits(K)
    a = pack_bits(a_bits)
    agree = [44, 20, 54, 10, 34, 30, 59, 5]   # -> values 24,-24,44,-44,4,-4,54,-54
    assert len(set(agree)) == N
    w_list = [agree_word(a_bits, ag) for ag in agree]
    emit_case("base", a, w_list, K, THRESH, note="plain path, 4/4 fire mix")


def gen_tail40():
    # tail40 (+ companion tail40_tailalt): K=40, N=4, EXPLICIT garbage in
    # the tail bits (bits 8..31 of the last word, mask=0xFF) of BOTH a and
    # every neuron's w, in two DIFFERENT fills -- exp must be (and is
    # asserted to be) byte-identical between the two.
    K, N, THRESH = 40, 4, 0
    a_bits = alt_bits(K)
    a_base = pack_bits(a_bits)
    agree = [25, 15, 35, 5]   # -> values 10,-10,30,-30
    assert len(set(agree)) == N
    w_base = [agree_word(a_bits, ag) for ag in agree]

    def variant(garbage_a, garbage_w_fn):
        a = with_tail_garbage(a_base, K, garbage_a)
        w = [with_tail_garbage(w_base[n], K, garbage_w_fn(n)) for n in range(N)]
        return a, w

    a1, w1 = variant(0xAAAAAAAA, lambda n: 0xAAAAAAAA ^ (n * 0x01010101))
    a2, w2 = variant(0x55555555, lambda n: 0x55555555 ^ (n * 0x03030303))

    out1 = xnor_layer(a1, w1, K, THRESH)
    out2 = xnor_layer(a2, w2, K, THRESH)
    assert out1 == out2, \
        "tail40/tail40_tailalt: garbage variants disagree -- tail mask not invariant!"

    emit_case("tail40", a1, w1, K, THRESH,
              note="explicit tail garbage fill A (bits 8:31 of last word)")
    emit_case("tail40_tailalt", a2, w2, K, THRESH,
              note="companion: DIFFERENT tail garbage fill B, byte-identical exp "
                   "(DUT tail-mask-invariance proof)")


def gen_tail33():
    # tail33: K=33, N=4 -- single bit in the last word (the harshest mask,
    # mask=0x1). Explicit nonzero garbage above bit 0 of the last word.
    K, N, THRESH = 33, 4, 1
    a_bits = alt_bits(K)
    a_base = pack_bits(a_bits)
    agree = [23, 13, 17, 16]   # -> values 13,-7,1,-1 (n2 AT thresh=1, n3 just misses)
    assert len(set(agree)) == N
    w_base = [agree_word(a_bits, ag) for ag in agree]

    a = with_tail_garbage(a_base, K, 0xDEADBEEF)
    w_list = [with_tail_garbage(w_base[n], K, 0xC0FFEE00 ^ (n * 0x11111111))
              for n in range(N)]
    emit_case("tail33", a, w_list, K, THRESH,
              note="single-bit-counted last word (mask=0x1), explicit garbage above bit0")


def gen_tie():
    # tie: K=32, N=6, THRESH=4 (even, on-lattice): n0 lands exactly AT
    # value=THRESH (fires), n1 at THRESH-2 (misses), plus a broader mix.
    K, N, THRESH = 32, 6, 4
    a_bits = alt_bits(K)
    a = pack_bits(a_bits)
    agree = [18, 17, 32, 0, 22, 12]   # -> values 4,2,32,-32,12,-8
    assert len(set(agree)) == N
    w_list = [agree_word(a_bits, ag) for ag in agree]
    outs = emit_case("tie", a, w_list, K, THRESH,
                      note="n0 value==THRESH (fires), n1 value==THRESH-2 (misses)")
    assert outs[0] == FIRE, "tie: n0 (value==THRESH) must fire"
    assert outs[1] == NOT_FIRE, "tie: n1 (value==THRESH-2) must not fire"


def gen_tie_offlattice():
    # tie_offlattice: same K=32/N=6 shape, THRESH=5 (ODD -- off the
    # even-K value lattice, so no value can equal it exactly). Probes the
    # >= boundary right around an unreachable threshold: the highest
    # reachable value below THRESH must miss, the lowest reachable value
    # at/above THRESH must fire.
    K, N, THRESH = 32, 6, 5
    a_bits = alt_bits(K)
    a = pack_bits(a_bits)
    agree = [18, 19, 32, 0, 15, 26]   # -> values 4,6,32,-32,-2,20
    assert len(set(agree)) == N
    w_list = [agree_word(a_bits, ag) for ag in agree]
    outs = emit_case("tie_offlattice", a, w_list, K, THRESH,
                      note="THRESH=5 off the even-K lattice: n0 value=4 misses, n1 value=6 fires")
    assert outs[0] == NOT_FIRE, "tie_offlattice: n0 (value=4 < THRESH=5) must miss"
    assert outs[1] == FIRE, "tie_offlattice: n1 (value=6 >= THRESH=5) must fire"


def gen_extremes():
    # extremes: three sub-cases, each checked against the 4096-word
    # staging-RAM footprint bound before addresses are allocated.

    # (a) K=1, N=2 -- minimal K, one real bit + explicit garbage elsewhere
    # in the (single, mostly-unused) staged word.
    K, THRESH = 1, 0
    a_bits = alt_bits(K)          # = [0]
    a_base = pack_bits(a_bits)
    w0_base = agree_word(a_bits, 1)   # agrees -> value=+1, fires
    w1_base = agree_word(a_bits, 0)   # disagrees -> value=-1, misses
    a = with_tail_garbage(a_base, K, 0xABCD1234)
    w0 = with_tail_garbage(w0_base, K, 0x12345678)
    w1 = with_tail_garbage(w1_base, K, 0x87654321)
    emit_case("extremes_k1", a, [w0, w1], K, THRESH,
              note="minimal K=1, tail garbage above the one counted bit")

    # (b) K=4096, N=1 -- max K, 128 packed words, single neuron landing
    # EXACTLY at THRESH (boundary check at full scale).
    K = 4096
    a_bits = alt_bits(K)
    a = pack_bits(a_bits)
    agree = 2096          # -> value = 2*2096-4096 = 96
    THRESH = 96
    w = agree_word(a_bits, agree)
    emit_case("extremes_k4096", a, [w], K, THRESH,
              note="max K=4096 (128 words/neuron), single neuron AT threshold (value==THRESH==96)")

    # (c) N=256, K=32 -- max N. 256 DISTINCT weight words via an odd-
    # multiplier LCG (a bijection on 32-bit ints, so any 256-element slice
    # of it is automatically pairwise-distinct) -- word_with_ones/agree_word
    # can only hit 33 distinct agreement counts for K=32, not 256 distinct
    # bit patterns, so this sub-case needs its own construction.
    K, N, THRESH = 32, 256, 0
    a_bits = alt_bits(K)
    a = pack_bits(a_bits)
    C, D = 2654435769, 0x1234567   # C odd => x -> C*x+D is a bijection mod 2**32
    w_list = [[(n * C + D) & 0xFFFFFFFF] for n in range(N)]
    emit_case("extremes_n256", a, w_list, K, THRESH,
              note="max N=256, distinct-by-construction (odd-multiplier LCG bijection) weights")


def gen_neuronorder():
    # neuronorder: N=8, weights constructed so every neuron's raw `value`
    # is pairwise DISTINCT and the fire pattern strictly ALTERNATES
    # (F,.,F,.,...) -- catches the realistic "off-by-one / adjacent-swap"
    # neuron-major addressing bug. See the swap self-check below for the
    # honest limit of this claim (binary output space).
    K, N, THRESH = 16, 8, 0
    a_bits = alt_bits(K)
    a = pack_bits(a_bits)
    agree = [12, 4, 11, 5, 10, 6, 9, 7]   # -> values 8,-8,6,-6,4,-4,2,-2 (alternating)
    assert len(set(agree)) == N
    w_list = [agree_word(a_bits, ag) for ag in agree]
    outs = emit_case("neuronorder", a, w_list, K, THRESH,
                      note="pairwise-distinct values, alternating fire pattern (swap-detection)")

    detected, silent = [], []
    for i in range(N):
        for j in range(i + 1, N):
            swapped = list(w_list)
            swapped[i], swapped[j] = swapped[j], swapped[i]
            swapped_out = xnor_layer(a, swapped, K, THRESH)
            if swapped_out[i] != outs[i] or swapped_out[j] != outs[j]:
                detected.append((i, j))
            else:
                silent.append((i, j))
    # The realistic addressing bug (off-by-one / adjacent shift) swaps
    # NEIGHBOURING neurons -- guarantee every adjacent pair is caught.
    adjacent = [(i, i + 1) for i in range(N - 1)]
    for pair in adjacent:
        assert pair in detected, \
            "neuronorder: adjacent swap %r was NOT detected (silent addressing bug)" % (pair,)
    print("  neuronorder swap self-check: %d/%d neuron-pair swaps change the "
          "observable output (all %d adjacent pairs among them); %d pairs are "
          "SILENT -- both members already share the same fire/not-fire class, "
          "so swapping them is unobservable through the binary +-1 output "
          "alone (a mathematical limit of a 2-valued output with N=8, not a "
          "gap in this test's construction -- see README/report note)."
          % (len(detected), len(detected) + len(silent), len(adjacent), len(silent)))


def main():
    if not os.path.isdir(OUT_DIR):
        os.makedirs(OUT_DIR)

    run_self_tests()

    print("=== gen_xnor_vectors.py -- NPU XNOR/popcount golden vectors (D6/D9/D17) ===\n")

    gen_base()
    gen_tail40()
    gen_tail33()
    gen_tie()
    gen_tie_offlattice()
    gen_extremes()
    gen_neuronorder()

    # Byte-identical proof for the tail40 / tail40_tailalt companion pair
    # (not just list-equality in-process -- actually diff the written files).
    exp_a = os.path.join(OUT_DIR, "npu_xnor_tail40_exp.txt")
    exp_b = os.path.join(OUT_DIR, "npu_xnor_tail40_tailalt_exp.txt")
    with open(exp_a, 'rb') as fa, open(exp_b, 'rb') as fb:
        content_a, content_b = fa.read(), fb.read()
    assert content_a == content_b, \
        "tail40/tail40_tailalt exp files are NOT byte-identical on disk!"
    print("\nByte-identical check: npu_xnor_tail40_exp.txt == "
          "npu_xnor_tail40_tailalt_exp.txt (%d bytes) -- OK" % len(content_a))

    print("\n=== Manifest (%d cases) ===" % len(CASES_MANIFEST))
    total_footprint = 0
    for row in CASES_MANIFEST:
        case, K, N, nw, ivsar, wvsar, ovsar, footprint, fire_pattern, note = row
        total_footprint += footprint
        print("  %-20s K=%-5d N=%-4d words/neuron=%-4d footprint=%-5d fire=[%s]"
              % (case, K, N, nw, footprint, fire_pattern))
    print("\nSum of per-case footprints: %d words (cases are NOT required to "
          "coexist in one image -- each is checked individually against the "
          "%d-word staging RAM; the running allocator additionally proves "
          "the whole set fits non-overlapping if a bench stages them all at "
          "once)." % (total_footprint, RAM_WORDS))
    print("Next free staging-RAM word address: %d / %d" % (alloc.cursor, RAM_WORDS))
    print("\nWrote %d cases to %s" % (len(CASES_MANIFEST), OUT_DIR))


if __name__ == '__main__':
    main()
