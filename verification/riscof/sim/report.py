#!/usr/bin/python3.6
"""Per-extension, per-test table across RISCOF work dirs.

  report.py <out.md> <label>=<workdir> [<label>=<workdir> ...]

For each test and each run: PASS when the DUT signature is non-empty and equal to
the Spike and the Sail signature. Otherwise the vesta.status word says why, plus
MISMATCH(n) with n differing words. A Spike/Sail disagreement is reported apart:
it means the references, not the DUT, need looking at. Reads files, never logs of
RISCOF itself, so its verdict is checked independently.
"""
import collections
import os
import sys


def sig(path):
    try:
        with open(path) as f:
            return f.read().split()
    except OSError:
        return None


def verdict(tdir):
    dut = sig(os.path.join(tdir, 'dut', 'DUT-vesta.signature'))
    spike = sig(os.path.join(tdir, 'ref', 'spike.signature'))
    sail = sig(os.path.join(tdir, 'ref', 'sail.signature'))
    try:
        status = open(os.path.join(tdir, 'dut', 'vesta.status')).read().strip()
    except OSError:
        status = 'NOT_RUN'
    refnote = ''
    if sail is None:
        refnote = 'nosail'
    elif spike != sail:
        refnote = 'REFDIFF'
    if status != 'SIM_OK' or not dut:
        return status, refnote
    if spike is None or len(dut) != len(spike):
        return 'LEN(%d/%s)' % (len(dut), len(spike) if spike else '-'), refnote
    n = sum(a != b for a, b in zip(dut, spike))
    return ('PASS' if n == 0 else 'MISMATCH(%d)' % n), refnote


def main():
    out = sys.argv[1]
    runs = [a.split('=', 1) for a in sys.argv[2:]]
    table = collections.OrderedDict()
    for label, wd in runs:
        for root, dirs, _ in os.walk(wd):
            for d in dirs:
                if d.endswith('.S') and os.path.exists(os.path.join(root, d, 'ref', 'spike.signature')):
                    ext = os.path.relpath(root, wd).split(os.sep)[0]
                    table.setdefault((ext, d[:-2]), {})[label] = verdict(os.path.join(root, d))
    labels = [l for l, _ in runs]
    with open(out, 'w') as f:
        f.write('| ext | test | ' + ' | '.join(labels) + ' | refs |\n')
        f.write('|---|---|' + '---|' * (len(labels) + 1) + '\n')
        summary = collections.defaultdict(collections.Counter)
        for (ext, t), row in sorted(table.items()):
            cells, notes = [], set()
            for l in labels:
                v = row.get(l)
                cells.append(v[0] if v else '-')
                if v:
                    notes.add(v[1])
                    summary[(ext, l)]['PASS' if v[0] == 'PASS' else 'FAIL'] += 1
            f.write('| %s | %s | %s | %s |\n' % (ext, t, ' | '.join(cells),
                                                 ','.join(sorted(n for n in notes if n)) or 'agree'))
    print('%-12s %s' % ('ext', ' '.join('%-10s' % l for l in labels)))
    for ext in sorted({e for e, _ in summary}):
        print('%-12s %s' % (ext, ' '.join(
            '%-10s' % ('%d/%d' % (summary[(ext, l)]['PASS'],
                                  summary[(ext, l)]['PASS'] + summary[(ext, l)]['FAIL'])) for l in labels)))


if __name__ == '__main__':
    main()
