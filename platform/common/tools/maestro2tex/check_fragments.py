#!/usr/bin/env python3
"""check_fragments.py -- audit the generated LaTeX chapter against its configs.

maestro2tex rewrites a block's master `.tex` from its config's `order` on every
run, and rewrites every fragment its `figures`/`tables` declare. Nothing else
checks that what is PUBLISHED still matches what would be REGENERATED, and the
two drift apart in three ways that all fail silently:

  1. A generated fragment is superseded by later work the config cannot
     reproduce, replaced by a hand-written file of the same name, and the swap
     is made in the master by hand -- where the next regeneration undoes it.
     (tab_biasgen_dcop: a supply-current corner spread of 0.30 uA against a
     true 17.6 uA, because every imported corner pinned the degeneration
     resistor at typical.)
  2. A fragment named in `order` does not exist, and emit_master skips it
     without a word, so a section quietly loses a table.
  3. A published fragment or intro paragraph is edited by hand; regeneration
     reverts the edit and nobody sees the revert in a diff of the config.

This script reports all three. It reads only; it never writes LaTeX.

    python3 check_fragments.py                    # audit + exit status
    python3 check_fragments.py --outdir DIR       # a different chapter copy
    python3 check_fragments.py --quiet            # errors only

Exit status is 1 if any ERROR was found, 0 otherwise -- so it can gate a build
or a CI step. WARNINGs (a dead generated file left on disk, a hand-written
fragment) do not fail it.

VALUE GUARDS. `guards.json` beside this script lists literal strings that must
not appear anywhere in the published chapter -- the actual wrong numbers, not
the file that carried them. That check survives any config edit, including
deleting the `superseded` key that made maestro2tex itself refuse to write the
fragment: the number cannot come back through any route without failing here.
"""

import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEF_OUT = os.path.normpath(os.path.join(
    HERE, '..', '..', '..', '..', 'implementations', 'asic', 'castalia', 'analog'))
DEF_CFG = os.path.join(HERE, 'configs')

# \input{\MaestroRoot frag.tex}  (a master)  or  \input{include/analog/frag.tex}
# (the chapter file, which reaches the fragments by an explicit path).
INPUT_RE = re.compile(r'\\input\{(?:\\MaestroRoot\s*|[^}]*?/)([A-Za-z0-9_]+)\.tex\}')

ERRORS = []
WARNS = []


def err(msg):
    ERRORS.append(msg)


def warn(msg):
    WARNS.append(msg)


def strip_comments(text):
    """Drop LaTeX comments.

    The generated master's own header carries a commented usage line,
    `%     \\input{include/analog/<Block>.tex}` -- read literally it makes every
    block look as though it inputs itself.
    """
    out = []
    for line in text.split('\n'):
        cut = re.search(r'(?<!\\)%', line)
        out.append(line[:cut.start()] if cut else line)
    return '\n'.join(out)


def inputs_of(path):
    with open(path) as f:
        return INPUT_RE.findall(strip_comments(f.read()))


def load_configs(cfgdir):
    out = {}
    for name in sorted(os.listdir(cfgdir)):
        if not name.endswith('.json') or name == 'guards.json':
            continue
        with open(os.path.join(cfgdir, name)) as f:
            try:
                out[name] = json.load(f)
            except ValueError as e:
                err('%s: not valid JSON (%s)' % (name, e))
    return out


def declared(cfg):
    """Fragment names this config would write."""
    names = set()
    for t in cfg.get('tables', []):
        names.add('tab_%s' % t['id'])
    for f in cfg.get('figures', []):
        names.add('fig_%s' % f['id'])
    if cfg.get('emit_corner_table', True):
        names.add('tab_%s_corners' % re.sub(r'[^A-Za-z0-9]+', '_',
                                            cfg.get('block', 'block')).strip('_'))
    return names


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--outdir', default=DEF_OUT, help='chapter directory to audit')
    ap.add_argument('--configs', default=DEF_CFG, help='maestro2tex config directory')
    ap.add_argument('--quiet', action='store_true', help='print errors only')
    args = ap.parse_args()
    outdir, cfgdir = os.path.abspath(args.outdir), os.path.abspath(args.configs)
    say = (lambda *a: None) if args.quiet else (lambda s='': print(s))

    if not os.path.isdir(outdir):
        sys.stderr.write('check_fragments: no such directory: %s\n' % outdir)
        return 2
    cfgs = load_configs(cfgdir)
    disk = set(n[:-4] for n in os.listdir(outdir) if n.endswith('.tex'))

    # Every fragment the chapter actually reaches, from every .tex in outdir.
    # A fragment only an unreferenced master inputs is not published, so the
    # roots are the files that nothing else inputs -- but scanning all of them
    # and then subtracting is simpler and cannot miss a root.
    reachable, master_inputs = set(), {}
    for n in sorted(disk):
        ins = inputs_of(os.path.join(outdir, n + '.tex'))
        master_inputs[n] = ins
        reachable |= set(ins)

    produced = {}
    for name, cfg in cfgs.items():
        for frag in declared(cfg):
            produced.setdefault(frag, []).append(name)

    # ---- 1. order vs the master on disk -----------------------------------
    say('== config `order` against the master it generates')
    for name, cfg in sorted(cfgs.items()):
        if not cfg.get('emit_master', True):
            continue
        block = cfg.get('block', 'block')
        master = os.path.join(outdir, block + '.tex')
        order = [o for o in cfg.get('order', []) if not o.lstrip().startswith('%')]
        if not os.path.isfile(master):
            err('%s: block master %s.tex is missing from %s' % (name, block, outdir))
            continue
        have = master_inputs.get(block, [])
        if order == have:
            say('   ok        %-34s %2d inputs' % (block + '.tex', len(have)))
            continue
        err('%s: `order` and %s.tex disagree -- a regeneration would rewrite the '
            'published input list' % (name, block))
        for o in order:
            if o not in have:
                err('    in `order`, NOT input by the master: %s' % o)
        for h in have:
            if h not in order:
                err('    input by the master, NOT in `order`: %s' % h)

    # ---- 2. superseded fragments ------------------------------------------
    say()
    say('== superseded fragments')
    any_sup = False
    for name, cfg in sorted(cfgs.items()):
        for frag, why in sorted((cfg.get('superseded') or {}).items()):
            any_sup = True
            say('   %s (%s)' % (frag, name))
            say('      %s' % why)
            if frag in declared(cfg):
                err('%s: superseded %s is still declared in figures/tables'
                    % (name, frag))
            if frag in cfg.get('order', []):
                err('%s: superseded %s is still listed in `order`' % (name, frag))
            if frag in reachable:
                err('%s: superseded %s is INPUT by the published chapter' % (name, frag))
            if frag in disk:
                warn('superseded %s.tex is still on disk (unreferenced); delete it '
                     'so it cannot be mistaken for live output' % frag)
    if not any_sup:
        say('   none declared')

    # ---- 3. value guards ---------------------------------------------------
    say()
    say('== value guards (guards.json)')
    gpath = os.path.join(cfgdir, 'guards.json')
    guards = []
    if os.path.isfile(gpath):
        with open(gpath) as f:
            guards = json.load(f).get('forbidden', [])
    if not guards:
        say('   no guards configured (%s)' % gpath)
    for g in guards:
        pat, why = g['pattern'], g.get('why', '')
        hits = []
        for frag in sorted(reachable | {b for b in disk if b in master_inputs and master_inputs[b]}):
            p = os.path.join(outdir, frag + '.tex')
            if not os.path.isfile(p):
                continue
            with open(p) as f:
                if re.search(pat, f.read()):
                    hits.append(frag)
        if hits:
            err('forbidden value is back in the published chapter (%s): %s\n'
                '       pattern: %s' % (why, ', '.join(hits), pat))
        else:
            say('   ok        %s' % (why or pat))

    # ---- 4. dead, missing and hand-written fragments -----------------------
    say()
    say('== fragment inventory')
    for frag in sorted(produced):
        if frag in disk and frag not in reachable:
            warn('%s.tex is generated by %s but nothing inputs it'
                 % (frag, ', '.join(produced[frag])))
    for name, cfg in sorted(cfgs.items()):
        for o in cfg.get('order', []):
            if o.lstrip().startswith('%'):
                continue
            if o not in disk:
                err('%s: `order` names %s.tex, which does not exist -- '
                    'emit_master skips it silently' % (name, o))
    hand = sorted(f for f in reachable & disk
                  if f not in produced and (f.startswith('tab_') or f.startswith('fig_')))
    say('   hand-written tables/figures published alongside generated ones:')
    for f in hand:
        say('      %s' % f)

    say()
    for w in WARNS:
        say('WARNING: %s' % w)
    for e in ERRORS:
        sys.stderr.write('ERROR: %s\n' % e)
    say('%d error(s), %d warning(s)' % (len(ERRORS), len(WARNS)))
    return 1 if ERRORS else 0


if __name__ == '__main__':
    sys.exit(main())
