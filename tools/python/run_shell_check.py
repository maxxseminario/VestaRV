#!/usr/bin/env python3
# coding: utf-8
"""VestaRV: run a POSIX shell checker and propagate its exit code.

    python3 tools/python/run_shell_check.py SCRIPT [ARG...]

Bazel 9 no longer defines sh_test natively and this workspace does not depend on rules_shell,
so a py_test runs the script through this runner. Output is not captured.
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
