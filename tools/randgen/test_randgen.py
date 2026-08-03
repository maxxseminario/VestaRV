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

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.abspath(os.path.dirname(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

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


def _assemble(lines, march='rv32imac_zba_zbb_zbc_zbs'):
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


def _compile_stream(text, march='rv32imac_zba_zbb_zbc_zbs'):
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
    eq(blocked, [], 'nothing blocked on the default-shaped config')


@test
def test_oracle_gate_blocks_verdict_b():
    """A verdict-B knob's class must not reach a stream by default."""
    # zicboz/zcmt/zfinx have no emitter class of their own in v1, so the gate is
    # tested where it is observable: the KNOB table must mark them B, and the
    # generator must name them rather than pass over them.
    for k in ('zicboz', 'zcmt', 'zfinx', 'zihpm', 'trapCsr', 'umode', 'pmp'):
        eq(isa_model.KNOB_ORACLE_STATUS[k], isa_model.B, '%s is verdict B' % k)
    ne = isa_model.knobs_on_without_emitter(_fake_cfg(zicboz=True).isa,
                                            _fake_cfg().priv)
    names = [k for (k, _v, _n) in ne]
    ok('zicboz' in names, 'a knob-on-with-no-emitter is NAMED: %r' % names)


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
    one family k3_spec.md forbids outright -- and it must NOT decode."""
    for w in (0x0000000b, 0x0000100b, 0x0200100b, 0x00000073, 0x0045a00f):
        eq(census.decode(w), None, 'refuses to name 0x%08x' % w)


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
