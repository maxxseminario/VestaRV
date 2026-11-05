"""Drop excluded tests from a RISCOF test_list.yaml, keeping a record of each one.
Run with the riscof environment's python.
Usage: filter_testlist.py <test_list.yaml> <exclusions.txt> [only-glob ...]
Writes <test_list.yaml>.run and <test_list.yaml>.excluded. An only-glob, given for a
partial run, keeps just the matching tests.
"""
import fnmatch
import sys

from riscof.utils import load_yaml, yaml


def rel(path):
    return path.split('rv32i_m/', 1)[1]


def main():
    tl, exc = sys.argv[1:3]
    only = sys.argv[3:]
    rules = []
    for line in open(exc):
        if line.strip() and not line.startswith('#'):
            glob, reason = line.strip().split(None, 1)
            rules.append((glob, reason))
    tests = load_yaml(tl)
    keep = {}
    with open(tl + '.excluded', 'w') as f:
        for name, entry in tests.items():
            hit = [r for g, r in rules if fnmatch.fnmatch(rel(name), g)]
            if hit:
                f.write('%s\t%s\n' % (rel(name), hit[0]))
            elif not only or any(fnmatch.fnmatch(rel(name), g) for g in only):
                keep[name] = entry
    with open(tl + '.run', 'w') as f:
        yaml.dump(keep, f)
    print('selected %d, excluded %d, running %d' % (len(tests),
          sum(1 for _ in open(tl + '.excluded')), len(keep)))


if __name__ == '__main__':
    main()
