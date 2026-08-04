#!/usr/bin/python3.6
"""randgen.py -- the K3 constrained-random instruction-stream generator.

    /usr/bin/python3.6 tools/randgen/randgen.py gen --name k3s01 \\
        --seed 1 --profile seq --length 320
    /usr/bin/python3.6 tools/randgen/randgen.py campaign --spec <file>
    /usr/bin/python3.6 tools/randgen/randgen.py verify      # R-DK5 detector
    /usr/bin/python3.6 tools/randgen/randgen.py classes     # what this config
                                                            # can and cannot do

`verify` is the reproducibility detector R-DK5 demands: it regenerates every
campaign stream from its recorded (seed, profile, length, config digest) and
compares the SHA-1 of the `.S`.  It REFUSES rather than reports a mismatch when
the recorded generator version differs from the running one, because a version
bump legitimately changes the bytes and "a stale artifact parses cleanly"
(method rule 6) applies to reproduction checks too.

Never `python3` -- that is Calibre's aoj_cal wrapper, which re-evaluates its
arguments and strips quotes.  Python 3.6 compatible.
"""

import argparse
import hashlib
import json
import os
import sys

_HERE = os.path.abspath(os.path.dirname(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)

import config as k3config                                    # noqa: E402
import emit                                                  # noqa: E402
import isa_model                                             # noqa: E402
import rng as k3rng                                          # noqa: E402
import stream as k3stream                                    # noqa: E402

REPO = os.path.dirname(os.path.dirname(_HERE))
GROUP = 'rv32uk'
DEFAULT_OUT = os.path.join(REPO, 'verification', 'isa', 'tests', GROUP)
CAMPAIGN_DIR = os.path.join(_HERE, 'campaign')
CAMPAIGN_INDEX = os.path.join(CAMPAIGN_DIR, 'campaign.json')

# The rcf filename contract, restated here so the generator refuses a name that
# would only fail much later.  `verify_stage.padded_rcf` raises above 22 chars
# and `flash_prepend.sh` merely WARNS and leaves the name unpadded, at which
# point `xrun_cosim.sh`'s 29-char TEST_FILE check rejects it -- three layers
# downstream of the choice.  Refuse at the source instead.
RCF_NAMELEN = 22


def rcf_basename(name):
    fn = '%s-p-%s.rcf' % (GROUP, name)
    if len(fn) > RCF_NAMELEN:
        raise SystemExit(
            'stream name %r gives rcf basename %r (%d chars), over the '
            '%d-char TEST_FILE contract -- riscv_tb\'s TEST_FILE generic is a '
            'FIXED 29-char string ("../xxx/" + 22).  Max name length for group '
            '%s is %d.'
            % (name, fn, len(fn), RCF_NAMELEN, GROUP,
               RCF_NAMELEN - len('%s-p-.rcf' % GROUP)))
    return 'x' * (RCF_NAMELEN - len(fn)) + fn


NEGCTRL_KINDS = tuple(sorted(k3stream.StreamBuilder.NEGCTRL))


def build_stream(cfg, name, seed, profile, length, irq_observe,
                 allow_unmodelled=False, negctrl=None):
    rng = k3rng.Rng(seed)
    b = k3stream.StreamBuilder(cfg, seed, profile, length, rng,
                               allow_unmodelled=allow_unmodelled,
                               negctrl=negctrl)
    b.build()
    text = emit.render(b, cfg, name, seed, profile, length, irq_observe)
    # K5: the FORBIDDEN table stops being a comment.  Its header claimed this
    # enforcement from K3 onward and the function did not exist; v1.3.0 adds the
    # first emitter that writes a CSR at all, so the claim is made true rather
    # than deleted.  Checked over the WHOLE file, not just the census range --
    # the reference executes the prologue and epilogue too.
    isa_model.assert_no_forbidden_text(text)
    return b, text


def manifest_for(b, cfg, name, seed, profile, length, irq_observe, text):
    counts = b.class_counts()
    return {
        'generator': emit.GENERATOR,
        'version': emit.VERSION,
        'name': name,
        'group': GROUP,
        'rcf': rcf_basename(name),
        'seed': seed,
        'profile': profile,
        'length_requested': length,
        'irq_observe': bool(irq_observe),
        'negctrl': b.negctrl,
        'irq_sites': b.irq_sites,
        'march': emit.required_march(cfg),
        'config': {
            'identity': cfg.identity(),
            'digest': cfg.digest(),
            'chip': cfg.chip,
            'numHarts': cfg.nharts,
            'knobs': cfg.knob_line(),
            'image_defines': cfg.image_defines(),
            'reference': {
                'isa': cfg.oracle_isa_string,
                'priv': cfg.oracle_priv,
                'pmpregions': cfg.oracle_pmpregions,
            },
        },
        'class_counts': counts,
        'total_instructions': sum(counts.values()),
        'blocked_classes': [list(x) for x in b.blocked],
        # K2b: the comparator amendments this stream's classes DEPEND ON. A
        # lockstep run of this stream without them diverges on record SHAPE,
        # which reads exactly like a DUT defect -- so the requirement travels
        # with the stream instead of living in someone's memory.
        'required_amendments': isa_model.required_amendments(b.available),
        'knobs_on_without_emitter': [list(x) for x in b.no_emitter],
        'census_opaque_classes': list(isa_model.CENSUS_OPAQUE_CLASSES),
        'asm_sha1': hashlib.sha1(text.encode('utf-8')).hexdigest(),
    }


def _write(path, text):
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with open(path, 'w') as f:
        f.write(text)


def cmd_gen(a):
    cfg = k3config.load(a.config)
    b, text = build_stream(cfg, a.name, a.seed, a.profile, a.length,
                           not a.no_irq_observe,
                           allow_unmodelled=a.allow_unmodelled,
                           negctrl=a.negctrl)
    man = manifest_for(b, cfg, a.name, a.seed, a.profile, a.length,
                       not a.no_irq_observe, text)
    out = a.out_dir or DEFAULT_OUT
    spath = os.path.join(out, a.name + '.S')
    _write(spath, text)
    mpath = os.path.join(CAMPAIGN_DIR, a.name + '.manifest.json')
    _write(mpath, json.dumps(man, indent=2, sort_keys=True) + '\n')
    print('%s  %d insns  sha1 %s' % (spath, man['total_instructions'],
                                     man['asm_sha1'][:12]))
    print('  manifest %s' % mpath)
    if b.blocked:
        print('  BLOCKED classes (%d):' % len(b.blocked))
        for c, why in b.blocked:
            print('    %-10s %s' % (c, why))
    if b.no_emitter:
        print('  KNOBS ON WITH NO EMITTER (%d) -- a knob-on row whose stream'
              % len(b.no_emitter))
        print('  contains none of that knob\'s encodings covers nothing:')
        for k, v, note in b.no_emitter:
            print('    %-10s oracle verdict %s  (%s)' % (k, v, note))
    return 0


def cmd_campaign(a):
    with open(a.spec) as f:
        spec = json.load(f)
    cfg = k3config.load(a.config)
    out = a.out_dir or DEFAULT_OUT
    rows = []
    for row in spec['streams']:
        name = row['name']
        seed = int(row['seed'])
        profile = row['profile']
        length = int(row['length'])
        obs = bool(row.get('irq_observe', True))
        b, text = build_stream(cfg, name, seed, profile, length, obs)
        man = manifest_for(b, cfg, name, seed, profile, length, obs, text)
        _write(os.path.join(out, name + '.S'), text)
        _write(os.path.join(CAMPAIGN_DIR, name + '.manifest.json'),
               json.dumps(man, indent=2, sort_keys=True) + '\n')
        rows.append(man)
        print('%-8s %-5s len=%-4d insns=%-4d irq=%-2d sha1=%s'
              % (name, profile, length, man['total_instructions'],
                 man['irq_sites'], man['asm_sha1'][:12]))
    index = {
        'generator': emit.GENERATOR,
        'version': emit.VERSION,
        'config': rows[0]['config'] if rows else None,
        'group': GROUP,
        'streams': [{'name': r['name'], 'seed': r['seed'],
                     'profile': r['profile'],
                     'length_requested': r['length_requested'],
                     'irq_observe': r['irq_observe'],
                     'irq_sites': r['irq_sites'],
                     'total_instructions': r['total_instructions'],
                     'rcf': r['rcf'],
                     'asm_sha1': r['asm_sha1']} for r in rows],
    }
    _write(CAMPAIGN_INDEX, json.dumps(index, indent=2, sort_keys=True) + '\n')
    print('campaign index: %s (%d streams)' % (CAMPAIGN_INDEX, len(rows)))
    return 0


def cmd_verify(a):
    """R-DK5: identical inputs must give a byte-identical `.S`."""
    if not os.path.isfile(CAMPAIGN_INDEX):
        raise SystemExit('no campaign index at %s' % CAMPAIGN_INDEX)
    with open(CAMPAIGN_INDEX) as f:
        index = json.load(f)
    if index.get('version') != emit.VERSION:
        raise SystemExit(
            'REFUSED: campaign was generated by %s %s, this is %s %s.\n'
            '  A version bump legitimately changes the emitted bytes, so a '
            'mismatch here would be meaningless.  Regenerate the campaign '
            'deliberately, or check out the matching generator.'
            % (index.get('generator'), index.get('version'),
               emit.GENERATOR, emit.VERSION))
    cfg = k3config.load(a.config)
    want_digest = (index.get('config') or {}).get('digest')
    if want_digest and want_digest != cfg.digest():
        raise SystemExit(
            'REFUSED: campaign was generated against config digest %s, the '
            'resolved config in the tree is %s (%s).\n'
            '  Stage the matching configuration (R-K1-3) before verifying.'
            % (want_digest, cfg.digest(), cfg.identity()))
    out = a.out_dir or DEFAULT_OUT
    bad = 0
    for row in index['streams']:
        name = row['name']
        _b, text = build_stream(cfg, name, row['seed'], row['profile'],
                                row['length_requested'], row['irq_observe'])
        sha = hashlib.sha1(text.encode('utf-8')).hexdigest()
        onfile = None
        p = os.path.join(out, name + '.S')
        if os.path.isfile(p):
            with open(p) as f:
                onfile = hashlib.sha1(f.read().encode('utf-8')).hexdigest()
        ok_rec = (sha == row['asm_sha1'])
        ok_disk = (onfile == row['asm_sha1'])
        status = 'OK' if (ok_rec and ok_disk) else 'MISMATCH'
        if status != 'OK':
            bad += 1
        print('%-8s %s  regen=%s recorded=%s ondisk=%s'
              % (name, status, sha[:12], row['asm_sha1'][:12],
                 (onfile or '<absent>')[:12]))
    print('reproducibility: %d/%d byte-identical'
          % (len(index['streams']) - bad, len(index['streams'])))
    return 1 if bad else 0


def cmd_classes(a):
    cfg = k3config.load(a.config)
    avail, blocked = isa_model.available_classes(
        cfg.isa, allow_unmodelled=a.allow_unmodelled)
    print('config   : %s' % cfg.identity())
    print('reference: --isa %s --priv %s --pmpregions %d'
          % (cfg.oracle_isa_string, cfg.oracle_priv, cfg.oracle_pmpregions))
    print('march    : %s' % emit.required_march(cfg))
    print('')
    print('EMITTABLE classes (%d):' % len(avail))
    for c in avail:
        print('  %-10s [oracle %s] %s'
              % (c, isa_model.CLASS_ORACLE[c], isa_model.CLASS_DESC[c]))
    print('')
    print('BLOCKED classes (%d):' % len(blocked))
    for c, why in blocked:
        print('  %-10s %s' % (c, why))
    req = isa_model.required_amendments(avail)
    print('')
    print('REQUIRED COMPARATOR AMENDMENTS (%d):' % len(req))
    if not req:
        print('  (none -- every emittable class is oracle verdict A or C)')
    for a in req:
        print('  %-14s compare.py --amend %s   [K2b, gated by the same '
              'resolved config]' % (a, a))
    ne = isa_model.knobs_on_without_emitter(cfg.isa, cfg.priv)
    print('')
    print('KNOBS ON WITH NO EMITTER (%d):' % len(ne))
    for k, v, note in ne:
        print('  %-10s oracle verdict %s  (%s)' % (k, v, note))
    print('')
    print('FORBIDDEN BY SPEC, unconditionally:')
    for what, why in isa_model.FORBIDDEN:
        print('  %-34s %s' % (what, why))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--config', default=None,
                    help='resolved config (default: platform/common/config/'
                         'ChipConfig.resolved.json)')
    ap.add_argument('--out-dir', default=None,
                    help='where the .S files go (default: %s)' % DEFAULT_OUT)
    sub = ap.add_subparsers(dest='cmd')

    g = sub.add_parser('gen')
    g.add_argument('--name', required=True)
    g.add_argument('--seed', type=int, required=True)
    g.add_argument('--profile', default='seq',
                   choices=list(k3stream.PROFILE_ORDER))
    g.add_argument('--length', type=int, default=320)
    g.add_argument('--no-irq-observe', action='store_true',
                   help='do NOT assert the handler count in the epilogue. '
                        'Makes an IRQ stream lockstep-eligible (the reference '
                        'never executes the bracketed handler, so its memory '
                        'never sees the count) at the cost of a weaker '
                        'behavioral verdict.')
    g.add_argument('--allow-unmodelled', action='store_true')
    g.add_argument('--negctrl', default=None, choices=list(NEGCTRL_KINDS),
                   help='emit a stream that VIOLATES the discipline on purpose '
                        'so the epilogue guard checks can be seen to fail. '
                        'Never put the result in a standing list.')
    g.set_defaults(func=cmd_gen)

    c = sub.add_parser('campaign')
    c.add_argument('--spec', required=True)
    c.set_defaults(func=cmd_campaign)

    v = sub.add_parser('verify')
    v.set_defaults(func=cmd_verify)

    k = sub.add_parser('classes')
    k.add_argument('--allow-unmodelled', action='store_true')
    k.set_defaults(func=cmd_classes)

    a = ap.parse_args(argv)
    if not getattr(a, 'func', None):
        ap.print_help()
        return 2
    try:
        return a.func(a)
    except (k3config.ConfigError, k3stream.StreamBuildError,
            isa_model.UnmodellableClass) as e:
        sys.stderr.write('randgen: REFUSED\n  %s\n' % e)
        return 2


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
