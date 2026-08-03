#!/usr/bin/python3.6
"""config.py -- the K3 generator's view of a RESOLVED chip configuration.

The refusal is NOT reimplemented here.  `tools/cosim/oracle_isa.py` already
carries the measured argument for why a SPARSE config must be an error rather
than a set of Falses -- it was found by running that CLI on a second input, and
reading missing keys as False derived `rv32i_zicsr_zicntr_zicboz` for a chip
that has M, A, C and all of Zb.  Reusing it here means there is ONE place that
knows what "resolved" means, not two that can drift.

Consequence worth stating: the generator therefore INHERITS oracle_isa's
refusals, including `div=true, mul=false` (no Spike lever, R-DK1 excludes it)
and `zawrs=true, atomics=false` (the RTL gates wrs on ZAWRS *and* ATOMICS while
Spike gates it on `_zawrs` alone).  A config the reference cannot be asked
about is a config K3 must not generate for.

Python 3.6 compatible.
"""

import hashlib
import json
import os
import sys

_HERE = os.path.abspath(os.path.dirname(__file__))
_TOOLS = os.path.dirname(_HERE)
_REPO = os.path.dirname(_TOOLS)

if os.path.join(_TOOLS, 'cosim') not in sys.path:
    sys.path.insert(0, os.path.join(_TOOLS, 'cosim'))

import oracle_isa                                            # noqa: E402

DEFAULT_RESOLVED = os.path.join(
    _REPO, 'platform', 'common', 'config', 'ChipConfig.resolved.json')


class ConfigError(Exception):
    pass


class ResolvedConfig(object):
    """A resolved config plus everything K3 needs to name it in a report line.

    R-DK5: "A finding without its reproduction line (seed + config + generator
    version) is not a finding."  `identity` below IS the config half of that
    line: a stable, human-readable string plus a digest over the exact knob set
    the generator consumed.  It deliberately does NOT digest the whole file --
    `chipName`, package and geometry keys move for reasons that cannot change a
    single emitted instruction, and a digest that moves for those would make
    every reproduction line look stale.
    """

    KEYS_ISA = tuple(sorted(oracle_isa._REQUIRED_ISA))
    KEYS_PRIV = tuple(sorted(oracle_isa._REQUIRED_PRIV))

    def __init__(self, cfg, path=None):
        # The one refusal, borrowed rather than copied.
        try:
            oracle_isa._require(cfg)
        except oracle_isa.OracleDerivationError as e:
            raise ConfigError(str(e))
        self.path = path
        self.raw = cfg
        self.chip = str(cfg.get('chipName', '')).strip() or 'chip'
        self.nharts = int(cfg['numHarts'])
        self.isa = dict(cfg['isa'])
        self.priv = dict(cfg['priv'])
        # Derived reference recipe.  Not used to emit anything -- carried so a
        # report line can state which reference the stream was meant for, and
        # so that an unmodellable config STOPS here rather than at sweep time.
        try:
            self.oracle_isa_string = oracle_isa.derive_isa_string(cfg)
            self.oracle_priv = oracle_isa.derive_priv(cfg)
            self.oracle_pmpregions = oracle_isa.derive_pmpregions(cfg)
        except oracle_isa.OracleDerivationError as e:
            raise ConfigError(
                'this configuration cannot be lockstepped, so K3 will not '
                'generate for it: %s' % e)

    # -- identity ---------------------------------------------------------
    def knob_line(self):
        on_isa = [k for k in self.KEYS_ISA if self.isa.get(k)]
        on_priv = [k for k in self.KEYS_PRIV if self.priv.get(k)]
        return 'isa=%s priv=%s harts=%d' % (
            '+'.join(on_isa) or '(none)',
            '+'.join(on_priv) or '(none)',
            self.nharts)

    def digest(self):
        """SHA1 over the knob set the generator consumes.  hashlib, never
        hash(): Python's str hash is randomised per process (the scar
        `verify_stage.imgset_tag` already carries)."""
        blob = json.dumps(
            {'isa': dict((k, bool(self.isa.get(k))) for k in self.KEYS_ISA),
             'priv': dict((k, bool(self.priv.get(k))) for k in self.KEYS_PRIV),
             'numHarts': self.nharts},
            sort_keys=True, separators=(',', ':'))
        return hashlib.sha1(blob.encode('utf-8')).hexdigest()[:12]

    def identity(self):
        return '%s [%s] cfg=%s' % (self.chip, self.knob_line(), self.digest())

    def image_defines(self):
        """The `-DCORE_ENABLE_*` list images for this config must carry.

        Imported from verify_stage rather than recomputed: K2/G3 made that the
        single source of the software half of the polarity pair, and a second
        copy here is a second thing to drift.
        """
        pc = os.path.join(_REPO, 'platform', 'common', 'python')
        if pc not in sys.path:
            sys.path.insert(0, pc)
        import verify_stage
        return verify_stage.image_defines(self.raw)


def load(path=None):
    path = path or DEFAULT_RESOLVED
    if not os.path.isfile(path):
        raise ConfigError(
            'resolved config not found: %s\n'
            '  K3 consumes config/ChipConfig.resolved.json (written by '
            '`make generate`), never a sparse CONFIG= file.' % path)
    with open(path) as f:
        cfg = json.load(f)
    return ResolvedConfig(cfg, path=path)
