#!/usr/bin/python3.6
"""VestaRV: print the hand-defined crosses from a merged.json.

    crosses.py <merged.json>

Rows are the states either hart class reached, so an empty cell is a real zero rather
than a state nobody asked about. PMP is absent: ENABLE_PMP is false on every Castalia
hart, so the roadmap's PMP cross has no bins here.
"""

import json
import sys

AMO_PHASES = ('AMO_READ', 'AMO_WRITEBACK', 'AMO_COMPUTE', 'AMO_WRITE', 'AMO_COMPLETE',
              'LR_READ', 'SC_CHECK')
ARB = ('IDLE', 'LATCH', 'DATA', 'LOCKED')


def two_way(cross, states, title):
    print('\n%s' % title)
    print('%-16s %12s %12s' % ('state', '0', '1'))
    for s in states:
        z = cross.get('%s 0' % s, 0)
        o = cross.get('%s 1' % s, 0)
        print('%-16s %12d %12d' % (s, z, o))


def main():
    d = json.load(open(sys.argv[1]))
    for cls, m in sorted(d['monitor'].items()):
        states = sorted(m['states'])
        print('\n========== class %s, %d tests ==========' % (cls, d['tests']))
        two_way(m['cross']['IRQ'], states, 'cpu_state x irq_save')
        two_way(m['cross']['SH'], states, 'cpu_state x sh_sel (1 = shared window)')
        for key, how in (('ARB', 'sampled on clk_cpu'), ('ARBM', 'sampled on mclk')):
            print('\nAMO phase x arbiter state x grant holder (self/other), %s' % how)
            print('%-16s' % 'phase' + ''.join('%9s/s %7s/o' % (a[:6], a[:6]) for a in ARB))
            arb = m['cross'].get(key, {})
            for s in AMO_PHASES:
                row = '%-16s' % s
                for a in ARB:
                    row += '%11d %9d' % (arb.get('%s %s SELF' % (s, a), 0),
                                         arb.get('%s %s OTHER' % (s, a), 0))
                print(row)
        lock = m['cross']['LOCK']
        print('\namo_lock high by state: %s' %
              {k[:-2]: v for k, v in sorted(lock.items()) if k.endswith(' 1')})


if __name__ == '__main__':
    main()
