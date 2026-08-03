#!/usr/bin/python3.6
"""isa_model.py -- what a given VestaRV configuration may legally be asked to
execute, and what the ORACLE can be asked to judge about it.

TWO GATES, NOT ONE.  This is the design decision of K3 and it is worth stating
before the tables:

  1. **Config-legality.**  An encoding the configured RTL would trap is never
     emitted.  On a default build a trap is TERMINAL (`vesta.vhd`'s TRAP_STATE
     self-loops with no ENABLE_ term -- K0 oracle probe §1.3n), so an
     illegal-for-config encoding does not fail loudly, it HANGS until the tb
     watchdog.  Gate 1 is what k3_spec.md requirement 2 asks for.

  2. **Oracle-judgeability.**  An encoding both sides execute but DESCRIBE
     DIFFERENTLY is worse than an illegal one, because the resulting divergence
     looks like an RTL bug.  The K0 oracle probe measured, per knob, whether the
     reference's record stream can be compared at all:

        verdict A  comparable today
        verdict B  needs a comparator amendment that DOES NOT EXIST (K2b)
        verdict C  not modellable; needs a V-series bracket channel

     A random generator that emits a verdict-B class into a lockstep run
     manufactures a divergence out of the harness.  So every class here carries
     its oracle status, and `select_classes()` REFUSES to hand a verdict-B class
     to a stream unless the caller passes `allow_unmodelled=True` and thereby
     takes responsibility for it in writing.

Neither gate is a substitute for the other.  Gate 1 is about the DUT; gate 2 is
about the reference.

WHAT THIS MODULE DOES NOT DO
----------------------------
It does not encode instructions.  It emits MNEMONIC TEXT and lets `gas` do the
encoding, so that the census (`census.py`) -- which decodes the built image's
BYTES back to a mnemonic from its own field table -- is an INDEPENDENT
instrument rather than a restatement of this file.  R-K2-5's `200f` lesson is
that a census which shares its author's assumptions confirms them; the unit
tests assert `census.decode(gas(m)) == m` for every mnemonic below, with
`objdump -M no-aliases` as the third-party referee.

Python 3.6 compatible.
"""

# --------------------------------------------------------------------------
# Oracle verdicts, quoted from k0_oracle_probe.md §1.2's table.  The citation
# is part of the datum: a status without its measurement is an opinion.
# --------------------------------------------------------------------------
A = 'A'      # comparable today
B = 'B'      # needs a comparator amendment that DOES NOT EXIST -- do not lockstep
C = 'C'      # not modellable at all; bracket channel only
E = 'E'      # ELIGIBLE VIA A NAMED, CONFIG-GATED K2b COMPARATOR AMENDMENT
             # (K2b): the record-shape difference is real and MEASURED, and a
             # tracked amendment in tools/cosim/amend.py reconciles it -- but
             # ONLY when the comparator runs with that amendment enabled, which
             # tools/cosim/oracle_isa.py derives from this same resolved config.
             # An E class is therefore emittable AND carries a REQUIREMENT: its
             # streams must be compared with the named amendment, and the
             # manifest records that requirement so a run cannot quietly drop
             # it.  E is NOT a promotion to A: A needs nothing.

KNOB_ORACLE = (
    # (knob, verdict, note[, amendments])
    ('mul',        A, 'k0 §1.2: `m`/`zmmul`'),
    ('div',        A, 'k0 §1.2: `m`; div-without-mul has NO lever (verdict C)'),
    ('atomics',    A, 'k0 §1.2: `a`, WITNESS lr.w'),
    ('compressed', A, 'k0 §1.2: `c`, WITNESS c.addi4spn'),
    ('bitmanip',   A, 'k0 §1.2: `_zba_zbb_zbs_zbc`, WITNESS sh1add'),
    ('zicond',     A, 'k0 §1.2: `_zicond`, WITNESS czero.eqz'),
    ('zcb',        A, 'k0 §1.2: `_zca_zcb`'),
    ('zimop',      A, 'k0 §1.2: `_zimop`(+`_zcmop`)'),
    ('zihint',     A, 'k0 §1.2/§1.3b: pause retires in BOTH polarities'),
    # zihpm STAYS B AT K2b AMENDMENT 4, for the same reason trapCsr does (see
    # the note there) and with a sharper edge: `hpm-warl` reconciles the WRITE
    # records and the CONFIGURATION registers' read-backs, and DELIBERATELY not
    # the COUNTER values -- the RTL has real event counters and the reference
    # hardwires them to zero, which is F1 and is the finding the amendment
    # exists to expose.  A stream that reads mhpmcounter* therefore diverges BY
    # CONSTRUCTION, and no amendment can or should change that.  Judgeable only
    # under a constraint no generator currently enforces => B.
    ('zihpm',      B, 'k0 §1.2/§3 + K2b: `hpm-warl` reconciles the HPM WRITE '
                      'records and the mcountinhibit/mhpmevent read-backs, but '
                      'a COUNTER read diverges by construction (real RTL event '
                      'counters vs a hardwired zero -- finding F1), so the knob '
                      'is judgeable only for streams that never read one'),
    ('zawrs',      A, 'k0 §1.2/§1.3c: RTL gate is ZAWRS *and* ATOMICS'),
    ('zabha',      A, 'k0 §1.2: `_zabha`, WITNESS amoadd.b'),
    ('zacas',      A, 'k0 §1.2: `_zacas`, WITNESS amocas.w'),
    ('zicboz',     E, 'k0 §1.3d: RTL emits 1 R + SIXTEEN M S, Spike emits 1 + 0 '
                      '-- reconciled by K2b amendment `cboz-stores`, which is '
                      'count- and geometry-checked (a 15-store burst is still '
                      'caught)',
                      ('cboz-stores',)),
    ('zcmp',       A, 'k0 §1.3l: record counts match exactly on both sides'),
    ('zcmt',       E, 'k0 §1.3e: cm.jt does a data-port table load the reference '
                      'never logs -- reconciled by K2b amendment `cmjt-load`, '
                      'bounded by addr == jvt + 4*index. The jvt WARL asymmetry '
                      'is NOT amended and does not need to be: it is already a '
                      'FORBIDDEN below (never write jvt), and every real table '
                      'base is 64-byte aligned',
                      ('cmjt-load',)),
    ('zbkb',       A, 'k0 §1.2: `_zbkb`, WITNESS pack'),
    ('zbkc',       A, 'k0 §1.2: `_zbkc`, WITNESS clmul'),
    ('zbkx',       A, 'k0 §1.2: `_zbkx`, WITNESS xperm8'),
    ('zkn',        A, 'k0 §1.2: `_zknd_zkne_zknh[_zkn]`'),
    ('zfinx',      E, 'k0 §1.3m: the RTL tracer emits C 001 on EVERY FPU_DONE, '
                      'Spike only when the op RAISES one -- reconciled by K2b '
                      'amendment `zfinx-fflags`',
                      ('zfinx-fflags',)),
    # trapCsr STAYS B AT K2b AMENDMENT 3, AND THAT IS A DELIBERATE DEPARTURE
    # from the spec's "each amendment flips its knob B -> eligible".  The two
    # record-shape differences the spec named ARE reconciled now (`mret-csr`,
    # `mtrap-t`), but a THIRD, unreconciled one gates them both: reaching
    # standard delivery at all requires clearing `mtrapctl.LEGACY`, and
    # `mtrapctl` (0x7C0) is a VestaRV CUSTOM CSR the unmodified reference treats
    # as an illegal instruction (measured).  Every test in the tree that
    # contains an `mret` therefore also contains an instruction the reference
    # traps on.  Marking this knob E would claim a judgeability that does not
    # exist -- and E is precisely a claim, since it tells the gate to admit the
    # class.  B is the honest letter until the blocker is ruled on.
    ('trapCsr',    B, 'k0 §1.3i/n + K2b F-K2b-2: mret/T record shapes are '
                      'reconciled by `mret-csr` + `mtrap-t`, but standard '
                      'delivery needs a write to the CUSTOM CSR mtrapctl '
                      '(0x7C0), which the reference traps on -- so the knob is '
                      'NOT judgeable end to end'),
    ('umode',      B, 'k0 §1.3j/o: --priv mu changes the reference reset state'),
    ('pmp',        B, 'k0 §1.4: Spike PMP reset state is NOT zero'),
)

KNOB_ORACLE_STATUS = dict((r[0], r[1]) for r in KNOB_ORACLE)
KNOB_ORACLE_NOTE = dict((r[0], r[2]) for r in KNOB_ORACLE)
# knob -> the K2b comparator amendment(s) its judgeability DEPENDS ON.  Empty
# for every A and C row; non-empty exactly on the E rows.
KNOB_AMENDMENTS = dict((r[0], tuple(r[3]) if len(r) > 3 else ()) 
                       for r in KNOB_ORACLE)


# --------------------------------------------------------------------------
# HARD REFUSALS -- the things k3_spec.md requirement 3 forbids outright, each
# with the measurement behind it.  These are not weights; nothing may switch
# them on.  Enforced by `assert_no_forbidden_text()` over the emitted body, so
# that a future emitter cannot reintroduce one silently.
# --------------------------------------------------------------------------
FORBIDDEN = (
    ('mip write',
     'k0 §1.3n: `mip` is a READ-ONLY mirror in the RTL and WRITABLE in M-mode '
     'in Spike -- a stream that writes it diverges by construction.'),
    ('jvt write',
     'k0 §1.3e: the RTL pins jvt[5:0] to zero, Spike stores what you wrote. '
     'Both legal WARL, different values, and C.val is a compared field.'),
    ('mtvec MODE != 0',
     'k0 §1.3n: mtvec MODE is WARL "00" in the RTL and vectored-capable in Spike.'),
    ('opcode 0x0b',
     'k0 §1.5: iret/extinguish/ignite TRAP in Spike under EVERY --isa string. '
     'Verdict C for every config; the treatment is the bracket channel.'),
    ('mutex-bank AMO/LR/SC',
     'CLAUDE.md: an `lw` of a mutex address is an atomic claim WITH A SIDE '
     'EFFECT; never AMO or LR/SC one.'),
    ('mhpmevent write on a non-ZIHPM config',
     'D-2026-07-29-1, the standing rv32ua-p-extzihpm divergence.'),
)


# --------------------------------------------------------------------------
# The shape classes.  A class is a set of mnemonics that (a) the census can
# tell apart from every other class by FIELD DECODE alone, and (b) share a
# knob requirement.  `needs` is a tuple of resolved-config isa.* keys that must
# ALL be true.
#
# ORDER IS PART OF THE CONTRACT: it is the order weights are consumed in and
# therefore reaches the emitted bytes.  Never reorder without bumping the
# generator version.
# --------------------------------------------------------------------------

# Base-integer R-type.
M_ALU_REG = ('add', 'sub', 'sll', 'slt', 'sltu', 'xor', 'srl', 'sra', 'or', 'and')
# Base-integer I-type (register-immediate).  `slli/srli/srai` take a shamt.
M_ALU_IMM = ('addi', 'slti', 'sltiu', 'xori', 'ori', 'andi')
M_ALU_SHIMM = ('slli', 'srli', 'srai')
M_BRANCH = ('beq', 'bne', 'blt', 'bge', 'bltu', 'bgeu')
M_LOAD = ('lb', 'lh', 'lw', 'lbu', 'lhu')
M_STORE = ('sb', 'sh', 'sw')
M_MUL = ('mul', 'mulh', 'mulhsu', 'mulhu')
M_DIV = ('div', 'divu', 'rem', 'remu')
M_AMO = ('amoswap.w', 'amoadd.w', 'amoxor.w', 'amoand.w', 'amoor.w',
         'amomin.w', 'amomax.w', 'amominu.w', 'amomaxu.w')
M_ZBA = ('sh1add', 'sh2add', 'sh3add')
M_ZBB_R = ('andn', 'orn', 'xnor', 'max', 'maxu', 'min', 'minu', 'rol', 'ror')
# `zext.h` is TWO-operand (`zext.h rd, rs1`) even though it is an OP-format
# encoding with rs2 pinned to zero, so it belongs with the unary group and not
# with the register-register one.  It was in M_ZBB_R in the first cut and gas
# rejected `zext.h x31,x15,x22` -- found by the longer unit-test streams, which
# is the whole reason those run at length 1200 rather than 300.
M_ZBB_UN = ('clz', 'ctz', 'cpop', 'sext.b', 'sext.h', 'orc.b', 'rev8',
            'zext.h')
M_ZBB_IMM = ('rori',)
M_ZBS_R = ('bclr', 'bext', 'binv', 'bset')
M_ZBS_IMM = ('bclri', 'bexti', 'binvi', 'bseti')
M_ZBC = ('clmul', 'clmulh', 'clmulr')
# Zfinx single-precision, x-register operands.  gas 2.41 accepts every one of
# these under an `_zfinx` arch (measured: `fadd.s x10,x11,x12` assembles to
# 0x00c5f553), so the "gas encodes it, census.py decodes it independently"
# contract holds here exactly as it does for the base ISA -- no `.insn` or raw
# `.short` fallback, which is why Zcmt gets no class and this does.
# THREE-OPERAND and TWO-OPERAND forms are separate tuples because the emitter
# has to know the arity; `fsqrt.s` in the register-register group is exactly the
# `zext.h` mistake M_ZBB_UN was split out for.
M_ZFINX_R = ('fadd.s', 'fsub.s', 'fmul.s', 'fdiv.s', 'fmin.s', 'fmax.s',
             'fsgnj.s', 'fsgnjn.s', 'fsgnjx.s', 'feq.s', 'flt.s', 'fle.s')
M_ZFINX_UN = ('fsqrt.s', 'fclass.s', 'fcvt.w.s', 'fcvt.wu.s', 'fcvt.s.w',
              'fcvt.s.wu')

# class name -> (required isa.* knobs, oracle verdict, human description)
CLASSES = (
    ('alu_reg', (), A, 'base-I register-register ALU'),
    ('alu_imm', (), A, 'base-I register-immediate ALU (incl. shift-immediate)'),
    ('lui', (), A, 'lui'),
    ('auipc', (), A, 'auipc'),
    ('branch', (), A, 'conditional branch, FORWARD only'),
    ('jal', (), A, 'jal (forward, or the subroutine-skip guard)'),
    ('jalr', (), A, 'jalr (the subroutine return)'),
    ('load', (), A, 'aligned load from the scratch block'),
    ('store', (), A, 'aligned store into the scratch block'),
    ('fence', (), A, 'fence iorw,iorw'),
    ('mul', ('mul',), A, 'M-extension multiply (multi-cycle sequencer)'),
    ('div', ('mul', 'div'), A, 'M-extension divide/remainder (DIV_WAIT/DIV_DONE)'),
    ('amo', ('atomics',), A, 'word AMO on the scratch block (AMO_* sequencer)'),
    ('lrsc', ('atomics',), A, 'adjacent lr.w/sc.w pair (LR_READ/SC_CHECK)'),
    ('zba', ('bitmanip',), A, 'Zba address generation'),
    ('zbb', ('bitmanip',), A, 'Zbb basic bit manipulation'),
    ('zbs', ('bitmanip',), A, 'Zbs single-bit'),
    ('zbc', ('bitmanip',), A, 'Zbc carry-less multiply'),
    ('zfinx', ('zfinx',), A, 'Zfinx single-precision FP in the x-registers '
                             '(FPU_WAIT/FPU_DONE, the fflags sticky-OR)'),
    ('clint_irq', (), C, 'CLINT msip self-injection (legacy IVT delivery; '
                         'lockstep needs BRACKET_ISR=1)'),
)

CLASS_NEEDS = dict((n, need) for (n, need, _o, _d) in CLASSES)
CLASS_OWN_ORACLE = dict((n, o) for (n, _need, o, _d) in CLASSES)


def class_oracle(name):
    """A class's oracle verdict = its OWN verdict combined with the verdicts of
    every knob it needs.

    DERIVED RATHER THAN TABULATED, and that is a K2b correction to K3's shape.
    Before this, `CLASSES` carried a hand-written verdict beside `KNOB_ORACLE`'s
    hand-written verdict, with nothing tying them together: a class needing a
    verdict-B knob could have been written down as A and the refusal arm would
    never have noticed.  (It could not happen in K3 only because no class
    needed a B knob at all -- which is exactly why R-K3-2's D-3 records that
    the refusal arm had never fired.)

    The combination is NOT a total order on 'badness', because C and B are
    treated oppositely on purpose:
        any B  -> B   REFUSED: modelled DIFFERENTLY by the two sides, and the
                      amendment that would reconcile it does not exist
        any C  -> C   ADMITTED via the existing V3 bracket channel
        any E  -> E   ADMITTED, and the run must carry the named amendment
        else      A
    """
    vs = [CLASS_OWN_ORACLE[name]] + [KNOB_ORACLE_STATUS[k]
                                     for k in CLASS_NEEDS[name]
                                     if k in KNOB_ORACLE_STATUS]
    for want in (B, C, E):
        if want in vs:
            return want
    return A


CLASS_ORACLE = dict((n, class_oracle(n)) for (n, _need, _o, _d) in CLASSES)
CLASS_DESC = dict((n, d) for (n, _need, _o, d) in CLASSES)
CLASS_ORDER = tuple(n for (n, _need, _o, _d) in CLASSES)

# Every mnemonic this module can emit, grouped by the class the census must
# report it as.  The unit tests walk this map, assemble each mnemonic, and
# assert census.decode() names it identically -- the instrument validation.
CLASS_MNEMONICS = (
    ('alu_reg', M_ALU_REG),
    ('alu_imm', M_ALU_IMM + M_ALU_SHIMM),
    ('lui', ('lui',)),
    ('auipc', ('auipc',)),
    ('branch', M_BRANCH),
    ('jal', ('jal',)),
    ('jalr', ('jalr',)),
    ('load', M_LOAD),
    ('store', M_STORE),
    ('fence', ('fence',)),
    ('mul', M_MUL),
    ('div', M_DIV),
    ('amo', M_AMO),
    ('lrsc', ('lr.w', 'sc.w')),
    ('zba', M_ZBA),
    ('zbb', M_ZBB_R + M_ZBB_UN + M_ZBB_IMM),
    ('zbs', M_ZBS_R + M_ZBS_IMM),
    ('zbc', M_ZBC),
    ('zfinx', M_ZFINX_R + M_ZFINX_UN),
)

MNEMONIC_CLASS = {}
for _c, _ms in CLASS_MNEMONICS:
    for _m in _ms:
        MNEMONIC_CLASS[_m] = _c
del _c, _ms, _m


# The 'clint_irq' class emits base-I loads/stores; its instructions decode as
# `alu_imm`/`store`/`load` and the census counts them as such.  That is
# deliberate and is stated in the manifest: a census cannot tell an
# msip-arming `sw` from any other `sw` by field decode, and pretending it can
# would be exactly the suffix-matching error R-K2-5 recorded.  The IRQ-site
# count is therefore a GENERATOR claim carried in the manifest and validated by
# a different witness (the ISR's own flag word), not by the census.
CENSUS_OPAQUE_CLASSES = ('clint_irq',)


class UnmodellableClass(Exception):
    """A class the reference model cannot be asked to judge."""


def available_classes(cfg_isa, allow_unmodelled=False):
    """The classes this configuration may legally and judgeably emit.

    Returns `(available, blocked)` where `blocked` is an ordered list of
    `(class, reason)` -- kept and reported rather than silently dropped, so a
    manifest can state what a run did NOT cover and why.

    VERDICT C IS ADMITTED AND VERDICT B IS NOT, which looks backwards until the
    difference is named: a C class has an EXISTING channel (the V3
    `BRACKET_ISR` machinery, a standing gate since the multi-hart sweep), while
    a B class needs a comparator amendment that K2 explicitly deferred to K2b
    and that DOES NOT EXIST.  "Not modellable, but bracketed" is a solved
    problem; "modelled differently by the two sides" is an open one, and only
    the second manufactures divergences that look like RTL bugs.
    """
    avail, blocked = [], []
    for name in CLASS_ORDER:
        need = CLASS_NEEDS[name]
        missing = [k for k in need if not cfg_isa.get(k)]
        if missing:
            blocked.append((name, 'config knob(s) off: ' + ', '.join(missing)))
            continue
        verdict = CLASS_ORACLE[name]
        if verdict == B and not allow_unmodelled:
            blocked.append((name, 'oracle verdict B (comparator amendment is '
                                  'K2b and does not exist)'))
            continue
        avail.append(name)
    return avail, blocked


def required_amendments(class_names):
    """The K2b comparator amendments a stream containing these classes NEEDS.

    A stream that carries an E class and is compared WITHOUT its amendment
    diverges on record SHAPE, which reads exactly like a DUT defect -- so the
    requirement is written into the manifest rather than left as folklore.
    The comparator is fed the same set independently, derived from the same
    resolved config by `tools/cosim/oracle_isa.py::derive_amendments`; this is
    the generator's half of that agreement, and the two are checked against
    each other by the unit tests.
    """
    out = []
    for name in class_names:
        for knob in CLASS_NEEDS[name]:
            for a in KNOB_AMENDMENTS.get(knob, ()):
                if a not in out:
                    out.append(a)
    return out


def knobs_on_without_emitter(cfg_isa, cfg_priv):
    """Knobs the config turns ON that this generator has NO emitter for.

    Named rather than ignored.  A knob-on row whose stream contains none of that
    knob's encodings is a green cell covering nothing -- R-K2-7 (2) ruled that
    distinction into the residue list, and this is the generator's half of it.
    """
    have_emitter = set()
    for name in CLASS_ORDER:
        for k in CLASS_NEEDS[name]:
            have_emitter.add(k)
    out = []
    for knob in (r[0] for r in KNOB_ORACLE):
        on = cfg_priv.get(knob) if knob in ('trapCsr', 'umode', 'pmp') \
            else cfg_isa.get(knob)
        if on and knob not in have_emitter:
            out.append((knob, KNOB_ORACLE_STATUS[knob], KNOB_ORACLE_NOTE[knob]))
    return out
