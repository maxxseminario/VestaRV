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

import re

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
    ('zawrs',      A, 'k0 §1.2/§1.3c: RTL gate is ZAWRS *and* ATOMICS. K5: a '
                      'generated wrs is judgeable, but the CLASS is emitted '
                      'suite-only under the standing screen -- see the '
                      '`zawrs` CLASSES row'),
    ('zabha',      A, 'k0 §1.2: `_zabha`, WITNESS amoadd.b'),
    ('zacas',      A, 'k0 §1.2: `_zacas`, WITNESS amocas.w'),
    ('zicboz',     E, 'k0 §1.3d: RTL emits 1 R + SIXTEEN M S, Spike emits 1 + 0 '
                      '-- reconciled by K2b amendment `cboz-stores`, which is '
                      'count- and geometry-checked (a 15-store burst is still '
                      'caught)',
                      ('cboz-stores',)),
    # zcmp: A (K0) -> B (K4-L3) -> E (K5 queue item 2).  THE HISTORY IS THE
    # DATUM.  K0 §1.3l measured only that the record COUNTS match, and wrote A.
    # K4-L3 then measured the record ORDER and found the two sides emit ONE
    # frame's memory records in different orders -- so the counts matched and
    # the stream still could not be compared positionally.  A was therefore a
    # judgeability claim the measurement did not support, and it was live in
    # this table for the whole of K4.  K5 queue item 2 landed the
    # `zcmp-frame-order` amendment (canonicalise ONE frame retire's memory
    # records into ascending address order, INDEPENDENTLY on each side; nothing
    # is dropped), which is exactly the E contract: emittable, and the run must
    # carry the named amendment.
    #
    # THE PRE-FLIP REFUSAL WAS MEASURED, NOT ASSUMED (K5 item 4).  With this row
    # at B, `available_classes` on a zcmp-ON config blocked EXACTLY ONE class --
    # zcmp -- with the reason "oracle verdict B (comparator amendment is K2b and
    # does not exist)", and `allow_unmodelled=True` re-admitted exactly that one
    # and nothing else.  That is the FIRST FIRING of the refusal arm in this
    # programme: R-K3-2's D-3 recorded it had never fired, and R-K4-3 (4)
    # measured that no CONFIGURATION could make it fire and named it a K5
    # emitter question.  It was, and this is the answer.  R-K4-3 (4)'s
    # accompanying instruction -- do not "prove" a new class by making the arm
    # fire -- is honoured: B is not a pose, it is this knob's honest state
    # between K4-L3's measurement and K5 queue item 2's amendment, and the flip
    # below is the amendment landing, not the demonstration ending.
    ('zcmp',       E, 'k0 §1.3l counted the records and said A; K4-L3 MEASURED '
                      'the frame store ORDER and the two sides differ, so A was '
                      'a judgeability claim the measurement did not support. '
                      'K5 queue item 2 landed `zcmp-frame-order`, which '
                      'canonicalises ONE frame retire\'s memory records into '
                      'ascending address order INDEPENDENTLY on each side -- '
                      'nothing is dropped, the full window survives, and cm.pop '
                      '(recorded UNVERIFIED at K4-L3) is inside it',
                      ('zcmp-frame-order',)),
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
# them on.
#
# K5 CORRECTION (method rule 12: a wrong rationale is worse than none).  This
# header said, from K3 until now, "Enforced by `assert_no_forbidden_text()`
# over the emitted body, so that a future emitter cannot reintroduce one
# silently."  THAT FUNCTION DID NOT EXIST -- anywhere in the tree.  The table
# was a comment claiming an enforcement it did not have, for two waves, while
# every emitter that could have violated it happened not to.  K5 queue item 4
# adds five emitters, one of which writes a CSR for the first time in the
# generator's life, so the claim is now made true instead of edited away:
# `assert_no_forbidden_text()` is below, it is called from
# `randgen.build_stream`, and the unit tests see it FAIL before its silence
# means anything (method rule 1).  Its limits are documented AT the function --
# it is a TEXT scan, not a semantic one, and it says so.
# --------------------------------------------------------------------------
FORBIDDEN = (
    ('mip write',
     'k0 §1.3n: `mip` is a READ-ONLY mirror in the RTL and WRITABLE in M-mode '
     'in Spike -- a stream that writes it diverges by construction.'),
    # K5 REFINEMENT, and it is a refinement rather than a relaxation.  The
    # hazard is not "writing jvt", it is writing a jvt value whose low six bits
    # are nonzero: the RTL pins jvt[5:0] to zero, Spike stores what you wrote,
    # and `C.val` is a compared field.  A 64-byte-aligned base makes the two
    # sides agree by construction, which is what `isa_model`'s own zcmt note
    # has said since K2b ("every real table base is 64-byte aligned") while
    # this entry still read as an absolute ban.  The Zcmt emitter writes jvt
    # exactly once, in the PROLOGUE, from a `.align 6` table symbol.
    ('jvt write with a nonzero low 6 bits',
     'k0 §1.3e: the RTL pins jvt[5:0] to zero, Spike stores what you wrote. '
     'Both legal WARL, different values, and C.val is a compared field. A '
     '64-byte-aligned base is SAFE and is what the Zcmt emitter writes.'),
    ('mtvec MODE != 0',
     'k0 §1.3n: mtvec MODE is WARL "00" in the RTL and vectored-capable in Spike.'),
    # K5 CORRECTION, and the correction is the interesting half.  Read
    # literally, this row said "no opcode 0x0b anywhere", and EVERY irq-profile
    # stream since K3 v1.0.0 has emitted an `iret` -- in the CLINT ISR that
    # `emit.render` writes.  Nothing caught it, because the enforcement the
    # FORBIDDEN header claimed did not exist (see the header).  When the check
    # was finally implemented, in K5, it fired on `k3i01` immediately.
    #
    # The EMISSION is correct and the ROW was wrong.  `clint_irq` is oracle
    # verdict C, admitted precisely because the V3 `BRACKET_ISR` channel exists;
    # the reference never executes the bracketed handler, so the `iret` inside
    # it is never a compared record.  What the row actually forbids is opcode
    # 0x0b in the COMPARED stream -- i.e. inside the census range -- and that is
    # the scope `assert_no_forbidden_text` now enforces.  A missing instrument
    # hid a wrong rule rather than a wrong emission, which is method rule 12
    # measured rather than quoted.
    ('opcode 0x0b in the census range',
     'k0 §1.5: iret/extinguish/ignite TRAP in Spike under EVERY --isa string. '
     'Verdict C for every config. The ONE sanctioned site is the CLINT ISR, '
     'which the V3 BRACKET_ISR channel excises from the comparison; anywhere '
     'the reference actually executes, it is fatal.'),
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

# --------------------------------------------------------------------------
# K5 queue item 4 -- the five emitter-less state-bearing Z rows R-K4-2 (2)
# dropped from the campaign with "write the emitters" filed for K5.
#
# THE TOOLCHAIN SPLITS THEM IN TWO, AND THE SPLIT DECIDES WHAT CAN BE TRUSTED.
# Measured on this tree's gas/objdump 2.41, not assumed:
#   * `zicboz`, `zawrs`, `zihint`(pause) have BOTH a mnemonic and a `.option
#     arch, +<ext>` fragment, and `objdump -M no-aliases` names them back.  The
#     K3 contract is intact for them: the generator emits TEXT, gas encodes,
#     census decodes the BYTES, objdump referees.
#   * `zcmp` and `zcmt` have NEITHER.  gas 2.41 rejects `_zcmp`, `_zcmt` and
#     `_zca` outright ("unknown prefixed ISA extension") and objdump prints
#     `.word`/`.short` for their encodings.  So for exactly these two classes
#     the generator must ENCODE the 16-bit words itself and BOTH third parties
#     are gone.  The substitute referee is a known-NONZERO one (method rule 4):
#     the X3 wave's directed tests carry hand-verified literals -- `0xB852`
#     (`cm.push {ra,s0},-16`), `0xBA52` (`cm.pop {ra,s0},16`), `0xA016`
#     (`cm.jt 5`) -- and the unit tests assert this encoder reproduces all
#     three.  A third, independent referee arrives at run time: Spike decodes
#     the same bytes, so a clean lockstep cell is itself a decode check.
#     This weakening is stated rather than papered over.
# `zihint`'s ntl group is a THIRD case: gas has no `_zihintntl` and no `ntl.*`
# mnemonic, but the encodings ARE plain `add x0, x0, x{2,3,4,5}` which gas
# assembles under the base ISA and objdump names as `add`.  So gas and objdump
# both survive for ntl at the ENCODING level and only the MNEMONIC is ours.
# --------------------------------------------------------------------------
M_ZICBOZ = ('cbo.zero',)
M_ZAWRS = ('wrs.nto', 'wrs.sto')
# `pause` is `fence w,0` -- opcode 0x0F funct3 0 -- so a decoder that keys on
# the opcode alone CONFLATES it with the generator's `fence iorw,iorw`.  That is
# the R-K2-5 lesson one field deeper, and census.py decodes the full imm/rd/rs1
# to keep them apart.
M_ZIHINT = ('pause', 'ntl.p1', 'ntl.pall', 'ntl.s1', 'ntl.all')
# Zcmp: push/pop ONLY.  cm.popret/cm.popretz are deliberately absent -- both
# END with a jump to `ra`, which would put a backward-capable transfer inside
# the census range and break the DAG termination invariant.  cm.mva01s/cm.mvsa01
# are absent because their operands are a0/a1 and s0/s1, every one of which is a
# RESERVED register here (a0 is the riscv_tb verdict register).
M_ZCMP = ('cm.push', 'cm.pop')
# Zcmt: cm.jt (index < 32, no link) and cm.jalt (index >= 32, links ra).  Both
# are real control transfers, and the emitter keeps the DAG by aiming cm.jt's
# table entry at the address of the NEXT instruction and cm.jalt's at a
# returning subroutine -- see stream._e_zcmt.
M_ZCMT = ('cm.jt', 'cm.jalt')

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
    ('zicboz', ('zicboz',), A, 'Zicboz cbo.zero 64-byte block zero '
                               '(CBOZ_WRITE/CBOZ_GAP burst sequencer)'),
    # The RTL gates wrs on ZAWRS *and* ATOMICS (k0 §1.3c), so BOTH knobs are
    # required -- config.py already inherits oracle_isa's refusal of the
    # zawrs-without-atomics combination, and this row is the generator's half.
    ('zawrs', ('zawrs', 'atomics'), A, 'Zawrs wrs.nto/wrs.sto '
                                       '(WRS_WAIT, no-reservation wake)'),
    ('zihint', ('zihint',), A, 'Zihint pause + the four ntl hints'),
    ('zcmp', ('zcmp',), A, 'Zcmp cm.push/cm.pop frame pair (ZCM_* sequencer)'),
    ('zcmt', ('zcmt',), A, 'Zcmt cm.jt/cm.jalt table jump (ZCM_JT_LD)'),
    ('clint_irq', (), C, 'CLINT msip self-injection (legacy IVT delivery; '
                         'lockstep needs BRACKET_ISR=1)'),
)

# Classes whose streams this generator declines to hand to the LOCKSTEP gate
# even though nothing in the oracle table refuses them -- the reason is not
# judgeability but a STANDING SCREEN, and it is recorded here so a future run
# cannot quietly promote one.
#
# `zawrs`: R-K5 carries the standing screen forward -- the class is suite-only.
# The screen's original subject was the DIRECTED test (`rv32ua-p-extzawrs`
# scores 4 counter-CSR reads, 6 MMIO sites and an `iret`, which is why B6 has
# no gate list at all), and a GENERATED wrs stream has none of those; so the
# honest statement is that the screen is inherited, not re-derived, and the
# class's lockstep eligibility is an OPEN question this wave did not settle.
# `zihint`: pause retires in BOTH polarities (k0 §1.3b), so a zihint stream is
# byte-identical content whether the knob is on or off.  A lockstep cell over
# it would be judging the base ISA with a config label attached -- R-K2-7(2)'s
# plumbing-control shape -- so the demonstration is the SUITE, where the claim
# "the encoding retires and touches nothing" is exactly what is checked.
SUITE_ONLY_CLASSES = ('zawrs', 'zihint')

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
    ('zicboz', M_ZICBOZ),
    ('zawrs', M_ZAWRS),
    ('zihint', M_ZIHINT),
    ('zcmp', M_ZCMP),
    ('zcmt', M_ZCMT),
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


class ForbiddenEmission(Exception):
    """The emitted text contains something the FORBIDDEN table bans."""


# The `.option arch, +<frag>` fragments a config's emitted classes need, for
# the extensions gas 2.41 KNOWS.  Deliberately march-INDEPENDENT: the rv32uk
# group's `-march` is fixed in verification/isa/Makefile and cannot follow a
# config, so the arch a stream needs travels inside the stream (the pattern
# `tests/rv32ua/extzawrs.S` and friends already use).  Zcmp/Zcmt are absent
# because gas 2.41 has no `_zcmp`/`_zcmt`/`_zca` at all -- their encodings are
# emitted as raw `.short`, which needs no arch.
ARCH_FRAGMENTS = (
    ('zicboz', 'zicboz'),
    ('zawrs', 'zawrs'),
    ('zihint', 'zihintpause'),
)


def arch_fragments(cfg_isa, class_names):
    """The `.option arch, +X` fragments the census range needs, in table order."""
    out = []
    for knob, frag in ARCH_FRAGMENTS:
        if not cfg_isa.get(knob):
            continue
        for name in class_names:
            if knob in CLASS_NEEDS[name]:
                out.append(frag)
                break
    return out


# The textual signatures a FORBIDDEN item leaves in the emitted assembly.  Each
# entry is (regex, the FORBIDDEN row it enforces).  Kept as raw text rather than
# as a re-implementation of the encoders, because the thing being defended
# against is an EMITTER that writes one of these lines -- and an emitter writes
# text.  Rule 16: a proof that needs a shell one-liner beats one that needs a
# bespoke decoder.
# scope: 'file' = the whole emitted `.S`; 'range' = between k3_stream_begin and
# k3_stream_end only.  The scope is part of the rule, not an optimisation --
# see the `opcode 0x0b` FORBIDDEN row for the case that forced the distinction.
_FORBIDDEN_PATTERNS = (
    (r'\bcsr[rw][wsci]*\s+[^,;#]*\b(mip|0x344)\b', 'file', 'mip write'),
    (r'\bcsr[rw][wsci]*\s+[^,;#]*\bmhpmevent\d*\b', 'file', 'mhpmevent write'),
    (r'\bcsr[rw][wsci]*\s+[^,;#]*\b(mtvec|0x305)\b', 'file', 'mtvec MODE != 0'),
    (r'\b(iret|extinguish|ignite)\b', 'range',
     'opcode 0x0b in the census range'),
)

RANGE_BEGIN = 'k3_stream_begin:'
RANGE_END = 'k3_stream_end:'


def assert_no_forbidden_text(text, allow=()):
    """Raise `ForbiddenEmission` if the emitted text trips a FORBIDDEN row.

    WHAT THIS IS AND IS NOT, stated at the site so no future reader over-reads
    it (the defect this function replaces was exactly an over-read comment):

      * It IS a text scan of the WHOLE emitted `.S`, prologue and epilogue
        included -- the reference executes those too, so a forbidden encoding
        is just as fatal there as in the census range.
      * It is NOT semantic.  It cannot see a `csrw` whose CSR number arrives in
        a register, it cannot evaluate a `jvt` value that comes from `la`, and
        it cannot tell a mutex address from any other address held in a
        register.  Those three are structural properties of the emitters
        instead: v1.3.0 emits exactly ONE CSR write in the whole generator
        (`csrw 0x017, <reg>` from a `.align 6` table symbol, Zcmt only), and no
        emitter can construct an address outside the scratch block.
      * `allow` is the ESCAPE for a caller that owns the exception in writing.
        The Zcmt prologue's `mtvec`-free `csrw 0x017` needs no escape; the
        parameter exists so that a future emitter with a measured argument
        writes the argument down rather than deleting a pattern.

    A scan that has never rejected anything is worth nothing (method rule 1),
    so `test_randgen.py` feeds it each pattern and asserts it fires.
    """
    lines = text.splitlines()
    lo = hi = None
    for n, line in enumerate(lines):
        if line.strip() == RANGE_BEGIN:
            lo = n
        elif line.strip() == RANGE_END:
            hi = n
    bad = []
    for pat, scope, row in _FORBIDDEN_PATTERNS:
        if row in allow:
            continue
        for n, line in enumerate(lines, 1):
            if scope == 'range':
                if lo is None or hi is None or not (lo + 1 < n <= hi):
                    continue
            code = line.split('#', 1)[0]
            if re.search(pat, code):
                bad.append('line %d trips FORBIDDEN row %r (scope %s): %s'
                           % (n, row, scope, line.strip()))
    if bad:
        raise ForbiddenEmission(
            'the emitted stream contains %d forbidden encoding(s):\n  %s'
            % (len(bad), '\n  '.join(bad)))


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
