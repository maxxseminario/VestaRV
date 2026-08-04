#!/usr/bin/python3.6
"""stream.py -- build one constrained-random RV32 instruction stream.

THE THREE INVARIANTS, AND WHY EACH IS STRUCTURAL RATHER THAN CHECKED
--------------------------------------------------------------------
On a default build a trap is TERMINAL: `TRAP_STATE` self-loops with no
`ENABLE_` term (K0 oracle probe §1.3n), so an illegal encoding, a misaligned
access or a stray branch does not FAIL, it HANGS until the 100 ms tb watchdog.
"Generate and check afterwards" is therefore not available.  Every trap source
is removed by construction instead:

  1. **Legality.**  Only mnemonics `isa_model` says this config implements, and
     `gas` refuses at build time under the config's own `-march` if that is ever
     wrong -- a second, independent gate.

  2. **Memory safety.**  Every load/store/AMO addresses `off(base)` where `base`
     is one of TWO RESERVED registers no emitter ever writes, and `off` is drawn
     from a window computed to keep the address inside a `.data` scratch block.
     Alignment is a property of the drawn offset, not of a runtime value.  The
     scratch block is bracketed by sixteen guard words on each side which the
     epilogue verifies -- so the discipline is BOTH structural and witnessed.

  3. **Termination.**  Conditional branches and `jal` are FORWARD ONLY, so the
     main body is a DAG and cannot loop.  The single backward transfer in the
     whole stream is a subroutine `jalr x0, 0(ra)` return, whose call site is
     itself executed at most once.  No bounded-retry budget is needed because
     there is no retry.

WHAT A PASSING RUN OF ONE OF THESE STREAMS ACTUALLY SAYS
--------------------------------------------------------
`RVTEST_PASS` is reached unconditionally except for the epilogue's discipline
checks, so a behavioral-suite PASS states: the stream did not trap, it
terminated, the base registers and `sp` survived, no store escaped the scratch
window, and (for an IRQ profile) every msip that was ACTUALLY RAISED was taken
and handled exactly once, and at least one was.  Both sides of that last
comparison are RUNTIME counters -- see `_e_clint_irq` for the measured reason a
static site count is the wrong thing to assert.
It states NOTHING about whether any computed value was right.  That is
the lockstep comparator's job, and `s5_ledger.md` §2.3's "has-a-bench is not
has-coverage" is why the distinction is written here rather than left implied.

Python 3.6 compatible.
"""

import isa_model

# --------------------------------------------------------------------------
# Register discipline.  x-numbers, not ABI names: the emitted text is meant to
# be read against the census output, and `x9` is unambiguous where `s1` is not.
# --------------------------------------------------------------------------
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
# calibrated delay (method rule 7 forbids calibrating a test to land on an
# instruction): it exists only so that two interrupts cannot plausibly coalesce
# into one, which would make the epilogue's exact-count assertion wrong for a
# benign reason.
IRQ_MIN_GAP = 12

# How far ahead a conditional branch may aim.  See `_resolve_branches` for the
# measurement that fixed this at 2 rather than "any later label".
BRANCH_TARGET_WINDOW = 2


# --------------------------------------------------------------------------
# K5 queue item 4 -- geometry and encoders for the five new classes.
#
# EVERY NUMBER BELOW IS DERIVED FROM SOMETHING, and the derivation is written
# next to it.  The one that matters most is CBOZ_MAX_OFF: it is not a tuned
# value, it is the largest offset for which the RTL's rounded-down 64-byte
# block is still a subset of the scratch window.
# --------------------------------------------------------------------------
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
    """The x-numbers `cm.push rlist` saves, in spec order.

    Mirrors `vesta.vhd`'s `zcm_reg_at`: position 0 = x1 (ra), 1 = x8 (s0),
    2 = x9 (s1), p >= 3 = x(15+p) (x18..x27).  Written from the spec here and
    checked against the RTL function by eye AND against the directed tests'
    literals by `test_randgen.py`.
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
    """The 16-bit `cm.push`/`cm.pop` encoding.

    C2 quadrant (bits 1:0 = 10), funct3 = 101 (bits 15:13), bit 12 = 1 selects
    the push/pop family, bit 11 = 1 and bit 8 = 0 are required by the encoding
    (and by `c_dec.vhd`, which refuses otherwise), bits 10:9 select
    push/pop/popretz/popret, bits 7:4 are rlist and bits 3:2 are spimm[5:4].

    KNOWN-NONZERO VALIDATION (method rule 4): this function must return
    0xB852 for (push, rlist=5, spimm=0) and 0xBA52 for (pop, rlist=5, spimm=0),
    the literals `verification/isa/tests/rv32ua/extzcmp.S` carries.  gas 2.41
    cannot assemble these and objdump 2.41 cannot name them, so those two
    literals are the only third party available and the unit tests assert
    against them.
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


# --------------------------------------------------------------------------
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
# --------------------------------------------------------------------------
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
    # 'zext' -- K5 v1.3.0.  The DEMONSTRATION profile for the five classes
    # R-K4-2 (2) dropped from the campaign: dense enough that one stream of a
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
    # checks fire (method rule 1: a detector never seen to fail proves
    # nothing).  These are NOT the acceptance mutants of k3_spec.md item 6 --
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

    # -- small helpers -----------------------------------------------------
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

    # -- per-class emitters -------------------------------------------------
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
        """Divide, with the two architecturally-defined edge cases DELIBERATELY
        reachable rather than left to chance.

        RISC-V defines both: `x/0` yields all-ones (rem yields x) and
        `INT_MIN/-1` yields INT_MIN (rem yields 0).  Neither traps, and both
        sides model both -- so they are free coverage of the DIV sequencer's
        early-out paths.  The setup instructions are ordinary `lui`/`addi` and
        the manifest counts them as such; nothing here is a pseudo-instruction
        (see the census contract in `census.py`).
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
        """Materialise a word-aligned in-window scratch address in a pool reg.

        RV32A has no offset field -- `amoadd.w rd, rs2, (rs1)` addresses rs1
        exactly -- so varying the address needs a real `addi`.  Emitted
        immediately before its consumer so nothing can overwrite it in between.
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
        """An IMMEDIATELY-ADJACENT lr.w / sc.w pair, and nothing else.

        Two things are deliberately not emitted:
          * a locally-FAILED SC (an intervening same-hart store, or a bare SC
            with no reservation).  Whether a same-hart store kills a reservation
            is implementation-defined, so the RTL and the reference may
            legitimately disagree -- a random generator emitting it would
            manufacture divergences.  The consequence is stated in
            k3_predictions.md P9: the fixpass residue item "no locally-failed-SC
            witness" is NOT retired by K3.
          * anything between the LR and the SC.  A branch target may never land
            there either (labels are placed only at template boundaries), so the
            pair cannot be entered half-way.

        The `lr.w` destination IS a live pool register whose value flows on into
        later instructions, so every retire of it is compared.  That is the
        `s2_c11_validation.md` LR-rd coverage hole -- "rv32ua-p-lrsc cannot
        observe an LR rd suppression" -- and a lockstep cell over this stream
        does observe it.
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
        """One Zfinx single-precision op on pool registers.

        Zfinx puts the FP operands and results in the INTEGER registers, so
        this needs no new register discipline: the pool's seeded values are
        reinterpreted as float bit patterns, which is precisely the point --
        the interesting inputs (NaNs, subnormals, +-0, huge exponents) arrive
        for free from the same 32-bit words `div` and `zbb` are fed.

        Nothing here can trap: an IEEE exception sets a sticky `fflags` bit, it
        does not raise.  So a Zfinx stream stays trap-free by construction on a
        non-TRAPCSR config, which is the k3_spec requirement-4 rule.

        The class is ORACLE VERDICT E: its record stream is only judgeable when
        the comparator runs with the K2b `zfinx-fflags` amendment, and
        `isa_model.required_amendments()` puts that requirement in the
        manifest.
        """
        if self.rng.bool_with(1, 3):
            m = self.rng.choice(isa_model.M_ZFINX_UN)
            self._emit('zfinx', '%-8s x%d, x%d' % (m, self._r(), self._r()))
        else:
            m = self.rng.choice(isa_model.M_ZFINX_R)
            self._emit('zfinx', '%-8s x%d, x%d, x%d'
                       % (m, self._r(), self._r(), self._r()))

    # ----------------------------------------------------------------------
    # K5 queue item 4 -- the five emitter-less state-bearing Z rows.
    # Each one's SAFETY argument is structural, in the sense the module
    # docstring means: the trap/hang source is removed by construction rather
    # than checked afterwards, because a trap is TERMINAL on a default build.
    # ----------------------------------------------------------------------
    def _e_zicboz(self):
        """One `cbo.zero` on a block that is a SUBSET of the scratch window.

        THE ROUNDING IS THE WHOLE DIFFICULTY.  The RTL latches
        `cboz_base = rs1 and not (CBOZ_BLOCK_SIZE-1)` once at dispatch
        (vesta.vhd's cboz_seq_proc), so the block a `cbo.zero rs1` writes need
        not START at rs1 -- it starts at rs1 rounded DOWN to 64.  A generator
        that drew rs1 anywhere in the 256-byte scratch block would therefore
        zero bytes BELOW its own window whenever it drew an offset in the first
        64 bytes of... no: it would zero bytes ABOVE the window whenever it drew
        an offset in the LAST block, because the block extends 63 bytes past
        rs1.  Either way the guard words are one draw away.

        The bound is taken on the OFFSET rather than on the address: `k3_scratch`
        is `.align 6` (emit.py), so scratch + off has block base
        scratch + (off and not 63); restricting off to [0, CBOZ_MAX_OFF] with
        CBOZ_MAX_OFF = 191 puts every block inside scratch bytes [0,192) --
        clear of both guard bands AND of the reserved tail at offset 248, which
        holds the dynamic IRQ-arm counter the epilogue compares.  Nothing is
        calibrated (method rule 7): the edge is structural arithmetic on the
        block size and the scratch geometry, both of which are constants here.

        THE BURST IS UNINTERRUPTIBLE in the RTL (CBOZ_WRITE has no irq_save
        check), which is real sequencer coverage and is why this class is worth
        having at all rather than being a decode-surface tick.

        ORACLE VERDICT E: the RTL emits 1 R + SIXTEEN `M S` and the reference
        emits 1 + 0, reconciled by the K2b `cboz-stores` amendment, which is
        count- AND geometry-checked.  `required_amendments()` puts that in the
        manifest so a lockstep run cannot quietly drop it.
        """
        off = self.rng.between(0, CBOZ_MAX_OFF)
        rt = self._r()
        self._emit('alu_imm', '%-8s x%d, x%d, %d' % ('addi', rt, R_BASE_A, off))
        self._emit('zicboz', '%-8s (x%d)' % ('cbo.zero', rt))

    def _e_zawrs(self):
        """One `wrs.nto` or `wrs.sto`, at a site where it CANNOT park.

        The K0 oracle probe §2.2 records the trap plainly: a `wrs.nto` with no
        wake never retires, and on a default build that is a watchdog hang, not
        a FAIL.  The RTL's wake is
        `wrs_wake <= '1' when (resv_valid_ext = '0' or wrs_int_pending = '1' or
        wrs_timeout = '1')`, and `wrs.nto` has no timeout arm -- so the ONLY
        structural guarantee available is the first term.

        It holds here, and it holds for a reason that is a property of the
        GENERATOR rather than of any particular stream: the only instruction
        this generator emits that can set a reservation is `lr.w`; `_e_lrsc`
        emits it ONLY as an immediately-adjacent `lr.w`/`sc.w` pair; a label may
        be placed only at a template boundary, so no branch can land between
        them; and `sc.w` clears the reservation whether it succeeds or fails.
        Therefore at every point OUTSIDE that two-instruction template -- which
        is every point a `wrs` can be emitted -- `resv_valid_ext` is '0', the
        wake is already asserted when the wrs dispatches, and it retires.

        `wrs.sto` is emitted too and needs no such argument (it has the
        timeout), but it is drawn less often because the interesting state is
        the one with no escape hatch.
        """
        m = 'wrs.sto' if self.rng.bool_with(1, 3) else 'wrs.nto'
        self._emit('zawrs', '%s' % m)

    def _e_zihint(self):
        """`pause`, or one of the four `ntl` hints.

        Both are architectural NOPs and both retire in EITHER polarity of the
        knob (k0 §1.3b), which is precisely why the class is SUITE-ONLY here
        (`isa_model.SUITE_ONLY_CLASSES` carries the reason).  What it buys is
        decode-surface coverage of two encodings that sit inside spaces the core
        decodes for other purposes: `pause` is a FENCE encoding and `ntl.*` are
        `add x0, x0, x{2..5}` -- an OP-format instruction with rd = x0.

        The `ntl` rs2 MUST be x2/x3/x4/x5; that IS the hint encoding, and x2 is
        `sp`.  Reading `sp` is harmless (RESERVED means never WRITTEN), and
        `add x0, ...` discards its result by definition, so no register
        discipline is touched.
        """
        if self.rng.bool_with(1, 2):
            self._emit('zihint', 'pause')
        else:
            hint = self.rng.choice(('ntl.p1', 'ntl.pall', 'ntl.s1', 'ntl.all'))
            self._emit('zihint', '%-8s x%d, x%d, x%d   # %s'
                       % ('add', R_ZERO, R_ZERO, ZIHINT_NTL_RS2[hint], hint))

    def _e_zcmp(self):
        """One BALANCED `cm.push` / `cm.pop` frame, emitted as ONE template.

        gas 2.41 has no `cm.*` mnemonic and no `_zcmp` march (measured), so the
        16-bit words are encoded here and emitted as `.short`.  The encoder is
        `zcmp_push_pop_word()` below and it is validated against the X3 directed
        tests' hand-verified literals.

        THREE THINGS THIS TEMPLATE GUARANTEES, each of them a hazard §H.2 named:

        * `sp` survives.  push and pop carry the SAME rlist and the SAME spimm,
          so the stack adjustment is exactly undone, and they are emitted
          together so no branch can separate them (labels sit at template
          boundaries only, exactly as for `lr.w`/`sc.w`).
        * the frame cannot collide with the stream's scratch band.  The frame
          lives at `sp` (0xBFF0 downward, TCM stack); the scratch block is a
          `.data` object.  Different objects, and neither emitter can address
          the other's.
        * no RESERVED register is written, even transiently.  The pushed list is
          {ra, s0, s1, s2..s11} = {x1, x8, x9, x18..x27}; x1/x8/x9 are reserved
          and are RESTORED by the pop, but the intermediate clobber -- which is
          what makes the pop's loads verifiable instead of a copy of what was
          already in the registers -- is drawn ONLY from x18..x27, which are
          ordinary POOL registers.

        The clobber matters more than it looks.  K4-L3 recorded `cm.pop` as
        UNVERIFIED: with nothing writing the saved registers between push and
        pop, a `cm.pop` that loaded nothing at all would leave identical
        architectural state and no comparator could tell.  With the clobber the
        pop's loads are the only thing that can restore the pre-push values, so
        a lockstep cell over this template observes them.
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
        """One `cm.jt` or `cm.jalt` through the jump-vector table.

        Both are REAL control transfers -- `zcm_jt_addr = jvt + 4*index`, load
        the word, redirect to it -- so the DAG invariant has to be preserved by
        where the table POINTS, not by anything about the instruction.  Two
        shapes, and the emitter picks between them:

        * `cm.jt` (index < 32, no link): the table entry is made to hold the
          address of the instruction IMMEDIATELY AFTER the cm.jt.  The transfer
          therefore lands exactly where a fall-through would, and the control
          flow of the stream is unchanged while the table load, the redirect and
          the no-link property are all exercised.  The landing label is NOT
          registered in `self.labels`, so no branch can target it.
        * `cm.jalt` (index >= 32, links ra): the table entry holds a subroutine
          that ends in `jalr x0, 0(ra)`, which is the `_e_jal` shape exactly --
          the one backward transfer the module docstring already allows.

        jvt is written ONCE, in the prologue, from a `.align 6` table symbol, so
        the FORBIDDEN row is satisfied by construction: the RTL pins jvt[5:0] to
        zero and the reference stores what it is given, and for a 64-byte
        aligned base those are the same 32 bits.

        ORACLE VERDICT E via `cmjt-load`: the RTL logs the table load as an
        `M L` record and the reference logs nothing, and the amendment drops it
        bounded by `addr == jvt + 4*index`.
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
        """Raise msip[0] -- a LEVEL interrupt on IVT slot 83 (M19: the CLINT
        slots are hardwire-enabled on every hart, so there is no unmask step).

        The store is the whole injection; the ISR clears the level and counts.
        Only a STORE is emitted and never a load: after the bracketed handler
        runs, the RTL's CLINT holds 0 while the reference's plain memory at
        0x5000 still holds 1, so a load would diverge on a harness artefact.

        Where the interrupt is actually TAKEN is not controlled here, and
        deliberately so -- method rule 7 forbids calibrating a test to land on
        an instruction.  What is controlled is PLACEMENT: the arm is emitted
        immediately before a multi-cycle sequencer instruction.  Arrival is a
        measurement K3 does not make; see k3_predictions.md P16.

        THE ARMED COUNTER, AND WHY IT EXISTS -- a MEASURED correction.
        The first cut had the epilogue assert `handled == <number of arm sites
        EMITTED>`, and `k3i01` FAILED at the a0 gate on its first behavioral
        run.  Cause: forward branches skip code, so the count of arms EXECUTED
        is dynamic and strictly smaller.  Measured on that stream: 9 arm sites
        emitted, 8 of them jumped over by at least one forward branch, so the
        executed count could legally be as low as 1.  The static/dynamic
        confusion this generator's own manifest warns about (a manifest counts
        what is IN the image, not what RAN) was present in the runtime check
        itself.  The fix is to count what happens: each arm bumps a reserved
        scratch word, and the epilogue compares THAT against the handler's
        count.  The assertion is now exactly "every msip that was actually
        raised was taken and handled exactly once".
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

    # -- construction ------------------------------------------------------
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
        """Every branch gets a target that comes STRICTLY LATER in the item
        list, drawn from the NEXT `BRANCH_TARGET_WINDOW` labels only.

        THE WINDOW IS THE WHOLE POINT, and it is there because of a
        measurement, not a hunch.  The first cut drew uniformly from ALL later
        labels, which meant one taken branch could skip most of the body.
        Measured on the v1.1.0 campaign, dynamic retires with a PC inside the
        census range as a fraction of instructions EMITTED there:

            k3b01   4 / 392   =  1.0 %
            k3s01  66 / 384   = 17.2 %
            k3s02  83 / 383   = 21.7 %
            k3z01 123 / 399   = 30.8 %
            k3i02 278 / 398   = 69.8 %

        A stream that PASSES the a0 gate having executed 1 % of its own body is
        precisely the green-cell-covering-nothing shape this programme exists to
        find (`s5_ledger.md` 2.3), and a manifest counting 392 instructions
        alongside it would be false precision (method rule 9).  Bounding the
        skip keeps the DAG -- targets are still strictly forward, so termination
        is unchanged -- while making the executed fraction a usable number.
        """
        for pos, br in self.branches:
            later = [name for (at, name) in self.labels if at > pos]
            if not later:
                raise AssertionError('no forward label after position %d' % pos)
            br.target = self.rng.choice(later[:BRANCH_TARGET_WINDOW])

    # -- shape manifest ----------------------------------------------------
    def class_counts(self):
        counts = {}
        for it in self.items:
            if isinstance(it, Label):
                continue
            counts[it.cls] = counts.get(it.cls, 0) + 1
        return counts

    def n_insns(self):
        return sum(self.class_counts().values())
