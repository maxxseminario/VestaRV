#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""run_shell_check.py -- run a POSIX shell checker and propagate its exit code.

    python3 tools/python/run_shell_check.py SCRIPT [ARG...]

WHY THIS EXISTS. The repo's shell-based guards want to be bazel tests, and the
natural rule for that is sh_test. Bazel 9 no longer defines sh_test natively:
it comes from the rules_shell module, which this workspace does not depend on.
Rather than add a module dependency for one rule, a py_test runs the script
through this three-line runner. The contract is identical -- the script's own
exit code is the test's exit code, and its output is not captured, so a failing
guard prints exactly what it always printed.

If rules_shell is ever added to MODULE.bazel, the tests using this runner can
become plain sh_test targets and this file can go.
"""

from __future__ import print_function

import os
import subprocess
import sys


def main(argv):
    if not argv:
        print("run_shell_check: no script named", file=sys.stderr)
        return 2
    script = argv[0]
    if not os.path.isfile(script):
        print("run_shell_check: no such script: " + script, file=sys.stderr)
        return 2
    return subprocess.call(["sh", script] + list(argv[1:]))


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
