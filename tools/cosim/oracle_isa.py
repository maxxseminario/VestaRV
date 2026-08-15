#!/usr/bin/python3.6
# oracle_isa.py -- derive the REFERENCE MODEL's command line from a resolved
# chip configuration.  K2 spec item 4 (K0 harness probe gaps G5+G7).
#
# WHAT THIS IS FOR
# ----------------
# `xrun_cosim.sh` hardcodes the whole reference recipe in four lines:
#
#     SPIKE_ISA="rv32imac_zicsr_zba_zbb_zbs_zbc"
#     SPIKE_MEM="0x8000:0x18000"
#     BOOT_MEM=${BOOT_MEM:-0x0:0x20000}
#     ... --priv m ... --pmpregions=0 (stock spike only)
#
# Not derived, not overridable, and already wrong about the DEFAULT config in
# one respect (`_zicntr`, below).  For a per-config harness every one of those
# is a function of the configuration, so this module makes them one.
#
# TWO BINARIES, AND BOTH ARE FED FROM HERE.  The oracle is `vesta_ref`
# (tools/cosim/vesta_ref.cc on pinned, UNPATCHED libriscv); stock `spike` is the
# identity gate's counterparty.  Anything said here has to hold for both,
# because the identity gate runs them against each other.  NEVER PATCH SPIKE --
# build_vesta_ref.sh asserts a clean tree at a pinned commit and that survives K.
#
# WHY NOT JUST CALL generate.py's `_isaString()`
# ----------------------------------------------
# It is the right SEED and the wrong ANSWER.  It is the chip's DOCUMENTATION
# string -- what the TRM and the configurator advertise -- and the K0 oracle
# probe measured two defects that matter only to a simulator:
#
#   (a) IT OMITS `_zicntr` WHENEVER `isa.counters` IS FALSE, WHICH EVERY SHIPPED
#       CONFIG IS.  Measured on this Spike, both directions:
#           csr 0xC00 (cycle)  rv32imac_zicsr         -> no retire (TRAP)
#           csr 0xC00 (cycle)  rv32imac_zicsr_zicntr  -> x10 0x00000000
#       The RTL admits the FOUR remaining counter CSRs UNCONDITIONALLY
#       (maindec.vhd's `csr_addr_valid` lists CSR_CYCLE/INSTRET(+H) with no
#       ENABLE_ gate; csr_unit.vhd reads them out).  There is NO
#       `ENABLE_COUNTERS` generic in vesta.vhd at all -- generate.py routes
#       `isa.counters` to a legacy picorv32 constant the vesta core never
#       consumes.  So `isa.counters` is a DOCUMENTATION knob, not a hardware
#       knob, and the oracle string must ALWAYS carry `_zicntr`.  Latent today
#       only because no compared instruction in the standing gate reads a
#       counter CSR -- and latent is precisely how F8 survived a year.
#
#       DD11-N1 (2026-08-06) INVERTED HALF OF THIS, and the inversion is
#       DOCUMENTED HERE RATHER THAN FIXED because it cannot be fixed with the
#       levers this Spike has.  `time`/`timeh` (0xC01/0xC81) are no longer
#       KNOWN CSRs in ANY build of either chip -- they raise
#       illegal-instruction, in M-mode and U-mode alike.  So the always-on
#       `_zicntr` is now:
#           RIGHT for cycle/cycleh/instret/instreth -- Spike retires, RTL retires
#           WRONG for time/timeh                    -- Spike RETIRES rdtime,
#                                                      the RTL TRAPS it
#       Zicntr is an all-or-nothing march lever: there is NO Spike knob that
#       models cycle+instret WITHOUT time, so dropping `_zicntr` would trade
#       two wrong CSRs for four.  The always-on form stays because it is the
#       cheaper error.
#       It remains LATENT BY CONSTRUCTION, not by luck: no instruction in
#       `cosim_tests.txt` or `cosim_sh_tests.txt` reads 0xC01/0xC81, and the
#       DD11-N1 blind detector (rv32ua-p-rdtimemp) is TRAP-POISON class, which
#       is INELIGIBLE for either cosim list by construction.  IF A FUTURE TEST
#       EVER READS time/timeh AND ENTERS A COSIM LIST, IT WILL DIVERGE AT THAT
#       INSTRUCTION AND THE ORACLE, NOT THE RTL, IS AT FAULT.  Disposition it
#       here; do not "fix" the RTL to match Spike.
#
#   (b) `if mul or div: s += 'm'`.  A `mul=true, div=false` config therefore
#       derives an --isa in which Spike MODELS DIV while the RTL traps it.  The
#       correct lever is `_zmmul`, which this Spike supports and which models
#       exactly mul-without-div (measured: `rv32iac_zicsr_zmmul` retires mul and
#       traps div, and leaves misa.M CLEAR -- which is also what the RTL does,
#       since csr_unit.vhd sets misa.M from `ENABLE_MUL and ENABLE_DIV`).
#
# `_isaString()` is therefore left alone as the documentation string, and the
# oracle string is derived HERE, with a unit test (test_oracle_isa.py) asserting
# that the default config still reproduces today's SPIKE_ISA modulo `_zicntr`.
#
# Python 3.6 compatible.  Never `python3` (the aoj_cal wrapper strips quotes).

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
    """Refuse anything that is not a RESOLVED config.

    FOUND BY EXERCISING THE CLI ON A SECOND INPUT, and it is exactly the class
    of defect this programme exists to find. A `CONFIG=` file is SPARSE -- it
    lists only the knobs it overrides:

        config/castalia_zicboz.json:  {"chipName": ..., "isa": {"zicboz": true}}

    Fed that, an implementation that reads missing keys as False derived
    `rv32i_zicsr_zicntr_zicboz` -- silently dropping M, A, C and all of Zb from a
    chip that has every one of them. The reference would then have traded a
    whole ISA for a knob, and the DIVERGENCE WOULD HAVE LOOKED LIKE AN RTL BUG.

    The defaults live in generate.py's `_CONFIG_SCHEMA` and are applied when it
    writes `config/ChipConfig.resolved.json`. That file -- and only that file --
    is a legal input here. Rather than duplicate the schema defaults (a second
    place to drift), this refuses: a missing key is an error, never a False.
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
    """`--priv`, which is `m` or `mu` and NEVER `msu`.

    Measured (K0 oracle probe §1.3o):
        csrr a0, misa   --priv m   -> 0x40001105
                        --priv mu  -> 0x40101105   (bit 20 = U)
                        --priv msu -> 0x40141105   (bit 20 = U AND bit 18 = S)
    The RTL sets misa bit 20 from ENABLE_UMODE and NEVER sets bit 18 (S-mode is
    explicitly out of scope, csr_unit.vhd).  `--priv msu` would therefore
    MANUFACTURE a misa divergence out of nothing.  Hard constraint.
    """
    _require(cfg)
    return 'mu' if _priv(cfg)['umode'] else 'm'


def derive_pmpregions(cfg):
    """`--pmpregions`.

    Spike's PMP reset state is NOT zero: it installs a backward-compatibility
    entry `pmpcfg0=0x1f` (L=0, A=TOR, X|W|R) with `pmpaddr0=0xffffffff`, while
    the RTL's bank resets ALL-ZERO with every entry A=OFF (csr_unit.vhd).  On a
    non-PMP config the honest request is therefore ZERO regions -- which also
    happens to be what the identity gate already passes to stock spike, so
    deriving it makes the gate's two sides agree instead of merely looking like
    they do (K0 oracle probe §1.4-3: harmless today, load-bearing the moment a
    PMP config is compared).
    """
    _require(cfg)
    p = _priv(cfg)
    if not p['pmp']:
        return 0
    # pmpEntries is schema-defaulted to 16 and is only meaningful when pmp is on.
    return int(p.get('pmpEntries', 16))


def derive_triggers(cfg):
    """`--triggers` (D1 / DD9-4, 2026-08-05).

    Spike's cfg_t defaults to FOUR hardware triggers, so an un-flagged
    reference carries live tselect/tdata1/tdata2/tinfo CSRs.  This RTL
    implements NONE: 0x7A0-0x7AF is absent from maindec's csr_addr_valid in
    EVERY build and every access raises illegal-instruction, and that stays
    true until D6 adds them.  The reference-side count must match the RTL, so
    the derived answer is 0 -- unconditionally, for now.

    IT IS A FUNCTION, NOT A CONSTANT, ON PURPOSE.  D6 will give the chip a
    trigger count and this is where the config will be read; a literal 0 at the
    call site would be one more place to forget.  It is deliberately NOT keyed
    on `debug.enable`: the debug knob adds the 0x7Bx CSRs and dret, not
    triggers, so a debug-ON chip still has zero of them.
    """
    _require(cfg)
    return 0


def derive_amendments(cfg):
    """The K2b comparator amendments this configuration turns on.

    THE GATE IS THE CONFIG, NOT AN ENVIRONMENT VARIABLE.  Every amendment in
    `amend.AMENDMENTS` carries the resolved-config predicate that owns it
    ('isa.zfinx', 'priv.trapCsr', ...), so the knob -> amendment mapping has
    exactly ONE home and this function is a lookup rather than a second table
    that can drift from the first.  The default Castalia config satisfies none
    of the predicates and therefore derives the EMPTY list -- which is what
    keeps the four standing gate pins unmoved while the amendments exist.

    A suppression that could be switched on by hand, on a config that does not
    ask for it, would be the R-K2-7(2) failure in its purest form: a green cell
    covering nothing, obtained by turning off the thing that was watching.
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
    """Read a `natural` constant (or generic default) out of a VHDL file.

    Same shape as mk_inject.py's reader, deliberately: the A13 rule is that a
    window is DERIVED from the RTL and never hardcoded twice, and two different
    parsers for one constant would be the second place.
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
    """(instances, bound) -- how many hart_tile/orch_tile instances MCU.vhd has,
    and how many BIND the SH_AW generic explicitly.

    CPR8/R7. Same reader, same reason, as mk_inject.py's (the A13 rule keeps
    the two parsers parallel rather than merged; they already were for
    `_vhdl_natural`). The old cross-check demanded MCU.vhd's `constant SH_AW`
    equal hart_tile.vhd's GENERIC DEFAULT. That only ever mattered if the
    default were what the build used -- and it is not: every generated MCU.vhd
    binds `SH_AW => SH_AW` on every hart instance.

    The promotion made this load-bearing. The shipped default is the
    orchestrator chip at SH_AW=16 (memory map v2, flash at 0x40000) while
    `config/castalia4.json` still emits SH_AW=15, and one entity default cannot
    equal both. So: PROVE the binding on every instance (stronger than the
    equality it replaces), and demand equality only when some instance leaves
    the generic unbound -- the one case where the default can reach the RTL.
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
    """(spike_mem, boot_mem) as `base:size` strings, DERIVED from the RTL.

    This is the `PLANT_WIN=auto` pattern applied to the two windows that were
    left hardcoded.  Both are functions of exactly two constants:

        RamStartAddress  (MemoryMap.vhd)  -- the private TCM base
        SH_AW            (MCU.vhd)        -- the shared address space is
                                             [0, 2**(SH_AW+2)) exactly

      BOOT_MEM  = 0 : 2**(SH_AW+2)                  the whole shared space
      SPIKE_MEM = RamStartAddress : 2**(SH_AW+2) - RamStartAddress

    At the default config these reproduce today's literals `0x0:0x20000` and
    `0x8000:0x18000` exactly -- which is what the unit test asserts.  They stop
    agreeing on Argus, and that is the point: the K0 oracle probe measured that
    the hardcoded SPIKE_MEM is SHORT BY 64 KiB for the 128 KiB shared RAM, so
    the literal was already wrong for a shipped configuration.
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
    """The whole reference recipe for one configuration, as a dict.

    `hdl_root` is where MemoryMap.vhd / MCU.vhd / hart_tile.vhd live (the same
    --hdl-root mk_inject takes).  Omit it to derive only the config-side fields.
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
