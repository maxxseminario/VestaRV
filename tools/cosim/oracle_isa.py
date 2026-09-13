#!/usr/bin/python3.6
# VestaRV: derive the reference model command line from a resolved chip configuration.
#
# Both binaries are fed from here, the oracle vesta_ref and stock spike, so anything said here
# must hold for both; never patch spike. generate.py's _isaString() is the seed, not the answer:
# the oracle string always carries _zicntr, because the RTL admits cycle and instret
# unconditionally, and uses _zmmul for mul-without-div, which leaves misa.M clear as the RTL does.

import json
import os
import re


# The knob -> march-fragment table, in `generate.py::_isaString()`'s EMISSION
# ORDER.  Order is not cosmetic: the derived string is compared against today's
# hardcoded SPIKE_ISA character for character by the unit test, and it is the
# byte stream the identity gate's md5 is taken over.
_X_FRAGMENTS = (
    ('zihpm',  '_zihpm'),
    ('zicond', '_zicond'),
    ('zicboz', '_zicboz'),
    ('zihint', '_zihintpause_zihintntl'),   # ONE knob, TWO extensions
)


class OracleDerivationError(Exception):
    """A configuration the reference model cannot be asked to represent."""


# EVERY isa/priv key the derivation reads. Presence is REQUIRED, not defaulted --
# see _require().
_REQUIRED_ISA = (
    'mul', 'div', 'atomics', 'compressed', 'bitmanip',
    'zicond', 'zcb', 'zimop', 'zihint', 'zihpm', 'zawrs', 'zabha', 'zacas',
    'zicboz', 'zcmp', 'zcmt', 'zbkb', 'zbkc', 'zbkx', 'zkn', 'zfinx',
)
_REQUIRED_PRIV = ('trapCsr', 'umode', 'pmp')


def _require(cfg):
    """Refuse anything that is not a resolved config. A CONFIG= file is sparse, listing only the
    knobs it overrides, and reading missing keys as False trades a whole ISA for a knob while the
    divergence looks like an RTL bug. Rather than duplicate the schema defaults, this refuses.
    """
    isa = cfg.get('isa')
    priv = cfg.get('priv')
    if not isinstance(isa, dict) or not isinstance(priv, dict):
        raise OracleDerivationError(
            'not a resolved config: expected top-level "isa" and "priv" objects. '
            'Pass platform/common/config/ChipConfig.resolved.json (written by '
            '`make generate`), not a sparse CONFIG= file.')
    missing = ([('isa.' + k) for k in _REQUIRED_ISA if k not in isa]
               + [('priv.' + k) for k in _REQUIRED_PRIV if k not in priv])
    if missing:
        raise OracleDerivationError(
            'not a resolved config -- %d key(s) absent: %s%s\n'
            'A CONFIG= file is SPARSE (it lists only its overrides), so a missing '
            'key here would silently read as FALSE and drop whole extensions from '
            'the reference\'s --isa. Pass config/ChipConfig.resolved.json, which '
            '`make generate` writes with every schema default applied.'
            % (len(missing), ', '.join(missing[:6]),
               ' ...' if len(missing) > 6 else ''))


def _isa(cfg):
    return cfg['isa']


def _priv(cfg):
    return cfg['priv']


def derive_isa_string(cfg):
    """The `--isa` string for this configuration, for BOTH binaries."""
    _require(cfg)
    isa = _isa(cfg)
    mul, div = bool(isa.get('mul')), bool(isa.get('div'))

    if div and not mul:
        # No Spike lever exists: `m` gives div AND mul, `_zmmul` gives mul only,
        # and there is no mul-less div extension.  R-DK1 excludes this
        # combination from the supported set in writing; raising here means a
        # config that sneaks in cannot silently be compared against a reference
        # that models an instruction the RTL traps.
        raise OracleDerivationError(
            'isa.div=true with isa.mul=false has NO Spike lever (`m` would model '
            'mul too, `_zmmul` models mul only). R-DK1 excludes this combination '
            'from the supported set; it cannot be lockstepped.')

    s = 'rv32i'
    if mul and div:
        s += 'm'
    if isa.get('atomics'):
        s += 'a'
    if isa.get('compressed'):
        s += 'c'
    # `_zicsr` is EXPLICIT here and absent from _isaString(). The RTL implements
    # the CSR instructions unconditionally, today's SPIKE_ISA carries it, and
    # dropping it would silently change Spike's behaviour -- the K0 inventory
    # probe's §5.5 warning, honoured.
    s += '_zicsr'
    if isa.get('bitmanip'):
        s += '_zba_zbb_zbs_zbc'     # ONE knob, all four Zb extensions
    # ALWAYS. See (a) in the header: the RTL has no counter knob.
    s += '_zicntr'
    if mul and not div:
        s += '_zmmul'               # See (b): NOT 'm'.

    for key, frag in _X_FRAGMENTS:
        if isa.get(key):
            s += frag
    if isa.get('zimop'):
        s += '_zimop'
        if isa.get('compressed'):
            s += '_zcmop'
    if isa.get('zcb') and isa.get('compressed'):
        s += '_zca_zcb'
    if isa.get('zawrs'):
        # The RTL gates `is_wrs_instr` on ENABLE_ZAWRS *and* ENABLE_ATOMICS
        # (maindec.vhd) while Spike's `_zawrs` needs no `a`, so this combination
        # would trap in the DUT and retire in the reference. generate.py raises
        # on it since K1 (d50ef73); this is defence in depth at the other end.
        if not isa.get('atomics'):
            raise OracleDerivationError(
                'isa.zawrs=true with isa.atomics=false: the RTL gates wrs.nto/sto '
                'on ZAWRS *and* ATOMICS, Spike gates it on _zawrs alone -- the '
                'reference would retire what the DUT traps.')
        s += '_zawrs'
    if isa.get('zabha'):
        s += '_zabha'
    if isa.get('zacas'):
        s += '_zacas'
    if isa.get('zcmp'):
        s += '_zcmp'
    if isa.get('zcmt'):
        s += '_zcmt'
    if isa.get('zbkb'):
        s += '_zbkb'
    if isa.get('zbkc'):
        s += '_zbkc'
    if isa.get('zbkx'):
        s += '_zbkx'
    if isa.get('zkn'):
        s += '_zknd_zkne_zknh'
        if isa.get('zbkb') and isa.get('zbkc') and isa.get('zbkx'):
            s += '_zkn'
    if isa.get('zfinx'):
        s += '_zfinx'
    return s


def derive_priv(cfg):
    """`--priv`, which is m or mu and never msu. The RTL sets misa bit 20 from ENABLE_UMODE and never
    sets bit 18, S-mode being out of scope, so --priv msu would manufacture a misa divergence.
    """
    _require(cfg)
    return 'mu' if _priv(cfg)['umode'] else 'm'


def derive_pmpregions(cfg):
    """`--pmpregions`. Spike's PMP reset state is not zero: it installs a compatibility entry with
    A=TOR and X|W|R, while the RTL's bank resets all-zero with every entry off. On a non-PMP
    config the honest request is therefore zero regions, which is also what the identity gate uses.
    """
    _require(cfg)
    p = _priv(cfg)
    if not p['pmp']:
        return 0
    # pmpEntries is schema-defaulted to 16 and is only meaningful when pmp is on.
    return int(p.get('pmpEntries', 16))


def derive_triggers(cfg):
    """`--triggers`. Spike defaults to four hardware triggers; this RTL implements none, 0x7A0-0x7AF
    being absent from csr_addr_valid in every build, so the derived answer is 0. A function rather
    than a constant, and deliberately not keyed on debug.enable, which adds CSRs but no triggers.
    """
    _require(cfg)
    return 0


def derive_amendments(cfg):
    """The comparator amendments this configuration turns on. Every amendment carries the
    resolved-config predicate that owns it, so the knob to amendment mapping has one home and this
    is a lookup. The default config satisfies none of them and derives the empty list.
    """
    _require(cfg)
    import amend                     # same directory; single source of truth
    out = []
    for name, pred, _desc in amend.AMENDMENTS:
        section, key = pred.split('.', 1)
        if cfg[section].get(key):
            out.append(name)
    return out


def _vhdl_natural(path, name, decl='constant'):
    """Read a `natural` constant, or a generic default, out of a VHDL file. Same shape as
    mk_inject.py's reader: a window is derived from the RTL and never hardcoded twice, and two
    different parsers for one constant would be the second place.
    """
    lead = (re.escape(decl) + r'\s+') if decl else r'^\s*'
    pat = re.compile(lead + re.escape(name) +
                     r'\s*:\s*natural\s*:=\s*([0-9_]+|16#[0-9a-fA-F_]+#)\s*[;)]')
    try:
        with open(path) as fh:
            for line in fh:
                m = pat.search(line)
                if m:
                    tok = m.group(1).replace('_', '')
                    if tok.startswith('16#'):
                        return int(tok[3:-1], 16)
                    return int(tok, 10)
    except IOError:
        return None
    return None


def _hart_tile_sh_aw_binding(mcu_path):
    """(instances, bound): how many hart_tile and orch_tile instances MCU.vhd has, and how many bind
    SH_AW explicitly. No entity default can equal both shipped values, so this proves the binding
    on every instance and demands equality only where some instance leaves the generic unbound.
    """
    inst = re.compile(r'entity\s+work\.(?:hart_tile|orch_tile)\b', re.I)
    bind = re.compile(r'\bSH_AW\s*=>')
    endg = re.compile(r'\bport\s+map\b', re.I)
    instances = 0
    bound = 0
    try:
        with open(mcu_path) as fh:
            lines = fh.readlines()
    except IOError:
        return 0, 0
    for i, line in enumerate(lines):
        if not inst.search(line):
            continue
        instances += 1
        for j in range(i + 1, min(i + 200, len(lines))):
            if bind.search(lines[j]):
                bound += 1
                break
            if endg.search(lines[j]):
                break
    return instances, bound


def derive_memory(hdl_root):
    """(spike_mem, boot_mem) as `base:size` strings, derived from RamStartAddress in MemoryMap.vhd
    and SH_AW in MCU.vhd: BOOT_MEM is 0 : 2**(SH_AW+2) and SPIKE_MEM is RamStartAddress up to the
    same top. At the default config these reproduce the old literals, which the unit test asserts.
    """
    mm = os.path.join(hdl_root, 'MemoryMap.vhd')
    mcu = os.path.join(hdl_root, 'MCU.vhd')
    ht = os.path.join(hdl_root, 'hart_tile.vhd')
    ram_start = _vhdl_natural(mm, 'RamStartAddress')
    sh_aw = _vhdl_natural(mcu, 'SH_AW')
    sh_aw_tile = _vhdl_natural(ht, 'SH_AW', decl='')
    missing = [n for n, v in (('RamStartAddress', ram_start), ('SH_AW (MCU.vhd)', sh_aw))
               if v is None]
    if missing:
        raise OracleDerivationError(
            'cannot derive the reference memory windows: %s not found in %s / %s'
            % (', '.join(missing), mm, mcu))
    # Same cross-check mk_inject makes, for the same reason -- and inverted the
    # same way at CPR8/R7: the MCU constant is authoritative WHEN every hart
    # instance binds the generic, so prove that instead. Only an unbound
    # instance can let the entity default reach the RTL.
    _inst, _bound = _hart_tile_sh_aw_binding(mcu)
    if _inst == 0:
        raise OracleDerivationError(
            'no hart_tile/orch_tile instance found in %s -- refusing to guess '
            'how SH_AW reaches the tiles' % mcu)
    if _bound != _inst and sh_aw_tile is not None and sh_aw_tile != sh_aw:
        raise OracleDerivationError(
            '%d of %d hart instances in MCU.vhd leave the SH_AW generic UNBOUND, '
            'and SH_AW disagrees between MCU.vhd (%d) and hart_tile.vhd\'s generic '
            'default (%d) -- refusing to guess which one the build used'
            % (_inst - _bound, _inst, sh_aw, sh_aw_tile))
    top = 1 << (sh_aw + 2)
    if top <= ram_start:
        raise OracleDerivationError(
            'derived reference window is empty (RamStartAddress=0x%x, top=0x%x)'
            % (ram_start, top))
    return ('0x%x:0x%x' % (ram_start, top - ram_start), '0x0:0x%x' % top)


def derive(cfg, hdl_root=None):
    """The whole reference recipe for one configuration, as a dict. `hdl_root` is where
    MemoryMap.vhd, MCU.vhd and hart_tile.vhd live; omit it to derive only the config-side fields.
    """
    out = {
        'isa': derive_isa_string(cfg),
        'priv': derive_priv(cfg),
        'pmpregions': derive_pmpregions(cfg),
        'triggers': derive_triggers(cfg),
        'amendments': derive_amendments(cfg),
    }
    if hdl_root:
        out['spike_mem'], out['boot_mem'] = derive_memory(hdl_root)
    return out


def main(argv):
    import argparse
    import sys
    ap = argparse.ArgumentParser(
        description='Derive the reference-model command line from a resolved '
                    'chip config (K2 item 4).')
    ap.add_argument('config', help='path to ChipConfig.resolved.json (or any '
                                   'config with the same isa/priv shape)')
    ap.add_argument('--hdl-root', default=None,
                    help='where MemoryMap.vhd / MCU.vhd / hart_tile.vhd live, '
                         'to derive SPIKE_MEM and BOOT_MEM')
    ap.add_argument('--shell', action='store_true',
                    help='emit KEY=VALUE lines for a shell to eval')
    a = ap.parse_args(argv)
    with open(a.config) as f:
        cfg = json.load(f)
    try:
        d = derive(cfg, a.hdl_root)
    except OracleDerivationError as e:
        # A clean refusal, not a traceback: this tool's whole job is to be the
        # place where an un-modellable configuration STOPS.
        sys.stderr.write('oracle_isa: REFUSED %s\n  %s\n' % (a.config, e))
        return 2
    if a.shell:
        print('SPIKE_ISA=%s' % d['isa'])
        print('SPIKE_PRIV=%s' % d['priv'])
        print('SPIKE_PMPREGIONS=%d' % d['pmpregions'])
        print('SPIKE_TRIGGERS=%d' % d['triggers'])
        # The comparator's config-gated amendments (K2b). EMPTY on the default
        # config, and the consumer must treat a NON-empty value it cannot honour
        # as a hard failure -- a comparator without --amend would silently run
        # the row with the amendment absent, which reads as a divergence in the
        # DUT rather than as a missing capability.
        print('COMPARE_AMEND=%s' % ','.join(d['amendments']))
        if 'spike_mem' in d:
            print('SPIKE_MEM=%s' % d['spike_mem'])
            print('BOOT_MEM=%s' % d['boot_mem'])
    else:
        print(json.dumps(d, indent=2, sort_keys=True))
    return 0


if __name__ == '__main__':
    import sys
    sys.exit(main(sys.argv[1:]))
