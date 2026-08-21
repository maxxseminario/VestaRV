#!/usr/bin/env python3
"""Byte-compare two chip_artifacts output trees.

The generation determinism gate. Two identical chip_artifacts targets run the
generator twice, in two separate staged trees, and every declared artifact must
come out byte-identical. This is what proves the outputs carry no wall-clock
stamp, no dict-ordering wobble and no absolute path from the sandbox.

generate.log is excluded by name: it records the staged tree's own absolute
paths, which differ between the two targets by construction.

Usage: compare_trees.py <treeA> <treeB> [--exclude NAME]...
"""

import os
import sys


def _fileMap(root):
    out = {}
    for dirPath, _dirNames, fileNames in os.walk(root):
        for name in fileNames:
            full = os.path.join(dirPath, name)
            out[os.path.relpath(full, root)] = full
    return out


def main(argv):
    excludes = set(['generate.log'])
    roots = []
    i = 0
    while i < len(argv):
        if argv[i] == '--exclude':
            excludes.add(argv[i + 1])
            i += 2
            continue
        roots.append(argv[i])
        i += 1
    if len(roots) != 2:
        sys.stderr.write('usage: compare_trees.py <treeA> <treeB>\n')
        return 2

    a, b = _fileMap(roots[0]), _fileMap(roots[1])
    keys = set(a) | set(b)
    keys = set(k for k in keys if os.path.basename(k) not in excludes)

    problems = []
    for key in sorted(keys):
        if key not in a:
            problems.append('only in ' + roots[1] + ': ' + key)
            continue
        if key not in b:
            problems.append('only in ' + roots[0] + ': ' + key)
            continue
        with open(a[key], 'rb') as f:
            da = f.read()
        with open(b[key], 'rb') as f:
            db = f.read()
        if da != db:
            problems.append('DIFFERS (%d vs %d bytes): %s' % (len(da), len(db), key))

    print('determinism: compared %d file(s) across two independent generations'
          % len(keys))
    if not keys:
        print('determinism: FAIL - nothing to compare, the trees are empty')
        return 1
    for line in problems[:40]:
        print('  ' + line)
    if len(problems) > 40:
        print('  ... (%d more)' % (len(problems) - 40))
    if problems:
        print('determinism: FAIL - %d difference(s)' % len(problems))
        return 1
    print('determinism: OK - byte-identical')
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
