#!/usr/bin/env python3
"""VestaRV: find an interpreter that can import systemrdl-compiler.

Exists for the Makefile only; the bazel path puts the closure on the child's PYTHONPATH.
Prints the child PYTHONPATH then the interpreter, one per line, preferring this interpreter
if systemrdl already imports and otherwise the hermetic one bazel provisions. Exits 1 when
nothing can import the compiler, rather than generating a chip with the registers missing.
"""

import glob
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WORKSPACE = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))

# The packages the SystemRDL compiler needs at run time, as their import names.
_PACKAGES = ('systemrdl', 'antlr4', 'colorama', 'typing_extensions')


def _canImport(interpreter, pythonPath):
    env = dict(os.environ)
    env.pop('PYTHONPATH', None)
    if pythonPath:
        env['PYTHONPATH'] = pythonPath
    try:
        return subprocess.call([interpreter, '-c', 'import systemrdl'],
                               env=env,
                               stdout=open(os.devnull, 'w'),
                               stderr=subprocess.STDOUT) == 0
    except OSError:
        return False


def _bazelOutputBase():
    bazel = os.path.join(WORKSPACE, 'tools', 'bin', 'bazel')
    if not os.path.isfile(bazel):
        return None
    try:
        out = subprocess.check_output([bazel, 'info', 'output_base'],
                                      cwd=WORKSPACE, stderr=open(os.devnull, 'w'))
    except (OSError, subprocess.CalledProcessError):
        return None
    return out.decode('utf-8', 'replace').strip() or None


def _bazelToolchain():
    """(pythonPath, interpreter) from bazel's own hermetic provisioning, or None. The wheels are
    fetched and extracted by the build, so this finds nothing until //tools/rdl has been built
    once; the caller says so.
    """
    base = _bazelOutputBase()
    if not base:
        return None
    external = os.path.join(base, 'external')
    interp = None
    for cand in sorted(glob.glob(os.path.join(external, '*python_3_1*'))):
        path = os.path.join(cand, 'bin', 'python3')
        if os.path.isfile(path) and os.access(path, os.X_OK):
            interp = path
            break
    if interp is None:
        return None
    dirs = []
    for entry in sorted(glob.glob(os.path.join(external, '*rdl_deps_3*', 'site-packages'))):
        for pkg in _PACKAGES:
            if (os.path.isdir(os.path.join(entry, pkg)) or
                    os.path.isfile(os.path.join(entry, pkg + '.py'))):
                dirs.append(entry)
                break
    if not any(os.path.isdir(os.path.join(d, 'systemrdl')) for d in dirs):
        return None
    return (os.pathsep.join(dirs), interp)


def resolve():
    if _canImport(sys.executable, None):
        return ('', sys.executable)
    found = _bazelToolchain()
    if found and _canImport(found[1], found[0]):
        return found
    sys.stderr.write(
        'rdl_python: no interpreter on this machine can import systemrdl-compiler,\n'
        '  and the chip generator reads hdl/common/regs/rdl/*.rdl for its register\n'
        '  maps. Fetch the pinned wheels once with\n\n'
        '      tools/bin/bazel build //tools/rdl:all\n\n'
        '  or generate through the hermetic action, which carries them itself:\n\n'
        '      tools/bin/bazel build //platform/common:chip_artifacts_castalia\n')
    raise SystemExit(1)


def main(argv):
    pythonPath, interpreter = resolve()
    if '--python' in argv:
        print(interpreter)
    elif '--pythonpath' in argv:
        print(pythonPath)
    else:
        print(pythonPath)
        print(interpreter)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
