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
    ),
    # 'seq' -- the roadmap Step 2 weighting: the multi-cycle sequencers.
    'seq': (
        ('alu_reg', 8), ('alu_imm', 8), ('lui', 2), ('auipc', 2),
        ('branch', 5), ('jal', 2), ('load', 6), ('store', 6),
        ('fence', 1), ('mul', 10), ('div', 22), ('amo', 20), ('lrsc', 14),
        ('zba', 1), ('zbb', 2), ('zbs', 1), ('zbc', 1), ('zfinx', 14),
        ('clint_irq', 0),
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
}
PROFILE_ORDER = ('base', 'seq', 'irq', 'bitm')

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
