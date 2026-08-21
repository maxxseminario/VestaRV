#!/usr/bin/env python3
"""Run one of the generator's check_* scripts as a bazel test.

The checks come in two shapes and this runner covers both:

  * Explicit-argument checks (check_mcu_vhd, check_memorymap_vhd,
    check_riscv_tb_vhd, check_memorymap_h, splice_web_data --check). They take
    every path on the command line, so they only need the runfiles tree and,
    for the C-compile check, an absolute RISCV_CC.

  * Layout-derived checks (check_intro_names, check_configurator_sync). They
    derive the repo root from their own __file__ and then read config/,
    out/web/ and docs/ at fixed relative paths. Their inputs are GENERATED and
    therefore live at different paths in bazel-out, so this runner stages the
    pieces into a scratch tree under TEST_TMPDIR that has the layout the script
    expects, and runs the script from there. Nothing is patched and the source
    tree is never written to.

Path tokens: an argument or environment value written as `abs:<path>` is
resolved against the runfiles root and made absolute; `stage:<path>` is
resolved against the staged tree. Bare arguments are passed through untouched
(the test's working directory is the runfiles root, so plain runfiles-relative
paths already work).
"""

import argparse
import os
import shutil
import subprocess
import sys


def _runfilesRoot():
    return os.getcwd()


def _stageOne(src, dst):
    if os.path.isdir(src):
        if os.path.isdir(dst):
            shutil.rmtree(dst)
        shutil.copytree(src, dst)
        for root, _dirs, files in os.walk(dst):
            for name in files:
                os.chmod(os.path.join(root, name), 0o644)
        return
    dstDir = os.path.dirname(dst)
    if dstDir and not os.path.isdir(dstDir):
        os.makedirs(dstDir)
    shutil.copyfile(src, dst)
    os.chmod(dst, 0o644)


def _resolve(token, stageRoot):
    if token.startswith('abs:'):
        return os.path.abspath(os.path.join(_runfilesRoot(), token[4:]))
    if token.startswith('stage:'):
        if stageRoot is None:
            raise SystemExit('check_runner: stage: token used without --stage')
        return os.path.join(stageRoot, token[6:])
    return token


def main(argv):
    parser = argparse.ArgumentParser(fromfile_prefix_chars='@')
    parser.add_argument('--script', required=True,
                        help='the check script; stage-relative when --stage is used, '
                             'runfiles-relative otherwise')
    parser.add_argument('--stage', action='append', default=[],
                        help='SRC=DST, SRC runfiles-relative (file or directory), '
                             'DST relative to the staged tree')
    parser.add_argument('--chdir', default='',
                        help='working directory for the script, resolved like --script')
    parser.add_argument('--env', action='append', default=[],
                        help='NAME=VALUE; VALUE may use the abs:/stage: prefixes')
    parser.add_argument('--expect-exit', type=int, default=0)
    parser.add_argument('args', nargs='*')
    args = parser.parse_args(argv)

    stageRoot = None
    if args.stage:
        base = os.environ.get('TEST_TMPDIR') or os.environ.get('TMPDIR') or '/tmp'
        stageRoot = os.path.join(base, 'checkstage')
        if os.path.isdir(stageRoot):
            shutil.rmtree(stageRoot)
        os.makedirs(stageRoot)
        for spec in args.stage:
            src, dst = spec.split('=', 1)
            _stageOne(os.path.join(_runfilesRoot(), src), os.path.join(stageRoot, dst))

    root = stageRoot if stageRoot is not None else _runfilesRoot()
    scriptPath = os.path.join(root, args.script)
    if not os.path.isfile(scriptPath):
        raise SystemExit('check_runner: script not found: ' + scriptPath)

    cwd = os.path.join(root, args.chdir) if args.chdir else root

    env = {
        'PATH': os.environ.get('PATH', '/usr/bin:/bin'),
        'TMPDIR': os.environ.get('TEST_TMPDIR', os.environ.get('TMPDIR', '/tmp')),
        'HOME': os.environ.get('TEST_TMPDIR', '/tmp'),
        'PYTHONDONTWRITEBYTECODE': '1',
        'PYTHONHASHSEED': '0',
        'PYTHONUTF8': '1',
        'PYTHONIOENCODING': 'utf-8',
        'LC_ALL': 'C.UTF-8',
        'LANG': 'C.UTF-8',
    }
    for spec in args.env:
        name, value = spec.split('=', 1)
        env[name] = _resolve(value, stageRoot)

    scriptArgs = [_resolve(a, stageRoot) for a in args.args]
    cmd = [sys.executable, scriptPath] + scriptArgs
    sys.stdout.write('check_runner: ' + ' '.join(cmd) + '\n')
    sys.stdout.flush()
    rc = subprocess.call(cmd, cwd=cwd, env=env)
    if rc != args.expect_exit:
        sys.stdout.write('check_runner: FAIL (exit %d, expected %d)\n'
                         % (rc, args.expect_exit))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
