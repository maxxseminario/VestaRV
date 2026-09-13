#!/usr/bin/python3.6
"""VestaRV: the random generator's deterministic pseudo-random source.

SplitMix64 in explicit 64-bit ops, not `random`: shuffle, sample and choice have changed
algorithm across CPython releases, so a seed in a reproduction line would stop reproducing.
Nothing in the emission path may call random, hash(), time or os.environ, or iterate an
unordered set or dict, which is why weighted_choice takes an ordered sequence of pairs.
"""

_M64 = (1 << 64) - 1

_GAMMA = 0x9E3779B97F4A7C15
_MIX1 = 0xBF58476D1CE4E5B9
_MIX2 = 0x94D049BB133111EB


class Rng(object):
    """SplitMix64.  Deterministic from `seed` alone."""

    def __init__(self, seed):
        # Accept any int; fold to 64 bits the same way for negatives and for
        # values above 2**64 so that a seed is a seed however it was spelled.
        self._s = int(seed) & _M64

    def next_u64(self):
        self._s = (self._s + _GAMMA) & _M64
        z = self._s
        z = ((z ^ (z >> 30)) * _MIX1) & _M64
        z = ((z ^ (z >> 27)) * _MIX2) & _M64
        return (z ^ (z >> 31)) & _M64

    def next_u32(self):
        return self.next_u64() >> 32

    def below(self, n):
        """Uniform integer in [0, n) with no modulo bias, by rejection sampling on the top bits; `n` must
        be positive. A bare `% n` would skew the low residues and make the class weights subtly wrong
        in a way no test would catch.
        """
        if n <= 0:
            raise ValueError('Rng.below(%r): n must be positive' % (n,))
        if n == 1:
            return 0
        # Largest multiple of n that fits in 64 bits; draws at or above it are
        # rejected and redrawn.
        limit = ((1 << 64) // n) * n
        while True:
            v = self.next_u64()
            if v < limit:
                return v % n

    def between(self, lo, hi):
        """Uniform integer in the INCLUSIVE range [lo, hi]."""
        if hi < lo:
            raise ValueError('Rng.between(%r, %r): empty range' % (lo, hi))
        return lo + self.below(hi - lo + 1)

    def choice(self, seq):
        """Uniform element of an ORDERED sequence (list/tuple only)."""
        if isinstance(seq, (set, frozenset, dict)):
            raise TypeError('Rng.choice needs an ORDERED sequence; a set/dict '
                            'iteration order would leak into the emitted bytes')
        if not seq:
            raise ValueError('Rng.choice: empty sequence')
        return seq[self.below(len(seq))]

    def weighted_choice(self, pairs):
        """Pick from an ordered sequence of (item, weight) pairs. Weights are non-negative ints and a
        zero-weight item is never picked. The argument is a sequence of pairs, never a dict, because
        dict iteration order must not reach an emitted byte.
        """
        if isinstance(pairs, dict):
            raise TypeError('Rng.weighted_choice needs an ordered sequence of '
                            '(item, weight) pairs, not a dict')
        total = 0
        for _item, w in pairs:
            if w < 0:
                raise ValueError('Rng.weighted_choice: negative weight %r' % (w,))
            total += w
        if total <= 0:
            raise ValueError('Rng.weighted_choice: all weights are zero')
        r = self.below(total)
        acc = 0
        for item, w in pairs:
            acc += w
            if r < acc:
                return item
        # Unreachable while the loop above sums to `total`; kept as a loud
        # failure rather than a silent last-item fallback.
        raise AssertionError('weighted_choice fell through (total=%d r=%d)'
                             % (total, r))

    def bool_with(self, num, den):
        """True with probability num/den."""
        return self.below(den) < num
