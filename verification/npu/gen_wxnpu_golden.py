#!/usr/bin/env python3
"""gen_wxnpu_golden.py -- THROWAWAY golden-value generator for the wxnpu.S
firmware smoke (npu_xnor_design.md D10-S5, digperiphs P4.2).

Modeled on gen_wnpuconv_golden.py's shape (same section layout: case params,
staged-word tables in decimal/hex, expected outputs, then an explicit proof
block) but for the XNOR/popcount mode -- so it imports the FROZEN bit-exact
arithmetic straight from gen_xnor_vectors.py (the real D9 bench golden
generator) instead of npu_fixed.py: no MAC/sigmoid here, XNOR is a brand new
integer-only datapath (npu_xnor_design.md D2).

Case: K=40, N=4 (npu_xnor_design.md D10-S5's own suggested shape). K=40 is
DELIBERATE: NW = ceil(40/32) = 2 packed words/neuron, a PARTIAL last word
(40 mod 32 = 8 -> tail_mask = 0xFF, only bits 32-39 of the K-bit stream are
real; bits 40-63, i.e. bits[31:8] of word 1, are unused/garbage-eligible per
neuron AND for the shared activation word). This script stages ADVERSARIAL
garbage in exactly those tail bits (of the activation's word 1 AND of every
neuron's weight word 1) and explicitly proves that an UNMASKED variant of
the DUT (one that forgot D3's tail-mask-on-the-XNOR-result rule and instead
popcounted the full 64 fetched bits before subtracting K) would flip at
least one neuron's fire/no-fire decision relative to the correctly-masked
golden result -- i.e. this is genuinely load-bearing test data, not a
vacuous partial-word case.

Golden semantics reused verbatim from gen_xnor_vectors.py (npu_family_spec.md
D6/D9/D17, npu_xnor_design.md D3/D4): LSB-first packing, popcount(XNOR(a,w))
over exactly the K counted bits (tail-masked on the RESULT), value = 2*pop-K,
fires iff value >= THRESH (signed 32-bit), output word 0x01000000 (+1.0) /
0xFF000000 (-1.0) exact Q7.24 literals.

Run with /usr/bin/python3 (NEVER `python3 -c` -- this machine's default
python3 is the aoj_cal wrapper, which re-evaluates its arguments and STRIPS
QUOTES).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_xnor_vectors import (   # noqa: E402
    alt_bits, pack_bits, agree_word, with_tail_garbage, tail_mask,
    nwords_for_k, bits32, popcount32, popcount_xnor, xnor_layer,
    FIRE, NOT_FIRE,
)

K, N, THRESH = 40, 4, 0
NW = nwords_for_k(K)
assert NW == 2, "K=40 must pack to 2 words/neuron"
MASK_LAST = tail_mask(K)
assert MASK_LAST == 0xFF, "K=40 tail mask must be 0xFF (bits 32-39 counted, 40-63 garbage-eligible)"

print("=== gen_wxnpu_golden.py -- wxnpu.S golden values (D9 xnor_layer arithmetic core) ===")
print("Case: K=%d N=%d THRESH=%d  NW=ceil(K/32)=%d  tail_mask(last word)=0x%02X"
      % (K, N, THRESH, NW, MASK_LAST))

# ---------------------------------------------------------------------------
# Base (clean, tail-zero) activation + per-neuron weight bit vectors, chosen
# for a mixed fire/no-fire pattern well clear of THRESH=0 on the CORRECT
# (masked) semantics -- same idiom as gen_xnor_vectors.py's gen_tail40().
# agree = XNOR-agreement count over the 40 counted bits -> value = 2*agree-40.
# ---------------------------------------------------------------------------
a_bits = alt_bits(K)                    # deterministic 0,1,0,1,... over 40 bits
a_clean = pack_bits(a_bits)             # tail bits (8:31 of word1) are 0 by construction
agree = [30, 10, 25, 15]                # -> values 20, -20, 10, -10
assert len(set(agree)) == N
w_clean = [agree_word(a_bits, ag) for ag in agree]

print("\n-- clean (tail-zero) base vectors, decimal agreement / masked value --")
for n, ag in enumerate(agree):
    val = 2 * ag - K
    print("  neuron %d: agree=%-3d  value=2*%d-%d=%-4d  %s"
          % (n, ag, ag, K, val, "FIRE" if val >= THRESH else "no-fire"))

# ---------------------------------------------------------------------------
# Adversarial tail garbage (npu_xnor_design.md D3/GX1's enforcement target):
# stage nonzero, DISTINCT bit patterns in the unused bits [31:8] of word 1,
# for BOTH the shared activation and every neuron's weight -- chosen so the
# FULLY-MATCHED case (neuron 3, agree=15, value=-10, the closest-to-threshold
# neuron) has activation tail == weight tail (XNOR=1 on all 24 tail bits),
# maximizing the popcount inflation an unmasked DUT would see there. The
# other three neurons get different, non-matching tail fills (still
# realistic "arbitrary garbage", just not engineered to flip).
# ---------------------------------------------------------------------------
A_TAIL_GARBAGE = 0xABCD1234
W_TAIL_GARBAGE = {
    0: 0x5A5A5A5A,   # neuron 0 (agree=30, value=20): unrelated garbage
    1: 0x0F0F0F0F,   # neuron 1 (agree=10, value=-20): unrelated garbage
    2: 0xDEADBEEF,   # neuron 2 (agree=25, value=10): unrelated garbage
    3: 0xABCD1234,   # neuron 3 (agree=15, value=-10): MATCHES a's tail exactly
}

a_words = with_tail_garbage(a_clean, K, A_TAIL_GARBAGE)
w_words = [with_tail_garbage(w_clean[n], K, W_TAIL_GARBAGE[n]) for n in range(N)]

print("\n-- staged words (word0/word1 per vector; decimal / 32-bit hex) --")
print("  activation (shared, IVSAR):")
for i, w in enumerate(a_words):
    print("    a_words[%d] = %-12d  0x%08X" % (i, bits32(w), bits32(w)))
for n in range(N):
    print("  neuron %d weight (WVSAR + %d*%d):" % (n, n, NW))
    for i, w in enumerate(w_words[n]):
        print("    w_words[%d][%d] = %-12d  0x%08X" % (n, i, bits32(w), bits32(w)))

# ---------------------------------------------------------------------------
# Correct (masked) golden result -- the actual npu_xnor_design.md D3/D4
# semantics, via the real bench library function.
# ---------------------------------------------------------------------------
masked_pop = [popcount_xnor(a_words, w_words[n], K) for n in range(N)]
masked_out = xnor_layer(a_words, w_words, K, THRESH)
fires = sum(1 for o in masked_out if o == FIRE)
assert 0 < fires < N, "degenerate fire pattern -- not a mix"

print("\n-- CORRECT (masked, K=%d counted bits) result --" % K)
for n in range(N):
    val = 2 * masked_pop[n] - K
    print("  neuron %d: pop=%-3d value=%-4d  out=0x%08X (%s)"
          % (n, masked_pop[n], val, bits32(masked_out[n]),
             "FIRE" if masked_out[n] == FIRE else "no-fire"))


# ---------------------------------------------------------------------------
# UNMASKED variant: simulate a DUT that forgot D3's tail mask and popcounts
# ALL 64 fetched bits (both packed words in full) before computing
# value = 2*pop_unmasked - K. This is the exact failure mode D3/GX1 warn
# about -- proves the staged garbage is load-bearing, not decorative.
# ---------------------------------------------------------------------------
def popcount_xnor_unmasked(a_w, w_w):
    pop = 0
    for i in range(len(a_w)):
        x = bits32(~(bits32(a_w[i]) ^ bits32(w_w[i])))
        pop += popcount32(x)
    return pop


unmasked_pop = [popcount_xnor_unmasked(a_words, w_words[n]) for n in range(N)]
unmasked_val = [2 * unmasked_pop[n] - K for n in range(N)]
unmasked_out = [FIRE if v >= THRESH else NOT_FIRE for v in unmasked_val]

print("\n-- UNMASKED (bug-simulation: full 64-bit popcount, K left at %d) result --" % K)
for n in range(N):
    print("  neuron %d: pop_unmasked=%-3d value=%-4d  out=0x%08X (%s)"
          % (n, unmasked_pop[n], unmasked_val[n], bits32(unmasked_out[n]),
             "FIRE" if unmasked_out[n] == FIRE else "no-fire"))

print("\n-- unmasked-differs proof (npu_xnor_design.md D3/GX1 enforcement) --")
diffs = [n for n in range(N) if masked_out[n] != unmasked_out[n]]
assert diffs, ("staged garbage is NOT load-bearing -- masked and unmasked "
               "variants agree on every neuron!")
for n in diffs:
    print("  PROOF: neuron %d flips -- masked=%s (value=%d) vs unmasked=%s (value=%d)"
          % (n, "FIRE" if masked_out[n] == FIRE else "no-fire", 2 * masked_pop[n] - K,
             "FIRE" if unmasked_out[n] == FIRE else "no-fire", unmasked_val[n]))
print("  %d/%d neuron(s) flip between the correctly-masked golden result and "
      "the unmasked-bug simulation -- an unmasked DUT would FAIL this test."
      % (len(diffs), N))

# ---------------------------------------------------------------------------
# Negative-structure survival hex (inputs/weights are read-only to the
# accelerator; only the output words are written).
# ---------------------------------------------------------------------------
print("\n-- operand survival hex (for the 'unchanged after run' negative-structure check) --")
print("  (same staged words printed above -- activation/weight staging RAM")
print("   is never written by the accelerator; only OUT_ADDR is written)")

print("\nDone. masked_out (hex) = %s" % ["0x%08X" % bits32(v) for v in masked_out])
print("K=%d N=%d THRESH=%d  NW=%d  IVSAR/WVSAR/OVSAR are wxnpu.S's own choice "
      "(0x1C0/0x1D0/0x1E0), not this script's" % (K, N, THRESH, NW))
