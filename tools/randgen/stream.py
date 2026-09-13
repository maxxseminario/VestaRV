#!/usr/bin/python3.6
"""VestaRV: build one constrained-random RV32 instruction stream.

A trap is terminal on a default build, so it hangs rather than fails and generate-then-check
is unavailable. Every trap source is removed by construction: only mnemonics isa_model says
the config implements; every memory access is off(base) on one of two reserved registers into
a guard-bracketed scratch block; branches and jal are forward only, so the body is a DAG.
"""

import isa_model

# Register discipline.  x-numbers, not ABI names: the emitted text is meant to
# be read against the census output, and `x9` is unambiguous where `s1` is not.
R_ZERO = 0
R_RA = 1        # reserved: subroutine link, written only by `jal x1`
R_SP = 2        # reserved: 0xBFF0.  MUST be valid before ANY interrupt --
                #           hardware pushes the return PC at sp-4 (M5b).
R_GP = 3        # reserved: the env's TESTNUM
R_BASE_A = 8    # reserved: &k3_scratch
R_BASE_B = 9    # reserved: &k3_scratch + 128
R_A0 = 10       # reserved: riscv_tb watches a0 for CAFEBABE/DEADBEEF

RESERVED = (R_ZERO, R_RA, R_SP, R_GP, R_BASE_A, R_BASE_B, R_A0)
POOL = tuple([r for r in range(1, 32) if r not in RESERVED])

# Scratch geometry.  64-byte-aligned and 64-byte-guarded on both sides so that
# a Zicboz-bearing config can later use it unchanged (cbo.zero's block is 64 B,
# constants.vhd:158-159).
GUARD_WORDS = 16
SCRATCH_WORDS = 64
SCRATCH_BYTES = SCRATCH_WORDS * 4          # 256
BASE_B_OFF = SCRATCH_BYTES // 2            # 128

# The last two scratch words are RESERVED and excluded from every random
# offset window.  `ARMED_OFF` holds the DYNAMIC count of IRQ arm sites actually
# executed -- see `_e_clint_irq` for why a static count is the wrong thing to
# assert.  Reserved rather than allocated elsewhere because the census range
# forbids pseudo-instructions, so a counter the body must reach has to be
# addressable as `off(base)` with no `la`.
ARMED_OFF = SCRATCH_BYTES - 8              # 248
RESERVED_TAIL = 8
USABLE_BYTES = SCRATCH_BYTES - RESERVED_TAIL   # 248 bytes of random window
GUARD_LO_MAGIC = 0x6C0F0000
GUARD_HI_MAGIC = 0x81DE0000

SP_INIT = 0xBFF0
CLINT_MSIP0 = 0x5000

# Minimum number of emitted instructions between two IRQ arm sites.  Not a
# calibrated delay, since a test must never be tuned to land on an
# instruction): it exists only so that two interrupts cannot plausibly coalesce
# into one, which would make the epilogue's exact-count assertion wrong for a
# benign reason.
IRQ_MIN_GAP = 12

# How far ahead a conditional branch may aim.  See `_resolve_branches` for the
# measurement that fixed this at 2 rather than "any later label".
BRANCH_TARGET_WINDOW = 2


# K5 queue item 4 -- geometry and encoders for the five new classes.
#
# EVERY NUMBER BELOW IS DERIVED FROM SOMETHING, and the derivation is written
# next to it.  The one that matters most is CBOZ_MAX_OFF: it is not a tuned
# value, it is the largest offset for which the RTL's rounded-down 64-byte
# block is still a subset of the scratch window.
CBOZ_BLOCK_BYTES = 64                       # constants.vhd CBOZ_BLOCK_SIZE
# The block base is `rs1 and not 63` and the block runs 64 bytes from there, so
# an offset `off` writes scratch bytes [off & ~63, (off & ~63) + 64).  The
# largest `off` whose block stays inside [0, SCRATCH_BYTES - RESERVED_TAIL) is
# the last byte of the last WHOLE block below the reserved tail.  With
# SCRATCH_BYTES = 256 and RESERVED_TAIL = 8 that is block 2, i.e. offsets up to
# 191.  Computed rather than written as 191 so a scratch-geometry change moves
# it automatically instead of silently invalidating the argument.
CBOZ_MAX_OFF = (((SCRATCH_BYTES - RESERVED_TAIL) // CBOZ_BLOCK_BYTES)
                * CBOZ_BLOCK_BYTES) - 1

# Zihintntl: the hint IS the rs2 specifier of `add x0, x0, rs2`.
ZIHINT_NTL_RS2 = {'ntl.p1': 2, 'ntl.pall': 3, 'ntl.s1': 4, 'ntl.all': 5}

# Zcmp rlist: 4 = {ra}, 5 = {ra,s0}, ... 14 = {ra,s0-s9}, 15 = {ra,s0-s11}.
# Values 0-3 are illegal and c_dec.vhd refuses them explicitly.  The generator
# starts at 7 = {ra,s0-s2} so that at least ONE pushed register (s2 = x18) is an
# ordinary POOL register the template can clobber between push and pop -- with a
# smaller list the pop would restore only reserved registers and would be
# unobservable, which is exactly the K4-L3 "cm.pop UNVERIFIED" hole.
ZCMP_RLIST_MIN = 7
ZCMP_RLIST_MAX = 15
# cm.jt takes index 0..31 (no link); cm.jalt takes 32..255 (links ra).
ZCMT_JT_LINK_BASE = 32
ZCMT_JT_ENTRIES = 64                        # table words emitted; 0..63


def zcmp_pushed_regs(rlist):
    """The x-numbers `cm.push rlist` saves, in spec order, mirroring vesta.vhd's zcm_reg_at:
    position 0 is x1, 1 is x8, 2 is x9 and p >= 3 is x(15+p). Written from the spec here and
    checked against the directed tests' literals by test_randgen.py.
    """
    n = 13 if rlist == 15 else rlist - 3
    out = []
    for p in range(n):
        if p == 0:
            out.append(1)
        elif p == 1:
            out.append(8)
        elif p == 2:
            out.append(9)
        else:
            out.append(15 + p)
    return out


def zcmp_stack_adj(rlist, spimm):
    """RV32 stack_adj = base(rlist) + 16*spimm.  Mirrors `zcm_stackadj`."""
    if rlist <= 7:
        base = 16
    elif rlist <= 11:
        base = 32
    elif rlist <= 14:
        base = 48
    else:
        base = 64
    return base + 16 * spimm


def zcmp_rlist_text(rlist):
    regs = zcmp_pushed_regs(rlist)
    return '{%s}' % ','.join('x%d' % r for r in regs)


def zcmp_push_pop_word(is_push, rlist, spimm):
    """The 16-bit cm.push/cm.pop encoding: C2 quadrant, funct3 101, bit 12 set, bits 11 and 8 fixed
    as c_dec.vhd requires, bits 10:9 the operation, 7:4 rlist, 3:2 spimm[5:4]. gas and objdump
    2.41 handle neither, so extzcmp.S's two literals are the only third party and are asserted.
    """
    if not 4 <= rlist <= 15:
        raise StreamBuildError('rlist %d is illegal (c_dec refuses 0-3)' % rlist)
    if not 0 <= spimm <= 3:
        raise StreamBuildError('spimm %d does not fit 2 bits' % spimm)
    w = 0x2                       # bits 1:0 = 10 (C2)
    w |= 0x5 << 13                # funct3 = 101
    w |= 1 << 12                  # push/pop family
    w |= 1 << 11                  # required
    w |= (0 if is_push else 1) << 9   # 00 push / 01 pop
    w |= (rlist & 0xF) << 4
    w |= (spimm & 0x3) << 2
    return w


def zcmt_word(index):
    """The 16-bit `cm.jt`/`cm.jalt` encoding: C2, funct3 101, 12:10 = 000,
    index at bits 9:2.  Validated against `extzcmt.S`'s 0xA016 (index 5)."""
    if not 0 <= index <= 255:
        raise StreamBuildError('cm.jt index %d does not fit 8 bits' % index)
    return 0x2 | (0x5 << 13) | ((index & 0xFF) << 2)


class Insn(object):
    __slots__ = ('cls', 'text')

    def __init__(self, cls, text):
        self.cls = cls
        self.text = text


class Label(object):
    __slots__ = ('name',)

    def __init__(self, name):
        self.name = name


class BranchTo(object):
    """A conditional branch whose target label is resolved after placement."""
    __slots__ = ('cls', 'prefix', 'target')

    def __init__(self, cls, prefix):
        self.cls = cls
        self.prefix = prefix
        self.target = None

    @property
    def text(self):
        if self.target is None:
            raise AssertionError('unresolved branch target')
        return '%s, %s' % (self.prefix, self.target)


# Profiles.  A profile is an ORDERED sequence of (class, weight) pairs; order
# reaches the emitted bytes through `Rng.weighted_choice`, so it is part of the
# generator contract.  Classes the config cannot supply are dropped and the
# remaining weights renormalise by themselves (weighted_choice sums what it is
# given).
#
# The sequencer weighting is `core_rtl_roadmap.md` Step 2's, read against the
# resolved config: of the six classes it names, only `div`, `amo` and `lrsc`
# exist on a default build -- Zcmp/Zcmt, Zicboz and Zfinx are OFF.  The
# generator does not pretend otherwise; `blocked_classes` in the manifest says
# so per stream.
PROFILES = {
    # 'base' -- flat-ish, for shaking out the emitter itself.
    'base': (
        ('alu_reg', 20), ('alu_imm', 20), ('lui', 4), ('auipc', 3),
        ('branch', 8), ('jal', 3), ('load', 10), ('store', 10),
        ('fence', 1), ('mul', 4), ('div', 4), ('amo', 4), ('lrsc', 3),
        ('zba', 3), ('zbb', 6), ('zbs', 4), ('zbc', 2), ('zfinx', 6),
        ('clint_irq', 0),
        # K5 v1.3.0: APPENDED, never interleaved.  On a config whose knob is
        # off each of these is dropped by `available_classes` before
        # `weighted_choice` ever sees it, so the weight list this profile
        # consumes on the DEFAULT config is character-for-character the v1.2.0
        # one and every default-config stream regenerates with a byte-identical
        # BODY.  That is checked, not asserted -- see the item-4 report.
        ('zicboz', 3), ('zawrs', 3), ('zihint', 3), ('zcmp', 3), ('zcmt', 3),
    ),
    # 'seq' -- the roadmap Step 2 weighting: the multi-cycle sequencers.
    'seq': (
        ('alu_reg', 8), ('alu_imm', 8), ('lui', 2), ('auipc', 2),
        ('branch', 5), ('jal', 2), ('load', 6), ('store', 6),
        ('fence', 1), ('mul', 10), ('div', 22), ('amo', 20), ('lrsc', 14),
        ('zba', 1), ('zbb', 2), ('zbs', 1), ('zbc', 1), ('zfinx', 14),
        ('clint_irq', 0),
        # K5 v1.3.0, appended (see 'base').  `zicboz`, `zcmp` and `zcmt` are
        # MULTI-CYCLE SEQUENCERS -- a 16-store burst, a 13-register frame pair
        # and a table-load redirect -- so they belong in the sequencer profile
        # on the same argument that put `div`/`amo`/`lrsc` here.  `zawrs` and
        # `zihint` are single-decode and get the base weight.
        ('zicboz', 10), ('zawrs', 4), ('zihint', 4), ('zcmp', 12), ('zcmt', 8),
    ),
    # 'irq' -- 'seq' plus CLINT self-injection immediately ahead of a sequencer.
    'irq': (
        ('alu_reg', 8), ('alu_imm', 8), ('lui', 2), ('auipc', 2),
        ('branch', 5), ('jal', 2), ('load', 6), ('store', 6),
        ('fence', 1), ('mul', 8), ('div', 18), ('amo', 16), ('lrsc', 12),
        ('zba', 1), ('zbb', 2), ('zbs', 1), ('zbc', 1), ('zfinx', 10),
        ('clint_irq', 9),
    ),
    # 'bitm' -- Zb-heavy, the widest single-cycle decode surface.
    'bitm': (
        ('alu_reg', 8), ('alu_imm', 8), ('lui', 3), ('auipc', 2),
        ('branch', 5), ('jal', 2), ('load', 5), ('store', 5),
        ('fence', 1), ('mul', 3), ('div', 3), ('amo', 3), ('lrsc', 2),
        ('zba', 12), ('zbb', 24), ('zbs', 16), ('zbc', 10), ('zfinx', 0),
        ('clint_irq', 0),
    ),
    # 'zext'.  The DEMONSTRATION profile for the five classes
    # once dropped from the campaign: dense enough that one stream of a
    # few hundred instructions carries tens of sites of its config's class, and
    # a base-ISA spine so the stream is still a stream (branches, loads, stores,
    # a subroutine) rather than a straight run of one encoding.
    #
    # `clint_irq` is 0 ON PURPOSE and the reason is measured, not stylistic:
    # `cbo.zero`'s 16-store burst is UNINTERRUPTIBLE in the RTL (CBOZ_WRITE has
    # no irq_save term), and `cm.push`/`cm.pop` walk the stack that IRQ_SV
    # pushes onto.  Mixing self-injected interrupts into the first stream that
    # ever exercises either sequencer would confound two new things at once.
    # That combination is a K7 candidate, named here rather than left implicit.
    #
    # On a config with none of the five knobs on, this profile degrades to its
    # base-ISA spine and the manifest's `blocked_classes` says exactly which
    # five were dropped and why -- a legal stream that covers none of what it
    # was aimed at, and says so.
    'zext': (
        ('alu_reg', 10), ('alu_imm', 10), ('lui', 2), ('auipc', 2),
        ('branch', 5), ('jal', 2), ('load', 6), ('store', 6),
        ('fence', 1), ('mul', 3), ('div', 3), ('amo', 3), ('lrsc', 3),
        ('zba', 1), ('zbb', 2), ('zbs', 1), ('zbc', 1), ('zfinx', 2),
        ('clint_irq', 0),
        ('zicboz', 24), ('zawrs', 24), ('zihint', 24), ('zcmp', 24),
        ('zcmt', 24),
    ),
}
PROFILE_ORDER = ('base', 'seq', 'irq', 'bitm', 'zext')

# The classes an IRQ arm may be placed immediately in front of.  `lrsc` is
# EXCLUDED and the exclusion is the interesting part: the reference's ISR window
# is bracketed out (V3 BRACKET_ISR), so the reference never executes the
# handler and its reservation survives, while the RTL's handler does real
# loads/stores and may kill the reservation.  That is a HARNESS asymmetry, not
# an RTL finding, and a generator that produced it would be manufacturing false
# divergences.  Named here rather than discovered later.
IRQ_TARGET_CLASSES = ('div', 'amo', 'mul')


class StreamBuildError(Exception):
    pass


class StreamBuilder(object):

    # Deliberate discipline violations, used ONLY to make the epilogue's guard
    # checks fire, a detector never seen to fail proving
    # nothing.  These are NOT the spec's acceptance mutants --
    # those target the generator's LEGALITY and are authored by a second agent
    # that has not seen this code.  Each is placed immediately before
    # `.Lk3_body_end`, the one point every path in the DAG converges on, so
    # that it cannot be branched over.
    NEGCTRL = {
        'escape-store': 'one store 4 bytes past the end of the scratch window, '
                        'into k3_guard_hi[0]',
        'clobber-base': 'one addi that moves scratch base A',
    }

    def __init__(self, cfg, seed, profile, length, rng,
                 allow_unmodelled=False, negctrl=None):
        if negctrl is not None and negctrl not in self.NEGCTRL:
            raise StreamBuildError('unknown negative control %r (have: %s)'
                                   % (negctrl, ', '.join(sorted(self.NEGCTRL))))
        self.negctrl = negctrl
        if profile not in PROFILES:
            raise StreamBuildError('unknown profile %r (have: %s)'
                                   % (profile, ', '.join(PROFILE_ORDER)))
        self.cfg = cfg
        self.seed = seed
        self.profile = profile
        self.length = int(length)
        self.rng = rng
        self.available, self.blocked = isa_model.available_classes(
            cfg.isa, allow_unmodelled=allow_unmodelled)
        self.no_emitter = isa_model.knobs_on_without_emitter(cfg.isa, cfg.priv)
        self.items = []
        self.subs = []            # (label, [Insn...]) subroutine bodies
        self.branches = []        # (index_in_items, BranchTo)
        self.labels = []          # (index_in_items, name)
        self.irq_sites = 0
        self.last_irq_at = -10 ** 9
        self._nlab = 0
        self._nsub = 0
        # K5: the Zcmt jump-vector table this stream needs.  (index, label)
        # pairs, filled by `_e_zcmt` and rendered by `emit.render`.  Kept on the
        # builder rather than in the emitter so the ONE place that knows what a
        # stream contains stays one place -- the same correction §4 of the K3
        # report records for the subroutine block.
        self.jt_entries = []
        self._njt = 0
        self._njalt = 0
        # The `.option arch, +X` fragments the census range needs for the
        # classes this config can actually emit.  Derived, never guessed: the
        # rv32uk group's -march is fixed in verification/isa/Makefile and cannot
        # follow a config, so the arch travels inside the stream.
        self.arch_frags = isa_model.arch_fragments(cfg.isa, self.available)
        weights = [(c, w) for (c, w) in PROFILES[profile]
                   if c in self.available and w > 0]
        if not weights:
            raise StreamBuildError(
                'profile %r has no usable class on this config (%s)'
                % (profile, cfg.knob_line()))
        self.weights = weights

    # -- small helpers
    def _r(self):
        return self.rng.choice(POOL)

    def _r_not(self, *excl):
        for _ in range(64):
            r = self.rng.choice(POOL)
            if r not in excl:
                return r
        raise StreamBuildError('could not draw a distinct pool register')

    def _label(self, kind='L'):
        self._nlab += 1
        return '.Lk3_%s%d' % (kind, self._nlab)

    def _emit(self, cls, text):
        self.items.append(Insn(cls, text))

    def _base_and_window(self):
        """Pick a scratch base register and its legal byte-offset window."""
        if self.rng.bool_with(1, 2):
            return R_BASE_A, 0, USABLE_BYTES - 1
        return R_BASE_B, -BASE_B_OFF, USABLE_BYTES - BASE_B_OFF - 1

    def _off(self, lo, hi, align, width):
        """A byte offset in [lo, hi] with `align` and room for `width` bytes."""
        top = hi - (width - 1)
        n_lo = -((-lo) // align) if lo < 0 else ((lo + align - 1) // align)
        n_hi = top // align if top >= 0 else -((-top + align - 1) // align)
        if n_hi < n_lo:
            raise StreamBuildError('empty offset window')
        return self.rng.between(n_lo, n_hi) * align

    # -- per-class emitters
    def _e_alu_reg(self):
        m = self.rng.choice(isa_model.M_ALU_REG)
        self._emit('alu_reg', '%-8s x%d, x%d, x%d'
                   % (m, self._r(), self._r(), self._r()))

    def _e_alu_imm(self):
        if self.rng.bool_with(1, 3):
            m = self.rng.choice(isa_model.M_ALU_SHIMM)
            self._emit('alu_imm', '%-8s x%d, x%d, %d'
                       % (m, self._r(), self._r(), self.rng.between(0, 31)))
        else:
            m = self.rng.choice(isa_model.M_ALU_IMM)
            self._emit('alu_imm', '%-8s x%d, x%d, %d'
                       % (m, self._r(), self._r(), self.rng.between(-2048, 2047)))

    def _e_lui(self):
        self._emit('lui', '%-8s x%d, %d' % ('lui', self._r(),
                                            self.rng.between(0, 0xFFFFF)))

    def _e_auipc(self):
        self._emit('auipc', '%-8s x%d, %d' % ('auipc', self._r(),
                                              self.rng.between(0, 0xFFFFF)))

    def _e_branch(self):
        m = self.rng.choice(isa_model.M_BRANCH)
        b = BranchTo('branch', '%-8s x%d, x%d' % (m, self._r(), self._r()))
        self.branches.append((len(self.items), b))
        self.items.append(b)

    def _e_jal(self):
        """A forward call into a subroutine that returns.  Emits `jal` here and
        parks the body (ending in `jalr x0, 0(ra)`) in the subroutine block."""
        self._nsub += 1
        lab = '.Lk3_sub%d' % self._nsub
        self._emit('jal', '%-8s x%d, %s' % ('jal', R_RA, lab))
        body = []
        for _ in range(self.rng.between(2, 4)):
            m = self.rng.choice(isa_model.M_ALU_REG)
            body.append(Insn('alu_reg', '%-8s x%d, x%d, x%d'
                             % (m, self._r(), self._r(), self._r())))
        body.append(Insn('jalr', '%-8s x%d, 0(x%d)' % ('jalr', R_ZERO, R_RA)))
        self.subs.append((lab, body))

    def _e_load(self):
        m = self.rng.choice(isa_model.M_LOAD)
        width = {'lb': 1, 'lbu': 1, 'lh': 2, 'lhu': 2, 'lw': 4}[m]
        base, lo, hi = self._base_and_window()
        off = self._off(lo, hi, width, width)
        self._emit('load', '%-8s x%d, %d(x%d)' % (m, self._r(), off, base))

    def _e_store(self):
        m = self.rng.choice(isa_model.M_STORE)
        width = {'sb': 1, 'sh': 2, 'sw': 4}[m]
        base, lo, hi = self._base_and_window()
        off = self._off(lo, hi, width, width)
        self._emit('store', '%-8s x%d, %d(x%d)' % (m, self._r(), off, base))

    def _e_fence(self):
        self._emit('fence', '%-8s iorw, iorw' % 'fence')

    def _e_mul(self):
        m = self.rng.choice(isa_model.M_MUL)
        self._emit('mul', '%-8s x%d, x%d, x%d'
                   % (m, self._r(), self._r(), self._r()))

    def _e_div(self):
        """Divide, with both architecturally-defined edge cases deliberately reachable: x/0 yields
        all-ones and INT_MIN/-1 yields INT_MIN, neither traps, and both sides model both, so they are
        free coverage of the DIV sequencer's early-out paths.
        """
        m = self.rng.choice(isa_model.M_DIV)
        rd, rs1, rs2 = self._r(), self._r(), self._r()
        pick = self.rng.below(8)
        if pick == 0:                       # divisor = 0
            rs2 = self._r_not(rs1)
            self._emit('alu_imm', '%-8s x%d, x%d, 0' % ('addi', rs2, R_ZERO))
        elif pick == 1:                     # INT_MIN / -1
            rs1 = self._r()
            rs2 = self._r_not(rs1)
            self._emit('lui', '%-8s x%d, %d' % ('lui', rs1, 0x80000))
            self._emit('alu_imm', '%-8s x%d, x%d, -1' % ('addi', rs2, R_ZERO))
        self._emit('div', '%-8s x%d, x%d, x%d' % (m, rd, rs1, rs2))

    def _amo_addr_reg(self, excl=()):
        """Materialise a word-aligned in-window scratch address in a pool register. RV32A has no offset
        field, so varying the address needs a real addi; it is emitted immediately before its
        consumer so nothing can overwrite it in between.
        """
        base, lo, hi = self._base_and_window()
        off = self._off(lo, hi, 4, 4)
        rt = self._r_not(*excl)
        self._emit('alu_imm', '%-8s x%d, x%d, %d' % ('addi', rt, base, off))
        return rt

    def _e_amo(self):
        m = self.rng.choice(isa_model.M_AMO)
        rt = self._amo_addr_reg()
        rd = self._r_not(rt)
        rs2 = self._r_not(rt)
        self._emit('amo', '%-8s x%d, x%d, (x%d)' % (m, rd, rs2, rt))

    def _e_lrsc(self):
        """An immediately adjacent lr.w / sc.w pair and nothing else. A locally-failed SC is not emitted,
        because whether a same-hart store kills a reservation is implementation-defined and the two
        models may legitimately disagree; nothing may sit between the pair, and no label may either.
        """
        rt = self._amo_addr_reg()
        rd = self._r_not(rt)
        rd2 = self._r_not(rt, rd)
        rs2 = self._r_not(rt)
        self._emit('lrsc', '%-8s x%d, (x%d)' % ('lr.w', rd, rt))
        self._emit('lrsc', '%-8s x%d, x%d, (x%d)' % ('sc.w', rd2, rs2, rt))

    def _e_zba(self):
        m = self.rng.choice(isa_model.M_ZBA)
        self._emit('zba', '%-8s x%d, x%d, x%d'
                   % (m, self._r(), self._r(), self._r()))

    def _e_zbb(self):
        pick = self.rng.below(10)
        if pick < 5:
            m = self.rng.choice(isa_model.M_ZBB_R)
            self._emit('zbb', '%-8s x%d, x%d, x%d'
                       % (m, self._r(), self._r(), self._r()))
        elif pick < 9:
            m = self.rng.choice(isa_model.M_ZBB_UN)
            self._emit('zbb', '%-8s x%d, x%d' % (m, self._r(), self._r()))
        else:
            m = self.rng.choice(isa_model.M_ZBB_IMM)
            self._emit('zbb', '%-8s x%d, x%d, %d'
                       % (m, self._r(), self._r(), self.rng.between(1, 31)))

    def _e_zbs(self):
        if self.rng.bool_with(1, 2):
            m = self.rng.choice(isa_model.M_ZBS_R)
            self._emit('zbs', '%-8s x%d, x%d, x%d'
                       % (m, self._r(), self._r(), self._r()))
        else:
            m = self.rng.choice(isa_model.M_ZBS_IMM)
            self._emit('zbs', '%-8s x%d, x%d, %d'
                       % (m, self._r(), self._r(), self.rng.between(0, 31)))

    def _e_zbc(self):
        m = self.rng.choice(isa_model.M_ZBC)
        self._emit('zbc', '%-8s x%d, x%d, x%d'
                   % (m, self._r(), self._r(), self._r()))

    def _e_zfinx(self):
        """One Zfinx single-precision op on pool registers, whose seeded integer values are reinterpreted
        as float bit patterns, so NaNs and subnormals arrive for free. Nothing here can trap: an IEEE
        exception sets a sticky fflags bit. Judgeable only with the zfinx-fflags amendment.
        """
        if self.rng.bool_with(1, 3):
            m = self.rng.choice(isa_model.M_ZFINX_UN)
            self._emit('zfinx', '%-8s x%d, x%d' % (m, self._r(), self._r()))
        else:
            m = self.rng.choice(isa_model.M_ZFINX_R)
            self._emit('zfinx', '%-8s x%d, x%d, x%d'
                       % (m, self._r(), self._r(), self._r()))

    # K5 queue item 4 -- the five emitter-less state-bearing Z rows.
    # Each one's SAFETY argument is structural, in the sense the module
    # docstring means: the trap/hang source is removed by construction rather
    # than checked afterwards, because a trap is TERMINAL on a default build.
    def _e_zicboz(self):
        """One `cbo.zero` on a block that is a subset of the scratch window. The RTL rounds rs1 down to
        the block size, so the bound is taken on the offset: k3_scratch is .align 6 and an offset in
        [0, CBOZ_MAX_OFF] puts every block clear of the guard bands and the reserved tail.
        """
        off = self.rng.between(0, CBOZ_MAX_OFF)
        rt = self._r()
        self._emit('alu_imm', '%-8s x%d, x%d, %d' % ('addi', rt, R_BASE_A, off))
        self._emit('zicboz', '%-8s (x%d)' % ('cbo.zero', rt))

    def _e_zawrs(self):
        """One `wrs.nto` or `wrs.sto` at a site where it cannot park. wrs.nto has no timeout arm, so the
        only structural guarantee is resv_valid_ext = '0'; that holds because lr.w is emitted only as
        an adjacent lr/sc pair no branch can enter, and sc.w clears the reservation either way.
        """
        m = 'wrs.sto' if self.rng.bool_with(1, 3) else 'wrs.nto'
        self._emit('zawrs', '%s' % m)

    def _e_zihint(self):
        """`pause`, or one of the four `ntl` hints. Both are architectural NOPs in either polarity of the
        knob, so the class is suite-only; what it buys is decode-surface coverage of two encodings
        inside spaces the core decodes for other purposes. The ntl rs2 must be x2 to x5.
        """
        if self.rng.bool_with(1, 2):
            self._emit('zihint', 'pause')
        else:
            hint = self.rng.choice(('ntl.p1', 'ntl.pall', 'ntl.s1', 'ntl.all'))
            self._emit('zihint', '%-8s x%d, x%d, x%d   # %s'
                       % ('add', R_ZERO, R_ZERO, ZIHINT_NTL_RS2[hint], hint))

    def _e_zcmp(self):
        """One balanced cm.push / cm.pop frame as one template, encoded here as .short since gas 2.41
        has no cm.* mnemonic. Push and pop carry the same rlist and spimm so sp survives, and the
        intermediate clobber is drawn only from pool registers, so the pop's loads are verifiable.
        """
        rlist = self.rng.between(ZCMP_RLIST_MIN, ZCMP_RLIST_MAX)
        spimm = self.rng.below(4)
        self._emit('zcmp', '.short 0x%04X   # cm.push %s, -%d'
                   % (zcmp_push_pop_word(True, rlist, spimm),
                      zcmp_rlist_text(rlist), zcmp_stack_adj(rlist, spimm)))
        pushed = [r for r in zcmp_pushed_regs(rlist) if r in POOL]
        for _ in range(self.rng.between(1, 2)):
            if not pushed:
                break
            r = self.rng.choice(pushed)
            self._emit('alu_imm', '%-8s x%d, x%d, %d'
                       % ('addi', r, r, self.rng.between(-2048, 2047)))
        self._emit('zcmp', '.short 0x%04X   # cm.pop %s, %d'
                   % (zcmp_push_pop_word(False, rlist, spimm),
                      zcmp_rlist_text(rlist), zcmp_stack_adj(rlist, spimm)))

    def _e_zcmt(self):
        """One `cm.jt` or `cm.jalt` through the jump-vector table. Both are real control transfers, so
        the DAG is preserved by where the table points: a cm.jt entry holds the address of the next
        instruction, unregistered as a label, and a cm.jalt entry a subroutine ending in jalr x0.
        """
        if self.rng.bool_with(1, 2) and self._njt < ZCMT_JT_LINK_BASE:
            # cm.jt: aim the entry at the next instruction.  The index counter
            # is SEPARATE from the jalt one -- a shared counter would have let a
            # jalt site push a later cm.jt past index 31 and turn it into a
            # linking jump, changing the instruction the manifest claims.
            idx = self._njt
            self._njt += 1
            lab = '.Lk3_jt%d' % idx
            self.jt_entries.append((idx, lab))
            self._emit('zcmt', '.short 0x%04X   # cm.jt %d -> %s'
                       % (zcmt_word(idx), idx, lab))
            self.items.append(Label(lab))     # NOT in self.labels: unbranchable
        else:
            self._nsub += 1
            sub = '.Lk3_jsub%d' % self._nsub
            idx = ZCMT_JT_LINK_BASE + self._njalt
            if idx > 255:
                raise StreamBuildError(
                    'cm.jalt index %d exceeds the 8-bit table index; this '
                    'stream asks for more than %d linking table jumps'
                    % (idx, 255 - ZCMT_JT_LINK_BASE))
            self._njalt += 1
            self.jt_entries.append((idx, sub))
            self._emit('zcmt', '.short 0x%04X   # cm.jalt %d -> %s'
                       % (zcmt_word(idx), idx, sub))
            body = []
            for _ in range(self.rng.between(2, 4)):
                m = self.rng.choice(isa_model.M_ALU_REG)
                body.append(Insn('alu_reg', '%-8s x%d, x%d, x%d'
                                 % (m, self._r(), self._r(), self._r())))
            body.append(Insn('jalr', '%-8s x%d, 0(x%d)'
                             % ('jalr', R_ZERO, R_RA)))
            self.subs.append((sub, body))

    def _e_clint_irq(self):
        """Raise msip[0], a level interrupt on an always-enabled CLINT slot. Only a store is emitted,
        never a load, since afterwards the RTL's CLINT holds 0 and the reference's memory 1. Each arm
        bumps a reserved scratch word, because forward branches skip arm sites.
        """
        rt = self._r()
        rv = self._r_not(rt)
        # armed += 1, in the reserved scratch word (base A, fixed offset).
        ra = self._r_not(rt, rv)
        self._emit('load', '%-8s x%d, %d(x%d)' % ('lw', ra, ARMED_OFF, R_BASE_A))
        self._emit('alu_imm', '%-8s x%d, x%d, 1' % ('addi', ra, ra))
        self._emit('store', '%-8s x%d, %d(x%d)' % ('sw', ra, ARMED_OFF, R_BASE_A))
        self._emit('lui', '%-8s x%d, %d' % ('lui', rt, CLINT_MSIP0 >> 12))
        self._emit('alu_imm', '%-8s x%d, x%d, 1' % ('addi', rv, R_ZERO))
        self._emit('store', '%-8s x%d, 0(x%d)' % ('sw', rv, rt))
        self.irq_sites += 1
        self.last_irq_at = len(self.items)
        # ...and immediately the sequencer it is aimed at.
        targets = [c for c in IRQ_TARGET_CLASSES if c in self.available]
        if targets:
            getattr(self, '_e_' + self.rng.choice(targets))()

    _EMITTERS = {
        'alu_reg': '_e_alu_reg', 'alu_imm': '_e_alu_imm', 'lui': '_e_lui',
        'auipc': '_e_auipc', 'branch': '_e_branch', 'jal': '_e_jal',
        'load': '_e_load', 'store': '_e_store', 'fence': '_e_fence',
        'mul': '_e_mul', 'div': '_e_div', 'amo': '_e_amo', 'lrsc': '_e_lrsc',
        'zba': '_e_zba', 'zbb': '_e_zbb', 'zbs': '_e_zbs', 'zbc': '_e_zbc',
        'zfinx': '_e_zfinx', 'clint_irq': '_e_clint_irq',
        'zicboz': '_e_zicboz', 'zawrs': '_e_zawrs', 'zihint': '_e_zihint',
        'zcmp': '_e_zcmp', 'zcmt': '_e_zcmt',
    }

    # -- construction
    def build(self):
        while len(self.items) < self.length:
            # A label may only be placed at a TEMPLATE boundary, never inside
            # one; that is what keeps a branch from entering an lr/sc pair or an
            # AMO's address setup half-way.
            if self.rng.bool_with(1, 8):
                lab = self._label()
                self.labels.append((len(self.items), lab))
                self.items.append(Label(lab))
            cls = self.rng.weighted_choice(self.weights)
            if cls == 'clint_irq' and \
                    len(self.items) - self.last_irq_at < IRQ_MIN_GAP:
                cls = 'alu_reg'
            getattr(self, self._EMITTERS[cls])()
        if self.negctrl == 'escape-store':
            self._emit('store', '%-8s x%d, %d(x%d)'
                       % ('sw', self._r(), SCRATCH_BYTES, R_BASE_A))
        elif self.negctrl == 'clobber-base':
            self._emit('alu_imm', '%-8s x%d, x%d, 4'
                       % ('addi', R_BASE_A, R_BASE_A))
        end = '.Lk3_body_end'
        self.labels.append((len(self.items), end))
        self.items.append(Label(end))
        # Branch targets are resolved BEFORE the subroutine block is appended,
        # so `self.labels` -- and therefore the legal target set -- contains
        # only main-body labels.  A branch can never enter a subroutine.
        self._resolve_branches(end)
        if self.subs:
            # The skip guard and the subroutine bodies go into `items` too, so
            # that the manifest counts EXACTLY what the emitter writes.  The
            # first cut kept them in a side list, the emitter added one `jal`
            # of its own, and the census read 67 where the manifest claimed 66
            # -- a one-instruction disagreement caused by having two places
            # that knew what a stream contains.  Now there is one.
            self._emit('jal', '%-8s x%d, .Lk3_subs_end' % ('jal', R_ZERO))
            for lab, body in self.subs:
                self.items.append(Label(lab))
                self.items.extend(body)
            self.items.append(Label('.Lk3_subs_end'))
        return self

    def _resolve_branches(self, end_label):
        """Every branch gets a target strictly later in the item list, drawn from the next
        BRANCH_TARGET_WINDOW labels only. Drawing from all later labels let one taken branch skip
        most of the body; bounding the skip keeps the DAG, since targets are still forward.
        """
        for pos, br in self.branches:
            later = [name for (at, name) in self.labels if at > pos]
            if not later:
                raise AssertionError('no forward label after position %d' % pos)
            br.target = self.rng.choice(later[:BRANCH_TARGET_WINDOW])

    # -- shape manifest
    def class_counts(self):
        counts = {}
        for it in self.items:
            if isinstance(it, Label):
                continue
            counts[it.cls] = counts.get(it.cls, 0) + 1
        return counts

    def n_insns(self):
        return sum(self.class_counts().values())
