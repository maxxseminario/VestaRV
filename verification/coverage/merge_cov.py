#!/usr/bin/python3.6
"""VestaRV: merge per-test coverage into per-hart-class results.

    merge_cov.py <COV_WORK> [--tag cov[,tag2...]] [--exclude test[,test...]] [--out name]

Reads results/<tag>/<test>.json.gz (ucis_dump.py) and results/<tag>/mon/ (the monitor).
There is no IMC on this host, so the merge is done here: every test ran the one snapshot,
so a coverage item has one key in every database and merging is a sum per key. That is
what `merge -union` does when the models are identical, which they are by construction;
a key seen in one test and not in another would mean they are not, and is counted.

Hart classes: `orch` is hart 0, `tile` is harts 1-4 summed. The classes are separate
because their cores are elaborated differently, so hart 0 has logic the tiles lack.

Writes results/<out>.json and prints the summary tables.
"""

import collections
import glob
import gzip
import json
import os
import re
import sys

CORE_RE = re.compile(r'\.uut\.dut\.hart(\d)(?:\.tile)?\.core(?:\.(.*))?$')
FABRIC_RE = re.compile(r'\.uut\.dut\.(mp_arb0|resv0|mtx0)$')
TILE_RE = re.compile(r'\.uut\.dut\.hart(\d)(?:\.tile)?$')
CLASSES = {'orch': (0,), 'tile': (1, 2, 3, 4)}
FSM_SIG = 'current_state'
BRANCH_RE = re.compile(r'^#(true|false|case|default)#')


def opts(argv):
    o = {'tag': 'cov', 'exclude': '', 'out': 'merged'}
    i = 0
    while i < len(argv):
        o[argv[i].lstrip('-')] = argv[i + 1]
        i += 2
    o['tag'] = o['tag'].split(',')
    o['exclude'] = set(x for x in o['exclude'].split(',') if x)
    return o


def hart_class(h):
    return 'orch' if h == 0 else 'tile'


def tests_of(work, tag):
    for f in sorted(glob.glob(os.path.join(work, 'results', tag, '*.json.gz'))):
        yield os.path.basename(f)[:-len('.json.gz')], f


def add(dst, key, n):
    dst[key] = dst.get(key, 0) + n


def module_of(sub):
    """The last path element, without any generate index."""
    leaf = re.sub(r'\(.*?\)', '', (sub or 'core').split('.')[-1])
    return {'md': 'maindec', 'c_dec_inst': 'c_dec'}.get(leaf, leaf)


def load(work, o):
    # data[hart][subpath][metric][key] = count
    data = collections.defaultdict(lambda: collections.defaultdict(lambda: collections.defaultdict(dict)))
    fabric = collections.defaultdict(lambda: collections.defaultdict(dict))
    hits = {c: {'state': collections.defaultdict(set), 'trans': collections.defaultdict(set)}
            for c in CLASSES}
    ntests = 0
    shape = None
    drift = 0
    for tag in o['tag']:
        for test, f in tests_of(work, tag):
            if test in o['exclude']:
                continue
            ntests += 1
            with gzip.open(f, 'rt') as fh:
                items = json.load(fh)['items']
            sig = sum(len(v) for r in items.values() for v in r.values())
            shape = shape if shape is not None else sig
            drift += sig != shape
            label = '%s/%s' % (tag, test) if len(o['tag']) > 1 else test
            for path, rec in items.items():
                m = CORE_RE.search(path)
                if m:
                    h, sub = int(m.group(1)), m.group(2) or ''
                    for metric, kv in rec.items():
                        dst = data[h][sub][metric]
                        for k, n in kv.items():
                            add(dst, k, n)
                            if n and metric in ('fsm_state', 'fsm_trans') and k.startswith(FSM_SIG + '|'):
                                which = 'state' if metric == 'fsm_state' else 'trans'
                                hits[hart_class(h)][which][k.split('|', 1)[1]].add(label)
                    continue
                m = FABRIC_RE.search(path) or None
                if m:
                    for metric, kv in rec.items():
                        for k, n in kv.items():
                            add(fabric[m.group(1)][metric], k, n)
    return data, fabric, hits, ntests, drift


def summarize(metric_items):
    """(covered, total) per reported metric from one instance's metric dict."""
    out = {}
    for metric, kv in metric_items.items():
        if metric == 'block':
            br = {k: n for k, n in kv.items() if BRANCH_RE.match(k)}
            out['block'] = (sum(1 for n in kv.values() if n), len(kv))
            out['branch'] = (sum(1 for n in br.values() if n), len(br))
        else:
            out[metric] = (sum(1 for n in kv.values() if n), len(kv))
    return out


def class_view(data, cls):
    """Union over the class's harts: an item is hit if any hart of the class hit it."""
    view = collections.defaultdict(lambda: collections.defaultdict(dict))
    for h in CLASSES[cls]:
        for sub, rec in data.get(h, {}).items():
            for metric, kv in rec.items():
                for k, n in kv.items():
                    add(view[sub][metric], k, n)
    return view


def mon_tables(work, o, nharts=5):
    tabs = {h: collections.defaultdict(lambda: collections.Counter()) for h in range(nharts)}
    per_test = collections.defaultdict(lambda: collections.defaultdict(set))
    for tag in o['tag']:
        for f in glob.glob(os.path.join(work, 'results', tag, 'mon', '*.txt.gz')):
            name = os.path.basename(f)
            m = re.match(r'(.*)\.h(\d)\.txt\.gz$', name)
            test, h = m.group(1), int(m.group(2))
            if test in o['exclude']:
                continue
            with gzip.open(f, 'rt') as fh:
                for line in fh:
                    tagf, a, b, c, n = line.split()
                    key = a.upper() if b == '-' else '%s %s %s' % (a.upper(), b.upper().strip("'"), c.upper())
                    key = key.replace(' -', '')
                    tabs[h][tagf][key] += int(n)
                    per_test[hart_class(h)][tagf + ' ' + key].add(test)
    return tabs, per_test


def main():
    work = sys.argv[1]
    o = opts(sys.argv[2:])
    data, fabric, hits, ntests, drift = load(work, o)
    tabs, per_test = mon_tables(work, o)
    out = {'tests': ntests, 'tags': o['tag'], 'excluded': sorted(o['exclude']),
           'model_shape_mismatches': drift, 'classes': {}, 'fabric': {}}
    print('tests merged: %d  (tags %s, excluded %d, model shape mismatches %d)'
          % (ntests, ','.join(o['tag']), len(o['exclude']), drift))
    for cls in CLASSES:
        v = class_view(data, cls)
        core = v.get('', {})
        fs = {k.split('|', 1)[1]: n for k, n in core.get('fsm_state', {}).items()
              if k.startswith(FSM_SIG + '|')}
        ft = {k.split('|', 1)[1]: n for k, n in core.get('fsm_trans', {}).items()
              if k.startswith(FSM_SIG + '|')}
        whole = collections.defaultdict(lambda: [0, 0])
        mods = {}
        for sub, rec in v.items():
            s = summarize(rec)
            mod = module_of(sub)
            mods.setdefault(mod, collections.defaultdict(lambda: [0, 0]))
            for metric, (c, t) in s.items():
                whole[metric][0] += c
                whole[metric][1] += t
                mods[mod][metric][0] += c
                mods[mod][metric][1] += t
        cinfo = {
            'fsm_states_total': len(fs), 'fsm_states_hit': sum(1 for n in fs.values() if n),
            'fsm_trans_total': len(ft), 'fsm_trans_hit': sum(1 for n in ft.values() if n),
            'states_never': sorted(k for k, n in fs.items() if not n),
            'trans_never': sorted(k for k, n in ft.items() if not n),
            'state_counts': fs, 'trans_counts': ft,
            'state_tests': {k: sorted(x) for k, x in hits[cls]['state'].items()},
            'trans_tests': {k: sorted(x) for k, x in hits[cls]['trans'].items()},
            'whole': {k: list(x) for k, x in whole.items()},
            'modules': {m: {k: list(x) for k, x in r.items()} for m, r in mods.items()},
            'never_items': {},
        }
        for sub, rec in v.items():
            if module_of(sub) in ('maindec', 'c_dec'):
                cinfo['never_items'][module_of(sub)] = {
                    metric: sorted(k for k, n in kv.items() if not n) for metric, kv in rec.items()}
        out['classes'][cls] = cinfo
        print('\n=== class %s ===' % cls)
        print('cpu_state states %d/%d, transitions %d/%d'
              % (cinfo['fsm_states_hit'], cinfo['fsm_states_total'],
                 cinfo['fsm_trans_hit'], cinfo['fsm_trans_total']))
        print('states never: %s' % ' '.join(cinfo['states_never']))
        for mod in ('maindec', 'c_dec', 'controller', 'core'):
            if mod in mods:
                print('  %-12s %s' % (mod, {k: tuple(x) for k, x in sorted(mods[mod].items())}))
        print('  whole core   %s' % {k: tuple(x) for k, x in sorted(whole.items())})

    for name, rec in fabric.items():
        out['fabric'][name] = {'summary': {k: list(x) for k, x in summarize(rec).items()},
                               'fsm_state': rec.get('fsm_state', {}),
                               'fsm_trans': rec.get('fsm_trans', {})}
        print('fabric %-8s %s' % (name, summarize(rec)))

    # Two instruments, one question: the tool's FSM counters and the monitor.
    print('\n=== tool vs monitor ===')
    out['monitor'] = {}
    for cls, harts in CLASSES.items():
        st = collections.Counter()
        tr = collections.Counter()
        cross = {k: collections.Counter() for k in ('IRQ', 'SH', 'LOCK', 'ARB', 'ARBM')}
        for h in harts:
            st.update(tabs[h]['ST'])
            tr.update(tabs[h]['TR'])
            for k in cross:
                cross[k].update(tabs[h][k])
        tool_s = {k for k, n in out['classes'][cls]['state_counts'].items() if n}
        tool_t = {k for k, n in out['classes'][cls]['trans_counts'].items() if n}
        tool_all_t = set(out['classes'][cls]['trans_counts'])
        mon_s = set(st)
        mon_t = {k.replace(' ', '->') for k in tr}
        mon_t_moving = {t for t in mon_t if t.split('->')[0] != t.split('->')[1]}
        tool_t_moving = {t for t in tool_t if t.split('->')[0] != t.split('->')[1]}
        print('%s: states tool %d mon %d, only-tool %s only-mon %s'
              % (cls, len(tool_s), len(mon_s), sorted(tool_s - mon_s), sorted(mon_s - tool_s)))
        print('%s: moving transitions tool %d mon %d, only-tool %s, only-mon %s'
              % (cls, len(tool_t_moving), len(mon_t_moving),
                 sorted(tool_t_moving - mon_t_moving), sorted(mon_t_moving - tool_t_moving)))
        print('%s: monitor transitions absent from the tool model: %s'
              % (cls, sorted(mon_t - tool_all_t)))
        out['monitor'][cls] = {
            'states': dict(st), 'trans': dict(tr),
            'cross': {k: dict(v) for k, v in cross.items()},
            'only_tool_states': sorted(tool_s - mon_s), 'only_mon_states': sorted(mon_s - tool_s),
            'only_tool_trans': sorted(tool_t_moving - mon_t_moving),
            'only_mon_trans': sorted(mon_t_moving - tool_t_moving),
            'mon_trans_not_in_model': sorted(mon_t - tool_all_t),
        }
    out['monitor_per_test'] = {c: {k: sorted(v) for k, v in d.items() if len(v) <= 3}
                               for c, d in per_test.items()}
    path = os.path.join(work, 'results', o['out'] + '.json')
    with open(path, 'w') as f:
        json.dump(out, f, indent=1, sort_keys=True)
    print('\nwrote %s' % path)


if __name__ == '__main__':
    main()
