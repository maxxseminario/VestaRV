#!/usr/bin/env python3
"""rdl_python.py -- find an interpreter that can import systemrdl-compiler.

The chip generator reads hdl/common/periph/rdl/*.rdl for its register maps
(tools/rdl/README.md, report R5), so `make generate` needs a Python that can
import `systemrdl`. That is not a given: systemrdl-compiler needs Python 3.8 or
newer and several hosts here carry a 3.6 as /usr/bin/python3, which is why the
generator's own sources stay 3.6-compatible while its toolchain does not.

The bazel path has no such problem -- //platform/common:chip_artifacts_* puts
the closure on the generator subprocess's PYTHONPATH -- so this exists only for
the Makefile. It prints, one per line:

    <PYTHONPATH for the child, possibly empty>
    <interpreter>

and exits 0. It exits 1 with a message on stderr when nothing on the machine can
import the compiler, which is the honest outcome: a generation without the
descriptions would emit a chip with eighteen peripherals' registers missing, and
that must not happen quietly.

Order of preference:
  1. this interpreter, if `systemrdl` already imports (a venv, a pip --user
     install, a newer system python);
  2. the hermetic interpreter and wheels bazel provisions -- the same ones the
     build uses, so the Makefile and the build agree by construction.

Deliberately NOT a pip install: the repo's rule for an external tool is a pinned
version and a pinned artifact hash fetched once (tools/rdl/requirements_lock.txt),
and a Makefile that silently installed packages would route around it.

    python3 rdl_python.py             both lines
    python3 rdl_python.py --python    the interpreter only
    python3 rdl_python.py --pythonpath  the PYTHONPATH only
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
    """(pythonPath, interpreter) from bazel's own hermetic provisioning, or None.

       The wheels are fetched and extracted by the build, so this finds nothing
       until something has built //tools/rdl:all once. The caller says so."""
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
        '  and the chip generator reads hdl/common/periph/rdl/*.rdl for its register\n'
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
