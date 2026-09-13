#!/usr/bin/env python3
"""VestaRV: assert a generated artifact set is present, non-empty and well-formed.

For configurations with no identity gate against tracked RTL, where the bar is that the
configuration still generates and its machine-readable outputs still parse; anything ending
in .json is json-loaded. Paths are runfiles-relative, and one ending in '/' must be a
non-empty directory. Usage: assert_artifacts.py <path>...
"""

import json
import os
import sys


def main(argv):
    if not argv:
        sys.stderr.write('assert_artifacts: no paths given\n')
        return 2

    problems = []
    for path in argv:
        if path.endswith('/'):
            if not os.path.isdir(path):
                problems.append('missing directory: ' + path)
            elif not os.listdir(path):
                problems.append('empty directory: ' + path)
            else:
                print('  OK  dir  %-58s (%d entries)'
                      % (path, len(os.listdir(path))))
            continue
        if not os.path.isfile(path):
            problems.append('missing file: ' + path)
            continue
        size = os.path.getsize(path)
        if size == 0:
            problems.append('empty file: ' + path)
            continue
        if path.endswith('.json'):
            try:
                with open(path, encoding='utf-8') as f:
                    json.load(f)
            except Exception as exc:
                problems.append('not valid json: %s (%s)' % (path, exc))
                continue
        print('  OK  file %-58s (%d bytes)' % (path, size))

    for line in problems:
        print('  FAIL ' + line)
    if problems:
        print('assert_artifacts: FAIL - %d problem(s)' % len(problems))
        return 1
    print('assert_artifacts: OK - %d artifact(s)' % len(argv))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
