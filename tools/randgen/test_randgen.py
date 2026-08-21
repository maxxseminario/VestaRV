#!/usr/bin/python3.6
"""test_randgen.py -- unit tests for the K3 generator and its census.

    /usr/bin/python3.6 tools/randgen/test_randgen.py

No test framework (there is none installed and the tree's precedent --
`tools/cosim/test_compare.py`, `test_oracle_isa.py` -- is a plain runner).
Exit 0 == all pass.

The load-bearing tests, named so a reader knows which ones matter:

  * `test_decoder_agrees_with_objdump` -- the CENSUS INSTRUMENT VALIDATION.
    Every mnemonic the generator can emit is assembled by `gas` and decoded by
    `census.decode`, and `objdump -M no-aliases` is the referee.  Method rule 4:
    validated against KNOWN NONZERO values, one per mnemonic, never against an
    expected zero.
  * `test_naive_suffix_census_is_wrong` -- the WRONG instrument, demonstrated
    live on a real stream rather than cited (R-K2-5's `200f` lesson).
  * `test_census_catches_a_mutated_manifest` -- the manifest checker seen to
    FAIL, so its OK verdicts mean something (method rule 1).
  * `test_reproducible` / `test_no_ambient_state` -- R-DK5.
"""

from __future__ import print_function

import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.abspath(os.path.dirname(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

# A hermetic caller (the bazel py_test) has no riscv-none-elf-* on PATH and
# points RANDGEN_GCC at the driver it staged instead.
# census.PREFIX already honours RISCV_PREFIX, so the one thing needed here is
# to derive that prefix from the driver path before census is imported.
# With RANDGEN_GCC unset nothing changes and the PATH lookup is unaffected.
_RANDGEN_GCC = os.environ.get('RANDGEN_GCC')
if _RANDGEN_GCC and not os.environ.get('RISCV_PREFIX'):
    _drv = os.path.abspath(_RANDGEN_GCC)
    if _drv.endswith('gcc'):
        os.environ['RISCV_PREFIX'] = _drv[:-len('gcc')]

import census                                                # noqa: E402
import config as k3config                                    # noqa: E402
import emit                                                  # noqa: E402
import isa_model                                             # noqa: E402
import randgen                                               # noqa: E402
import rng as k3rng                                          # noqa: E402
import stream as k3stream                                    # noqa: E402

PREFIX = census.PREFIX
_RESULTS = []


def test(fn):
    _RESULTS.append(fn)
    return fn


def eq(a, b, what=''):
    if a != b:
        raise AssertionError('%s: %r != %r' % (what or 'eq', a, b))


def ok(c, what=''):
    if not c:
        raise AssertionError(what or 'assertion failed')


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def _cfg():
    return k3config.load()


def _fake_cfg(**over):
    """A COMPLETE synthetic resolved config, defaults matching the schema's."""
    isa = dict((k, False) for k in k3config.ResolvedConfig.KEYS_ISA)
    isa.update({'mul': True, 'div': True, 'atomics': True,
                'compressed': True, 'bitmanip': True})
    priv = dict((k, False) for k in k3config.ResolvedConfig.KEYS_PRIV)
    cfg = {'chipName': 'Synthetic', 'numHarts': 4, 'isa': isa, 'priv': priv}
    for k, v in over.items():
        if k in isa:
            isa[k] = v
        elif k in priv:
            priv[k] = v
        else:
            cfg[k] = v
    return k3config.ResolvedConfig(cfg)


def _assemble(lines, march='rv32imac_zba_zbb_zbc_zbs_zfinx'):
    """Assemble bare instruction lines; return the list of 32-bit words."""
    src = '.option norvc\n.option norelax\n' + '\n'.join(lines) + '\n'
    d = tempfile.mkdtemp(prefix='k3t')
    try:
        s = os.path.join(d, 'a.s')
        o = os.path.join(d, 'a.o')
        with open(s, 'w') as f:
            f.write(src)
        subprocess.check_call([PREFIX + 'gcc', '-march=' + march,
                               '-mabi=ilp32', '-c', s, '-o', o],
                              stderr=subprocess.STDOUT)
        raw = os.path.join(d, 'a.bin')
        subprocess.check_call([PREFIX + 'objcopy', '-O', 'binary',
                               '--only-section=.text', o, raw])
        import struct
        with open(raw, 'rb') as f:
            data = f.read()
        return [struct.unpack('<I', data[i:i + 4])[0]
                for i in range(0, len(data), 4)], o
    finally:
        pass  # `d` is intentionally left for objdump in the caller


def _objdump_mnemonics(obj):
    out = subprocess.check_output(
        [PREFIX + 'objdump', '-d', '-M', 'no-aliases', obj]
    ).decode('utf-8', 'replace')
    ms = []
    for line in out.splitlines():
        m = re.match(r'^\s+[0-9a-f]+:\s+[0-9a-f]{8}\s+(\S+)', line)
        if m:
            ms.append(m.group(1))
    return ms


def _one_of_each():
    """One concrete instance of every mnemonic the generator can emit."""
    rows = []           # (mnemonic, asm text)
    for m in isa_model.M_ALU_REG + isa_model.M_ZBA + isa_model.M_ZBC:
        rows.append((m, '%s x10, x11, x12' % m))
    for m in isa_model.M_ALU_IMM:
        rows.append((m, '%s x10, x11, 5' % m))
    for m in isa_model.M_ALU_SHIMM:
        rows.append((m, '%s x10, x11, 5' % m))
    rows.append(('lui', 'lui x10, 0x12345'))
    rows.append(('auipc', 'auipc x10, 0x12345'))
    for m in isa_model.M_BRANCH:
        rows.append((m, '%s x10, x11, .Lt' % m))
    rows.append(('jal', 'jal x1, .Lt'))
    rows.append(('jalr', 'jalr x0, 0(x1)'))
    for m in isa_model.M_LOAD:
        rows.append((m, '%s x10, 4(x8)' % m))
    for m in isa_model.M_STORE:
        rows.append((m, '%s x10, 4(x8)' % m))
    rows.append(('fence', 'fence iorw, iorw'))
    for m in isa_model.M_MUL + isa_model.M_DIV:
        rows.append((m, '%s x10, x11, x12' % m))
    for m in isa_model.M_AMO:
        rows.append((m, '%s x10, x11, (x8)' % m))
    rows.append(('lr.w', 'lr.w x10, (x8)'))
    rows.append(('sc.w', 'sc.w x10, x11, (x8)'))
    for m in isa_model.M_ZBB_R:
        rows.append((m, '%s x10, x11, x12' % m))
    for m in isa_model.M_ZBB_UN:
        rows.append((m, '%s x10, x11' % m))
    for m in isa_model.M_ZBB_IMM:
        rows.append((m, '%s x10, x11, 5' % m))
    for m in isa_model.M_ZBS_R:
        rows.append((m, '%s x10, x11, x12' % m))
    for m in isa_model.M_ZBS_IMM:
        rows.append((m, '%s x10, x11, 5' % m))
    return rows


def _build(seed=7, profile='seq', length=200, cfg=None, irq_observe=True):
    cfg = cfg or _cfg()
    return randgen.build_stream(cfg, 'k3u', seed, profile, length, irq_observe)


def _compile_stream(text, march='rv32imac_zba_zbb_zbc_zbs_zfinx'):
    repo = randgen.REPO
    isadir = os.path.join(repo, 'verification', 'isa')
    d = tempfile.mkdtemp(prefix='k3s')
    s = os.path.join(d, 'k3u.S')
    e = os.path.join(d, 'k3u.elf')
    with open(s, 'w') as f:
        f.write(text)
    cmd = [PREFIX + 'gcc', '-march=' + march, '-mabi=ilp32', '-static',
           '-mcmodel=medany', '-fvisibility=hidden', '-nostdlib',
           '-nostartfiles', '-DNHARTS=4',
           '-I' + os.path.join(isadir, '..', 'env', 'p'),
           '-I' + os.path.join(isadir, 'macros', 'scalar'),
           '-I' + os.path.join(repo, 'platform', 'myshkin', 'gcc', 'lib',
                               'include'),
           '-T' + os.path.join(isadir, '..', 'env', 'p', 'link.ld'),
           s, '-o', e]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    _o, err = p.communicate()
    if p.returncode != 0:
        raise AssertionError('stream failed to build:\n%s'
                             % err.decode('utf-8', 'replace')[-3000:])
    return e


# ==========================================================================
# RNG
# ==========================================================================
@test
def test_rng_is_deterministic():
    a = [k3rng.Rng(12345).next_u64() for _ in range(5)]
    b = [k3rng.Rng(12345).next_u64() for _ in range(5)]
    eq(a, b, 'same seed, same stream')
    c = k3rng.Rng(12346).next_u64()
    ok(c != a[0], 'different seed gives a different first draw')


@test
def test_rng_below_is_in_range_and_unbiased_enough():
    r = k3rng.Rng(99)
    hist = [0] * 7
    for _ in range(70000):
        v = r.below(7)
        ok(0 <= v < 7, 'below(7) in range')
        hist[v] += 1
    # 70000/7 = 10000 expected.  A modulo-biased implementation over 64-bit
    # draws would be undetectable here, so this is a RANGE test with a sanity
    # band, and it is labelled as such rather than sold as a bias proof.
    for h in hist:
        ok(abs(h - 10000) < 700, 'rough uniformity: %r' % (hist,))


@test
def test_rng_refuses_unordered_containers():
    r = k3rng.Rng(1)
    for bad in ({1, 2, 3}, {'a': 1}, frozenset([1])):
        try:
            r.choice(bad)
        except TypeError:
            continue
        raise AssertionError('choice accepted an unordered container %r' % (bad,))
    try:
        r.weighted_choice({'a': 1})
    except TypeError:
        pass
    else:
        raise AssertionError('weighted_choice accepted a dict')


@test
def test_rng_weighted_choice_respects_zero_weight():
    r = k3rng.Rng(5)
    pairs = (('a', 3), ('b', 0), ('c', 1))
    seen = set()
    for _ in range(2000):
        seen.add(r.weighted_choice(pairs))
    eq(sorted(seen), ['a', 'c'], 'zero-weight item never picked')


# ==========================================================================
# config gate
# ==========================================================================
@test
def test_sparse_config_is_refused():
    try:
        k3config.ResolvedConfig({'chipName': 'X', 'numHarts': 4,
                                 'isa': {'zicboz': True}, 'priv': {}})
    except k3config.ConfigError as e:
        ok('resolved' in str(e), 'refusal names the cause: %s' % e)
    else:
        raise AssertionError('a sparse config was accepted')
    # positive control: a complete config IS accepted
    _fake_cfg()


@test
def test_unlockstepable_config_is_refused_at_load():
    """`div` without `mul` has no Spike lever; the refusal is inherited from
    oracle_isa rather than restated, and it must reach the generator."""
    try:
        _fake_cfg(mul=False)
    except k3config.ConfigError as e:
        ok('lockstep' in str(e) or 'Spike lever' in str(e), str(e))
    else:
        raise AssertionError('div-without-mul was accepted')


# ==========================================================================
# class gating -- the two gates of isa_model
# ==========================================================================
@test
def test_config_gate_removes_classes():
    avail, blocked = isa_model.available_classes(_fake_cfg().isa)
    for c in ('div', 'amo', 'lrsc', 'zbb'):
        ok(c in avail, '%s available on the default-shaped config' % c)
    avail2, blocked2 = isa_model.available_classes(_fake_cfg(atomics=False).isa)
    ok('amo' not in avail2 and 'lrsc' not in avail2,
       'atomics off removes amo/lrsc')
    reasons = dict(blocked2)
    ok('atomics' in reasons['amo'], 'the reason names the knob: %r' % reasons)
    avail3, _ = isa_model.available_classes(_fake_cfg(bitmanip=False).isa)
    for c in ('zba', 'zbb', 'zbs', 'zbc'):
        ok(c not in avail3, 'bitmanip off removes %s' % c)
    # `zfinx` is blocked on the default-shaped config because its KNOB is off,
    # which is gate 1 (config-legality), not gate 2 (oracle-judgeability). The
    # distinction is the point: the reason string has to name the knob.
    # K5: five more knob-off classes joined the table (the emitters R-K4-2 (2)
    # filed for this wave), so the list grew.  What is asserted is unchanged in
    # substance and is deliberately stated as a SET plus a property, not as a
    # literal that has to be re-typed every time a class is added: on a
    # default-shaped config EVERY blocked class is blocked for the CONFIG
    # reason and none for the oracle one.
    eq(sorted(c for (c, _w) in blocked),
       ['zawrs', 'zcmp', 'zcmt', 'zfinx', 'zicboz', 'zihint'],
       'the knob-off classes on the default-shaped config')
    for c, w in blocked:
        ok('config knob(s) off: %s' % c in w or 'config knob(s) off' in w,
           'the reason for %s is the KNOB, not the oracle: %r' % (c, w))
    ok(not [w for _c, w in blocked if 'oracle verdict' in w],
       'nothing on a default-shaped config is refused by the ORACLE gate')


@test
def test_oracle_gate_blocks_verdict_b():
    """A verdict-B knob's class must not reach a stream by default.

    K2b UPDATE. In K3 this could only be tested INDIRECTLY -- no class needed a
    verdict-B knob, so the refusal arm in `available_classes` had never
    executed (R-K3-2 D-3). K2b adds a `zfinx` CLASS and DERIVES the class
    verdict from the knob verdicts, so the arm is now reachable: the assertions
    below run it for real, on a synthetic B knob, and the K2b implementation
    report quotes the same transition on the live table.
    """
    for k in ('zihpm', 'trapCsr', 'umode', 'pmp'):
        eq(isa_model.KNOB_ORACLE_STATUS[k], isa_model.B, '%s is verdict B' % k)
    eq(isa_model.KNOB_ORACLE_STATUS['zfinx'], isa_model.E,
       'zfinx is verdict E -- eligible via the K2b `zfinx-fflags` amendment')
    # K2b amendment 2: zicboz and zcmt leave B for E.
    # K5 CORRECTION to this comment (method rule 12 -- a wrong rationale is
    # worse than none, and this one would have read as current): at K2b these
    # two had NO emitter class, so the flip bought JUDGEABILITY and not
    # coverage.  K5 queue item 4 adds the emitters, so from v1.3.0 the flip
    # buys both, and the tail of this test now asserts the OPPOSITE of what it
    # asserted at K2b.  The change is recorded here rather than made silently.
    eq(isa_model.KNOB_ORACLE_STATUS['zicboz'], isa_model.E,
       'zicboz is verdict E -- eligible via `cboz-stores`')
    eq(isa_model.KNOB_ORACLE_STATUS['zcmt'], isa_model.E,
       'zcmt is verdict E -- eligible via `cmjt-load`')
    eq(isa_model.KNOB_AMENDMENTS['zicboz'], ('cboz-stores',),
       'and it names the amendment it depends on')
    eq(isa_model.KNOB_AMENDMENTS['zcmt'], ('cmjt-load',),
       'and so does zcmt')
    eq(isa_model.CLASS_ORACLE['zfinx'], isa_model.E,
       'and the CLASS verdict DERIVES from it')
    eq(isa_model.required_amendments(['zfinx']), ['zfinx-fflags'],
       'the class names the amendment it depends on')
    # THE REFUSAL ARM, executed. A knob forced back to B must take its class
    # out of the emittable set with the ORACLE reason, not the knob reason --
    # and `allow_unmodelled` must put it back.
    saved = isa_model.KNOB_ORACLE_STATUS['zfinx']
    saved_cls = isa_model.CLASS_ORACLE['zfinx']
    try:
        isa_model.KNOB_ORACLE_STATUS['zfinx'] = isa_model.B
        isa_model.CLASS_ORACLE['zfinx'] = isa_model.class_oracle('zfinx')
        avail, blocked = isa_model.available_classes(_fake_cfg(zfinx=True).isa)
        ok('zfinx' not in avail, 'a verdict-B class is REFUSED')
        ok('oracle verdict B' in dict(blocked)['zfinx'],
           'and the reason is the ORACLE: %r' % (blocked,))
        avail2, _ = isa_model.available_classes(_fake_cfg(zfinx=True).isa,
                                                allow_unmodelled=True)
        ok('zfinx' in avail2,
           '--allow-unmodelled admits it, in writing')
    finally:
        isa_model.KNOB_ORACLE_STATUS['zfinx'] = saved
        isa_model.CLASS_ORACLE['zfinx'] = saved_cls
    # The knob-on-with-no-emitter report still works, and the class that
    # DEMONSTRATES it changed: `zicboz` had no emitter at K2b and has one now,
    # so the standing example is `zihpm` -- verdict B, no emitter, and R-K4-2
    # (2)'s reason for that (a stream that reads an HPM counter diverges by
    # construction) is unchanged.
    ne = isa_model.knobs_on_without_emitter(_fake_cfg(zihpm=True).isa,
                                            _fake_cfg().priv)
    names = [k for (k, _v, _n) in ne]
    ok('zihpm' in names, 'a knob-on-with-no-emitter is NAMED: %r' % names)
    ne2 = isa_model.knobs_on_without_emitter(_fake_cfg(zicboz=True).isa,
                                             _fake_cfg().priv)
    ok('zicboz' not in [k for (k, _v, _n) in ne2],
       'zicboz has an emitter from v1.3.0 and must NOT be reported as lacking one')


@test
def test_verdict_c_is_admitted_and_verdict_b_is_not():
    """The asymmetry is deliberate and is asserted, not left to the comment."""
    eq(isa_model.CLASS_ORACLE['clint_irq'], isa_model.C, 'clint_irq is C')
    avail, _ = isa_model.available_classes(_fake_cfg().isa)
    ok('clint_irq' in avail,
       'verdict C is admitted -- the V3 BRACKET_ISR channel exists')


# ==========================================================================
# stream discipline
# ==========================================================================
def _rd_of(text):
    """Destination register number, or None for stores/branches/fence."""
    parts = text.split(None, 1)
    m = parts[0]
    if m in isa_model.M_STORE or m in isa_model.M_BRANCH or m == 'fence':
        return None
    first = parts[1].split(',')[0].strip()
    mm = re.match(r'^x(\d+)$', first)
    return int(mm.group(1)) if mm else None


@test
def test_reserved_registers_are_never_written():
    for seed in (1, 2, 3, 11, 101):
        b, _t = _build(seed=seed, profile='base', length=400)
        for it in b.items:
            if isinstance(it, k3stream.Label):
                continue
            rd = _rd_of(it.text)
            if rd is None:
                continue
            if it.cls == 'jal':
                ok(rd in (k3stream.R_ZERO, k3stream.R_RA),
                   'jal writes only x0/ra, got x%d in %r' % (rd, it.text))
                continue
            ok(rd not in (k3stream.R_BASE_A, k3stream.R_BASE_B,
                          k3stream.R_SP, k3stream.R_GP, k3stream.R_A0),
               'reserved x%d written by %r' % (rd, it.text))


@test
def test_every_memory_access_is_in_window_and_aligned():
    lo_a, hi_a = 0, k3stream.SCRATCH_BYTES - 1
    lo_b = -k3stream.BASE_B_OFF
    hi_b = k3stream.SCRATCH_BYTES - k3stream.BASE_B_OFF - 1
    widths = {'lb': 1, 'lbu': 1, 'lh': 2, 'lhu': 2, 'lw': 4,
              'sb': 1, 'sh': 2, 'sw': 4}
    checked = 0
    for seed in (4, 5, 6, 77):
        b, _t = _build(seed=seed, profile='base', length=500)
        for it in b.items:
            if isinstance(it, k3stream.Label):
                continue
            m = it.text.split(None, 1)[0]
            mo = re.search(r'(-?\d+)\(x(\d+)\)$', it.text)
            if it.cls in ('load', 'store'):
                ok(mo, 'memory operand parsed from %r' % it.text)
                off, base = int(mo.group(1)), int(mo.group(2))
                ok(base in (k3stream.R_BASE_A, k3stream.R_BASE_B),
                   'base is reserved: %r' % it.text)
                w = widths[m]
                eq(off % w, 0, 'aligned: %r' % it.text)
                lo, hi = (lo_a, hi_a) if base == k3stream.R_BASE_A \
                    else (lo_b, hi_b)
                ok(lo <= off and off + w - 1 <= hi,
                   'in window: %r (window %d..%d)' % (it.text, lo, hi))
                checked += 1
            elif m == 'addi' and mo is None:
                # the AMO/LR-SC address setup: `addi xt, base, off`
                am = re.match(r'^addi\s+x(\d+), x(\d+), (-?\d+)$',
                              ' '.join(it.text.split()))
                if am and int(am.group(2)) in (k3stream.R_BASE_A,
                                               k3stream.R_BASE_B):
                    base, off = int(am.group(2)), int(am.group(3))
                    eq(off % 4, 0, 'word-aligned AMO address: %r' % it.text)
                    lo, hi = (lo_a, hi_a) if base == k3stream.R_BASE_A \
                        else (lo_b, hi_b)
                    ok(lo <= off and off + 3 <= hi,
                       'AMO address in window: %r' % it.text)
                    checked += 1
    ok(checked > 200, 'the check actually ran over %d accesses' % checked)


@test
def test_branches_are_forward_only():
    for seed in (8, 9, 10):
        b, _t = _build(seed=seed, profile='base', length=400)
        pos = {}
        for i, it in enumerate(b.items):
            if isinstance(it, k3stream.Label):
                pos[it.name] = i
        n = 0
        for i, it in enumerate(b.items):
            if isinstance(it, k3stream.Label) or it.cls != 'branch':
                continue
            tgt = it.text.rsplit(',', 1)[1].strip()
            ok(tgt in pos, 'branch target %r exists' % tgt)
            ok(pos[tgt] > i, 'branch at %d targets %d (forward)'
               % (i, pos[tgt]))
            n += 1
        ok(n > 5, 'saw %d branches' % n)


@test
def test_lrsc_pairs_are_adjacent_and_unbranchable():
    for seed in (12, 13, 14):
        b, _t = _build(seed=seed, profile='seq', length=400)
        labels = set()
        for it in b.items:
            if isinstance(it, k3stream.Label):
                labels.add(it.name)
        pairs = 0
        for i, it in enumerate(b.items):
            if isinstance(it, k3stream.Label) or it.cls != 'lrsc':
                continue
            if it.text.startswith('lr.w'):
                nxt = b.items[i + 1]
                ok(not isinstance(nxt, k3stream.Label),
                   'no label between lr.w and sc.w')
                ok(nxt.text.startswith('sc.w'),
                   'lr.w is immediately followed by sc.w, got %r' % nxt.text)
                pairs += 1
        ok(pairs > 3, 'saw %d lr/sc pairs' % pairs)


@test
def test_no_pseudo_instructions_in_the_census_range():
    """The census contract: one emitted line == one machine instruction."""
    banned = ('li', 'la', 'mv', 'nop', 'ret', 'call', 'tail', 'j', 'jr',
              'beqz', 'bnez', 'bgez', 'blez', 'bltz', 'bgtz', 'seqz', 'snez',
              'not', 'neg', 'sext.w', 'lla')
    for seed in (15, 16, 17):
        b, _t = _build(seed=seed, profile='irq', length=400)
        for it in b.items:
            if isinstance(it, k3stream.Label):
                continue
            m = it.text.split(None, 1)[0]
            ok(m not in banned, 'pseudo-instruction %r in the range' % m)


@test
def test_irq_arms_never_precede_an_lrsc():
    """The reference's ISR window is bracketed out, so its reservation survives
    while the RTL's may not -- a harness asymmetry, excluded by construction."""
    for seed in (21, 22, 23):
        b, _t = _build(seed=seed, profile='irq', length=500)
        ok(b.irq_sites > 0, 'the irq profile emitted arms')
        for i, it in enumerate(b.items):
            if isinstance(it, k3stream.Label):
                continue
            if it.text.startswith('sw') and '0(x' in it.text:
                # candidate msip arm: the very next instruction must not be
                # part of an lr/sc template
                for j in range(i + 1, min(i + 3, len(b.items))):
                    nx = b.items[j]
                    if isinstance(nx, k3stream.Label):
                        continue
                    ok(not nx.text.startswith('lr.w'),
                       'an IRQ arm precedes an lr.w at item %d' % j)
                    break


# ==========================================================================
# reproducibility -- R-DK5
# ==========================================================================
@test
def test_reproducible():
    cfg = _cfg()
    a = randgen.build_stream(cfg, 'k3u', 4242, 'seq', 300, True)[1]
    b = randgen.build_stream(cfg, 'k3u', 4242, 'seq', 300, True)[1]
    eq(a, b, 'identical inputs, byte-identical .S')
    c = randgen.build_stream(cfg, 'k3u', 4243, 'seq', 300, True)[1]
    ok(a != c, 'a different seed gives a different stream')


@test
def test_no_ambient_state():
    """Emission must not depend on anything outside (seed, profile, length,
    config).  Perturb the environment and the PID-sensitive things Python
    exposes, and demand the same bytes."""
    cfg = _cfg()
    base = randgen.build_stream(cfg, 'k3u', 777, 'irq', 300, True)[1]
    old = os.environ.get('K3_NOISE')
    os.environ['K3_NOISE'] = 'x' * 97
    try:
        # touch the hash-randomised surface on purpose
        _ = {str(i): i for i in range(500)}
        _ = set('abcdefghijklmnop')
        again = randgen.build_stream(cfg, 'k3u', 777, 'irq', 300, True)[1]
    finally:
        if old is None:
            del os.environ['K3_NOISE']
        else:
            os.environ['K3_NOISE'] = old
    eq(base, again, 'emission is independent of ambient state')


@test
def test_reproduction_line_is_in_the_file():
    cfg = _cfg()
    text = randgen.build_stream(cfg, 'k3rl', 31337, 'seq', 120, True)[1]
    for needle in ('seed      : 31337', 'profile   : seq',
                   emit.GENERATOR + ' ' + emit.VERSION, cfg.digest()):
        ok(needle in text, 'reproduction line carries %r' % needle)


@test
def test_name_length_contract_is_enforced_at_the_source():
    randgen.rcf_basename('k3s01')                    # fine
    try:
        randgen.rcf_basename('waytoolongname')
    except SystemExit as e:
        ok('22-char' in str(e), 'refusal names the contract: %s' % e)
    else:
        raise AssertionError('an over-long stream name was accepted')


# ==========================================================================
# THE CENSUS INSTRUMENT
# ==========================================================================
@test
def test_decoder_agrees_with_objdump():
    rows = _one_of_each()
    lines = [t for (_m, t) in rows] + ['.Lt:']
    words, obj = _assemble(lines)
    dumped = _objdump_mnemonics(obj)
    eq(len(words), len(rows), 'one word per mnemonic (no pseudo expansion)')
    eq(len(dumped), len(rows), 'objdump saw the same number')
    bad = []
    for (want, _t), w, od in zip(rows, words, dumped):
        got = census.decode(w)
        if got != want or od != want:
            bad.append('%-10s encoded 0x%08x  census=%-10s objdump=%s'
                       % (want, w, got, od))
    ok(not bad, 'decoder/objdump disagreements:\n  ' + '\n  '.join(bad))
    ok(len(rows) >= 80, 'validated against %d distinct mnemonics' % len(rows))


@test
def test_every_emittable_mnemonic_has_a_class():
    for m, _t in _one_of_each():
        ok(m in census.MNEMONIC_CLASS, 'census classifies %r' % m)
        ok(m in isa_model.MNEMONIC_CLASS, 'isa_model classifies %r' % m)
        eq(census.MNEMONIC_CLASS[m], isa_model.MNEMONIC_CLASS[m],
           'the two independent tables agree on %r' % m)


@test
def test_decoder_rejects_what_it_cannot_name():
    """`None`, never a guess.  0x0000000b is the VestaRV custom opcode -- the
    one family k3_spec.md forbids outright -- and it must NOT decode.

    K5 UPDATE, and the reason is recorded rather than the list quietly edited:
    `0x0045a00f` (`cbo.zero a1`) was in this list because until v1.3.0 nothing
    could emit it, so naming it would have been a decoder guessing beyond the
    generator.  v1.3.0 has a Zicboz emitter, the decode is a full field decode
    (funct3=010, rd=x0, imm=0x004) and objdump referees it, so it MOVES from
    this list to `test_zicboz_and_zawrs_round_trip_through_gas_and_objdump`.
    `0x00000073` (`ecall`) stays: the SYSTEM arm added for Zawrs names the two
    wrs encodings and nothing else.
    """
    for w in (0x0000000b, 0x0000100b, 0x0200100b, 0x00000073):
        eq(census.decode(w), None, 'refuses to name 0x%08x' % w)
    eq(census.decode(0x0045a00f), 'cbo.zero',
       '0x0045a00f is now a NAMED encoding -- see the docstring')


@test
def test_census_matches_manifest_on_a_real_stream():
    cfg = _cfg()
    b, text = randgen.build_stream(cfg, 'k3u', 4242, 'seq', 300, True)
    man = randgen.manifest_for(b, cfg, 'k3u', 4242, 'seq', 300, True, text)
    elf = _compile_stream(text)
    cen = census.census(elf)
    bad = census.check_against_manifest(cen, man)
    ok(not bad, 'census vs manifest:\n  ' + '\n  '.join(bad))
    # `length` bounds the ITEM count (labels included), so the instruction
    # count is a little under it; the exact-match assertion above is the real
    # test and this is only a non-triviality bar.
    ok(cen['total'] >= 250, 'the range is non-trivial (%d)' % cen['total'])
    for c in ('div', 'amo', 'lrsc', 'mul'):
        ok(cen['counts'].get(c, 0) > 0,
           'the sequencer class %r is present with %d' % (c, cen['counts'].get(c, 0)))


@test
def test_census_catches_a_mutated_manifest():
    """The checker seen to FAIL.  A checker never seen to fail proves nothing."""
    cfg = _cfg()
    b, text = randgen.build_stream(cfg, 'k3u', 4242, 'seq', 300, True)
    man = randgen.manifest_for(b, cfg, 'k3u', 4242, 'seq', 300, True, text)
    elf = _compile_stream(text)
    cen = census.census(elf)
    eq(census.check_against_manifest(cen, man), [], 'clean before mutation')
    mut = dict(man)
    mut['class_counts'] = dict(man['class_counts'])
    mut['class_counts']['div'] = mut['class_counts']['div'] + 1
    bad = census.check_against_manifest(cen, mut)
    ok(any('CLASS div' in x for x in bad), 'off-by-one in div caught: %r' % bad)
    mut2 = dict(man)
    mut2['class_counts'] = dict(man['class_counts'])
    del mut2['class_counts']['lrsc']
    bad2 = census.check_against_manifest(cen, mut2)
    ok(any('CLASS lrsc' in x for x in bad2), 'a dropped class caught: %r' % bad2)


@test
def test_naive_suffix_census_is_wrong():
    """R-K2-5, demonstrated instead of cited.

    The S5 ledger's "ends `200f`" shorthand generalises to "match the low
    sixteen bits", and rs1 lives in bits 19:15 -- inside those sixteen.  On a
    real K3 stream, whose rd/rs1/rs2 come from a 25-register pool, the naive
    matcher must both MISS real instances and FALSELY HIT unrelated ones.
    """
    cfg = _cfg()
    _b, text = randgen.build_stream(cfg, 'k3u', 4242, 'base', 1200, True)
    elf = _compile_stream(text)
    cen = census.census(elf)
    words = [w for _a, w in census.stream_words(elf)]

    # Pick the most common mnemonic in the image and use ONE of its encodings'
    # low sixteen bits as the "pattern", exactly as the ledger's shorthand
    # would have been derived from a single hand-assembled example.
    target = max(cen['mnemonics'].items(), key=lambda kv: (kv[1], kv[0]))[0]
    sample = next(w for w in words if census.decode(w) == target)
    naive = census.naive_suffix_count(elf, '%04x' % (sample & 0xFFFF))
    truth = cen['mnemonics'][target]
    ok(truth > 1, 'more than one %s to be wrong about (%d)' % (target, truth))
    ok(naive < truth,
       'the naive suffix matcher MISSES: pattern from a real %s matched '
       'naive=%d where the field decode finds %d' % (target, naive, truth))


@test
def test_naive_suffix_census_also_FALSE_HITS():
    """The sharper half of the claim (k3_predictions.md P6): the naive matcher
    does not merely undercount, it CONFLATES.  Bits 15:0 hold opcode, rd,
    funct3 and rs1's low bit -- but NOT funct7 -- so `add`/`sub`,
    `srli`/`srai`/`rori`/`bexti` and friends are indistinguishable to it."""
    cfg = _cfg()
    _b, text = randgen.build_stream(cfg, 'k3u', 4242, 'base', 1200, True)
    elf = _compile_stream(text)
    words = [w for _a, w in census.stream_words(elf)]
    by_suffix = {}
    for w in words:
        by_suffix.setdefault(w & 0xFFFF, set()).add(census.decode(w))
    collisions = sorted((suf, sorted(ms)) for suf, ms in by_suffix.items()
                        if len(ms) > 1)
    ok(collisions,
       'no 16-bit suffix in this stream maps to two different mnemonics -- '
       'the FALSE-HIT half of P6 is then unproven and must be recorded as a '
       'PARTIAL rather than widened away')


@test
def test_census_refuses_a_compressed_encoding_in_the_range():
    """`.option norvc` is supposed to make this impossible, so if it ever
    happens the census must say so loudly rather than mis-count."""
    ok(hasattr(census, 'stream_words'))
    d = tempfile.mkdtemp(prefix='k3c')
    # Build a tiny ELF whose range deliberately contains a 16-bit encoding.
    src = ('.globl k3_stream_begin\n.globl k3_stream_end\n'
           '.text\nk3_stream_begin:\n'
           '  .option rvc\n  c.addi x10, 1\n  c.addi x10, 1\n'
           'k3_stream_end:\n')
    s = os.path.join(d, 'c.S')
    e = os.path.join(d, 'c.elf')
    with open(s, 'w') as f:
        f.write(src)
    subprocess.check_call([PREFIX + 'gcc', '-march=rv32imac', '-mabi=ilp32',
                           '-nostdlib', '-nostartfiles', '-Wl,-Ttext=0x8200',
                           s, '-o', e], stderr=subprocess.STDOUT)
    try:
        census.stream_words(e, section='.text')
    except census.CensusError as ex:
        ok('compressed' in str(ex) or 'norvc' in str(ex), str(ex))
    else:
        raise AssertionError('a compressed encoding in the range went unnoticed')


# ==========================================================================
# the negative controls for the STREAM's own runtime detector
# ==========================================================================
@test
def test_negative_controls_are_constructible():
    """The epilogue guard checks must be seen to FAIL, which needs a stream
    that violates the discipline on purpose.  These are NOT the acceptance
    mutants of k3_spec.md 6 (those are authored by a second, blind agent and
    target the generator's LEGALITY); they are the method-rule-1 controls for
    the guard words and the base-register check."""
    cfg = _cfg()
    for kind in randgen.NEGCTRL_KINDS:
        b, text = randgen.build_stream(cfg, 'k3n', 5, 'base', 120, True,
                                       negctrl=kind)
        ok('K3 NEGATIVE CONTROL' in text, 'the file announces itself: %s' % kind)
        _compile_stream(text)


# ==========================================================================
# K5 queue item 4 -- the five emitter-less state-bearing Z rows.
#
# The ORDER of these tests is the order of the argument they make: first that
# the two instruments (encoder, decoder) agree with a third party that is not
# either of them; then that each emitter's SAFETY claim holds on real streams;
# then that the oracle bookkeeping says what the manifests will carry.
# ==========================================================================
def _cfg_knob(knob):
    """A complete synthetic resolved config with `knob` (and its dependants) on."""
    over = {knob: True}
    return _fake_cfg(**over)


# The literals two X3-wave directed tests carry, hand-verified against the RTL
# and against Spike long before this generator existed.  gas 2.41 cannot
# assemble a `cm.*` mnemonic and objdump 2.41 cannot name one, so for Zcmp and
# Zcmt these five words are the ONLY third-party referee available -- method
# rule 4's "validate against a known NONZERO value", with the nonzero values
# supplied by somebody else's wave.
_ZCM_KNOWN_GOOD = (
    # (word, mnemonic, source, kwargs for the encoder)
    (0xB852, 'cm.push', 'tests/rv32ua/extzcmp.S', ('push', 5, 0)),
    (0xBA52, 'cm.pop', 'tests/rv32ua/extzcmp.S', ('pop', 5, 0)),
    (0xA016, 'cm.jt', 'tests/rv32ua/extzcmt.S', ('jt', 5, None)),
    (0xA00E, 'cm.jt', 'tests/rv32ua/shcmt.S', ('jt', 3, None)),
    (0xA07E, 'cm.jt', 'tests/rv32ua/shcmt.S', ('jt', 31, None)),
    (0xA082, 'cm.jalt', 'tests/rv32ua/shcmt.S', ('jt', 32, None)),
    (0xA0A2, 'cm.jalt', 'tests/rv32ua/shcmt.S', ('jt', 40, None)),
)


@test
def test_zcm_encoder_reproduces_the_directed_tests_literals():
    for word, mnem, src, (kind, a, b) in _ZCM_KNOWN_GOOD:
        if kind == 'push':
            got = k3stream.zcmp_push_pop_word(True, a, b)
        elif kind == 'pop':
            got = k3stream.zcmp_push_pop_word(False, a, b)
        else:
            got = k3stream.zcmt_word(a)
        eq('0x%04X' % got, '0x%04X' % word,
           'encoder vs %s (%s)' % (src, mnem))
        eq(census.decode16(word), mnem, 'decoder vs %s' % src)


@test
def test_zcm_decoder_refuses_what_it_must_not_name():
    """The 16-bit decoder's scope is four encodings, and everything else in the
    C2/funct3=101 space must come back None -- including the two pop variants
    that END IN A JUMP (cm.popret/cm.popretz) and would break the DAG."""
    ok(census.decode16(0x0505) is None, 'c.addi is not named')
    ok(census.decode16(0x4108) is None, 'c.lw is not named')
    # push/pop family with the sub-field set to popretz (10) and popret (11).
    base = k3stream.zcmp_push_pop_word(True, 8, 1)
    for sub, what in ((2, 'cm.popretz'), (3, 'cm.popret')):
        w = (base & ~(0x3 << 9)) | (sub << 9)
        ok(census.decode16(w) is None, '%s must not be named' % what)
    # rlist 0-3 are illegal and c_dec.vhd refuses them.
    for rl in range(4):
        w = (base & ~(0xF << 4)) | (rl << 4)
        ok(census.decode16(w) is None, 'rlist %d must not be named' % rl)
    # bit8 must be 0 and bit11 must be 1 -- both are encoding requirements the
    # RTL enforces, so a word violating either is not a cm.push.
    ok(census.decode16(base | (1 << 8)) is None, 'bit8=1 must not be named')
    ok(census.decode16(base & ~(1 << 11)) is None, 'bit11=0 must not be named')


@test
def test_pause_is_not_fence_and_ntl_is_not_add():
    """Both are the R-K2-5 lesson one field deeper: the opcode alone conflates
    them, and the discriminator is in the fields."""
    words, obj = _assemble(['pause', 'fence iorw, iorw',
                            'add x0, x0, x2', 'add x0, x0, x5',
                            'add x10, x11, x12'],
                           march='rv32imac_zihintpause')
    eq(census.decode(words[0]), 'pause', 'pause')
    eq(census.decode(words[1]), 'fence', 'fence')
    eq(census.decode(words[2]), 'ntl.p1', 'ntl.p1')
    eq(census.decode(words[3]), 'ntl.all', 'ntl.all')
    eq(census.decode(words[4]), 'add', 'an ordinary add stays an add')
    eq(census.MNEMONIC_CLASS['pause'], 'zihint')
    eq(census.MNEMONIC_CLASS['fence'], 'fence')
    eq(census.MNEMONIC_CLASS['ntl.p1'], 'zihint')
    # objdump 2.41 has no `ntl.*` mnemonic, so the third party referees the
    # ENCODING and this module owns the NAME.  Stated, not glossed.
    ms = _objdump_mnemonics(obj)
    eq(ms[0], 'pause', 'objdump names pause')
    eq(ms[2], 'add', 'objdump sees ntl as a plain add -- referee limit')


@test
def test_zicboz_and_zawrs_round_trip_through_gas_and_objdump():
    words, obj = _assemble(['cbo.zero (x31)', 'cbo.zero (x4)',
                            'wrs.nto', 'wrs.sto'],
                           march='rv32imac_zicboz_zawrs')
    eq([census.decode(w) for w in words],
       ['cbo.zero', 'cbo.zero', 'wrs.nto', 'wrs.sto'])
    eq(_objdump_mnemonics(obj), ['cbo.zero', 'cbo.zero', 'wrs.nto', 'wrs.sto'],
       'objdump is the third party for these three classes')
    # The sibling cbo.* operations TRAP on this core (cbozill.S is the standing
    # proof), so the instrument must refuse to name them rather than count them.
    for imm in (0, 1, 2):
        w = (imm << 20) | (2 << 12) | 0x0F
        ok(census.decode(w) is None, 'cbo imm=%d must not be named' % imm)


@test
def test_each_new_emitter_builds_and_censuses_clean():
    """One dense stream per class, on that class's config, built with gas and
    counted from its own decoded image."""
    want = {'zicboz': 'cbo.zero', 'zawrs': 'wrs.nto', 'zihint': 'pause',
            'zcmp': 'cm.push', 'zcmt': 'cm.jt'}
    for knob in ('zicboz', 'zawrs', 'zihint', 'zcmp', 'zcmt'):
        cfg = _cfg_knob(knob)
        b, text = randgen.build_stream(cfg, 'k3u', 11, 'zext', 240, True)
        man = randgen.manifest_for(b, cfg, 'k3u', 11, 'zext', 240, True, text)
        e = _compile_stream(text)
        cen = census.census(e)
        bad = census.check_against_manifest(cen, man)
        eq(bad, [], 'census vs manifest for %s' % knob)
        ok(cen['counts'].get(knob, 0) > 0,
           '%s stream actually contains %s encodings' % (knob, knob))
        ok(cen['mnemonics'].get(want[knob], 0) > 0,
           '%s stream contains at least one %s' % (knob, want[knob]))


@test
def test_zicboz_blocks_never_escape_the_scratch_window():
    """The RTL rounds the block base DOWN to 64, so containment is a property
    of the OFFSET, not of the address the instruction names."""
    cfg = _cfg_knob('zicboz')
    b, text = randgen.build_stream(cfg, 'k3u', 3, 'zext', 400, True)
    # Scope matters here, and the first cut of this test got it wrong in a way
    # worth keeping: it matched EVERY `addi xN, x8, imm`, which also catches
    # `_amo_addr_reg`'s address setup -- whose offsets legitimately run to 247.
    # The claim is about the addi that FEEDS A cbo.zero, so pair them.
    seq = [it for it in b.items if not isinstance(it, k3stream.Label)]
    offs = []
    for i, it in enumerate(seq):
        if it.cls != 'zicboz':
            continue
        prev = seq[i - 1].text.strip()
        m = re.match(r'addi\s+x(\d+), x%d, (-?\d+)$' % k3stream.R_BASE_A, prev)
        ok(m is not None, 'cbo.zero is fed by an addi off base A: %s' % prev)
        rt = re.match(r'cbo\.zero\s+\(x(\d+)\)$', it.text.strip())
        ok(rt is not None and rt.group(1) == m.group(1),
           'and by the SAME register it was just given')
        offs.append(int(m.group(2)))
    ok(offs, 'the stream materialised at least one cbo.zero address')
    top = k3stream.SCRATCH_BYTES - k3stream.RESERVED_TAIL
    for off in offs:
        base = off & ~(k3stream.CBOZ_BLOCK_BYTES - 1)
        ok(0 <= base and base + k3stream.CBOZ_BLOCK_BYTES <= top,
           'block [%d,%d) from offset %d is inside [0,%d)'
           % (base, base + k3stream.CBOZ_BLOCK_BYTES, off, top))


@test
def test_zcmp_frames_are_balanced_and_unbranchable():
    """`sp` survives because push and pop carry the same rlist and spimm and
    nothing can be placed between them -- the `lr.w`/`sc.w` argument, reused."""
    cfg = _cfg_knob('zcmp')
    b, _text = randgen.build_stream(cfg, 'k3u', 5, 'zext', 400, True)
    seq = [it for it in b.items if not isinstance(it, k3stream.Label)]
    labels_at = set(at for at, _n in b.labels)
    npair = 0
    for i, it in enumerate(seq):
        if it.cls != 'zcmp' or 'cm.push' not in it.text:
            continue
        npair += 1
        j = i + 1
        while j < len(seq) and seq[j].cls != 'zcmp':
            # only pool-register arithmetic may sit inside a frame
            m = re.match(r'addi\s+x(\d+), x\1, ', seq[j].text.strip())
            ok(m is not None, 'inside a frame: %s' % seq[j].text)
            r = int(m.group(1))
            ok(r in k3stream.POOL, 'x%d clobbered inside a frame is in POOL' % r)
            ok(r not in k3stream.RESERVED, 'x%d is not reserved' % r)
            j += 1
        ok(j < len(seq) and 'cm.pop' in seq[j].text, 'every push has its pop')
        pw = int(re.search(r'0x([0-9A-F]{4})', seq[i].text).group(1), 16)
        qw = int(re.search(r'0x([0-9A-F]{4})', seq[j].text).group(1), 16)
        eq(census.zcmp_fields(pw), census.zcmp_fields(qw),
           'push and pop carry the same (rlist, spimm)')
    ok(npair > 0, 'the stream contains at least one frame')
    for at in labels_at:
        ok(at <= len(b.items), 'label index is in range')


@test
def test_zcmt_indices_and_table_agree():
    """Every emitted index has a table entry, cm.jt indices are < 32 and
    cm.jalt indices are >= 32 -- the split the RTL's `zcm_jt_link` makes."""
    cfg = _cfg_knob('zcmt')
    b, text = randgen.build_stream(cfg, 'k3u', 9, 'zext', 400, True)
    used = dict(b.jt_entries)
    n_jt = n_jalt = 0
    for it in b.items:
        if isinstance(it, k3stream.Label) or it.cls != 'zcmt':
            continue
        w = int(re.search(r'0x([0-9A-F]{4})', it.text).group(1), 16)
        idx = census.zcmt_index(w)
        ok(idx in used, 'index %d has a table entry' % idx)
        if census.decode16(w) == 'cm.jt':
            ok(idx < 32, 'cm.jt index %d < 32' % idx)
            n_jt += 1
        else:
            ok(idx >= 32, 'cm.jalt index %d >= 32' % idx)
            n_jalt += 1
    ok(n_jt > 0 and n_jalt > 0, 'both shapes are exercised (%d/%d)'
       % (n_jt, n_jalt))
    ok('k3_jvt:' in text and '.align 6' in text, 'the table is 64-byte aligned')
    ok('csrw 0x017' in text, 'jvt is installed in the prologue')
    # Every index below the largest one used must appear in the table, and the
    # ones no instruction names must point at `k3_bad` -- fail-safe, method
    # rule 15.  Whether any gap EXISTS depends on the draw (a stream that uses
    # all 32 cm.jt slots has none), so the gap is constructed rather than hoped
    # for: this checks the rendering directly.
    tbl = text.split('k3_jvt:')[1].splitlines()
    words = [l.strip() for l in tbl if l.strip().startswith('.word')]
    eq(len(words), max(used) + 1, 'the table covers every index up to the max')
    for i, w in enumerate(words):
        if i in used:
            ok(used[i] in w, 'entry %d names its target' % i)
        else:
            ok('k3_bad' in w, 'unused entry %d fails loudly' % i)


@test
def test_zawrs_is_never_emitted_with_a_live_reservation():
    """The wake this relies on is `resv_valid_ext = '0'`; the structural claim
    is that no `wrs` can sit between an `lr.w` and its `sc.w`."""
    cfg = _cfg_knob('zawrs')
    b, _text = randgen.build_stream(cfg, 'k3u', 13, 'zext', 400, True)
    seq = [it for it in b.items if not isinstance(it, k3stream.Label)]
    live = False
    nwrs = 0
    for it in seq:
        if it.cls == 'lrsc' and it.text.strip().startswith('lr.w'):
            live = True
        elif it.cls == 'lrsc' and it.text.strip().startswith('sc.w'):
            live = False
        elif it.cls == 'zawrs':
            nwrs += 1
            ok(not live, 'a wrs was emitted with a live reservation')
    ok(nwrs > 0, 'the stream contains at least one wrs (%d)' % nwrs)


@test
def test_forbidden_text_check_is_seen_to_fail():
    """A scan that has never rejected anything is worth nothing (method rule 1).

    One synthetic violation per FORBIDDEN pattern, each placed in the scope the
    row is enforced over, plus the case that FOUND the row's own defect: an
    `iret` in the ISR is LEGAL (bracket channel) and an `iret` in the census
    range is not."""
    head = 'k3_stream_begin:\n'
    tail = 'k3_stream_end:\n'
    cases = [
        ('csrw mip, x5\n' + head + tail, 'mip write'),
        ('csrw mhpmevent3, x5\n' + head + tail, 'mhpmevent write'),
        ('csrw mtvec, x5\n' + head + tail, 'mtvec MODE != 0'),
        (head + '    iret\n' + tail, 'opcode 0x0b in the census range'),
    ]
    for text, row in cases:
        try:
            isa_model.assert_no_forbidden_text(text)
        except isa_model.ForbiddenEmission as ex:
            ok(row in str(ex), 'the right row fired: %r vs %s' % (row, ex))
        else:
            raise AssertionError('FORBIDDEN row %r did not fire' % row)
    # ...and the legal shape passes: an `iret` OUTSIDE the census range is the
    # CLINT ISR, which the V3 bracket channel excises from the comparison.
    isa_model.assert_no_forbidden_text(head + tail + '\nk3_msip_isr:\n    iret\n')
    # every real stream this generator makes passes, IRQ profile included.
    for prof in ('base', 'seq', 'irq', 'bitm'):
        _b, text = _build(seed=21, profile=prof, length=160)
        isa_model.assert_no_forbidden_text(text)


@test
def test_the_verdict_b_refusal_arm_fires_for_a_real_class():
    """R-K3-2's D-3 recorded that this arm had never fired; R-K4-3 (4) measured
    that no CONFIGURATION could make it fire and named it an emitter question.
    With a class whose knob is verdict B, it fires -- and re-admits exactly that
    class under `allow_unmodelled`, and nothing else."""
    saved = isa_model.KNOB_ORACLE_STATUS['zcmp']
    savedc = dict(isa_model.CLASS_ORACLE)
    try:
        isa_model.KNOB_ORACLE_STATUS['zcmp'] = isa_model.B
        isa_model.CLASS_ORACLE['zcmp'] = isa_model.class_oracle('zcmp')
        cfg = _cfg_knob('zcmp')
        avail, blocked = isa_model.available_classes(cfg.isa)
        hits = [(c, w) for c, w in blocked if 'verdict B' in w]
        eq([c for c, _w in hits], ['zcmp'], 'exactly one class refused')
        ok('zcmp' not in avail, 'and it is not emittable')
        a2, _b2 = isa_model.available_classes(cfg.isa, allow_unmodelled=True)
        eq(sorted(set(a2) - set(avail)), ['zcmp'],
           'the written-permission escape re-admits exactly that class')
    finally:
        isa_model.KNOB_ORACLE_STATUS['zcmp'] = saved
        isa_model.CLASS_ORACLE.clear()
        isa_model.CLASS_ORACLE.update(savedc)


@test
def test_new_classes_declare_their_amendments_and_match_the_comparator():
    """The generator's half of the K2b agreement, checked against the
    comparator's half derived from the SAME resolved config."""
    sys.path.insert(0, os.path.join(randgen.REPO, 'tools', 'cosim'))
    import oracle_isa
    expect = {'zicboz': ['cboz-stores'], 'zcmp': ['zcmp-frame-order'],
              'zcmt': ['cmjt-load'], 'zawrs': [], 'zihint': []}
    for knob, want in sorted(expect.items()):
        cfg = _cfg_knob(knob)
        avail, _bl = isa_model.available_classes(cfg.isa)
        ok(knob in avail, '%s is emittable' % knob)
        eq(isa_model.required_amendments(avail), want,
           'manifest amendments for %s' % knob)
        eq(oracle_isa.derive_amendments(cfg.raw), want,
           'comparator amendments for %s' % knob)
        ne = [k for k, _v, _n in
              isa_model.knobs_on_without_emitter(cfg.isa, cfg.priv)]
        ok(knob not in ne, '%s is no longer an emitter-less knob' % knob)


@test
def test_suite_only_classes_are_named_with_a_reason():
    """`zawrs` and `zihint` are demonstrated on the suite and not on lockstep.
    That is a decision, so it lives in the source with its reason attached
    rather than in a report."""
    eq(sorted(isa_model.SUITE_ONLY_CLASSES), ['zawrs', 'zihint'])
    for c in isa_model.SUITE_ONLY_CLASSES:
        ok(c in isa_model.CLASS_ORDER, '%s is a real class' % c)
        eq(isa_model.CLASS_ORACLE[c], isa_model.A,
           '%s is judgeable -- the screen is a policy, not a verdict' % c)


@test
def test_arch_fragments_follow_the_config_not_the_group_march():
    """The rv32uk group's -march is fixed in verification/isa/Makefile and
    cannot follow a config, so the arch travels inside the stream."""
    for knob, frag in (('zicboz', 'zicboz'), ('zawrs', 'zawrs'),
                       ('zihint', 'zihintpause')):
        cfg = _cfg_knob(knob)
        avail, _bl = isa_model.available_classes(cfg.isa)
        eq(isa_model.arch_fragments(cfg.isa, avail), [frag],
           'arch fragment for %s' % knob)
    # Zcmp/Zcmt have NO gas fragment (measured: `unknown prefixed ISA
    # extension`), so they must contribute none and rely on `.short`.
    for knob in ('zcmp', 'zcmt'):
        cfg = _cfg_knob(knob)
        avail, _bl = isa_model.available_classes(cfg.isa)
        eq(isa_model.arch_fragments(cfg.isa, avail), [],
           '%s contributes no arch fragment' % knob)


@test
def test_default_config_streams_are_unmoved_by_the_new_classes():
    """The five classes are APPENDED to the profile tuples, and every one of
    them is filtered out by `available_classes` on a config whose knob is off --
    so the weight list `weighted_choice` consumes on the DEFAULT config is the
    v1.2.0 one and the emitted BODY cannot move.  Checked against the tracked
    campaign, not asserted."""
    cfg = _cfg()
    idx = json.load(open(os.path.join(randgen.CAMPAIGN_INDEX)))
    for row in idx['streams']:
        _b, text = randgen.build_stream(
            cfg, row['name'], row['seed'], row['profile'],
            row['length_requested'], row['irq_observe'])
        eq(hashlib.sha1(text.encode('utf-8')).hexdigest(), row['asm_sha1'],
           'default-config stream %s reproduces' % row['name'])
    avail, blocked = isa_model.available_classes(cfg.isa)
    for c in ('zicboz', 'zawrs', 'zihint', 'zcmp', 'zcmt'):
        ok(c not in avail, '%s is not emittable on the default config' % c)
        ok(any(n == c and 'knob(s) off' in w for n, w in blocked),
           '%s is blocked for the CONFIG reason, not the oracle one' % c)


def main():
    npass = nfail = 0
    for fn in _RESULTS:
        try:
            fn()
            npass += 1
            print('  ok   %s' % fn.__name__)
        except Exception as e:                                # noqa: BLE001
            nfail += 1
            print('  FAIL %s\n       %s' % (fn.__name__, e))
    print('%d/%d passed' % (npass, npass + nfail))
    return 1 if nfail else 0


if __name__ == '__main__':
    sys.exit(main())
