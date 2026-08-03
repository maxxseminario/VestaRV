#!/usr/bin/python3.6
# test_oracle_isa.py -- unit tests for the K2 oracle derivation.
#
#   /usr/bin/python3.6 tools/cosim/test_oracle_isa.py
#
# THE LOAD-BEARING TEST is test_default_reproduces_todays_spike_isa: the K2 spec
# requires that the default config derive TODAY'S hardcoded SPIKE_ISA plus
# `_zicntr` AND NOTHING ELSE.  That is what makes acceptance B interpretable --
# if the derivation moved anything besides the one correction, a changed pin
# could not be attributed.
#
# Python 3.6 compatible.  Same style as tools/cosim/test_compare.py (plain
# asserts, one process, no framework).

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
ROOT = os.path.dirname(os.path.dirname(HERE)) if False else os.path.dirname(os.path.dirname(HERE))

import oracle_isa as O                                          # noqa: E402

# The string xrun_cosim.sh has hardcoded since V0. Quoted here so the test fails
# loudly if either side moves.
TODAYS_SPIKE_ISA = 'rv32imac_zicsr_zba_zbb_zbs_zbc'
TODAYS_SPIKE_MEM = '0x8000:0x18000'
TODAYS_BOOT_MEM = '0x0:0x20000'

FAILURES = []
COUNT = [0]


def check(name, cond, detail=''):
    COUNT[0] += 1
    if cond:
        print('  ok    %s' % name)
    else:
        print('  FAIL  %s %s' % (name, detail))
        FAILURES.append(name)


def cfg(isa=None, priv=None):
    """A resolved-config shape with the SHIPPED defaults: the five base-ISA
    knobs true, every X knob and every priv knob false."""
    base = {'mul': True, 'div': True, 'atomics': True, 'compressed': True,
            'bitmanip': True, 'counters': False, 'counters64': False}
    for k in ('zicond', 'zcb', 'zimop', 'zihint', 'zihpm', 'zawrs', 'zabha',
              'zacas', 'zicboz', 'zcmp', 'zcmt', 'zbkb', 'zbkc', 'zbkx', 'zkn',
              'zfinx'):
        base[k] = False
    base.update(isa or {})
    p = {'trapCsr': False, 'umode': False, 'pmp': False, 'pmpEntries': 16}
    p.update(priv or {})
    return {'isa': base, 'priv': p, 'numHarts': 4}


# ---------------------------------------------------------------------------
# THE ACCEPTANCE-B PRECONDITION
# ---------------------------------------------------------------------------
def test_default_reproduces_todays_spike_isa():
    got = O.derive_isa_string(cfg())
    check('default derives exactly today\'s SPIKE_ISA + _zicntr',
          got == TODAYS_SPIKE_ISA + '_zicntr',
          '\n        got:  %s\n        want: %s' % (got, TODAYS_SPIKE_ISA + '_zicntr'))
    # ...and NOTHING ELSE: removing the one correction must give back the
    # hardcoded string character for character.
    check('stripping _zicntr yields the hardcoded string byte for byte',
          got[:-len('_zicntr')] == TODAYS_SPIKE_ISA,
          '(got %r)' % got[:-len('_zicntr')])


def test_zicntr_is_unconditional():
    """isa.counters is a DOCUMENTATION knob -- there is no ENABLE_COUNTERS
    generic in vesta.vhd and the core implements cycle/time/instret always."""
    off = O.derive_isa_string(cfg({'counters': False}))
    on = O.derive_isa_string(cfg({'counters': True}))
    check('_zicntr present with isa.counters FALSE', '_zicntr' in off)
    check('_zicntr present with isa.counters TRUE', '_zicntr' in on)
    check('isa.counters does not change the oracle string at all', off == on)


# ---------------------------------------------------------------------------
# THE MUL/DIV LEVER
# ---------------------------------------------------------------------------
def test_mul_only_uses_zmmul_not_m():
    s = O.derive_isa_string(cfg({'mul': True, 'div': False}))
    check('mul-only emits _zmmul', '_zmmul' in s, '(got %s)' % s)
    check('mul-only does NOT emit a bare `m`', not s.startswith('rv32im'),
          '(got %s)' % s)


def test_mul_and_div_uses_m():
    s = O.derive_isa_string(cfg({'mul': True, 'div': True}))
    check('mul+div emits `m`', s.startswith('rv32im'), '(got %s)' % s)
    check('mul+div does NOT emit _zmmul', '_zmmul' not in s)


def test_neither_mul_nor_div():
    s = O.derive_isa_string(cfg({'mul': False, 'div': False}))
    check('no M at all: neither `m` nor _zmmul',
          not s.startswith('rv32im') and '_zmmul' not in s, '(got %s)' % s)


def test_div_without_mul_is_refused():
    try:
        O.derive_isa_string(cfg({'mul': False, 'div': True}))
        check('div-without-mul raises', False, '(it did not)')
    except O.OracleDerivationError as e:
        check('div-without-mul raises with a reason', 'no Spike lever' in str(e).lower()
              or 'NO Spike lever' in str(e))


# ---------------------------------------------------------------------------
# PRIV AND PMP
# ---------------------------------------------------------------------------
def test_priv_is_m_or_mu_never_msu():
    check('default -> --priv m', O.derive_priv(cfg()) == 'm')
    check('umode   -> --priv mu',
          O.derive_priv(cfg(priv={'trapCsr': True, 'umode': True})) == 'mu')
    # msu sets misa.S, which the RTL never sets. Assert it is unreachable for
    # EVERY combination rather than merely absent from the two above.
    for u in (False, True):
        for p in (False, True):
            got = O.derive_priv(cfg(priv={'trapCsr': True, 'umode': u, 'pmp': p}))
            check('priv is never msu (umode=%s pmp=%s)' % (u, p), got in ('m', 'mu'),
                  '(got %r)' % got)


def test_pmpregions():
    check('no PMP -> 0 regions (matches the RTL bank, which does not exist)',
          O.derive_pmpregions(cfg()) == 0)
    check('PMP 16 -> 16', O.derive_pmpregions(
        cfg(priv={'trapCsr': True, 'umode': True, 'pmp': True, 'pmpEntries': 16})) == 16)
    check('PMP 8 -> 8 (the A3.8 sub-row)', O.derive_pmpregions(
        cfg(priv={'trapCsr': True, 'umode': True, 'pmp': True, 'pmpEntries': 8})) == 8)


# ---------------------------------------------------------------------------
# CROSS-KNOB REFUSALS
# ---------------------------------------------------------------------------
def test_zawrs_requires_atomics():
    try:
        O.derive_isa_string(cfg({'zawrs': True, 'atomics': False}))
        check('zawrs without atomics raises', False, '(it did not)')
    except O.OracleDerivationError:
        check('zawrs without atomics raises', True)
    ok = O.derive_isa_string(cfg({'zawrs': True, 'atomics': True}))
    check('zawrs with atomics emits _zawrs', '_zawrs' in ok)


# ---------------------------------------------------------------------------
# THE X KNOBS -- every one must reach the string, and none may leak
# ---------------------------------------------------------------------------
def test_every_x_knob_changes_the_string():
    base = O.derive_isa_string(cfg())
    knobs = ('zicond', 'zcb', 'zimop', 'zihint', 'zihpm', 'zawrs', 'zabha',
             'zacas', 'zicboz', 'zcmp', 'zcmt', 'zbkb', 'zbkc', 'zbkx', 'zkn',
             'zfinx')
    for k in knobs:
        s = O.derive_isa_string(cfg({k: True}))
        check('isa.%s changes the oracle string' % k, s != base,
              '(unchanged: %s)' % s)


def test_composites():
    check('zihint is TWO extensions',
          '_zihintpause_zihintntl' in O.derive_isa_string(cfg({'zihint': True})))
    check('bitmanip is FOUR extensions',
          '_zba_zbb_zbs_zbc' in O.derive_isa_string(cfg({'bitmanip': True})))
    check('zkn is Zknd+Zkne+Zknh',
          '_zknd_zkne_zknh' in O.derive_isa_string(cfg({'zkn': True})))
    check('composite _zkn only when zbkb+zbkc+zbkx are all on too',
          '_zknd_zkne_zknh_zkn' in O.derive_isa_string(
              cfg({'zkn': True, 'zbkb': True, 'zbkc': True, 'zbkx': True})))
    check('composite _zkn NOT emitted when one of the three is off',
          O.derive_isa_string(cfg({'zkn': True, 'zbkb': True, 'zbkc': True}))
          .endswith('_zknd_zkne_zknh'))
    check('_zcmop only when zimop AND compressed',
          '_zcmop' in O.derive_isa_string(cfg({'zimop': True, 'compressed': True}))
          and '_zcmop' not in O.derive_isa_string(
              cfg({'zimop': True, 'compressed': False})))
    check('_zca_zcb only when zcb AND compressed',
          '_zca_zcb' in O.derive_isa_string(cfg({'zcb': True, 'compressed': True}))
          and '_zca_zcb' not in O.derive_isa_string(
              cfg({'zcb': True, 'compressed': False})))


# ---------------------------------------------------------------------------
# THE MEMORY WINDOWS -- derived, and they must reproduce today's literals
# ---------------------------------------------------------------------------
def test_memory_windows_reproduce_todays_literals():
    hdl = os.path.join(ROOT, 'hdl', 'common')
    if not os.path.isfile(os.path.join(hdl, 'MemoryMap.vhd')):
        print('  skip  memory windows (no %s)' % hdl)
        return
    spike_mem, boot_mem = O.derive_memory(hdl)
    check('SPIKE_MEM derives to today\'s literal', spike_mem == TODAYS_SPIKE_MEM,
          '\n        got:  %s\n        want: %s' % (spike_mem, TODAYS_SPIKE_MEM))
    check('BOOT_MEM derives to today\'s literal', boot_mem == TODAYS_BOOT_MEM,
          '\n        got:  %s\n        want: %s' % (boot_mem, TODAYS_BOOT_MEM))


def test_against_the_real_resolved_config():
    """A LIVE control on the config SHAPE.

    Every test above builds its config from this file's own `cfg()` helper, so
    all of them would still pass if the real ChipConfig.resolved.json used a
    different key layout entirely -- they would be testing the helper, not the
    generator's output. This one reads the file `make generate` actually writes.
    """
    import json
    p = os.path.join(ROOT, 'platform', 'common', 'config', 'ChipConfig.resolved.json')
    if not os.path.isfile(p):
        print('  skip  real resolved config (not present)')
        return
    with open(p) as f:
        real = json.load(f)
    d = O.derive(real, os.path.join(ROOT, 'hdl', 'common'))
    check('real resolved config derives today\'s SPIKE_ISA + _zicntr',
          d['isa'] == TODAYS_SPIKE_ISA + '_zicntr',
          '\n        got:  %s' % d['isa'])
    check('real resolved config -> --priv m', d['priv'] == 'm', '(got %r)' % d['priv'])
    check('real resolved config -> 0 pmpregions', d['pmpregions'] == 0)
    check('real resolved config -> today\'s SPIKE_MEM', d['spike_mem'] == TODAYS_SPIKE_MEM)
    check('real resolved config -> today\'s BOOT_MEM', d['boot_mem'] == TODAYS_BOOT_MEM)
    # And the synthetic helper must AGREE with the real file, or every other
    # test in this module is measuring the wrong thing.
    check('the synthetic cfg() helper agrees with the real resolved config',
          O.derive_isa_string(cfg()) == d['isa'])


def test_sparse_config_is_refused():
    """THE DEFECT THIS GUARD EXISTS FOR, both polarities.

    A `CONFIG=` file is SPARSE. Before the guard, feeding one derived
    `rv32i_zicsr_zicntr_zicboz` from castalia_zicboz.json -- silently trading M,
    A, C and all of Zb for one knob. A divergence from THAT would have looked
    like an RTL bug.
    """
    sparse = {'chipName': 'CastaliaZicboz', 'isa': {'zicboz': True}}
    try:
        O.derive_isa_string(sparse)
        check('a sparse CONFIG= file is refused', False, '(it was accepted)')
    except O.OracleDerivationError as e:
        check('a sparse CONFIG= file is refused', True)
        check('the refusal names the resolved file', 'ChipConfig.resolved.json' in str(e))
    # partially-sparse: has both objects, but one key missing
    part = cfg()
    del part['isa']['zcmt']
    try:
        O.derive_isa_string(part)
        check('one missing isa key is refused', False, '(it was accepted)')
    except O.OracleDerivationError as e:
        check('one missing isa key is refused', 'isa.zcmt' in str(e), '(%s)' % e)
    part2 = cfg()
    del part2['priv']['pmp']
    try:
        O.derive_pmpregions(part2)
        check('one missing priv key is refused', False, '(it was accepted)')
    except O.OracleDerivationError as e:
        check('one missing priv key is refused', 'priv.pmp' in str(e), '(%s)' % e)
    # POSITIVE control: the complete shape is still accepted.
    check('a complete config is still accepted', O.derive_isa_string(cfg()).startswith('rv32imac'))


def test_amendments_are_config_gated():
    """K2b: the comparator amendment set is DERIVED, and the default is EMPTY.

    The default-empty check is the one that matters: it is what keeps the four
    standing gate pins unmoved while the amendments exist in the tree.
    """
    import amend
    check('default config derives NO amendment',
          O.derive_amendments(cfg()) == [])
    check('isa.zfinx derives zfinx-fflags',
          O.derive_amendments(cfg(isa={'zfinx': True})) == ['zfinx-fflags'])
    # Every amendment's gate predicate must name a key the resolved config
    # actually has -- a typo would silently make the amendment underivable,
    # i.e. permanently off, which reads exactly like "it never fires".
    base = cfg()
    for name, pred, _d in amend.AMENDMENTS:
        section, key = pred.split('.', 1)
        check('%s gate %s exists in a resolved config' % (name, pred),
              key in base[section],
              '-- %r is not a resolved-config key' % pred)
        on = cfg(**{section: dict(base[section], **{key: True})})
        check('%s is derived when %s is on' % (name, pred),
              name in O.derive_amendments(on))
    # And the CLI the derivation feeds must accept every name it can emit.
    everything = dict(base['isa'])
    everything.update(dict((k.split('.', 1)[1], True)
                           for (_n, k, _d) in amend.AMENDMENTS
                           if k.startswith('isa.')))
    names = O.derive_amendments(cfg(isa=everything))
    check('every derived name parses in the comparator',
          list(amend.parse_names([','.join(names)])) == names,
          '-- derived %r' % (names,))


def main():
    print('test_oracle_isa: K2 item 4, the oracle derivation')
    for fn in (test_default_reproduces_todays_spike_isa,
               test_zicntr_is_unconditional,
               test_mul_only_uses_zmmul_not_m,
               test_mul_and_div_uses_m,
               test_neither_mul_nor_div,
               test_div_without_mul_is_refused,
               test_priv_is_m_or_mu_never_msu,
               test_pmpregions,
               test_zawrs_requires_atomics,
               test_every_x_knob_changes_the_string,
               test_composites,
               test_memory_windows_reproduce_todays_literals,
               test_against_the_real_resolved_config,
               test_sparse_config_is_refused,
               test_amendments_are_config_gated):
        print('%s:' % fn.__name__)
        fn()
    print('')
    if FAILURES:
        print('test_oracle_isa: %d/%d FAILED: %s'
              % (len(FAILURES), COUNT[0], ', '.join(FAILURES)))
        return 1
    print('test_oracle_isa: OK -- %d/%d checks passed' % (COUNT[0], COUNT[0]))
    return 0


if __name__ == '__main__':
    sys.exit(main())
